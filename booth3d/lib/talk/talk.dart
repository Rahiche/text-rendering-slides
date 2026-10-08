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
  /// framing (once known), the camera this frame; how high this flight has
  /// to go over the buildings on its way (null: not worked out yet).
  Shot? _from, _to, _cam;
  double? _lift;

  /// A step back (Back, Home, End): a quick flight there, the scene shown
  /// as it ends, the card at once.
  bool _back = false;

  /// A scene's own camera as the talk follows it: eased after it (its
  /// cuts, made for the booth's director, become quick moves).
  vm.Vector3? _liveEye, _liveTarget;
  double _liveFov = 0;

  /// Counts frames while the talk's on (what's pinned to the city follows
  /// the camera).
  final frame = ValueNotifier<int>(0);

  /// The screen blanked (a clicker's blank key), the talk held behind it.
  final blank = ValueNotifier<bool>(false);

  TalkSection get section => sections[_section];
  int get sectionIndex => _section;

  /// The beat on screen, of the section's (for the talk's progress).
  int get beatIndex => _beat;
  TalkBeat get _now => section.beats[_beat];

  /// Whether the beat's card is up yet (a beat may hold it back until the
  /// camera's on its way down).
  bool get cardShown => _on && (_from == null || _back || _age >= _now.cardAt);

  /// Whether the chapter's title is up (a chapter's beat, its card not yet).
  bool get chapter => _on && _now.chapter && !cardShown;
  bool _cardWas = false;

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
      for (var i = 0; i < s.stops.length; i++) ...() {
        final c = s.card(i);
        return [
          c.kicker,
          c.title,
          c.lede,
          for (final f in c.facts)
            switch (f) {
              FactRow(:final label, :final value, :final example) => '$label $value ${example ?? ''}',
              FactTable(:final columns, :final rows) => [...columns, for (final r in rows) ...r].join(' '),
              FactCode(:final code) => code,
              FactLetters(:final label, :final cells) => '$label ${cells.map((c) => '${c.$1} ${c.$2}').join(' ')}',
            },
        ];
      }(),
      for (final b in s.beats)
        for (final p in b.pins) p.name,
    ],
  ].join(' ');

  /// Starts the talk at section [at]'s first stop, the camera flown there
  /// from [from] (where it is).
  void start(PerspectiveCamera from, {int at = 0}) {
    if (_on) return;
    _on = true;
    _section = at.clamp(0, sections.length - 1);
    // (From the top: down out of the sky onto the title.)
    _cam = _section == 0 ? _sky : Shot(from.position.clone(), from.target.clone(), fov: from.fovRadiansY * 180 / math.pi);
    section.enter();
    _go(_section, 0);
  }

  /// Ends the talk: the camera goes back to the director, the world to the
  /// booth.
  void end() {
    if (!_on) return;
    _on = false;
    blank.value = false;
    section.leave();
    director.talkShot = null;
    notifyListeners();
  }

  /// The next beat, flown to (from a section's last, the next section).
  void next() {
    if (!_on) return;
    if (_beat < section.beats.length - 1) {
      _go(_section, _beat + 1);
    } else if (_section < sections.length - 1) {
      _go(_section + 1, 0);
    }
  }

  /// The beat before, as it was left (a quick flight back).
  void back() {
    if (!_on) return;
    if (_beat > 0) {
      _go(_section, _beat - 1, back: true);
    } else if (_section > 0) {
      _go(_section - 1, sections[_section - 1].beats.length - 1, back: true);
    }
  }

  /// This section's first beat, or its last, as left (a quick flight).
  void first() {
    if (_on) _go(_section, 0, back: true);
  }

  void last() {
    if (_on) _go(_section, section.beats.length - 1, back: true);
  }

  /// Section [i]'s first beat, flown to.
  void jump(int i) {
    if (_on && i >= 0 && i < sections.length) _go(i, 0);
  }

  void _go(int s, int b, {bool back = false}) {
    if (s != _section) {
      section.leave();
      _section = s;
      section.enter();
    }
    _beat = b;
    _age = 0;
    _to = null;
    _lift = null;
    _liveEye = _liveTarget = null;
    // From where the camera is now (mid-flight, if it is).
    _from = _cam;
    _back = back;
    section.arrive(b, cut: back);
    notifyListeners();
  }

  /// Advances the talk [dt] seconds (at scene time [t]): the section's
  /// world, the camera. Call before the site's update.
  void update(double t, double dt) {
    _script(t);
    if (!_on) return;
    _age += dt;
    if (cardShown != _cardWas) {
      _cardWas = cardShown;
      notifyListeners();
    }
    section.update(_beat, _age, t, dt);
    final b = _now;
    var to = b.live == null ? _to ??= _framed(b.shot, b.shift, b.pull) : _live(_framed(b.live!(), b.shift, b.pull), dt);
    final from = _from;
    // (A step back: quickly.)
    final u = from == null ? 1.0 : seg(_age, 0, _back ? math.min(b.fly, 1.1) : b.fly);
    if (u >= 1 && b.live == null) {
      // Held: creeping in a little while it's on (a frame that breathes).
      final k = 0.04 * eo(seg(_age - (from == null ? 0 : b.fly), 0, 30));
      to = Shot(to.eye + (to.target - to.eye) * k, to.target, fov: to.fov, settle: to.settle, drift: to.drift);
    }
    _cam = u >= 1 ? to : _between(from!, to, u, _lift ??= _clearance(from.eye, to.eye));
    if (_logCuts) _cutCheck(t, dt);
    director
      ..talkShot = _cam
      ..talkLabel = 'talk ${section.number} ${section.stops[stop]}${beats > 1 ? ' ${beat + 1}' : ''}';
  }

  /// Capture aid (a capture build): a hard cut logged with the beat it's
  /// in — the camera jumping (or turning, or zooming) in one frame several
  /// times as far as it did the frame before (a fast flight speeds up
  /// smoothly; a cut doesn't).
  static const _logCuts = String.fromEnvironment('BOOTH3D_TIMES') != '';
  Shot? _was;
  double _wasMove = 0, _wasTurn = 0;

  void _cutCheck(double t, double dt) {
    final was = _was, now = _cam!;
    _was = now;
    if (was == null || dt <= 0) return;
    final move = (now.eye - was.eye).length;
    final a = (was.target - was.eye).normalized(), b = (now.target - now.eye).normalized();
    final turn = math.acos(a.dot(b).clamp(-1.0, 1.0)) * 180 / math.pi;
    final zoom = (now.fov - was.fov).abs();
    if ((move > 0.8 && move > 4 * _wasMove + 0.4) || (turn > 5 && turn > 4 * _wasTurn + 2) || zoom > 3) {
      debugPrint('CUT t=${t.toStringAsFixed(2)} talk ${section.number} ${section.stops[stop]} beat $_beat age ${_age.toStringAsFixed(2)}: '
          '${move.toStringAsFixed(2)} m (was ${_wasMove.toStringAsFixed(2)}), ${turn.toStringAsFixed(1)}° (was ${_wasTurn.toStringAsFixed(1)}), '
          'fov ${zoom.toStringAsFixed(1)}°${_back ? ' (back)' : ''}');
    }
    _wasMove = move;
    _wasTurn = turn;
  }

  /// [s], a scene's own camera this frame, eased after: within a quarter
  /// second as it moves on, its cuts turned into quick moves.
  Shot _live(Shot s, double dt) {
    final eye = _liveEye, target = _liveTarget;
    if (eye == null || target == null || dt <= 0) {
      _liveEye = s.eye.clone();
      _liveTarget = s.target.clone();
      _liveFov = s.fov;
    } else {
      final k = 1 - math.exp(-dt / 0.25);
      eye.add((s.eye - eye) * k);
      target.add((s.target - target) * k);
      _liveFov += (s.fov - _liveFov) * k;
    }
    return Shot(_liveEye!.clone(), _liveTarget!.clone(), fov: _liveFov, settle: s.settle, drift: s.drift);
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
  /// The lowest a long flight goes, over the park's trees and the scenes'
  /// buildings.
  static const cruise = 16.0;

  /// Where the talk starts from the top: high over the city, from beyond
  /// the avenue.
  static final _sky = Shot(vm.Vector3(0, 150, -230), vm.Vector3(0, 35, 60), fov: 46, drift: 0.6);

  static Shot _framed(Shot shot, double shift, double pull) {
    // (Pulled back from what it looks at, by [pull]: room for all of it.)
    final s = pull == 1 ? shot : Shot(shot.target + (shot.eye - shot.target) * pull, shot.target, fov: shot.fov, settle: shot.settle, drift: shot.drift);
    final f = s.target - s.eye;
    final d = f.length;
    final right = vm.Vector3(0, 1, 0).cross(f)..normalize();
    final slide = shift * d * math.tan(s.fov * math.pi / 360) * 16 / 9;
    final by = right * -slide;
    return Shot(s.eye + by, s.target + by, fov: s.fov, settle: s.settle, drift: s.drift);
  }

  /// The way from [a] to [b], [u] of the way: eased in and out, lifted a
  /// little over a long way; and over buildings in the way, by [over]: up
  /// first, across, then down (a crane's move, never through a wall).
  static Shot _between(Shot a, Shot b, double u, double over) {
    final e = u * u * u * (u * (u * 6 - 15) + 10);
    final eye = a.eye + (b.eye - a.eye) * e;
    final arc = math.min(6.0, 0.12 * (b.eye - a.eye).length) * math.sin(math.pi * e);
    eye.y += math.max(arc, over * smooth(0, 0.3, u) * (1 - smooth(0.7, 1, u)));
    return Shot(eye, a.target + (b.target - a.target) * e, fov: lerp(a.fov, b.fov, e), drift: lerp(a.drift, b.drift, e));
  }

  /// How far above the straight way from [a] to [b] the camera has to go
  /// to clear the buildings under it (and the giant glyphs), with room to
  /// spare; a long way, over the trees and the scenes' buildings too (at
  /// [cruise] at least): 0 when nothing's in the way.
  double _clearance(vm.Vector3 a, vm.Vector3 b) {
    final flat = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z));
    var need = flat > 20 ? cruise - math.min(a.y, b.y) : 0.0;
    const n = 32, room = 3.0;
    for (var i = 1; i < n; i++) {
      final p = a + (b - a) * (i / n);
      for (final (c, h) in director.solids) {
        if ((p.x - c.x).abs() < h.x + room && (p.z - c.z).abs() < h.z + room) {
          need = math.max(need, c.y + h.y + 4 - p.y);
        }
      }
    }
    return need;
  }

  // ── A capture's script ────────────────────────────────────────────────────

  /// Capture aid: --dart-define=BOOTH3D_TALK=05@2,9,15,p20,end@30,… starts
  /// the talk at scene time 2 (at section 05; without it, at the first),
  /// then presses next (or, with p, back; with b, blank; with a section,
  /// jumps there) at each time after.
  static const _scriptDef = String.fromEnvironment('BOOTH3D_TALK');
  static final _presses = [
    for (final s in _scriptDef.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) s,
  ];
  int _pressed = 0;

  /// A section by its number ('end': the last).
  int _sectionAt(String n) => n == 'end' ? sections.length - 1 : math.max(0, sections.indexWhere((s) => s.number == n));

  void _script(double t) {
    while (_pressed < _presses.length) {
      final p = _presses[_pressed];
      final at = p.contains('@') ? p.split('@').first : null;
      final when = double.parse((at == null ? p : p.split('@').last).replaceFirst(RegExp('^[pb]'), ''));
      if (t < when) return;
      if (_pressed == 0) {
        start(director.camera, at: at == null ? 0 : _sectionAt(at));
      } else if (at != null) {
        jump(_sectionAt(at));
      } else if (p.startsWith('b')) {
        blank.value = !blank.value;
      } else if (p.startsWith('p')) {
        back();
      } else {
        next();
      }
      _pressed++;
    }
  }
}
