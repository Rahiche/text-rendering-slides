import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;
import 'package:text_slides/booth/raster.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../world/director.dart';
import '../world/ease.dart';
import '../world/glyph_works.dart';
import '../world/shot.dart';
import '../world/site_letters.dart';
import 'journey_cards.dart';

/// 05 · One word's journey, told in the city instead of on slides: each
/// press of the clicker flies the camera to the next stop of the word's way
/// through Flutter, where the city shows it, and a card beside it says what
/// happens there, with the word's real values.
///
/// The stops are the Glyph Works' (glyph_works.dart): the word's first
/// letter is taken down the line a step at a time, the camera following
/// (the rest of the word shaped with it in the stick, and drawn with it
/// onto the board). Before them, the city from above and the works from
/// outside: the map, the widget, the string.
///
/// The works runs on the talk's own clock: a stop plays its step once the
/// camera's nearly there, then holds (the maker stays at the step, idling,
/// as long as the presenter talks). Back goes straight to the stop before,
/// as it was left. The booth carries on round it all: names are built on
/// the plaza, the crowd walks by.
class JourneyTalk extends ChangeNotifier {
  JourneyTalk(this.works, this.director);

  final GlyphWorks works;
  final Director director;

  /// The word on its way (the deck's journey word).
  static const word = 'Flutter';

  bool get on => _on;
  bool _on = false;

  /// The beat on screen (a stop has one or two), how long it's been on,
  /// and the clock the works runs on.
  int _beat = 0;
  double _age = 0, _clock = 0;

  /// The camera when the beat started (flown from there), and the beat's
  /// own framing (once known); the camera this frame.
  Shot? _from, _to;
  Shot? _cam;

  /// The word's letters being got ready (capture waits on it).
  Future<void>? pending;

  /// Counts frames while the talk's on (what's pinned to the city follows
  /// the camera).
  final frame = ValueNotifier<int>(0);

  /// What's pinned to the city at this beat — where, and its name
  /// (Japanese, English) — and how far it's shown (0..1): from above, the
  /// works, where the word's way runs.
  List<(vm.Vector3, String, String)> get pins => _on && _beat == 0 ? _mapPins : const [];
  double get pinsShown {
    if (!_on || _beat != 0) return 0;
    final from = _from == null ? 0.0 : _beats[0].fly * 0.85;
    return seg(_age, from, from + 0.6);
  }

  static final _mapPins = [(vm.Vector3(-12.55, 3.3, 6.2), '文字工場', 'GLYPH WORKS')];

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

  /// The stop on screen (0 the map … 10 the draw), how many there are, and
  /// its card.
  int get stop => _beats[_beat].stop;
  int get stops => journeyStops.length;
  JourneyCard get card => journeyCards(word, works.talkName, works.latin)[stop];

  /// The beat within the stop, and how many it has.
  int get beat => _beat - _beats.indexWhere((b) => b.stop == stop);
  int get beats => _beats.where((b) => b.stop == stop).length;

  /// Starts the talk at its first stop, the camera flown there from [from]
  /// (where it is).
  void start(PerspectiveCamera from) {
    if (_on) return;
    _on = true;
    _beat = 0;
    _age = 0;
    _clock = 0;
    _from = Shot(from.position.clone(), from.target.clone(), fov: from.fovRadiansY * 180 / math.pi);
    _to = null;
    _cam = _from;
    pending = NameRaster.of(word).then((r) async {
      if (!_on) return;
      works.planTalk(word, NameLetters.of(r));
      notifyListeners();
      // (The cards' values: the word's fonts looked up, its pixels.)
      await works.pending;
      pending = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Ends the talk: the works goes back to the site, the camera to the
  /// director.
  void end() {
    if (!_on) return;
    _on = false;
    works.endTalk();
    director.talkShot = null;
    pending = null;
    notifyListeners();
  }

  /// The next beat: flown to, its step played.
  void next() {
    if (!_on || _beat >= _beats.length - 1) return;
    _go(_beat + 1, fly: true);
  }

  /// The beat before, as it was left (a cut).
  void back() {
    if (!_on || _beat == 0) return;
    _go(_beat - 1, fly: false);
  }

  /// The first stop, or the last, as left (a cut).
  void first() {
    if (_on) _go(0, fly: false);
  }

  void last() {
    if (_on) _go(_beats.length - 1, fly: false);
  }

  void _go(int b, {required bool fly}) {
    final was = _beat;
    _beat = b;
    _age = 0;
    _to = null;
    if (fly) {
      // From where the camera is now (mid-flight, if it is).
      _from = _cam;
    } else {
      _from = null;
      // As it was left: the works at the beat's end.
      if (works.talk case final tk?) _clock = _until(b, tk);
    }
    if (b != was) notifyListeners();
  }

  /// The works' clock at the end of beat [b] (as the last that sets it
  /// left it).
  static double _until(int b, WorksTalk tk) {
    for (var i = b; i >= 0; i--) {
      if (_beats[i].until(tk) case final u?) return u;
    }
    return 0;
  }

  /// Advances the talk [dt] seconds (at scene time [t]): the works' clock,
  /// the camera. Call before the site's update.
  void update(double t, double dt) {
    _script(t);
    if (!_on) return;
    final b = _beats[_beat];
    _age += dt;
    final tk = works.talk;
    if (tk != null) {
      // Catch up with the beat before, quickly, if it was cut short; then,
      // once the camera's nearly there, play this beat's part.
      final before = _beat == 0 ? 0.0 : _until(_beat - 1, tk), until = _until(_beat, tk);
      if (_clock < before - 1e-6) {
        _clock = math.min(before, _clock + 3 * dt);
      } else if (_age >= b.fly * b.lag) {
        _clock = math.min(until, _clock + dt);
      }
    }
    works.talkTime = _clock;
    final to = _to ??= _framed(b.shot, b.shift);
    final from = _from;
    final u = from == null ? 1.0 : seg(_age, 0, b.fly);
    _cam = u >= 1 ? to : _between(from!, to, u);
    director
      ..talkShot = _cam
      ..talkLabel = 'talk ${journeyStops[b.stop]}${beats > 1 ? ' ${beat + 1}' : ''}';
  }

  /// After the director's update (the camera this frame is known).
  void framed() {
    if (_on) frame.value++;
  }

  /// The works' caption for the beat (after the site's update, which clears
  /// it).
  void caption() {
    if (!_on) return;
    final b = _beats[_beat];
    if (b.step < 0) return;
    final from = _from == null ? 0.0 : b.fly * 0.75;
    works.talkCaption(b.step, seg(_age, from, from + 0.5));
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

  /// Capture aid: --dart-define=BOOTH3D_TALK=2,9,15,p20,… starts the talk at
  /// scene time 2, then presses next (or, with p, back) at each time after.
  static const _scriptDef = String.fromEnvironment('BOOTH3D_TALK');
  static final _presses = [
    for (final s in _scriptDef.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) (s.startsWith('p'), double.parse(s.replaceFirst('p', ''))),
  ];
  int _pressed = 0;

  void _script(double t) {
    while (_pressed < _presses.length && t >= _presses[_pressed].$2) {
      final (isBack, _) = _presses[_pressed];
      if (_pressed == 0) {
        start(director.camera);
      } else if (isBack) {
        back();
      } else {
        next();
      }
      _pressed++;
    }
  }
}

/// One beat of the talk: its stop, the camera's framing, the works' clock
/// at its end (null: as the beat before left it), the step the works'
/// caption gives (−1: none), how long the camera takes to get there, and
/// when (of that) the works starts.
class _Beat {
  const _Beat(this.stop, this.shot, this.until, {this.step = -1, this.fly = 2.0, this.lag = 0.7, this.shift = 0.3});

  final int stop;
  final Shot shot;
  final double? Function(WorksTalk tk) until;
  final int step;
  final double fly, lag;

  /// How far right of the middle what it looks at is (of the half width).
  final double shift;
}

double? _hold(WorksTalk tk) => null;

Shot _shot(double ex, double ey, double ez, double tx, double ty, double tz, double fov, {double drift = 0.35}) =>
    Shot(vm.Vector3(ex, ey, ez), vm.Vector3(tx, ty, tz), fov: fov, drift: drift);

final _beats = <_Beat>[
  // The map: the city from above, the plaza and the works.
  _Beat(0, _shot(-2, 44, -36, -7, 0, 4, 46, drift: 1.0), (tk) => 0, fly: 3.2, shift: 0.24),
  // Text(): the works from outside, its sign; the maker walks in.
  _Beat(1, _shot(-11.2, 2.6, 0.2, -12.4, 1.8, 6.0, 50, drift: 0.5), (tk) => tk.at[0] - 0.9, fly: 3.4, lag: 0.55),
  // A Dart String: the string's board over the feeder.
  _Beat(2, _shot(-14.2, 1.75, 4.7, -15.0, 1.45, 7.6, 40), _hold, fly: 2.4),
  // Into the engine: the bytes out of the feeder.
  _Beat(3, GlyphWorks.stepShot(0), (tk) => tk.end[0] - 0.05, step: 0, fly: 1.8),
  // Unicode analysis: into the decoder, the code point out.
  _Beat(4, _shot(-14.75, 1.6, 4.25, -15.15, 0.95, 6.4, 44), (tk) => tk.end[1] - 0.05, step: 1, fly: 1.6),
  // Find the glyphs: the font cases.
  _Beat(5, GlyphWorks.stepShot(2), (tk) => tk.end[2] - 0.05, step: 2, fly: 1.8),
  // Shape: onto the stick, the rest of the word after it.
  _Beat(6, GlyphWorks.stepShot(3), (tk) => tk.set + 0.25, step: 3, fly: 1.8),
  // Lay out: the line measured.
  _Beat(7, _shot(-13.0, 1.32, 4.7, -13.12, 0.86, 6.3, 36), (tk) => tk.line.$2 + 0.1, fly: 1.6),
  // Record: down the rest of the line, still to come.
  _Beat(8, _shot(-13.9, 2.3, 4.0, -10.6, 0.75, 5.7, 46), (tk) => tk.at[4] - 0.25, fly: 2.0),
  // Rasterize: the outline bent, then scanned into pixels.
  _Beat(9, GlyphWorks.stepShot(4), (tk) => tk.end[4] - 0.05, step: 4, fly: 2.0),
  _Beat(9, GlyphWorks.stepShot(5), (tk) => tk.end[5] - 0.05, step: 5, fly: 1.6),
  // Draw: onto the board, the rest of the word with it; the whole board.
  _Beat(10, GlyphWorks.stepShot(6), (tk) => tk.home + 0.3, step: 6, fly: 2.0),
  _Beat(10, _shot(-9.85, 1.5, 3.25, -9.85, 0.8, 5.12, 38), _hold, fly: 2.2),
];
