import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'detective_chapters.dart';
import 'noir_kit.dart';

const _scene = Rect.fromLTRB(600, 40, 1540, 580);

// ─────────────────────────────────────────────────────────────────────────────
// 01 · the scene: 直's chalk outline on the floor, police tape, markers, and
// the detective crouching with a torch (it follows the pointer).
// ─────────────────────────────────────────────────────────────────────────────

class CrimeScene extends ChapterScene {
  Path? _chalk;
  double _flashAt = -9;

  Path? _outline() {
    if (_chalk != null) return _chalk;
    final f = CaseFonts.ready;
    if (f == null) return null;
    final em = emToBox(f.em(true, caseCp), const Rect.fromLTWH(0, 0, 520, 520));
    // Lying on the floor: squashed and sheared into perspective.
    final m = Float64List(16)
      ..[0] = 1
      ..[4] = 0.16
      ..[5] = 0.58
      ..[10] = 1
      ..[15] = 1
      ..[12] = 900
      ..[13] = 256;
    return _chalk = em.transform(m);
  }

  @override
  void tap(Offset p, SceneCtx c) {
    if (_scene.contains(p)) _flashAt = c.t;
  }

  @override
  void paint(Canvas canvas, SceneCtx c) {
    if (CaseFonts.ready == null) CaseFonts.load();
    final t = c.t;
    const floor = 556.0;
    // Floor and a far wall line.
    canvas.drawLine(const Offset(620, floor), const Offset(1540, floor), Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5);
    canvas.drawPath(dashPath(Path()
      ..moveTo(620, 330)
      ..lineTo(1540, 330), dash: 14, gap: 10), Paint()
      ..color = BP.lineFaint
      ..style = PaintingStyle.stroke);

    // Where the torch points: the pointer, or a slow sweep over the outline.
    final auto = Offset(1120 + math.sin(t * 0.55) * 200, 460 + math.sin(t * 1.1) * 45);
    final p = c.pointer;
    final target = p != null && _scene.contains(p) ? p : auto;

    // Detective, crouched, torch in hand.
    const feet = Offset(700, floor);
    const h = 220.0;
    final shoulder = feet + const Offset(0.06 * h, -(0.71 - 0.13 * 0.85) * h);
    final ang = math.atan2(target.dy - shoulder.dy, target.dx - shoulder.dx);
    paintShadow(canvas, feet, 110);

    final chalk = _outline();
    if (chalk != null) {
      canvas.drawPath(chalk, Paint()
        ..color = BP.ink.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4);
    }

    // Markers pop up one by one.
    const marks = [Offset(890, 548), Offset(1330, 330), Offset(1480, 548)];
    for (var i = 0; i < marks.length; i++) {
      final a = segOut(t, 1.0 + i * 0.35, 1.4 + i * 0.35);
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(marks[i].dx, marks[i].dy);
      canvas.scale(1, a);
      paintMarker(canvas, Offset.zero, '${i + 1}', c.labels);
      canvas.restore();
    }

    // Beam: from the torch to an ellipse of light on the floor.
    final rig = paintDetective(canvas, feet, h, DetPose(crouch: 0.85, torch: 1, pointAngle: ang, look: 0.3));
    final o = rig.lens;
    final spot = Rect.fromCenter(center: target, width: 220, height: 110);
    final beam = Path()
      ..moveTo(o.dx, o.dy)
      ..lineTo(spot.center.dx, spot.top)
      ..lineTo(spot.right, spot.center.dy)
      ..lineTo(spot.center.dx, spot.bottom)
      ..lineTo(spot.left, spot.center.dy)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = ui.Gradient.linear(o, target, [
          BP.amber.withValues(alpha: 0.26),
          BP.amber.withValues(alpha: 0.08),
        ]),
    );
    canvas.drawOval(spot, Paint()
      ..shader = ui.Gradient.radial(target, 110, [BP.amber.withValues(alpha: 0.25), BP.amber.withValues(alpha: 0)]));
    if (chalk != null) {
      // In the light, the chalk reads clearly.
      canvas.save();
      canvas.clipPath(Path()..addOval(spot));
      canvas.drawPath(chalk, Paint()
        ..color = BP.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
      canvas.restore();
    }

    // Police tape across the top of the scene.
    _tape(canvas, const Offset(612, 170), const Offset(1540, 112), t, c.labels);

    // Camera flash.
    final fa = c.t - _flashAt;
    if (fa >= 0 && fa < 0.4) {
      canvas.drawRect(_scene, Paint()..color = Colors.white.withValues(alpha: 0.35 * (1 - fa / 0.4)));
    }
    final tag = c.labels.get('${hexOf(caseCp)} · victim: JP form', BT.mono(13, color: BP.inkDim));
    tag.paint(canvas, const Offset(1540, 572) - Offset(tag.width, 0));
  }

  void _tape(Canvas canvas, Offset a, Offset b, double t, LabelCache labels) {
    final d = b - a;
    final len = d.distance;
    canvas.save();
    canvas.translate(a.dx, a.dy + math.sin(t * 1.3) * 2);
    canvas.rotate(math.atan2(d.dy, d.dx) + math.sin(t * 0.9) * 0.004);
    const hh = 30.0;
    canvas.drawRect(Rect.fromLTWH(0, -hh / 2, len, hh), Paint()..color = BP.amber.withValues(alpha: 0.92));
    final tp = labels.get('KEEP OUT  立入禁止  ', NT.jp(16, color: BP.paper, weight: 700));
    for (var x = 8.0 - (t * 6) % (tp.width); x < len; x += tp.width) {
      if (x + tp.width < 0) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, -hh / 2, len, hh));
      tp.paint(canvas, Offset(x, -tp.height / 2));
      canvas.restore();
    }
    canvas.restore();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 02 · the suspects: the section's glyphs in mugshot frames against a height
// chart. Flashes pop in turn; hovering one shows its real line height.
// ─────────────────────────────────────────────────────────────────────────────

class SuspectsScene extends ChapterScene {
  double _flashAt = -9;
  int _flashed = -1;

  static Rect _frame(int i, int n) {
    final w = math.min(135.0, 860 / n - 12);
    final x = 660 + i * (860 / n);
    return Rect.fromLTWH(x, 110, w, 250);
  }

  @override
  void tap(Offset p, SceneCtx c) {
    final n = c.info.glyphs.length;
    for (var i = 0; i < n; i++) {
      if (_frame(i, n).contains(p)) {
        _flashAt = c.t;
        _flashed = i;
      }
    }
  }

  @override
  void paint(Canvas canvas, SceneCtx c) {
    final t = c.t;
    final glyphs = c.info.glyphs;
    final n = glyphs.length;
    // Height chart.
    final line = Paint()
      ..color = BP.lineFaint
      ..strokeWidth = 1;
    for (var i = 0; i <= 9; i++) {
      final y = 70.0 + i * 40;
      canvas.drawLine(Offset(640, y), Offset(1540, y), line..strokeWidth = i.isEven ? 1.4 : 0.8);
      if (i.isEven) {
        c.labels.get('${200 - i * 10}', BT.mono(11, color: BP.inkFaint)).paint(canvas, Offset(612, y - 7));
      }
    }
    final p = c.pointer;
    // Automatic flashes in turn (and on click).
    final k = (t / 1.5).floor();
    final auto = k % n;
    final autoAge = t - k * 1.5;
    for (var i = 0; i < n; i++) {
      final r = _frame(i, n);
      final hot = p != null && r.contains(p);
      final pop = segOut(t, 0.5 + i * 0.12, 1.0 + i * 0.12);
      if (pop <= 0) continue;
      canvas.save();
      canvas.translate(0, 20 * (1 - pop));
      canvas.drawRect(r, Paint()..color = hot ? BP.amber.withValues(alpha: 0.08) : BP.panel.withValues(alpha: 0.9));
      canvas.drawRect(r, Paint()
        ..color = hot ? BP.amber : BP.lineDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot ? 2 : 1);
      final g = c.labels.get(glyphs[i], BT.sample(80, color: hot ? BP.ink : BP.inkDim));
      final gx = r.center.dx - g.width / 2;
      final gy = r.top + 86 - g.height / 2;
      g.paint(canvas, Offset(gx, gy));
      // Placard.
      final pl = Rect.fromLTWH(r.left + 8, r.bottom - 64, r.width - 16, 52);
      canvas.drawRect(pl, Paint()..color = BP.paper);
      canvas.drawRect(pl, Paint()
        ..color = BP.inkDim
        ..style = PaintingStyle.stroke);
      final script = scriptOfCluster(glyphs[i]);
      c.labels.get(script.label, BT.mono(13, color: script.color)).paint(canvas, pl.topLeft + const Offset(8, 7));
      c.labels.get('#${(i + 1).toString().padLeft(2, '0')}', BT.mono(12, color: BP.inkFaint)).paint(canvas, pl.topLeft + const Offset(8, 28));
      // Real line height of this glyph's run (its font's ascent + descent).
      if (hot) {
        final top = gy;
        final bot = gy + g.height;
        final x = r.right + 6;
        final dp = Paint()
          ..color = BP.amber
          ..strokeWidth = 1.2;
        canvas.drawLine(Offset(x, top), Offset(x, bot), dp);
        canvas.drawLine(Offset(x - 4, top), Offset(x + 4, top), dp);
        canvas.drawLine(Offset(x - 4, bot), Offset(x + 4, bot), dp);
        c.labels.get('h ${g.height.toStringAsFixed(0)}', BT.mono(12, color: BP.amber)).paint(canvas, Offset(x + 6, (top + bot) / 2 - 8));
      }
      // Flash.
      final fAge = i == _flashed ? t - _flashAt : (i == auto ? autoAge : 9.0);
      if (fAge >= 0 && fAge < 0.45) {
        final a = 1 - fAge / 0.45;
        canvas.drawRect(r, Paint()..color = Colors.white.withValues(alpha: 0.3 * a));
        final b = Offset(r.center.dx, r.top - 16);
        final bp = Paint()
          ..color = BP.amber.withValues(alpha: a)
          ..strokeWidth = 1.5;
        for (var s = 0; s < 8; s++) {
          final ang = s * math.pi / 4;
          final dir = Offset(math.cos(ang), math.sin(ang));
          canvas.drawLine(b + dir * 6, b + dir * (12 + 8 * (1 - a)), bp);
        }
      }
      canvas.restore();
    }

    // The detective, inspecting the line-up.
    final sway = math.sin(t * 0.8) * 0.1;
    paintShadow(canvas, const Offset(612, 568), 90);
    paintDetective(canvas, const Offset(612, 568), 170, DetPose(lens: 0.9 + sway, look: 0.2 + sway));
  }
}
