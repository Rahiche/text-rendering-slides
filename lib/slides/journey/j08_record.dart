import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

/// Stop 8: paint doesn't draw pixels, it records. canvas.drawParagraph ends
/// up as a DrawTextFrame op in a DisplayList; its TextFrame holds the real
/// glyph ids and x positions of the word. The DisplayList then goes to the
/// raster thread.
class JRecordSlide extends StatelessWidget {
  const JRecordSlide({super.key});

  @override
  Widget build(BuildContext context) => JourneyFrame(
    stop: 8,
    title: (_) => 'Record',
    builder: (context, d) => _Record(data: d),
  );
}

// Geometry (content-area coordinates, 1472 × 628).
const _contentW = 1472.0;
const _wordO = Offset(24, 104);
const _tapeX = 460.0;
const _tapeTop = 92.0;
const _tapeH = 64.0;
const _opY = _tapeTop + 14;
const _opH = 36.0;
const _structRect = Rect.fromLTWH(460, 204, 1012, 228);
const _laneY = 450.0;
const _dropX = 420.0;
const _rasterMid = 534.0;
const _treeRect = Rect.fromLTWH(330, 499, 250, 70);
const _rasterRect = Rect.fromLTWH(650, 499, 200, 70);
const _implRect = Rect.fromLTWH(920, 499, 200, 70);

/// (label, left, width) of the call-chain chips.
const _calls = [
  ('RenderParagraph.paint', 170.0, 230.0),
  ('TextPainter.paint', 440.0, 200.0),
  ('canvas.drawParagraph', 680.0, 230.0),
];
const _chipH = 40.0;

String _f1(double v) => v.toStringAsFixed(1);
double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

enum _Kind { font, arabic, fallback }

/// One glyph as recorded in the TextFrame.
class _G {
  _G({
    required this.shown,
    required this.id,
    required this.x,
    required this.box,
    required this.font,
    required this.kind,
  });

  /// What to draw for it (Arabic: with ZWJ so it keeps its joined form).
  final String shown;

  /// Glyph id; null when the platform fallback font chose it (unknown to us).
  final int? id;

  /// Pen x from the real layout.
  final double x;

  /// Cluster box in paragraph coordinates.
  final Rect box;
  final String font;
  final _Kind kind;
}

class _Run {
  _Run(this.font, this.kind, this.glyphs);

  final String font;
  final _Kind kind;
  final List<_G> glyphs;
}

// ─────────────────────────────────────────────────────────────────────────────
// Arabic joining, so a single letter can be drawn in its contextual form.
// ─────────────────────────────────────────────────────────────────────────────

const _rightJoining = {
  0x0622, 0x0623, 0x0624, 0x0625, 0x0627, 0x0629, 0x062F, 0x0630, 0x0631, 0x0632, //
  0x0648, 0x0671, 0x0672, 0x0673, 0x0675, 0x0676, 0x0677, 0x06C0, 0x06CD, 0x06CF,
  0x06D2, 0x06D3, 0x06D5, 0x06EE, 0x06EF,
};

/// Unicode joining type, simplified: R, D, C (tatweel), T (marks), U.
String _joining(int c) {
  if ((c >= 0x064B && c <= 0x065F) || c == 0x0670 || (c >= 0x06D6 && c <= 0x06DC) || (c >= 0x06DF && c <= 0x06E4)) {
    return 'T';
  }
  if (_rightJoining.contains(c) || (c >= 0x0688 && c <= 0x0699) || (c >= 0x06C3 && c <= 0x06CB)) return 'R';
  if (c == 0x0640) return 'C';
  if (c == 0x0621 || c == 0x0674 || c == 0x06D4 || c == 0x06DD) return 'U';
  if ((c >= 0x0620 && c <= 0x064A) || (c >= 0x066E && c <= 0x06FF)) return 'D';
  return 'U';
}

String _contextual(List<JGlyph> gs, int i) {
  final t = _joining(gs[i].codePoint);
  if (t == 'U' || t == 'T') return gs[i].char;
  String near(int from, int step) {
    for (var k = from; k >= 0 && k < gs.length; k += step) {
      final j = _joining(gs[k].codePoint);
      if (j != 'T') return j;
    }
    return 'U';
  }

  final prev = near(i - 1, -1);
  final next = near(i + 1, 1);
  final joinPrev = prev == 'D' || prev == 'C';
  final joinNext = (t == 'D' || t == 'C') && (next == 'D' || next == 'R' || next == 'C');
  const zwj = '\u200D';
  return '${joinPrev ? zwj : ''}${gs[i].char}${joinNext ? zwj : ''}';
}

List<_Run> _buildRuns(JourneyData d, TextProbe probe) {
  final logical = <_G>[];
  final clusters = probe.graphemes().toList();
  // The glyphs as shaped: the font's ligatures one glyph (t t: #906), a
  // platform cluster (an emoji) one color glyph.
  for (final r in d.run) {
    var box = probe.rectFor(r.start, r.end);
    if (box == null || box.width < 0.5) {
      for (final (s, e) in clusters) {
        if (r.start >= s && r.start < e) box = probe.rectFor(s, e);
      }
    }
    if (box == null) continue;
    if (r.font == null) {
      // Platform fallback (e.g. an emoji font): one color glyph per cluster.
      logical.add(_G(
        shown: d.text.substring(r.start, r.end),
        id: null,
        x: box.left,
        box: box,
        font: 'system fallback',
        kind: _Kind.fallback,
      ));
      continue;
    }
    final i = r.parts.first;
    final g = d.glyphs[i];
    final arabic = g.script == Script.arabic;
    logical.add(_G(
      shown: r.ligature ? d.text.substring(r.start, r.end) : (g.codePoint == 0x20 ? '␠' : (arabic ? _contextual(d.glyphs, i) : g.char)),
      id: r.glyphId,
      x: box.left,
      box: box,
      font: g.fontName,
      kind: arabic ? _Kind.arabic : _Kind.font,
    ));
  }
  final runs = <_Run>[];
  for (final g in logical) {
    if (runs.isNotEmpty && runs.last.font == g.font) {
      runs.last.glyphs.add(g);
    } else {
      runs.add(_Run(g.font, g.kind, [g]));
    }
  }
  // A TextFrame stores glyphs in visual order (RTL runs come out reversed).
  for (final r in runs) {
    r.glyphs.sort((a, b) => a.x.compareTo(b.x));
  }
  runs.sort((a, b) => a.glyphs.first.x.compareTo(b.glyphs.first.x));
  return runs;
}

// ─────────────────────────────────────────────────────────────────────────────

class _Record extends StatefulWidget {
  const _Record({required this.data});

  final JourneyData data;

  @override
  State<_Record> createState() => _RecordState();
}

class _RecordState extends State<_Record> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  )..addListener(_onIntro);
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  late final double _fs;
  late final TextProbe _probe;
  late final List<_Run> _runs;
  late final List<_G> _all;
  late final ui.LineMetrics? _line;
  late final List<String> _ops;
  late final List<Rect> _opRects;

  bool _open = false;
  bool _hoverOp = false;
  bool _autoOpened = false;
  int? _hoverGlyph;

  bool get _expanded => _open || _hoverOp;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    TextProbe probe(double fs) => TextProbe(
      TextSpan(text: d.text, style: journeyStyle(fs)),
      textDirection: d.rtl ? TextDirection.rtl : TextDirection.ltr,
    );
    final m = probe(96);
    final fit = math.min(1.0, math.min(330 / math.max(m.size.width, 1), 172 / math.max(m.size.height, 1)));
    m.dispose();
    _fs = (96 * fit).floorToDouble();
    _probe = probe(_fs);
    final lines = _probe.lines;
    _line = lines.isEmpty ? null : lines.first;
    _runs = _buildRuns(d, _probe);
    _all = [for (final r in _runs) ...r.glyphs];

    final x = _line?.left ?? 0;
    final y = _line?.baseline ?? 0;
    _ops = [
      'Save',
      // Offset of the paragraph on the 1600 × 900 canvas.
      'Translate(${_f1(BP.margin + _wordO.dx)}, ${_f1(176 + _wordO.dy)})',
      'DrawRect(bg)',
      'DrawTextFrame(frame, ${_f1(x)}, ${_f1(y)})',
      'Restore',
    ];
    var ox = _tapeX + 20;
    _opRects = [];
    for (final op in _ops) {
      final w = op.length * 9.0 + 26;
      _opRects.add(Rect.fromLTWH(ox, _opY, w, _opH));
      ox += w + 10;
    }

    _intro.forward();
    _loop.repeat();
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    _fly.dispose();
    _probe.dispose();
    super.dispose();
  }

  void _onIntro() {
    if (!_autoOpened && _intro.value >= 0.72) {
      _autoOpened = true;
      _setExpanded(() => _open = true);
    }
  }

  void _setExpanded(VoidCallback change) {
    final was = _expanded;
    setState(change);
    if (!was && _expanded) _fly.forward(from: 0);
  }

  void _replay() {
    setState(() {
      _open = false;
      _hoverOp = false;
      _autoOpened = false;
    });
    _fly.value = 0;
    _intro.forward(from: 0);
    _loop
      ..value = 0
      ..repeat();
  }

  /// Flight progress of glyph k (0 = in the word, 1 = in the struct).
  double _flyT(int k) {
    final n = _all.length;
    final start = n <= 1 ? 0.0 : k / (n - 1) * 0.4;
    return _seg(_fly.value, start, start + 0.6);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _loop, _fly]),
      builder: (context, _) {
        final t = _loop.value;
        final printed = _intro.value >= 0.6;
        final active = [
          for (var k = 0; k < 3; k++) t >= 0.02 + k * 0.09 && t < 0.13 + k * 0.09,
        ];
        final pulse = printed && t >= 0.28 && t < 0.4;
        final packetP = printed && t >= 0.4 && t < 0.84 ? Curves.easeInOutCubic.transform(_seg(t, 0.4, 0.84)) : null;
        final rasterHot = printed && t >= 0.84;
        final flying = <int>{
          for (var k = 0; k < _all.length; k++)
            if (_expanded && _flyT(k) > 0 && _flyT(k) < 1) k,
        };
        final hotGlyphs = {...flying, ?_hoverGlyph};

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Wires, lanes, tape paper.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WiresPainter(
                    active: active,
                    opRects: _opRects,
                    expanded: _expanded,
                    packetP: packetP,
                    printed: _intro.value,
                    rasterHot: rasterHot,
                  ),
                ),
              ),
            ),
            // Lane tags
            const Positioned(left: 0, top: 6, child: BpTag('UI thread', color: BP.line)),
            const Positioned(left: 0, top: _laneY + 14, child: BpTag('raster thread', color: BP.violet)),
            // Call chain
            for (var k = 0; k < 3; k++)
              Positioned(
                left: _calls[k].$2,
                top: 0,
                width: _calls[k].$3,
                height: _chipH,
                child: _Chip(text: _calls[k].$1, hot: active[k]),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: BpButton(label: 'replay', icon: Icons.replay, size: 13, onTap: _replay),
            ),
            // The word (a RenderParagraph on a background box).
            Positioned(
              left: 0,
              top: _wordO.dy - 36,
              child: Text('RenderParagraph', style: BT.mono(12, color: BP.inkFaint)),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WordPainter(
                    probe: _probe,
                    glyphs: _all,
                    line: _line,
                    hot: hotGlyphs,
                    measure: _hoverGlyph,
                  ),
                ),
              ),
            ),
            Positioned(
              left: _wordO.dx,
              top: _wordO.dy,
              width: _probe.size.width,
              height: _probe.size.height,
              child: MouseRegion(
                onHover: (e) {
                  int? hit;
                  for (var k = 0; k < _all.length; k++) {
                    if (_all[k].box.contains(e.localPosition)) hit = k;
                  }
                  if (hit != _hoverGlyph) setState(() => _hoverGlyph = hit);
                },
                onExit: (_) => setState(() => _hoverGlyph = null),
                child: const SizedBox.expand(),
              ),
            ),
            // DisplayList tape
            Positioned(
              left: _tapeX,
              top: _tapeTop - 24,
              child: Text('DisplayList', style: BT.mono(13, color: BP.line)),
            ),
            for (var k = 0; k < _ops.length; k++) _op(k, pulse),
            Positioned(
              right: 0,
              top: _tapeTop + _tapeH + 12,
              child: const BpTag('Skia backend: DrawTextBlob', color: BP.inkDim, size: 12),
            ),
            // The TextFrame struct
            Positioned.fromRect(
              rect: _structRect,
              child: Reveal(
                visible: _expanded,
                offset: const Offset(0, -14),
                duration: const Duration(milliseconds: 380),
                child: _struct(hotGlyphs),
              ),
            ),
            // Raster lane
            Positioned.fromRect(
              rect: _treeRect,
              child: _Box(
                title: 'layer tree',
                sub: 'PictureLayer · DisplayList',
                hot: packetP != null && packetP > 0.62,
              ),
            ),
            Positioned.fromRect(
              rect: _rasterRect,
              child: _Box(title: 'Rasterizer', sub: 'raster thread', hot: rasterHot),
            ),
            Positioned.fromRect(
              rect: _implRect,
              child: const _Box(title: 'Impeller', sub: 'atlas · quads', hot: false, dim: true),
            ),
            // Variable children last, so the ones above keep their state.
            if (packetP != null) _packet(packetP),
            // Glyphs in flight: word → struct fields.
            for (final k in flying) _flight(k),
          ],
        );
      },
    );
  }

  Widget _op(int k, bool pulse) {
    final r = _opRects[k];
    final p = _seg(_intro.value, 0.08 + k * 0.11, 0.16 + k * 0.11);
    if (p <= 0) return const SizedBox.shrink();
    final isFrame = k == 3;
    final open = isFrame && _expanded;
    final hot = isFrame && (pulse || _hoverOp);
    final cell = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: open || hot ? BP.amber.withValues(alpha: hot ? 0.2 : 0.1) : BP.paper,
        border: Border.all(
          color: isFrame ? BP.amber : BP.lineDim,
          width: open || hot ? 2 : 1,
        ),
      ),
      child: Text(_ops[k], style: BT.mono(15, color: isFrame ? BP.amber : BP.ink)),
    );
    return Positioned(
      left: r.left - (1 - p) * 18,
      top: r.top,
      width: r.width,
      height: r.height,
      child: Opacity(
        opacity: p,
        child: isFrame
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => _setExpanded(() => _hoverOp = true),
                onExit: (_) => setState(() => _hoverOp = false),
                child: GestureDetector(
                  onTap: () => _setExpanded(() => _open = !_open),
                  child: cell,
                ),
              )
            : cell,
      ),
    );
  }

  // Struct layout inside the panel.
  double get _cardH => _runs.length <= 1 ? 108 : 62;
  double get _runH => 34 + _cardH + 12;
  double get _cardW {
    final maxN = _runs.fold<int>(1, (a, r) => math.max(a, r.glyphs.length));
    return ((_structRect.width - 150 - 70) / maxN - 8).clamp(40.0, 96.0);
  }

  Offset _cardPos(int run, int i) => Offset(150 + i * (_cardW + 8), 44 + run * _runH + 32);

  double get _slotFs => math.min(46.0, (_cardH - 38) * 0.62);

  /// Glyph slot center of card k, in content coordinates.
  Offset _target(int k) {
    var run = 0;
    var i = k;
    while (run < _runs.length - 1 && i >= _runs[run].glyphs.length) {
      i -= _runs[run].glyphs.length;
      run++;
    }
    return _structRect.topLeft + _cardPos(run, i) + Offset(_cardW / 2, (_cardH - 38) / 2);
  }

  Widget _struct(Set<int> hot) {
    final dim = BT.mono(15, color: BP.inkDim);
    final children = <Widget>[
      Positioned(left: 20, top: 16, child: Text('runs: [', style: dim)),
    ];
    var k = 0;
    for (var r = 0; r < _runs.length; r++) {
      final run = _runs[r];
      final y = 44 + r * _runH;
      final size = _fs.round();
      final font = run.kind == _Kind.fallback ? '${run.font} $size' : '${run.font} $size · wght 300';
      children.add(Positioned(
        left: 44,
        top: y,
        child: Row(
          children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '{ font: ', style: dim),
              TextSpan(text: "'$font'", style: BT.mono(15, color: run.kind == _Kind.fallback ? BP.violet : BP.amber)),
              TextSpan(text: ',', style: dim),
            ])),
            if (run.kind == _Kind.arabic) ...[
              const SizedBox(width: 14),
              const BpTag('ids before GSUB', color: BP.coral, size: 11),
            ],
          ],
        ),
      ));
      final rowTop = y + 32;
      children.add(Positioned(
        left: 64,
        top: rowTop + _cardH / 2 - 10,
        child: Text('glyphs: [', style: dim),
      ));
      for (var i = 0; i < run.glyphs.length; i++, k++) {
        final g = run.glyphs[i];
        final p = _cardPos(r, i);
        children.add(Positioned(
          left: p.dx,
          top: p.dy,
          width: _cardW,
          height: _cardH,
          child: _card(g, k, hot.contains(k)),
        ));
      }
      final end = _cardPos(r, run.glyphs.length);
      children.add(Positioned(
        left: end.dx + 2,
        top: rowTop + _cardH / 2 - 10,
        child: Text('] }', style: dim),
      ));
    }
    children.add(Positioned(left: 20, top: 44 + _runs.length * _runH - 4, child: Text(']', style: dim)));
    return BpPanel(
      label: 'impeller::TextFrame',
      color: BP.amber,
      padding: EdgeInsets.zero,
      child: SizedBox.expand(child: Stack(clipBehavior: Clip.none, children: children)),
    );
  }

  Widget _card(_G g, int k, bool hot) {
    final t = _flyT(k);
    final landed = t >= 1;
    final fields = _seg(t, 0.7, 1);
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverGlyph = k),
      onExit: (_) => setState(() => _hoverGlyph = null),
      child: Container(
        decoration: BoxDecoration(
          color: hot ? BP.amber.withValues(alpha: 0.1) : BP.paper,
          border: Border.all(color: hot ? BP.amber : (landed ? BP.lineDim : BP.lineFaint), width: hot ? 1.6 : 1),
        ),
        child: Column(
          children: [
            SizedBox(
              height: _cardH - 38,
              child: Center(
                child: landed
                    ? Text(g.shown, style: journeyStyle(_slotFs, color: hot ? BP.amber : BP.ink))
                    : null,
              ),
            ),
            Opacity(
              opacity: fields,
              child: SizedBox(
                height: 16,
                child: Text(
                  g.id == null ? 'id ?' : 'id ${g.id}',
                  style: BT.mono(12, color: g.id == null ? BP.inkFaint : BP.line),
                ),
              ),
            ),
            Opacity(
              opacity: fields,
              child: SizedBox(
                height: 16,
                child: Text('x ${_f1(g.x)}', style: BT.mono(12, color: BP.inkDim)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flight(int k) {
    final g = _all[k];
    final e = Curves.easeInOutCubic.transform(_flyT(k));
    final from = _wordO + g.box.center;
    final to = _target(k);
    final p = Offset.lerp(from, to, e)! - Offset(0, math.sin(math.pi * e) * 46);
    final size = ui.lerpDouble(_fs, _slotFs, e)!;
    return Positioned(
      left: p.dx,
      top: p.dy,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Text(g.shown, style: journeyStyle(size, color: BP.amber)),
        ),
      ),
    );
  }

  Widget _packet(double p) {
    // Path: tape → left → down to the raster lane → into the Rasterizer.
    const a = Offset(_tapeX, _tapeTop + _tapeH / 2);
    const b = Offset(_dropX, _tapeTop + _tapeH / 2);
    const c = Offset(_dropX, _rasterMid);
    final d = Offset(_rasterRect.left, _rasterMid);
    final l1 = (b - a).distance;
    final l2 = (c - b).distance;
    final l3 = (d - c).distance;
    var s = p * (l1 + l2 + l3);
    Offset at;
    if (s < l1) {
      at = Offset.lerp(a, b, s / l1)!;
    } else if ((s -= l1) < l2) {
      at = Offset.lerp(b, c, s / l2)!;
    } else {
      at = Offset.lerp(c, d, (s - l2) / l3)!;
    }
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: const IgnorePointer(
        child: FractionalTranslation(translation: Offset(-0.5, -0.5), child: _DlPacket()),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.hot});

  final String text;
  final bool hot;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: hot ? BP.amber.withValues(alpha: 0.16) : BP.panel,
      border: Border.all(color: hot ? BP.amber : BP.lineDim, width: hot ? 2 : 1),
    ),
    child: Text(text, style: BT.mono(15, color: hot ? BP.amber : BP.ink)),
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.title, required this.sub, required this.hot, this.dim = false});

  final String title;
  final String sub;
  final bool hot;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = hot ? BP.amber : (dim ? BP.lineFaint : BP.violet);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: hot ? BP.amber.withValues(alpha: 0.12) : BP.panel,
        border: Border.all(color: c, width: hot ? 2 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: BT.mono(16, color: dim ? BP.inkFaint : (hot ? BP.amber : BP.ink))),
          const SizedBox(height: 4),
          Text(sub, style: BT.mono(12, color: dim ? BP.inkFaint : BP.inkDim)),
        ],
      ),
    );
  }
}

/// A tiny DisplayList: a strip of recorded ops.
class _DlPacket extends StatelessWidget {
  const _DlPacket();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: BP.paper,
      border: Border.all(color: BP.line, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (w, c) in [(18.0, BP.lineDim), (24.0, BP.lineDim), (14.0, BP.amber), (10.0, BP.lineDim)])
              Container(width: w, height: 2.5, margin: const EdgeInsets.symmetric(vertical: 1.2), color: c),
          ],
        ),
        const SizedBox(width: 8),
        Text('DisplayList', style: BT.mono(12, color: BP.line)),
      ],
    ),
  );
}

class _WordPainter extends CustomPainter {
  _WordPainter({
    required this.probe,
    required this.glyphs,
    required this.line,
    required this.hot,
    required this.measure,
  });

  final TextProbe probe;
  final List<_G> glyphs;
  final ui.LineMetrics? line;
  final Set<int> hot;
  final int? measure;

  @override
  void paint(Canvas canvas, Size size) {
    const o = _wordO;
    final ps = probe.size;
    // The background the DrawRect op records.
    final bg = Rect.fromLTWH(o.dx - 16, o.dy - 12, ps.width + 32, ps.height + 24);
    canvas.drawRect(bg, Paint()..color = BP.panel);
    canvas.drawRect(
      bg,
      Paint()
        ..color = BP.lineDim
        ..style = PaintingStyle.stroke,
    );
    for (var k = 0; k < glyphs.length; k++) {
      final r = glyphs[k].box.shift(o);
      final h = hot.contains(k);
      canvas.drawPath(
        dashPath(Path()..addRect(r), dash: 4, gap: 4),
        Paint()
          ..color = h ? BP.amber : BP.lineFaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = h ? 1.6 : 1,
      );
      if (h) canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.08));
    }
    final l = line;
    if (l != null) {
      final by = o.dy + l.baseline;
      canvas.drawLine(
        Offset(bg.left, by),
        Offset(bg.right, by),
        Paint()
          ..color = BP.amber.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
    }
    probe.paint(canvas, o);
    if (l != null) {
      // The (x, y) that DrawTextFrame gets: line start on the baseline.
      final p = Offset(o.dx + l.left, o.dy + l.baseline);
      final a = Paint()
        ..color = BP.amber
        ..strokeWidth = 1.4;
      canvas.drawLine(p - const Offset(8, 0), p + const Offset(8, 0), a);
      canvas.drawLine(p - const Offset(0, 8), p + const Offset(0, 8), a);
      canvas.drawCircle(p, 3, Paint()..color = BP.amber);
      _text(canvas, '(x, y)', p + const Offset(8, 6), BP.amber);

      // Hovered glyph: its x from the frame origin.
      final m = measure;
      if (m != null && m < glyphs.length) {
        final g = glyphs[m];
        final y = bg.bottom + 16;
        final x0 = o.dx + l.left;
        final x1 = o.dx + g.x;
        final pen = Paint()
          ..color = BP.amber
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(x0, y), Offset(x1, y), pen);
        canvas.drawLine(Offset(x0, y - 6), Offset(x0, y + 6), pen);
        canvas.drawLine(Offset(x1, y - 6), Offset(x1, y + 6), pen);
        canvas.drawPath(
          dashPath(Path()
            ..moveTo(x1, o.dy + g.box.top)
            ..lineTo(x1, y)),
          pen,
        );
        _text(canvas, 'x ${_f1(g.x)}', Offset(math.max(x0, x1) + 8, y - 8), BP.amber);
      }
    }
  }

  void _text(Canvas c, String s, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: BT.mono(12, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_WordPainter old) =>
      old.measure != measure || old.hot.length != hot.length || !old.hot.containsAll(hot);
}

class _WiresPainter extends CustomPainter {
  _WiresPainter({
    required this.active,
    required this.opRects,
    required this.expanded,
    required this.packetP,
    required this.printed,
    required this.rasterHot,
  });

  final List<bool> active;
  final List<Rect> opRects;
  final bool expanded;
  final double? packetP;
  final double printed;
  final bool rasterHot;

  @override
  void paint(Canvas canvas, Size size) {
    Paint pen(Color c, [double w = 1.2]) => Paint()
      ..color = c
      ..strokeWidth = w
      ..style = PaintingStyle.stroke;

    // Call chain arrows.
    const y = _chipH / 2;
    for (var k = 0; k < 2; k++) {
      final a = Offset(_calls[k].$2 + _calls[k].$3 + 4, y);
      final b = Offset(_calls[k + 1].$2 - 4, y);
      drawArrow(canvas, a, b, pen(active[k + 1] ? BP.amber : BP.lineDim), head: 7);
    }
    // drawParagraph records into the DisplayList.
    final cx = _calls[2].$2 + _calls[2].$3 / 2;
    drawArrow(canvas, Offset(cx, _chipH + 3), Offset(cx, _tapeTop - 3), pen(active[2] ? BP.amber : BP.lineDim), head: 7);

    // Tape paper with sprocket holes.
    final tape = Rect.fromLTRB(_tapeX, _tapeTop, _contentW, _tapeTop + _tapeH);
    canvas.drawRect(tape, Paint()..color = BP.panel);
    canvas.drawLine(tape.topLeft, tape.topRight, pen(BP.lineDim, 1));
    canvas.drawLine(tape.bottomLeft, tape.bottomRight, pen(BP.lineDim, 1));
    canvas.drawLine(tape.topLeft, tape.bottomLeft, pen(BP.lineDim, 1));
    final hole = Paint()..color = BP.lineFaint;
    for (var x = tape.left + 10; x < tape.right - 6; x += 18) {
      canvas.drawRect(Rect.fromLTWH(x, tape.top + 4, 6, 5), hole);
      canvas.drawRect(Rect.fromLTWH(x, tape.bottom - 9, 6, 5), hole);
    }
    // Print head: after the last printed op.
    final printedOps = [
      for (var k = 0; k < opRects.length; k++)
        if (printed >= 0.08 + k * 0.11) k,
    ];
    final headX = printedOps.isEmpty ? _tapeX + 16 : opRects[printedOps.last].right + 6;
    if (printed < 1) {
      canvas.drawLine(Offset(headX, _opY - 4), Offset(headX, _opY + _opH + 4), pen(BP.amber, 2.5));
    }

    // DrawTextFrame → its TextFrame.
    if (expanded && opRects.length > 3) {
      final r = opRects[3];
      final a = Offset(r.center.dx, r.bottom + 2);
      final b = Offset(r.center.dx, _structRect.top - 2);
      canvas.drawPath(dashPath(Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy), dash: 4, gap: 3), pen(BP.amber, 1.4));
      drawArrowHead(canvas, b, a, pen(BP.amber, 1.4), 7);
    }

    // Lane divider.
    canvas.drawPath(
      dashPath(Path()
        ..moveTo(0, _laneY)
        ..lineTo(_contentW, _laneY), dash: 10, gap: 6),
      pen(BP.lineFaint, 1.5),
    );

    // The DisplayList's route to the raster thread.
    final route = Path()
      ..moveTo(_tapeX, _tapeTop + _tapeH / 2)
      ..lineTo(_dropX, _tapeTop + _tapeH / 2)
      ..lineTo(_dropX, _rasterMid)
      ..lineTo(_rasterRect.left, _rasterMid);
    final live = packetP != null;
    canvas.drawPath(dashPath(route, dash: 5, gap: 5), pen(live ? BP.line : BP.lineFaint, live ? 1.4 : 1));
    if (live) {
      canvas.drawPath(partialPath(route, packetP!), pen(BP.line.withValues(alpha: 0.5), 3));
    }
    drawArrowHead(canvas, Offset(_rasterRect.left - 2, _rasterMid), Offset(_rasterRect.left - 20, _rasterMid), pen(BP.line), 7);

    // Rasterizer → Impeller
    drawArrow(
      canvas,
      Offset(_rasterRect.right + 4, _rasterMid),
      Offset(_implRect.left - 4, _rasterMid),
      pen(rasterHot ? BP.amber : BP.lineDim),
      dashed: true,
      head: 7,
    );
  }

  @override
  bool shouldRepaint(_WiresPainter old) => true;
}
