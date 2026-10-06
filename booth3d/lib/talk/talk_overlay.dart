import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/ui/ink.dart';
import 'package:text_slides/deck/theme.dart';

import 'journey_cards.dart';
import 'journey_talk.dart';

/// The talk's slide over the city: the stop's card on the left (what
/// happens there, with the word's real values) over a shade, and the whole
/// way along the bottom, this stop lit.
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

  final JourneyTalk talk;

  /// Cross-fade the cards (not in a capture: frames are taken at once).
  final bool animate;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ListenableBuilder(
      listenable: talk,
      builder: (context, _) {
        if (!talk.on) return const SizedBox.shrink();
        final stop = talk.stop;
        return Stack(
          children: [
            // The city's bright by day: a shade behind the card.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 820,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [BP.bg.withValues(alpha: 0.62), BP.bg.withValues(alpha: 0.38), BP.bg.withValues(alpha: 0)],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _PinPainter(talk))),
            Positioned(
              left: BP.margin,
              top: 56,
              width: 520,
              child: AnimatedSwitcher(
                duration: animate ? const Duration(milliseconds: 380) : Duration.zero,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(-0.04, 0), end: Offset.zero).animate(a), child: child),
                ),
                child: _Card(key: ValueKey(stop), card: talk.card, stop: stop, stops: talk.stops, beat: talk.beat, beats: talk.beats),
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
            Positioned(left: BP.margin, right: BP.margin, bottom: 26, height: 52, child: _Route(stop: stop)),
          ],
        );
      },
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.card, required this.stop, required this.stops, required this.beat, required this.beats});

  final JourneyCard card;
  final int stop, stops;

  /// Where in the stop (a stop with more than one beat shows a dot each).
  final int beat, beats;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(30, 26, 30, 30),
    decoration: BoxDecoration(
      color: BP.panel.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: BP.line.withValues(alpha: 0.22)),
      boxShadow: [BoxShadow(color: BP.bg.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 10))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text("05 · ONE WORD'S JOURNEY", style: UT.mono(12.5, color: BP.amber, weight: 600, ls: 1.6)),
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
            Text('${stop + 1} / $stops', style: UT.mono(12.5, color: BP.inkFaint, weight: 600, ls: 1.2)),
          ],
        ),
        const SizedBox(height: 18),
        Text(card.ja, style: UT.label(16, color: BP.inkDim, weight: 500)),
        const SizedBox(height: 2),
        Text(card.title, style: UT.name(46, color: BP.ink, weight: 600, height: 1.05)),
        const SizedBox(height: 12),
        Text(card.lede, style: UT.label(18.5, color: BP.inkDim, weight: 400, height: 1.42)),
        for (final f in card.facts) ...[const SizedBox(height: 18), _fact(f)],
      ],
    ),
  );

  Widget _fact(CardFact f) => switch (f) {
    FactRow(:final label, :final value, :final accent) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(width: 132, child: Text(label.toUpperCase(), style: UT.mono(11.5, color: BP.inkFaint, weight: 600, ls: 1.2))),
        Expanded(child: Text(value, style: UT.mono(16, color: accent ? BP.amber : BP.ink, weight: 600))),
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
      child: Text(code, style: UT.mono(14, color: BP.ink, weight: 500).copyWith(height: 1.5)),
    ),
    FactLetters(:final label, :final cells) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: UT.mono(11.5, color: BP.inkFaint, weight: 600, ls: 1.2)),
        const SizedBox(height: 8),
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
                      Text(letter, style: UT.name(26, color: lit ? BP.amber : BP.ink, weight: 500, height: 1.1)),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(value, maxLines: 1, style: UT.mono(12, color: lit ? BP.amber : BP.inkDim, weight: 600)),
                      ),
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

/// What's pinned to the city: a dot where it is, a line up from it and its
/// name, following the camera.
class _PinPainter extends CustomPainter {
  _PinPainter(this.talk) : super(repaint: talk.frame);

  final JourneyTalk talk;

  @override
  void paint(Canvas canvas, Size size) {
    final shown = talk.pinsShown;
    if (shown <= 0.01) return;
    final k = Curves.easeOutCubic.transform(shown);
    for (final (at, ja, en) in talk.pins) {
      final o = talk.project(at);
      if (o == null) continue;
      final amber = BP.amber.withValues(alpha: k);
      canvas
        ..drawCircle(o, 5, Paint()..color = amber)
        ..drawCircle(
          o,
          9 + 5 * (1 - k),
          Paint()
            ..color = BP.amber.withValues(alpha: 0.5 * k)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      final top = o.dy - 58 * k;
      canvas.drawLine(
        o - const Offset(0, 9),
        Offset(o.dx, top),
        Paint()
          ..color = amber
          ..strokeWidth = 1.6,
      );
      final label = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: '$ja  ', style: UT.label(17, color: BP.ink.withValues(alpha: k), weight: 600)),
            TextSpan(text: en, style: UT.mono(13, color: BP.amber.withValues(alpha: k), weight: 700, ls: 1.4)),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromLTWH(o.dx - label.width / 2 - 14, top - label.height - 16, label.width + 28, label.height + 16);
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(8));
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
        ..paint(canvas, Offset(box.left + 14, box.top + 8))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.talk != talk;
}

/// The way: a dot per stop on a line, those passed lit, this one ringed.
class _Route extends StatelessWidget {
  const _Route({required this.stop});

  final int stop;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RoutePainter(stop));
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.stop);

  final int stop;

  @override
  void paint(Canvas canvas, Size size) {
    final n = journeyStops.length;
    const y = 12.0;
    final dx = size.width / (n - 1);
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
          text: journeyStops[i].toUpperCase(),
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
  bool shouldRepaint(_RoutePainter old) => old.stop != stop;
}
