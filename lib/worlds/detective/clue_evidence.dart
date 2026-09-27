import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'clue_codepoint.dart' show CaseCharPicker;
import 'noir_kit.dart';

/// Clue 6: the forensic report. The real outlines of U+76F4 in Noto Sans JP
/// and Noto Sans SC (parsed from the font files): contour and point counts,
/// the strokes with no twin in the other font, and the overlay.
/// Poke: hover a contour, pick another exhibit.
class EvidenceClueSlide extends StatefulWidget {
  const EvidenceClueSlide({super.key});

  @override
  State<EvidenceClueSlide> createState() => _EvidenceClueSlideState();
}

const _panel = 400.0;
const _panelTop = 34.0;
double _panelX(int i) => i * (1472 - _panel) / 2;

class _EvidenceClueSlideState extends State<EvidenceClueSlide> {
  int _cp = caseCp;
  int? _hoverJP;
  int? _hoverSC;

  int? _hit(CaseFonts f, bool jp, Offset p) {
    final box = Rect.fromLTWH(0, 0, _panel, _panel).deflate(24);
    final o = f.outline(jp, _cp);
    for (var i = o.contours.length - 1; i >= 0; i--) {
      final path = emToBox(f.contour(jp, _cp, i), box);
      if (path.getBounds().inflate(4).contains(p) && path.contains(p)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'Forensic report',
      trailing: CaseCharPicker(selected: _cp, onChanged: (c) => setState(() => _cp = c)),
      child: CaseFontsBuilder(
        builder: (context, f) => LoopBuilder(
          period: const Duration(seconds: 5),
          builder: (context, t, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              for (final (i, jp) in [(0, true), (2, false)])
                Positioned(
                  left: _panelX(i),
                  top: _panelTop,
                  width: _panel,
                  height: _panel,
                  child: MouseRegion(
                    onHover: (e) => setState(() {
                      final h = _hit(f, jp, e.localPosition);
                      if (jp) {
                        _hoverJP = h;
                      } else {
                        _hoverSC = h;
                      }
                    }),
                    onExit: (_) => setState(() => jp ? _hoverJP = null : _hoverSC = null),
                    child: CustomPaint(
                      painter: _FormPainter(cp: _cp, jp: jp, t: t, hover: jp ? _hoverJP : _hoverSC),
                    ),
                  ),
                ),
              Positioned(
                left: _panelX(1),
                top: _panelTop,
                width: _panel,
                height: _panel,
                child: CustomPaint(painter: _OverlayPainter(cp: _cp, t: t)),
              ),
              for (final (i, jp) in [(0, true), (2, false)])
                Positioned(left: _panelX(i), top: _panelTop + _panel + 18, child: _Stats(f: f, cp: _cp, jp: jp, hover: jp ? _hoverJP : _hoverSC)),
              Positioned(
                left: _panelX(1),
                top: _panelTop + _panel + 18,
                width: _panel,
                child: Column(
                  children: [
                    Text('overlay · JP ⊕ SC', style: BT.mono(16, color: BP.red)),
                    const SizedBox(height: 8),
                    Text('same code point · ${hexOf(_cp)}', style: BT.mono(15, color: BP.inkDim)),
                    const SizedBox(height: 8),
                    Text('outlines: assets/fonts/*-case.ttf', style: BT.mono(12, color: BP.inkFaint)),
                  ],
                ),
              ),
              for (final (i, label, color) in [(0, 'Noto Sans JP', BP.line), (1, 'overlay', BP.red), (2, 'Noto Sans SC', BP.amber)])
                Positioned(
                  left: _panelX(i),
                  top: 0,
                  child: Text(label, style: BT.mono(15, color: color)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.f, required this.cp, required this.jp, required this.hover});

  final CaseFonts f;
  final int cp;
  final bool jp;
  final int? hover;

  @override
  Widget build(BuildContext context) {
    final o = f.outline(jp, cp);
    final odd = f.oddContours(jp, cp).where((b) => b).length;
    final c = jp ? BP.line : BP.amber;
    final h = hover;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('gid #${f.glyphId(jp, cp)}', style: BT.mono(15, color: BP.inkDim)),
        const SizedBox(height: 6),
        Row(
          children: [
            AnimatedCount(value: o.contours.length, style: BT.mono(26, color: c)),
            Text(' contours  ', style: BT.mono(15, color: BP.inkDim)),
            AnimatedCount(value: o.pointCount, style: BT.mono(26, color: c)),
            Text(' points', style: BT.mono(15, color: BP.inkDim)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          h == null ? 'no twin in the other font: $odd' : 'contour $h · ${o.contours[h].length} points',
          style: BT.mono(15, color: h == null ? BP.red : BP.amber),
        ),
      ],
    );
  }
}

class _FormPainter extends CustomPainter {
  _FormPainter({required this.cp, required this.jp, required this.t, required this.hover});

  final int cp;
  final bool jp;
  final double t;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final f = CaseFonts.ready;
    if (f == null) return;
    final frame = Offset.zero & size;
    canvas.drawRect(frame, Paint()..color = BP.panel);
    canvas.drawRect(frame, Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke);
    final box = frame.deflate(24);
    canvas.drawPath(dashPath(Path()..addRect(box), dash: 5, gap: 5), Paint()
      ..color = BP.lineFaint
      ..style = PaintingStyle.stroke);
    final c = jp ? BP.line : BP.amber;
    final o = f.outline(jp, cp);
    final odd = f.oddContours(jp, cp);
    final oddIdx = [for (var i = 0; i < odd.length; i++) if (odd[i]) i];
    final blink = oddIdx.isEmpty ? -1 : oddIdx[(t * oddIdx.length * 2).floor() % oddIdx.length];
    final glyph = emToBox(f.em(jp, cp), box);
    canvas.drawPath(glyph, Paint()..color = c.withValues(alpha: 0.22));
    for (var i = 0; i < o.contours.length; i++) {
      final hot = hover == i;
      final isOdd = odd[i];
      final p = emToBox(f.contour(jp, cp, i), box);
      if (hot || i == blink) {
        // The ink this contour contributes (holes stay holes).
        final ink = Path.combine(PathOperation.intersect, p, glyph);
        canvas.drawPath(ink, Paint()..color = (hot ? BP.ink : BP.red).withValues(alpha: hot ? 0.45 : 0.5));
      }
      canvas.drawPath(p, Paint()
        ..color = hot ? BP.ink : (isOdd ? BP.red : c)
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot || isOdd ? 2.2 : 1.5);
    }
    // Points: on-curve squares, off-curve circles.
    final s = box.width / 1000;
    for (var i = 0; i < o.contours.length; i++) {
      for (final p in o.contours[i]) {
        final q = Offset(box.left + p.x * s, box.top + (880 - p.y) * s);
        final col = hover == i ? BP.ink : c.withValues(alpha: 0.9);
        if (p.onCurve) {
          canvas.drawRect(Rect.fromCenter(center: q, width: 4.5, height: 4.5), Paint()..color = col);
        } else {
          canvas.drawCircle(q, 3, Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FormPainter old) => old.cp != cp || old.t != t || old.hover != hover;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.cp, required this.t});

  final int cp;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final f = CaseFonts.ready;
    if (f == null) return;
    final frame = Offset.zero & size;
    canvas.drawRect(frame, Paint()..color = BP.panel);
    canvas.drawRect(frame, Paint()
      ..color = BP.red.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke);
    final box = frame.deflate(24);
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 4);
    canvas.drawPath(emToBox(f.xor(cp), box), Paint()..color = BP.red.withValues(alpha: 0.25 + 0.35 * pulse));
    canvas.drawPath(emToBox(f.em(true, cp), box), Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    canvas.drawPath(dashPath(emToBox(f.em(false, cp), box), dash: 6, gap: 4), Paint()
      ..color = BP.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    // Scanner band.
    final y = frame.top + frame.height * seg(t, 0, 0.9);
    canvas.drawRect(
      Rect.fromLTWH(frame.left, y - 16, frame.width, 16),
      Paint()..color = BP.green.withValues(alpha: 0.08),
    );
    canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), Paint()
      ..color = BP.green.withValues(alpha: 0.7)
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.cp != cp || old.t != t;
}
