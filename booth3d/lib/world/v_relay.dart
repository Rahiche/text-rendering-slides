import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'vignette.dart';

/// リレー · Text() to ui.Paragraph, a running track beyond the park (east of
/// the pixel farm): Flutter's text stack as a relay. Five runners — Text,
/// RichText, RenderParagraph, TextPainter, ui.Paragraph — each at their
/// station; the baton is the word, run from one to the next down the
/// stack (the constraints go down with it). At the end ui.Paragraph lays
/// it out and holds up its size, which goes back up the line, tossed from
/// hand to hand to Text (sizes come up). Then they jog back to their marks.
class TextRelay extends Vignette {
  TextRelay(super.kit);

  @override
  String get name => 'relay';
  @override
  String get kick => 'Text() → ui.Paragraph';
  @override
  String get line => 'Constraints go down, sizes come up';
  @override
  String get note => 'Text → RichText → RenderParagraph → TextPainter → ui.Paragraph';

  @override
  double get loop => 20;
  @override
  double get visit => 13.6;

  @override
  final frame = trs(vm.Vector3(10, 0, 78));

  static const _layers = ['Text', 'RichText', 'RenderParagraph', 'TextPainter', 'ui.Paragraph'];
  static const _colors = [0x3A6EA5, 0x2E9C8A, 0x7A5CC0, 0xE8A33D, 0xE8505F];

  /// The stations along the track (x), where each runner waits.
  static double _station(int k) => -6.0 + 3.0 * k;

  /// The legs: runner k carries the baton from their station to the next
  /// over [_leg0 + k·_legEvery, + _run], hands it on.
  static const _leg0 = 1.0, _legEvery = 1.45, _run = 1.1;
  static double _legAt(int k) => _leg0 + _legEvery * k;

  /// Laid out at the end; the size tossed back hand to hand; the jog home.
  static final _laid = _legAt(4) + 0.2, _toss0 = _laid + 1.0;
  static const _tossEvery = 0.8;
  static final _home = _toss0 + 4 * _tossEvery + 2.6;

  final _runners = <int>[];
  final _poses = List.generate(5, (_) => FigurePose());
  late final Glyph3D _baton;
  late final Node _size;
  bool _ready = false;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700);

  @override
  List<(String, TextStyle)> get fontRuns => [('Flutter Text RichText RenderParagraph TextPainter ui.Paragraph', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 8, glows: 16);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.85);
    // The track (a lane, its lines, the exchange marks), the posts for
    // the stations' boards, a finish arch.
    box(b, m, 15.5, 0.04, 1.6, 0, 0.02, 0, Vignette.c(0xB5523A));
    for (final z in [-0.78, 0.78]) {
      box(b, m, 15.5, 0.045, 0.05, 0, 0.025, z, Vignette.c(0xF4F1EA));
    }
    for (var k = 0; k < 5; k++) {
      box(b, m, 0.06, 0.045, 1.5, _station(k), 0.025, 0, Vignette.c(0xF4F1EA));
      for (final dx in [-0.75, 0.75]) {
        box(b, m, 0.08, 1.9, 0.08, _station(k) + dx, 0.95, 1.6, Vignette.c(0x3A4C6E));
      }
    }
    for (final x in [7.2, 8.6]) {
      box(b, m, 0.15, 3.2, 0.15, x, 1.6, x == 7.2 ? -0.9 : 0.9, Vignette.c(0x3A4C6E));
    }
    b.buildInto(detail, 'relay track', castsShadows: false, lightChannelMask: 0x01);
    final ink = const Color(0xFF14203A);
    await Future.wait([
      for (var k = 0; k < 5; k++)
        sign(1.7, 0.62, vm.Matrix4.translation(vm.Vector3(_station(k), 1.75, 1.55)), (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4F1EA));
          c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height * 0.18), Paint()..color = Color(0xFF000000 | _colors[k]));
          Vignette.text(c, _layers[k], Rect.fromLTWH(0, s.height * 0.22, s.width, s.height * 0.5), s.height * 0.34, ink, family: BP.mono);
          Vignette.text(c, '${k + 1}', Rect.fromLTWH(0, s.height * 0.7, s.width, s.height * 0.26), s.height * 0.2, ink);
        }),
      // The rule, along the back.
      sign(9.0, 0.7, vm.Matrix4.translation(vm.Vector3(0, 3.0, 1.62)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14203A));
        Vignette.text(c, 'constraints go down  →', Rect.fromLTWH(0, 0, s.width / 2, s.height), s.height * 0.38, const Color(0xFF7FB4F0));
        Vignette.text(c, '←  sizes come up', Rect.fromLTWH(s.width / 2, 0, s.width / 2, s.height), s.height * 0.38, const Color(0xFFF2A33A));
      }, glow: 0.6),
    ]);
    _size = await sign(
      0.56,
      0.32,
      vm.Matrix4.identity(),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF2A33A));
        Vignette.text(c, '92 × 24', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.56, ink, family: BP.mono);
      },
      px: 320,
      glow: 0.6,
      thick: 0.02,
    );
    _size.visible = false;
    final gold = pbr(Vignette.c(0xF2C94C), roughness: 0.3, metallic: 0.6, emissive: Vignette.c(0xF2C94C), emissiveStrength: 0.35);
    _baton = (await letters([('Flutter', _style)], gold, unitsPerPx: 0.16 / 160, depth: 0.04)).first;
    for (var k = 0; k < 5; k++) {
      _runners.add(
        person(
          FigureLook()
            ..top = rgbHex(0xF4F4F0)
            ..layer = rgbHex(_colors[k])
            ..legs = rgbHex(0x1C1F26)
            ..shoes = rgbHex(k.isEven ? 0xF4F4F0 : 0xE8505F)
            ..skin = rgbHex(const [0xE0BB9E, 0xC59A7C, 0xEFD0BA, 0x8E644B, 0xE8C6AC][k])
            ..hairColor = rgbHex(0x1A1714)
            ..hair = k.isOdd ? Hair.bob : Hair.short
            ..slim = k.isOdd,
        ),
      );
    }
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// Where runner [k] is at [u], whether running (and at what pace, how far
  /// into the run), and which way they face.
  (double, double, double, double) _at(int k, double u) {
    final x0 = _station(k), stop = k < 4 ? _station(k + 1) - 0.65 : x0;
    if (k < 4) {
      final a = _legAt(k);
      if (u < a) return (x0, 0, 0, -math.pi / 2);
      if (u < a + _run) {
        final f = seg(u, a, a + _run), d = (stop - x0) * (f * f * (3 - 2 * f));
        return (x0 + d, (stop - x0) / _run * 1.5 * math.sin(math.pi * f).clamp(0.3, 1.0), d, -math.pi / 2);
      }
    }
    // Home again: a jog back to the mark.
    final back = _home + 0.25 * k;
    if (k < 4 && u >= back && u < back + 1.6) {
      final f = seg(u, back, back + 1.6);
      return (lerp(stop, x0, f), 1.8, (stop - x0) * f, math.pi / 2);
    }
    final x = k < 4 && u >= _legAt(k) && u < back ? stop : x0;
    // Waiting faces the way the baton comes (the last one back up the
    // track); for the size going back, all face the camera.
    final wait = k == 4 ? math.pi / 2 : -math.pi / 2;
    return (x, 0, 0, u >= _laid && u < _home ? lerp(wait, 0, smooth(_laid, _laid + 0.5, u)) : wait);
  }

  final _palm = vm.Vector3.zero(), _p2 = vm.Vector3.zero();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    // Who has the baton: runner k from their leg until the next one's.
    var holder = 0;
    for (var k = 1; k < 5; k++) {
      if (u >= _legAt(k) - 0.1) holder = k;
    }
    if (u >= _home) holder = -1;
    // The size, tossed back up: who has it, or where it is in the air.
    var sizeHolder = -1;
    double? fly;
    if (u >= _laid + 0.4 && u < _home) {
      sizeHolder = 4;
      for (var k = 0; k < 4; k++) {
        final at = _toss0 + _tossEvery * k;
        if (u >= at) sizeHolder = 3 - k;
        if (u >= at - _tossEvery * 0.55 && u < at) fly = 4 - k - (u - (at - _tossEvery * 0.55)) / (_tossEvery * 0.55);
      }
    }
    for (var k = 0; k < 5; k++) {
      final p = _poses[k]..rest();
      final (x, speed, dist, yaw) = _at(k, u);
      p.pos.setValues(x, 0, 0);
      final m = Manner.of(200 + k);
      if (speed > 0.05) {
        // (The steps fitted to the leg, whatever the pace.)
        Gait.walk(p, Gait.phaseOver(dist.abs(), 2.35, 2.4, 1, m), speed.clamp(1.0, 4.0), m);
      } else {
        Idle.stand(p, t, m, look: 0.4, at: vm.Vector3(_station(holder.clamp(0, 4)), 1.2, 0));
        // Ready for the baton: up on the toes, a hand back.
        final next = k > 0 ? _legAt(k) : -1.0;
        if (k > 0 && u > next - 1.0 && u < next) {
          p.armPitch[1] = -0.55;
          p.armRoll[1] = 0.2;
          p.lean = 0.25;
        }
      }
      p.yaw = yaw;
      // Holding the size out.
      if (sizeHolder == k) p.handTo(1, 0.2, 0.4, -0.32);
      worldPose(p);
      kit.figures.draw(_runners[k], p);
      final rig = kit.figures.rig;
      if (holder == k) local(rig.palms[1], _palm);
      if (sizeHolder == k) local(rig.palms[1], _p2);
    }
    // The baton (the word, gold), in its holder's hand; the size card.
    if (holder >= 0) {
      put(_baton, _palm.x, _palm.y + 0.08, _palm.z - 0.05);
      final hot = u > _laid - 0.2 && u < _laid + 1.0;
      if (hot) pglow(_palm.x, _palm.y + 0.08, _palm.z - 0.08, 0.7, 0.24, 0.02, vm.Vector4(1.4, 1.1, 0.3, 1));
    } else {
      put(_baton, 0, 0, 0, s: 0);
    }
    _size.visible = sizeHolder >= 0 || fly != null;
    if (fly != null) {
      // In the air between two runners (from the higher to the lower).
      final from = fly.ceil(), to = fly.floor(), f = 1 - (fly - to);
      final x0 = _at(from, u).$1, x1 = _at(to, u).$1;
      _place(lerp(x0, x1, f), 2.1 + 1.1 * math.sin(math.pi * f), -0.05);
    } else if (sizeHolder >= 0) {
      _place(_p2.x, _p2.y + 0.18, _p2.z - 0.06);
    }
    pool.end();
  }

  final _mm = vm.Matrix4.identity();

  void _place(double x, double y, double z) {
    _mm
      ..setIdentity()
      ..setTranslationRaw(x, y, z);
    _size.localTransform = frame * _mm;
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // Alongside the baton down the track; back for the toss up the line.
    final leg = ((u - _leg0) / _legEvery).clamp(0.0, 4.0);
    final bx = lerp(_station(0), _station(4), leg / 4);
    final back = smooth(_laid - 0.2, _laid + 1.0, u);
    final eye = vm.Vector3(lerp(bx - 3.2, 0.5, back), lerp(1.7, 3.3, back), lerp(-4.6, -9.6, back));
    final tg = vm.Vector3(lerp(bx + 1.0, 0.2, back), lerp(1.15, 1.4, back), 0.2);
    return Shot(eye, tg, fov: lerp(46, 48, back), settle: 0.8, drift: 0.4);
  }
}
