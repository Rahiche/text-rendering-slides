import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 3: TextPainter's calls into dart:ui, and what they build on the C++
/// side of the @Native boundary. The word crosses as UTF-16 and is stored as
/// UTF-8. The same calls are run for real to produce the paragraph shown.
class JBuilderSlide extends StatelessWidget {
  const JBuilderSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 3,
    title: (_) => 'Into the engine',
    builder: (context, d) => _EngineStage(data: d),
  );
}

// ── Geometry ────────────────────────────────────────────────────────────────
const _boundaryX = 712.0;
const _codeTop = 84.0;
const _rowH = 48.0;
const _gutter = 44.0;
const _codeSize = 19.0;
const _scrubTop = 440.0;
const _scrubW = 640.0;

const _cppX = 760.0;
const _cppW = 712.0;
const _labelX = _cppX + 24;
const _valX = 950.0;
const _valR = 1352.0;
const _chipH = 26.0;

const _boxATop = 70.0;
const _boxAH = 300.0;
const _yHeadA = _boxATop + 22;
const _yU16 = 142.0;
const _yUtf8 = 190.0;
const _yStack = 238.0;
const _yBlocks = 286.0;
const _yPh = 334.0;

const _boxBTop = 410.0;
const _boxBH = 202.0;
const _yHeadB = _boxBTop + 22;
const _yFields = _boxBTop + 72;
const _yLayout = _boxBTop + 118;
const _yResult = _boxBTop + 164;
const _paraX = 1284.0;
const _paraW = 164.0;

const _layoutWidth = 360.0;

/// Timeline: start of each statement, then the end of the last one.
const _seg = [0.0, 0.08, 0.17, 0.47, 0.56, 0.65, 0.88];
const _period = Duration(milliseconds: 12500);

/// Code rows → statement index.
const _rowStmt = [0, 0, 1, 2, 3, 4, 5];

List<(String, Color)> _row(int r, String word) => switch (r) {
  0 => [('final ', BP.violet), ('b = ', BP.ink), ('ParagraphBuilder', BP.line), ('(', BP.inkDim)],
  1 => [
    ('    ParagraphStyle', BP.line),
    ('(textDirection: ', BP.inkDim),
    ('TextDirection', BP.line),
    ('.ltr', BP.ink),
    ('));', BP.inkDim),
  ],
  2 => [('b.pushStyle', BP.ink), ('(style.', BP.inkDim), ('getTextStyle', BP.ink), ('());', BP.inkDim)],
  3 => [('b.addText', BP.ink), ("('", BP.inkDim), (word, BP.amber), ("');", BP.inkDim)],
  4 => [('b.pop', BP.ink), ('();', BP.inkDim)],
  5 => [('final ', BP.violet), ('p = b.build', BP.ink), ('();', BP.inkDim)],
  _ => [
    ('p.layout', BP.ink),
    ('(', BP.inkDim),
    ('ParagraphConstraints', BP.line),
    ('(width: ', BP.inkDim),
    ('${_layoutWidth.round()}', BP.coral),
    ('));', BP.inkDim),
  ],
};

double _clamp01(double v) => v.clamp(0.0, 1.0);
double _sub(double p, double a, double b) => _clamp01((p - a) / (b - a));
double _ease(double v) => Curves.easeInOutCubic.transform(_clamp01(v));

/// Progress (0..1) of statement [i] at time [t].
double _p(double t, int i) => _sub(t, _seg[i], _seg[i + 1]);

String _hex(int v, int w) => v.toRadixString(16).toUpperCase().padLeft(w, '0');

class _EngineStage extends StatefulWidget {
  const _EngineStage({required this.data});

  final JourneyData data;

  @override
  State<_EngineStage> createState() => _EngineStageState();
}

class _EngineStageState extends State<_EngineStage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _period)..repeat();
  late final String _word = widget.data.text;
  late final List<int> _units = _word.codeUnits;
  late final List<int> _bytes = utf8.encode(_word);

  /// Per code point: (first unit, unit count, first byte, byte count).
  late final List<(int, int, int, int)> _map;
  late final ui.Paragraph _para;
  late final Offset _wordAnchor;
  late final Offset _styleAnchor;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    final map = <(int, int, int, int)>[];
    var b = 0;
    for (final g in widget.data.glyphs) {
      final nb = utf8.encode(g.char).length;
      map.add((g.start, g.end - g.start, b, nb));
      b += nb;
    }
    _map = map;

    // The exact calls on the left, run for real.
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: TextDirection.ltr))
      ..pushStyle(journeyStyle(48).getTextStyle())
      ..addText(_word)
      ..pop();
    _para = builder.build()..layout(const ui.ParagraphConstraints(width: _layoutWidth));

    // Where the word / the style sit in their code rows (flight origins).
    double measure(String s) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: BT.mono(_codeSize)),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final pre = measure("b.addText('");
    final ww = measure(_word);
    _wordAnchor = Offset(_gutter + 8 + pre + ww / 2, _codeTop + 3 * _rowH + _rowH / 2 - 2);
    _styleAnchor = Offset(_gutter + 8 + measure('b.pushStyle(style.getTextStyle'), _codeTop + 2 * _rowH + _rowH / 2 - 2);
  }

  @override
  void dispose() {
    _c.dispose();
    _para.dispose();
    super.dispose();
  }

  void _toggle() => setState(() {
    _playing = !_playing;
    _playing ? _c.repeat() : _c.stop();
  });

  void _seek(double v) {
    _c.value = v.clamp(0.0, 0.999);
    if (_playing) _c.repeat();
  }

  void _seekStmt(int i) => _seek(_playing ? _seg[i] + 0.0005 : _seg[i + 1] - 0.0005);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Headers
        Positioned(
          left: 0,
          top: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dart', style: BT.display(30)),
              Text('TextPainter.layout()', style: BT.mono(14, color: BP.inkFaint)),
            ],
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('C++', style: BT.display(30)),
              Text('engine', style: BT.mono(14, color: BP.inkFaint)),
            ],
          ),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _frame(context, _c.value),
          ),
        ),
        // Controls
        Positioned(
          left: 0,
          top: _scrubTop,
          width: _scrubW,
          height: 44,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _seek(d.localPosition.dx / _scrubW),
              onPanUpdate: (d) => _seek(d.localPosition.dx / _scrubW),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _ScrubPainter(_c.value)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: _scrubTop + 70,
          child: BpButton(
            label: _playing ? 'pause' : 'play',
            icon: _playing ? Icons.pause : Icons.play_arrow,
            size: 14,
            onTap: _toggle,
          ),
        ),
      ],
    );
  }

  Widget _frame(BuildContext context, double t) {
    int? active;
    for (var i = 0; i < 6; i++) {
      if (t >= _seg[i] && t < _seg[i + 1]) active = i;
    }
    final fade = 1 - _sub(t, 0.955, 1.0);
    final p0 = _p(t, 0), p1 = _p(t, 1), p2 = _p(t, 2), p3 = _p(t, 3), p4 = _p(t, 4), p5 = _p(t, 5);

    final n = _units.length;
    final m = _bytes.length;
    final cps = _map.length;
    final uw = math.min(56.0, (_valR - _valX - (n - 1) * 6) / n);
    final bw = math.min(44.0, (_valR - _valX - (m - 1) * 6) / math.max(1, m));
    double ux(int k) => _valX + k * (uw + 6);
    double bx(int j) => _valX + j * (bw + 6);

    // Unit k flies across the boundary, staggered.
    double unitStart(int k) => 0.02 + 0.26 * (n == 1 ? 0 : k / (n - 1));
    double unitF(int k) => _ease(_sub(p2, unitStart(k), unitStart(k) + 0.18));
    // Code point q converts to its UTF-8 bytes, staggered.
    double cpStart(int q) => 0.52 + 0.30 * (cps == 1 ? 0 : q / (cps - 1));
    double cpF(int q) => _ease(_sub(p2, cpStart(q), cpStart(q) + 0.14));

    final landedUnits = [for (var k = 0; k < n; k++) if (unitF(k) >= 1) k].length;
    var landedBytes = 0;
    for (var q = 0; q < cps; q++) {
      if (cpF(q) >= 1) landedBytes += _map[q].$4;
    }
    final crossing = (p1 > 0.05 && p1 < 0.8) || (p2 > 0.02 && p2 < 0.5);

    final dimA = 1 - 0.5 * _ease(p4);
    final boxA = _ease(_sub(p0, 0, 0.5)) * fade * dimA;
    final boxB = _ease(_sub(p4, 0.2, 0.8)) * fade;
    final styleIn = _ease(_sub(p1, 0.05, 0.75));
    final styleOut = _ease(_sub(p3, 0.1, 0.6));
    final blockEnd = (m * _ease(_sub(p3, 0.2, 0.8))).round();
    final result = _ease(_sub(p5, 0.82, 1)) * fade;

    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _LinesPainter(
            crossing: crossing,
            buildArrow: _sub(p4, 0, 0.5) * fade,
            maps: [
              for (var q = 0; q < cps; q++)
                if (cpF(q) > 0)
                  (
                    Offset(
                      (ux(_map[q].$1) + ux(_map[q].$1 + _map[q].$2 - 1) + uw) / 2,
                      _yU16 + _chipH / 2,
                    ),
                    Offset(
                      (bx(_map[q].$3) + bx(_map[q].$3 + _map[q].$4 - 1) + bw) / 2,
                      _yUtf8 - _chipH / 2,
                    ),
                    cpF(q) * fade,
                  ),
            ],
          ),
        ),
      ),
      Positioned(
        left: _boundaryX - 125,
        top: 0,
        width: 250,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: BP.paper,
              border: Border.all(color: crossing ? BP.amber : BP.lineDim),
            ),
            child: Text('dart:ui · @Native FFI', style: BT.mono(13, color: crossing ? BP.amber : BP.line)),
          ),
        ),
      ),

      // ── Dart code ──────────────────────────────────────────────────────
      for (var r = 0; r < _rowStmt.length; r++)
        Positioned(
          left: 0,
          top: _codeTop + r * _rowH,
          width: _boundaryX - 30,
          height: _rowH - 4,
          child: _CodeRow(
            number: r == 0 || _rowStmt[r] != _rowStmt[r - 1] ? '${_rowStmt[r] + 1}' : '',
            spans: _row(r, _word),
            state: active == _rowStmt[r] ? 1 : (t >= _seg[_rowStmt[r] + 1] ? 2 : 0),
            onTap: () => _seekStmt(_rowStmt[r]),
          ),
        ),

      // ── C++: txt::ParagraphBuilderSkia ────────────────────────────────
      Positioned(
        left: _cppX,
        top: _boxATop,
        width: _cppW,
        height: _boxAH,
        child: Opacity(
          opacity: boxA,
          child: const BpPanel(label: 'txt::ParagraphBuilderSkia', child: SizedBox.expand()),
        ),
      ),
      _at(_labelX, _yHeadA, boxA, Text('└ skia::textlayout::ParagraphBuilder', style: BT.mono(16, color: BP.ink))),
      for (final (y, label) in const [
        (_yU16, 'std::u16string'),
        (_yUtf8, 'text · UTF-8'),
        (_yStack, 'style stack'),
        (_yBlocks, 'blocks'),
        (_yPh, 'placeholders'),
      ])
        _at(_labelX, y + 4, boxA, Text(label, style: BT.mono(13, color: BP.inkFaint))),

      // style stack
      _at(_valX, _yStack + 2, boxA * (1 - styleIn * (1 - styleOut)), Text('[ ]', style: BT.mono(15, color: BP.inkFaint))),
      // blocks
      if (p1 > 0.75)
        _at(
          _valX,
          _yBlocks,
          boxA,
          _Chip(
            text: '[0, $blockEnd)  → TextStyle',
            color: blockEnd == m && m > 0 ? BP.green : BP.lineDim,
          ),
        ),
      // placeholders
      _at(_valX, _yPh + 2, boxA, Text('[ ]', style: BT.mono(15, color: BP.inkDim))),

      // counts
      if (landedUnits > 0)
        _at(_valR + 14, _yU16 + 4, boxA, Text('$landedUnits units', style: BT.mono(13, color: BP.inkDim))),
      if (landedBytes > 0)
        _at(
          _valR + 14,
          _yUtf8 + 4,
          fade * dimA,
          Text(
            '$landedBytes bytes',
            style: BT.mono(13, color: landedBytes == m && m != n ? BP.amber : BP.inkDim),
          ),
        ),

      // ── C++: txt::ParagraphSkia → ParagraphImpl ───────────────────────
      Positioned(
        left: _cppX,
        top: _boxBTop,
        width: _cppW,
        height: _boxBH,
        child: Opacity(
          opacity: boxB,
          child: const BpPanel(label: 'txt::ParagraphSkia', child: SizedBox.expand()),
        ),
      ),
      _at(_labelX, _yHeadB, boxB, Text('└ skia::textlayout::ParagraphImpl', style: BT.mono(16, color: BP.ink))),
      _at(
        _labelX,
        _yFields - 13,
        boxB,
        Row(
          children: [
            _Chip(text: 'text · $m bytes', color: BP.line),
            const SizedBox(width: 8),
            const _Chip(text: 'blocks · 1', color: BP.line),
            const SizedBox(width: 8),
            const _Chip(text: 'UTF-8 ↔ UTF-16', color: BP.lineDim),
          ],
        ),
      ),
      _at(
        _labelX,
        _yLayout - 13,
        _ease(_sub(p5, 0, 0.12)) * fade,
        Row(
          children: [
            SizedBox(
              width: 116,
              child: Text('layout(${_layoutWidth.round()})', style: BT.mono(14, color: BP.amber)),
            ),
            for (final (i, (name, id)) in const [
              ('unicode', 'j-unicode'),
              ('shape', 'j-shape'),
              ('wrap', 'j-layout'),
              ('format', 'j-layout'),
            ].indexed) ...[
              if (i > 0) Text(' → ', style: BT.mono(13, color: BP.inkFaint)),
              _StageChip(
                text: name,
                state: _stageState(p5, i),
                onTap: () => DeckScope.read(context).goToId(id),
              ),
            ],
          ],
        ),
      ),
      _at(
        _labelX,
        _yResult - 10,
        result,
        Text(
          'longestLine ${_para.longestLine.toStringAsFixed(1)}   height ${_para.height.toStringAsFixed(1)}',
          style: BT.mono(13, color: BP.green),
        ),
      ),
      Positioned(
        left: _paraX,
        top: _boxBTop + 44,
        width: _paraW,
        height: _boxBH - 64,
        child: Opacity(opacity: result, child: CustomPaint(painter: _ParagraphPainter(_para))),
      ),
    ];

    // ── Flying things (on top) ───────────────────────────────────────────
    // pushStyle: the style crosses the boundary, sits on the stack, pops off.
    if (p1 > 0.05 && styleOut < 1) {
      final pos = _arc(_styleAnchor - const Offset(0, _chipH / 2), const Offset(_valX, _yStack), styleIn);
      children.add(
        Positioned(
          left: pos.dx,
          top: pos.dy - 20 * styleOut,
          child: Opacity(
            opacity: (1 - styleOut) * fade,
            child: _Chip(
              text: 'TextStyle · ${BP.display} · 48',
              color: styleIn < 1 ? BP.amber : BP.line,
            ),
          ),
        ),
      );
    }

    // addText: UTF-16 units cross, then become UTF-8 bytes.
    for (var q = 0; q < cps; q++) {
      final (u0, un, b0, bn) = _map[q];
      final converted = cpF(q);
      for (var k = u0; k < u0 + un; k++) {
        final f = unitF(k);
        if (p2 <= unitStart(k)) continue;
        final dst = Offset(ux(k), _yU16);
        final src = Offset(_wordAnchor.dx - uw / 2, _wordAnchor.dy - _chipH / 2);
        final pos = _arc(src, dst, f);
        children.add(
          Positioned(
            left: pos.dx,
            top: pos.dy,
            width: uw,
            height: _chipH,
            child: Opacity(
              opacity: fade * dimA * (1 - 0.55 * converted),
              child: _Cell(
                text: _hex(_units[k], 4),
                color: f < 1 ? BP.amber : (un == 2 ? BP.coral : BP.line),
              ),
            ),
          ),
        );
      }
      if (converted <= 0) continue;
      final src = Offset((ux(u0) + ux(u0 + un - 1) + uw) / 2, _yU16);
      for (var j = b0; j < b0 + bn; j++) {
        final dst = Offset(bx(j) + bw / 2, _yUtf8);
        final pos = Offset.lerp(src, dst, converted)!;
        children.add(
          Positioned(
            left: pos.dx - bw / 2,
            top: pos.dy,
            width: bw,
            height: _chipH,
            child: Opacity(
              opacity: fade * dimA,
              child: _Cell(
                text: _hex(_bytes[j], 2),
                color: converted < 1 ? BP.amber : (bn > un ? BP.amber : BP.green),
              ),
            ),
          ),
        );
      }
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }

  static int _stageState(double p5, int i) {
    final a = 0.14 + i * 0.17;
    if (p5 < a) return 0;
    if (p5 < a + 0.17) return 1;
    return 2;
  }

  /// Quadratic arc from [a] to [b], lifted in the middle.
  static Offset _arc(Offset a, Offset b, double f) {
    final c = Offset((a.dx + b.dx) / 2, math.min(a.dy, b.dy) - 70);
    final u = 1 - f;
    return a * (u * u) + c * (2 * u * f) + b * (f * f);
  }

  static Widget _at(double x, double y, double opacity, Widget child) => Positioned(
    left: x,
    top: y,
    child: IgnorePointer(
      ignoring: opacity < 0.5,
      child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
    ),
  );
}

class _CodeRow extends StatefulWidget {
  const _CodeRow({required this.number, required this.spans, required this.state, required this.onTap});

  final String number;
  final List<(String, Color)> spans;

  /// 0 pending, 1 running, 2 done.
  final int state;
  final VoidCallback onTap;

  @override
  State<_CodeRow> createState() => _CodeRowState();
}

class _CodeRowState extends State<_CodeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final running = widget.state == 1;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: running
              ? BP.amber.withValues(alpha: 0.09)
              : (_hover ? BP.line.withValues(alpha: 0.06) : Colors.transparent),
          child: Row(
            children: [
              Container(width: 3, color: running ? BP.amber : Colors.transparent),
              SizedBox(
                width: _gutter - 3,
                child: Text(
                  widget.number,
                  textAlign: TextAlign.center,
                  style: BT.mono(14, color: running ? BP.amber : BP.inkFaint),
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: widget.state == 0 ? 0.38 : 1,
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (final (s, c) in widget.spans)
                        TextSpan(text: s, style: BT.mono(_codeSize, color: c)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: _chipH,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color),
    ),
    child: Text(text, style: BT.mono(13, color: color == BP.lineDim ? BP.inkDim : color)),
  );
}

/// A fixed-size memory cell (UTF-16 unit or UTF-8 byte).
class _Cell extends StatelessWidget {
  const _Cell({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: BP.panel,
      border: Border.all(color: color),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: BT.mono(13, color: color)),
    ),
  );
}

class _StageChip extends StatelessWidget {
  const _StageChip({required this.text, required this.state, required this.onTap});

  final String text;

  /// 0 waiting, 1 running, 2 done.
  final int state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = switch (state) {
      1 => BP.amber,
      2 => BP.line,
      _ => BP.lineDim,
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: _chipH,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: state == 1 ? BP.amber : c.withValues(alpha: 0.10),
            border: Border.all(color: c),
          ),
          child: Text(text, style: BT.mono(13, color: state == 1 ? BP.paper : (state == 2 ? BP.line : BP.inkDim))),
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter({required this.crossing, required this.buildArrow, required this.maps});

  final bool crossing;
  final double buildArrow;

  /// UTF-16 group → UTF-8 group connectors: (from, to, opacity).
  final List<(Offset, Offset, double)> maps;

  @override
  void paint(Canvas canvas, Size size) {
    // The FFI boundary
    canvas.drawPath(
      dashPath(
        Path()
          ..moveTo(_boundaryX, 34)
          ..lineTo(_boundaryX, size.height),
        dash: 8,
        gap: 6,
      ),
      Paint()
        ..color = crossing ? BP.amber : BP.line.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = crossing ? 2 : 1.5,
    );
    for (final (a, b, o) in maps) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = BP.lineDim.withValues(alpha: o.clamp(0.0, 1.0))
          ..strokeWidth = 1,
      );
    }
    if (buildArrow > 0) {
      drawArrow(
        canvas,
        const Offset(1100, _boxATop + _boxAH + 4),
        const Offset(1100, _boxBTop - 6),
        Paint()
          ..color = BP.line
          ..strokeWidth = 1.5,
        progress: buildArrow,
        head: 7,
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}

class _ScrubPainter extends CustomPainter {
  _ScrubPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 12.0;
    final dim = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, y), Offset(size.width, y), dim);
    canvas.drawLine(
      const Offset(0, y),
      Offset(size.width * t, y),
      Paint()
        ..color = BP.line
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 6; i++) {
      final x = size.width * _seg[i];
      final on = t >= _seg[i];
      canvas.drawLine(Offset(x, y - 7), Offset(x, y + 7), on ? (Paint()..color = BP.line) : dim);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: BT.mono(12, color: on ? BP.inkDim : BP.inkFaint)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 5, y + 6));
      tp.dispose();
    }
    final x = size.width * t;
    final d = Path()
      ..moveTo(x, y - 8)
      ..lineTo(x + 8, y)
      ..lineTo(x, y + 8)
      ..lineTo(x - 8, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_ScrubPainter old) => old.t != t;
}

/// Paints the real ui.Paragraph built from the calls on the left.
class _ParagraphPainter extends CustomPainter {
  _ParagraphPainter(this.paragraph);

  final ui.Paragraph paragraph;

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.max(1.0, paragraph.longestLine);
    final h = math.max(1.0, paragraph.height);
    final s = math.min(1.0, math.min(size.width / w, size.height / h));
    final o = Offset((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(s);
    canvas.drawPath(
      dashPath(Path()..addRect(Rect.fromLTWH(0, 0, w, h)), dash: 5, gap: 4),
      Paint()
        ..color = BP.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / s,
    );
    canvas.drawParagraph(paragraph, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ParagraphPainter old) => old.paragraph != paragraph;
}
