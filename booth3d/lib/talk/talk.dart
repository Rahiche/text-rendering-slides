import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:vector_math/vector_math.dart' as vm;

import '../world/director.dart';
import '../world/ease.dart';
import '../world/shot.dart';
import 'talk_section.dart';

/// The talk, told in the city instead of on slides: each press of the
/// clicker flies the camera to the next stop of a section (the deck's
/// sections, in order), where the city shows it, and a card beside it says
/// what happens there.
///
/// Sections (talk_section.dart) bring their stops, the camera's beats, the
/// cards and what they do to the world while they're on. Next goes on to
/// the next beat, from a section's last beat to the next section; back cuts
/// to the beat before, as it was left. The booth carries on round it all:
/// names are built on the plaza, the crowd walks by.
class Talk extends ChangeNotifier {
  Talk(this.director, this.sections);

  final Director director;
  final List<TalkSection> sections;

  bool get on => _on;
  bool _on = false;

  /// The section and the beat (of its beats) on screen, how long it's been
  /// on.
  int _section = 0, _beat = 0;
  double _age = 0;

  /// The camera when the beat started (flown from there), the beat's own
  /// framing (once known), the camera this frame.
  Shot? _from, _to, _cam;

  /// Counts frames while the talk's on (what's pinned to the city follows
  /// the camera).
  final frame = ValueNotifier<int>(0);

  TalkSection get section => sections[_section];
  int get sectionIndex => _section;
  TalkBeat get _now => section.beats[_beat];

  /// The stop on screen (of [section]'s), its card, and the beat within it
  /// (of how many).
  int get stop => _now.stop;
  TalkCard get card => section.card(stop);
  int get beat => _beat - section.beats.indexWhere((b) => b.stop == stop);
  int get beats => section.beats.where((b) => b.stop == stop).length;

  /// Got ready (the capture waits for it).
  Future<void>? get pending => _on ? section.pending : null;

  /// Every word the talk's cards and pins show (the web's fonts for them
  /// fetched before it starts, not as tofu halfway through).
  String get allText => [
    for (final s in sections) ...[
      s.title,
      s.ja,
      for (var i = 0; i < s.stops.length; i++) ...() {
        final c = s.card(i);
        return [
          c.ja,
          c.title,
          c.lede,
          for (final f in c.facts)
            switch (f) {
              FactRow(:final label, :final value) => '$label $value',
              FactCode(:final code) => code,
              FactLetters(:final label, :final cells) => '$label ${cells.map((c) => '${c.$1} ${c.$2}').join(' ')}',
            },
        ];
      }(),
      for (final b in s.beats)
        for (final p in b.pins) '${p.ja} ${p.en}',
    ],
  ].join(' ');

  /// Starts the talk at section [at]'s first stop, the camera flown there
  /// from [from] (where it is).
  void start(PerspectiveCamera from, {int at = 0}) {
    if (_on) return;
    _on = true;
    _section = at.clamp(0, sections.length - 1);
    _cam = Shot(from.position.clone(), from.target.clone(), fov: from.fovRadiansY * 180 / math.pi);
    section.enter();
    _go(_section, 0, fly: true);
  }

  /// Ends the talk: the camera goes back to the director, the world to the
  /// booth.
  void end() {
    if (!_on) return;
    _on = false;
    section.leave();
    director.talkShot = null;
    notifyListeners();
  }

  /// The next beat, flown to (from a section's last, the next section).
  void next() {
    if (!_on) return;
    if (_beat < section.beats.length - 1) {
      _go(_section, _beat + 1, fly: true);
    } else if (_section < sections.length - 1) {
      _go(_section + 1, 0, fly: true);
    }
  }

  /// The beat before, as it was left (a cut).
  void back() {
    if (!_on) return;
    if (_beat > 0) {
      _go(_section, _beat - 1, fly: false);
    } else if (_section > 0) {
      _go(_section - 1, sections[_section - 1].beats.length - 1, fly: false);
    }
  }

  /// This section's first beat, or its last, as left (a cut).
  void first() {
    if (_on) _go(_section, 0, fly: false);
  }

  void last() {
    if (_on) _go(_section, section.beats.length - 1, fly: false);
  }

  /// Section [i]'s first beat, flown to.
  void jump(int i) {
    if (_on && i >= 0 && i < sections.length) _go(i, 0, fly: true);
  }

  void _go(int s, int b, {required bool fly}) {
    if (s != _section) {
      section.leave();
      _section = s;
      section.enter();
    }
    _beat = b;
    _age = 0;
    _to = null;
    // From where the camera is now (mid-flight, if it is); or a cut.
    _from = fly ? _cam : null;
    section.arrive(b, cut: !fly);
    notifyListeners();
  }

  /// Advances the talk [dt] seconds (at scene time [t]): the section's
  /// world, the camera. Call before the site's update.
  void update(double t, double dt) {
    _script(t);
    if (!_on) return;
    _age += dt;
    section.update(_beat, _age, t, dt);
    final b = _now;
    final to = b.live == null ? _to ??= _framed(b.shot, b.shift) : _framed(b.live!(), b.shift);
    final from = _from;
    final u = from == null ? 1.0 : seg(_age, 0, b.fly);
    _cam = u >= 1 ? to : _between(from!, to, u);
    director
      ..talkShot = _cam
      ..talkLabel = 'talk ${section.number} ${section.stops[stop]}${beats > 1 ? ' ${beat + 1}' : ''}';
  }

  /// After the site's update (the captions it clears).
  void caption() {
    if (_on) section.caption(_beat, _age);
  }

  /// After the director's update (the camera this frame is known).
  void framed() {
    if (_on) frame.value++;
  }

  /// What's named in the city now, and how far it's shown (0..1): once
  /// the camera's (nearly) there.
  List<TalkPin> get pins => _on ? _now.pins : const [];
  double get pinsShown {
    if (!_on) return 0;
    final from = _from == null ? 0.0 : _now.fly * 0.85;
    return seg(_age, from, from + 0.6);
  }

  /// Where [p] is on the canvas (1600×900) through the camera this frame;
  /// null behind it.
  Offset? project(vm.Vector3 p) {
    final cam = director.camera;
    final f = (cam.target - cam.position)..normalize();
    final right = vm.Vector3(0, 1, 0).cross(f)..normalize();
    final up = f.cross(right);
    final d = p - cam.position;
    final z = d.dot(f);
    if (z < 0.1) return null;
    final ty = math.tan(cam.fovRadiansY / 2), tx = ty * 16 / 9;
    return Offset((0.5 + 0.5 * d.dot(right) / (z * tx)) * 1600, (0.5 - 0.5 * d.dot(up) / (z * ty)) * 900);
  }

  /// [s] with what it looks at moved right of the middle by [shift] of the
  /// half width (the card's on the left): the camera slid left, square to
  /// its view.
  static Shot _framed(Shot s, double shift) {
    final f = s.target - s.eye;
    final d = f.length;
    final right = vm.Vector3(0, 1, 0).cross(f)..normalize();
    final slide = shift * d * math.tan(s.fov * math.pi / 360) * 16 / 9;
    final by = right * -slide;
    return Shot(s.eye + by, s.target + by, fov: s.fov, settle: s.settle, drift: s.drift);
  }

  /// The way from [a] to [b], [u] of the way: eased in and out, lifted a
  /// little over a long way (not through what's between).
  static Shot _between(Shot a, Shot b, double u) {
    final e = u * u * u * (u * (u * 6 - 15) + 10);
    final eye = a.eye + (b.eye - a.eye) * e;
    final lift = math.min(6.0, 0.12 * (b.eye - a.eye).length);
    eye.y += lift * math.sin(math.pi * e);
    return Shot(eye, a.target + (b.target - a.target) * e, fov: lerp(a.fov, b.fov, e), drift: lerp(a.drift, b.drift, e));
  }

  // ── A capture's script ────────────────────────────────────────────────────

  /// Capture aid: --dart-define=BOOTH3D_TALK=05@2,9,15,p20,… starts the talk
  /// at scene time 2 (at section 05; without it, at the first), then
  /// presses next (or, with p, back) at each time after.
  static const _scriptDef = String.fromEnvironment('BOOTH3D_TALK');
  static final _presses = [
    for (final s in _scriptDef.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) s,
  ];
  int _pressed = 0;

  void _script(double t) {
    while (_pressed < _presses.length) {
      final p = _presses[_pressed];
      final at = p.contains('@') ? p.split('@').first : null;
      final when = double.parse((at == null ? p : p.split('@').last).replaceFirst('p', ''));
      if (t < when) return;
      if (_pressed == 0) {
        start(director.camera, at: at == null ? 0 : math.max(0, sections.indexWhere((s) => s.number == at)));
      } else if (p.startsWith('p')) {
        back();
      } else {
        next();
      }
      _pressed++;
    }
  }
}
