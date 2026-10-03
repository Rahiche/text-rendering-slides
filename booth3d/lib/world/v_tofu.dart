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
  String get kick => '豆腐屋 · FONT FALLBACK';
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

  /// Each ask: when the courier gets to kiosk k (and how long it takes).
  static const _ask = 1.7, _hop = 1.25;
  static double _at(int k) => 0.2 + k * (_ask + _hop);

  /// The tofu: when the courier gets to the shop, when the tofu's in the
  /// crate, when they set off round the back.
  static final _toShop = _at(3) + _ask, _atShop = _toShop + 1.5, _tofuIn = _atShop + 2.2, _show = _tofuIn + 0.3, _leave = _tofuIn + 2.4;

  /// Round the back to the start, then ب: kiosk 0 (✕), kiosk 1 (✓), back
  /// to the start.
  static final _back = Walk(
    [
      vm.Vector3(_shopX - 0.3, 0, _shopZ),
      vm.Vector3(_shopX + 1.6, 0, _stopZ + 0.2),
      vm.Vector3(_shopX + 1.6, 0, 2.1),
      vm.Vector3(-6.2, 0, 2.1),
      vm.Vector3(-6.2, 0, _stopZ),
    ],
    _leave,
    1.5,
  );
  static final _again = _back.end + 0.6;
  static double _at2(int k) => _again + 1.4 + k * (_ask + _hop);
  static final _found = _at2(1) + _ask, _home = _found + 1.2;
  static final _loop = _home + 3.4;

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
    ('豆腐屋 TOFU .notdef U+0378 U+0628 ب', const TextStyle(fontFamily: BP.display, fontFamilyFallback: [BP.arabic])),
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

    // The courier, the four keepers in their fonts' colours, the tofu maker.
    _people.add(person(_look(top: 0x2E5E4E, legs: 0x1E2B40, cap: 0x1F3D33)));
    for (var k = 0; k < 4; k++) {
      _people.add(person(_look(top: 0xF2F0EA, legs: 0x2B3442, layer: _fonts[k].$3, slim: k.isOdd)));
    }
    _people.add(person(_look(top: 0xF4F2EC, legs: 0x3A4252, skirt: 0xF4F2EC, cap: 0xFFFFFF)));
    _ready = true;
  }

  static FigureLook _look({required int top, required int legs, int? cap, int? layer, int? skirt, bool slim = false}) {
    final l = FigureLook()
      ..top = rgbHex(top)
      ..legs = rgbHex(legs)
      ..shoes = rgbHex(0x1B1C20)
      ..skin = rgbHex(slim ? 0xE8C6AC : 0xE0BB9E)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = slim ? Hair.bob : Hair.short
      ..slim = slim;
    if (cap != null) l.cap = rgbHex(cap);
    if (layer != null) l.layer = rgbHex(layer);
    if (skirt != null) {
      l
        ..skirt = rgbHex(skirt)
        ..skirtLength = 1.1;
    }
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
        // The noren: three panels of navy, 豆腐 in white.
        final w = s.width / 3;
        for (var i = 0; i < 3; i++) {
          c.drawRect(Rect.fromLTWH(i * w + 3, 0, w - 6, s.height), Paint()..color = const Color(0xFF1E2A4A));
        }
        Vignette.text(c, '豆 腐', Rect.fromLTWH(0, 0, s.width * 0.7, s.height * 0.95), s.height * 0.62, const Color(0xFFF4F1EA), lang: 'ja');
        Vignette.text(c, '.notdef', Rect.fromLTWH(s.width * 0.67, s.height * 0.3, s.width * 0.32, s.height * 0.5), s.height * 0.22, const Color(0xFFF4F1EA));
      }, glow: 0.3),
      sign(1.9, 0.4, vm.Matrix4.translation(vm.Vector3(_shopX, 3.18, _counterZ - 0.1)), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4EBD8));
        Vignette.text(c, '豆腐屋 · TOFU · □', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.6, const Color(0xFF8E2A1E), lang: 'ja');
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
    // Where the courier is, and the ask going on (kiosk, its start, which
    // code point).
    var ask = -1, askAt = 0.0, second = false;
    if (u < _toShop) {
      final k = ((u - 0.2) / (_ask + _hop)).floor().clamp(0, 3);
      final a = _at(k);
      if (u < a + _ask) {
        ask = k;
        askAt = a;
        courier.pos.setValues(_kx[k], 0, _stopZ);
        Idle.stand(courier, t, Manner.of(101), look: 0.3);
        courier.yaw = math.pi;
      } else {
        _walkBetween(courier, _kx[k], k < 3 ? _kx[k + 1] : _shopX - 0.3, a + _ask, k < 3 ? _at(k + 1) : _atShop, u, z1: k < 3 ? _stopZ : _shopZ);
      }
    } else if (u < _atShop) {
      _walkBetween(courier, _kx[3], _shopX - 0.3, _toShop, _atShop, u, z1: _shopZ);
    } else if (u < _leave) {
      // The tofu in the crate: turning round to show it (□, 0378).
      courier.pos.setValues(_shopX - 0.3, 0, _shopZ);
      Idle.stand(courier, t, Manner.of(101), look: 0.2);
      courier.yaw = math.pi * (1 - smooth(_show, _show + 0.6, u) * (1 - smooth(_leave - 0.5, _leave, u)));
    } else if (u < _again) {
      _back.pose(courier, u, 101);
    } else if (u < _found) {
      second = true;
      final first = u < _at2(1);
      final a = first ? _at2(0) : _at2(1);
      if (u < _at2(0)) {
        _walkBetween(courier, -6.2, _kx[0], _again, _at2(0), u);
      } else if (u < a + _ask) {
        ask = first ? 0 : 1;
        askAt = a;
        courier.pos.setValues(_kx[ask], 0, _stopZ);
        Idle.stand(courier, t, Manner.of(101), look: 0.3);
        courier.yaw = math.pi;
      } else {
        _walkBetween(courier, _kx[0], _kx[1], _at2(0) + _ask, _at2(1), u);
      }
    } else if (u < _home) {
      second = true;
      courier.pos.setValues(_kx[1], 0, _stopZ);
      Idle.stand(courier, t, Manner.of(101), look: 0.2);
      courier.yaw = math.pi;
    } else {
      second = true;
      // (Back to the first kiosk: where the next turn starts.)
      _walkBetween(courier, _kx[1], _kx[0], _home, _loop - 0.2, u);
    }
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
    // The keepers: minding their kiosks; asked, a turn to the shelf, a hand
    // along it, back; a shake of the head, or the glyph handed over.
    for (var k = 0; k < 4; k++) {
      final p = _poses[1 + k]..rest();
      p.pos.setValues(_kx[k], 0, _keeperZ);
      final asked = ask == k ? u - askAt : -1.0;
      final has = second && k == 1;
      _keeper(p, k, asked, has, t);
      // The lamp on the counter: red for no, green for yes.
      final lit = asked < 0 ? 0.0 : smooth(1.05, 1.2, asked) * (1 - smooth(_ask - 0.1, _ask + 0.4, asked));
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
      // The shelf being searched: a light running along its rows.
      if (asked > 0.55 && asked < 1.15) {
        final f = seg(asked, 0.55, has ? 0.95 : 1.15);
        final cell = has ? 1 + (f * 1).floor() : (f * 24).floor().clamp(0, 23);
        final cx = _kx[k] - 0.64 + 0.256 * (cell % 6), cy2 = 2.07 - 0.345 * (cell ~/ 6);
        pglow(cx, cy2, _shelfZ + 0.04, 0.24, 0.33, 0.01, has && f >= 1 ? vm.Vector4(0.3, 2.2, 0.8, 1) : vm.Vector4(1.6, 1.4, 0.6, 1));
      }
      // ب off the shelf, over the counter, into the crate.
      if (has && asked >= 0) {
        final f = seg(asked, 1.0, 1.6);
        if (asked < 1.0) {
          put(_beh[0], 0, 0, 0, s: 0);
        } else {
          final sx = _kx[1] - 0.64 + 0.256 * 1, sy = 2.07, sz = _shelfZ - 0.05;
          final e = eio(f);
          put(_beh[0], lerp(sx, _crate.x, e), lerp(sy, _crate.y + 0.12, e) + 0.35 * math.sin(math.pi * e), lerp(sz, _crate.z, e));
        }
      }
    }
    if (!(second && (u >= _at2(1) + 1.0))) {
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
      if (ts < 2.2) {
        m.lean += 0.32 * math.sin(math.pi * c01(ts / 2.2));
        _a.setValues(tofuX - 0.13, tofuY, tofuZ);
        _b.setValues(tofuX + 0.13, tofuY, tofuZ);
        worldPose(m);
        kit.crew.aim(m, 0, world(_a.x, _a.y, _a.z));
        kit.crew.aim(m, 1, world(_b.x, _b.y, _b.z));
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
    final showTofu = !second && u >= _atShop + 0.3 && u < _again;
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

  /// Walks [p] along the stops' line from x [x0] to [x1] over [a]–[b] (to
  /// [z1] off it, at the end).
  void _walkBetween(FigurePose p, double x0, double x1, double a, double b, double u, {double z1 = _stopZ}) {
    final f = seg(u, a, b), dz = z1 - _stopZ, d = math.sqrt((x1 - x0) * (x1 - x0) + dz * dz);
    p.pos.setValues(lerp(x0, x1, eio(f)), 0, lerp(_stopZ, z1, eio(f)));
    if (f <= 0 || f >= 1) {
      Idle.stand(p, u, Manner.of(101));
      p.yaw = math.pi;
      return;
    }
    final m = Manner.of(101), speed = d / math.max(b - a, 0.1);
    Gait.walk(p, Gait.phaseOver(d * eio(f), d, speed, 1, m), speed, m);
    p.yaw = math.atan2(-(x1 - x0), -dz);
  }

  /// Keeper [k] ([asked] seconds into an ask, or < 0; [has]: the font has
  /// it).
  void _keeper(FigurePose p, int k, double asked, bool has, double t) {
    final m = Manner.of(110 + k);
    Idle.stand(p, t, m, look: asked < 0 ? 0.8 : 0.1, fidget: asked < 0 ? 0.4 : 0);
    if (asked < 0) {
      p.yaw = Idle.facing(t, m, 0.35);
      draw(_people[1 + k], p);
      return;
    }
    // Round to the shelf and back.
    final away = smooth(0.15, 0.5, asked) * (1 - smooth(1.05, 1.35, asked));
    p.yaw = math.pi * away;
    if (away > 0.6) {
      // A hand along the shelf.
      final f = seg(asked, 0.55, has ? 0.95 : 1.15);
      final cell = has ? 1 : (f * 6).floor().clamp(0, 5);
      worldPose(p);
      kit.crew.aim(p, 1, world(_kx[k] - 0.64 + 0.256 * (cell % 6), 2.07 - 0.345 * (f * 4).floor().clamp(0, 3) * (has ? 0 : 1), _shelfZ - 0.05));
      kit.figures.draw(_people[1 + k], p);
      return;
    }
    if (asked > 1.25) {
      if (has) {
        // Here it is: both hands to the crate.
        p.armPitch[0] = p.armPitch[1] = lerp(0.1, 1.2, smooth(1.25, 1.5, asked));
        p.armRoll[0] = p.armRoll[1] = -0.2;
      } else {
        // No: a shake of the head, palms up.
        final no = smooth(1.25, 1.4, asked) * (1 - smooth(_ask - 0.15, _ask + 0.2, asked));
        p.headYaw += 0.38 * math.sin((asked - 1.25) * 17) * no;
        p.armPitch[0] = p.armPitch[1] = lerp(0.1, 0.75, no);
        p.armRoll[0] = p.armRoll[1] = lerp(0.12, 0.55, no);
      }
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
