import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'deck.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Slide layout
// ─────────────────────────────────────────────────────────────────────────────

/// Standard slide: "07 / shaping" kicker + title, content area below.
///
/// Content area is the canvas minus margins: 1472 × 628 at (64, 176).
class SlideFrame extends StatelessWidget {
  const SlideFrame({
    super.key,
    required this.title,
    required this.child,
    this.kicker,
    this.contentTop = 176,
    this.contentBottom = 96,
    this.trailing,
  });

  final String title;
  final String? kicker;
  final Widget child;
  final double contentTop;
  final double contentBottom;

  /// Optional widget at the top-right (e.g. a control).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scope = SlideScope.of(context);
    final n = (scope.index + 1).toString().padLeft(2, '0');
    return Stack(
      children: [
        Positioned(
          left: BP.margin,
          right: BP.margin,
          top: contentTop,
          bottom: contentBottom,
          child: child,
        ),
        Positioned(
          left: BP.margin,
          top: 44,
          child: _TitleBlock(kicker: '$n / ${kicker ?? scope.section}', title: title),
        ),
        if (trailing != null)
          Positioned(right: BP.margin, top: 64, child: trailing!),
      ],
    );
  }
}

class _TitleBlock extends StatefulWidget {
  const _TitleBlock({required this.kicker, required this.title});

  final String kicker;
  final String title;

  @override
  State<_TitleBlock> createState() => _TitleBlockState();
}

class _TitleBlockState extends State<_TitleBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final line = Curves.easeOutCubic.transform((t / 0.6).clamp(0, 1));
        final text = Curves.easeOutCubic.transform(((t - 0.2) / 0.8).clamp(0, 1));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 28 * line, height: 1.5, color: BP.line),
                SizedBox(width: 10 * line),
                Opacity(
                  opacity: line,
                  child: Text(widget.kicker, style: BT.mono(16)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: text,
                child: Text(
                  widget.title,
                  style: BT.display(58, height: 1.1, letterSpacing: -1),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A section divider slide: big outlined number, name, and a row of glyphs.
class SectionSlide extends StatefulWidget {
  const SectionSlide({
    super.key,
    required this.number,
    required this.title,
    this.glyphs = const [],
  });

  final String number;
  final String title;
  final List<String> glyphs;

  @override
  State<SectionSlide> createState() => _SectionSlideState();
}

class _SectionSlideState extends State<SectionSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        double seg(double a, double b) =>
            Curves.easeOutCubic.transform(((_c.value - a) / (b - a)).clamp(0, 1));
        return Stack(
          children: [
            Positioned(
              left: 150,
              top: 250,
              child: Opacity(
                opacity: seg(0, 0.4),
                child: Text(
                  widget.number,
                  style: BT.display(260, weight: 700, height: 1).copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 2
                      ..color = BP.line,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 150,
              top: 560,
              width: 1300 * seg(0.1, 0.6),
              height: 1.5,
              child: const ColoredBox(color: BP.line),
            ),
            Positioned(
              left: 150,
              top: 590,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: seg(0.3, 0.8),
                  child: Text(widget.title, style: BT.display(72, letterSpacing: -1.5)),
                ),
              ),
            ),
            Positioned(
              left: 720,
              top: 300,
              right: 120,
              child: Wrap(
                spacing: 36,
                runSpacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  for (var i = 0; i < widget.glyphs.length; i++)
                    Opacity(
                      opacity: seg(0.4 + i * 0.05, 0.7 + i * 0.05),
                      child: Transform.translate(
                        offset: Offset(0, 30 * (1 - seg(0.4 + i * 0.05, 0.7 + i * 0.05))),
                        child: Text(
                          widget.glyphs[i],
                          style: BT.sample(88, color: i.isEven ? BP.line : BP.inkDim),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reveal helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Fades + slides a child in when [visible] becomes true.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.visible,
    required this.child,
    this.offset = const Offset(0, 24),
    this.duration = const Duration(milliseconds: 550),
    this.delay = Duration.zero,
    this.curve = Curves.easeOutCubic,
  });

  final bool visible;
  final Widget child;

  /// Offset in logical pixels the child starts from.
  final Offset offset;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _show();
  }

  @override
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      widget.visible ? _show() : _c.reverse();
    }
  }

  Future<void> _show() async {
    if (widget.delay > Duration.zero) {
      await Future<void>.delayed(widget.delay);
      if (!mounted || !widget.visible) return;
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = widget.curve.transform(_c.value);
        return IgnorePointer(
          ignoring: t < 0.5,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(offset: widget.offset * (1 - t), child: child),
          ),
        );
      },
    );
  }
}

/// [Reveal] driven by the slide's build step: visible once step >= [at].
class StepReveal extends StatelessWidget {
  const StepReveal({
    super.key,
    required this.at,
    required this.child,
    this.offset = const Offset(0, 24),
    this.delay = Duration.zero,
  });

  final int at;
  final Widget child;
  final Offset offset;
  final Duration delay;

  @override
  Widget build(BuildContext context) => Reveal(
    visible: SlideScope.of(context).step >= at,
    offset: offset,
    delay: delay,
    child: child,
  );
}

/// Repeating 0→1 animation value.
class LoopBuilder extends StatefulWidget {
  const LoopBuilder({
    super.key,
    required this.period,
    required this.builder,
    this.child,
    this.reverse = false,
  });

  final Duration period;
  final bool reverse;
  final Widget? child;
  final Widget Function(BuildContext context, double t, Widget? child) builder;

  @override
  State<LoopBuilder> createState() => _LoopBuilderState();
}

class _LoopBuilderState extends State<LoopBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: widget.reverse);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => widget.builder(context, _c.value, child),
  );
}

/// Rebuilds every frame with the elapsed time (for physics / continuous motion).
class ElapsedBuilder extends StatefulWidget {
  const ElapsedBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Duration elapsed) builder;

  @override
  State<ElapsedBuilder> createState() => _ElapsedBuilderState();
}

class _ElapsedBuilderState extends State<ElapsedBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _elapsed = d))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _elapsed);
}

/// Animated number, formatted with thousands separators.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
    this.suffix = '',
  });

  final num value;
  final TextStyle style;
  final Duration duration;
  final String suffix;

  static String format(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text('${format(v)}$suffix', style: style),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Panels, labels, tags
// ─────────────────────────────────────────────────────────────────────────────

/// Outlined blueprint panel with an optional label notched into the top edge.
class BpPanel extends StatelessWidget {
  const BpPanel({
    super.key,
    required this.child,
    this.label,
    this.padding = const EdgeInsets.all(24),
    this.color = BP.lineDim,
    this.fill = BP.panel,
    this.width,
    this.height,
    this.dashed = false,
  });

  final Widget child;
  final String? label;
  final EdgeInsets padding;
  final Color color;
  final Color fill;
  final double? width;
  final double? height;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _PanelPainter(color: color, fill: fill, dashed: dashed),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(padding: padding, child: child),
            if (label != null)
              Positioned(
                left: 14,
                top: -9,
                child: Container(
                  color: BP.paper,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(label!, style: BT.mono(13, color: color == BP.lineDim ? BP.line : color)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelPainter extends CustomPainter {
  _PanelPainter({required this.color, required this.fill, required this.dashed});

  final Color color;
  final Color fill;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = fill.withValues(alpha: fill.a * 0.85));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (dashed) {
      canvas.drawPath(dashPath(Path()..addRect(r)), p);
    } else {
      canvas.drawRect(r, p);
    }
    // Corner ticks
    final t = Paint()
      ..color = BP.line
      ..strokeWidth = 2;
    const l = 8.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx == 0 ? l : -l;
      final dy = c.dy == 0 ? l : -l;
      canvas.drawLine(c, c + Offset(dx, 0), t);
      canvas.drawLine(c, c + Offset(0, dy), t);
    }
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.color != color || old.fill != fill || old.dashed != dashed;
}

/// Box with a dashed outline (glyph boxes, bounding boxes).
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    this.color = BP.lineDim,
    this.padding = EdgeInsets.zero,
    this.strokeWidth = 1,
    this.dash = 6,
    this.gap = 4,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: DashedRectPainter(color: color, strokeWidth: strokeWidth, dash: dash, gap: gap),
    child: Padding(padding: padding, child: child),
  );
}

class DashedRectPainter extends CustomPainter {
  DashedRectPainter({
    this.color = BP.lineDim,
    this.strokeWidth = 1,
    this.dash = 6,
    this.gap = 4,
  });

  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(Path()..addRect(Offset.zero & size), dash: dash, gap: gap),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(DashedRectPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

/// Small mono tag with a tinted fill.
class BpTag extends StatelessWidget {
  const BpTag(this.text, {super.key, this.color = BP.line, this.size = 13, this.filled = false});

  final String text;
  final Color color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: size * 0.25),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.12),
      border: Border.all(color: color, width: 1),
    ),
    child: Text(text, style: BT.mono(size, color: filled ? BP.paper : color)),
  );
}

/// A dimension line like on a technical drawing: |←— label —→|
class DimensionLine extends StatelessWidget {
  const DimensionLine({
    super.key,
    required this.length,
    required this.label,
    this.vertical = false,
    this.color = BP.amber,
  });

  final double length;
  final String label;
  final bool vertical;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lineBox = SizedBox(
      width: vertical ? 16 : length,
      height: vertical ? length : 16,
      child: CustomPaint(painter: _DimPainter(vertical: vertical, color: color)),
    );
    final text = Text(label, style: BT.mono(13, color: color));
    return vertical
        ? Row(mainAxisSize: MainAxisSize.min, children: [lineBox, const SizedBox(width: 6), text])
        : Column(mainAxisSize: MainAxisSize.min, children: [lineBox, const SizedBox(height: 2), text]);
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter({required this.vertical, required this.color});

  final bool vertical;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    if (vertical) {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      canvas.drawLine(Offset(0, 0), Offset(size.width, 0), p);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p);
      drawArrowHead(canvas, Offset(x, 0), Offset(x, 10), p, 5);
      drawArrowHead(canvas, Offset(x, size.height), Offset(x, size.height - 10), p, 5);
    } else {
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      canvas.drawLine(Offset(0, 0), Offset(0, size.height), p);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
      drawArrowHead(canvas, Offset(0, y), Offset(10, y), p, 5);
      drawArrowHead(canvas, Offset(size.width, y), Offset(size.width - 10, y), p, 5);
    }
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Controls (none of them take keyboard focus, so arrows keep driving the deck)
// ─────────────────────────────────────────────────────────────────────────────

class BpButton extends StatefulWidget {
  const BpButton({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color = BP.line,
    this.size = 15,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final Color color;
  final double size;
  final IconData? icon;

  @override
  State<BpButton> createState() => _BpButtonState();
}

class _BpButtonState extends State<BpButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: widget.size * 0.9, vertical: widget.size * 0.45),
          decoration: BoxDecoration(
            color: sel ? c : (_hover ? c.withValues(alpha: 0.14) : Colors.transparent),
            border: Border.all(color: sel || _hover ? c : c.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.size + 2, color: sel ? BP.paper : c),
                const SizedBox(width: 8),
              ],
              Text(widget.label, style: BT.mono(widget.size, color: sel ? BP.paper : c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of mutually exclusive [BpButton]s.
class BpSegmented<T> extends StatelessWidget {
  const BpSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.labelOf,
    this.color = BP.line,
    this.size = 15,
    this.spacing = 8,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final Color color;
  final double size;
  final double spacing;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: spacing,
    runSpacing: spacing,
    children: [
      for (final v in values)
        BpButton(
          label: labelOf?.call(v) ?? '$v',
          selected: v == selected,
          color: color,
          size: size,
          onTap: () => onChanged(v),
        ),
    ],
  );
}

/// Ruler-style slider: ticks, a diamond thumb, a mono readout.
class BpSlider extends StatelessWidget {
  const BpSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.width = 320,
    this.label,
    this.format,
    this.ticks = 10,
    this.color = BP.line,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final double width;
  final String? label;
  final String Function(double v)? format;
  final int ticks;
  final Color color;

  @override
  Widget build(BuildContext context) {
    void update(Offset p, double w) {
      final t = (p.dx / w).clamp(0.0, 1.0);
      onChanged(min + t * (max - min));
    }

    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: BT.mono(14, color: BP.inkDim)),
          const SizedBox(width: 14),
        ],
        SizedBox(
          width: width,
          height: 36,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => update(d.localPosition, width),
              onPanUpdate: (d) => update(d.localPosition, width),
              child: CustomPaint(painter: _SliderPainter(t: t, ticks: ticks, color: color)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 88,
          child: Text(
            format?.call(value) ?? value.toStringAsFixed(1),
            style: BT.mono(14, color: BP.amber),
          ),
        ),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({required this.t, required this.ticks, required this.color});

  final double t;
  final int ticks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dim = Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1;
    final hot = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), dim);
    for (var i = 0; i <= ticks; i++) {
      final x = size.width * i / ticks;
      final h = i % 5 == 0 ? 8.0 : 4.0;
      canvas.drawLine(Offset(x, y - h), Offset(x, y + h), dim);
    }
    final x = size.width * t;
    canvas.drawLine(Offset(0, y), Offset(x, y), hot);
    final d = Path()
      ..moveTo(x, y - 9)
      ..lineTo(x + 9, y)
      ..lineTo(x, y + 9)
      ..lineTo(x - 9, y)
      ..close();
    canvas.drawPath(d, Paint()..color = BP.paper);
    canvas.drawPath(
      d,
      Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.t != t || old.color != color;
}

/// Blueprint text input. Tapping outside or pressing Esc releases focus so the
/// arrow keys drive the deck again.
class BpTextField extends StatelessWidget {
  const BpTextField({
    super.key,
    required this.controller,
    this.onChanged,
    this.style,
    this.width = 520,
    this.hint,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;
  final double width;
  final String? hint;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      textAlign: textAlign,
      style: style ?? BT.sample(30),
      cursorColor: BP.amber,
      cursorWidth: 2.5,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: BT.mono(18, color: BP.inkFaint),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(right: 10, top: 6),
          child: Text('›', style: BT.mono(26, color: BP.amber)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: BP.lineDim)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: BP.amber, width: 2)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Paths: arrows, dashes, draw-on
// ─────────────────────────────────────────────────────────────────────────────

Path dashPath(Path source, {double dash = 6, double gap = 4}) {
  final out = Path();
  for (final m in source.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
      d += dash + gap;
    }
  }
  return out;
}

/// The first [t] (0..1) of [source]'s length.
Path partialPath(Path source, double t) {
  if (t >= 1) return source;
  final metrics = source.computeMetrics().toList();
  final total = metrics.fold<double>(0, (a, m) => a + m.length);
  var left = total * t.clamp(0, 1);
  final out = Path();
  for (final m in metrics) {
    if (left <= 0) break;
    out.addPath(m.extractPath(0, math.min(left, m.length)), Offset.zero);
    left -= m.length;
  }
  return out;
}

/// Draws a V arrow head at [tip], pointing away from [from].
void drawArrowHead(Canvas canvas, Offset tip, Offset from, Paint paint, [double size = 9]) {
  final dir = (tip - from);
  if (dir.distance == 0) return;
  final a = math.atan2(dir.dy, dir.dx);
  final p = Path()
    ..moveTo(tip.dx - size * math.cos(a - 0.45), tip.dy - size * math.sin(a - 0.45))
    ..lineTo(tip.dx, tip.dy)
    ..lineTo(tip.dx - size * math.cos(a + 0.45), tip.dy - size * math.sin(a + 0.45));
  canvas.drawPath(
    p,
    Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

/// Draws a straight arrow from [a] to [b], optionally dashed and partially.
void drawArrow(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  bool dashed = false,
  double progress = 1,
  double head = 9,
}) {
  final end = Offset.lerp(a, b, progress.clamp(0, 1))!;
  final path = Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(end.dx, end.dy);
  canvas.drawPath(dashed ? dashPath(path) : path, paint..style = PaintingStyle.stroke);
  if (progress > 0.05) drawArrowHead(canvas, end, a, paint, head);
}

/// Animates stroking a path, like a pen drawing it.
class DrawOn extends StatefulWidget {
  const DrawOn({
    super.key,
    required this.path,
    this.color = BP.line,
    this.strokeWidth = 1.5,
    this.duration = const Duration(milliseconds: 900),
    this.delay = Duration.zero,
    this.visible = true,
    this.dashed = false,
    this.arrow = false,
    this.child,
  });

  final Path Function(Size size) path;
  final Color color;
  final double strokeWidth;
  final Duration duration;
  final Duration delay;
  final bool visible;
  final bool dashed;
  final bool arrow;
  final Widget? child;

  @override
  State<DrawOn> createState() => _DrawOnState();
}

class _DrawOnState extends State<DrawOn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.visible) _play();
  }

  @override
  void didUpdateWidget(DrawOn old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) widget.visible ? _play() : _c.reverse();
  }

  Future<void> _play() async {
    if (widget.delay > Duration.zero) {
      await Future<void>.delayed(widget.delay);
      if (!mounted || !widget.visible) return;
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DrawOnPainter(
      animation: _c,
      path: widget.path,
      color: widget.color,
      strokeWidth: widget.strokeWidth,
      dashed: widget.dashed,
      arrow: widget.arrow,
    ),
    child: widget.child ?? const SizedBox.expand(),
  );
}

class _DrawOnPainter extends CustomPainter {
  _DrawOnPainter({
    required this.animation,
    required this.path,
    required this.color,
    required this.strokeWidth,
    required this.dashed,
    required this.arrow,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Path Function(Size) path;
  final Color color;
  final double strokeWidth;
  final bool dashed;
  final bool arrow;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOutCubic.transform(animation.value);
    if (t <= 0) return;
    final full = path(size);
    var p = partialPath(full, t);
    if (dashed) p = dashPath(p);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(p, paint);
    if (arrow) {
      final ms = partialPath(full, t).computeMetrics().toList();
      if (ms.isNotEmpty) {
        final m = ms.last;
        final tan = m.getTangentForOffset(m.length);
        final back = m.getTangentForOffset(math.max(0, m.length - 6));
        if (tan != null && back != null) {
          drawArrowHead(canvas, tan.position, back.position, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DrawOnPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Text measurement
// ─────────────────────────────────────────────────────────────────────────────

/// A laid-out paragraph you can query: glyph boxes, lines, carets.
///
/// Wraps [TextPainter] (which wraps dart:ui's Paragraph, i.e. SkParagraph).
class TextProbe {
  TextProbe(
    InlineSpan span, {
    double maxWidth = double.infinity,
    TextAlign textAlign = TextAlign.start,
    TextDirection textDirection = TextDirection.ltr,
  }) : painter = TextPainter(
         text: span,
         textAlign: textAlign,
         textDirection: textDirection,
       )..layout(maxWidth: maxWidth);

  final TextPainter painter;

  Size get size => painter.size;
  String get text => painter.plainText;
  List<ui.LineMetrics> get lines => painter.computeLineMetrics();

  /// Boxes covering UTF-16 range [start, end). Several boxes if bidi splits it.
  List<TextBox> boxes(int start, int end) =>
      painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));

  Rect? rectFor(int start, int end) {
    final b = boxes(start, end);
    if (b.isEmpty) return null;
    return b.map((e) => e.toRect()).reduce((a, c) => a.expandToInclude(c));
  }

  /// Grapheme clusters as UTF-16 [start, end) ranges.
  List<(int, int)> graphemes() {
    final out = <(int, int)>[];
    var i = 0;
    for (final g in text.characters) {
      out.add((i, i + g.length));
      i += g.length;
    }
    return out;
  }

  void paint(Canvas canvas, Offset offset) => painter.paint(canvas, offset);

  void dispose() => painter.dispose();
}
