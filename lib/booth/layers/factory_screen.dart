part of 'factory_draw.dart';

/// The lesson screen above the line: the pipeline step by step while a name
/// comes in (its code points, runs, fonts, glyphs, pixels), replayed during
/// the build, then done / demolition / recycling.
extension _Screen on _Frame {
  void screen() {
    final r = FG.screen;
    box(r, col: BP.line, w: 1.6, fill: _screenFill);
    final inner = r.deflate(6);
    c.drawRect(inner, st(BP.lineFaint, 1));
    final jj = j, dd = d;
    c.save();
    c.clipRect(inner);
    if (jj == null || dd == null) {
      _center(tx.get('グリフ工場 · ready', FS.m16dim, key: 'm16d'), inner);
    } else {
      switch (jj.phase) {
        case Phase.intake:
          if (s < FL.landed) {
            _arrive(inner, dd, s / FL.landed);
          } else {
            _lessonStep(inner, dd, step < 0 ? 4 : step, live: true);
          }
        case Phase.build:
          _lessonStep(inner, dd, step < 0 ? 4 : step, live: s < FL.arrive(4) + 0.6);
          _progress(inner, jj);
        case Phase.reveal || Phase.celebrate:
          _done(inner, dd, jj);
        case Phase.demolish:
          _demolish(inner, dd, jj);
        case Phase.cleanup:
          _recycle(inner, dd, jj);
      }
    }
    c.restore();
  }

  void _center(TextPainter p, Rect r) => p.paint(c, Offset(r.center.dx - p.width / 2, r.center.dy - p.height / 2));

  /// The name at [size] in [col], scaled to fit [maxW]; returns its rect.
  (TextPainter, Rect, double) _name(JobData dd, Offset at, double maxW, {Color col = BP.ink, String key = 'n24', double size = 24}) {
    final p = tx.get(dd.name, FS.name(size, col), key: key);
    final k = math.min(1.0, maxW / math.max(1, p.width));
    final rect = Rect.fromLTWH(at.dx, at.dy, p.width * k, p.height * k);
    if (k < 1) {
      c.save();
      c.translate(at.dx, at.dy);
      c.scale(k);
      p.paint(c, Offset.zero);
      c.restore();
    } else {
      p.paint(c, at);
    }
    return (p, rect, k);
  }

  List<Rect> _boxes(JobData dd, TextPainter p, double size) => dd.boxes[size] ??= [
    for (final g in dd.graphemes)
      () {
        final bs = p.getBoxesForSelection(TextSelection(baseOffset: g.start, extentOffset: g.end));
        if (bs.isEmpty) return Rect.zero;
        return bs.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b));
      }(),
  ];

  void _arrive(Rect r, JobData dd, double a) {
    final tag = tx.get('▸ new name · 新しい名前', FS.m16amber, key: 'm16a');
    if ((t * 4).floor().isEven || a > 0.6) tag.paint(c, Offset(r.left + 6, r.top + 4));
    // The name types in.
    final n = dd.graphemes.length;
    final shown = (a * 1.4 * n).floor().clamp(0, n);
    final at = Offset(r.left + 6, r.top + 30);
    final (p, rect, k) = _name(dd, at, r.width - 12);
    if (shown < n) {
      // Hide the rest (paint over it with the screen colour).
      final bx = _boxes(dd, p, 24);
      final x = shown == 0 ? 0.0 : bx[shown - 1].right;
      c.drawRect(Rect.fromLTRB(rect.left + x * k, rect.top - 2, r.right, rect.bottom + 2), fl(_screenFill));
      c.drawRect(Rect.fromLTWH(rect.left + x * k + 1, rect.top + 4, 2.5, rect.height - 8), fl(BP.amber));
    }
  }

  void _lessonStep(Rect r, JobData dd, int k, {required bool live}) {
    final jj = j!;
    final ls = s;
    final head = Offset(r.left + 6, r.top + 1);
    final maxW = r.width - 12;
    final detail = Rect.fromLTRB(r.left + 6, r.top + 36, r.right - 6, r.bottom - 4);
    switch (k) {
      case 0: // read: each code point under its character
        final n = dd.cps.length;
        final f = live ? c01((ls - FL.landed) / (FL.readEnd - FL.landed)) * n : -1.0;
        _cpColumns(r, dd, f);
      case 1: // itemize: runs
        final p = tx.span(('runs', dd.job.serial), () => TextSpan(
          children: [
            for (final run in dd.runs) TextSpan(text: run.text, style: FS.name(24, run.script.color)),
          ],
        ));
        final kk = math.min(1.0, maxW / math.max(1, p.width));
        c.save();
        c.translate(head.dx, head.dy);
        c.scale(kk);
        p.paint(c, Offset.zero);
        c.restore();
        // Underline each run.
        final bx = _boxes(dd, tx.get(dd.name, FS.name(24, BP.ink), key: 'n24'), 24);
        for (final run in dd.runs) {
          Rect? u;
          for (var i = 0; i < dd.graphemes.length; i++) {
            final g = dd.graphemes[i];
            if (g.start >= run.start && g.start < run.end && !g.space) u = u == null ? bx[i] : u.expandToInclude(bx[i]);
          }
          if (u == null) continue;
          final y = head.dy + u.bottom * kk + 1;
          c.drawLine(Offset(head.dx + u.left * kk + 1, y), Offset(head.dx + u.right * kk - 1, y), st(run.script.color, 2.4));
        }
        final label = dd.runs.length == 1 ? '1 run · ' : '${dd.runs.length} runs · ';
        final spans = <InlineSpan>[TextSpan(text: label, style: FS.m16dim)];
        for (var i = 0; i < dd.runs.length; i++) {
          if (i > 0) spans.add(TextSpan(text: ' + ', style: FS.m16dim));
          spans.add(TextSpan(text: dd.runs[i].script.label, style: BT.mono(16, color: dd.runs[i].script.color, weight: 600)));
        }
        _fit(tx.span(('runsLabel', dd.job.serial), () => TextSpan(children: spans)), detail);
      case 2: // fonts
        final (p, rect, ks) = _name(dd, head, maxW);
        // Full font names when they fit at 16 px, short ones when there are
        // several.
        TextPainter fonts(bool short) => tx.span(('fonts', dd.job.serial, short), () {
          final spans = <InlineSpan>[TextSpan(text: '→ ', style: FS.m16dim)];
          for (var i = 0; i < dd.fonts.length; i++) {
            if (i > 0) spans.add(TextSpan(text: ' + ', style: FS.m16dim));
            final f = dd.fonts[i];
            spans.add(TextSpan(text: short ? _fontShort(f.font) : f.font, style: BT.mono(16, color: f.script.color, weight: 600)));
          }
          return TextSpan(children: spans);
        });
        final full = fonts(false);
        _fit(full.width <= detail.width ? full : fonts(true), detail);
        // Each run's glyphs get their font's colour tick.
        final bx = _boxes(dd, p, 24);
        for (var i = 0; i < dd.graphemes.length; i++) {
          final g = dd.graphemes[i];
          if (g.space) continue;
          final b = bx[i];
          c.drawRect(Rect.fromLTRB(rect.left + b.left * ks + 2, rect.top + b.bottom * ks, rect.left + b.right * ks - 2, rect.top + b.bottom * ks + 2), fl(g.script.color.withValues(alpha: 0.7)));
        }
      case 3: // shape: glyphs placed
        final (p, rect, ks) = _name(dd, head, maxW);
        final bx = _boxes(dd, p, 24);
        final a = live ? c01((ls - FL.leave[2] - FL.mv / 2) / (FL.leave[3] - FL.leave[2]) * 1.6) : 1.0;
        final shownN = (bx.length * a).ceil();
        final xs = <String>[];
        for (var i = 0; i < bx.length && i < shownN; i++) {
          final b = bx[i];
          if (dd.graphemes[i].space) continue;
          final hb = Rect.fromLTRB(rect.left + b.left * ks, rect.top + b.top * ks + 3, rect.left + b.right * ks, rect.top + b.bottom * ks - 2);
          c.drawRect(hb, st(BP.amber.withValues(alpha: 0.8), 1));
          c.drawLine(Offset(hb.left, hb.bottom), Offset(hb.left, hb.bottom + 4), st(BP.amber, 1));
          xs.add(b.left.round().toString());
        }
        final glyphs = dd.graphemes.where((g) => !g.space).length;
        var text = '$glyphs glyphs · x ${xs.join(' ')}';
        final maxChars = (detail.width / 9.6).floor();
        if (text.length > maxChars) text = '${text.substring(0, maxChars - 1)}…';
        tx.get(text, FS.m16, key: 'm16').paint(c, detail.topLeft);
      default: // raster
        final dots = dd.dots;
        if (dots == null) {
          _name(dd, head, maxW);
          break;
        }
        final area = Rect.fromLTRB(r.left + 6, r.top + 4, r.right - 6, r.top + 44);
        final kk = math.min(3.0, math.min(area.width / dots.cols, area.height / dots.rows));
        final o = Offset(area.left, area.center.dy - dots.rows * kk / 2);
        final dev = live ? c01((ls - FL.leave[3] - FL.mv / 2) / (FL.end - 0.2 - FL.leave[3] - FL.mv / 2)) : 1.0;
        c.save();
        c.clipRect(Rect.fromLTRB(o.dx - 1, o.dy + dots.rows * kk * (1 - dev) - 1, o.dx + dots.cols * kk + 1, o.dy + dots.rows * kk + 1));
        c.translate(o.dx, o.dy);
        c.scale(kk);
        final paint = Paint()
          ..strokeWidth = kk >= 2 ? 0.86 : 1
          ..strokeCap = StrokeCap.square;
        for (var l = 0; l < RasterDots.levels; l++) {
          paint.color = brickColor(RasterDots.coverOf(l));
          c.drawRawPoints(ui.PointMode.points, dots.xy[l], paint);
        }
        c.restore();
        if (dev < 1) {
          final y = o.dy + dots.rows * kk * (1 - dev);
          c.drawLine(Offset(o.dx - 2, y), Offset(o.dx + dots.cols * kk + 2, y), st(BP.amber, 1.2));
        }
        final rr = jj.raster!;
        final text = '${rr.fontSize.round()}px → ${dots.cols}×${dots.rows} px · ${jj.total} bricks';
        _fit(tx.get(text, FS.m16, key: 'm16'), Rect.fromLTRB(detail.left, detail.top + 6, detail.right, detail.bottom + 4));
    }
  }

  /// Paints [p] left-aligned in [r], shrunk to fit its width.
  void _fit(TextPainter p, Rect r) {
    final k = math.min(1.0, r.width / math.max(1, p.width));
    c.save();
    c.translate(r.left, r.top);
    c.scale(k);
    p.paint(c, Offset.zero);
    c.restore();
  }

  /// The name spelled out in columns, each character over its code point
  /// ("田" over "U+7530"). Live, they appear as the hopper reads them (the
  /// current one lit and kept in view); otherwise all of them, scrolling by
  /// when they don't fit.
  void _cpColumns(Rect r, JobData dd, double f) {
    final n = dd.cps.length;
    final live = f >= 0;
    final cur = live ? f.floor().clamp(0, n - 1) : -1;
    final count = live ? cur + 1 : n;
    const gap = 14.0;
    final chars = <TextPainter>[], hexes = <TextPainter>[];
    final xs = <double>[], ws = <double>[];
    var x = 0.0;
    for (var k = 0; k < n; k++) {
      final hot = k == cur;
      final cp = dd.cps[k];
      chars.add(tx.get(cp.shown, FS.name(26, hot ? BP.amber : BP.ink), key: hot ? 'c26a' : 'c26'));
      hexes.add(tx.get(cp.hex, hot ? FS.m16amber : FS.m16dim, key: hot ? 'h16a' : 'h16'));
      final w = math.max(chars[k].width, hexes[k].width);
      xs.add(x);
      ws.add(w);
      x += w + gap;
    }
    final total = x - gap;
    final inner = r.deflate(3);
    double scroll;
    var reps = 1;
    if (total <= inner.width) {
      scroll = -(inner.width - total) / 2;
    } else if (live) {
      // Keep the current column in view; just before the next one is read,
      // slide over to open its slot.
      double need(int k) => math.max(0, xs[k] + ws[k] + 6 - inner.width);
      final fr = (f - cur).clamp(0.0, 1.0);
      scroll = lerp(need(cur), need(math.min(n - 1, cur + 1)), eio(seg(fr, 0.65, 1)));
    } else {
      scroll = (t * 24) % (total + 48);
      reps = 2;
    }
    for (var rep = 0; rep < reps; rep++) {
      for (var k = 0; k < count; k++) {
        final cx = inner.left + xs[k] - scroll + rep * (total + 48) + ws[k] / 2;
        if (cx - ws[k] / 2 > inner.right || cx + ws[k] / 2 < inner.left) continue;
        final ch = chars[k], hx = hexes[k];
        if (k == cur) {
          final box = Rect.fromLTRB(cx - ws[k] / 2 - 5, inner.top, cx + ws[k] / 2 + 5, inner.bottom);
          c.drawRect(box, fl(BP.amber.withValues(alpha: 0.10)));
          c.drawRect(box, st(BP.amber, 1));
        }
        ch.paint(c, Offset(cx - ch.width / 2, inner.top + 2));
        hx.paint(c, Offset(cx - hx.width / 2, inner.bottom - hx.height));
      }
    }
    if (total > inner.width) {
      // Columns slide in and out of soft edges (only where they run past).
      final shownRight = reps > 1 ? double.infinity : xs[count - 1] + ws[count - 1] - scroll;
      final (leftFade, rightFade) = (_screenFades[0], _screenFades[1]);
      if (reps > 1 || scroll > 1) c.drawRect(leftFade.$1, leftFade.$2);
      if (shownRight > inner.width + 1) c.drawRect(rightFade.$1, rightFade.$2);
    }
  }

  void _progress(Rect r, Job jj) {
    final laid = jj.laid(t);
    final frac = jj.total == 0 ? 0.0 : laid / jj.total;
    final y = r.bottom - 1;
    c.drawLine(Offset(r.left, y), Offset(r.right, y), st(BP.lineFaint, 2));
    c.drawLine(Offset(r.left, y), Offset(r.left + r.width * frac, y), st(BP.amber, 2));
  }

  void _done(Rect r, JobData dd, Job jj) {
    final (_, rect, _) = _name(dd, Offset(r.left + 6, r.top + 2), r.width - 12, col: BP.amber, key: 'n24a');
    final spans = TextSpan(children: [
      TextSpan(text: '完成 · done!  ', style: FS.name(17, BP.green)),
      TextSpan(text: '${jj.total} bricks', style: FS.m16),
    ]);
    final p = tx.span(('done', jj.total), () => spans);
    p.paint(c, Offset(r.left + 26, r.top + 40));
    // A tick, drawn.
    final o = Offset(r.left + 12, r.top + 51);
    c.drawPath(
      Path()
        ..moveTo(o.dx - 5, o.dy)
        ..lineTo(o.dx - 1, o.dy + 4)
        ..lineTo(o.dx + 6, o.dy - 5),
      st(BP.green, 2),
    );
    for (var i = 0; i < 4; i++) {
      final q = (t * 0.8 + i * 0.25) % 1;
      final sx = rect.left + rect.width * rnd(i, (t * 0.8 + i * 0.25).floor(), 9);
      star(Offset(sx, rect.top + 4 + 20 * rnd(i, (t * 0.8).floor(), 10)), 3 + 4 * bump(q), BP.amber.withValues(alpha: bump(q)));
    }
  }

  void _demolish(Rect r, JobData dd, Job jj) {
    _name(dd, Offset(r.left + 6, r.top + 2), r.width - 12, col: BP.inkDim, key: 'n24d');
    final blink = (t * 2.5).floor().isEven;
    final p = tx.get('解体中 · demolition', FS.name(17, blink ? BP.amber : BP.red), key: blink ? 'dem1' : 'dem0');
    p.paint(c, Offset(r.left + 6, r.top + 40));
    // Hazard stripes along the right.
    final stripes = Path();
    for (var y = r.top - 12.0 + (t * 20) % 12; y < r.bottom; y += 12) {
      stripes
        ..moveTo(r.right - 30, y + 12)
        ..lineTo(r.right - 18, y);
    }
    c.save();
    c.clipRect(Rect.fromLTRB(r.right - 30, r.top, r.right, r.bottom));
    c.drawPath(stripes, st(BP.amber.withValues(alpha: 0.6), 4));
    c.restore();
  }

  void _recycle(Rect r, JobData dd, Job jj) {
    final head = tx.get('リサイクル · recycling', FS.name(20, BP.green), key: 'rec');
    head.paint(c, Offset(r.left + 30, r.top + 2));
    recycleMark(this, Offset(r.left + 14, r.top + 15), 8, BP.green);
    final n = jj.cutAt ?? jj.total;
    final p = tx.get('$n bricks → raw pixels', FS.m16, key: 'm16');
    p.paint(c, Offset(r.left + 6, r.top + 40));
  }
}
