import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../deck/theme.dart';
import '../../../worlds/factory/factory_kit.dart';
import '../method.dart';
import '../stage.dart';

/// 3Dプリント · 3D printing: a gantry printer is set over the glyph on a
/// heated bed; layer by layer from the bottom (the glyph's rows), the nozzle
/// zig-zags along every inside span extruding a bead of filament, the gantry
/// stepping up a layer at a time, while its little screen counts the %.
/// The print shows its layer lines; violet or teal filament.
class Print3dCraft extends CraftMethod {
  const Print3dCraft();

  @override
  String get id => 'print3d';

  @override
  String get en => '3D printing';

  @override
  String get ja => '3Dプリント';

  @override
  Color get color => Mat.plastic;

  @override
  double get weight => 1.0;

  static final _prints = Expando<_Print>();
  static final _pics = Expando<ui.Picture>();

  _Print _print(CraftContext x) => _prints[x.s] ??= _Print(x.s, x.seed);

  // ── The print ─────────────────────────────────────────────────────────────

  /// Adds one bead (a span of a layer, from [x0] to [x1]) to the paths.
  static void _bead(double x0, double x1, double y0, double y1, Path body, Path lo, Path hi) {
    if (x1 - x0 < 0.5) return;
    final h = y1 - y0;
    final r = math.min(h / 2, (x1 - x0) / 2);
    body.addRRect(RRect.fromLTRBR(x0, y0, x1, y1, Radius.circular(r)));
    if (x1 - x0 > 2 * r + 1) {
      lo
        ..moveTo(x0 + r, y1 - 0.7)
        ..lineTo(x1 - r, y1 - 0.7);
      hi
        ..moveTo(x0 + r, y0 + h * 0.3)
        ..lineTo(x1 - r, y0 + h * 0.3);
    }
  }

  static void _flush(Canvas c, _Print pr, Path body, Path lo, Path hi) {
    c.drawPath(body, Paint()..color = pr.base);
    c.drawPath(
      lo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = pr.dark,
    );
    c.drawPath(
      hi,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, pr.lh * 0.16)
        ..strokeCap = StrokeCap.round
        ..color = pr.light.withValues(alpha: 0.75),
    );
  }

  ui.Picture _finished(CraftContext x) => _pics[x.s] ??= () {
    final pr = _print(x);
    final rec = ui.PictureRecorder();
    final body = Path(), lo = Path(), hi = Path();
    for (final l in pr.layers) {
      for (final (a, b) in l.spans) {
        _bead(a, b, l.top, l.bottom, body, lo, hi);
      }
    }
    _flush(Canvas(rec), pr, body, lo, hi);
    return rec.endRecording();
  }();

  @override
  void paintFinished(CraftContext x) => x.c.drawPicture(_finished(x));

  // ── Making ────────────────────────────────────────────────────────────────

  @override
  void paintMaking(CraftContext x, double p) {
    final s = x.s, c = x.c;
    final pr = _print(x);
    final q = seg(p, 0.08, 0.93);
    final at = pr.at(q);

    c.drawPath(s.outline, x.st(BP.lineFaint, 1.2));

    // Printed so far: whole layers (the finished print, clipped), then the
    // current layer's beads up to the nozzle.
    if (q >= 1) {
      c.drawPicture(_finished(x));
    } else if (pr.layers.isNotEmpty) {
      final l = pr.layers[at.layer];
      c.save();
      c.clipRect(Rect.fromLTRB(s.ink.left - 10, l.bottom, s.ink.right + 10, s.ink.bottom + 10));
      c.drawPicture(_finished(x));
      c.restore();
      final body = Path(), lo = Path(), hi = Path();
      for (var i = 0; i < l.spans.length; i++) {
        if (l.dir > 0 ? i >= at.span : i <= at.span) continue;
        final (a, b) = l.spans[i];
        _bead(a, b, l.top, l.bottom, body, lo, hi);
      }
      if (at.extruding) {
        final (a, b) = l.spans[at.span];
        final (x0, x1) = l.dir > 0 ? (a, at.nozzle.dx) : (at.nozzle.dx, b);
        _bead(x0, x1, l.top, l.bottom, body, lo, hi);
      }
      _flush(c, pr, body, lo, hi);
    }

    // The printer: lowered in, printing, parked and lifted away.
    final drop = 1 - eo(seg(p, 0, 0.05));
    final away = eio(seg(p, 0.95, 1));
    final alpha = math.min(seg(p, 0, 0.035), 1 - away);
    if (alpha <= 0) return;
    Offset nozzle;
    if (q <= 0) {
      // Homing from the back corner.
      nozzle = Offset.lerp(pr.park, pr.start, eio(seg(p, 0.05, 0.08)))!;
    } else if (q >= 1) {
      nozzle = Offset.lerp(pr.end, pr.park, eio(seg(p, 0.93, 0.955)))!;
    } else {
      nozzle = at.nozzle;
    }
    final fade = alpha < 1;
    if (fade) {
      c.saveLayer(
        Rect.fromLTRB(pr.frame.left - 40, pr.frame.top - 40, pr.frame.right + 140, x.floorY + 4),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }
    c.save();
    // (Small moves only: the frame's top stays clear of the name sign.)
    c.translate(0, -12 * drop - 10 * away);
    _printer(x, pr, nozzle, printing: q > 0 && q < 1 && at.extruding, p: p, q: q);
    c.restore();
    if (fade) c.restore();
    _crew(x, pr, p);
  }

  static const _frameCol = Color(0xFF9FB8D4);
  static const _rail = Color(0xFF5E7A99);

  void _printer(CraftContext x, _Print pr, Offset nozzle, {required bool printing, required double p, required double q}) {
    final c = x.c;
    final f = pr.frame;
    // Heated bed under the glyph.
    final bed = Rect.fromLTRB(f.left + 14, f.bottom - 1, f.right - 14, f.bottom + 7);
    c.drawRect(bed, x.fl(const Color(0xFF1B2733)));
    final heat = 0.5 + 0.5 * seg(p, 0.02, 0.08);
    c.drawLine(
      Offset(bed.left + 2, bed.top + 1.5),
      Offset(bed.right - 2, bed.top + 1.5),
      x.st(Color.lerp(BP.lineDim, BP.coral, heat)!, 1.6),
    );
    c.drawRect(bed, x.st(_rail, 1.2));
    // Posts and top bar.
    for (final px in [f.left, f.right]) {
      final post = Rect.fromLTRB(px - 6, f.top, px + 6, f.bottom + 7);
      c.drawRect(post, x.fl(BP.panel));
      c.drawRect(post, x.st(_frameCol, 1.4));
      c.drawLine(Offset(px, f.top + 8), Offset(px, f.bottom), x.st(_rail, 1));
      // Foot.
      c.drawRect(Rect.fromLTRB(px - 12, f.bottom + 3, px + 12, f.bottom + 9), x.fl(_rail));
    }
    final top = Rect.fromLTRB(f.left - 10, f.top - 10, f.right + 10, f.top + 2);
    c.drawRect(top, x.fl(BP.panel));
    c.drawRect(top, x.st(_frameCol, 1.4));
    // Lead screws (Z) beside the posts.
    for (final px in [f.left + 12, f.right - 12]) {
      c.drawLine(Offset(px, f.top + 2), Offset(px, f.bottom - 1), x.st(_rail.withValues(alpha: 0.8), 1.2));
    }
    // X gantry at the nozzle's height.
    final gy = nozzle.dy - 27;
    final beam = Rect.fromLTRB(f.left - 4, gy - 5, f.right + 4, gy + 5);
    c.drawRect(beam, x.fl(BP.panel));
    c.drawRect(beam, x.st(_frameCol, 1.3));
    c.drawLine(Offset(beam.left + 6, gy), Offset(beam.right - 6, gy), x.st(_rail, 1));
    // Filament: spool on the right post, Bowden tube to the head.
    final spool = Offset(f.right + 34, f.top + 46);
    c.drawLine(Offset(f.right + 6, spool.dy), spool, x.st(_frameCol, 2.4));
    c.drawCircle(spool, 22, x.fl(pr.dark));
    c.drawCircle(spool, 17, x.fl(pr.base));
    c.drawCircle(spool, 22, x.st(BP.ink, 1.2));
    c.drawCircle(spool, 6, x.fl(BP.panel));
    final spin = -x.t * (printing ? 2.2 : 0.2);
    for (var i = 0; i < 3; i++) {
      final a = spin + i * math.pi * 2 / 3;
      c.drawLine(spool, spool + Offset(math.cos(a), math.sin(a)) * 6, x.st(BP.ink, 1.2));
    }
    final head = Rect.fromCenter(center: Offset(nozzle.dx, gy), width: 34, height: 24);
    // (Kept below the name sign: the curve stays inside its control points.)
    final arch = f.top - 16;
    final tube = Path()
      ..moveTo(spool.dx - 4, spool.dy - 20)
      ..cubicTo(spool.dx - 8, arch, head.center.dx + 24, arch, head.center.dx + 6, head.top);
    c.drawPath(tube, x.st(BP.ink.withValues(alpha: 0.7), 1.6));
    // Print head: carriage, fan, heater block, nozzle.
    c.drawRRect(RRect.fromRectAndRadius(head, const Radius.circular(3)), x.fl(const Color(0xFF203246)));
    c.drawRRect(RRect.fromRectAndRadius(head, const Radius.circular(3)), x.st(_frameCol, 1.3));
    final fan = head.center + const Offset(0, 1);
    c.drawCircle(fan, 9, x.st(BP.inkDim, 1));
    final blades = x.t * (printing ? 24 : 3);
    for (var i = 0; i < 4; i++) {
      final a = blades + i * math.pi / 2;
      c.drawLine(fan, fan + Offset(math.cos(a), math.sin(a)) * 7.5, x.st(BP.inkDim, 1.4));
    }
    final block = Rect.fromLTRB(nozzle.dx - 7, head.bottom, nozzle.dx + 7, head.bottom + 6);
    c.drawRect(block, x.fl(Mat.bronze));
    c.drawRect(block, x.st(const Color(0xFF8A5A2B), 1));
    final cone = Path()
      ..moveTo(nozzle.dx - 5, block.bottom)
      ..lineTo(nozzle.dx + 5, block.bottom)
      ..lineTo(nozzle.dx + 1.2, nozzle.dy - 1)
      ..lineTo(nozzle.dx - 1.2, nozzle.dy - 1)
      ..close();
    c.drawPath(cone, x.fl(Mat.gold));
    if (printing) {
      x.glow(nozzle, 9, BP.coral, alpha: 0.45);
      c.drawCircle(nozzle, 2.2, x.fl(pr.light));
    }
    // Control screen with the progress.
    final scr = Rect.fromLTWH(f.right + 10, x.floorY - 96, 66, 44);
    c.drawRect(scr, x.fl(BP.panel));
    c.drawRect(scr, x.st(_frameCol, 1.3));
    final lcd = scr.deflate(4);
    c.drawRect(lcd, x.fl(const Color(0xFF062437)));
    final pct = (q * 100).floor().clamp(0, 100);
    final label = x.text.get('$pct%', BT.mono(17, color: BP.green, weight: 700));
    label.paint(c, Offset(lcd.center.dx - label.width / 2, lcd.top + 1));
    final bar = Rect.fromLTWH(lcd.left + 4, lcd.bottom - 7, lcd.width - 8, 4);
    c.drawRect(bar, x.fl(BP.lineFaint));
    c.drawRect(Rect.fromLTWH(bar.left, bar.top, bar.width * q, bar.height), x.fl(BP.green));
    c.drawLine(Offset(scr.center.dx, scr.bottom), Offset(scr.center.dx, x.floorY), x.st(_frameCol, 2));
  }

  /// A technician at the screen; a colleague on a crate with a coffee,
  /// watching the print.
  void _crew(CraftContext x, _Print pr, double p) {
    final c = x.c, f = pr.frame;
    final techX = math.min(f.right + 96, 1440.0);
    final screen = Offset(f.right + 43, x.floorY - 74);
    final limbs = x.reach(Offset(techX, x.floorY), screen, dir: -1, hat: BP.violet);
    c.drawCircle(limbs.handA, 2, x.fl(BP.ink));
    final crate = Rect.fromLTRB(1444, x.floorY - 18, 1474, x.floorY);
    x.ink.crate(crate, BP.lineDim);
    final pose = Pose()
      ..sit(44, 18)
      ..upA = 1.5
      ..head = -0.15;
    final l = x.ink.worker(Offset(1458, x.floorY), 44, -1, pose, hat: BP.green);
    x.ink.coffee(l.handA, x.t);
  }
}

/// One layer: its band of the glyph and the inside spans along its middle.
class _Layer {
  _Layer(this.top, this.bottom, this.spans, this.dir);

  final double top;
  final double bottom;

  /// Left to right.
  final List<(double, double)> spans;

  /// Print direction (1: left → right; odd layers come back).
  final int dir;
}

/// A nozzle move: travel or extrusion along a layer.
class _Move {
  _Move(this.layer, this.span, this.from, this.to, this.start, this.units, {required this.extrude});

  final int layer;
  final int span;
  final Offset from;
  final Offset to;
  final double start;
  final double units;
  final bool extrude;
}

/// The glyph sliced into layers (bottom first) and the nozzle's path.
class _Print {
  _Print(GlyphStage s, int seed) {
    final ink = s.ink;
    final teal = rnd(seed, 3, 11) < 0.5;
    base = teal ? const Color(0xFF45CFC0) : Mat.plastic;
    dark = teal ? const Color(0xFF1F8F84) : const Color(0xFF7A5BC4);
    light = teal ? const Color(0xFFB4F5EC) : const Color(0xFFE6D9FF);
    final n = math.max(1, (ink.height / (2 * s.typicalRadius * 0.34).clamp(5.0, 10.0)).round()).clamp(1, 60);
    lh = ink.height / n;
    for (var i = 0; i < n; i++) {
      final bottom = ink.bottom - i * lh, top = bottom - lh;
      final spans = [
        for (final sp in _scan(s, (top + bottom) / 2))
          if (sp.$2 - sp.$1 >= 1.5) sp,
      ];
      if (spans.isEmpty) continue;
      layers.add(_Layer(top, bottom, spans, layers.length.isEven ? 1 : -1));
    }
    frame = Rect.fromLTRB(ink.left - 54, math.max(330.0, ink.top - 40), ink.right + 54, ink.bottom);
    park = Offset(frame.right - 30, frame.top + 42);
    start = layers.isEmpty ? park : Offset(layers.first.spans.first.$1, layers.first.top);
    // The nozzle's path: along each layer's spans (alternating direction),
    // travelling between them, stepping up between layers.
    var at = start;
    var t = 0.0;
    void move(int layer, int span, Offset to, {required bool extrude}) {
      final d = (to - at).distance;
      final units = extrude ? d + 2 : d * 0.3 + 3;
      _moves.add(_Move(layer, span, at, to, t, units, extrude: extrude));
      t += units;
      at = to;
    }

    for (var li = 0; li < layers.length; li++) {
      final l = layers[li];
      final order = l.dir > 0 ? [for (var i = 0; i < l.spans.length; i++) i] : [for (var i = l.spans.length - 1; i >= 0; i--) i];
      for (final si in order) {
        final (a, b) = l.spans[si];
        final y = l.top;
        final from = Offset(l.dir > 0 ? a : b, y), to = Offset(l.dir > 0 ? b : a, y);
        move(li, si, from, extrude: false);
        move(li, si, to, extrude: true);
      }
    }
    _total = math.max(1, t);
    end = at;
  }

  late final Color base;
  late final Color dark;
  late final Color light;

  /// Layer height (canvas px).
  late final double lh;
  final layers = <_Layer>[];
  late final Rect frame;
  late final Offset park;
  late final Offset start;
  late final Offset end;
  final _moves = <_Move>[];
  late final double _total;

  /// The nozzle at print progress [q]: layer, span (index in the layer's
  /// left-to-right list; the spans before it in print order are done),
  /// position, and whether it's extruding.
  ({int layer, int span, Offset nozzle, bool extruding}) at(double q) {
    if (_moves.isEmpty) return (layer: 0, span: 0, nozzle: park, extruding: false);
    final time = q.clamp(0.0, 1.0) * _total;
    var lo = 0, hi = _moves.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_moves[mid].start <= time) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final m = _moves[lo];
    final f = ((time - m.start) / m.units).clamp(0.0, 1.0);
    final pos = Offset.lerp(m.from, m.to, f)!;
    return (layer: m.layer, span: m.span, nozzle: pos, extruding: m.extrude);
  }

  /// Inside intervals (canvas x, left to right) of the glyph's outline along
  /// the horizontal line [y] (even-odd over every contour).
  static List<(double, double)> _scan(GlyphStage s, double y) {
    final xs = <double>[];
    final ox = s.origin.dx, oy = s.origin.dy, k = s.k;
    for (final c in s.geo.contours) {
      final n = c.count, pts = c.pts;
      for (var i = 0; i < n; i++) {
        final j = i + 1 == n ? 0 : i + 1;
        final ay = oy + pts[2 * i + 1] * k, by = oy + pts[2 * j + 1] * k;
        if ((ay <= y) == (by <= y)) continue;
        final ax = ox + pts[2 * i] * k, bx = ox + pts[2 * j] * k;
        xs.add(ax + (y - ay) / (by - ay) * (bx - ax));
      }
    }
    xs.sort();
    return [for (var i = 0; i + 1 < xs.length; i += 2) (xs[i], xs[i + 1])];
  }
}
