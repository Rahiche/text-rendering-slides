import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../../slides/journey/journey.dart';
import 'noir_kit.dart';

const _bands = ['framework · Dart', 'dart:ui', 'engine · C++', 'SkParagraph', 'Impeller', 'GPU'];
const _bandH = 84.0;
const _bandTop = 20.0;

double _bandY(int b) => _bandTop + b * _bandH + _bandH / 2;

/// (stop index, band, x) — the same route as the classic journey map.
const _stations = [
  (1, 0, 300.0),
  (2, 0, 430.0),
  (3, 2, 560.0),
  (4, 3, 690.0),
  (5, 3, 820.0),
  (6, 3, 950.0),
  (7, 3, 1080.0),
  (8, 2, 1230.0),
  (9, 4, 1330.0),
  (10, 5, 1430.0),
];

/// Whether this world switches the journey word to 直 on first show. Off:
/// the shared 'Find the glyphs' slide still describes any non-bundled
/// character as a colour emoji glyph, which would be wrong for a kanji.
const _defaultToCase = true;
bool _defaulted = false;

/// Journey overview as a reconstruction: the word's route pinned across the
/// layers with red string — layout() goes down to SkParagraph and comes back
/// up with a size; paint() goes down to the GPU. Click a pin to go there.
class DetectiveJourney extends StatefulWidget {
  const DetectiveJourney({super.key});

  @override
  State<DetectiveJourney> createState() => _DetectiveJourneyState();
}

class _DetectiveJourneyState extends State<DetectiveJourney> {
  late final _ctrl = TextEditingController(text: journeyWord.value);
  int? _hover;

  @override
  void initState() {
    super.initState();
    // This case follows 直 (once, and only if nobody picked a word yet).
    if (_defaultToCase && !_defaulted) {
      _defaulted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (journeyWord.value == 'Flutter') journeyWord.value = caseChar;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return JourneyFrame(
      stop: 0,
      rekey: false,
      title: (_) => "One word's journey",
      builder: (context, d) {
        if (_ctrl.text != d.text) _ctrl.text = d.text;
        final samples = _samples(d, locale);
        final points = [for (final s in _stations) Offset(s.$3, _bandY(s.$2))];
        // Return trip after layout(): back up to the framework with a size.
        final route = <Offset>[
          ...points.sublist(0, 7),
          Offset(points[6].dx + 70, _bandY(0)),
          ...points.sublist(7),
        ];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var b = 0; b < _bands.length; b++)
              Positioned(
                left: 0,
                right: 0,
                top: _bandTop + b * _bandH,
                height: _bandH,
                child: Reveal(
                  visible: true,
                  delay: Duration(milliseconds: 70 * b),
                  offset: const Offset(-30, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: b.isEven ? BP.line.withValues(alpha: 0.03) : Colors.transparent,
                      border: const Border(top: BorderSide(color: BP.lineFaint)),
                    ),
                    padding: const EdgeInsets.only(left: 4),
                    alignment: Alignment.centerLeft,
                    child: Text(_bands[b], style: BT.mono(14, color: BP.inkDim)),
                  ),
                ),
              ),
            // Red string + the lens travelling along it.
            Positioned.fill(
              child: IgnorePointer(
                child: LoopBuilder(
                  period: const Duration(seconds: 16),
                  builder: (context, t, _) => CustomPaint(painter: _RoutePainter(route: route, t: t)),
                ),
              ),
            ),
            _phase(points[2].dx - 20, points[6].dx + 20, 'layout()'),
            _phase(points[7].dx - 20, points[9].dx + 20, 'paint()'),
            Positioned(
              left: points[6].dx + 78,
              top: _bandY(1) - 10,
              child: Text('size ↑', style: BT.mono(13, color: BP.amber)),
            ),
            for (var i = 0; i < _stations.length; i++)
              Positioned(
                left: points[i].dx - 66,
                top: points[i].dy - 40,
                width: 132,
                child: Reveal(
                  visible: true,
                  delay: Duration(milliseconds: 500 + 110 * i),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      onTap: () => DeckScope.read(context).goToId(journeyStops[_stations[i].$1].$1),
                      child: _Pin(
                        name: journeyStops[_stations[i].$1].$2,
                        index: _stations[i].$1,
                        sample: samples[i],
                        hot: _hover == i,
                        clue: _stations[i].$1 == 5,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('word', style: BT.mono(16, color: BP.inkDim)),
                  const SizedBox(width: 16),
                  BpTextField(
                    controller: _ctrl,
                    width: 360,
                    style: journeyStyle(34).copyWith(locale: jaLocale),
                    onChanged: (v) {
                      if (v.isNotEmpty) journeyWord.value = v;
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _phase(double x0, double x1, String label) => Positioned(
    left: x0,
    width: x1 - x0,
    top: _bandTop + 6 * _bandH + 8,
    child: Column(
      children: [
        SizedBox(height: 10, child: CustomPaint(painter: _BracketPainter(), size: Size.infinite)),
        const SizedBox(height: 4),
        Text(label, style: BT.mono(15, color: BP.amber)),
      ],
    ),
  );

  /// What the evidence looks like at each stop, for this word (as on the
  /// classic map; glyphs no bundled font has are marked as fallback).
  List<String> _samples(JourneyData d, Locale? locale) {
    final w = d.text;
    String hex(int v, int n) => v.toRadixString(16).toUpperCase().padLeft(n, '0');
    final units = w.codeUnits.take(3).map((u) => hex(u, 4)).join(' ');
    final bytes = utf8.encode(w).take(4).map((b) => hex(b, 2)).join(' ');
    final real = d.glyphs.where((g) => !g.isJoinControl).take(3).toList();
    final fallback = real.any((g) => g.font == null);
    final ids = fallback ? 'fallback · ${locale?.toLanguageTag() ?? '—'}' : '${real.map((g) => '#${g.glyphId}').join(' ')} …';
    final adv = d.glyphs.take(3).map((g) => g.font == null ? '?' : '${g.advance}').join(' ');
    final probe = TextProbe(TextSpan(text: w, style: journeyStyle(48)));
    final size = probe.size;
    probe.dispose();
    final short = w.length > 8 ? '${w.substring(0, 7)}…' : w;
    return [
      "Text('$short')",
      '$units${w.length > 3 ? ' …' : ''}',
      'utf8 $bytes …',
      '${w.characters.length} graphemes · ${d.rtl ? 'RTL' : 'LTR'}',
      ids,
      'adv $adv …',
      '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}',
      'DrawTextFrame',
      'atlas ← ${d.atlasGlyphs}',
      '${d.quads * 2} triangles',
    ];
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.name, required this.index, required this.sample, required this.hot, required this.clue});

  final String name;
  final int index;
  final String sample;
  final bool hot;
  final bool clue;

  @override
  Widget build(BuildContext context) {
    final c = hot ? BP.amber : (clue ? BP.amber : BP.ink);
    return Column(
      children: [
        Text('${index.toString().padLeft(2, '0')} $name', style: BT.mono(14, color: c)),
        const SizedBox(height: 8),
        AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: hot ? 1.4 : 1,
          child: CustomPaint(size: const Size(16, 16), painter: _PinPainter(clue)),
        ),
        const SizedBox(height: 8),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: BT.mono(hot ? 15 : 12, color: hot ? BP.amber : BP.inkDim).copyWith(locale: jaLocale),
          child: Text(sample, textAlign: TextAlign.center, softWrap: false, overflow: TextOverflow.visible),
        ),
      ],
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter(this.clue);

  final bool clue;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (clue) {
      // The stop where the case turned: an evidence tag.
      paintTag(canvas, Rect.fromLTWH(c.dx + 4, c.dy + 2, 16, 11), color: BP.amber, filled: true);
    }
    drawPin(canvas, c, r: 6);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.clue != clue;
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0),
      Paint()
        ..color = BP.amber
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.route, required this.t});

  final List<Offset> route;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Strung pin to pin (sagging a little), drawn on at the start.
    final draw = seg(t * 16, 0.3, 2.3);
    final path = Path()..moveTo(route.first.dx, route.first.dy);
    for (var i = 1; i < route.length; i++) {
      final a = route[i - 1];
      final b = route[i];
      final mid = Offset.lerp(a, b, 0.5)! + Offset(0, 10 + (b - a).distance * 0.04);
      path.quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
    }
    final paint = Paint()
      ..color = BP.red.withValues(alpha: 0.85)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(draw >= 1 ? path : partialPath(path, draw), paint);
    if (draw < 1) return;
    // The lens retraces the route.
    final m = path.computeMetrics().first;
    final u = Curves.easeInOut.transform(((t * 16 - 2.5) / 13).clamp(0.0, 1.0));
    final d = m.length * u;
    final tan = m.getTangentForOffset(d);
    if (tan == null || u <= 0 || u >= 1) return;
    canvas.drawPath(
      m.extractPath(math.max(0, d - 160), d),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.8)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final p = tan.position;
    canvas.drawCircle(p, 16, Paint()..color = BP.amber.withValues(alpha: 0.15));
    paintMagnifier(canvas, p + const Offset(-4, -4), 11, angle: 0.8, rim: BP.ink, handle: 1);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.t != t || old.route != route;
}
