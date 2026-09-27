import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kumihan/kumihan.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// 文節で改行: the same headline laid out by plain Flutter (left) and by
/// kumihan (right) at one shared, draggable width. Real layouts: words split
/// across lines (泣き別れ), kinsoku violations (禁則) and lone last characters
/// (孤立) are found by comparing line breaks against BudouX phrases.
class PhraseLabSlide extends StatefulWidget {
  const PhraseLabSlide({super.key});

  @override
  State<PhraseLabSlide> createState() => _PhraseLabSlideState();
}

class _Preset {
  const _Preset(this.label, this.text, {this.size = 46, this.bold = true, this.height = 1.42, this.minW = 210});

  final String label;
  final String text;
  final double size;
  final bool bold;
  final double height;
  final double minW;

  TextStyle get style => TextStyle(
    fontFamily: 'Hiragino Sans',
    fontFamilyFallback: const ['Hiragino Kaku Gothic ProN', 'Noto Sans JP', 'Noto Sans CJK JP'],
    fontSize: size,
    height: height,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: BP.ink,
    locale: const Locale('ja'),
  );
}

const _presets = [
  _Preset('見出し 1', 'Flutterで日本語の改行をきれいにする方法'),
  _Preset('見出し 2', '今日は天気です。明日も晴れるでしょう。'),
  _Preset('見出し 3', 'テキストレンダリングの仕組みを理解しよう'),
  _Preset(
    '段落',
    'カンファレンスのセッションでは、ショートカットやキャッシュの仕組みについてディスカッションしました。'
        'ちょっとしたチューニングでパフォーマンスがぐっと良くなります。',
    size: 24,
    bold: false,
    height: 1.75,
    minW: 180,
  ),
];

// Geometry inside the content area (1472 × 628).
const _panelTop = 64.0;
const _panelW = 716.0;
const _panelH = 520.0;
const _rightX = 756.0;
const _textX = 36.0; // text origin inside a panel
const _textY = 88.0;
const _maxW = 624.0;

/// split: a phrase broken although it fits the line (泣き別れ); forced: the
/// phrase is wider than the line, so any engine has to break it.
enum _MarkKind { split, forced, kinsoku, orphan }

class _Mark {
  const _Mark(this.kind, this.from, this.to);

  final _MarkKind kind;

  /// Source grapheme range [from, to] (inclusive), all on one line.
  final int from;
  final int to;
}

/// One side of the comparison: a real paragraph plus what we found in it.
class _Side {
  _Side(this.kumihan);

  final bool kumihan;
  TextPainter? tp;
  String display = '';
  KumihanPrepared? prepared;
  double layoutW = 0;

  final target = <Rect>[]; // per source grapheme, in paragraph coordinates
  final shown = <Offset>[]; // animated top-left per source grapheme
  final lineOf = <int>[];
  final bands = <Rect>[];
  final marks = <_Mark>[];
  final ticks = <int>[]; // grapheme indices starting a phrase, mid-line
  final goodBreaks = <int>[]; // grapheme indices ending a line at a phrase end
  int splits = 0;
  int forced = 0;
  int kinsoku = 0;
  int orphans = 0;

  void dispose() => tp?.dispose();
}

class _Lab extends ChangeNotifier {
  final left = _Side(false);
  final right = _Side(true);
  double w = 520;
  double fade = 1;

  void notify() => notifyListeners();
}

class _PhraseLabSlideState extends State<PhraseLabSlide> with SingleTickerProviderStateMixin {
  final _lab = _Lab();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0;
  double _fadeT = 1;

  int _preset = 0;
  bool _phrases = true;
  bool _strict = true;
  bool _balance = false;
  bool _auto = true;

  KumihanLayout? _layout;
  KumihanLayout? _plain; // for balancing plain text when kumihan is off
  Set<int> _bounds = {};

  _Preset get _p => _presets[_preset];

  @override
  void initState() {
    super.initState();
    _load(animate: false);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _lab.left.dispose();
    _lab.right.dispose();
    _layout?.dispose();
    _plain?.dispose();
    _lab.dispose();
    super.dispose();
  }

  /// New text or new options: rebuild the analysis, relayout both sides.
  void _load({bool animate = true, bool resetGlide = true}) {
    _layout?.dispose();
    _layout = KumihanLayout(_p.text, style: _p.style, phrases: _phrases, strictKinsoku: _strict, locale: const Locale('ja'));
    _plain?.dispose();
    _plain = KumihanLayout(_p.text, style: _p.style, phrases: false, strictKinsoku: false, locale: const Locale('ja'));
    _bounds = _layout!.phraseBoundaries.toSet();
    _lab.w = _lab.w.clamp(_p.minW, _maxW);
    for (final s in [_lab.left, _lab.right]) {
      if (resetGlide) {
        s.tp?.dispose();
        s.tp = null;
        s.shown.clear();
      }
      _relayout(s);
      if (resetGlide) {
        s.shown
          ..clear()
          ..addAll(s.target.map((r) => r.topLeft));
      }
    }
    if (animate && resetGlide) _fadeT = 0;
  }

  void _relayout(_Side s) {
    final layout = _layout!;
    final text = _p.text;
    final w = _lab.w;
    if (s.kumihan && (_phrases || _strict)) {
      final p = layout.prepare(w);
      s.prepared = p;
      s.display = p.text;
      s.layoutW = _balance ? layout.balancedWidth(w, prepared: p) : w;
    } else {
      s.prepared = null;
      s.display = text;
      s.layoutW = s.kumihan && _balance ? _plainBalance(w) : w;
    }
    if (s.tp == null || s.tp!.plainText != s.display) {
      s.tp?.dispose();
      s.tp = TextPainter(
        text: TextSpan(text: s.display, style: _p.style),
        textDirection: TextDirection.ltr,
        locale: const Locale('ja'),
      );
    }
    final tp = s.tp!..layout(maxWidth: s.layoutW);

    final n = layout.graphemeCount;
    s.target.clear();
    for (var k = 0; k < n; k++) {
      final a = layout.graphemeStart(k);
      final b = layout.graphemeStart(k + 1);
      final da = s.prepared?.toDisplay(a) ?? a;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: da, extentOffset: da + (b - a)));
      s.target.add(boxes.isEmpty ? Rect.zero : boxes.first.toRect());
    }
    while (s.shown.length < s.target.length) {
      s.shown.add(s.target[s.shown.length].topLeft);
    }

    s.bands
      ..clear()
      ..addAll([
        for (final l in tp.computeLineMetrics())
          Rect.fromLTWH(0, l.baseline - l.ascent, s.layoutW, l.ascent + l.descent),
      ]);
    s.lineOf.clear();
    for (final r in s.target) {
      var li = 0;
      for (var i = 0; i < s.bands.length; i++) {
        if (r.center.dy >= s.bands[i].top - 1) li = i;
      }
      s.lineOf.add(li);
    }
    _analyze(s);
  }

  /// Plain Flutter text balanced the same way (when kumihan is switched off).
  double _plainBalance(double w) => _plain!.balancedWidth(w);

  void _analyze(_Side s) {
    final layout = _layout!;
    final text = _p.text;
    final n = layout.graphemeCount;
    s.marks.clear();
    s.ticks.clear();
    s.goodBreaks.clear();
    s.splits = s.forced = s.kinsoku = s.orphans = 0;
    final adv = layout.graphemeAdvances;
    if (n == 0) return;
    int phraseStartOf(int k) {
      var ps = 0;
      for (var j = 1; j <= k; j++) {
        if (_bounds.contains(layout.graphemeStart(j))) ps = j;
      }
      return ps;
    }

    int phraseEndOf(int k) {
      for (var j = k + 1; j < n; j++) {
        if (_bounds.contains(layout.graphemeStart(j))) return j - 1;
      }
      return n - 1;
    }

    int cp(int k) => text.codeUnitAt(layout.graphemeStart(k));
    for (var k = 1; k < n; k++) {
      final isBreak = s.lineOf[k] != s.lineOf[k - 1];
      final atBound = _bounds.contains(layout.graphemeStart(k));
      if (!isBreak) {
        if (atBound) s.ticks.add(k);
        continue;
      }
      if (atBound) {
        s.goodBreaks.add(k - 1);
      } else {
        final ps = phraseStartOf(k - 1);
        final pe = phraseEndOf(k);
        var pw = 0.0;
        for (var j = ps; j <= pe; j++) {
          pw += adv[j];
        }
        final kind = pw > _lab.w + 0.001 ? _MarkKind.forced : _MarkKind.split;
        kind == _MarkKind.split ? s.splits++ : s.forced++;
        s.marks.add(_Mark(kind, ps, k - 1));
        s.marks.add(_Mark(kind, k, pe));
      }
      if (isLineStartProhibited(cp(k))) {
        s.kinsoku++;
        s.marks.add(_Mark(_MarkKind.kinsoku, k, k));
      } else if (isLineEndProhibited(cp(k - 1))) {
        s.kinsoku++;
        s.marks.add(_Mark(_MarkKind.kinsoku, k - 1, k - 1));
      }
    }
    final lastLine = s.lineOf.last;
    if (lastLine > 0 && s.lineOf.where((l) => l == lastLine).length == 1) {
      s.orphans++;
      s.marks.add(_Mark(_MarkKind.orphan, n - 1, n - 1));
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    final lab = _lab;
    if (_auto) {
      _phase += dt;
      final lo = _p.minW;
      final t = 0.5 + 0.5 * math.sin(_phase * 2 * math.pi / 14 + math.pi / 2);
      final w = lo + (_maxW - 40 - lo) * t;
      if ((w - lab.w).abs() > 0.25) {
        lab.w = w;
        _relayout(lab.left);
        _relayout(lab.right);
      }
    }
    final k = 1 - math.exp(-dt / 0.08);
    for (final s in [lab.left, lab.right]) {
      for (var i = 0; i < s.target.length; i++) {
        final t = s.target[i].topLeft;
        final c = s.shown[i];
        s.shown[i] = (t - c).distance < 0.3 ? t : Offset.lerp(c, t, k)!;
      }
    }
    _fadeT = math.min(1, _fadeT + dt / 0.45);
    lab.fade = Curves.easeOutCubic.transform(_fadeT);
    lab.notify();
  }

  void _drag(double dx) {
    _lab.w = (_lab.w + dx).clamp(_p.minW, _maxW);
    _relayout(_lab.left);
    _relayout(_lab.right);
    if (_auto) setState(() => _auto = false);
  }

  void _toggle(void Function() f) {
    setState(f);
    _load(resetGlide: false);
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Phrase breaking',
      trailing: Text('文節で改行', style: _ja(34, BP.inkDim)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: BpSegmented<int>(
              values: const [0, 1, 2, 3],
              selected: _preset,
              labelOf: (i) => _presets[i].label,
              onChanged: (i) {
                setState(() => _preset = i);
                _load();
              },
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Row(
              children: [
                BpButton(
                  label: '文節 phrases',
                  selected: _phrases,
                  onTap: () => _toggle(() => _phrases = !_phrases),
                ),
                const SizedBox(width: 8),
                BpButton(
                  label: '禁則 kinsoku',
                  selected: _strict,
                  onTap: () => _toggle(() => _strict = !_strict),
                ),
                const SizedBox(width: 8),
                BpButton(
                  label: 'balance',
                  selected: _balance,
                  color: BP.violet,
                  onTap: () => _toggle(() => _balance = !_balance),
                ),
                const SizedBox(width: 28),
                BpButton(
                  label: 'auto',
                  selected: _auto,
                  color: BP.amber,
                  onTap: () => setState(() => _auto = !_auto),
                ),
              ],
            ),
          ),
          _panel(_lab.left, 0, 'Text()  ·  Flutter today'),
          _panel(_lab.right, _rightX, 'KumihanText()  ·  kumihan'),
        ],
      ),
    );
  }

  Widget _panel(_Side s, double x, String label) {
    return Positioned(
      left: x,
      top: _panelTop,
      width: _panelW,
      height: _panelH,
      child: BpPanel(
        label: label,
        padding: EdgeInsets.zero,
        color: s.kumihan ? BP.line : BP.lineDim,
        width: _panelW,
        height: _panelH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRect(
                child: RepaintBoundary(child: CustomPaint(painter: _SidePainter(_lab, s))),
              ),
            ),
            AnimatedBuilder(
              animation: _lab,
              builder: (context, _) => Positioned(
                left: _textX + _lab.w - 22,
                top: 30,
                width: 44,
                height: _panelH - 100,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
                    child: CustomPaint(painter: _HandlePainter(active: !_auto)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 16,
              child: AnimatedBuilder(animation: _lab, builder: (context, _) => _Counters(s)),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _ja(double size, Color color, {FontWeight weight = FontWeight.w400}) => TextStyle(
  fontFamily: 'Hiragino Sans',
  fontFamilyFallback: const ['Hiragino Kaku Gothic ProN', 'Noto Sans JP', 'Noto Sans CJK JP'],
  fontSize: size,
  fontWeight: weight,
  color: color,
  locale: const Locale('ja'),
);

class _Counters extends StatelessWidget {
  const _Counters(this.s);

  final _Side s;

  @override
  Widget build(BuildContext context) {
    Widget count(String label, String romaji, int n) => Padding(
      padding: const EdgeInsets.only(right: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: _ja(16, BP.inkDim)),
          const SizedBox(width: 6),
          Text(romaji, style: BT.mono(11, color: BP.inkFaint)),
          const SizedBox(width: 10),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: BT.display(28, color: n > 0 ? BP.red : BP.green, weight: 600),
            child: Text('$n'),
          ),
        ],
      ),
    );
    return Row(
      children: [
        count('泣き別れ', 'split', s.splits),
        count('禁則', 'kinsoku', s.kinsoku),
        count('孤立', 'orphan', s.orphans),
        if (s.forced > 0) ...[
          Text('phrase > width', style: BT.mono(12, color: BP.amber)),
          const SizedBox(width: 8),
          Text('${s.forced}', style: BT.display(22, color: BP.amber, weight: 600)),
        ],
        const Spacer(),
        if (s.kumihan && s.prepared != null)
          BpTag('U+2060 × ${s.prepared!.joinerCount}', color: BP.amber, size: 12),
      ],
    );
  }
}

class _SidePainter extends CustomPainter {
  _SidePainter(this.lab, this.s) : super(repaint: lab);

  final _Lab lab;
  final _Side s;

  static const o = Offset(_textX, _textY);

  Rect _shownRect(int k) {
    final t = s.target[k];
    final p = s.shown[k];
    return Rect.fromLTWH(p.dx, p.dy, t.width, t.height).shift(o);
  }

  /// Union of the shown boxes of graphemes [from, to], one rect per line.
  List<Rect> _fragments(int from, int to) {
    final out = <int, Rect>{};
    for (var k = from; k <= to && k < s.target.length; k++) {
      final r = _shownRect(k);
      final l = s.lineOf[k];
      out[l] = out[l]?.expandToInclude(r) ?? r;
    }
    return out.values.toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tp = s.tp;
    if (tp == null || s.target.isEmpty) return;
    final w = lab.w;
    final bottom = size.height - 70;

    // The measure: the column the text may use.
    canvas.drawRect(
      Rect.fromLTRB(o.dx, o.dy - 10, o.dx + w, bottom),
      Paint()..color = BP.line.withValues(alpha: 0.025),
    );

    // Line bands, numbered in the gutter (or tagged when the line breaks a rule).
    final gutterTags = <int, String>{};
    for (final m in s.marks) {
      if (m.kind == _MarkKind.kinsoku) gutterTags[s.lineOf[m.from]] = '禁則';
      if (m.kind == _MarkKind.orphan) gutterTags[s.lineOf[m.from]] ??= '孤立';
    }
    for (var i = 0; i < s.bands.length; i++) {
      final r = s.bands[i].shift(o);
      canvas.drawRect(
        Rect.fromLTWH(o.dx, r.top, w, r.height),
        Paint()..color = (i.isEven ? BP.line : BP.violet).withValues(alpha: 0.045),
      );
      final tag = gutterTags[i];
      if (tag != null) {
        _tag(canvas, tag, Offset(o.dx - 19, r.center.dy));
      } else {
        _label(canvas, (i + 1).toString().padLeft(2, '0'), BT.mono(12, color: BP.inkFaint), Offset(o.dx - 20, r.center.dy));
      }
    }

    // Problems, behind the glyphs.
    for (final m in s.marks) {
      for (final r in _fragments(m.from, m.to)) {
        switch (m.kind) {
          case _MarkKind.split:
          case _MarkKind.forced:
            final c = m.kind == _MarkKind.split ? BP.red : BP.amber;
            canvas.drawRect(r.inflate(1), Paint()..color = c.withValues(alpha: m.kind == _MarkKind.split ? 0.17 : 0.1));
            canvas.drawLine(
              Offset(r.left, r.bottom + 2),
              Offset(r.right, r.bottom + 2),
              Paint()
                ..color = c
                ..strokeWidth = m.kind == _MarkKind.split ? 3 : 2,
            );
          case _MarkKind.kinsoku:
          case _MarkKind.orphan:
            final box = r.inflate(3);
            canvas.drawRect(box, Paint()..color = BP.red.withValues(alpha: 0.12));
            canvas.drawPath(
              dashPath(Path()..addRect(box), dash: 4, gap: 3),
              Paint()
                ..color = BP.red
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
        }
      }
    }

    _paintText(canvas, tp, size);

    if (s.kumihan) {
      // Phrase boundaries inside a line: faint ruler ticks under the text.
      final tick = Paint()
        ..color = BP.line.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      for (final k in s.ticks) {
        final r = _shownRect(k);
        final y = r.bottom - r.height * 0.08;
        canvas.drawLine(Offset(r.left, y - r.height * 0.25), Offset(r.left, y + 4), tick);
        canvas.drawCircle(Offset(r.left, y + 4), 2.2, Paint()..color = BP.line);
      }
      // Breaks that land on a phrase boundary.
      final ok = Paint()
        ..color = BP.green
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final k in s.goodBreaks) {
        final r = _shownRect(k);
        final x = r.right + 7;
        canvas.drawLine(Offset(x, r.top + r.height * 0.25), Offset(x, r.bottom - r.height * 0.25), ok);
      }
    }

    // Balanced width.
    if (s.layoutW < w - 0.5) {
      final bx = o.dx + s.layoutW;
      canvas.drawPath(
        dashPath(Path()
          ..moveTo(bx, o.dy - 16)
          ..lineTo(bx, bottom), dash: 3, gap: 4),
        Paint()
          ..color = BP.violet
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _label(canvas, 'balance', BT.mono(12, color: BP.violet), Offset(bx - 30, bottom - 10));
    }

    // Width limit and its dimension line.
    final lx = o.dx + w;
    final dash = Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(dashPath(Path()
      ..moveTo(lx, o.dy - 50)
      ..lineTo(lx, bottom), dash: 7, gap: 5), dash);
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(o.dx, o.dy - 50)
        ..lineTo(o.dx, bottom), dash: 7, gap: 5),
      Paint()
        ..color = BP.lineDim
        ..style = PaintingStyle.stroke,
    );
    final dy = o.dy - 38;
    final dp = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(o.dx, dy), Offset(lx, dy), dp);
    drawArrowHead(canvas, Offset(o.dx, dy), Offset(o.dx + 10, dy), dp, 5);
    drawArrowHead(canvas, Offset(lx, dy), Offset(lx - 10, dy), dp, 5);
    final lt = TextPainter(
      text: TextSpan(text: '${w.round()} px', style: BT.mono(14, color: BP.amber)),
      textDirection: TextDirection.ltr,
    )..layout();
    final lr = Rect.fromCenter(center: Offset((o.dx + lx) / 2, dy), width: lt.width + 16, height: lt.height);
    canvas.drawRect(lr, Paint()..color = BP.panel);
    lt.paint(canvas, lr.topLeft + const Offset(8, 0));
    lt.dispose();
  }

  void _paintText(Canvas canvas, TextPainter tp, Size size) {
    final fade = lab.fade;
    final area = Offset.zero & size;
    if (fade < 1) canvas.saveLayer(area, Paint()..color = Color.fromRGBO(0, 0, 0, fade));
    final moving = <int>[];
    for (var k = 0; k < s.target.length; k++) {
      if ((s.shown[k] - s.target[k].topLeft).distance > 0.3) moving.add(k);
    }
    if (moving.isEmpty) {
      tp.paint(canvas, o);
    } else {
      final holes = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(area);
      for (final k in moving) {
        holes.addRect(_clipFor(k).shift(o));
      }
      canvas.save();
      canvas.clipPath(holes);
      tp.paint(canvas, o);
      canvas.restore();
      for (final k in moving) {
        final d = s.shown[k] - s.target[k].topLeft;
        canvas.save();
        canvas.translate(d.dx, d.dy);
        canvas.clipRect(_clipFor(k).shift(o));
        tp.paint(canvas, o);
        canvas.restore();
      }
    }
    if (fade < 1) canvas.restore();
  }

  /// Grapheme [k]'s box stretched over its whole line band.
  Rect _clipFor(int k) {
    final r = s.target[k];
    final li = s.lineOf[k];
    if (li >= s.bands.length) return r;
    final b = s.bands[li];
    return Rect.fromLTRB(
      r.left,
      li == 0 ? b.top - 30 : b.top,
      r.right,
      li == s.bands.length - 1 ? b.bottom + 30 : b.bottom,
    );
  }

  static void _tag(Canvas canvas, String text, Offset center) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _ja(11, BP.paper, weight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: center, width: tp.width + 8, height: tp.height + 4);
    canvas.drawRect(r, Paint()..color = BP.red);
    tp.paint(canvas, r.topLeft + const Offset(4, 2));
    tp.dispose();
  }

  static void _label(Canvas canvas, String text, TextStyle style, Offset center) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_SidePainter old) => old.lab != lab || old.s != s;
}

class _HandlePainter extends CustomPainter {
  _HandlePainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.45;
    final r = Rect.fromCenter(center: Offset(cx, cy), width: 16, height: 64);
    canvas.drawRect(r, Paint()..color = BP.paper);
    canvas.drawRect(
      r,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.5 : 1.5,
    );
    final g = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.5;
    for (final dy in [-8.0, 0.0, 8.0]) {
      canvas.drawLine(Offset(cx - 4, cy + dy), Offset(cx + 4, cy + dy), g);
    }
    final a = Paint()
      ..color = BP.amber.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    drawArrowHead(canvas, Offset(cx - 18, cy), Offset(cx - 10, cy), a, 5);
    drawArrowHead(canvas, Offset(cx + 18, cy), Offset(cx + 10, cy), a, 5);
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.active != active;
}
