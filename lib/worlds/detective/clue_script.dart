import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Clue 2: script ≠ language. The itemizer stamps each run with its script
/// (Hani, Hira, Kana…); nothing in the text says "Japanese". The language
/// only arrives with the locale. Poke: type, switch the locale.
class ScriptClueSlide extends StatefulWidget {
  const ScriptClueSlide({super.key});

  @override
  State<ScriptClueSlide> createState() => _ScriptClueSlideState();
}

const _locales = [Locale('en', 'US'), Locale('ja'), Locale('zh', 'CN')];

String _tag(Locale l) => l.countryCode == null ? l.languageCode : '${l.languageCode}_${l.countryCode}';

/// ISO 15924 script code of a code point (the handful this slide needs).
String _iso(int c) {
  if (c == 0x30FC || c == 0x30FB || c == 0x30A0 || c == 0x309B || c == 0x309C) return 'Zyyy';
  if (c >= 0x3040 && c <= 0x309F) return 'Hira';
  if ((c >= 0x30A0 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF) || (c >= 0xFF66 && c <= 0xFF9D)) return 'Kana';
  if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x20000 && c <= 0x2FFFF) || c == 0x3005 || c == 0x3007) {
    return 'Hani';
  }
  if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0xC0 && c <= 0x24F)) return 'Latn';
  if ((c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F)) return 'Hang';
  if (c >= 0x0600 && c <= 0x06FF) return 'Arab';
  return 'Zyyy';
}

Color _colorOf(String iso) => switch (iso) {
  'Hani' => BP.green,
  'Hira' => const Color(0xFF9FF0D6),
  'Kana' => BP.violet,
  'Latn' => BP.line,
  'Hang' => const Color(0xFF7FE0FF),
  'Arab' => BP.amber,
  _ => BP.inkDim,
};

/// Languages that write with a script (only for the ones that are ambiguous).
List<String> _candidates(String iso) => switch (iso) {
  'Hani' => const ['ja', 'zh', 'ko'],
  'Latn' => const ['en', 'fr', 'de', '…'],
  _ => const ['?'],
};

class _Run {
  _Run(this.start, this.end, this.iso);

  final int start;
  int end;
  final String iso;
}

class _ScriptClueSlideState extends State<ScriptClueSlide> {
  final _ctrl = TextEditingController(text: '直したテキスト');
  final _labels = LabelCache();
  Locale _locale = _locales.first;
  TextProbe? _probe;
  String? _probeKey;

  @override
  void dispose() {
    _ctrl.dispose();
    _labels.dispose();
    _probe?.dispose();
    super.dispose();
  }

  TextProbe _probeFor(String text) {
    final key = '$text|${_tag(_locale)}';
    if (_probeKey != key) {
      _probe?.dispose();
      // Rendered with the chosen locale: fallback picks the face for it.
      _probe = TextProbe(TextSpan(text: text, style: BT.sample(104).copyWith(locale: _locale)));
      _probeKey = key;
    }
    return _probe!;
  }

  @override
  Widget build(BuildContext context) {
    final text = _ctrl.text.isEmpty ? ' ' : _ctrl.text;
    final probe = _probeFor(text);
    return SlideFrame(
      title: 'Script ≠ language',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('locale', style: BT.mono(14, color: BP.inkDim)),
          const SizedBox(width: 12),
          BpSegmented<Locale>(
            values: _locales,
            selected: _locale,
            labelOf: _tag,
            color: BP.amber,
            onChanged: (l) => setState(() => _locale = l),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('text', style: BT.mono(16, color: BP.inkDim)),
                const SizedBox(width: 16),
                BpTextField(
                  controller: _ctrl,
                  width: 420,
                  style: NT.jp(30),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          Positioned.fill(
            top: 90,
            child: LoopBuilder(
              period: const Duration(seconds: 6),
              builder: (context, t, _) => CustomPaint(
                painter: _ItemizePainter(probe: probe, t: t, locale: _locale, labels: _labels),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemizePainter extends CustomPainter {
  _ItemizePainter({required this.probe, required this.t, required this.locale, required this.labels});

  final TextProbe probe;
  final double t;
  final Locale locale;
  final LabelCache labels;

  @override
  void paint(Canvas canvas, Size size) {
    final text = probe.text;
    // Itemize: one script per code point; Common joins its neighbour.
    final runs = <_Run>[];
    final cells = <(int, int, String)>[];
    var i = 0;
    for (final r in text.runes) {
      final len = r > 0xFFFF ? 2 : 1;
      final iso = _iso(r);
      cells.add((i, i + len, iso));
      if (iso == 'Zyyy' && runs.isNotEmpty) {
        runs.last.end = i + len;
      } else if (runs.isNotEmpty && (runs.last.iso == iso || runs.last.iso == 'Zyyy')) {
        if (runs.last.iso == 'Zyyy') {
          runs[runs.length - 1] = _Run(runs.last.start, i + len, iso);
        } else {
          runs.last.end = i + len;
        }
      } else {
        runs.add(_Run(i, i + len, iso));
      }
      i += len;
    }

    const left = 150.0;
    final origin = Offset(left, 10);
    final scanX = left + seg(t, 0.05, 0.45) * (probe.size.width + 40) - 20;

    // Row labels.
    for (final (y, s) in [(220.0, 'script'), (300.0, 'run'), (384.0, 'language')]) {
      final tp = labels.get(s, BT.mono(14, color: BP.inkFaint));
      tp.paint(canvas, Offset(0, y));
    }

    // Per code point: a dashed cell tinted by its script once scanned.
    for (final (s, e, iso) in cells) {
      final rect = probe.rectFor(s, e);
      if (rect == null) continue;
      final r = rect.shift(origin);
      final lit = scanX > r.center.dx;
      final c = _colorOf(iso);
      if (lit) canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.08));
      canvas.drawPath(
        dashPath(Path()..addRect(r), dash: 4, gap: 4),
        Paint()
          ..color = lit ? c.withValues(alpha: 0.8) : BP.lineFaint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final code = labels.get(iso, BT.mono(13, color: lit ? c : BP.inkFaint));
      code.paint(canvas, Offset(r.center.dx - code.width / 2, 220));
    }
    probe.paint(canvas, origin);

    // Scanner.
    if (scanX < left + probe.size.width + 20) {
      canvas.drawLine(Offset(scanX, 0), Offset(scanX, 250), Paint()
        ..color = BP.amber.withValues(alpha: 0.8)
        ..strokeWidth = 2);
    }

    // Runs: brackets + script stamp + an empty "language" slot.
    final arrive = seg(t, 0.55, 0.75);
    for (final run in runs) {
      final rect = probe.rectFor(run.start, run.end);
      if (rect == null) continue;
      final r = rect.shift(origin);
      final done = scanX > r.right;
      final c = _colorOf(run.iso);
      final y = 288.0;
      final br = Paint()
        ..color = done ? c : BP.lineFaint
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(
        Path()
          ..moveTo(r.left + 3, y - 8)
          ..lineTo(r.left + 3, y)
          ..lineTo(r.right - 3, y)
          ..lineTo(r.right - 3, y - 8),
        br,
      );
      final stamp = labels.get(run.iso, BT.mono(20, color: done ? c : BP.inkFaint, weight: 600));
      stamp.paint(canvas, Offset(r.center.dx - stamp.width / 2, y + 8));

      // Language slot: "?" until the locale arrives from above.
      final slot = Rect.fromCenter(center: Offset(r.center.dx, 396), width: math.max(56, r.width - 16), height: 36);
      canvas.drawRect(slot, Paint()..color = BP.paper);
      canvas.drawPath(dashPath(Path()..addRect(slot), dash: 5, gap: 4), Paint()
        ..color = arrive > 0.5 ? BP.amber : BP.lineDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
      final q = labels.get(arrive > 0.5 ? locale.languageCode : '?', BT.mono(18, color: arrive > 0.5 ? BP.amber : BP.inkDim));
      q.paint(canvas, Offset(slot.center.dx - q.width / 2, slot.center.dy - q.height / 2));
      // The locale drops in from the top.
      if (arrive > 0 && arrive < 1) {
        final y0 = -80.0;
        final yy = y0 + (slot.top - y0) * arrive;
        canvas.drawCircle(Offset(slot.center.dx, yy), 5, Paint()..color = BP.amber);
      }
    }

    // Side panel: what a script alone can tell you.
    final px = math.max(left + probe.size.width + 80, 1000.0);
    final hani = runs.any((r) => r.iso == 'Hani');
    final iso = hani ? 'Hani' : (runs.isEmpty ? 'Zyyy' : runs.first.iso);
    final head = labels.get('$iso →', BT.mono(22, color: _colorOf(iso)));
    head.paint(canvas, Offset(px, 40));
    var x = px + head.width + 16;
    final wob = math.sin(t * math.pi * 4) * 3;
    for (final lang in _candidates(iso)) {
      final tp = labels.get(lang, BT.mono(20, color: BP.ink));
      final r = Rect.fromLTWH(x, 36 + wob, tp.width + 20, 34);
      canvas.drawRect(r, Paint()..color = BP.amber.withValues(alpha: 0.1));
      canvas.drawRect(r, Paint()
        ..color = BP.amber.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke);
      tp.paint(canvas, Offset(r.left + 10, r.top + 5));
      x = r.right + 10;
    }
    final big = labels.get('?', BT.display(150, color: BP.amber, height: 1));
    big.paint(canvas, Offset(px + 20, 96));
    final note = labels.get('language ← locale', BT.mono(16, color: BP.amber));
    note.paint(canvas, Offset(px, 270));
    final loc = labels.get("TextStyle(locale: ${_code(locale)})", BT.mono(15, color: BP.inkDim));
    loc.paint(canvas, Offset(px, 300));
  }

  String _code(Locale l) =>
      l.countryCode == null ? "Locale('${l.languageCode}')" : "Locale('${l.languageCode}', '${l.countryCode}')";

  @override
  bool shouldRepaint(_ItemizePainter old) => old.t != t || old.probe != probe || old.locale != locale;
}
