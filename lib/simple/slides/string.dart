import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';

/// "A string ≠ text": graphemes → code points → UTF-16 units → UTF-8 bytes,
/// laid out as a tree so each level lines up with the one above.
class StringSlide extends StatefulWidget {
  const StringSlide({super.key});

  @override
  State<StringSlide> createState() => _StringSlideState();
}

class _StringSlideState extends State<StringSlide> {
  static const _presets = [
    'Hello',
    'か\u3099', // が, decomposed: か + combining dakuten
    '🇯🇵',
    '👨‍👩‍👧‍👦',
    'नमस्ते',
  ];

  late final _ctrl = TextEditingController(text: '👨‍👩‍👧‍👦');
  int? _hover;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(String s) {
    _ctrl.text = s;
    setState(() => _hover = null);
  }

  @override
  Widget build(BuildContext context) {
    final text = _ctrl.text;
    final clusters = text.characters.toList();
    final runes = text.runes.length;
    final units = text.length;
    final bytes = utf8.encode(text).length;

    return SlideFrame(
      title: 'A string ≠ text',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BpTextField(
                controller: _ctrl,
                width: 380,
                style: BT.sample(40),
                onChanged: (_) => setState(() => _hover = null),
              ),
              const Spacer(),
              for (final p in _presets) ...[
                const SizedBox(width: 12),
                _PresetChip(text: p, selected: p == text, onTap: () => _set(p)),
              ],
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                const labelW = 220.0;
                const countW = 340.0;
                final avail = box.maxWidth - labelW - countW - 48 - 18.0 * (clusters.length - 1);
                final cell = bytes == 0
                    ? 72.0
                    : math.min(72.0, math.max(10.0, avail / bytes - _gap));
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: labelW, child: _Labels()),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: box.maxWidth - labelW - countW - 48,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < clusters.length; i++)
                                MouseRegion(
                                  key: ValueKey('$i:${clusters[i]}'),
                                  onEnter: (_) => setState(() => _hover = i),
                                  onExit: (_) => setState(() => _hover = null),
                                  child: Reveal(
                                    visible: true,
                                    delay: Duration(milliseconds: 60 * math.min(i, 12)),
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: i < clusters.length - 1 ? 18 : 0,
                                      ),
                                      child: _ClusterColumn(
                                        cluster: clusters[i],
                                        cell: cell,
                                        hot: _hover == i,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                    SizedBox(
                      width: countW,
                      child: _Counts(
                        graphemes: clusters.length,
                        runes: runes,
                        units: units,
                        bytes: bytes,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const _gap = 4.0;
const _rowH = [170.0, 96.0, 66.0, 66.0];
const _rowGap = 30.0;
const _rowColor = [BP.ink, BP.inkDim, BP.amber, BP.inkDim];

/// One plain name per row.
class _Labels extends StatelessWidget {
  const _Labels();

  @override
  Widget build(BuildContext context) {
    const names = ['graphemes', 'code points', 'UTF-16 units', 'UTF-8 bytes'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < names.length; r++) ...[
          SizedBox(
            height: _rowH[r],
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(names[r], style: BT.display(28, color: _rowColor[r])),
            ),
          ),
          if (r < names.length - 1) const SizedBox(height: _rowGap),
        ],
      ],
    );
  }
}

/// The counts. The two that matter to a Dart developer carry their API:
/// what you see (`s.characters.length`) vs what `s.length` says.
class _Counts extends StatelessWidget {
  const _Counts({
    required this.graphemes,
    required this.runes,
    required this.units,
    required this.bytes,
  });

  final int graphemes;
  final int runes;
  final int units;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final values = [graphemes, runes, units, bytes];
    const api = ['s.characters.length', null, 's.length', null];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var r = 0; r < 4; r++) ...[
          SizedBox(
            height: _rowH[r],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (api[r] case final a?) ...[
                  Text(a, style: BT.mono(22, color: _rowColor[r])),
                  const SizedBox(width: 18),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: AnimatedCount(
                      value: values[r],
                      duration: const Duration(milliseconds: 500),
                      style: BT.display(r == 2 ? 64 : 52, color: _rowColor[r], weight: 500),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (r < 3) const SizedBox(height: _rowGap),
        ],
      ],
    );
  }
}

/// One grapheme and everything underneath it.
class _ClusterColumn extends StatelessWidget {
  const _ClusterColumn({required this.cluster, required this.cell, required this.hot});

  final String cluster;
  final double cell;
  final bool hot;

  static double _span(int n, double cell) => n * cell + (n - 1) * _gap;

  @override
  Widget build(BuildContext context) {
    final cps = cluster.runes.toList();
    final bytesPer = [for (final c in cps) utf8.encode(String.fromCharCode(c)).length];
    final unitsPer = [for (final c in cps) c > 0xFFFF ? 2 : 1];
    final totalBytes = bytesPer.fold(0, (a, b) => a + b);
    final width = _span(totalBytes, cell);
    final c = hot ? BP.amber : BP.lineDim;
    final t = hot ? BP.amber : BP.line;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grapheme
          SizedBox(
            height: _rowH[0],
            width: width,
            child: CustomPaint(
              painter: DashedRectPainter(color: hot ? BP.amber : BP.line, strokeWidth: hot ? 2 : 1),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      cluster == ' ' ? '␠' : cluster,
                      style: BT.sample(120, color: hot ? BP.amber : BP.ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _Connector(width: width, hot: hot),
          // Code points
          Row(
            children: [
              for (var k = 0; k < cps.length; k++) ...[
                _Cell(
                  width: _span(bytesPer[k], cell),
                  height: _rowH[1],
                  color: c,
                  top: _visible(cps[k]),
                  bottom: 'U+${cps[k].toRadixString(16).toUpperCase().padLeft(4, '0')}',
                  textColor: t,
                ),
                if (k < cps.length - 1) const SizedBox(width: _gap),
              ],
            ],
          ),
          _Connector(width: width, hot: hot),
          // UTF-16 code units
          Row(
            children: [
              for (var k = 0; k < cps.length; k++) ...[
                for (var u = 0; u < unitsPer[k]; u++) ...[
                  _Cell(
                    width: (_span(bytesPer[k], cell) - (unitsPer[k] - 1) * _gap) / unitsPer[k],
                    height: _rowH[2],
                    color: hot ? BP.amber : BP.amber.withValues(alpha: 0.5),
                    bottom: _utf16(cps[k])[u],
                    textColor: BP.amber,
                  ),
                  if (u < unitsPer[k] - 1) const SizedBox(width: _gap),
                ],
                if (k < cps.length - 1) const SizedBox(width: _gap),
              ],
            ],
          ),
          _Connector(width: width, hot: hot),
          // UTF-8 bytes
          Row(
            children: [
              for (var k = 0; k < cps.length; k++) ...[
                for (final (j, b) in utf8.encode(String.fromCharCode(cps[k])).indexed) ...[
                  _Cell(
                    width: cell,
                    height: _rowH[3],
                    color: c,
                    bottom: b.toRadixString(16).toUpperCase().padLeft(2, '0'),
                    textColor: hot ? BP.amber : BP.inkDim,
                  ),
                  if (j < bytesPer[k] - 1) const SizedBox(width: _gap),
                ],
                if (k < cps.length - 1) const SizedBox(width: _gap),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static List<String> _utf16(int cp) {
    final s = String.fromCharCode(cp);
    return [for (final u in s.codeUnits) u.toRadixString(16).toUpperCase().padLeft(4, '0')];
  }

  /// A printable stand-in for a code point.
  static String _visible(int cp) {
    if (cp == 0x200D) return 'ZWJ';
    if (cp == 0xFE0F) return 'VS16';
    if (cp == 0x20) return '␠';
    final s = String.fromCharCode(cp);
    // Combining marks get a dotted circle to sit on.
    final combining = (cp >= 0x0300 && cp <= 0x036F) ||
        (cp >= 0x093A && cp <= 0x094F) ||
        (cp >= 0x0951 && cp <= 0x0957) ||
        (cp >= 0x0900 && cp <= 0x0903) ||
        (cp >= 0x064B && cp <= 0x065F) ||
        (cp >= 0x3099 && cp <= 0x309A);
    return combining ? '◌$s' : s;
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.width, required this.hot});

  final double width;
  final bool hot;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: _rowGap,
    child: CustomPaint(painter: _BracketPainter(hot: hot)),
  );
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.hot});

  final bool hot;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = hot ? BP.amber : BP.lineFaint
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final m = size.height / 2;
    final path = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width / 2, m)
      ..moveTo(2, size.height - 4)
      ..lineTo(2, m)
      ..lineTo(size.width - 2, m)
      ..lineTo(size.width - 2, size.height - 4);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.hot != hot;
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.height,
    required this.color,
    required this.bottom,
    required this.textColor,
    this.top,
  });

  final double width;
  final double height;
  final Color color;
  final String? top;
  final String bottom;
  final Color textColor;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    width: width,
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (top != null)
            Text(top!, style: BT.sample(34, color: BP.ink)),
          Text(bottom, style: BT.mono(18, color: textColor)),
        ],
      ),
    ),
  );
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? BP.line.withValues(alpha: 0.18) : Colors.transparent,
            border: Border.all(color: selected ? BP.amber : BP.lineDim, width: selected ? 2 : 1),
          ),
          child: Text(text, style: BT.sample(28, color: selected ? BP.ink : BP.inkDim)),
        ),
      ),
    );
  }
}
