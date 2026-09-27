import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kumihan/kumihan.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// 約物の詰め: full-width punctuation carries half an em of blank. When two
/// marks meet (」「, 。」, （「) JLREQ closes the gap. The font has no `chws`
/// (the OpenType feature that does exactly this), `halt` on everything is too
/// tight, kumihan applies `halt` per glyph by adjacency. Every row is a real
/// paragraph; the kumihan row glides between the two real layouts.
class YakumonoLabSlide extends StatefulWidget {
  const YakumonoLabSlide({super.key});

  @override
  State<YakumonoLabSlide> createState() => _YakumonoLabSlideState();
}

const _samples = [
  '「こんにちは」「世界」。',
  '（注）「例」、『本』。',
  '『吾輩は猫である』（夏目漱石）。',
  '彼は「はい。」と言った。',
];

const _pairs = ['」「', '。」', '（「', '、「'];

enum _Mode { chws, haltAll, kumihan }

const _heroSize = 64.0;
const _pairSize = 46.0;
const _rowX = 190.0; // text origin x in the hero
const _rowAY = 92.0; // top of the Text() row
const _rowBY = 232.0; // top of the kumihan row

TextStyle _ja(double size, {Color color = BP.ink, FontWeight weight = FontWeight.w400}) => TextStyle(
  fontFamily: 'Hiragino Sans',
  fontFamilyFallback: const ['Hiragino Kaku Gothic ProN', 'Noto Sans JP', 'Noto Sans CJK JP'],
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: 1.3,
  locale: const Locale('ja'),
);

/// Two real layouts of one string: plain, and with the chosen spacing.
class _Row {
  _Row(this.text, this.size, _Mode mode) {
    final style = _ja(size);
    before = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    final InlineSpan span = switch (mode) {
      _Mode.chws => TextSpan(
        text: text,
        style: style.copyWith(fontFeatures: const [ui.FontFeature.enable('chws')]),
      ),
      _Mode.haltAll => TextSpan(
        text: text,
        style: style.copyWith(fontFeatures: const [ui.FontFeature.enable('halt')]),
      ),
      _Mode.kumihan => Kumihan.yakumono(text, style: style),
    };
    after = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    var i = 0;
    for (final g in text.characters) {
      final a = i, b = i + g.length;
      i = b;
      final rb = _box(before, a, b);
      final ra = _box(after, a, b);
      if (rb == null || ra == null) continue;
      ranges.add((a, b));
      boxB.add(rb);
      boxA.add(ra);
      final cp = g.runes.first;
      // Where the ink sits in a full-width box: right half for opening
      // brackets, left half for closing ones and 、。, centred otherwise.
      ink.add(isYakumonoOpening(cp) ? 1.0 : (isYakumonoClosing(cp) ? 0.0 : 0.5));
      halved.add(ra.width < rb.width - 0.5);
    }
  }

  final String text;
  final double size;
  late final TextPainter before;
  late final TextPainter after;
  final ranges = <(int, int)>[];
  final boxB = <Rect>[];
  final boxA = <Rect>[];
  final ink = <double>[];
  final halved = <bool>[];

  double get widthB => before.width;
  double get widthA => after.width;

  static Rect? _box(TextPainter tp, int a, int b) {
    final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b));
    if (boxes.isEmpty) return null;
    return boxes.map((e) => e.toRect()).reduce((x, y) => x.expandToInclude(y));
  }

  /// The box of grapheme [k] at squeeze progress [t] (0 = plain layout).
  Rect boxAt(int k, double t) {
    final b = boxB[k], a = boxA[k];
    return Rect.fromLTRB(
      ui.lerpDouble(b.left, a.left, t)!,
      a.top,
      ui.lerpDouble(b.right, a.right, t)!,
      a.bottom,
    );
  }

  /// How far grapheme [k] of [after] must move to sit at progress [t].
  double shiftAt(int k, double t) {
    final b = boxB[k], a = boxA[k];
    final atStart = b.left + ink[k] * (b.width - a.width) - a.left;
    return atStart * (1 - t);
  }

  double rightAt(double t) => boxA.isEmpty ? 0 : boxAt(boxA.length - 1, t).right;

  /// Paints [after] with every grapheme moved to progress [t].
  void paintAt(Canvas canvas, Offset o, double t) {
    if (t >= 1) {
      after.paint(canvas, o);
      return;
    }
    for (var k = 0; k < boxA.length; k++) {
      final a = boxA[k];
      canvas.save();
      canvas.translate(shiftAt(k, t), 0);
      canvas.clipRect(Rect.fromLTRB(a.left - 1, a.top - 20, a.right + 1, a.bottom + 20).shift(o));
      after.paint(canvas, o);
      canvas.restore();
    }
  }

  void dispose() {
    before.dispose();
    after.dispose();
  }
}

class _Squeeze extends ChangeNotifier {
  double t = 0;

  void set(double v) {
    if (v == t) return;
    t = v;
    notifyListeners();
  }
}

class _YakumonoLabSlideState extends State<YakumonoLabSlide> with SingleTickerProviderStateMixin {
  late final _ctrl = TextEditingController(text: _samples[0]);
  final _squeeze = _Squeeze();
  late final Ticker _ticker;
  double _clock = 0;
  Duration _last = Duration.zero;

  _Mode _mode = _Mode.kumihan;
  bool _boxes = true;
  bool _loop = true;
  _Row? _hero;
  List<_Row> _pairRows = [];

  @override
  void initState() {
    super.initState();
    _rebuild();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ctrl.dispose();
    _hero?.dispose();
    for (final r in _pairRows) {
      r.dispose();
    }
    _squeeze.dispose();
    super.dispose();
  }

  void _rebuild() {
    _hero?.dispose();
    _hero = _Row(_ctrl.text, _heroSize, _mode);
    for (final r in _pairRows) {
      r.dispose();
    }
    _pairRows = [for (final p in _pairs) _Row(p, _pairSize, _mode)];
  }

  void _tick(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    if (_loop) {
      _clock = (_clock + dt) % 5.6;
      final p = _clock;
      final double t;
      if (p < 1.3) {
        t = 0;
      } else if (p < 2.1) {
        t = Curves.easeInOutCubic.transform((p - 1.3) / 0.8);
      } else if (p < 4.8) {
        t = 1;
      } else {
        t = 1 - Curves.easeInOutCubic.transform((p - 4.8) / 0.8);
      }
      _squeeze.set(t);
    } else {
      _squeeze.set(math.min(1, _squeeze.t + dt / 0.5));
    }
  }

  void _set(void Function() f) {
    setState(f);
    _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    final hero = _hero!;
    return SlideFrame(
      title: 'Punctuation spacing',
      trailing: Text('約物の詰め', style: _ja(34, color: BP.inkDim)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _HeroPainter(hero, _squeeze, boxes: _boxes)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: BpSegmented<int>(
              values: const [0, 1, 2, 3],
              selected: _samples.indexOf(_ctrl.text),
              labelOf: (i) => _samples[i],
              size: 14,
              onChanged: (i) => _set(() => _ctrl.text = _samples[i]),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Row(
              children: [
                BpSegmented<_Mode>(
                  values: _Mode.values,
                  selected: _mode,
                  size: 14,
                  labelOf: (m) => switch (m) {
                    _Mode.chws => "'chws'",
                    _Mode.haltAll => "'halt' all",
                    _Mode.kumihan => 'kumihan',
                  },
                  onChanged: (m) => _set(() => _mode = m),
                ),
                const SizedBox(width: 24),
                BpButton(
                  label: 'em',
                  size: 14,
                  selected: _boxes,
                  onTap: () => setState(() => _boxes = !_boxes),
                ),
                const SizedBox(width: 8),
                BpButton(
                  label: 'loop',
                  size: 14,
                  color: BP.amber,
                  selected: _loop,
                  onTap: () => setState(() => _loop = !_loop),
                ),
              ],
            ),
          ),
          // Row labels.
          Positioned(left: 0, top: _rowAY + 24, child: _rowLabel('Text()', 'Flutter', BP.inkDim)),
          Positioned(
            left: 0,
            top: _rowBY + 24,
            child: _rowLabel(
              switch (_mode) {
                _Mode.chws => "'chws'",
                _Mode.haltAll => "'halt'",
                _Mode.kumihan => 'kumihan',
              },
              switch (_mode) {
                _Mode.chws => 'not in font',
                _Mode.haltAll => 'every glyph',
                _Mode.kumihan => 'by adjacency',
              },
              switch (_mode) {
                _Mode.kumihan => BP.green,
                _ => BP.red,
              },
            ),
          ),
          // Type your own.
          Positioned(
            left: _rowX,
            top: 420,
            child: BpTextField(
              controller: _ctrl,
              width: 560,
              style: _ja(28),
              onChanged: (_) => _set(() {}),
            ),
          ),
          // What kumihan actually does to the paragraph.
          Positioned(
            left: _rowX,
            top: 500,
            child: Row(
              children: [
                BpTag(
                  switch (_mode) {
                    _Mode.chws => "FontFeature.enable('chws')",
                    _ => "FontFeature.enable('halt')",
                  },
                  color: _mode == _Mode.kumihan ? BP.green : BP.red,
                  size: 14,
                ),
                const SizedBox(width: 14),
                Text(
                  switch (_mode) {
                    _Mode.chws => 'no effect',
                    _Mode.haltAll => '× ${hero.boxA.length} glyphs',
                    _Mode.kumihan => '× ${hero.halved.where((h) => h).length} of ${hero.boxA.length} glyphs',
                  },
                  style: BT.mono(15, color: BP.inkDim),
                ),
              ],
            ),
          ),
          // The rules, pair by pair.
          for (var i = 0; i < _pairRows.length; i++)
            Positioned(
              left: 812 + i * 168.0,
              top: 392,
              width: 150,
              height: 236,
              child: RepaintBoundary(
                child: CustomPaint(painter: _PairPainter(_pairRows[i], _squeeze, boxes: _boxes)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowLabel(String name, String sub, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: BT.mono(18, color: color == BP.inkDim ? BP.ink : color)),
      const SizedBox(height: 4),
      Text(sub, style: BT.mono(13, color: color)),
    ],
  );
}

void _emBox(Canvas canvas, Rect r, {required bool half, double alpha = 1}) {
  if (half) {
    canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.18 * alpha));
  }
  canvas.drawRect(
    r,
    Paint()
      ..color = (half ? BP.amber : BP.lineDim).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = half ? 1.5 : 1,
  );
  // Centre cross, like a glyph box on a drawing.
  final c = r.center;
  final p = Paint()
    ..color = (half ? BP.amber : BP.lineFaint).withValues(alpha: alpha)
    ..strokeWidth = 1;
  canvas.drawLine(c - const Offset(4, 0), c + const Offset(4, 0), p);
  canvas.drawLine(c - const Offset(0, 4), c + const Offset(0, 4), p);
}

void _dim(Canvas canvas, double x0, double x1, double y, String label, Color color, {bool above = false}) {
  final p = Paint()
    ..color = color
    ..strokeWidth = 1.2;
  canvas.drawLine(Offset(x0, y), Offset(x1, y), p);
  canvas.drawLine(Offset(x0, y - 6), Offset(x0, y + 6), p);
  canvas.drawLine(Offset(x1, y - 6), Offset(x1, y + 6), p);
  if ((x1 - x0).abs() > 14) {
    drawArrowHead(canvas, Offset(x0, y), Offset(x0 + 10, y), p, 5);
    drawArrowHead(canvas, Offset(x1, y), Offset(x1 - 10, y), p, 5);
  }
  final tp = TextPainter(
    text: TextSpan(text: label, style: BT.mono(14, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset((x0 + x1) / 2 - tp.width / 2, above ? y - tp.height - 6 : y + 6));
  tp.dispose();
}

String _em(double px, double size) {
  final v = px / size;
  final s = v.abs() < 0.05 ? '0' : v.toStringAsFixed(1);
  return '$s em';
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.row, this.squeeze, {required this.boxes}) : super(repaint: squeeze);

  final _Row row;
  final _Squeeze squeeze;
  final bool boxes;

  @override
  void paint(Canvas canvas, Size size) {
    final t = squeeze.t;
    const oA = Offset(_rowX, _rowAY);
    const oB = Offset(_rowX, _rowBY);
    final s = row.size;

    // Baseline guides.
    final guide = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1;
    for (final o in [oA, oB]) {
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(o.dx - 20, o.dy + row.before.height / 2)
          ..lineTo(size.width, o.dy + row.before.height / 2)),
        guide,
      );
    }

    // Plain row.
    if (boxes) {
      for (var k = 0; k < row.boxB.length; k++) {
        _emBox(canvas, row.boxB[k].shift(oA), half: false, alpha: 0.9);
      }
    }
    row.before.paint(canvas, oA);

    // Spaced row, gliding between the two real layouts.
    if (boxes) {
      for (var k = 0; k < row.boxA.length; k++) {
        final half = row.halved[k];
        final r = row.boxAt(k, t).shift(oB);
        _emBox(canvas, r, half: half && t > 0.02);
        if (half && t > 0.5) {
          final lp = TextPainter(
            text: TextSpan(text: '½', style: _ja(15, color: BP.amber.withValues(alpha: (t - 0.5) * 2))),
            textDirection: TextDirection.ltr,
          )..layout();
          lp.paint(canvas, Offset(r.center.dx - lp.width / 2, r.top - lp.height - 2));
          lp.dispose();
        }
      }
    }
    row.paintAt(canvas, oB, t);

    // Widths, and what was saved.
    final endA = oA.dx + row.widthB;
    final endB = oB.dx + row.rightAt(t);
    _dim(canvas, oA.dx, endA, oA.dy + row.before.height + 10, _em(row.widthB, s), BP.inkDim);
    _dim(canvas, oB.dx, endB, oB.dy + row.after.height + 10, _em(row.rightAt(t), s), BP.line);
    final saved = row.widthB - row.rightAt(t);
    final c = row.widthB - row.widthA > 0.5 ? BP.amber : BP.red;
    final dash = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(dashPath(Path()
      ..moveTo(endA, oA.dy)
      ..lineTo(endA, oB.dy + row.after.height), dash: 4, gap: 4), dash);
    canvas.drawPath(dashPath(Path()
      ..moveTo(endB, oB.dy - 6)
      ..lineTo(endB, oB.dy + row.after.height), dash: 4, gap: 4), dash);
    final y = oB.dy - 18;
    final label = saved.abs() < 0.5 ? '±0' : '−${_em(saved, s)}';
    _dim(canvas, math.min(endA, endB), math.max(endA, endB), y, label, c, above: true);
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.row != row || old.boxes != boxes || old.squeeze != squeeze;
}

class _PairPainter extends CustomPainter {
  _PairPainter(this.row, this.squeeze, {required this.boxes}) : super(repaint: squeeze);

  final _Row row;
  final _Squeeze squeeze;
  final bool boxes;

  @override
  void paint(Canvas canvas, Size size) {
    final t = squeeze.t;
    final panel = Offset.zero & size;
    canvas.drawRect(panel, Paint()..color = BP.panel.withValues(alpha: 0.6));
    canvas.drawRect(
      panel,
      Paint()
        ..color = BP.lineFaint
        ..style = PaintingStyle.stroke,
    );
    final x = (size.width - row.widthB) / 2;
    final oA = Offset(x, 28);
    final oB = Offset(x, 28 + row.before.height + 34);
    for (var k = 0; k < row.boxB.length; k++) {
      _emBox(canvas, row.boxB[k].shift(oA), half: false, alpha: boxes ? 0.9 : 0.35);
    }
    row.before.paint(canvas, oA);
    for (var k = 0; k < row.boxA.length; k++) {
      _emBox(canvas, row.boxAt(k, t).shift(oB), half: row.halved[k] && t > 0.02, alpha: boxes ? 1 : 0.35);
    }
    row.paintAt(canvas, oB, t);
    // Arrow from plain to spaced.
    final ay0 = oA.dy + row.before.height + 6;
    drawArrow(
      canvas,
      Offset(size.width / 2, ay0),
      Offset(size.width / 2, oB.dy - 6),
      Paint()
        ..color = BP.lineDim
        ..strokeWidth = 1.2,
      head: 6,
    );
    final saved = row.widthB - row.rightAt(t);
    final c = row.widthB - row.widthA > 0.5 ? BP.amber : BP.red;
    final tp = TextPainter(
      text: TextSpan(text: saved.abs() < 0.5 ? '±0' : '−${_em(saved, row.size)}', style: BT.mono(14, color: c)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height - tp.height - 12));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_PairPainter old) => old.row != row || old.boxes != boxes || old.squeeze != squeeze;
}
