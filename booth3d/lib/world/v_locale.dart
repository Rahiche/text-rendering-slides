import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'vignette.dart';

/// ロケール · Locale, across the left-hand side street (where a block was):
/// a sorting office where one code point is set in two languages. A card
/// with the code point comes down the chute and is split in two, a copy to
/// each press: the ja press stamps the glyph as Japanese has it, the
/// zh-Hans press as Chinese does — the same character, drawn two ways (one
/// code point for both: the locale picks the font). The two plates go up
/// side by side over the code point, to compare. Then the next: 直, 角,
/// 骨, 写.
class LocaleOffice extends Vignette {
  LocaleOffice(super.kit);

  @override
  String get name => 'locale';
  @override
  String get kick => 'ロケール · LOCALE';
  @override
  String get line => 'One code point, two glyphs';
  @override
  String get note => 'the same character as Japanese and as Chinese: the locale picks the font';

  @override
  double get loop => 15;
  @override
  double get visit => 12.8;

  /// Facing the plaza across the street.
  @override
  final frame = trs(vm.Vector3(-28.4, 0, 25.2), rotY: -math.pi / 2);

  static const _chars = ['直', '角', '骨', '写'];
  static const _codes = ['U+76F4', 'U+89D2', 'U+9AA8', 'U+5199'];

  /// The bundled fonts with both regional forms of these (subsets of Noto
  /// Sans JP and SC), and each side's colour.
  static const _families = ['CaseJP', 'CaseSC'];
  static const _langs = ['ja', 'zh'];
  static const _colors = [0x3A6EA5, 0xE8A33D];

  /// The presses (x either side, their table's top), the line's depth, the
  /// chute's mouth; the display (its plates' middles, size, depth).
  static const _pressX = 2.2, _tableY = 1.0, _z = 3.0, _chuteY = 3.75;
  static const _showX = 0.52, _showY = 2.75, _showZ = 3.62, _plate = 0.86;

  /// Each character's turn: from [_first], one every [_every] seconds.
  static const _first = 0.6, _every = 2.7;
  static double _at(int i) => _first + _every * i;

  final _cards = <Node>[], _plates = <Node>[], _codeTags = <Node>[];
  final _clerks = <int>[];
  final _poses = [FigurePose(), FigurePose()];
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [
    for (var s = 0; s < 2; s++) (_chars.join(), TextStyle(fontFamily: _families[s], fontSize: 160, locale: Locale(_langs[s]))),
  ];

  @override
  Future<void> init() async {
    makePool(boxes: 16, glows: 8, cyls: 4);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.75);
    storefront(b, w: 11, trim: 0x8E2A1E);
    b.buildInto(shell, 'locale office', lightChannelMask: 0x01);
    // The chute, the table along the line, the two presses' frames, the
    // wall the plates go up on.
    final dark = Vignette.c(0x2B2E33), steel = Vignette.c(0x8A8F98);
    box(b, m, 0.7, 0.9, 0.6, 0, _chuteY + 0.6, _z, Vignette.c(0x3A4252));
    box(b, m, 0.5, 0.2, 0.4, 0, _chuteY + 0.05, _z, steel);
    box(b, m, 6.0, 0.1, 0.8, 0, _tableY - 0.05, _z, Vignette.c(0x5A6470));
    for (final x in [-2.8, -1.0, 1.0, 2.8]) {
      box(b, m, 0.08, _tableY - 0.1, 0.08, x, (_tableY - 0.1) / 2, _z, dark);
    }
    for (final s in [-1.0, 1.0]) {
      for (final dx in [-0.42, 0.42]) {
        box(b, m, 0.1, 1.3, 0.1, s * _pressX + dx, _tableY + 0.65, _z + 0.2, dark);
      }
      box(b, m, 0.94, 0.14, 0.3, s * _pressX, _tableY + 1.32, _z + 0.2, dark);
    }
    box(b, m, 2.6, 1.6, 0.08, 0, _showY - 0.1, _showZ + 0.24, Vignette.c(0x1E2433));
    b.buildInto(detail, 'locale presses', lightChannelMask: 0x01);
    final ink = const Color(0xFF14203A);
    final nodes = await Future.wait([
      sign(
        7.0,
        1.3,
        vm.Matrix4.translation(vm.Vector3(0, 6.2, -0.05)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1E2433));
          Vignette.text(c, 'ロケール · LOCALE', Rect.fromLTWH(0, 0, s.width, s.height * 0.66), s.height * 0.46, const Color(0xFFF2C94C), lang: 'ja');
          Vignette.text(c, 'ONE CODE POINT, TWO GLYPHS', Rect.fromLTWH(0, s.height * 0.62, s.width, s.height * 0.32), s.height * 0.22, const Color(0xFFF4EBD8));
        },
        glow: 0.5,
        shell: true,
      ),
      // The presses' names, on their crossbars.
      for (var s = 0; s < 2; s++)
        sign(
          1.3,
          0.3,
          vm.Matrix4.translation(vm.Vector3((s == 0 ? -1 : 1) * _pressX, _tableY + 1.32, _z + 0.03)),
          (c, sz) {
            c.drawRect(Offset.zero & sz, Paint()..color = Color(0xFF000000 | _colors[s]));
            Vignette.text(
              c,
              s == 0 ? 'ja · 日本語' : 'zh-Hans · 简体中文',
              Rect.fromLTWH(0, 0, sz.width, sz.height),
              sz.height * 0.52,
              const Color(0xFFF4F1EA),
              lang: _langs[s],
            );
          },
          glow: 0.5,
          thick: 0.03,
        ),
      // The cards (two of each: the copies), the plates (one a side).
      for (var i = 0; i < 4; i++)
        for (var s = 0; s < 2; s++)
          sign(
            0.56,
            0.28,
            vm.Matrix4.identity(),
            (c, sz) {
              c.drawRect(Offset.zero & sz, Paint()..color = const Color(0xFFF4EBD8));
              Vignette.text(c, _codes[i], Rect.fromLTWH(0, 0, sz.width, sz.height), sz.height * 0.48, ink, family: 'monospace');
            },
            px: 320,
            glow: 0.3,
            thick: 0.01,
          ),
      for (var i = 0; i < 4; i++)
        for (var s = 0; s < 2; s++)
          sign(
            _plate,
            _plate,
            vm.Matrix4.identity(),
            (c, sz) {
              c.drawRect(Offset.zero & sz, Paint()..color = const Color(0xFFF7F4EC));
              c.drawRect(Rect.fromLTWH(0, sz.height * 0.9, sz.width, sz.height * 0.1), Paint()..color = Color(0xFF000000 | _colors[s]));
              final tp = TextPainter(
                text: TextSpan(
                  text: _chars[i],
                  style: TextStyle(fontFamily: _families[s], fontSize: sz.height * 0.74, color: ink, locale: Locale(_langs[s]), height: 1.0),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              tp.paint(c, Offset((sz.width - tp.width) / 2, sz.height * 0.45 - tp.height / 2));
              tp.dispose();
            },
            px: 360,
            glow: 0.25,
            thick: 0.03,
          ),
      // The code point under the pair on show.
      for (var i = 0; i < 4; i++)
        sign(
          1.0,
          0.24,
          vm.Matrix4.translation(vm.Vector3(0, _showY - _plate / 2 - 0.2, _showZ - 0.02)),
          (c, sz) {
            c.drawRect(Offset.zero & sz, Paint()..color = const Color(0xFF14203A));
            Vignette.text(c, '${_codes[i]} · ${_chars[i]}', Rect.fromLTWH(0, 0, sz.width, sz.height), sz.height * 0.56, const Color(0xFFF4EBD8), lang: 'ja');
          },
          px: 400,
          glow: 0.6,
          thick: 0.01,
        ),
    ]);
    _cards.addAll(nodes.sublist(3, 11));
    _plates.addAll(nodes.sublist(11, 19));
    _codeTags.addAll(nodes.sublist(19, 23));
    for (final n in [..._cards, ..._plates, ..._codeTags]) {
      n.visible = false;
    }
    for (var s = 0; s < 2; s++) {
      _clerks.add(
        person(
          FigureLook()
            ..top = rgbHex(0xF2F0EA)
            ..layer = rgbHex(_colors[s])
            ..legs = rgbHex(0x2B3442)
            ..shoes = rgbHex(0x1B1C20)
            ..skin = rgbHex(s == 0 ? 0xE8C6AC : 0xD9B194)
            ..hairColor = rgbHex(0x1A1714)
            ..hair = s == 0 ? Hair.short : Hair.bob
            ..slim = s == 1,
        ),
      );
    }
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
    final stamp = [0.0, 0.0];
    for (var i = 0; i < 4; i++) {
      final a = _at(i);
      // Down the chute to the table, then a copy to each press.
      final drop = eio(seg(u, a, a + 0.5)), split = eio(seg(u, a + 0.55, a + 1.0));
      // The press comes down on it; the plate it leaves goes up on show,
      // until the next pair takes its place.
      final press = math.sin(math.pi * seg(u, a + 1.05, a + 1.45)), stamped = u >= a + 1.25, up = eio(seg(u, a + 1.5, a + 2.4));
      final next = i < 3 ? _at(i + 1) + 1.5 : 1e9, gone = eio(seg(u, next, next + 0.5));
      _codeTags[i].visible = u >= a + 2.2 && gone < 0.5;
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        if (u >= a - 0.6 && u < a + 1.25) stamp[s] = math.max(stamp[s], press);
        final card = _cards[i * 2 + s]..visible = u >= a && !stamped;
        if (card.visible) _place(card, side * _pressX * split + side * 0.02 * (1 - split), lerp(_chuteY - 0.2, _tableY + 0.16, drop), _z - 0.1);
        final plate = _plates[i * 2 + s]..visible = stamped && gone < 1;
        if (plate.visible) {
          // (The pair before drops back out of sight behind the board.)
          _place(
            plate,
            lerp(side * _pressX, side * _showX, up),
            lerp(_tableY + _plate / 2 + 0.02, _showY, up) + 0.2 * math.sin(math.pi * up) - 1.6 * gone,
            lerp(_z - 0.1, _showZ, up) + 0.5 * gone,
          );
        }
        if (u > a + 1.2 && u < a + 1.6) {
          // A flash as it's stamped.
          final f = 1 - seg(u, a + 1.25, a + 1.6), c = Vignette.c(_colors[s]);
          pglow(side * _pressX, _tableY + 0.03, _z - 0.1, 0.7, 0.02, 0.5, vm.Vector4(c.x * 3 * f, c.y * 3 * f, c.z * 3 * f, 1));
        }
      }
    }
    // The press heads, down for each stamp.
    for (var s = 0; s < 2; s++) {
      final side = s == 0 ? -1.0 : 1.0, y = lerp(_tableY + 1.05, _tableY + 0.48, stamp[s]);
      pbox(side * _pressX, y, _z + 0.05, 0.8, 0.26, 0.5, Vignette.c(0x5A6470));
      pbox(side * _pressX, y - 0.15, _z - 0.08, 0.64, 0.04, 0.22, Vignette.c(_colors[s]));
      // The clerk beside it: a hand on its lever, pulled for each stamp.
      final p = _poses[s]..rest();
      p.pos.setValues(side * (_pressX + 1.25), 0.2, _z - 0.15);
      p.yaw = -side * 1.15;
      Idle.stand(p, t, Manner.of(220 + s), look: 0.3, at: vm.Vector3(0, 1.4, _z));
      worldPose(p);
      final lx = side * (_pressX + 0.62), ly = _tableY + 0.62 - 0.14 * stamp[s];
      kit.crew.aim(p, s == 0 ? 0 : 1, world(lx, ly, _z));
      kit.figures.draw(_clerks[s], p);
      pbox(lx, ly - 0.1, _z, 0.04, 0.24, 0.04, Vignette.c(0x2B2E33));
      pcyl(lx, ly + 0.02, _z, 0.03, 0.08, Vignette.c(_colors[s]));
    }
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From the plaza's edge across the street, then in at the doorway on
    // the presses and the pair on show.
    final k = smooth(0.3, 2.0, u);
    return Shot(
      vm.Vector3(lerp(2.4, 0.0, k), lerp(4.4, 2.35, k), lerp(-9.5, -0.6, k)),
      vm.Vector3(lerp(0.3, 0.0, k), lerp(3.2, 2.1, k), lerp(1.0, _z, k)),
      fov: lerp(52, 54, k),
      settle: 1.1,
      drift: 0.35,
    );
  }
}
