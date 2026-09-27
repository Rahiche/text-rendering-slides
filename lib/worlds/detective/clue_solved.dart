import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Case solved: the fixes (any one of them), and 直 before / after, big.
/// Poke: click a fix to apply it — the stamp comes down.
class SolvedSlide extends StatefulWidget {
  const SolvedSlide({super.key});

  @override
  State<SolvedSlide> createState() => _SolvedSlideState();
}

const _fixes = <List<(String, Color)>>[
  [
    ('MaterialApp(', BP.ink),
    ("  supportedLocales: const [Locale('ja'), Locale('en')],", BP.green),
    ('  localizationsDelegates: GlobalMaterialLocalizations.delegates,', BP.green),
    ('  // ↑ package:flutter_localizations', BP.inkFaint),
    (')', BP.ink),
  ],
  [("Text('直', locale: const Locale('ja'))", BP.green)],
  [("TextStyle(locale: const Locale('ja'))", BP.green)],
  [
    ('// or bundle a Japanese font:', BP.inkFaint),
    ("TextStyle(fontFamily: 'Noto Sans JP')", BP.green),
  ],
];

const _fixLabels = ['app', 'widget', 'style', 'font'];

class _SolvedSlideState extends State<SolvedSlide> with SingleTickerProviderStateMixin {
  int _sel = 0;
  bool _touched = false;
  Timer? _auto;
  late final AnimationController _stamp = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  final _labels = LabelCache();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _stamp.forward(from: 0);
    });
    _auto = Timer.periodic(const Duration(milliseconds: 3800), (_) {
      if (!_touched && mounted) _apply((_sel + 1) % _fixes.length, user: false);
    });
  }

  void _apply(int i, {bool user = true}) {
    setState(() {
      _sel = i;
      if (user) _touched = true;
    });
    _stamp.forward(from: 0);
  }

  @override
  void dispose() {
    _auto?.cancel();
    _stamp.dispose();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Case solved',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The fixes: any one of them closes the case.
          Positioned(
            left: 0,
            top: 0,
            width: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _fixes.length; i++) ...[
                  _FixCard(
                    index: i,
                    label: _fixLabels[i],
                    lines: _fixes[i],
                    selected: i == _sel,
                    onTap: () => _apply(i),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          // Before → after.
          Positioned(
            left: 850,
            top: 20,
            child: PinnedPhoto(
              width: 260,
              height: 320,
              color: BP.amber,
              caption: const _Cap('before', 'en-US', BP.amber),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: Text('直', style: NT.caseSC(190, color: BP.amber.withValues(alpha: 0.75)))),
                  CustomPaint(painter: _StrikePainter()),
                ],
              ),
            ),
          ),
          Positioned(
            left: 1122,
            top: 164,
            child: Text('→', style: BT.mono(40, color: BP.inkDim)),
          ),
          Positioned(
            left: 1190,
            top: 20,
            child: PinnedPhoto(
              width: 282,
              height: 360,
              color: BP.line,
              caption: const _Cap('after', 'ja', BP.line),
              child: AnimatedBuilder(
                animation: _stamp,
                builder: (context, _) => Center(
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * Curves.easeOutBack.transform(_stamp.value.clamp(0.0, 1.0)),
                    child: Text('直', style: NT.caseJP(220, color: BP.line)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 850,
            top: 400,
            child: Text('demo: Noto Sans JP / SC', style: BT.mono(12, color: BP.inkFaint)),
          ),
          // The stamp.
          Positioned(
            left: 1080,
            top: 330,
            width: 400,
            height: 260,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _stamp,
                builder: (context, _) => CustomPaint(
                  painter: _StampPainter(_stamp.value, _labels),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FixCard extends StatefulWidget {
  const _FixCard({required this.index, required this.label, required this.lines, required this.selected, required this.onTap});

  final int index;
  final String label;
  final List<(String, Color)> lines;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FixCard> createState() => _FixCardState();
}

class _FixCardState extends State<_FixCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hot = widget.selected || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 800,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            color: widget.selected ? BP.green.withValues(alpha: 0.08) : BP.panel,
            border: Border.all(color: widget.selected ? BP.green : (hot ? BP.line : BP.lineDim), width: widget.selected ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                child: Text(widget.label, style: BT.mono(14, color: widget.selected ? BP.green : BP.inkFaint)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (line, color) in widget.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          line,
                          style: BT.mono(line.length > 56 ? 16 : 18, color: widget.selected ? color : color.withValues(alpha: 0.7))
                              .copyWith(locale: jaLocale),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cap extends StatelessWidget {
  const _Cap(this.label, this.lang, this.color);

  final String label;
  final String lang;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: BT.mono(16, color: color)),
      EvidenceTag(lang, color: color, size: 13),
    ],
  );
}

class _StrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.9),
      Offset(size.width * 0.9, size.height * 0.1),
      Paint()
        ..color = BP.red.withValues(alpha: 0.8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StrikePainter old) => false;
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.t, this.labels);

  final double t;
  final LabelCache labels;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = labels.get('解決 · SOLVED', NT.jp(40, color: BP.red, weight: 700));
    paintStamp(canvas, Offset(size.width / 2, size.height / 2), tp, t, angle: -0.14 + 0.02 * math.sin(t * 3));
  }

  @override
  bool shouldRepaint(_StampPainter old) => old.t != t;
}
