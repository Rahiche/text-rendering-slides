import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'noir_kit.dart';

/// Clue 3: the suspect. Our fonts don't cover U+76F4, so the paragraph asks
/// the platform font manager for a fallback — passing the text's locale.
/// Which CJK face comes back depends on that locale. Poke: en ↔ ja ↔ zh.
class FallbackClueSlide extends StatefulWidget {
  const FallbackClueSlide({super.key});

  @override
  State<FallbackClueSlide> createState() => _FallbackClueSlideState();
}

const _fbLocales = ['en-US', 'ja', 'zh-CN'];

// Drawers of the (illustrative) language-tagged CJK fallback faces.
const _drawers = [
  ('CJK JP', 'ja'),
  ('CJK SC', 'zh-Hans'),
  ('CJK TC', 'zh-Hant'),
  ('CJK KR', 'ko'),
];

class _FallbackClueSlideState extends State<FallbackClueSlide> {
  String _locale = 'en-US';
  final _labels = LabelCache();

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideFrame(
      title: 'The suspect: fallback',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('locale', style: BT.mono(14, color: BP.inkDim)),
          const SizedBox(width: 12),
          BpSegmented<String>(
            values: _fbLocales,
            selected: _locale,
            color: BP.amber,
            onChanged: (v) => setState(() => _locale = v),
          ),
        ],
      ),
      child: LoopBuilder(
        period: const Duration(milliseconds: 4200),
        builder: (context, t, _) => CustomPaint(
          painter: _FallbackPainter(t: t, locale: _locale, labels: _labels, clock: noirSeconds),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _FallbackPainter extends CustomPainter {
  _FallbackPainter({required this.t, required this.locale, required this.labels, required this.clock});

  final double t;
  final String locale;
  final LabelCache labels;
  final double clock;

  static const _para = Rect.fromLTWH(0, 150, 300, 300);
  static const _cab = Rect.fromLTWH(1010, 40, 460, 520);

  int? get _match => switch (locale) {
    'ja' => 0,
    'zh-CN' => 1,
    _ => null,
  };

  /// For en_US nothing says "Japanese": the answer depends on the platform.
  bool get _jpResult => _match == 0 || (_match == null && (clock * 1.6).floor().isEven);

  void _text(Canvas canvas, String s, TextStyle st, Offset at, {bool center = false}) {
    final tp = labels.get(s, st);
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dim = Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // The paragraph, with a gap where the glyph should be.
    canvas.drawRect(_para, Paint()..color = BP.panel);
    canvas.drawRect(_para, ink);
    _text(canvas, 'SkParagraph', BT.mono(15, color: BP.line), _para.topLeft + const Offset(0, -26));
    _text(canvas, 'Space Grotesk  ✕', BT.mono(14, color: BP.red), _para.bottomLeft + const Offset(0, 14));
    _text(canvas, 'Noto Kufi Arabic  ✕', BT.mono(14, color: BP.red), _para.bottomLeft + const Offset(0, 38));
    _text(canvas, '→ ask the platform', BT.mono(14, color: BP.amber), _para.bottomLeft + const Offset(0, 66));
    final slot = Rect.fromCenter(center: _para.center, width: 200, height: 200);
    final back = seg(t, 0.62, 0.86);
    final landed = t >= 0.86;
    if (!landed) {
      canvas.drawPath(dashPath(Path()..addRect(slot), dash: 6, gap: 5), dim);
      _text(canvas, hexOf(caseCp), BT.mono(18, color: BP.inkDim), slot.center, center: true);
    }

    // The request slip travels right; the glyph travels back.
    final y = _para.center.dy;
    canvas.drawPath(dashPath(Path()
      ..moveTo(_para.right + 10, y)
      ..lineTo(_cab.left - 10, y), dash: 8, gap: 6), dim);
    final go = seg(t, 0.02, 0.32);
    if (go > 0 && go < 1) {
      final x = _para.right + 20 + (_cab.left - _para.right - 320) * go;
      final r = Rect.fromLTWH(x, y - 58, 300, 116);
      canvas.drawRect(r, Paint()..color = BP.paper);
      canvas.drawRect(r, Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      _text(canvas, 'fallback for', BT.mono(13, color: BP.inkDim), r.topLeft + const Offset(14, 12));
      _text(canvas, '${hexOf(caseCp)}  直', NT.jp(22, color: BP.ink), r.topLeft + const Offset(14, 34));
      _text(canvas, 'locale: $locale', BT.mono(18, color: BP.amber), r.topLeft + const Offset(14, 76));
    } else {
      _text(canvas, 'U+76F4 · locale: $locale', BT.mono(16, color: BP.amber),
          Offset((_para.right + _cab.left) / 2, y - 30), center: true);
    }
    // The real call SkParagraph makes (Skia's font manager API).
    final mx = _para.right + 60;
    _text(canvas, 'SkFontMgr::matchFamilyStyleCharacter(', BT.mono(16, color: BP.inkDim), Offset(mx, 40));
    _text(canvas, '  …, bcp47: ["$locale"], U+76F4)', BT.mono(16, color: BP.inkDim), Offset(mx, 66));
    final hi = labels.get('"$locale"', BT.mono(16, color: BP.amber));
    final pre = labels.get('  …, bcp47: [', BT.mono(16, color: BP.inkDim));
    hi.paint(canvas, Offset(mx + pre.width, 66));

    // The cabinet: language-tagged CJK faces.
    canvas.drawRect(_cab, Paint()..color = BP.panel);
    canvas.drawRect(_cab, ink);
    _text(canvas, 'platform font manager', BT.mono(15, color: BP.line), _cab.topLeft + const Offset(0, -26));
    final scan = seg(t, 0.32, 0.58);
    final match = _match;
    const dh = 104.0;
    for (var i = 0; i < _drawers.length; i++) {
      final (name, lang) = _drawers[i];
      final top = _cab.top + 30 + i * (dh + 16);
      final checking = scan > 0 && scan < 1 && (scan * _drawers.length).floor() == i;
      final isMatch = match == i && scan >= (i + 0.5) / _drawers.length;
      final open = isMatch ? segOut(t, 0.4 + i * 0.05, 0.55 + i * 0.05) * (1 - seg(t, 0.92, 1.0)) : 0.0;
      final r = Rect.fromLTWH(_cab.left + 24 - 60 * open, top, _cab.width - 48, dh);
      canvas.drawRect(r, Paint()..color = isMatch ? BP.amber.withValues(alpha: 0.12) : BP.paper);
      canvas.drawRect(r, Paint()
        ..color = isMatch ? BP.amber : (checking ? BP.line : BP.lineDim)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isMatch || checking ? 2 : 1);
      // Handle.
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(r.left + 40, r.center.dy), width: 36, height: 10), const Radius.circular(5)), dim);
      _text(canvas, name, BT.mono(18, color: BP.ink), Offset(r.left + 78, r.top + 24));
      final tag = labels.get(lang, BT.mono(14, color: isMatch ? BP.amber : BP.inkDim));
      final tr = Rect.fromLTWH(r.left + 78, r.top + 58, tag.width + 30, tag.height + 6);
      paintTag(canvas, tr, color: isMatch ? BP.amber : BP.inkDim);
      tag.paint(canvas, Offset(tr.left + 22, tr.top + 3));
      if (i < 2) {
        final g = labels.get('直', i == 0 ? NT.caseJP(64, color: BP.line) : NT.caseSC(64, color: BP.amber));
        g.paint(canvas, Offset(r.right - 96, r.center.dy - g.height / 2));
      } else {
        _text(canvas, 'not in demo', BT.mono(12, color: BP.inkFaint), Offset(r.right - 118, r.center.dy - 8));
      }
      if (match == null && checking) {
        _text(canvas, 'lang?', BT.mono(14, color: BP.red), Offset(r.right - 200, r.top + 10));
      }
    }

    // The glyph flies back into the paragraph.
    final jp = _jpResult;
    final g = labels.get('直', jp ? NT.caseJP(180, color: BP.line) : NT.caseSC(180, color: BP.amber));
    if (back > 0 || landed) {
      final from = Offset(_cab.left + 10, _cab.top + 90);
      final to = slot.center;
      final p = landed ? to : Offset.lerp(from, to, back)! + Offset(0, -math.sin(back * math.pi) * 60);
      final s = landed ? 1.0 : 0.4 + 0.6 * back;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.scale(s);
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
    }
    if (landed || back > 0.9) {
      final label = match == null ? '? depends on platform' : (jp ? 'JP form' : 'SC form');
      _text(canvas, label, BT.mono(15, color: match == null ? BP.red : (jp ? BP.line : BP.amber)),
          _para.topRight + const Offset(24, 8));
    }
    _text(canvas, 'demo: Noto Sans JP / SC', BT.mono(12, color: BP.inkFaint), _cab.bottomLeft + const Offset(0, 14));
  }

  @override
  bool shouldRepaint(_FallbackPainter old) => true;
}
