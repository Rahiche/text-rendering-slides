import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 4: ParagraphImpl's one-time Unicode pass. Each ICU iterator sweeps
/// the word and drops its flags into a per-code-point matrix; the result is
/// the word cut into bidi runs and script runs, ready to shape.
class JUnicodeSlide extends StatelessWidget {
  const JUnicodeSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 4,
    title: (_) => 'Unicode analysis',
    builder: (context, d) => _UnicodeStage(data: d),
  );
}

const _rows = [
  ('grapheme', 'UBRK_CHARACTER'),
  ('word', 'UBRK_WORD'),
  ('line break', 'UBRK_LINE'),
  ('whitespace', 'u_isWhitespace'),
  ('bidi level', 'ubidi'),
  ('script', 'uscript'),
];

// Geometry
const _mx = 330.0;
const _mw = 1472.0 - _mx;
const _headTop = 60.0;
const _headH = 88.0;
const _rowTop = _headTop + _headH + 8;
const _rowH = 40.0;
const _rowStep = 42.0;
double _ry(int r) => _rowTop + r * _rowStep;
const _matBottom = _rowTop + 6 * _rowStep;
const _bidiTop = 458.0;
const _scriptTop = 516.0;
const _barH = 42.0;

// Timeline (fractions of the loop)
const _passStart = 0.03;
const _passLen = 0.085;
const _resultAt = 0.58;
const _period = Duration(milliseconds: 12500);

bool _isWhitespace(int c) =>
    // ICU u_isWhitespace: White_Space minus the no-break spaces, plus FS..US.
    (c >= 0x09 && c <= 0x0D) ||
    (c >= 0x1C && c <= 0x20) ||
    c == 0x85 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x2006) ||
    (c >= 0x2008 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x205F ||
    c == 0x3000;

bool _isPunct(int c) =>
    (c >= 0x21 && c <= 0x2F && c != 0x27) ||
    (c >= 0x3A && c <= 0x40) ||
    (c >= 0x5B && c <= 0x60) ||
    (c >= 0x7B && c <= 0x7E) ||
    (c >= 0x2010 && c <= 0x2027 && c != 0x2019) ||
    (c >= 0x3001 && c <= 0x3003) ||
    c == 0x060C ||
    c == 0x061F;

/// ISO 15924 code, as ICU's uscript reports it.
String _iso(Script s, int cp) => switch (s) {
  Script.latin => 'Latn',
  Script.arabic => 'Arab',
  Script.hebrew => 'Hebr',
  Script.devanagari => 'Deva',
  Script.thai => 'Thai',
  Script.han => 'Hani',
  Script.kana => cp < 0x30A0 ? 'Hira' : 'Kana',
  Script.hangul => 'Hang',
  Script.cyrillic => 'Cyrl',
  Script.greek => 'Grek',
  Script.emoji || Script.common => 'Zyyy',
};

class _Analysis {
  const _Analysis({
    required this.grapheme,
    required this.word,
    required this.lineBreak,
    required this.space,
    required this.level,
    required this.bidiRuns,
    required this.scriptRuns,
  });

  /// Boundary flags, n + 1 entries (the last one is the end of text).
  final List<bool> grapheme;
  final List<bool> word;

  /// 0 none, 1 soft, 2 hard. n + 1 entries.
  final List<int> lineBreak;
  final List<bool> space;
  final List<int> level;

  /// Column ranges [start, end) with their level / script.
  final List<(int, int, int)> bidiRuns;
  final List<(int, int, Script, int)> scriptRuns;
}

_Analysis _analyze(JourneyData d, TextDirection dir) {
  final text = d.text;
  final cps = d.glyphs;
  final n = cps.length;
  int col(int offset) {
    for (var i = 0; i < n; i++) {
      if (cps[i].start >= offset) return i;
    }
    return n;
  }

  final clusters = <(int, int)>[];
  var o = 0;
  for (final g in text.characters) {
    clusters.add((o, o + g.length));
    o += g.length;
  }
  int first(int k) => text.runes.elementAt(col(clusters[k].$1));

  final grapheme = List<bool>.filled(n + 1, false);
  for (final (s, _) in clusters) {
    grapheme[col(s)] = true;
  }
  grapheme[n] = true;

  bool other(int cp) => _isWhitespace(cp) || _isPunct(cp);
  final word = List<bool>.filled(n + 1, false);
  word[0] = true;
  word[n] = true;
  for (var k = 1; k < clusters.length; k++) {
    final a = first(k - 1), b = first(k);
    final bothSpace = _isWhitespace(a) && _isWhitespace(b);
    if ((other(a) || other(b)) && !bothSpace) word[col(clusters[k].$1)] = true;
  }

  final lineBreak = List<int>.filled(n + 1, 0);
  for (var k = 1; k < clusters.length; k++) {
    final a = first(k - 1), b = first(k);
    if (a == 0x0A || a == 0x0D || a == 0x2028 || a == 0x2029) {
      lineBreak[col(clusters[k].$1)] = 2;
    } else if (_isWhitespace(a) && !_isWhitespace(b)) {
      lineBreak[col(clusters[k].$1)] = 1;
    }
  }
  lineBreak[n] = 2; // end of text: mandatory break

  final space = [for (final g in cps) _isWhitespace(g.codePoint)];

  // Bidi: the real resolved direction of each cluster, from the engine's own
  // layout of the word in a paragraph of direction [dir].
  final probe = TextProbe(TextSpan(text: text, style: journeyStyle(40)), textDirection: dir);
  final level = List<int>.filled(n, 0);
  for (final (s, e) in clusters) {
    final boxes = probe.boxes(s, e);
    final rtl = boxes.isNotEmpty ? boxes.first.direction == TextDirection.rtl : cps[col(s)].script.rtl;
    final lv = dir == TextDirection.ltr ? (rtl ? 1 : 0) : (rtl ? 1 : 2);
    for (var i = col(s); i < col(e); i++) {
      level[i] = lv;
    }
  }
  probe.dispose();

  final bidiRuns = <(int, int, int)>[];
  for (var i = 0; i < n; i++) {
    if (bidiRuns.isNotEmpty && bidiRuns.last.$3 == level[i]) {
      final r = bidiRuns.removeLast();
      bidiRuns.add((r.$1, i + 1, r.$3));
    } else {
      bidiRuns.add((i, i + 1, level[i]));
    }
  }
  final scriptRuns = [
    for (final r in itemize(text)) (col(r.start), col(r.end), r.script, r.text.runes.first),
  ];

  return _Analysis(
    grapheme: grapheme,
    word: word,
    lineBreak: lineBreak,
    space: space,
    level: level,
    bidiRuns: bidiRuns,
    scriptRuns: scriptRuns,
  );
}

class _UnicodeStage extends StatefulWidget {
  const _UnicodeStage({required this.data});

  final JourneyData data;

  @override
  State<_UnicodeStage> createState() => _UnicodeStageState();
}

class _UnicodeStageState extends State<_UnicodeStage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _period)..repeat();
  TextDirection _dir = TextDirection.ltr;
  late _Analysis _a = _analyze(widget.data, _dir);
  int? _hover;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _run() {
    _c.value = 0;
    _c.repeat();
  }

  void _setDir(TextDirection d) {
    setState(() {
      _dir = d;
      _a = _analyze(widget.data, d);
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.data.glyphs.length;
    if (n == 0) return const SizedBox();
    final colW = math.min(150.0, _mw / (n + 1));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('SkUnicode · ICU', style: BT.mono(20, color: BP.line)),
              const SizedBox(width: 18),
              Text('web: Intl.Segmenter', style: BT.mono(13, color: BP.inkFaint)),
            ],
          ),
        ),
        Positioned(
          right: 0,
          top: -2,
          child: Row(
            children: [
              Text('paragraph', style: BT.mono(13, color: BP.inkFaint)),
              const SizedBox(width: 12),
              BpSegmented<TextDirection>(
                values: const [TextDirection.ltr, TextDirection.rtl],
                selected: _dir,
                onChanged: _setDir,
                labelOf: (d) => d == TextDirection.ltr ? 'LTR' : 'RTL',
                size: 13,
              ),
              const SizedBox(width: 16),
              BpButton(label: 'run', icon: Icons.replay, size: 13, onTap: _run),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _frame(_c.value, n, colW),
            ),
          ),
        ),
        Positioned(
          left: _mx,
          top: _headTop,
          width: (n + 1) * colW,
          height: _matBottom - _headTop,
          child: MouseRegion(
            onHover: (e) => setState(() => _hover = (e.localPosition.dx / colW).floor().clamp(0, n)),
            onExit: (_) => setState(() => _hover = null),
          ),
        ),
      ],
    );
  }

  Widget _frame(double t, int n, double colW) {
    final a = _a;
    final glyphs = widget.data.glyphs;
    double colX(int c) => _mx + c * colW;
    final fade = 1 - ((t - 0.95) / 0.05).clamp(0.0, 1.0);

    int? pass;
    var pp = 0.0;
    for (var r = 0; r < _rows.length; r++) {
      final s = _passStart + r * _passLen;
      if (t >= s && t < s + _passLen) {
        pass = r;
        pp = (t - s) / _passLen;
      }
    }
    final barX = pass == null ? null : _mx + pp * (n + 1) * colW;
    final barCol = barX == null ? null : ((barX - _mx) / colW).floor();

    double pop(int r, int c) {
      final s = _passStart + r * _passLen;
      if (t < s) return 0;
      if (t >= s + _passLen) return 1;
      final cols = (t - s) / _passLen * (n + 1);
      return ((cols - c - 0.3) / 0.45).clamp(0.0, 1.0);
    }

    final res = Curves.easeOutCubic.transform(((t - _resultAt) / 0.08).clamp(0.0, 1.0));
    final arrow = ((t - _resultAt - 0.08) / 0.06).clamp(0.0, 1.0);
    final barsEnd = colX(n);
    final arrowX0 = math.min(barsEnd + 26, 1472.0 - 220);

    Widget cellMark(int r, int c) {
      Widget dot() => Container(width: 4, height: 4, color: BP.lineDim);
      switch (r) {
        case 0:
          return a.grapheme[c]
              ? Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(width: 13, height: 13, color: BP.amber),
                )
              : dot();
        case 1:
          return a.word[c] ? Container(width: 4, height: 26, color: BP.line) : dot();
        case 2:
          return switch (a.lineBreak[c]) {
            2 => const BpTag('hard', color: BP.coral, size: 12),
            1 => const BpTag('soft', color: BP.green, size: 12),
            _ => dot(),
          };
        case 3:
          return a.space[c] ? Container(width: 14, height: 14, color: BP.violet) : dot();
        case 4:
          final lv = a.level[c];
          return Text('$lv', style: BT.mono(22, color: lv.isOdd ? BP.amber : BP.line, weight: 600));
        default:
          final g = glyphs[c];
          return Text(_iso(g.script, g.codePoint), style: BT.mono(15, color: g.script.color));
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(
              n: n,
              colW: colW,
              pass: pass,
              barX: barX,
              hover: _hover,
              arrow: arrow * fade,
              arrowX0: arrowX0,
            ),
          ),
        ),

        // Row labels
        for (var r = 0; r < _rows.length; r++)
          Positioned(
            left: 0,
            top: _ry(r),
            height: _rowH,
            width: _mx - 16,
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    _rows[r].$1,
                    style: BT.mono(16, color: pass == r ? BP.amber : (pop(r, n) >= 1 ? BP.ink : BP.inkDim)),
                  ),
                ),
                Text(
                  _rows[r].$2,
                  style: BT.mono(12, color: pass == r ? BP.amber.withValues(alpha: 0.8) : BP.inkFaint),
                ),
              ],
            ),
          ),

        // Column headers: glyph + code point
        for (var c = 0; c <= n; c++)
          Positioned(
            left: colX(c),
            top: _headTop,
            width: colW,
            height: _headH,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: c == n
                    ? Text('end', style: BT.mono(14, color: barCol == c ? BP.amber : BP.inkFaint))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 48,
                            child: Center(
                              child: Text(
                                _visible(glyphs[c].codePoint),
                                style: journeyStyle(
                                  34,
                                  color: barCol == c || _hover == c ? BP.amber : BP.ink,
                                ).copyWith(height: 1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            glyphs[c].hex,
                            style: BT.mono(12, color: barCol == c ? BP.amber : BP.inkDim),
                          ),
                        ],
                      ),
              ),
            ),
          ),

        // Marks
        for (var r = 0; r < _rows.length; r++)
          for (var c = 0; c <= n; c++)
            if (c < n || r < 3)
              if (pop(r, c) > 0)
                Positioned(
                  left: colX(c),
                  top: _ry(r),
                  width: colW,
                  height: _rowH,
                  child: Center(
                    child: Opacity(
                      opacity: (pop(r, c) * fade).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: Curves.easeOutBack.transform(pop(r, c)),
                        child: cellMark(r, c),
                      ),
                    ),
                  ),
                ),

        // Result: itemize()
        Positioned(
          left: 0,
          top: _bidiTop - 34,
          child: Opacity(
            opacity: res * fade,
            child: Text('itemize()', style: BT.mono(13, color: BP.amber)),
          ),
        ),
        Positioned(
          left: 0,
          top: _bidiTop + 10,
          child: Text('bidi runs', style: BT.mono(16, color: res > 0 ? BP.ink : BP.inkFaint)),
        ),
        Positioned(
          left: 0,
          top: _scriptTop + 10,
          child: Text('script runs', style: BT.mono(16, color: res > 0 ? BP.ink : BP.inkFaint)),
        ),
        for (final (s, e, lv) in a.bidiRuns)
          _bar(
            left: colX(s) + 3,
            top: _bidiTop,
            width: ((e - s) * colW - 6) * res,
            opacity: fade,
            color: lv.isOdd ? BP.amber : BP.line,
            hot: _hover != null && _hover! >= s && _hover! < e,
            label: '${lv.isOdd ? '←' : '→'}  level $lv',
          ),
        for (final (s, e, sc, cp) in a.scriptRuns)
          _bar(
            left: colX(s) + 3,
            top: _scriptTop,
            width: ((e - s) * colW - 6) * res,
            opacity: fade,
            color: sc.color,
            hot: _hover != null && _hover! >= s && _hover! < e,
            label: sc == Script.emoji ? 'Zyyy · emoji' : _iso(sc, cp),
          ),
        Positioned(
          left: arrowX0 + 140,
          top: (_bidiTop + _scriptTop + _barH) / 2 - 14,
          child: Opacity(
            opacity: arrow * fade,
            child: Text('shape', style: BT.display(24, color: BP.amber)),
          ),
        ),
      ],
    );
  }

  static Widget _bar({
    required double left,
    required double top,
    required double width,
    required double opacity,
    required Color color,
    required bool hot,
    required String label,
  }) {
    if (width <= 1) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: _barH,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: hot ? 0.30 : 0.14),
            border: Border.all(color: color, width: hot ? 2 : 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: BT.mono(15, color: color)),
          ),
        ),
      ),
    );
  }

  static String _visible(int cp) {
    if (cp == 0x20) return 'SP';
    if (cp == 0x200D) return 'ZWJ';
    if (cp == 0xFE0F) return 'VS16';
    final s = String.fromCharCode(cp);
    final combining = (cp >= 0x0300 && cp <= 0x036F) || (cp >= 0x064B && cp <= 0x065F);
    return combining ? '◌$s' : s;
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.n,
    required this.colW,
    required this.pass,
    required this.barX,
    required this.hover,
    required this.arrow,
    required this.arrowX0,
  });

  final int n;
  final double colW;
  final int? pass;
  final double? barX;
  final int? hover;
  final double arrow;
  final double arrowX0;

  @override
  void paint(Canvas canvas, Size size) {
    final right = _mx + (n + 1) * colW;
    final faint = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1;
    final dim = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Active row band, hovered column band.
    if (pass != null) {
      canvas.drawRect(
        Rect.fromLTRB(_mx, _ry(pass!) - 1, right, _ry(pass!) + _rowH + 1),
        Paint()..color = BP.amber.withValues(alpha: 0.07),
      );
    }
    if (hover != null) {
      canvas.drawRect(
        Rect.fromLTWH(_mx + hover! * colW, _headTop, colW, _matBottom - _headTop),
        Paint()..color = BP.line.withValues(alpha: 0.08),
      );
    }

    // Grid
    canvas.drawRect(Rect.fromLTRB(_mx, _headTop, right, _matBottom), dim);
    canvas.drawLine(const Offset(_mx, _rowTop - 4), Offset(right, _rowTop - 4), dim);
    for (var r = 1; r < _rows.length; r++) {
      final y = _ry(r) - (_rowStep - _rowH) / 2;
      canvas.drawLine(Offset(_mx, y), Offset(right, y), faint);
    }
    for (var c = 1; c <= n; c++) {
      final x = _mx + c * colW;
      if (c == n) {
        canvas.drawPath(
          dashPath(
            Path()
              ..moveTo(x, _headTop)
              ..lineTo(x, _matBottom),
            dash: 5,
            gap: 4,
          ),
          dim,
        );
      } else {
        canvas.drawLine(Offset(x, _headTop), Offset(x, _matBottom), faint);
      }
    }

    // Scan bar
    if (barX != null) {
      final x = barX!;
      canvas.drawRect(
        Rect.fromLTRB(x - 14, _headTop, x, _matBottom),
        Paint()..color = BP.amber.withValues(alpha: 0.08),
      );
      canvas.drawLine(
        Offset(x, _headTop - 8),
        Offset(x, _matBottom + 8),
        Paint()
          ..color = BP.amber
          ..strokeWidth = 2,
      );
      final tri = Path()
        ..moveTo(x - 7, _headTop - 16)
        ..lineTo(x + 7, _headTop - 16)
        ..lineTo(x, _headTop - 7)
        ..close();
      canvas.drawPath(tri, Paint()..color = BP.amber);
    }

    // Runs → shape
    if (arrow > 0) {
      final p = Paint()
        ..color = BP.amber.withValues(alpha: arrow)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final x0 = arrowX0;
      const yA = _bidiTop + _barH / 2;
      const yB = _scriptTop + _barH / 2;
      const yM = (yA + yB) / 2;
      final bracket = Path()
        ..moveTo(x0 - 22, yA)
        ..lineTo(x0, yA)
        ..lineTo(x0, yB)
        ..lineTo(x0 - 22, yB);
      canvas.drawPath(partialPath(bracket, arrow), p);
      drawArrow(canvas, Offset(x0, yM), Offset(x0 + 128, yM), p, progress: arrow, head: 10);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}
