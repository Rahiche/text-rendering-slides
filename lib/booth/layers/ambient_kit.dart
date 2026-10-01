import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../layout.dart';
import '../model.dart';

/// Shared pieces of the city of text: the time of day, sky tones, a sprite
/// sheet of small glyphs (windows, stars, birds) drawn in one batch, and the
/// "calm zone" over the UI board.

// ─────────────────────────────────────────────────────────────────────────────
// Time of day
// ─────────────────────────────────────────────────────────────────────────────

/// Seconds from one sunrise to the next.
const dayLength = 480.0;

/// Where in the day the booth starts (0 = sunrise): early morning.
const _dayAtStart = 0.06;

double smoothstep(double a, double b, double x) {
  final t = c01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

double fract(double v) => v - v.floorToDouble();

/// The time of day at a scene time.
class DayClock {
  factory DayClock(double t) {
    final p = fract(t / dayLength + _dayAtStart);
    final sun = math.sin(2 * math.pi * p);
    final g = sun / 0.34;
    return DayClock._(p, sun, smoothstep(-0.24, 0.3, sun), math.exp(-g * g));
  }

  const DayClock._(this.phase, this.sun, this.day, this.glow);

  /// 0..1 through the day: 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight.
  final double phase;

  /// Height of the sun, −1..1 (below 0 the moon is up).
  final double sun;

  /// 1 in daylight, 0 at night.
  final double day;

  /// Dawn / dusk colour near the horizon, 0..1.
  final double glow;

  double get night => 1 - day;

  /// Sunset side of the day (dusk rather than dawn colours).
  bool get evening => phase > 0.25 && phase < 0.75;

  /// Seconds since the day last passed [at] (a phase), 0..[dayLength].
  double since(double at) => fract(phase - at) * dayLength;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sky tones
// ─────────────────────────────────────────────────────────────────────────────

const _nightTop = Color(0xFF071526);
const _nightMid = Color(0xFF0A1C33);
const _nightHorizon = Color(0xFF13284A);
const _nightLow = Color(0xFF132C4D);
const _dayTop = Color(0xFF0F2D51);
const _dayMid = Color(0xFF16395F);
const _dayHorizon = Color(0xFF1E4874);
const _dayLow = Color(0xFF224D7A);

/// Gradient stops (y) of the sky.
const _skyStops = [0.0, 170.0, 330.0, BL.groundY];

/// The sky's colours at one time of day, top to the ground line.
class SkyTones {
  factory SkyTones(DayClock d) {
    final k = d.day;
    var top = Color.lerp(_nightTop, _dayTop, k)!;
    var mid = Color.lerp(_nightMid, _dayMid, k)!;
    var hor = Color.lerp(_nightHorizon, _dayHorizon, k)!;
    var low = Color.lerp(_nightLow, _dayLow, k)!;
    final g = d.glow;
    if (d.evening) {
      top = Color.lerp(top, BP.violet, 0.04 * g)!;
      mid = Color.lerp(mid, BP.violet, 0.13 * g)!;
      hor = Color.lerp(hor, BP.coral, 0.34 * g)!;
      low = Color.lerp(low, BP.amber, 0.22 * g)!;
    } else {
      mid = Color.lerp(mid, BP.violet, 0.10 * g)!;
      hor = Color.lerp(hor, BP.pink, 0.24 * g)!;
      low = Color.lerp(low, BP.amber, 0.18 * g)!;
    }
    return SkyTones._([top, mid, hor, low]);
  }

  SkyTones._(this.colors);

  final List<Color> colors;

  Color get top => colors[0];
  Color get horizon => colors[2];

  /// The sky colour at height [y].
  Color at(double y) {
    if (y <= _skyStops.first) return colors.first;
    for (var i = 1; i < _skyStops.length; i++) {
      if (y <= _skyStops[i]) {
        return Color.lerp(colors[i - 1], colors[i], (y - _skyStops[i - 1]) / (_skyStops[i] - _skyStops[i - 1]))!;
      }
    }
    return colors.last;
  }

  /// A vertical gradient matching the sky (for the sky itself and for haze).
  Shader shader() => ui.Gradient.linear(
    Offset.zero,
    const Offset(0, BL.groundY),
    colors,
    [for (final s in _skyStops) s / BL.groundY],
  );

  /// Haze over [top]..[bottom]: sky colour at each height with growing alpha.
  Shader haze(double top, double bottom, List<double> alphas) {
    final n = alphas.length;
    return ui.Gradient.linear(
      Offset(0, top),
      Offset(0, bottom),
      [for (var i = 0; i < n; i++) at(lerp(top, bottom, i / (n - 1))).withValues(alpha: alphas[i])],
      [for (var i = 0; i < n; i++) i / (n - 1)],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Calm over the UI board
// ─────────────────────────────────────────────────────────────────────────────

/// Opacity for an ambient element at [p]: 1 away from the UI board, [floor]
/// over it (with soft edges), so the board's text stays calm.
double boardCalmAt(Offset p, {double floor = 0.25}) {
  const b = BL.board;
  final dx = math.max(b.left - p.dx, p.dx - b.right);
  final dy = math.max(b.top - p.dy, p.dy - b.bottom);
  return lerp(floor, 1, smoothstep(-10, 40, math.max(dx, dy)));
}

/// Like [boardCalmAt] for an element covering [r].
double boardCalm(Rect r, {double floor = 0.25}) {
  final i = r.intersect(BL.board.inflate(16));
  if (i.width <= 0 || i.height <= 0) return 1;
  final f = (i.width * i.height) / math.max(1, r.width * r.height);
  return lerp(1, floor, smoothstep(0, 0.6, f));
}

// ─────────────────────────────────────────────────────────────────────────────
// Small glyphs as sprites
// ─────────────────────────────────────────────────────────────────────────────

/// Window glyphs by script: each building lights its windows in one script.
const windowScripts = <(List<String>, Locale?)>[
  (['田', '口', '日', '目', '回', '品', '門', '囲'], Locale('ja')),
  (['ロ', 'コ', 'ヨ', 'エ', 'ア', 'テ', 'キ', 'ス'], Locale('ja')),
  (['あ', 'い', 'う', 'え', 'お', 'か', 'も', 'じ'], Locale('ja')),
  (['A', 'B', 'E', 'H', 'M', 'N', 'O', 'T'], null),
  (['Ж', 'Я', 'Б', 'Д', 'Ш', 'П', 'Ф', 'Щ'], null),
  (['Ω', 'Σ', 'Π', 'Ξ', 'Δ', 'Φ', 'Ψ', 'Λ'], null),
  (['한', '글', '가', '나', '다', '문', '자', '집'], Locale('ko')),
  (['क', 'ख', 'ग', 'म', 'न', 'ट', 'ठ', 'ह'], null),
  (['ก', 'ข', 'ม', 'ห', 'บ', 'ด', 'ฟ', 'ศ'], null),
  (['ب', 'ت', 'ج', 'ح', 'س', 'ص', 'ط', 'م'], null),
  (['א', 'ב', 'ג', 'ד', 'ה', 'ם', 'ש', 'ת'], null),
  (['中', '文', '字', '国', '语', '书', '图', '画'], Locale('zh', 'CN')),
];

/// Sprite ids in [AmbientSprites].
abstract final class Spr {
  static const perScript = 8;
  static int window(int script, int i) => script * perScript + i % perScript;
  static final dot = windowScripts.length * perScript;
  static final sparkle = dot + 1; // ✦
  static final asterisk = dot + 2; // ＊
  static final starKanji = dot + 3; // 星
  static final birdUp = dot + 4; // v
  static final birdFlat = dot + 5; // 〜
}

/// Base font size of window glyphs on the canvas.
const windowGlyphSize = 8.0;

List<(String, TextStyle)> _spriteGlyphs() {
  TextStyle st(double size, {Locale? locale, double weight = 500}) =>
      BT.sample(size, weight: weight, color: const Color(0xFFFFFFFF)).copyWith(locale: locale);
  return [
    for (final (glyphs, locale) in windowScripts)
      for (final g in glyphs) (g, st(windowGlyphSize, locale: locale)),
    ('·', st(18, weight: 700)),
    ('✦', st(10)),
    ('＊', st(10, locale: jaLocale)),
    ('星', st(10, locale: jaLocale)),
    ('v', st(13, weight: 400)),
    ('〜', st(13, locale: jaLocale, weight: 400)),
  ];
}

/// Small glyphs rendered once into one image (at about the screen's pixel
/// density, so they stay crisp on a 4K TV) and drawn many at a time with
/// [SpriteBatch]. Rebuilt only if the screen scale or the fonts change.
class AmbientSprites {
  AmbientSprites() {
    PaintingBinding.instance.systemFonts.addListener(_drop);
  }

  final _glyphs = _spriteGlyphs();
  final _src = <Rect>[];
  ui.Image? _image;
  double _scale = 0;

  /// Pixels per canvas unit in the sheet.
  double get scale => _scale;
  ui.Image get image => _image!;
  Rect src(int id) => _src[id];

  /// Makes sure the sheet exists for the current screen scale.
  void prepare() {
    final s = _screenScale();
    if (_image != null && s == _scale) return;
    _drop();
    _scale = s;
    const pad = 2.0, width = 1024.0;
    final painters = [
      for (final (g, style) in _glyphs)
        TextPainter(
          text: TextSpan(text: g, style: style.copyWith(fontSize: style.fontSize! * s)),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    var x = 0.0, y = 0.0, rowH = 0.0;
    for (final p in painters) {
      final w = p.width.ceilToDouble() + pad * 2, h = p.height.ceilToDouble() + pad * 2;
      if (x + w > width) {
        x = 0;
        y += rowH;
        rowH = 0;
      }
      _src.add(Rect.fromLTWH(x, y, w, h));
      x += w;
      rowH = math.max(rowH, h);
    }
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (var i = 0; i < painters.length; i++) {
      painters[i].paint(c, _src[i].topLeft + const Offset(pad, pad));
      painters[i].dispose();
    }
    final pic = rec.endRecording();
    _image = pic.toImageSync(width.toInt(), (y + rowH).ceil());
    pic.dispose();
  }

  static double _screenScale() {
    final v = ui.PlatformDispatcher.instance.implicitView;
    if (v == null) return 2;
    final p = v.physicalSize;
    final s = math.min(p.width / BL.size.width, p.height / BL.size.height);
    return ((s * 2).ceil() / 2).clamp(1.0, 4.0);
  }

  void _drop() {
    _image?.dispose();
    _image = null;
    _src.clear();
  }

  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_drop);
    _drop();
  }
}

/// Collects sprites (glyph, centre, size, colour) and draws them in one call.
class SpriteBatch {
  SpriteBatch(this.capacity)
    : _xf = Float32List(capacity * 4),
      _rc = Float32List(capacity * 4),
      _col = Int32List(capacity);

  final int capacity;
  final Float32List _xf;
  final Float32List _rc;
  final Int32List _col;
  int _n = 0;

  static final _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Adds sprite [id] centred on ([cx], [cy]) at [k] × its base size.
  void add(AmbientSprites s, int id, double cx, double cy, double k, Color color) {
    if (_n >= capacity || color.a <= 0.004) return;
    final r = s.src(id);
    final sc = k / s.scale;
    final i = _n * 4;
    _xf[i] = sc;
    _xf[i + 1] = 0;
    _xf[i + 2] = cx - sc * r.width / 2;
    _xf[i + 3] = cy - sc * r.height / 2;
    _rc[i] = r.left;
    _rc[i + 1] = r.top;
    _rc[i + 2] = r.right;
    _rc[i + 3] = r.bottom;
    _col[_n] = color.toARGB32();
    _n++;
  }

  void flush(Canvas c, AmbientSprites s) {
    if (_n == 0) return;
    c.drawRawAtlas(
      s.image,
      Float32List.sublistView(_xf, 0, _n * 4),
      Float32List.sublistView(_rc, 0, _n * 4),
      Int32List.sublistView(_col, 0, _n),
      BlendMode.modulate,
      null,
      _paint,
    );
    _n = 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One painted frame
// ─────────────────────────────────────────────────────────────────────────────

/// Everything a part of the city needs to paint one frame.
class AmbientFrame {
  AmbientFrame(this.c, this.m, this.text, this.sprites, this.batch)
    : t = m.t,
      d = DayClock(m.t),
      ink = FactoryInk(c) {
    sky = SkyTones(d);
  }

  final Canvas c;
  final BoothModel m;
  final TextCache text;
  final AmbientSprites sprites;
  final SpriteBatch batch;
  final double t;
  final DayClock d;
  final FactoryInk ink;
  late final SkyTones sky;

  /// The phase of the name being built (null between names).
  Phase? get phase => m.job?.phase;

  /// Paints [p] centred on [center].
  void centered(TextPainter p, Offset center) => p.paint(c, center - Offset(p.width / 2, p.height / 2));
}

/// Shared paints (reconfigured on every use; painting is single-threaded).
final fillPaint = Paint();
final strokePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint fillOf(Color c) => fillPaint
  ..color = c
  ..shader = null
  ..maskFilter = null;

Paint strokeOf(Color c, [double w = 1.2]) => strokePaint
  ..color = c
  ..strokeWidth = w;

final _glowPaint = Paint();

/// A soft blurred glow (rounded rect), cheap on Impeller.
void glow(Canvas c, Rect r, Color col, double sigma, {double radius = 6}) {
  _glowPaint
    ..color = col
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
  c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), _glowPaint);
}
