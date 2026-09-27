import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'detective_chapters.dart';
import 'noir_kit.dart';

const _floor = 556.0;
const _area = Rect.fromLTRB(600, 40, 1540, 580);

// ─────────────────────────────────────────────────────────────────────────────
// 03 · other precincts: four stations down a rainy street. The detective
// walks from door to door; each has its own lead on the language.
// Click a precinct to send him there.
// ─────────────────────────────────────────────────────────────────────────────

class PrecinctsScene extends ChapterScene {
  static const _names = ['Chrome', 'Figma', 'Apple', 'Android'];
  static const _leads = ['lang="ja"', 'Noto per char', 'preferred languages', 'setTextLocale'];
  static const _heights = [300.0, 262.0, 330.0, 286.0];

  double _x = 640;
  int _target = 0;
  double _arrivedAt = -1;
  double _phase = 0;

  static double _cx(int i) => 740 + i * 232.0;

  @override
  void tap(Offset p, SceneCtx c) {
    for (var i = 0; i < 4; i++) {
      if ((p.dx - _cx(i)).abs() < 100 && p.dy > _floor - _heights[i] && p.dy < _floor) {
        _target = i;
        _arrivedAt = -1;
      }
    }
  }

  @override
  void paint(Canvas canvas, SceneCtx c) {
    final t = c.t;
    // Walk towards the target door; wait; move on.
    final goal = _cx(_target) - 34;
    final d = goal - _x;
    var stride = 0.0;
    if (d.abs() > 2) {
      final step = 150 * c.dt * d.sign;
      _x += step.abs() > d.abs() ? d : step;
      _phase += step.abs() / 30;
      stride = 1;
    } else {
      if (_arrivedAt < 0) _arrivedAt = t;
      if (t - _arrivedAt > 3.2) {
        _target = (_target + 1) % 4;
        _arrivedAt = -1;
      }
    }
    final at = _arrivedAt >= 0 ? _target : -1;

    paintRain(canvas, _area, c.clock, count: 90, alpha: 0.12, salt: 21);
    for (var i = 0; i < 4; i++) {
      _building(canvas, i, i == at, i == _target, c);
    }
    paintStreet(canvas, _floor, 620, 1540);
    paintSplashes(canvas, 620, 1540, _floor, c.clock, count: 10, salt: 4);

    final facing = d.abs() > 2 ? d.sign : 1.0;
    final knock = at >= 0 ? math.max(0.0, math.sin((t - _arrivedAt) * 9)) * seg(t - _arrivedAt, 0.2, 0.4) * (1 - seg(t - _arrivedAt, 1.0, 1.2)) : 0.0;
    paintShadow(canvas, Offset(_x, _floor), 70);
    paintDetective(
      canvas,
      Offset(_x, _floor),
      150,
      DetPose(walk: _phase, stride: stride, facing: facing, point: knock, pointAngle: -0.2, look: at >= 0 ? 0.4 : 0),
    );
  }

  void _building(Canvas canvas, int i, bool here, bool next, SceneCtx c) {
    final h = _heights[i];
    final r = Rect.fromLTWH(_cx(i) - 100, _floor - h, 200, h);
    final ink = here ? BP.line : BP.lineDim;
    canvas.drawRect(r, Paint()..color = BP.panel);
    canvas.drawRect(r, Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = here ? 1.8 : 1.2);
    // Cornice and sign.
    canvas.drawLine(r.topLeft - const Offset(8, 0), r.topRight + const Offset(8, 0), Paint()
      ..color = ink
      ..strokeWidth = 2);
    final sign = Rect.fromCenter(center: Offset(r.center.dx, r.top + 26), width: 160, height: 34);
    canvas.drawRect(sign, Paint()..color = BP.paper);
    canvas.drawRect(sign, Paint()
      ..color = here ? BP.amber : BP.inkDim
      ..style = PaintingStyle.stroke);
    final name = c.labels.get(_names[i], BT.mono(17, color: here ? BP.amber : BP.ink));
    name.paint(canvas, sign.center - Offset(name.width / 2, name.height / 2));
    // Windows, some lit (lit up when the detective is here).
    for (var row = 0; row < ((h - 150) / 44).floor(); row++) {
      for (var col = 0; col < 3; col++) {
        final w = Rect.fromLTWH(r.left + 26 + col * 56, r.top + 60 + row * 44, 36, 28);
        final lit = here || hash01(i * 31 + row * 7 + col, (c.clock / 3).floor()) > 0.7;
        canvas.drawRect(w, Paint()..color = lit ? BP.amber.withValues(alpha: here ? 0.35 : 0.18) : BP.paper);
        canvas.drawRect(w, Paint()
          ..color = BP.lineFaint
          ..style = PaintingStyle.stroke);
      }
    }
    // Door + lamp.
    final door = Rect.fromLTWH(r.center.dx - 22, _floor - 70, 44, 70);
    canvas.drawRect(door, Paint()..color = BP.paper);
    canvas.drawRect(door, Paint()
      ..color = ink
      ..style = PaintingStyle.stroke);
    final lamp = Offset(r.center.dx, door.top - 14);
    final pulse = 0.5 + 0.5 * math.sin(c.clock * 3 + i);
    canvas.drawCircle(lamp, 16, Paint()
      ..shader = ui.Gradient.radial(lamp, 16, [BP.line.withValues(alpha: 0.5 * pulse), BP.line.withValues(alpha: 0)]));
    canvas.drawCircle(lamp, 4, Paint()..color = BP.line);
    // The lead, hanging under the sign.
    final lead = c.labels.get(_leads[i], BT.mono(13, color: here ? BP.paper : BP.amber));
    final tr = Rect.fromLTWH(r.center.dx - (lead.width + 30) / 2, sign.bottom + 10, lead.width + 30, lead.height + 8);
    paintTag(canvas, tr, color: BP.amber, filled: here);
    lead.paint(canvas, Offset(tr.left + 22, tr.top + 4));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 04 · the motive: the interrogation room. A lamp swings over the table with
// two cards on it, ✕ and ✓. Drag to push the lamp.
// ─────────────────────────────────────────────────────────────────────────────

class InterrogationScene extends ChapterScene {
  double _a = 0.35;
  double _w = 0;

  static const _pivot = Offset(1160, 40);
  static const _cord = 170.0;

  @override
  void drag(Offset delta, SceneCtx c) => _w += delta.dx * 0.01;

  @override
  void tap(Offset p, SceneCtx c) => _w += (p.dx < _pivot.dx ? 1 : -1) * 0.9;

  @override
  void paint(Canvas canvas, SceneCtx c) {
    // Pendulum, lightly damped, nudged so it never quite stops.
    final dt = c.dt;
    for (var k = 0; k < 2; k++) {
      final acc = -9.0 / (_cord / 100) * math.sin(_a) - 0.25 * _w;
      _w += acc * dt / 2;
      _a += _w * dt / 2;
    }
    if (_a.abs() < 0.12 && _w.abs() < 0.25) _w += 0.02 * (_w >= 0 ? 1 : -1);
    _a = _a.clamp(-1.1, 1.1);
    final bulb = _pivot + Offset(math.sin(_a), math.cos(_a)) * _cord;

    // Back wall: the one-way mirror.
    final mirror = const Rect.fromLTWH(680, 90, 300, 180);
    canvas.drawRect(mirror, Paint()..color = BP.panel);
    canvas.drawRect(mirror, Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    final glint = Paint()
      ..color = BP.inkDim.withValues(alpha: 0.18)
      ..strokeWidth = 6;
    canvas.save();
    canvas.clipRect(mirror);
    for (var k = 0; k < 2; k++) {
      final x = mirror.left + ((c.clock * 30 + k * 150) % 420) - 60;
      canvas.drawLine(Offset(x, mirror.bottom), Offset(x + 90, mirror.top), glint);
    }
    canvas.restore();
    canvas.drawLine(const Offset(620, _floor), const Offset(1540, _floor), Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5);

    // Light cone along the cord's direction.
    final dir = Offset(math.sin(_a), math.cos(_a));
    final ground = bulb + dir * ((_floor - bulb.dy) / math.max(0.3, dir.dy));
    paintCone(canvas, bulb, _floor, halfWidth: 170, skew: ground.dx - bulb.dx, topHalf: 14);

    // Table and the chair across it.
    final ink = Paint()
      ..color = BP.ink
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(960, 440), const Offset(1370, 440), ink..strokeWidth = 3);
    canvas.drawLine(const Offset(985, 440), const Offset(985, _floor), ink..strokeWidth = 2);
    canvas.drawLine(const Offset(1345, 440), const Offset(1345, _floor), ink);
    final chair = Path()
      ..moveTo(1420, _floor)
      ..lineTo(1420, 470)
      ..lineTo(1480, 470)
      ..lineTo(1480, _floor)
      ..moveTo(1480, 470)
      ..lineTo(1488, 360);
    canvas.drawPath(chair, ink);
    final placard = c.labels.get('Flutter', BT.mono(14, color: BP.line));
    final pr = Rect.fromLTWH(1440, 380, placard.width + 18, placard.height + 8);
    canvas.drawRect(pr, Paint()..color = BP.paper);
    canvas.drawRect(pr, Paint()
      ..color = BP.line
      ..style = PaintingStyle.stroke);
    placard.paint(canvas, pr.topLeft + const Offset(9, 4));

    // The two cards on the table.
    final p = c.pointer;
    final glyphs = c.info.glyphs;
    for (var i = 0; i < 2; i++) {
      final r = Rect.fromLTWH(1060 + i * 150, 340, 96, 96);
      final hot = p != null && r.inflate(10).contains(p);
      final lit = (bulb.dx - r.center.dx).abs() < 150;
      final col = i == 0 ? BP.red : BP.green;
      canvas.save();
      canvas.translate(r.center.dx, r.bottom);
      canvas.rotate((i == 0 ? -0.06 : 0.05) + (hot ? 0.04 : 0));
      canvas.translate(-r.center.dx, -r.bottom);
      final rr = hot ? r.inflate(6) : r;
      canvas.drawRect(rr, Paint()..color = lit || hot ? Color.alphaBlend(col.withValues(alpha: 0.12), BP.paper) : BP.paper);
      canvas.drawRect(rr, Paint()
        ..color = col.withValues(alpha: lit || hot ? 1 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
      final m = Paint()
        ..color = col.withValues(alpha: lit || hot ? 1 : 0.6)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final q = rr.deflate(26);
      if (i == 0 || glyphs.isEmpty) {
        canvas.drawLine(q.topLeft, q.bottomRight, m);
        canvas.drawLine(q.topRight, q.bottomLeft, m);
      } else {
        canvas.drawPath(Path()
          ..moveTo(q.left, q.center.dy)
          ..lineTo(q.left + q.width * 0.38, q.bottom)
          ..lineTo(q.right, q.top), m);
      }
      canvas.restore();
      final lab = c.labels.get(i == 0 ? "can't" : 'can', BT.mono(14, color: col));
      lab.paint(canvas, Offset(r.center.dx - lab.width / 2, 450));
    }

    // Lamp on top of everything.
    canvas.drawLine(_pivot, bulb, Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1.5);
    canvas.save();
    canvas.translate(bulb.dx, bulb.dy);
    canvas.rotate(-_a);
    paintLampShade(canvas, Offset.zero, size: 44, glow: 1);
    canvas.restore();

    // Detective leaning over the table, pointing at the cards.
    paintShadow(canvas, const Offset(900, _floor), 90);
    paintDetective(canvas, const Offset(900, _floor), 200,
        DetPose(lean: 1, point: 0.8 + 0.2 * math.sin(c.t * 1.3), pointAngle: 0.35, look: -0.3));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 05 · the reconstruction: the evidence board. The word, its glyph id and its
// pixels pinned up, joined by red string; hover a photo to lift it.
// ─────────────────────────────────────────────────────────────────────────────

class BoardScene extends ChapterScene {
  static const _board = Rect.fromLTRB(660, 56, 1500, 486);
  static const _photos = [Rect.fromLTWH(710, 120, 150, 170), Rect.fromLTWH(960, 270, 150, 170), Rect.fromLTWH(1250, 110, 150, 170)];
  static const _notes = [(Offset(900, 100), 'layout()'), (Offset(1150, 360), 'paint()')];

  @override
  void paint(Canvas canvas, SceneCtx c) {
    final t = c.t;
    canvas.drawRect(_board, Paint()..color = BP.panel);
    canvas.drawPath(dashPath(Path()..addRect(_board), dash: 10, gap: 6), Paint()
      ..color = BP.lineDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    // Cork texture: a sparse dot field.
    final dot = Paint()..color = BP.lineFaint;
    for (var i = 0; i < 90; i++) {
      canvas.drawCircle(Offset(_board.left + hash01(i, 1) * _board.width, _board.top + hash01(i, 2) * _board.height), 1.2, dot);
    }
    final items = [
      for (final g in c.info.glyphs)
        if (g != '→') g,
    ];
    final p = c.pointer;
    // Pins: photo, note, photo, note, photo.
    final pins = <Offset>[
      _photos[0].topCenter + const Offset(0, 10),
      _notes[0].$1 + const Offset(60, 6),
      _photos[1].topCenter + const Offset(0, 10),
      _notes[1].$1 + const Offset(55, 6),
      _photos[2].topCenter + const Offset(0, 10),
    ];
    // Photos.
    for (var i = 0; i < _photos.length; i++) {
      final r0 = _photos[i];
      final hot = p != null && r0.contains(p);
      final pop = segOut(t, 0.4 + i * 0.25, 0.9 + i * 0.25);
      if (pop <= 0) continue;
      final r = hot ? r0.inflate(6) : r0;
      canvas.save();
      canvas.translate(r.center.dx, r.top);
      canvas.rotate([-0.05, 0.04, -0.03][i] + (hot ? 0.02 : 0));
      canvas.scale(pop);
      canvas.translate(-r.center.dx, -r.top);
      if (hot) canvas.drawRect(r.shift(const Offset(6, 8)), Paint()..color = Colors.black.withValues(alpha: 0.3));
      canvas.drawRect(r, Paint()..color = BP.paper);
      canvas.drawRect(r, Paint()
        ..color = hot ? BP.amber : BP.inkDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4);
      final inner = Rect.fromLTWH(r.left + 12, r.top + 22, r.width - 24, r.height - 58);
      canvas.drawRect(inner, Paint()..color = BP.panel);
      final label = i < items.length ? items[i] : '';
      if (label == '▦' || i == 2) {
        // Pixels: a tiny coverage grid.
        final cell = inner.width / 8;
        for (var y = 0; y < 6; y++) {
          for (var x = 0; x < 8; x++) {
            final v = hash01(x * 13 + y * 5, 9);
            canvas.drawRect(
              Rect.fromLTWH(inner.left + x * cell, inner.top + 8 + y * cell, cell - 1, cell - 1),
              Paint()..color = BP.line.withValues(alpha: v > 0.45 ? v * 0.8 : 0.06),
            );
          }
        }
      } else {
        final g = c.labels.get(label, i == 0 ? BT.display(80, color: BP.ink) : BT.mono(44, color: BP.amber));
        g.paint(canvas, inner.center - Offset(g.width / 2, g.height / 2));
      }
      final cap = c.labels.get(['word', 'glyph id', 'pixels'][i], BT.mono(13, color: BP.inkDim));
      cap.paint(canvas, Offset(r.left + 12, r.bottom - 28));
      canvas.restore();
    }
    for (final (o, s) in _notes) {
      final tp = c.labels.get(s, BT.mono(15, color: BP.amber));
      final r = Rect.fromLTWH(o.dx, o.dy, tp.width + 28, 40);
      canvas.drawRect(r, Paint()..color = Color.alphaBlend(BP.amber.withValues(alpha: 0.1), BP.paper));
      canvas.drawRect(r, Paint()
        ..color = BP.amber
        ..style = PaintingStyle.stroke);
      tp.paint(canvas, r.topLeft + Offset(14, 20 - tp.height / 2));
    }
    // Red string, strung pin by pin; then re-strung every 12 s.
    final u = (t % 12.0);
    for (var i = 0; i < pins.length - 1; i++) {
      final prog = seg(u, 1.2 + i * 0.6, 1.8 + i * 0.6) * (1 - seg(u, 11.2, 11.8));
      drawString(canvas, pins[i], pins[i + 1], sag: 26, progress: prog, width: 2);
    }
    for (final pin in pins) {
      drawPin(canvas, pin, r: 6);
    }

    // The detective pins it all together.
    final reach = 0.6 + 0.4 * math.sin(t * 1.1);
    paintShadow(canvas, const Offset(1470, 568), 90);
    paintDetective(canvas, const Offset(1470, 568), 190,
        DetPose(facing: -1, point: reach, pointAngle: -0.9, look: 0.6, notes: 0.8 * (1 - reach)));
  }
}
