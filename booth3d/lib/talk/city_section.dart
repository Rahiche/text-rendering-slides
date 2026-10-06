import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../world/script_alley.dart';
import '../world/site_fx.dart' show Fx3D;
import '../world/shot.dart';
import '../world/vignette.dart';
import 'talk_section.dart';

/// A beat of a city section: where the camera goes. A framing ([at]); or a
/// scene's own camera as it plays ([scene]: from [from] seconds into its
/// turn, held [hold] seconds in while the presenter talks, else on round);
/// or a Script Alley stall's ([stall]), its letters played and held.
class CityBeat {
  CityBeat.at(Shot this.shot, {this.fly = 2.2, this.shift = 0.3, this.pins = const [], this.cardAt = 0, this.fireworks = false, this.chapter = false})
    : scene = null,
      stall = null,
      from = 0,
      hold = null;

  CityBeat.scene(String this.scene, {this.hold, this.from = 0, this.fly = 2.2, this.shift = 0.3, this.pins = const []})
    : shot = null,
      stall = null,
      cardAt = 0,
      fireworks = false,
      chapter = false;

  CityBeat.stall(int this.stall, {this.fly = 2.0, this.shift = 0.3})
    : shot = Shot(
        AlleyLayout.toWorld(stall, _stallEye),
        AlleyLayout.toWorld(stall, _stallTarget),
        fov: 40,
        drift: 0.4,
      ),
      scene = null,
      from = 0,
      hold = null,
      pins = const [],
      cardAt = 0,
      fireworks = false,
      chapter = false;

  final Shot? shot;
  final String? scene;
  final int? stall;
  final double from;
  final double? hold;
  final double fly, shift;
  final List<TalkPin> pins;

  /// Seconds before the card comes up (flown to); fireworks over the plaza
  /// while it's on.
  final double cardAt;
  final bool fireworks;

  /// Opens the section (its title large in the middle first).
  final bool chapter;

  /// A stall from the path, as the build's visits see it.
  static final _stallEye = vm.Vector3(0.85, 1.72, -4.0), _stallTarget = vm.Vector3(0.05, 1.42, -0.1);
}

/// A stop: its short name (the way along the bottom), its card, its beats.
class CityStop {
  CityStop(this.name, this.card, this.beats);
  final String name;
  final TalkCard card;
  final List<CityBeat> beats;
}

/// A section told with the city as it is: a place a beat, the scene there
/// called on to play as the camera gets there (and held on how it ends
/// while the presenter talks), let go again after; cut to (back, a jump),
/// held on how it ends at once.
class CitySection extends TalkSection {
  CitySection({
    required this.number,
    required this.title,
    required this.ja,
    required this.cityStops,
    required this.vignettes,
    required this.alley,
    this.fx,
    this.glyphShapes,
    this.glyphs = const [],
  }) {
    for (final (i, s) in cityStops.indexed) {
      for (final b in s.beats) {
        _plan.add(b);
        _beats.add(
          TalkBeat(
            i,
            b.shot ?? _nowhere,
            fly: b.fly,
            shift: b.shift,
            pins: b.pins,
            live: b.scene == null ? null : () => _live(b),
            cardAt: b.cardAt,
            chapter: b.chapter,
          ),
        );
      }
    }
  }

  @override
  final String number, title, ja;
  @override
  final List<String> glyphs;
  final List<CityStop> cityStops;
  final Vignettes vignettes;
  final ScriptAlley alley;

  /// For a finale's fireworks: the effects, and glyphs to burst in.
  final Fx3D? fx;
  final List<List<vm.Vector2>> Function()? glyphShapes;

  final _plan = <CityBeat>[];
  final _beats = <TalkBeat>[];

  @override
  List<String> get stops => [for (final s in cityStops) s.name];
  @override
  List<TalkBeat> get beats => _beats;
  @override
  TalkCard card(int stop) => cityStops[stop].card;

  /// The beat just come to (set up at the next update, when the time's
  /// known), and whether it was cut to; scene time now; the scene and the
  /// stall called on.
  int _arrived = -1;
  bool _cut = false;
  double _t = 0;
  String? _scene;
  int? _stall;

  @override
  void arrive(int beat, {required bool cut}) {
    _arrived = beat;
    _cut = cut;
  }

  @override
  void leave() {
    _letGo(scene: true, stall: true);
    _arrived = -1;
  }

  @override
  void update(int beat, double age, double t, double dt) {
    _t = t;
    if (_arrived != beat) return;
    _arrived = -1;
    final b = _plan[beat];
    // When it plays: once the camera's (nearly) there; cut to, how it
    // ends at once.
    if (b.scene case final name?) {
      if (name != _scene) _letGo(scene: true);
      _letGo(stall: true);
      final at = _cut ? t - ((b.hold ?? b.from) - b.from) : t + b.fly * 0.7;
      vignettes.play(name, at, from: b.from, hold: b.hold);
      _scene = name;
    } else if (b.stall case final i?) {
      if (i != _stall) _letGo(stall: true);
      _letGo(scene: true);
      alley.play(i, _cut ? t - 7.2 : t + b.fly * 0.7);
      _stall = i;
    } else {
      _letGo(scene: true, stall: true);
    }
  }

  void _letGo({bool scene = false, bool stall = false}) {
    if (scene && _scene != null) {
      vignettes.release();
      _scene = null;
    }
    if (stall && _stall != null) {
      alley.release();
      _stall = null;
    }
  }

  @override
  void caption(int beat, double age) {
    final b = _plan[beat], fx = this.fx;
    if (!b.fireworks || fx == null) return;
    // Fireworks over the plaza, one show after another, once it's there.
    final u = age - b.fly * 0.8;
    // (High and wide: over the title in the middle, not behind it.)
    if (u >= 0) fx.fireworks(u % 11.6, 22, 11, 3, const [], glyphShapes?.call() ?? const []);
  }

  /// A scene beat's camera now: the scene's own, where it's got to (held
  /// with it).
  Shot _live(CityBeat b) {
    final v = vignettes.byName(b.scene!);
    if (v == null) return _nowhere;
    final u = (_scene == b.scene ? vignettes.playedAt(_t) : null) ?? b.from;
    return Vignettes.shotOf(v, b.hold == null ? u : math.min(u, v.visit));
  }

  static final _nowhere = talkShot(0, 30, -40, 0, 0, 0, 50);
}
