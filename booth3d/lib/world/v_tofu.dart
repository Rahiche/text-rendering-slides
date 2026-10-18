import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'shot.dart';
import 'vignette.dart';
import 'walk.dart';

/// 豆腐屋 · Font fallback, in the park past the alley (on the left of the
/// long path): four fonts' kiosks in a row — Space Grotesk, Noto Kufi
/// Arabic, Noto Sans JP, Noto Color Emoji — each with its cmap on the shelf
/// behind the counter, and at the end of the row the tofu shop.
///
/// A courier brings a code point in a crate and asks each font in turn:
/// the keeper turns to the shelf, runs a hand along it, and turns back with
/// a shake of the head (✕), until one has it (✓: the glyph comes off the
/// shelf into the crate) — or none does, and the tofu maker cuts a tofu: □,
/// the code point's hex on its face (.notdef, the box a font draws for a
/// character it hasn't got). First U+0378 (no one's: tofu), then, round
/// the back of the row and in again, ب U+0628 (the second font's).
class TofuShop extends Vignette {
  TofuShop(super.kit);

  @override
  String get name => 'tofu';
  @override
  String get kick => 'FONT FALLBACK';
  @override
  String get line => 'U+0378: no font has it';
  @override
  String get note => 'each font is asked in turn; then .notdef, the tofu □';

  @override
  double get loop => _loop;
  @override
  double get visit => _leave - 0.2;

  @override
  final frame = trs(vm.Vector3(-6.6, 0, 48.5), rotY: -math.pi / 2);

  // ── The row ───────────────────────────────────────────────────────────────

  /// The kiosks' middles (x), the tofu shop's; the counters' fronts (z),
  /// where the keepers stand, where the courier stops, the shelves.
  static const _kx = [-4.2, -2.1, 0.0, 2.1], _shopX = 4.6;
  static const _counterZ = -0.35, _keeperZ = 0.45, _stopZ = -1.15, _shelfZ = 0.9;

  /// Where the courier stands at the tofu shop: up at its counter (the
  /// crate held out over it).
  static const _shopZ = -0.66;

  static const _fonts = [
    ('Space Grotesk', 'Aa', 0xF2B13A),
    ('Noto Kufi Arabic', 'خط', 0x3FA37A),
    ('Noto Sans JP', 'あ字', 0xE8505F),
    ('Noto Color Emoji', '😀', 0x6C8EE0),
  ];

  /// What each cmap shelf shows (its glyphs, in a grid).
  static const _shelves = [
    'ABCDEFGHIJKLMNOPQRSTUVWX',
    'ابتثجحخدذرزسشصضطظعغفقكلم',
    'あいうえおかきくけこさし文字日本語漢東京花山川',
    '😀😃😄😁😆😅🙂😉😊😇🥰😍🤩😘😋😛😜🤪😎🤓🧐🤔🤗🤭',
  ];

  // ── The timeline (seconds into a turn) ────────────────────────────────────

  /// Each ask: when the courier gets to kiosk k; how long the ask takes,
  /// and the walk on to the next (an easy pace, picked up and slowed to a
  /// stop).
  static const _ask = 2.0, _hop = 1.8;
  static double _at(int k) => 0.2 + k * (_ask + _hop);

  /// The tofu: when the courier sets off for the shop and gets there, when
  /// the tofu's in the crate, when they turn round with it, when they set
  /// off round the back.
  static final _toShop = _at(3) + _ask, _atShop = _toShop + 1.9, _tofuIn = _atShop + 2.2, _show = _tofuIn + 0.3, _leave = _tofuIn + 2.4;

  /// Where the courier stops at kiosk [x] (or elsewhere on the path).
  static vm.Vector3 _stop(double x, [double z = _stopZ]) => vm.Vector3(x, 0, z);

  /// A walk along [pts] from [a] to [b], ending facing the counters.
  static Walk _walk(List<vm.Vector3> pts, double a, double b) => Walk(pts, a, Walk.lengthOf(pts) / (b - a), face: math.pi);

  /// Round the back of the row to the start and in to the first kiosk
  /// again; behind the row ([_swap]) the crate's label becomes ب's.
  static final _back = Walk(
    [
      vm.Vector3(_shopX - 0.3, 0, _shopZ),
      vm.Vector3(_shopX + 1.6, 0, _stopZ + 0.2),
      vm.Vector3(_shopX + 1.6, 0, 2.1),
      vm.Vector3(-6.2, 0, 2.1),
      vm.Vector3(-6.2, 0, _stopZ),
      _stop(_kx[0]),
    ],
    _leave,
    1.5,
    face: math.pi,
  );
  static final _swap = (_back.at(2) + _back.at(3)) / 2;

  /// Then ب: kiosk 0 (✕), kiosk 1 (✓); back to the first kiosk, where the
  /// next turn starts.
  static double _at2(int k) => _back.end + 0.2 + k * (_ask + _hop);
  static final _found = _at2(1) + _ask, _home = _found + 1.2;
  static final _loop = _home + 3.4;

  /// The courier's walks in turn; before walk i they stand (stand i) at a
  /// kiosk or the shop.
  static final _walks = [
    for (var k = 0; k < 3; k++) _walk([_stop(_kx[k]), _stop(_kx[k + 1])], _at(k) + _ask, _at(k + 1)),
    _walk([_stop(_kx[3]), _stop(_shopX - 0.3, _shopZ)], _toShop, _atShop),
    _back,
    _walk([_stop(_kx[0]), _stop(_kx[1])], _at2(0) + _ask, _at2(1)),
    _walk([_stop(_kx[1]), _stop(_kx[0])], _home, _loop - 0.5),
  ];

  // ── Building ──────────────────────────────────────────────────────────────

  final _people = <int>[];
  final _poses = List.generate(6, (_) => FigurePose());
  late final List<Glyph3D> _beh;
  late final Node _tofuFace, _label0378, _label0628;
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [
    for (final (n, s, _) in _fonts) ('$n $s', const TextStyle(fontFamily: BP.display)),
    for (final s in _shelves) (s, const TextStyle(fontFamily: BP.display)),
    ('TOFU SHOP .notdef U+0378 U+0628 ب', const TextStyle(fontFamily: BP.display, fontFamilyFallback: [BP.arabic])),
  ];

  @override
  Future<void> init() async {
    makePool(boxes: 40, glows: 24);
    final b = Batch();
    final timber = pbr(rgb(1, 1, 1), roughness: 0.8);
    final dark = Vignette.c(0x26282E), wood = Vignette.c(0xB98A5A), post = Vignette.c(0x4A3426), white = Vignette.c(0xF2EFE8);
    for (var k = 0; k < 4; k++) {
      final x = _kx[k], col = Vignette.c(_fonts[k].$3);
      // The counter (its top, a band of the font's colour), the posts, the
      // shelf's frame, the awning sloping down to the front.
      box(b, timber, 1.7, 0.95, 0.6, x, 0.475, _counterZ + 0.3, dark);
      box(b, timber, 1.82, 0.05, 0.74, x, 0.975, _counterZ + 0.3, wood);
      box(b, timber, 1.72, 0.2, 0.02, x, 0.74, _counterZ - 0.01, col);
      for (final dx in [-0.86, 0.86]) {
        box(b, timber, 0.08, 2.55, 0.08, x + dx, 1.275, _counterZ + 0.05, post);
        box(b, timber, 0.08, 2.55, 0.08, x + dx, 1.275, _shelfZ + 0.12, post);
      }
      box(b, timber, 1.66, 1.5, 0.05, x, 1.55, _shelfZ + 0.12, dark);
      for (var r = 0; r < 4; r++) {
        box(b, timber, 1.6, 0.03, 0.2, x, 0.88 + 0.36 * r, _shelfZ, wood);
      }
      for (var s = 0; s < 4; s++) {
        box(b, timber, 0.46, 0.06, 1.6, x - 0.69 + 0.46 * s, 2.62, 0.4, s.isEven ? col : white, rotX: -0.16);
      }
    }
    // The tofu shop: wider, a noren over its front, a tank of water on the
    // counter with tofu in it.
    box(b, timber, 2.3, 0.95, 0.7, _shopX, 0.475, _counterZ + 0.35, Vignette.c(0x3A3F48));
    box(b, timber, 2.42, 0.05, 0.84, _shopX, 0.975, _counterZ + 0.35, wood);
    for (final dx in [-1.15, 1.15]) {
      box(b, timber, 0.1, 2.9, 0.1, _shopX + dx, 1.45, _counterZ + 0.02, post);
      box(b, timber, 0.1, 2.9, 0.1, _shopX + dx, 1.45, _shelfZ + 0.3, post);
    }
    box(b, timber, 2.3, 1.9, 0.05, _shopX, 1.85, _shelfZ + 0.32, Vignette.c(0xE9E2D2));
    box(b, timber, 2.5, 0.1, 1.5, _shopX, 2.92, 0.45, Vignette.c(0x2B2F3A));
    box(b, timber, 0.96, 0.16, 0.56, _shopX + 0.5, 1.08, _counterZ + 0.32, Vignette.c(0x6E7F8C));
    box(b, timber, 0.88, 0.02, 0.48, _shopX + 0.5, 1.155, _counterZ + 0.32, Vignette.c(0x3F6F8A));
    b.buildInto(detail, 'tofu row', castsShadows: false, lightChannelMask: 0x01);

    await Future.wait([_signs(), _letters()]);

    // The courier in their company's green, the four keepers in their
    // fonts' colours, the tofu maker in white.
    _people.add(person(_look(top: 0x2E5E4E, legs: 0x1E2B40, cap: 0x1F3D33, wear: 'casual_m4')));
    for (var k = 0; k < 4; k++) {
      _people.add(person(_look(top: _fonts[k].$3, legs: 0x2B3442, slim: k.isOdd, wear: k.isOdd ? 'casual_f4' : 'casual_m4')));
    }
    _people.add(person(_look(top: 0xF4F2EC, legs: 0x3A4252, cap: 0xFFFFFF, wear: 'casual_m4')));
    _ready = true;
  }

  static FigureLook _look({required int top, required int legs, required String wear, int? cap, bool slim = false}) {
    final l = FigureLook()
      ..wear = wear
      ..atWork = true
      ..top = rgbHex(top)
      ..legs = rgbHex(legs)
      ..shoes = rgbHex(0x1B1C20)
      ..skin = rgbHex(slim ? 0xE8C6AC : 0xE0BB9E)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = slim ? Hair.bob : Hair.short
      ..slim = slim;
    if (cap != null) l.cap = rgbHex(cap);
    return l;
  }

  Future<void> _signs() async {
    final ink = const Color(0xFF14203A);
    await Future.wait([
      for (var k = 0; k < 4; k++) ...[
        // The font's name over its kiosk, and its cmap on the shelf.
        sign(1.74, 0.46, vm.Matrix4.translation(vm.Vector3(_kx[k], 2.98, _counterZ - 0.02)), (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = Color(0xFF000000 | _fonts[k].$3));
          Vignette.text(c, _fonts[k].$1, Rect.fromLTWH(0, s.height * 0.08, s.width * 0.7, s.height * 0.84), s.height * 0.34, ink);
          Vignette.text(c, _fonts[k].$2, Rect.fromLTWH(s.width * 0.7, 0, s.width * 0.28, s.height), s.height * 0.6, ink, lang: k == 2 ? 'ja' : null);
        }),
        sign(
          1.54,
          1.38,
          vm.Matrix4.translation(vm.Vector3(_kx[k], 1.55, _shelfZ + 0.08)),
          (c, s) {
            c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF20232B));
            final g = _shelves[k].characters.toList();
            const cols = 6, rows = 4;
            for (var i = 0; i < math.min(g.length, cols * rows); i++) {
              final r = Rect.fromLTWH(s.width * (i % cols) / cols, s.height * (i ~/ cols) / rows, s.width / cols, s.height / rows).deflate(6);
              c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = const Color(0xFFF4EFE4));
              Vignette.text(c, g[i], r, r.height * 0.62, ink, lang: k == 2 ? 'ja' : null, weight: FontWeight.w600);
            }
          },
          glow: 0.15,
          thick: 0.02,
        ),
      ],
      sign(2.3, 0.62, vm.Matrix4.translation(vm.Vector3(_shopX, 2.5, _counterZ - 0.06)), (c, s) {
        // The noren: three panels of navy, TOFU in white.
        final w = s.width / 3;
        for (var i = 0; i < 3; i++) {
          c.drawRect(Rect.fromLTWH(i * w + 3, 0, w - 6, s.height), Paint()..color = const Color(0xFF1E2A4A));
        }
        Vignette.text(c, 'TOFU', Rect.fromLTWH(0, 0, s.width * 0.7, s.height * 0.95), s.height * 0.5, const Color(0xFFF4F1EA));
        Vignette.text(c, '.notdef', Rect.fromLTWH(s.width * 0.67, s.height * 0.3, s.width * 0.32, s.height * 0.5), s.height * 0.22, const Color(0xFFF4F1EA));
      }, glow: 0.3),
      sign(1.9, 0.4, vm.Matrix4.translation(vm.Vector3(_shopX, 3.18, _counterZ - 0.1)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4EBD8));
        Vignette.text(c, 'TOFU SHOP · □', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.6, const Color(0xFF8E2A1E), lang: 'ja');
      }),
    ]);
    // The tofu's face (the .notdef box: the code point's hex), and the
    // crate's two labels.
    _tofuFace = await sign(
      0.2,
      0.2,
      vm.Matrix4.identity(),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFFFFF));
        c.drawRect(
          (Offset.zero & s).deflate(s.width * 0.12),
          Paint()
            ..color = const Color(0xFF1E2230)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.width * 0.05,
        );
        Vignette.text(c, '03', Rect.fromLTWH(0, s.height * 0.2, s.width, s.height * 0.3), s.height * 0.26, const Color(0xFF1E2230), family: 'monospace');
        Vignette.text(c, '78', Rect.fromLTWH(0, s.height * 0.5, s.width, s.height * 0.3), s.height * 0.26, const Color(0xFF1E2230), family: 'monospace');
      },
      px: 256,
      glow: 0.2,
      thick: 0.004,
    );
    Future<Node> label(String s1) => sign(
      0.3,
      0.1,
      vm.Matrix4.identity(),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4EBD8));
        Vignette.text(c, s1, Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.62, const Color(0xFF14203A));
      },
      px: 384,
      glow: 0.2,
      thick: 0.004,
    );
    _label0378 = await label('U+0378');
    _label0628 = await label('U+0628');
    for (final n in [_tofuFace, _label0378, _label0628]) {
      n.visible = false;
    }
  }

  Future<void> _letters() async {
    final mat = pbr(Vignette.c(0x3FA37A), roughness: 0.4, emissive: Vignette.c(0x3FA37A), emissiveStrength: 0.2);
    _beh = await letters(
      [('ب', const TextStyle(fontFamily: BP.arabic, fontSize: 160, fontWeight: FontWeight.w700))],
      mat,
      unitsPerPx: 0.26 / 160,
      depth: 0.05,
    );
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero(), _crate = vm.Vector3.zero(), _tank = vm.Vector3.zero();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    final courier = _poses[0]..rest();
    _courier(courier, u, t);
    final second = u >= _swap;
    // The crate, held in front.
    final fwdX = -math.sin(courier.yaw), fwdZ = -math.cos(courier.yaw);
    // (Held out over the shop's counter for the tofu.)
    final over = smooth(_atShop - 0.2, _atShop + 0.3, u) * (1 - smooth(_show, _show + 0.4, u));
    _crate.setValues(courier.pos.x + fwdX * (0.36 + 0.08 * over), 1.0 + 0.2 * over, courier.pos.z + fwdZ * (0.36 + 0.08 * over));
    final cy = courier.yaw;
    pbox(_crate.x, _crate.y - 0.07, _crate.z, 0.3, 0.2, 0.3, Vignette.c(0xB98A5A), yaw: cy);
    final label = second ? _label0628 : _label0378;
    (second ? _label0378 : _label0628).visible = false;
    label.visible = true;
    _faceCamera(label, _crate.x, _crate.y - 0.1, _crate.z - 0.153);
    // The keepers: minding their kiosks; the courier coming, an eye on
    // them; asked, round to the shelf, a hand along it, back; a shake of
    // the head, or the glyph handed over.
    for (var k = 0; k < 4; k++) {
      final p = _poses[1 + k]..rest();
      p.pos.setValues(_kx[k], 0, _keeperZ);
      final asked = _askedAt(k, u), a = asked ?? -9.0;
      final has = second && k == 1;
      _keeper(p, k, a, has, t);
      // The lamp on the counter: red for no, green for yes.
      final lit = smooth(1.3, 1.45, a) * (1 - smooth(_ask - 0.1, _ask + 0.4, a));
      final col = has ? vm.Vector4(0.25, 2.6, 0.9, 1) : vm.Vector4(2.8, 0.25, 0.2, 1);
      pglow(
        _kx[k] + 0.7,
        1.08,
        _counterZ + 0.1,
        0.12,
        0.12,
        0.12,
        lit > 0 ? vm.Vector4(col.x * lit + 0.08, col.y * lit + 0.08, col.z * lit + 0.08, 1) : vm.Vector4(0.08, 0.08, 0.09, 1),
      );
      if (lit > 0.02) _mark(_kx[k], 1.78, _counterZ - 0.25, has, lit);
      // The shelf being searched: a light running along its rows, where
      // the hand is.
      if (a > 0.6 && a < (has ? 0.95 : 1.05)) {
        final (col6, row) = _search(seg(a, 0.6, has ? 0.85 : 1.0), has);
        final cx = _kx[k] - 0.64 + 0.256 * col6.round(), cy2 = 2.07 - 0.345 * row.round();
        pglow(cx, cy2, _shelfZ + 0.04, 0.24, 0.33, 0.01, has && a >= 0.85 ? vm.Vector4(0.3, 2.2, 0.8, 1) : vm.Vector4(1.6, 1.4, 0.6, 1));
      }
      // ب off the shelf, over the counter, into the crate.
      if (has && asked != null && a >= 0) {
        if (a < 0.95) {
          put(_beh[0], 0, 0, 0, s: 0);
        } else {
          final sx = _kx[1] - 0.64 + 0.256, sy = 2.07, sz = _shelfZ - 0.05;
          final e = eio(seg(a, 0.95, 1.5));
          put(_beh[0], lerp(sx, _crate.x, e), lerp(sy, _crate.y + 0.12, e) + 0.35 * math.sin(math.pi * e), lerp(sz, _crate.z, e));
        }
      }
    }
    if (!(second && u >= _at2(1) + 0.95)) {
      put(_beh[0], 0, 0, 0, s: 0);
    } else if (u >= _found) {
      // In the crate, standing up in it.
      put(_beh[0], _crate.x, _crate.y + 0.12, _crate.z);
    }
    // The tofu maker: lifts a tofu out of the water, turns, sets it in the
    // crate.
    final m = _poses[5]..rest();
    m.pos.setValues(_shopX + 0.3, 0, _keeperZ + 0.06);
    Idle.stand(m, t, Manner.of(106), look: 0.6);
    final ts = u - _atShop;
    final tank = _tank..setValues(_shopX + 0.5, 1.2, _counterZ + 0.32);
    double tofuX = tank.x, tofuY = 1.17, tofuZ = tank.z;
    if (!second && ts >= 0 && ts < 3.2) {
      final lift = smooth(0.3, 0.9, ts), over = eio(seg(ts, 1.0, 1.9));
      tofuX = lerp(tank.x, _crate.x, over);
      tofuY = lerp(1.17, _crate.y + 0.07, over) + 0.25 * lift * (1 - over) + 0.1 * math.sin(math.pi * over);
      tofuZ = lerp(tank.z, _crate.z, over);
      // (Hands to it and off it again, not at once.)
      final hands = smooth(0, 0.35, ts) * (1 - smooth(1.9, 2.3, ts));
      if (hands > 0) {
        m.lean += 0.32 * math.sin(math.pi * c01(ts / 2.3));
        _a.setValues(tofuX - 0.13, tofuY, tofuZ);
        _b.setValues(tofuX + 0.13, tofuY, tofuZ);
        worldPose(m);
        kit.crew.aimBy(m, 0, world(_a.x, _a.y, _a.z), hands);
        kit.crew.aimBy(m, 1, world(_b.x, _b.y, _b.z), hands);
        kit.figures.draw(_people[5], m);
      } else {
        draw(_people[5], m);
      }
    } else {
      draw(_people[5], m);
    }
    final inCrate = !second && u >= _atShop + 1.9;
    if (inCrate) {
      tofuX = _crate.x;
      tofuY = _crate.y + 0.07;
      tofuZ = _crate.z;
    }
    final showTofu = !second && u >= _atShop + 0.3;
    if (showTofu) {
      pbox(tofuX, tofuY, tofuZ, 0.2, 0.14, 0.2, Vignette.c(0xFFFFFF));
      _tofuFace.visible = true;
      _faceCamera(_tofuFace, tofuX, tofuY, tofuZ - 0.102, s: 0.66);
    } else {
      _tofuFace.visible = false;
    }
    // A few tofu waiting in the tank.
    for (var i = 0; i < 3; i++) {
      pbox(_shopX + 0.25 + 0.24 * i, 1.15, _counterZ + 0.32, 0.18, 0.08, 0.18, Vignette.c(0xFAFAF6));
    }
    // The courier, with the crate in both hands.
    worldPose(courier);
    final side = vm.Vector3(math.cos(cy), 0, -math.sin(cy));
    kit.crew.aim(courier, 0, world(_crate.x - side.x * 0.18, _crate.y, _crate.z - side.z * 0.18));
    kit.crew.aim(courier, 1, world(_crate.x + side.x * 0.18, _crate.y, _crate.z + side.z * 0.18));
    kit.figures.draw(_people[0], courier);
    pool.end();
  }

  /// Which way the courier faces standing before walk [i] (at [u]): the
  /// counter; at the shop, round to show the tofu once it's in the crate.
  static double _standFace(int i, double u) => i == 4 ? math.pi * (1 - smooth(_show, _show + 0.6, u)) : math.pi;

  /// [a] turned [k] of the way to [b], the short way round.
  static double _towards(double a, double b, double k) {
    var d = (b - a) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return a + d * k;
  }

  /// Poses the courier at [u]: walking (turning into a walk as they set
  /// off and out of it as they stop, never round on the spot in a frame)
  /// or standing.
  void _courier(FigurePose p, double u, double t) {
    var i = 0;
    while (i < _walks.length && u >= _walks[i].end) {
      i++;
    }
    final next = i < _walks.length ? _walks[i] : null, last = i > 0 ? _walks[i - 1] : _walks.last;
    if (next != null && u >= next.start) {
      next.pose(p, u, 101);
      final yaw = _towards(_standFace(i, next.start), next.headingAt(u), smooth(next.start - 0.25, next.start + 0.45, u));
      p.yaw = _towards(yaw, _standFace(i + 1, next.end), smooth(next.end - 0.45, next.end + 0.25, u));
      return;
    }
    final at = last.last;
    p.pos.setValues(at.x, 0, at.z);
    Idle.stand(p, t, Manner.of(101), look: 0.3);
    var yaw = _standFace(i, u);
    if (i > 0) yaw = _towards(last.headingAt(last.end), yaw, smooth(last.end - 0.45, last.end + 0.25, u));
    if (next != null) yaw = _towards(yaw, next.headingAt(next.start), smooth(next.start - 0.25, next.start + 0.45, u));
    p.yaw = yaw;
  }

  /// How far into an ask at keeper [k]'s kiosk the turn is at [u], from a
  /// little before the courier comes up to a little after they've gone
  /// (null: none near).
  static double? _askedAt(int k, double u) {
    for (final a in [_at(k), if (k < 2) _at2(k), if (k == 0) _loop + _at(0)]) {
      if (u > a - 1.2 && u < a + _ask + 1.4) return u - a;
    }
    return null;
  }

  /// Where the search is on the shelf [f] (0..1) of the way: along its
  /// rows in turn, back and forth, top to bottom (column, row; fractional
  /// in between); straight to ب's place when the font has it.
  static (double, double) _search(double f, bool has) {
    if (has) return (1, 0);
    final r = f * 4, row = math.min(r.floor(), 3), along = r - row;
    final x = math.min(along / 0.85, 1.0) * 5;
    return (row.isEven ? x : 5 - x, row + (row < 3 ? smooth(0.85, 1.0, along) : 0));
  }

  /// Keeper [k], [a] seconds from the start of an ask (negative: the
  /// courier on the way; far below: none near); [has]: the font has it.
  void _keeper(FigurePose p, int k, double a, bool has, double t) {
    final m = Manner.of(110 + k);
    // An eye on the courier from as they come up until they've gone.
    final on = smooth(-0.8, -0.1, a) * (1 - smooth(_ask + 0.3, _ask + 1.1, a));
    Idle.stand(p, t, m, look: lerp(0.8, 0.15, on), fidget: 0.4 * (1 - on));
    // Round to the shelf and back (as quick as a person turns).
    final away = smooth(0.1, 0.6, a) * (1 - smooth(1.0, 1.45, a));
    p.yaw = Idle.facing(t, m, 0.35) * (1 - on) + math.pi * away;
    if (away > 0.02) {
      // A hand along the shelf, where the light is.
      final (col6, row) = _search(seg(a, 0.6, has ? 0.85 : 1.0), has);
      worldPose(p);
      kit.crew.aimBy(p, 1, world(_kx[k] - 0.64 + 0.256 * col6, 2.07 - 0.345 * row, _shelfZ - 0.05), smooth(0.3, 0.75, away));
      kit.figures.draw(_people[1 + k], p);
      return;
    }
    // Here it is, both hands to the crate; or no: a shake of the head,
    // palms up.
    final give = has ? smooth(1.35, 1.6, a) * (1 - smooth(_ask + 0.2, _ask + 0.7, a)) : 0.0;
    final no = has ? 0.0 : smooth(1.35, 1.55, a) * (1 - smooth(_ask - 0.1, _ask + 0.3, a));
    if (give > 0) {
      p.armPitch[0] = p.armPitch[1] = lerp(p.armPitch[0], 1.2, give);
      p.armRoll[0] = p.armRoll[1] = lerp(p.armRoll[0], -0.2, give);
    } else if (no > 0) {
      p.headYaw += 0.34 * math.sin((a - 1.35) * 15) * no;
      p.armPitch[0] = p.armPitch[1] = lerp(p.armPitch[0], 0.75, no);
      p.armRoll[0] = p.armRoll[1] = lerp(p.armRoll[0], 0.55, no);
    }
    draw(_people[1 + k], p);
  }

  /// A big ✕ (red) or ✓ (green) in light over a counter.
  void _mark(double x, double y, double z, bool yes, double k) {
    final s = 0.85 + 0.15 * k;
    if (yes) {
      final c = vm.Vector4(0.3 * k, 2.4 * k, 0.8 * k, 1);
      pglow(x - 0.07 * s, y - 0.04 * s, z, 0.05 * s, 0.2 * s, 0.03, c, roll: 0.75);
      pglow(x + 0.07 * s, y + 0.03 * s, z, 0.05 * s, 0.36 * s, 0.03, c, roll: -0.6);
    } else {
      final c = vm.Vector4(2.6 * k, 0.25 * k, 0.2 * k, 1);
      pglow(x, y, z, 0.05 * s, 0.4 * s, 0.03, c, roll: 0.785);
      pglow(x, y, z, 0.05 * s, 0.4 * s, 0.03, c, roll: -0.785);
    }
  }

  final _mm = vm.Matrix4.identity();

  /// Board [n] at (x, y, z) of the frame, facing the path (−z).
  void _faceCamera(Node n, double x, double y, double z, {double s = 1}) {
    _mm
      ..setIdentity()
      ..setTranslationRaw(x, y, z)
      ..scaleByDouble(s, s, s, 1);
    n.localTransform = frame * _mm;
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    if (u < _toShop + 0.6) {
      // Along the row with the courier, from the path.
      final f = seg(u, 0, _toShop);
      final x = lerp(_kx[0] - 0.4, _kx[3] + 0.6, f);
      return Shot(vm.Vector3(x - 0.6, 1.85, -6.3), vm.Vector3(x + 0.5, 1.35, 0.2), fov: 42, settle: 1.4, drift: 0.5);
    }
    // In on the tofu: over the courier's shoulder as it's cut, then on the
    // crate as it's shown.
    final show = smooth(_show, _show + 0.8, u);
    return Shot(
      vm.Vector3(lerp(_shopX - 2.3, _shopX - 0.9, show), lerp(2.25, 1.55, show), lerp(-2.4, -3.0, show)),
      vm.Vector3(lerp(_shopX + 0.15, _shopX - 0.3, show), lerp(1.15, 1.05, show), lerp(-0.2, _stopZ, show)),
      fov: 40,
      settle: 0.9,
      drift: 0.35,
    );
  }
}
