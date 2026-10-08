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

/// ハイフン · Hyphenation, a sawmill in the park (east of the path): a word
/// cut where the line ends. "split" is on the first line; "hyphenation"
/// is set down after it and runs past the margin. Its soft hyphen (U+00AD,
/// invisible till now) lights up between "hyphen" and "ation"; the saw
/// comes down there, a hyphen shows up at the end of the first half, and
/// the rest drops to the next line.
class HyphenMill extends Vignette {
  HyphenMill(super.kit);

  @override
  String get name => 'hyphen';
  @override
  String get kick => 'HYPHENATION';
  @override
  String get line => 'Break inside a word';
  @override
  String get note => 'at a soft hyphen (U+00AD): it only shows when the line ends there';

  @override
  double get loop => 13;
  @override
  double get visit => 11.4;

  /// Facing the park's path.
  @override
  final frame = trs(vm.Vector3(7.0, 0, 57.0), rotY: math.pi / 2);

  /// The lines: where they start, the margin, their heights, their depth.
  static const _left = -3.4, _margin = 0.2, _line1 = 1.2, _line2 = 0.55, _z = 1.6;

  /// The words' blocks: widths, height, depth; the space; the hyphen's.
  static const _wSplit = 1.1, _wHy = 1.5, _wAt = 1.2, _h = 0.42, _d = 0.3, _space = 0.18, _dash = 0.2;

  /// Where "hyphenation" goes, and the joint in it (the soft hyphen).
  static const _hyX = _left + _wSplit + _space, _joint = _hyX + _wHy;

  /// The timeline: the word set down, the soft hyphen lights, the saw, the
  /// rest to the next line, the hold, cleared away.
  static const _set0 = 0.6, _setLen = 1.0, _shy = 2.4, _saw0 = 3.6, _sawLen = 1.2, _drop0 = 5.2, _dropLen = 1.0, _clear = 10.6;

  final _words = <Node>[];
  late final Node _shyTag;
  int _sawyer = -1;
  final _p = FigurePose();
  bool _ready = false;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700);

  @override
  List<(String, TextStyle)> get fontRuns => [('split hyphenation hyphen- ation HYPHENATION U+00AD', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 16, glows: 12, cyls: 6);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.85);
    final wood = Vignette.c(0x9C6B3C), dark = Vignette.c(0x3A4252);
    // The two lines (benches), the margin post, the saw's frame, the back
    // board's posts.
    for (final y in [_line1, _line2]) {
      box(b, m, _margin - _left + 0.5, 0.08, 0.7, (_left + _margin) / 2 - 0.1, y - 0.04, _z, wood);
      for (final x in [_left + 0.1, _margin - 0.2]) {
        box(b, m, 0.08, y - 0.08, 0.08, x, (y - 0.08) / 2, _z + 0.25, Vignette.c(0x6E4A2A));
      }
    }
    box(b, m, 0.07, 2.0, 0.07, _margin, 1.0, _z - 0.42, Vignette.c(0xE8505F));
    box(b, m, 0.07, 2.0, 0.07, _margin, 1.0, _z + 0.42, Vignette.c(0xE8505F));
    box(b, m, 0.07, 0.07, 0.9, _margin, 2.0, _z, Vignette.c(0xE8505F));
    box(b, m, 0.12, 2.6, 0.12, _joint, 1.3, _z + 0.6, dark);
    box(b, m, 0.16, 0.16, 0.7, _joint, 2.55, _z + 0.3, dark);
    for (final x in [-3.4, 1.4]) {
      box(b, m, 0.1, 3.7, 0.1, x, 1.85, _z + 1.1, dark);
    }
    b.buildInto(detail, 'hyphen mill', lightChannelMask: 0x01);
    final ink = const Color(0xFF3A2414);
    Future<Node> word(String s, double w) => sign(
      w,
      _h,
      vm.Matrix4.identity(),
      (c, sz) {
        c.drawRect(Offset.zero & sz, Paint()..color = const Color(0xFFE2C59A));
        // Rings at the ends, as cut wood.
        for (final x in [0.0, sz.width]) {
          c.drawCircle(Offset(x, sz.height / 2), sz.height * 0.42, Paint()..color = const Color(0xFFCFAE7E));
        }
        Vignette.text(c, s, Rect.fromLTWH(0, 0, sz.width, sz.height), sz.height * 0.6, ink);
      },
      px: (w * 360).round(),
      glow: 0.2,
      thick: _d,
    );
    final nodes = await Future.wait([
      sign(4.6, 0.8, vm.Matrix4.translation(vm.Vector3(-1.0, 3.35, _z + 1.05)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1E2433));
        Vignette.text(c, 'HYPHENATION', Rect.fromLTWH(0, 0, s.width, s.height * 0.62), s.height * 0.42, const Color(0xFFF2C94C), lang: 'ja');
        Vignette.text(c, 'break inside a word', Rect.fromLTWH(0, s.height * 0.6, s.width, s.height * 0.34), s.height * 0.24, const Color(0xFFF4EBD8));
      }, glow: 0.5),
      sign(
        0.9,
        0.3,
        vm.Matrix4.translation(vm.Vector3(_margin, 2.25, _z)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE8505F));
          Vignette.text(c, 'MARGIN', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.5, const Color(0xFFF4F1EA));
        },
        glow: 0.5,
        thick: 0.02,
      ),
      word('split', _wSplit),
      word('hyphen', _wHy),
      word('ation', _wAt),
      word('-', _dash),
      sign(
        0.62,
        0.2,
        vm.Matrix4.identity(),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14203A));
          Vignette.text(c, 'U+00AD', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.6, const Color(0xFF7FE0B0), family: 'monospace');
        },
        px: 320,
        glow: 0.8,
        thick: 0.01,
      ),
    ]);
    _words.addAll(nodes.sublist(2, 6));
    _shyTag = nodes[6]..visible = false;
    _sawyer = person(
      FigureLook()
        ..top = rgbHex(0xC8442F)
        ..legs = rgbHex(0x3A3F48)
        ..shoes = rgbHex(0x3A2E26)
        ..skin = rgbHex(0xC59A7C)
        ..hairColor = rgbHex(0x8F8B86)
        ..cap = rgbHex(0x2B3442),
    );
    _ready = true;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

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
    final clear = eio(seg(u, _clear, _clear + 0.9));
    final y1 = _line1 + _h / 2, y2 = _line2 + _h / 2;
    // "split", there from the start (and lifted off with the rest).
    _place(_words[0], _left + _wSplit / 2, y1 + 2.5 * clear, _z);
    // "hyphenation" set down after it (one piece till it's cut).
    final set = eo(seg(u, _set0, _set0 + _setLen));
    final hy = _words[1]..visible = u >= _set0;
    final at = _words[2]..visible = u >= _set0;
    final down = lerp(1.6, 0, set);
    if (hy.visible) _place(hy, _hyX + _wHy / 2, y1 + down + 2.5 * clear, _z);
    // The rest, once cut: up clear of the line, back over it to the start
    // of the next, down onto it.
    final drop = seg(u, _drop0, _drop0 + _dropLen);
    if (at.visible) {
      final x0 = _joint + _wAt / 2, x1 = _left + _wAt / 2;
      final y = lerp(lerp(y1, y1 + _h + 0.15, smooth(0, 0.3, drop)), y2, smooth(0.68, 1, drop));
      _place(at, lerp(x0, x1, smooth(0.22, 0.8, drop)), y + down + 2.5 * clear, _z);
    }
    // The hyphen it gets, popping in at the end of the first half.
    final dash = eo(seg(u, _drop0 + 0.2, _drop0 + 0.55));
    final dn = _words[3]..visible = dash > 0;
    if (dn.visible) {
      _mm
        ..setIdentity()
        ..setTranslationRaw(_joint + _dash / 2 + 0.02, y1 + 2.5 * clear, _z)
        ..scaleByDouble(dash, dash, 1, 1);
      dn.localTransform = frame * _mm;
    }
    // Over the margin: a red glow where the word runs past it, until it's
    // cut.
    final over = seg(u, _set0 + _setLen - 0.2, _set0 + _setLen) * (1 - seg(u, _drop0, _drop0 + 0.3));
    if (over > 0.01) {
      final x1 = _joint + _wAt;
      pglow((_margin + x1) / 2, y1 - _h / 2 - 0.02, _z - _d / 2 - 0.03, x1 - _margin, 0.03, 0.04, vm.Vector4(2.6 * over, 0.3 * over, 0.25 * over, 1));
    }
    // The soft hyphen: invisible in the word, lit up where the line can
    // break; its code on a tag.
    final shy = seg(u, _shy, _shy + 0.4) * (1 - seg(u, _drop0 + 0.4, _drop0 + 0.8));
    _shyTag.visible = shy > 0.01;
    if (_shyTag.visible) {
      pglow(_joint, y1, _z - _d / 2 - 0.02, 0.025, _h + 0.1, 0.02, vm.Vector4(0.6 * shy * 2.4, 2.2 * shy, 1.2 * shy, 1));
      _place(_shyTag, _joint, y1 + _h / 2 + 0.28 + 0.06 * math.sin(t * 2.4), _z - 0.2);
    }
    // The saw: down at the soft hyphen, spinning, the dust flying.
    final saw = math.sin(math.pi * seg(u, _saw0, _saw0 + _sawLen));
    final sy = lerp(2.15, y1 + 0.02, saw);
    pcyl(_joint, sy, _z - 0.02, 0.3, 0.02, Vignette.c(0xC9CED6), pitch: math.pi / 2);
    pcyl(_joint, sy, _z - 0.035, 0.07, 0.02, Vignette.c(0x5A6470), pitch: math.pi / 2);
    pbox(_joint, (sy + 2.55) / 2, _z + 0.28, 0.08, 2.55 - sy, 0.08, Vignette.c(0x5A6470));
    if (saw > 0.6) {
      for (var i = 0; i < 4; i++) {
        final age = ((t * 2.2 + i * 0.25) % 1.0);
        final w = world(_joint, y1 + 0.1 + 0.3 * age, _z - 0.2);
        kit.fx.puff(w.x, w.y, w.z, age, 0.08, seed: i, n: 1, tint: vm.Vector4(0.95, 0.85, 0.6, 0.6));
      }
    }
    // The sawyer, beside it: a hand on the lever that brings it down.
    final p = _p..rest();
    p.pos.setValues(_joint + 0.95, 0, _z + 0.85);
    p.yaw = 0.55;
    Idle.stand(p, t, Manner.of(240), look: 0.3, at: vm.Vector3(_joint, y1, _z));
    worldPose(p);
    final ly = 1.15 - 0.2 * saw;
    kit.crew.aim(p, 1, world(_joint + 0.5, ly, _z + 0.45));
    kit.figures.draw(_sawyer, p);
    pbox(_joint + 0.27, (ly + 1.45) / 2, _z + 0.45, 0.5, 0.04, 0.04, Vignette.c(0x2B2E33), roll: math.atan2(1.45 - ly, 0.5));
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the path: both lines and the margin; in a little for the cut.
    final k = smooth(_shy - 0.4, _shy + 0.4, u) * (1 - smooth(_drop0 + 1.2, _drop0 + 2.2, u));
    return Shot(
      vm.Vector3(lerp(-1.4, -0.9, k), lerp(1.9, 1.7, k), lerp(-4.4, -3.2, k)),
      vm.Vector3(lerp(-1.4, -0.9, k), lerp(1.1, 1.25, k), _z),
      fov: 52,
      settle: 1.0,
      drift: 0.35,
    );
  }
}
