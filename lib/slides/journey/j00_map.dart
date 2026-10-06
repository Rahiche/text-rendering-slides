import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'journey.dart';

const _bands = [
  'framework · Dart',
  'dart:ui',
  'engine · C++',
  'SkParagraph',
  'Impeller',
  'GPU',
];

const _bandH = 84.0;
const _bandTop = 20.0;

double _bandY(int b) => _bandTop + b * _bandH + _bandH / 2;

/// (stop index, band, x)
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

/// Overview: the word's route down through the layers — layout() goes down to
/// SkParagraph and returns a size; paint() goes down again to the GPU.
class JMapSlide extends StatefulWidget {
  const JMapSlide({super.key});

  @override
  State<JMapSlide> createState() => _JMapSlideState();
}

class _JMapSlideState extends State<JMapSlide> {
  late final _ctrl = TextEditingController(text: journeyWord.value);
  int? _hover;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return JourneyFrame(
      stop: 0,
      rekey: false,
      title: (_) => "One word's journey",
      builder: (context, d) {
        if (_ctrl.text != d.text) _ctrl.text = d.text;
        final samples = _samples(d);
        final points = [for (final s in _stations) Offset(s.$3, _bandY(s.$2))];
        // Return trip after layout(): back up to the framework.
        final route = <Offset>[
          ...points.sublist(0, 7),
          Offset(points[6].dx + 70, _bandY(0)),
          ...points.sublist(7),
        ];
        final path = Path()..moveTo(route.first.dx, route.first.dy);
        for (final p in route.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Bands
            for (var b = 0; b < _bands.length; b++)
              Positioned(
                left: 0,
                right: 0,
                top: _bandTop + b * _bandH,
                height: _bandH,
                child: Reveal(
                  visible: true,
                  delay: Duration(milliseconds: 80 * b),
                  offset: const Offset(-30, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: b.isEven ? BP.line.withValues(alpha: 0.035) : Colors.transparent,
                      border: const Border(top: BorderSide(color: BP.lineFaint)),
                    ),
                    padding: const EdgeInsets.only(left: 4),
                    alignment: Alignment.centerLeft,
                    child: Text(_bands[b], style: BT.mono(14, color: BP.inkDim)),
                  ),
                ),
              ),
            // Phase brackets
            Positioned(
              left: points[2].dx - 20,
              width: points[6].dx - points[2].dx + 40,
              top: _bandTop + 6 * _bandH + 8,
              child: const _Phase(label: 'layout()'),
            ),
            Positioned(
              left: points[7].dx - 20,
              width: points[9].dx - points[7].dx + 40,
              top: _bandTop + 6 * _bandH + 8,
              child: const _Phase(label: 'paint()'),
            ),
            // Route
            Positioned.fill(
              child: DrawOn(
                duration: const Duration(milliseconds: 1800),
                delay: const Duration(milliseconds: 400),
                color: BP.lineDim,
                strokeWidth: 2,
                path: (_) => path,
              ),
            ),
            Positioned(
              left: points[6].dx + 76,
              top: _bandY(1) - 10,
              child: Text('size ↑', style: BT.mono(13, color: BP.inkFaint)),
            ),
            // Travelling packet
            Positioned.fill(
              child: IgnorePointer(
                child: LoopBuilder(
                  period: const Duration(seconds: 14),
                  builder: (context, t, _) => CustomPaint(
                    painter: _PacketPainter(path: path, t: t, route: route, samples: samples),
                  ),
                ),
              ),
            ),
            // Stations
            for (var i = 0; i < _stations.length; i++)
              Positioned(
                left: points[i].dx - 60,
                top: points[i].dy - 36,
                width: 120,
                child: Reveal(
                  visible: true,
                  delay: Duration(milliseconds: 600 + 120 * i),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      onTap: () => DeckScope.read(context).goToId(journeyStops[_stations[i].$1].$1),
                      child: _Station(
                        name: journeyStops[_stations[i].$1].$2,
                        index: _stations[i].$1,
                        sample: samples[i],
                        hot: _hover == i,
                      ),
                    ),
                  ),
                ),
              ),
            // Word input
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
                    style: journeyStyle(34),
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

  /// What the data looks like at each station, for this word.
  List<String> _samples(JourneyData d) {
    final w = d.text;
    final units = w.codeUnits.take(3).map((u) => u.toRadixString(16).toUpperCase().padLeft(4, '0')).join(' ');
    final bytes = utf8.encode(w).take(4).map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
    final ids = d.glyphs.where((g) => !g.isJoinControl).take(3).map((g) => g.font == null ? '?' : '#${g.glyphId}').join(' ');
    final adv = d.glyphs.take(3).map((g) => g.advance).join(' ');
    final probe = TextProbe(TextSpan(text: w, style: journeyStyle(48)));
    final size = probe.size;
    probe.dispose();
    return [
      "Text('${_short(w)}')",
      '$units${w.length > 3 ? ' …' : ''}',
      'utf8 $bytes …',
      '${w.characters.length} graphemes · ${d.rtl ? 'RTL' : 'LTR'}',
      '$ids …',
      'adv $adv …',
      '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)}',
      'DrawTextFrame',
      'atlas ← ${d.atlasGlyphs}',
      '${d.quads * 2} triangles',
    ];
  }

  String _short(String w) => w.length > 8 ? '${w.substring(0, 7)}…' : w;
}

class _Station extends StatelessWidget {
  const _Station({required this.name, required this.index, required this.sample, required this.hot});

  final String name;
  final int index;
  final String sample;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final c = hot ? BP.amber : BP.line;
    return Column(
      children: [
        Text(
          '${index.toString().padLeft(2, '0')} $name',
          style: BT.mono(14, color: hot ? BP.amber : BP.ink),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: hot ? 20 : 14,
          height: hot ? 20 : 14,
          decoration: BoxDecoration(
            color: BP.paper,
            border: Border.all(color: c, width: 2),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: journeyStyle(hot ? 15 : 12, color: hot ? BP.amber : BP.inkDim).copyWith(fontFamily: BP.mono),
          child: Text(sample, textAlign: TextAlign.center, softWrap: false, overflow: TextOverflow.visible),
        ),
      ],
    );
  }
}

class _Phase extends StatelessWidget {
  const _Phase({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(height: 10, child: CustomPaint(painter: _BracketPainter(), size: Size.infinite)),
      const SizedBox(height: 4),
      Text(label, style: BT.mono(15, color: BP.amber)),
    ],
  );
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = BP.amber
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0),
      p,
    );
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}

class _PacketPainter extends CustomPainter {
  _PacketPainter({required this.path, required this.t, required this.route, required this.samples});

  final Path path;
  final double t;
  final List<Offset> route;
  final List<String> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    // Ease between stations: dwell a little at each.
    final d = m.length * Curves.easeInOut.transform(t);
    final tan = m.getTangentForOffset(d);
    if (tan == null) return;
    // Lit trail
    canvas.drawPath(
      m.extractPath(math.max(0, d - 140), d),
      Paint()
        ..color = BP.amber.withValues(alpha: 0.7)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    final p = tan.position;
    final diamond = Path()
      ..moveTo(p.dx, p.dy - 8)
      ..lineTo(p.dx + 8, p.dy)
      ..lineTo(p.dx, p.dy + 8)
      ..lineTo(p.dx - 8, p.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = BP.amber);
  }

  @override
  bool shouldRepaint(_PacketPainter old) => old.t != t || old.path != path;
}
