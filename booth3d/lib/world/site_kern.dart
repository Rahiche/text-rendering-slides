import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_fx.dart';
import 'site_geo.dart';
import 'site_plan.dart';

/// What the kerning caption (the 2D overlay's lower third) shows, refreshed
/// every frame by the site.
class KernCaption {
  /// 0 hidden … 1 fully in.
  double show = 0;

  /// The pair (left, right) and the font's kerning for it, in em.
  String left = '', right = '';
  double em = 0;

  /// 0..1: the value counting up, and the right letter sliding into place.
  double count = 0, push = 0;

  /// A full close-up (vs a quick check).
  bool full = false;
}

/// The kerning step's props: a low steel skid under each letter (the
/// letter slides on it), and the measuring tape (blade, ticks, hook, case)
/// stretched across the gap — all small boxes in one instanced draw. Also
/// the dust of the push and the tap, and the caption's data.
class Kern3D {
  Kern3D(this.scene);

  final Scene scene;

  static const _max = 112;
  late final InstancedMesh _parts;
  late final Node _node;
  int _n = 0, _hi = 0;

  final caption = KernCaption();

  void init() {
    _parts = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(rgb(1, 1, 1), roughness: 0.42, metallic: 0.3));
    for (var i = 0; i < _max; i++) {
      _parts.addInstance(hidden);
    }
    _node = Node(name: 'kerning props')
      ..addComponent(InstancedMeshComponent(_parts))
      ..castsShadows = false
      ..visible = false;
    scene.add(_node);
  }

  final _m = vm.Matrix4.identity();
  static final _qi = vm.Quaternion.identity();
  static final _steel = lin(const Color(0xFF2A2F37)), _stripe = lin(const Color(0xFFFFC23D));
  static final _blade = lin(const Color(0xFFFFD84A)), _tick = lin(const Color(0xFF1A2230)), _case = lin(const Color(0xFFFF8A3D));

  /// Light dust: thin enough to see the letter through.
  static final _dust = vm.Vector4(1, 1, 1, 0.32);

  void _box(double x, double y, double z, double sx, double sy, double sz, vm.Vector4 c) {
    if (_n >= _max || sx <= 0 || sy <= 0 || sz <= 0) return;
    _parts.setInstanceTransform(_n, setTqs(_m, x, y, z, _qi, sx, sy, sz));
    _parts.setInstanceColor(_n, c);
    _n++;
  }

  /// Poses the props for [j]'s build at [t] ([skidGone]: when, in the
  /// finish, the plaster covers each letter's foot and its skid goes),
  /// puffs the dust into [fx] and fills [caption].
  void update(BuildPlan? plan, Job j, double t, Fx3D fx, {double Function(int letter)? skidGone}) {
    _n = 0;
    caption.show = 0;
    final building = j.phase == Phase.intake || j.phase == Phase.build;
    if (plan != null && (building || (j.phase == Phase.reveal && j.cutAt == null))) {
      _skids(plan, t, building ? null : skidGone);
      final st = building ? plan.stepAt(t) : null;
      if (st != null) _tape(plan, st, t, fx);
    }
    for (var i = _n; i < _hi; i++) {
      _parts.setInstanceTransform(i, hidden);
    }
    _hi = _n;
    _node.visible = _n > 0;
  }

  /// A steel skid under each letter from just before its first brick.
  void _skids(BuildPlan plan, double t, double Function(int letter)? gone) {
    final b = plan.b, half = plan.width / 2;
    for (var k = 0; k < plan.letterCount; k++) {
      final first = plan.layAt(plan.letterStart[k]);
      final pop = c01((t - first + 0.9) / 0.35);
      if (pop <= 0) break;
      final l = plan.letters.letters[k];
      final y = l.row0 * b - 0.03;
      if (gone != null && t >= gone(k)) continue;
      final x0 = l.col0 * b - half - 0.12, x1 = (l.col1 + 1) * b - half + 0.12;
      final off = plan.offsetAt(k, t), s = eo(pop);
      final cx = (x0 + x1) / 2 + off, w = (x1 - x0) * s;
      _box(cx, y, 0, w, 0.06 * s, b * 1.2, _steel);
      for (final e in const [-1.0, 1.0]) {
        _box(cx + e * (w / 2 - 0.035), y + 0.005, 0, 0.07 * s, 0.075 * s, b * 1.26, _stripe);
      }
    }
  }

  /// The tape across the gap, the push's dust and the final tap.
  void _tape(BuildPlan plan, KernStep st, double t, Fx3D fx) {
    final b = plan.b;
    final off = st.offset(t);
    final y = st.tapeY, z = b * 0.5 + 0.035;
    // The case sits in the gap against the new letter's edge; the blade
    // runs out from it to the hook on the letter before.
    final caseX = st.gapR + off - 0.075;
    final out = eio(seg(t, st.tapeA, st.tapeB));
    final back = seg(t, st.tapB, st.retractB);
    final hookX = back > 0 ? lerp(st.gapL, caseX, back * back) : lerp(caseX, st.gapL, out);
    final caseOn = c01((t - st.tapeA + 0.3) / 0.25) * (1 - seg(t, st.retractB + 0.05, st.retractB + 0.3));
    if (caseOn > 0) {
      final s = eo(caseOn);
      _box(caseX, y, z, 0.13 * s, 0.13 * s, 0.06 * s, _case);
      _box(caseX, y, z - 0.031 * s, 0.07 * s, 0.07 * s, 0.004, _tick);
    }
    final len = caseX - 0.065 - hookX;
    if (t >= st.tapeA && t < st.retractB && len > 0.01) {
      _box(hookX + len / 2, y, z, len, 0.034, 0.006, _blade);
      _box(hookX - 0.006, y - 0.004, z, 0.012, 0.05, 0.03, _tick);
      // Ticks every 10 cm from the hook (zero) end, bigger every 50.
      for (var i = 1; i * 0.1 < len - 0.01 && i <= 40; i++) {
        final major = i % 5 == 0;
        _box(hookX + i * 0.1, y + (major ? 0.004 : 0.009), z - 0.004, 0.007, major ? 0.024 : 0.014, 0.004, _tick);
      }
    }
    // Dust from the skid as the letter is heaved along, and at the tap.
    final l = plan.letters.letters[st.letter];
    final foot = l.row0 * b;
    final left = l.col0 * b - plan.width / 2;
    for (var p = 0; p < 4; p++) {
      final at = st.pushA + (st.pushB - st.pushA) * (p + 0.15) / 4;
      final age = (t - at) / 0.8;
      if (age < 0 || age >= 1) continue;
      final o = st.offset(at);
      fx.puff(left + o - 0.08, foot, -0.05, age, 0.12 + 0.25 * b, seed: st.letter * 11 + p, n: 2, tint: _dust);
      fx.puff(st.pushX + o + 0.05, foot, 0.1, age, 0.1 + 0.2 * b, seed: st.letter * 13 + p, n: 1, tint: _dust);
    }
    final strike = tapAt(st);
    final age = (t - strike) / 0.55;
    if (age >= 0 && age < 1) fx.puff(st.pushX + 0.02, st.pushY, 0.05, age, 0.16, seed: st.letter * 17, n: 3, tint: _dust);
    // The caption: in once the tape is out, out once it's back.
    caption
      ..show = seg(t, st.tapeB - 0.35, st.tapeB + 0.15) * (1 - seg(t, st.retractB, st.e + 0.35))
      ..left = st.left
      ..right = st.right
      ..em = st.em
      ..count = seg(t, st.tapeB, st.tapeB + (st.full ? 0.9 : 0.5))
      ..push = seg(t, st.pushA, st.pushB)
      ..full = st.full;
  }

  /// When the pusher's hand comes down on the letter (the final tap).
  static double tapAt(KernStep st) => st.pushB + (st.tapB - st.pushB) * 0.55;

  /// Where the hook's end of the tape is at [t]: (x, out?) for the crew.
  static double hookAt(KernStep st, double t) {
    final caseX = st.gapR + st.offset(t) - 0.075;
    final back = seg(t, st.tapB, st.retractB);
    return back > 0 ? lerp(st.gapL, caseX, back * back) : lerp(caseX, st.gapL, eio(seg(t, st.tapeA, st.tapeB)));
  }

  /// A camera close-up of step [st] at [t] and how much of the frame it
  /// wants (0..1): low, at the builders' height, slightly to the side; on
  /// the tape while it's measured, widening to take in the push.
  static (vm.Vector3 eye, vm.Vector3 target, double fov, double weight) shot(KernStep st, double t) {
    final ease = st.full ? 1.1 : 0.7;
    final w = seg(t, st.a - ease, st.a + ease * 0.6) * (1 - seg(t, st.retractB - 0.1, st.e + 0.6));
    final gapMid = (st.gapL + st.gapR + st.slide) / 2;
    final measure = math.max(st.gapR + st.slide - st.gapL + 2.6, 3.6);
    final pushL = st.gapL - 0.4, pushR = st.pushX + st.slide * 0.5 + 1.1;
    final f = eio(seg(t, st.checkB - 0.4, st.pushA + 0.2));
    final cx = lerp(gapMid, (pushL + pushR) / 2, f);
    final span = lerp(measure, pushR - pushL, f);
    final side = st.letter.isEven ? 1.0 : -1.0;
    final fov = st.full ? 30.0 : 36.0;
    // Horizontal half-angle at 16:9.
    final th = math.tan(fov * math.pi / 360) * 16 / 9;
    final dist = math.max(3.2, span / (2 * th) * 1.12) * (st.full ? 1 : 1.25);
    final tg = vm.Vector3(cx, st.tapeY + 0.05, 0.15);
    final a = (st.full ? 0.3 : 0.18) * side - 0.04 * math.sin(t * 0.4);
    final up = st.full ? 0.32 : 0.7;
    final eye = vm.Vector3(tg.x + math.sin(a) * dist, tg.y + up, tg.z - math.cos(a) * dist);
    return (eye, tg, fov, w * (st.full ? 1.0 : 0.55));
  }
}
