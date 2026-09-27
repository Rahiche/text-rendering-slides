import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:slug/slug.dart';

/// `?probe=slug&…`: renders Flutter `Text` and `SlugText` side by side under
/// the same transform, for compare/index.html to embed next to Chrome's text
/// under the equivalent CSS transform.
///
/// Params (all optional): w, h (viewport px), size (font px), scale, rx, ry
/// (degrees), persp (px, 0 = none), ox, oy (transform origin in the text's
/// own coordinates), x0, y0 (where the text sits in the viewport), gap,
/// text, font (latin|jp), base (Chrome's baseline to align to), anim.
class SlugProbeApp extends StatelessWidget {
  const SlugProbeApp({super.key});

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(),
      child: ColoredBox(color: Colors.white, child: _Probe()),
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  SlugFont? _sg;
  SlugFont? _jp;

  static final _q = Uri.base.queryParameters;
  static double _p(String k, double d) => double.tryParse(_q[k] ?? '') ?? d;

  Ticker? _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    if (_q['anim'] == '1') {
      _ticker = createTicker((d) => setState(() => _t = d.inMicroseconds / 4e6))..start();
    }
    Future.wait([
      SlugFont.load('assets/fonts/SpaceGrotesk.ttf'),
      SlugFont.load('assets/fonts/NotoSansJP-case.ttf'),
    ]).then((f) {
      if (!mounted) return;
      setState(() {
        _sg = f[0];
        _jp = f[1];
      });
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// perspective() rotateX() rotateY() scale(), multiplied in CSS order.
  Matrix4 get _matrix {
    final m = Matrix4.identity();
    final d = _p('persp', 0);
    if (d > 0) m.setEntry(3, 2, -1 / d);
    m.rotateX(_p('rx', 0) * math.pi / 180);
    m.rotateY(_p('ry', 0) * math.pi / 180);
    var s = _p('scale', 1);
    // Same easing as the CSS keyframes: 1 → scale → 1 every 4 s.
    if (_ticker != null) s = 1 + (s - 1) * (0.5 - 0.5 * math.cos(2 * math.pi * _t));
    m.scaleByDouble(s, s, 1, 1);
    return m;
  }

  Widget _viewport(Widget subject, double dy) {
    return SizedBox(
      width: _p('w', 560),
      height: _p('h', 300),
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _p('x0', 0),
              top: _p('y0', 0) + dy,
              child: Transform(
                transform: _matrix,
                // Same pivot in viewport space as the CSS side.
                origin: Offset(_p('ox', 0), _p('oy', 0) - dy),
                child: subject,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sg = _sg, jp = _jp;
    if (sg == null || jp == null) return const SizedBox();
    final size = _p('size', 48);
    // Pin the variable font to its default instance: that's what the glyf
    // outlines Slug reads describe (Space Grotesk: wght 300).
    final latin = TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: size,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even, // CSS half-leading
      color: const Color(0xFF111111),
      fontVariations: [for (final e in sg.defaultAxes.entries) ui.FontVariation(e.key, e.value)],
    );
    final cjk = TextStyle(
      fontFamily: 'CaseJP',
      fontSize: size,
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
      color: const Color(0xFF111111),
    );
    // One font per subject (text=…, font=latin|jp), so both engines use the
    // same line metrics and the crops line up with the CSS side.
    final text = _q['text'] ?? '直';
    final jpFont = _q['font'] == 'jp';
    final style = jpFont ? cjk : latin;
    // `base` = Chrome's measured baseline (px from the box top). Chrome snaps
    // its line metrics to whole pixels, so shift ours to sit on the same line.
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final ours = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.dispose();
    final dy = _p('base', ours) - ours;
    return Align(
      alignment: Alignment.topLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _viewport(Text(text, style: style), dy),
          SizedBox(width: _p('gap', 18)),
          _viewport(SlugText([SlugSpan(text, font: jpFont ? jp : sg, style: style)]), dy),
        ],
      ),
    );
  }
}
