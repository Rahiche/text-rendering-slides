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

/// 分割 · Itemize, up the right-hand side street (where a block was): a
/// works whose open ground floor cuts text into runs before it's shaped.
/// "Hi مرحبا 世界 👋" comes in on the belt as one bar; a scanner reads it
/// and each stretch lights up in its script's colour (Latin, Arabic, Han,
/// emoji); blades come down where the script changes, the runs part, and
/// each gets its tag: its script, its direction (the Arabic one right to
/// left), the font it'll be shaped with. Then they go on, one by one, to
/// shaping.
class ItemizeWorks extends Vignette {
  ItemizeWorks(super.kit);

  @override
  String get name => 'itemize';
  @override
  String get kick => 'ITEMIZE';
  @override
  String get line => 'One string, four runs';
  @override
  String get note => 'cut where the script changes: each run gets a direction and a font';

  @override
  double get loop => 13.5;
  @override
  double get visit => 11.6;

  /// Facing the plaza across the street.
  @override
  final frame = trs(vm.Vector3(28.4, 0, 29.2), rotY: math.pi / 2);

  /// The runs: their text, script, direction, font, colour, and the block's
  /// width.
  static const _text = ['Hi', 'مرحبا', '世界', '👋'];
  static const _script = ['Latin', 'Arabic', 'Han', 'Emoji'];
  static const _rtl = [false, true, false, false];
  static const _font = ['Space Grotesk', 'Noto Kufi Arabic', 'Noto Sans JP', 'Noto Color Emoji'];
  static const _colors = [0x6C9BE0, 0x3FA37A, 0xE8505F, 0xF2B13A];
  static const _w = [0.74, 1.3, 1.0, 0.64];

  /// The belt (its top, its depth line: well inside, so the camera can
  /// stand in the doorway, the street behind it), the blocks' height and
  /// depth, the gap the cuts open.
  static const _beltY = 1.0, _beltZ = 3.2, _h = 0.56, _d = 0.32, _gap = 0.32;
  static final _barW = _w.reduce((a, b) => a + b);

  /// Where run [k]'s middle is in the bar (from its middle).
  static double _mid(int k) {
    var x = -_barW / 2;
    for (var i = 0; i < k; i++) {
      x += _w[i];
    }
    return x + _w[k] / 2;
  }

  /// The joint after run [k] (a cut there).
  static double _joint(int k) => _mid(k) + _w[k] / 2;

  /// The timeline: in on the belt, the scan, the cuts, the tags, out.
  static const _in0 = 0.3, _in1 = 2.4, _scan0 = 2.7, _scan1 = 4.5, _cut0 = 4.9, _cutEvery = 0.6, _tag0 = 6.9, _out0 = 9.0, _outEvery = 0.45;
  static double _cutAt(int k) => _cut0 + _cutEvery * k;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700);

  final _blocks = <Node>[], _tags = <Node>[];
  int _operator = -1;
  final _p = FigurePose();
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [('Hi مرحبا 世界 👋 ITEMIZE Latin Arabic Han Emoji LTR RTL', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 16, glows: 24, cyls: 4);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.75);
    storefront(b, trim: 0xC8442F);
    b.buildInto(shell, 'itemize works', lightChannelMask: 0x01);
    // The belt on its legs, the scanner's rails, the blades' beam, the
    // controls, the way out to shaping.
    final dark = Vignette.c(0x2B2E33), steel = Vignette.c(0x8A8F98);
    box(b, m, 11.4, 0.12, 0.7, 0, _beltY - 0.06, _beltZ, Vignette.c(0x3A3F48));
    for (var x = -5.0; x <= 5.01; x += 2.5) {
      for (final dz in [-0.28, 0.28]) {
        box(b, m, 0.08, _beltY - 0.12, 0.08, x, (_beltY - 0.12) / 2, _beltZ + dz, dark);
      }
    }
    for (final dz in [-0.48, 0.48]) {
      box(b, m, 7.0, 0.06, 0.06, 0, 2.35, _beltZ + dz, steel);
    }
    box(b, m, 4.2, 0.18, 0.5, _joint(1), 2.45, _beltZ, dark);
    box(b, m, 0.5, 1.1, 0.4, 4.6, 0.55, _beltZ + 1.0, Vignette.c(0x2E6DA8));
    box(b, m, 1.4, 2.2, 0.1, 5.6, 1.1, _beltZ, Vignette.c(0x14181F));
    b.buildInto(detail, 'itemize belt', lightChannelMask: 0x01);
    final ink = const Color(0xFF14203A);
    await Future.wait([
      sign(
        7.0,
        1.3,
        vm.Matrix4.translation(vm.Vector3(0, 6.2, -0.05)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1E2433));
          Vignette.text(c, 'ITEMIZE', Rect.fromLTWH(0, 0, s.width, s.height * 0.66), s.height * 0.5, const Color(0xFFF2C94C), lang: 'ja');
          Vignette.text(c, 'ONE STRING → FOUR RUNS', Rect.fromLTWH(0, s.height * 0.62, s.width, s.height * 0.32), s.height * 0.22, const Color(0xFFF4EBD8));
        },
        glow: 0.5,
        shell: true,
      ),
      sign(
        1.3,
        0.34,
        vm.Matrix4.translation(vm.Vector3(5.6, 2.4, _beltZ - 0.08)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF2E3546));
          Vignette.text(c, '→ SHAPING', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.5, const Color(0xFFF4EBD8));
        },
        glow: 0.6,
        thick: 0.02,
      ),
      // The bar's runs: each a block with its text on the front.
      for (var k = 0; k < 4; k++)
        sign(
          _w[k],
          _h,
          vm.Matrix4.identity(),
          (c, s) {
            c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4F1EA));
            final family = k == 1 ? BP.arabic : BP.display;
            Vignette.text(
              c,
              _text[k],
              Rect.fromLTWH(0, s.height * 0.08, s.width, s.height * 0.84),
              s.height * 0.56,
              ink,
              lang: k == 2 ? 'ja' : null,
              family: family,
            );
          },
          px: (_w[k] * 400).round(),
          glow: 0.15,
          thick: _d,
        ),
      // Their tags: the script and direction, the font.
      for (var k = 0; k < 4; k++)
        sign(
          0.96,
          0.38,
          vm.Matrix4.identity(),
          (c, s) {
            c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4EBD8));
            c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height * 0.12), Paint()..color = Color(0xFF000000 | _colors[k]));
            final dir = k == 3 ? '' : (_rtl[k] ? ' · RTL ←' : ' · LTR →');
            Vignette.text(c, '${_script[k]}$dir', Rect.fromLTWH(0, s.height * 0.14, s.width, s.height * 0.44), s.height * 0.3, ink);
            Vignette.text(
              c,
              _font[k],
              Rect.fromLTWH(0, s.height * 0.58, s.width, s.height * 0.36),
              s.height * 0.22,
              const Color(0xFF3A4558),
              weight: FontWeight.w600,
            );
          },
          px: 400,
          glow: 0.3,
          thick: 0.015,
        ),
    ]).then((nodes) {
      _blocks.addAll(nodes.sublist(2, 6));
      _tags.addAll(nodes.sublist(6, 10));
    });
    for (final n in [..._blocks, ..._tags]) {
      n.visible = false;
    }
    _operator = person(
      FigureLook()
        ..top = rgbHex(0xF2F0EA)
        ..layer = rgbHex(0xC8442F)
        ..legs = rgbHex(0x2B3442)
        ..shoes = rgbHex(0x1B1C20)
        ..skin = rgbHex(0xC59A7C)
        ..hairColor = rgbHex(0x1A1714)
        ..cap = rgbHex(0xC8442F),
    );
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// Where the bar's middle is on the belt at [u] (coming in from the left).
  static double _barX(double u) => lerp(-8.0, 0, eio(seg(u, _in0, _in1)));

  /// How far the cuts have parted run [k] from the bar's middle (each cut
  /// left of it pushes it on a gap).
  static double _parted(int k, double u) {
    var x = 0.0;
    for (var i = 0; i < 3; i++) {
      final f = eio(seg(u, _cutAt(i) + 0.25, _cutAt(i) + 0.55));
      x += (i < k ? 1 : 0) * _gap * f - _gap * 1.5 * f / 3;
    }
    return x;
  }

  /// Run [k] going out to shaping (the last first): how far along.
  static double _outOf(int k, double u) => eio(seg(u, _out0 + _outEvery * (3 - k), _out0 + _outEvery * (3 - k) + 1.1));

  final _mm = vm.Matrix4.identity();

  void _place(Node n, double x, double y, double z) {
    _mm
      ..setIdentity()
      ..setTranslationRaw(x, y, z);
    n.localTransform = frame * _mm;
  }

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final bar = _barX(u);
    final scanX = lerp(_mid(0) - 0.7, _mid(3) + 0.7, seg(u, _scan0, _scan1));
    final scanning = u > _scan0 - 0.2 && u < _scan1 + 0.2;
    for (var k = 0; k < 4; k++) {
      final out = _outOf(k, u);
      final x = bar + _mid(k) + _parted(k, u) + out * (6.4 - (_mid(k) + _parted(k, u)));
      final shown = u >= _in0 && out < 0.98;
      final n = _blocks[k]..visible = shown;
      if (shown) _place(n, x, _beltY + _h / 2, _beltZ);
      // Read: lit in its script's colour once the scan's been over it (a
      // strip along the belt in front of it, and its colour on the belt).
      final read = smooth(_mid(k) - 0.2, _mid(k) + 0.2, scanX) * (u > _scan0 ? 1 : 0);
      if (shown && read > 0.01) {
        final c = Vignette.c(_colors[k]), g = 1.8 * read;
        pglow(x, _beltY + 0.012, _beltZ - _d / 2 - 0.06, _w[k] - 0.06, 0.03, 0.06, vm.Vector4(c.x * g, c.y * g, c.z * g, 1));
        // The direction it'll be laid out in: an arrow on the belt.
        final dir = _rtl[k] ? -1.0 : 1.0, ax = x + dir * 0.18, ay = _beltY + 0.012, az = _beltZ - _d / 2 - 0.2;
        pglow(ax - dir * 0.16, ay, az, 0.32, 0.02, 0.03, vm.Vector4(c.x * g, c.y * g, c.z * g, 1));
        pglow(ax + dir * 0.02, ay, az + 0.04, 0.12, 0.02, 0.03, vm.Vector4(c.x * g, c.y * g, c.z * g, 1), yaw: dir * 0.7);
        pglow(ax + dir * 0.02, ay, az - 0.04, 0.12, 0.02, 0.03, vm.Vector4(c.x * g, c.y * g, c.z * g, 1), yaw: -dir * 0.7);
      }
      // The tag, dropped onto it once it's cut free.
      final tag = smooth(_tag0 + 0.3 * k, _tag0 + 0.3 * k + 0.45, u);
      final tn = _tags[k]..visible = shown && tag > 0;
      if (tn.visible) _place(tn, x, _beltY + _h + 0.3 + 1.2 * (1 - eo(tag)), _beltZ - 0.02);
    }
    // The scanner: a frame over the belt riding its rails, its light.
    final sx = scanning ? scanX : (u < _scan0 ? _mid(0) - 0.7 : _mid(3) + 0.7);
    pbox(sx, 1.68, _beltZ - 0.48, 0.1, 1.36, 0.08, Vignette.c(0x3A4252));
    pbox(sx, 1.68, _beltZ + 0.48, 0.1, 1.36, 0.08, Vignette.c(0x3A4252));
    pbox(sx, 2.36, _beltZ, 0.16, 0.12, 1.06, Vignette.c(0x3A4252));
    if (scanning) pglow(sx, _beltY + _h + 0.06, _beltZ, 0.03, 0.02, 0.9, vm.Vector4(0.6, 1.6, 2.4, 1));
    // The blades: one over each joint, down through it in turn.
    var pull = 0.0;
    for (var i = 0; i < 3; i++) {
      final a = _cutAt(i), f = math.sin(math.pi * seg(u, a, a + 0.4));
      pull = math.max(pull, f);
      // (Over the joint, wherever the runs either side of it have got to.)
      final bx = bar + (_mid(i) + _parted(i, u) + _w[i] / 2 + _mid(i + 1) + _parted(i + 1, u) - _w[i + 1] / 2) / 2;
      final y = lerp(2.2, _beltY + _h / 2 + 0.02, f), top = y + (_h + 0.1) / 2;
      pbox(bx, y, _beltZ, 0.02, _h + 0.1, _d + 0.16, Vignette.c(0xC9CED6));
      pbox(bx, (top + 2.45) / 2, _beltZ, 0.05, math.max(0.05, 2.45 - top), 0.05, Vignette.c(0x5A6470));
      if (f > 0.85) pglow(bx, _beltY + 0.1, _beltZ - _d / 2 - 0.02, 0.06, 0.06, 0.02, vm.Vector4(2.4, 2.0, 1.4, 1));
    }
    // The operator at the controls: a hand on the lever, pulled for each
    // cut.
    final p = _p..rest();
    p.pos.setValues(4.6, 0.2, _beltZ + 1.6);
    p.yaw = 0.25;
    Idle.stand(p, t, Manner.of(210), look: 0.25, at: vm.Vector3(0, 1.4, _beltZ));
    worldPose(p);
    kit.crew.aim(p, 1, world(4.42, 1.14 - 0.1 * pull, _beltZ + 1.0));
    kit.figures.draw(_operator, p);
    pcyl(4.42, 1.14 - 0.1 * pull, _beltZ + 1.0, 0.025, 0.1, Vignette.c(0xC8442F));
    pbox(4.45, 1.08 - 0.05 * pull, _beltZ + 1.0, 0.03, 0.14, 0.03, Vignette.c(0x5A6470), roll: 0.3);
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the plaza's edge across the street: the works, then in at the
    // doorway on the belt, along with the runs as they go.
    final k = smooth(0.4, 2.4, u), out = smooth(_out0 - 0.3, _out0 + 1.5, u);
    return Shot(
      vm.Vector3(lerp(2.6, 0.5, k) + 1.4 * out, lerp(4.4, 2.3, k), lerp(-9.6, -0.3, k)),
      vm.Vector3(lerp(0.3, 0.3, k) + 1.8 * out, lerp(3.0, 1.35, k), lerp(1.0, _beltZ, k)),
      fov: lerp(52, 48, k),
      settle: 1.1,
      drift: 0.4,
    );
  }
}
