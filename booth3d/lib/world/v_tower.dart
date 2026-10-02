import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// ユニコード塔 · Unicode, a tower up the right-hand side street, past the
/// park (beside the street, turned to look down it to the plaza): 128 →
/// 172,808. On a small plinth that is ASCII
/// (1963: 128 characters) stand the bands Unicode added, each as tall as
/// what it brought — 1.0 (1991, about 7,000), 3.0 (1999, 49,194), 6.0
/// (2010, 109,449: the emoji arrive), 18.0 (2026, 172,808: more than 170
/// scripts). A lift climbs its face while the counter on the crown counts
/// up with it, and letters of the world's scripts fall round it like snow.
class UnicodeTower extends Vignette {
  UnicodeTower(super.kit);

  @override
  String get name => 'tower';
  @override
  String get kick => 'ユニコード塔 · UNICODE';
  @override
  String get line => '128 → 172,808 characters';
  @override
  String get note => 'ASCII in 1963; Unicode 18.0 (2026): 170+ scripts';

  @override
  double get loop => 22;
  @override
  double get visit => 13.5;

  @override
  final frame = trs(vm.Vector3(33, 0, 92), rotY: 0.45);

  /// The milestones: year, name, characters, the band's colour.
  static const _marks = [
    (1963, 'ASCII', 128, 0x8C96A8),
    (1991, 'Unicode 1.0', 7000, 0x3A6EA5),
    (1999, 'Unicode 3.0', 49194, 0x2E9C8A),
    (2010, 'Unicode 6.0 · 😀', 109449, 0xE8A33D),
    (2026, 'Unicode 18.0', 172808, 0xE8505F),
  ];

  /// The plinth's height (ASCII), metres a character above it, the shaft's
  /// width.
  static const _plinth = 2.4, _perChar = 30.0 / 172808, _w = 4.6;

  /// Where band [i]'s top is.
  static double _top(int i) => i == 0 ? _plinth : _plinth + _marks[i].$3 * _perChar;

  /// Letters of the world's scripts, falling.
  static const _snow = ['ሀ', 'Ꭰ', 'ᐃ', 'ཀ', 'ක', 'ក', 'က', '龍', 'あ', 'ㅎ', 'ب', 'א', 'Ω', 'Ж', 'क', 'ก', 'ꦲ', 'ᠮ', 'ⴰ', 'ߒ', 'ꕙ', 'Ꮳ', 'ᚠ', 'Ա'];

  late final List<Glyph3D> _flakes;
  bool _ready = false;

  static const _style = TextStyle(fontFamily: BP.display, fontSize: 160, fontWeight: FontWeight.w700);

  @override
  List<(String, TextStyle)> get fontRuns => [(_snow.join(' '), _style), ('ユニコード塔 UNICODE 128 172,808 😀', _style)];

  @override
  Future<void> init() async {
    makePool(boxes: 8, glows: 64);
    final b = Batch();
    final m = pbr(rgb(1, 1, 1), roughness: 0.55, metallic: 0.15);
    final glass = pbr(rgb(1, 1, 1), roughness: 0.15, metallic: 0.4);
    // The plinth (ASCII), then the bands, each a little narrower, a ledge
    // between; windows in rows.
    box(b, m, _w + 1.2, _plinth, _w + 1.2, 0, _plinth / 2, 0, Vignette.c(_marks[0].$4));
    for (var i = 1; i < _marks.length; i++) {
      final y0 = _top(i - 1), y1 = _top(i), w = _w - 0.35 * (i - 1);
      box(b, m, w, y1 - y0 - 0.12, w, 0, (y0 + y1) / 2, 0, Vignette.c(_marks[i].$4));
      box(b, m, w + 0.3, 0.12, w + 0.3, 0, y1 - 0.06, 0, Vignette.c(0xE9E4D6));
      for (var y = y0 + 0.9; y < y1 - 0.6; y += 1.1) {
        for (final s in [-1.0, 1.0]) {
          box(b, glass, w * 0.7, 0.42, 0.04, 0, y, s * w / 2 + s * 0.01, Vignette.c(0x9CC4E0));
          box(b, glass, 0.04, 0.42, w * 0.7, s * w / 2 + s * 0.01, y, 0, Vignette.c(0x9CC4E0));
        }
      }
    }
    // The crown with its counter, a mast.
    final top = _top(_marks.length - 1);
    box(b, m, 3.4, 1.4, 1.2, 0, top + 0.7, -1.2, Vignette.c(0x1E2230));
    // The mast, banded red and white.
    for (var k = 0; k < 6; k++) {
      box(b, m, 0.22 - 0.02 * k, 1.0, 0.22 - 0.02 * k, 0, top + 0.5 + k, 0.4, Vignette.c(k.isEven ? 0xE8505F : 0xF4F1EA));
    }
    // The lift's rails up the front.
    for (final x in [-0.55, 0.55]) {
      box(b, m, 0.08, top - 0.4, 0.08, x, (top - 0.4) / 2 + 0.2, -_w / 2 - 0.5, Vignette.c(0xC9CDD4));
    }
    b.buildInto(shell, 'unicode tower', lightChannelMask: 0x01);
    // The milestones' plates, on each band's front.
    await Future.wait([
      for (var i = 0; i < _marks.length; i++)
        sign(
          3.6,
          0.95,
          vm.Matrix4.translation(vm.Vector3(-0.4, i == 0 ? _plinth * 0.55 : _top(i) - 1.0, -(i == 0 ? _w + 1.2 : _w - 0.35 * (i - 1)) / 2 - 0.03)),
          (c, s) {
            c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF4F1EA));
            c.drawRect(Rect.fromLTWH(0, 0, s.width * 0.04, s.height), Paint()..color = Color(0xFF000000 | _marks[i].$4));
            final (year, what, n, _) = _marks[i];
            Vignette.text(
              c,
              '$year · $what',
              Rect.fromLTWH(s.width * 0.06, s.height * 0.06, s.width * 0.92, s.height * 0.44),
              s.height * 0.32,
              const Color(0xFF14203A),
            );
            Vignette.text(
              c,
              '${i == 1 ? '~' : ''}${_group(n)} characters',
              Rect.fromLTWH(s.width * 0.06, s.height * 0.52, s.width * 0.92, s.height * 0.4),
              s.height * 0.28,
              const Color(0xFF3A4252),
            );
          },
          glow: 0.35,
        ),
      sign(
        5.2,
        1.0,
        vm.Matrix4.translation(vm.Vector3(0, _plinth + 0.75, -_w / 2 - 0.62)),
        (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14203A));
          Vignette.text(c, 'ユニコード塔 · UNICODE', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.5, const Color(0xFFF2C94C), lang: 'ja');
        },
        glow: 0.5,
        shell: true,
      ),
    ]);
    final mat = pbr(Vignette.c(0xF4F1EA), roughness: 0.4, emissive: Vignette.c(0xBFD8FF), emissiveStrength: 0.3);
    _flakes = await letters([for (final s in _snow) (s, _style)], mat, unitsPerPx: 1.1 / 160, depth: 0.1);
    _ready = true;
  }

  static String _group(int n) {
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  /// When the lift gets to each milestone (it stops a moment at each).
  static const _stops = [1.6, 3.9, 6.2, 8.5, 10.8];

  /// How far up the lift is at [u] (0 the ground … 4 the top: at
  /// milestone i at i), and so its height.
  static double _level(double u) {
    var level = 0.0;
    for (var i = 1; i < _stops.length; i++) {
      level += smooth(_stops[i - 1] + 0.5, _stops[i], u);
    }
    return level;
  }

  static double _lift(double u) {
    final l = _level(u), i = l.floor().clamp(0, _marks.length - 2), f = l - i;
    final y0 = math.max(0.4, _top(i) - 1.4), y1 = _top(i + 1) - 1.4;
    return lerp(y0, y1, f);
  }

  /// What the counter shows at [u]: the characters up to where the lift
  /// is, exactly each milestone's at its stop.
  static int _count(double u) {
    final l = _level(u), i = l.floor().clamp(0, _marks.length - 2), f = l - i;
    if (u < _stops[0]) return (128 * smooth(0.6, _stops[0], u)).round();
    return lerp(_marks[i].$3.toDouble(), _marks[i + 1].$3.toDouble(), f).round();
  }

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    // The lift: a lit cab climbing the front.
    final y = _lift(u);
    pbox(0, y + 0.55, -_w / 2 - 0.55, 1.0, 1.1, 0.7, Vignette.c(0xE9E4D6));
    pglow(0, y + 0.6, -_w / 2 - 0.91, 0.8, 0.7, 0.02, vm.Vector4(1.6, 1.5, 1.1, 1));
    // The counter on the crown: seven-segment digits, lit warm.
    final n = _count(u);
    digits('$n'.padLeft(6), 0, _top(_marks.length - 1) + 0.72, -1.82, comma: 3, color: vm.Vector4(1.5, 0.75, 0.2, 1));
    // The windows lit after dark, a band at a time as the lift passes.
    // (Snow:) letters falling all round, turning as they go.
    for (var i = 0; i < _flakes.length; i++) {
      final speed = 1.1 + 0.6 * rnd(i, 5), h = 34.0;
      final fall = ((t * speed + rnd(i, 6) * h) % h);
      final ang = rnd(i, 7) * math.pi * 2 + t * 0.06, r = 3.6 + 3.2 * rnd(i, 8);
      put(_flakes[i], math.cos(ang) * r, h + 2 - fall, math.sin(ang) * r, yaw: t * (0.4 + rnd(i, 9)), roll: 0.3 * math.sin(t + i));
    }
    pool.end();
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // From over the street's trees, the whole tower; then rising with the
    // lift up its face, to the counter on the crown.
    final y = _lift(u), top = _top(_marks.length - 1);
    final k = smooth(1.5, visit - 1.5, u);
    final eye = vm.Vector3(lerp(-3.0, -1.6, k), lerp(9.0, top + 2.4, k), lerp(-27.0, -10.5, k));
    final tg = vm.Vector3(0, lerp(13.0, math.min(top + 0.6, y + 2.0), k), lerp(0, -_w / 2, k));
    return Shot(eye, tg, fov: lerp(52, 44, k), settle: 1.1, drift: 0.5);
  }
}
