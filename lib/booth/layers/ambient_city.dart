import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../layout.dart';
import 'ambient_kit.dart';

/// The distant skyline: two rows of buildings whose windows are tiny glyphs
/// (one script per building) that light up at night, rooftop water tanks
/// and antennas, and neon signs in many languages that flicker on at dusk.
class CityArt {
  CityArt() {
    _generate();
  }

  final _far = <_Building>[];
  final _mid = <_Building>[];
  final _windows = <_Window>[];
  int _farWindows = 0;
  final _beacons = <Offset>[];
  final _signs = <_Sign>[];
  ui.Picture? _farPic, _midPic;
  final _tower = _Tower(774);

  // Rooftop life: an LED ticker, flags, steaming vents, a window cleaner.
  late final _Building _tickerHost;
  late final Rect _ticker;
  late final Path _ledGrid;
  TextPainter? _tickerText;
  int _tickerNames = -1;
  final _flags = <(Offset, Color)>[];
  final _vents = <Offset>[];
  late final Rect _gondola;
  late final double _gondolaRoof;

  void dispose() {
    _farPic?.dispose();
    _midPic?.dispose();
    _tickerText?.dispose();
  }

  // ── Generation (deterministic) ────────────────────────────────────────────

  void _generate() {
    // Far row: slim towers with gaps, mostly lost in the haze.
    var x = -20.0;
    var i = 0;
    while (x < 1620) {
      final w = 24 + 40 * rnd(i, 11);
      final top = 298 + 66 * rnd(i, 12);
      _far.add(_Building(Rect.fromLTRB(x, top, x + w, BL.groundY), i, (rnd(i, 13) * windowScripts.length).floor(), 0));
      x += w + (rnd(i, 14) < 0.5 ? 6 + 22 * rnd(i, 15) : -4);
      i++;
    }
    // Mid row: a continuous street of blocks with a lively roofline. Towers
    // stand at the gaps (between factory and site, right edge); behind the
    // plot some blocks are low, and those carrying a sign keep their roof
    // above the name.
    x = -24;
    while (x < 1624) {
      final w = 48 + 64 * rnd(i, 21);
      final cx = x + w / 2;
      double top;
      if (cx < 560) {
        top = 334 + 44 * rnd(i, 22);
      } else if (cx < 662) {
        top = 316 + 14 * rnd(i, 22);
      } else if (cx < 1470) {
        top = rnd(i, 24) < 0.3 ? 402 + 44 * rnd(i, 22) : 336 + 46 * rnd(i, 22);
      } else {
        top = 312 + 26 * rnd(i, 22);
      }
      final left = x;
      if (_signSpecs.any((s) => !s.$5 && s.$3 >= left && s.$3 < left + w - 1)) top = math.min(top, 372);
      _mid.add(_Building(Rect.fromLTRB(x, top, x + w, BL.groundY), i, (rnd(i, 23) * windowScripts.length).floor(), 1));
      x += w - 1;
      i++;
    }
    _Building midAt(double x) => _mid.firstWhere((b) => b.rect.left <= x && b.rect.right > x);
    _Building farNear(double x) => _far.reduce((a, b) => (a.rect.center.dx - x).abs() < (b.rect.center.dx - x).abs() ? a : b);
    _tickerHost = midAt(1100);
    final tr = _tickerHost.rect;
    _ticker = Rect.fromLTRB(tr.left + 7, tr.top + 9, tr.right - 7, tr.top + 22);
    _ledGrid = Path();
    for (var x = _ticker.left + 1.2; x < _ticker.right; x += 1.7) {
      _ledGrid
        ..moveTo(x, _ticker.top)
        ..lineTo(x, _ticker.bottom);
    }
    for (var y = _ticker.top + 1.2; y < _ticker.bottom; y += 1.7) {
      _ledGrid
        ..moveTo(_ticker.left, y)
        ..lineTo(_ticker.right, y);
    }
    for (final (x, col) in [(290.0, BP.coral), (900.0, BP.green)]) {
      final r = midAt(x).rect;
      _flags.add((Offset(r.right - 8, r.top), col));
    }
    for (final x in [452.0, 1262.0]) {
      final r = farNear(x).rect;
      _vents.add(Offset(r.center.dx + 4, r.top));
    }
    final g = midAt(580).rect;
    _gondolaRoof = g.top;
    _gondola = Rect.fromLTRB(g.left + 22, g.top + 18, g.left + 44, g.top + 112);
    for (final b in _far) {
      _addWindows(b, pitchX: 7.5, pitchY: 9.5, k: 0.72, depth: 46 + 40 * rnd(b.seed, 34), fill: 0.6);
    }
    _farWindows = _windows.length;
    for (final b in _mid) {
      _addWindows(b, pitchX: 10.5 + 2 * rnd(b.seed, 31), pitchY: 13, k: 0.95, depth: 64 + 80 * rnd(b.seed, 35), fill: 0.7);
    }
    _placeSigns();
    // Red beacons on the tallest antennas.
    for (final b in [..._far, ..._mid]) {
      if (_roofKind(b) != 2) continue;
      final (ax, top) = _antenna(b);
      if (top < 330) _beacons.add(Offset(ax, top - 1));
    }
  }

  /// What stands on [b]'s roof (0–1 water tank, 2 antenna, 3 setback,
  /// 4 stair house, 5 air-conditioning; −1 a sign).
  int _roofKind(_Building b) {
    if (b.row == 1 && _signs.any((s) => s.b == b && !s.vertical)) return -1;
    return (rnd(b.seed, 51) * 6).floor();
  }

  /// An antenna's x and the y of its tip.
  (double, double) _antenna(_Building b) {
    final r = b.rect;
    return (r.left + r.width * (0.3 + 0.4 * rnd(b.seed, 53)), r.top - (16 + 22 * rnd(b.seed, 54)));
  }

  void _addWindows(
    _Building b, {
    required double pitchX,
    required double pitchY,
    required double k,
    required double depth,
    required double fill,
  }) {
    final r = b.rect;
    final cols = math.max(1, ((r.width - 8) / pitchX).floor());
    final x0 = r.center.dx - (cols - 1) * pitchX / 2;
    final y1 = math.min(r.bottom - 6, r.top + depth);
    // Some buildings leave a blank band (a floor of shops, a sign board).
    final skip = rnd(b.seed, 32) < 0.35 ? (2 + rnd(b.seed, 33) * 4).floor() : -1;
    var row = 0;
    for (var y = r.top + 11; y < y1; y += pitchY, row++) {
      if (row == skip) continue;
      if (b == _tickerHost && y < _ticker.bottom + 5) continue;
      for (var c = 0; c < cols; c++) {
        final id = _windows.length;
        if (rnd(b.seed, row * 31 + c, 44) > fill) continue;
        final p = Offset(x0 + c * pitchX, y);
        final hue = rnd(id, 41);
        _windows.add(
          _Window(
            p,
            Spr.window(b.script, (rnd(id, 42) * Spr.perScript).floor()),
            k,
            rnd(id, 43),
            hue < 0.62
                ? BP.amber
                : hue < 0.8
                ? const Color(0xFFFFE6B8)
                : hue < 0.92
                ? BP.ink
                : BP.coral,
            // Calmer behind the name being built.
            BL.plot.inflate(6).contains(p) ? 0.3 : 1,
          ),
        );
      }
    }
  }

  static const _signSpecs = <(String, Color, double, Locale?, bool, double)>[
    // text, neon colour, centre x, locale, vertical, font size
    ('Hello', BP.line, 100, null, false, 16),
    ('テキスト', BP.pink, 200, jaLocale, false, 15),
    ('مرحبا', BP.green, 370, null, false, 15),
    ('नमस्ते', BP.amber, 509, null, false, 15),
    ('文字', BP.coral, 598, jaLocale, true, 17),
    ('你好', BP.red, 736, Locale('zh', 'CN'), false, 16),
    ('Привет', BP.violet, 822, null, false, 15),
    ('Flutter', BP.line, 995, null, false, 17),
    ('สวัสดี', BP.amber, 1193, null, false, 15),
    ('שלום', BP.line, 1374, null, false, 15),
    ('안녕', BP.green, 1500, Locale('ko'), false, 16),
    ('ようこそ', BP.pink, 1446, jaLocale, false, 13),
    ('カラオケ', BP.violet, 1584, jaLocale, true, 13),
  ];

  void _placeSigns() {
    for (var i = 0; i < _signSpecs.length; i++) {
      final (text, neon, x, locale, vertical, size) = _signSpecs[i];
      final b = _mid.firstWhere((b) => b.rect.left <= x && b.rect.right > x);
      _signs.add(_Sign(text, neon, x, locale, vertical, size, b, i));
    }
  }

  // ── Static drawing (recorded once) ────────────────────────────────────────

  ui.Picture _record(List<_Building> row, int depth, TextCache text) {
    for (final s in _signs) {
      s.box(text);
    }
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final edge = depth == 0 ? BP.lineFaint : const Color(0xFF24527F);
    final fill = depth == 0 ? const Color(0xFF0C223B) : const Color(0xFF0B1F36);
    for (final b in row) {
      final r = b.rect;
      c.drawRect(r, fillOf(fill));
      c.drawRect(r, strokeOf(edge, 1));
      _roof(c, b, edge, fill);
    }
    if (depth == 0) {
      for (final v in _vents) {
        final stack = Rect.fromLTWH(v.dx - 3, v.dy - 9, 6, 9);
        c.drawRect(stack, fillOf(fill));
        c.drawRect(stack, strokeOf(edge, 1));
      }
    } else {
      for (final s in _signs) {
        s.frame(c, edge);
        if (!s.vertical) continue;
        final board = s.box(text).inflate(6);
        for (var i = _farWindows; i < _windows.length; i++) {
          if (board.contains(_windows[i].p)) _windows[i].hidden = true;
        }
      }
      for (final (p, _) in _flags) {
        c.drawLine(p, p - const Offset(0, 4), strokeOf(edge, 1.2));
      }
      final panel = _ticker.inflate(2);
      c.drawRect(panel, fillOf(const Color(0xFF050F1C)));
      c.drawRect(panel, strokeOf(edge, 1));
      // The window cleaner's davit on the roof.
      c.drawLine(Offset(_gondola.left - 2, _gondolaRoof), Offset(_gondola.left - 2, _gondolaRoof - 6), strokeOf(edge, 1));
      c.drawLine(Offset(_gondola.left - 2, _gondolaRoof - 6), Offset(_gondola.right + 2, _gondolaRoof - 6), strokeOf(edge, 1));
    }
    return rec.endRecording();
  }

  void _roof(Canvas c, _Building b, Color edge, Color fill) {
    final r = b.rect;
    // Parapet.
    c.drawLine(Offset(r.left + 2, r.top + 3), Offset(r.right - 2, r.top + 3), strokeOf(edge.withValues(alpha: 0.6), 0.8));
    switch (_roofKind(b)) {
      case -1:
        break;
      case 0 || 1:
        // Water tank on legs.
        final tx = r.left + 8 + (r.width - 26) * rnd(b.seed, 52);
        final tank = Rect.fromLTWH(tx, r.top - 15, 13, 10);
        c.drawLine(Offset(tx + 2, r.top), Offset(tx + 2, tank.bottom), strokeOf(edge, 1));
        c.drawLine(Offset(tx + 11, r.top), Offset(tx + 11, tank.bottom), strokeOf(edge, 1));
        c.drawRect(tank, fillOf(fill));
        c.drawRect(tank, strokeOf(edge, 1));
        c.drawOval(Rect.fromLTWH(tx, tank.top - 2, 13, 4), strokeOf(edge, 0.9));
      case 2:
        // Antenna mast (tall ones get a red beacon at night).
        final (ax, tip) = _antenna(b);
        final h = r.top - tip;
        c.drawLine(Offset(ax, r.top), Offset(ax, tip), strokeOf(edge, 1));
        c.drawLine(Offset(ax - 5, r.top - h * 0.55), Offset(ax + 5, r.top - h * 0.55), strokeOf(edge, 0.9));
        c.drawLine(Offset(ax - 3, r.top - h * 0.8), Offset(ax + 3, r.top - h * 0.8), strokeOf(edge, 0.9));
      case 3:
        // Setback: a narrower block on top.
        final w = r.width * (0.45 + 0.2 * rnd(b.seed, 55));
        final s = Rect.fromLTWH(r.center.dx - w / 2, r.top - 14, w, 14);
        c.drawRect(s, fillOf(fill));
        c.drawRect(s, strokeOf(edge, 1));
      case 4:
        // Stair house and a railing.
        final sx = r.left + 6 + (r.width - 24) * rnd(b.seed, 56);
        final s = Rect.fromLTWH(sx, r.top - 9, 12, 9);
        c.drawRect(s, fillOf(fill));
        c.drawRect(s, strokeOf(edge, 1));
        final rail = Path()
          ..moveTo(r.left + 3, r.top - 5)
          ..lineTo(r.right - 3, r.top - 5);
        for (var x = r.left + 3; x <= r.right - 3; x += 6) {
          rail
            ..moveTo(x, r.top)
            ..lineTo(x, r.top - 5);
        }
        c.drawPath(rail, strokeOf(edge.withValues(alpha: 0.7), 0.8));
      default:
        // Air-conditioning boxes.
        for (var k = 0; k < 2; k++) {
          final bx = r.left + 6 + (r.width - 20) * rnd(b.seed, 57 + k);
          c.drawRect(Rect.fromLTWH(bx, r.top - 5, 9, 5), strokeOf(edge, 0.9));
        }
    }
  }

  // ── One frame ─────────────────────────────────────────────────────────────

  void paint(AmbientFrame f) {
    final c = f.c;
    _farPic ??= _record(_far, 0, f.text);
    _midPic ??= _record(_mid, 1, f.text);
    c.drawPicture(_farPic!);
    _paintWindows(f, 0, _farWindows, 0.75);
    for (var i = 0; i < _vents.length; i++) {
      f.ink.steam(_vents[i] - const Offset(0, 10), f.t + i * 7, per: 0.8, life: 4, rise: 34, r: 6, col: BP.inkDim.withValues(alpha: 0.5), seed: i * 13, drift: -16);
    }
    // Haze: the far row melts into the sky.
    c.drawRect(
      const Rect.fromLTRB(0, 280, 1600, BL.groundY),
      Paint()..shader = f.sky.haze(280, BL.groundY, const [0.42, 0.5, 0.62, 0.78]),
    );
    _tower.paint(f);
    c.drawPicture(_midPic!);
    _paintWindows(f, _farWindows, _windows.length, 1);
    _paintRooftops(f);
    // Haze thickening towards the ground, so the lower city (behind the
    // factory and the name) stays quiet.
    c.drawRect(
      const Rect.fromLTRB(0, 300, 1600, BL.groundY),
      Paint()..shader = f.sky.haze(300, BL.groundY, const [0.0, 0.06, 0.3, 0.6, 0.8, 0.88]),
    );
    _paintBeacons(f);
    _paintTicker(f);
    for (final s in _signs) {
      s.paint(f);
    }
  }

  /// Flags on the roofs and a window cleaner's gondola going up and down.
  void _paintRooftops(AmbientFrame f) {
    final c = f.c;
    for (final (p, col) in _flags) {
      f.ink.flag(p - const Offset(0, 4), f.t + p.dx, color: col.withValues(alpha: 0.8));
    }
    final g = _gondola;
    final u = 0.5 - 0.5 * math.cos(2 * math.pi * f.t / 84);
    final y = lerp(g.top, g.bottom, eio(u));
    const edge = Color(0xFF3C6A99);
    c.drawLine(Offset(g.left + 1, _gondolaRoof - 6), Offset(g.left + 1, y - 9), strokeOf(edge, 0.8));
    c.drawLine(Offset(g.right - 1, _gondolaRoof - 6), Offset(g.right - 1, y - 9), strokeOf(edge, 0.8));
    final cleaner = Pose()..wipe(f.t * 0.8);
    f.ink.worker(Offset(g.center.dx - 3, y), 12, 1, cleaner, ink: BP.inkDim, back: BP.inkFaint);
    final deck = Rect.fromLTRB(g.left, y - 9, g.right, y);
    c.drawLine(deck.topLeft, deck.topRight, strokeOf(edge, 1));
    c.drawRect(Rect.fromLTRB(g.left, y - 3, g.right, y), fillOf(const Color(0xFF0B1F36)));
    c.drawRect(Rect.fromLTRB(g.left, y - 3, g.right, y), strokeOf(edge, 1));
  }

  /// An LED ticker on a facade: a welcome, then the names built lately.
  void _paintTicker(AmbientFrame f) {
    final c = f.c;
    final built = f.m.built;
    if (_tickerText == null || _tickerNames != built.length) {
      _tickerNames = built.length;
      _tickerText?.dispose();
      final names = built.length > 6 ? built.sublist(built.length - 6) : built;
      final line = StringBuffer('名前工場 NAME FACTORY  ★  ようこそ WELCOME  ★  ');
      if (names.isNotEmpty) line.write('ありがとう THANK YOU · ${names.join(' · ')}  ★  ');
      _tickerText = TextPainter(
        text: TextSpan(text: line.toString(), style: BT.mono(9, color: BP.amber, weight: 600).copyWith(locale: jaLocale)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _tickerText!;
    final r = _ticker;
    final night = f.d.night;
    if (night > 0.2) glow(c, r.inflate(3), BP.amber.withValues(alpha: 0.14 * night), 5, radius: 2);
    c.save();
    c.clipRect(r);
    final w = tp.width;
    for (var x = r.left - (f.t * 24) % w; x < r.right; x += w) {
      tp.paint(c, Offset(x, r.center.dy - tp.height / 2));
    }
    c.drawPath(_ledGrid, strokeOf(const Color(0xFF050F1C).withValues(alpha: 0.6), 0.6));
    c.restore();
  }

  void _paintWindows(AmbientFrame f, int from, int to, double k) {
    final night = f.d.night;
    final t = f.t;
    final unlit = Color.lerp(const Color(0xFF4A7AAB), const Color(0xFF2E5A88), night)!;
    final unlitA = lerp(0.5, 0.32, night) * k;
    // Lights come on through the evening and go out again after midnight.
    final late = smoothstep(0.76, 0.98, f.d.phase);
    for (var i = from; i < to; i++) {
      final w = _windows[i];
      if (w.hidden) continue;
      var lit = night > 0.12 + 1.3 * w.th + 0.55 * late;
      if (night > 0.6) {
        // People switch lights on and off.
        final slot = ((t + w.th * 53) / 17).floor();
        if (rnd(i, slot, 9) < 0.06) lit = !lit;
      }
      final col = lit ? w.lit.withValues(alpha: 0.82 * k * w.calm) : unlit.withValues(alpha: unlitA * w.calm);
      f.batch.add(f.sprites, w.glyph, w.p.dx, w.p.dy, w.k, col);
    }
    f.batch.flush(f.c, f.sprites);
  }

  void _paintBeacons(AmbientFrame f) {
    final night = f.d.night;
    if (night < 0.3) return;
    for (var i = 0; i < _beacons.length; i++) {
      final on = fract(f.t * 0.5 + i * 0.37) < 0.35;
      if (!on) continue;
      final p = _beacons[i];
      f.c.drawCircle(p, 5, fillOf(BP.red.withValues(alpha: 0.18 * night)));
      f.c.drawCircle(p, 1.8, fillOf(BP.red.withValues(alpha: 0.9 * night)));
    }
  }
}

class _Building {
  _Building(this.rect, this.seed, this.script, this.row);
  final Rect rect;
  final int seed;
  final int script;
  final int row;
}

class _Window {
  _Window(this.p, this.glyph, this.k, this.th, this.lit, this.calm);
  final Offset p;

  /// Behind a sign board.
  bool hidden = false;
  final int glyph;
  final double k;

  /// Darkness at which this window's light comes on (0..1).
  final double th;
  final Color lit;

  /// Extra dimming (behind the name being built).
  final double calm;
}

/// A neon sign on a roof (or down a facade, written vertically).
class _Sign {
  _Sign(this.text, this.neon, this.x, this.locale, this.vertical, this.size, this.b, this.seed) {
    // Switch on around sunset, off around sunrise, each at its own moment.
    onAt = 0.47 + 0.05 * rnd(seed, 1);
    offAt = 0.965 + 0.04 * rnd(seed, 2);
    legs = vertical ? 0 : 4 + 16 * rnd(seed, 3);
  }

  final String text;
  final Color neon;
  final double x;
  final Locale? locale;
  final bool vertical;
  final double size;
  final _Building b;
  final int seed;
  late final double onAt;
  late final double offAt;
  late final double legs;

  String get _shown => vertical ? text.split('').join('\n') : text;

  TextStyle _style(Color c) => BT.sample(size, color: c, weight: 600, height: vertical ? 1.05 : null).copyWith(locale: locale);

  Color get _onColor => Color.lerp(neon, const Color(0xFFFFFFFF), 0.28)!;
  Color get _offColor => Color.lerp(neon, BP.inkFaint, 0.6)!.withValues(alpha: 0.55);

  /// The sign's text box (fixed; measured once).
  Rect? _box;

  Rect box(TextCache text) => _box ??= () {
    final p = text.get(_shown, _style(_onColor), align: TextAlign.center);
    final r = b.rect;
    if (vertical) return Rect.fromLTWH(x - p.width / 2, r.top + 14, p.width, p.height);
    final y = math.max(BL.trainY + 22, r.top - legs - 6 - p.height);
    return Rect.fromLTWH(x - p.width / 2, y, p.width, p.height);
  }();

  /// Frame and supports (static, in the skyline picture). Needs [_box].
  void frame(Canvas c, Color edge) {
    final r = _box;
    if (r == null) return;
    final board = r.inflate(4);
    if (vertical) {
      c.drawRect(board, fillOf(const Color(0xFF0A1C31)));
      c.drawRect(board, strokeOf(edge, 1));
      final wall = x < b.rect.center.dx ? b.rect.left : b.rect.right;
      c.drawLine(Offset(x < b.rect.center.dx ? board.left : board.right, board.top + 6), Offset(wall, board.top + 6), strokeOf(edge, 1));
      c.drawLine(Offset(x < b.rect.center.dx ? board.left : board.right, board.bottom - 6), Offset(wall, board.bottom - 6), strokeOf(edge, 1));
      return;
    }
    final legsPath = Path()
      ..moveTo(board.left + 6, board.bottom)
      ..lineTo(board.left + 6, b.rect.top)
      ..moveTo(board.right - 6, board.bottom)
      ..lineTo(board.right - 6, b.rect.top)
      ..moveTo(board.left + 6, b.rect.top)
      ..lineTo(board.right - 6, board.bottom)
      ..moveTo(board.right - 6, b.rect.top)
      ..lineTo(board.left + 6, board.bottom);
    c.drawPath(legsPath, strokeOf(edge.withValues(alpha: 0.7), 0.8));
    c.drawLine(board.bottomLeft, board.bottomRight, strokeOf(edge, 1.2));
  }

  /// 0 off .. 1 on, with a flicker at switch-on/off and the odd hiccup.
  double _lit(AmbientFrame f) {
    final d = f.d;
    final sOn = d.since(onAt), sOff = d.since(offAt);
    final on = sOn < sOff;
    if (on) {
      if (sOn < 1.8) return rnd(seed, (sOn * 14).floor(), 3) > 0.62 - 0.32 * sOn ? 1 : 0;
      // Every so often a tube hiccups.
      final slot = (f.t / 11).floor();
      if (rnd(seed, slot, 4) < 0.1) {
        final u = f.t - slot * 11 - 4 * rnd(seed, slot, 5);
        if (u > 0 && u < 0.6) return rnd(seed, (f.t * 18).floor(), 6) > 0.5 ? 1 : 0.15;
      }
      return 1;
    }
    if (sOff < 0.9) return rnd(seed, (sOff * 14).floor(), 7) > 0.5 ? 1 : 0;
    return 0;
  }

  /// Signs whose letters light up one after another, then blink.
  bool get _chase => text == 'Flutter' || text == 'テキスト' || text == 'Hello';

  /// How many letters a chasing sign shows lit (all of them most of the time).
  int _chaseCount(double t) {
    final n = text.length;
    const step = 0.3;
    final u = fract((t + seed * 3.7) / 11) * 11;
    if (u < n * step) return (u / step).floor() + 1;
    final b = u - n * step;
    if (b < 1.2) return fract(b * 2.5) < 0.5 ? 0 : n;
    return n;
  }

  final _litBoxes = <int, Rect>{};

  void paint(AmbientFrame f) {
    final c = f.c;
    final r = box(f.text);
    final lit = _lit(f);
    final on = f.text.get(_shown, _style(_onColor), align: TextAlign.center);
    if (lit > 0.5 && _chase) {
      final k = _chaseCount(f.t);
      if (k < text.length) {
        f.text.get(_shown, _style(_offColor), align: TextAlign.center).paint(c, r.topLeft);
        if (k == 0) return;
        final part = _litBoxes[k] ??= () {
          final boxes = on.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: k));
          var u = boxes.first.toRect();
          for (final b in boxes) {
            u = u.expandToInclude(b.toRect());
          }
          return u;
        }();
        final lr = part.shift(r.topLeft);
        glow(c, lr.inflate(6), neon.withValues(alpha: 0.24), 8);
        c.save();
        c.clipRect(lr.inflate(1.5));
        on.paint(c, r.topLeft);
        c.restore();
        return;
      }
    }
    if (lit > 0) {
      glow(c, r.inflate(7), neon.withValues(alpha: 0.24 * lit), 9);
      glow(c, r.inflate(1), neon.withValues(alpha: 0.12 * lit), 3, radius: 3);
    }
    (lit > 0.5 ? on : f.text.get(_shown, _style(_offColor), align: TextAlign.center)).paint(c, r.topLeft);
  }
}

/// A slim broadcast tower on the skyline (after Tokyo's Skytree): line art
/// by day; at night lit in its two alternating styles, Iki (粋, pale blue)
/// and Miyabi (雅, purple), with a red beacon on top.
class _Tower {
  _Tower(this.x) {
    final edges = Path();
    final lattice = Path();
    double half(double y) => lerp(4.5, 14, math.pow((y - _deck) / (_base - _deck), 1.25).toDouble());
    for (final s in [-1.0, 1.0]) {
      edges.moveTo(x + s * half(_base), _base);
      for (var y = _base; y >= _deck; y -= 6) {
        edges.lineTo(x + s * half(y), y);
      }
    }
    for (var y = _base; y > _deck + 4; y -= 9) {
      final y2 = y - 9;
      lattice
        ..moveTo(x - half(y), y)
        ..lineTo(x + half(y2), y2)
        ..moveTo(x + half(y), y)
        ..lineTo(x - half(y2), y2);
    }
    // Observation decks, the upper shaft and the antenna.
    edges
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x - 13, _deck - 8, x + 13, _deck + 4), const Radius.circular(3)))
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x - 8.5, _gallery - 5, x + 8.5, _gallery + 3), const Radius.circular(3)))
      ..moveTo(x - 4, _deck - 8)
      ..lineTo(x - 3.2, _gallery + 3)
      ..moveTo(x + 4, _deck - 8)
      ..lineTo(x + 3.2, _gallery + 3)
      ..moveTo(x - 2.6, _gallery - 5)
      ..lineTo(x - 1.2, _top + 12)
      ..moveTo(x + 2.6, _gallery - 5)
      ..lineTo(x + 1.2, _top + 12)
      ..moveTo(x, _top + 12)
      ..lineTo(x, _top);
    _edges = edges;
    _lattice = lattice;
  }

  final double x;
  static const _base = 372.0, _deck = 224.0, _gallery = 200.0, _top = 140.0;
  late final Path _edges;
  late final Path _lattice;

  void paint(AmbientFrame f) {
    final c = f.c;
    final night = f.d.night;
    final haze = f.sky.at(240);
    final day = Color.lerp(BP.lineDim, haze, 0.12)!;
    // Alternate styles night by night.
    final iki = ((f.t / dayLength).floor()).isEven;
    final lit = iki ? const Color(0xFF9FD8FF) : BP.violet;
    final col = Color.lerp(day, lit, smoothstep(0.35, 0.8, night))!;
    for (final r in [
      Rect.fromLTRB(x - 13, _deck - 8, x + 13, _deck + 4),
      Rect.fromLTRB(x - 8.5, _gallery - 5, x + 8.5, _gallery + 3),
    ]) {
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), fillOf(Color.lerp(BP.panel, haze, 0.4)!));
    }
    c.drawPath(_lattice, strokeOf(col.withValues(alpha: 0.35 + 0.2 * night), 0.8));
    if (night > 0.35) {
      c.drawPath(_edges, strokeOf(lit.withValues(alpha: 0.12 * night), 5));
      // Deck windows.
      for (var i = -4; i <= 4; i++) {
        c.drawCircle(Offset(x + i * 2.6, _deck - 2), 0.8, fillOf(BP.amber.withValues(alpha: 0.8 * night)));
      }
    }
    c.drawPath(_edges, strokeOf(col.withValues(alpha: 0.75), 1.1));
    if (night > 0.3 && fract(f.t * 0.5) < 0.4) {
      c.drawCircle(Offset(x, _top), 4.5, fillOf(BP.red.withValues(alpha: 0.2 * night)));
      c.drawCircle(Offset(x, _top), 1.6, fillOf(BP.red.withValues(alpha: night)));
    }
  }
}
