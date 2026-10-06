import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/ui/ink.dart';
import 'package:text_slides/deck/theme.dart';

import 'talk.dart';
import 'talk_section.dart';

/// The talk's slide over the city: the stop's card on the left (what
/// happens there, with the talk's real values) over a shade, and the
/// section's way along the bottom, this stop lit.
///
///   05 · ONE WORD'S JOURNEY                    4 / 11
///   デコード
///   Unicode analysis
///   ICU walks the code points: where a letter …
///   ┌ F  l  u  t  t  e  r ┐
///   └ U+0046 …           ┘
///
///   ●──●──●──●──◉──○──○──○──○──○──○
///   MAP WIDGET STRING ENGINE UNICODE …
class TalkOverlay extends StatelessWidget {
  const TalkOverlay({super.key, required this.talk, this.animate = true});

  final Talk talk;

  /// Cross-fade the cards (not in a capture: frames are taken at once).
  final bool animate;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ListenableBuilder(
      listenable: talk,
      builder: (context, _) {
        if (!talk.on) return const SizedBox.shrink();
        final stop = talk.stop, section = talk.section;
        return Stack(
          children: [
            // The city's bright by day: a shade behind the card.
            if (talk.cardShown)
              Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 820,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [BP.bg.withValues(alpha: 0.5), BP.bg.withValues(alpha: 0.28), BP.bg.withValues(alpha: 0)],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // How far through the whole talk: a section a stretch, along the top.
            Positioned(left: 0, right: 0, top: 0, height: 4, child: CustomPaint(painter: _ProgressPainter(talk))),
            Positioned.fill(child: CustomPaint(painter: _PinPainter(talk))),
            // A chapter's opening, large in the middle until its card's up.
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: animate ? const Duration(milliseconds: 520) : Duration.zero,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: talk.chapter
                    ? _Chapter(
                        key: ValueKey(('chapter', talk.sectionIndex, stop)),
                        card: talk.card,
                        section: section,
                        glyphs: stop == 0,
                        animate: animate,
                      )
                    : const SizedBox.shrink(key: ValueKey('no chapter')),
              ),
            ),
            Positioned(
              left: BP.margin,
              top: 56,
              width: 548,
              child: AnimatedSwitcher(
                duration: animate ? const Duration(milliseconds: 380) : Duration.zero,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(-0.04, 0), end: Offset.zero).animate(a), child: child),
                ),
                child: !talk.cardShown
                    ? const SizedBox(key: ValueKey('none'))
                    : _Card(
                  key: ValueKey((talk.sectionIndex, stop)),
                  card: talk.card,
                  section: section,
                  stop: stop,
                  beat: talk.beat,
                  beats: talk.beats,
                  animate: animate,
                ),
              ),
            ),
            // (And under the way along the bottom.)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [BP.bg.withValues(alpha: 0), BP.bg.withValues(alpha: 0.7)],
                  ),
                ),
              ),
            ),
            if (section.stops.length > 2)
              Positioned(left: BP.margin, right: BP.margin, bottom: 26, height: 52, child: _Route(stops: section.stops, stop: stop)),
          ],
        );
      },
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.card,
    required this.section,
    required this.stop,
    required this.beat,
    required this.beats,
    required this.animate,
  });

  final TalkCard card;
  final TalkSection section;
  final int stop;

  /// Where in the stop (a stop with more than one beat shows a dot each).
  final int beat, beats;

  /// Its parts come in one after another (not in a capture).
  final bool animate;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    // Frosted: the city behind it, blurred, through a tinted pane.
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(30, 26, 30, 30),
        decoration: BoxDecoration(
          color: BP.panel.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BP.line.withValues(alpha: 0.2)),
        ),
        child: _Stagger(
          animate: animate,
          children: [
            Row(
              children: [
                Text(
                  section.number.isEmpty ? section.title.toUpperCase() : '${section.number} · ${section.title.toUpperCase()}',
                  style: UT.mono(12.5, color: BP.amber, weight: 600, ls: 1.6),
                ),
                const Spacer(),
                if (beats > 1) ...[
                  for (var i = 0; i < beats; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= beat ? BP.amber : null,
                        border: Border.all(color: i <= beat ? BP.amber : BP.inkFaint, width: 1.2),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
                Text('${stop + 1} / ${section.stops.length}', style: UT.mono(12.5, color: BP.inkFaint, weight: 600, ls: 1.2)),
              ],
            ),
            if (card.opener && section.number.isNotEmpty)
              // A section's first: its number large, as the deck's divider.
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(section.number, style: UT.name(88, color: BP.amber, weight: 500, height: 0.95)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.ja, style: UT.label(16, color: BP.inkDim, weight: 500)),
                  const SizedBox(height: 2),
                  Text(card.title, style: UT.name(card.opener ? 52 : 46, color: BP.ink, weight: 600, height: 1.05)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(card.lede, style: UT.label(19.5, color: BP.inkDim, weight: 400, height: 1.42)),
            ),
            for (final f in card.facts) Padding(padding: const EdgeInsets.only(top: 18), child: _fact(f)),
          ],
        ),
      ),
    ),
  );

  /// A label in capitals, but code as it's written (s.length).
  static String _caps(String label) => label.contains(RegExp(r'[.(_]')) ? label : label.toUpperCase();

  Widget _fact(CardFact f) => switch (f) {
    FactRow(:final label, :final value, :final accent) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(width: 138, child: Text(_caps(label), style: UT.mono(12.5, color: BP.inkFaint, weight: 600, ls: 1.1))),
        Expanded(
          child: accent
              ? _CountUp(value, style: UT.mono(17, color: BP.amber, weight: 600), animate: animate)
              : Text(value, style: UT.mono(17, color: BP.ink, weight: 600)),
        ),
      ],
    ),
    FactCode(:final code) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: BP.bg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BP.lineFaint),
      ),
      child: Text(code, style: UT.mono(15, color: BP.ink, weight: 500).copyWith(height: 1.5)),
    ),
    FactLetters(:final label, :final cells) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(_caps(label), style: UT.mono(11.5, color: BP.inkFaint, weight: 600, ls: 1.2)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            for (final (i, (letter, value, lit)) in cells.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                  decoration: BoxDecoration(
                    color: lit ? BP.amber.withValues(alpha: 0.13) : BP.bg.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: lit ? BP.amber.withValues(alpha: 0.7) : BP.lineFaint),
                  ),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(letter, maxLines: 1, style: UT.name(26, color: lit ? BP.amber : BP.ink, weight: 500, height: 1.1)),
                      ),
                      if (value.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(value, maxLines: 1, style: UT.mono(12, color: lit ? BP.amber : BP.inkDim, weight: 600)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  };
}

/// A chapter's opening, as the deck's dividers: its number very large in
/// outline, a rule, its title and Japanese name, a line under them, and its
/// glyphs rising one by one; in the middle, over a soft shade.
class _Chapter extends StatelessWidget {
  const _Chapter({super.key, required this.card, required this.section, required this.glyphs, required this.animate});

  final TalkCard card;
  final TalkSection section;

  /// With the section's glyphs (its opening: not a later chapter in it).
  final bool glyphs;
  final bool animate;

  static const _glow = [Shadow(color: Color(0xCC081728), blurRadius: 28)];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        radius: 0.75,
        colors: [BP.bg.withValues(alpha: 0.62), BP.bg.withValues(alpha: 0.32), BP.bg.withValues(alpha: 0)],
        stops: const [0, 0.55, 1],
      ),
    ),
    child: Center(
      child: _Stagger(
        animate: animate,
        center: true,
        children: [
          if (section.number.isNotEmpty)
            Text(
              section.number,
              style: UT.name(210, weight: 400, height: 0.9).copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.6
                  ..color = BP.amber,
              ),
            ),
          Container(width: 140, height: 2, margin: const EdgeInsets.only(top: 20, bottom: 26), color: BP.amber),
          Text(card.ja, style: UT.label(24, color: BP.inkDim, weight: 500).copyWith(shadows: _glow)),
          const SizedBox(height: 6),
          Text(
            card.title,
            textAlign: TextAlign.center,
            style: UT.name(section.number.isEmpty ? 92 : 76, color: BP.ink, weight: 600, height: 1.05).copyWith(shadows: _glow),
          ),
          if (section.number.isEmpty && card.lede.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(card.lede, style: UT.label(24, color: BP.inkDim, weight: 400).copyWith(shadows: _glow)),
            ),
          if (glyphs && section.glyphs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 34),
              child: _Stagger(
                animate: animate,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, g) in section.glyphs.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(g, style: UT.name(46, color: i.isEven ? BP.line : BP.inkDim, weight: 500).copyWith(shadows: _glow)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// A value whose first number (10 or more) counts up as its card comes in.
class _CountUp extends StatelessWidget {
  const _CountUp(this.value, {required this.style, required this.animate});

  final String value;
  final TextStyle style;
  final bool animate;

  static final _number = RegExp(r'\d[\d,]*');

  @override
  Widget build(BuildContext context) {
    final m = _number.firstMatch(value);
    final digits = m?.group(0);
    final n = digits == null ? null : int.tryParse(digits.replaceAll(',', ''));
    if (!animate || m == null || digits == null || n == null || n < 10) return Text(value, style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: n.toDouble()),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(value.replaceRange(m.start, m.end, _grouped(v.round(), digits.contains(','))), style: style),
    );
  }

  /// [v] with thousands commas, if [commas].
  static String _grouped(int v, bool commas) {
    final s = '$v';
    if (!commas) return s;
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

/// The whole talk along the top: a stretch a section (as long as its
/// beats), those done lit, this one lit as far as it's got.
class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.talk);

  final Talk talk;

  @override
  void paint(Canvas canvas, Size size) {
    final secs = talk.sections;
    final total = secs.fold<int>(0, (a, s) => a + s.beats.length);
    const gap = 6.0;
    final w = size.width - gap * (secs.length - 1);
    var x = 0.0;
    for (final (i, s) in secs.indexed) {
      final len = w * s.beats.length / total;
      final r = Rect.fromLTWH(x, 0, len, size.height);
      canvas.drawRect(r, Paint()..color = BP.inkFaint.withValues(alpha: 0.28));
      final done = i < talk.sectionIndex ? 1.0 : (i == talk.sectionIndex ? (talk.beatIndex + 1) / s.beats.length : 0.0);
      if (done > 0) canvas.drawRect(Rect.fromLTWH(x, 0, len * done, size.height), Paint()..color = BP.amber.withValues(alpha: i == talk.sectionIndex ? 0.95 : 0.55));
      x += len + gap;
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => true;
}

/// A card's parts coming in one after another, each a little up and in,
/// as it's shown.
class _Stagger extends StatefulWidget {
  const _Stagger({required this.children, required this.animate, this.center = false});

  final List<Widget> children;
  final bool animate;

  /// Each part in the middle (a chapter's), else on the left.
  final bool center;

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger> with SingleTickerProviderStateMixin {
  late final _in = AnimationController(vsync: this, duration: Duration(milliseconds: 420 + 80 * widget.children.length));

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _in.forward();
    } else {
      _in.value = 1;
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    return Column(
      crossAxisAlignment: widget.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in widget.children.indexed)
          () {
            final from = 0.55 * i / n;
            final a = CurvedAnimation(parent: _in, curve: Interval(from, math.min(1.0, from + 0.45), curve: Curves.easeOutCubic));
            return FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: child),
            );
          }(),
      ],
    );
  }
}

/// What's pinned to the city: a dot where it is, a line up from it and its
/// name, following the camera.
class _PinPainter extends CustomPainter {
  _PinPainter(this.talk) : super(repaint: talk.frame);

  final Talk talk;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = talk.pinsShown;
    if (shown <= 0.01) return;
    final k = Curves.easeOutCubic.transform(shown);
    final amber = BP.amber.withValues(alpha: k);
    // Each name above its place; one that would cover another goes up until
    // it doesn't (the lowest on screen, the nearest, placed first).
    final pins = [
      for (final p in talk.pins)
        if (talk.project(p.at) case final o?) (o, p),
    ]..sort((a, b) => b.$1.dy.compareTo(a.$1.dy));
    final placed = <Rect>[];
    for (final (o, TalkPin(:ja, :en)) in pins) {
      final label = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: '$ja  ', style: UT.label(17, color: BP.ink.withValues(alpha: k), weight: 600)),
            TextSpan(text: en, style: UT.mono(13, color: BP.amber.withValues(alpha: k), weight: 700, ls: 1.4)),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = label.width + 28, h = label.height + 16;
      var lift = 58.0;
      Rect box() => Rect.fromLTWH(o.dx - w / 2, o.dy - lift * k - h, w, h);
      while (lift < 420 && placed.any((r) => r.overlaps(box().inflate(5)))) {
        lift += 6;
      }
      final b = box();
      placed.add(b);
      canvas
        ..drawCircle(o, 5, Paint()..color = amber)
        ..drawCircle(
          o,
          9 + 5 * (1 - k),
          Paint()
            ..color = BP.amber.withValues(alpha: 0.5 * k)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        )
        ..drawLine(
          o - const Offset(0, 9),
          Offset(o.dx, b.bottom),
          Paint()
            ..color = amber
            ..strokeWidth = 1.6,
        );
      final rr = RRect.fromRectAndRadius(b, const Radius.circular(8));
      canvas
        ..drawRRect(rr, Paint()..color = BP.panel.withValues(alpha: 0.92 * k))
        ..drawRRect(
          rr,
          Paint()
            ..color = amber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      label
        ..paint(canvas, Offset(b.left + 14, b.top + 8))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.talk != talk;
}

/// The way: a dot per stop on a line, those passed lit, this one ringed.
class _Route extends StatelessWidget {
  const _Route({required this.stops, required this.stop});

  final List<String> stops;
  final int stop;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RoutePainter(stops, stop));
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.stops, this.stop);

  final List<String> stops;
  final int stop;

  @override
  void paint(Canvas canvas, Size size) {
    final n = stops.length;
    const y = 12.0;
    final dx = n < 2 ? 0.0 : size.width / (n - 1);
    final dim = Paint()
      ..color = BP.inkFaint.withValues(alpha: 0.55)
      ..strokeWidth = 1.6;
    final lit = Paint()
      ..color = BP.amber.withValues(alpha: 0.75)
      ..strokeWidth = 2.2;
    canvas
      ..drawLine(Offset(dx * stop, y), Offset(size.width, y), dim)
      ..drawLine(const Offset(0, y), Offset(dx * stop, y), lit);
    for (var i = 0; i < n; i++) {
      final o = Offset(dx * i, y);
      if (i == stop) {
        canvas
          ..drawCircle(o, 9, Paint()..color = BP.bg)
          ..drawCircle(
            o,
            9,
            Paint()
              ..color = BP.amber
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2,
          )
          ..drawCircle(o, 4.5, Paint()..color = BP.amber);
      } else {
        canvas.drawCircle(o, i < stop ? 4.5 : 4, Paint()..color = i < stop ? BP.amber : BP.bg);
        if (i > stop) {
          canvas.drawCircle(
            o,
            4,
            Paint()
              ..color = BP.inkFaint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        }
      }
      final label = TextPainter(
        text: TextSpan(
          text: stops[i].toUpperCase(),
          style: UT.mono(11, color: i == stop ? BP.amber : (i < stop ? BP.inkDim : BP.inkFaint), weight: i == stop ? 700 : 600, ls: 1.1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (o.dx - label.width / 2).clamp(-8.0, size.width - label.width + 8);
      label
        ..paint(canvas, Offset(lx, y + 15))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.stop != stop || !identical(old.stops, stops);
}
