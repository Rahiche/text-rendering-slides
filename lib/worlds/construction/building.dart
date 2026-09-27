import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import 'site_kit.dart';

/// "Our building": the one the whole talk constructs, floor by floor. The
/// section dividers and the outro all draw it at the same place, so paging
/// through the deck shows it grow: foundation → 1F → 2F → 3F → 4F → roof.
abstract final class Bld {
  static const ground = 742.0;
  static const left = 1000.0;
  static const width = 400.0;
  static const right = left + width;
  static const cx = left + width / 2;
  static const floorH = 70.0;
  static const bays = 5;
  static const bay = width / bays;
  static const floors = 4;
  static const footTop = ground + 12;
  static const footBottom = ground + 44;

  // The tower crane next to it.
  static const mastL = 1452.0;
  static const mastR = 1478.0;
  static const jibY = 318.0;
  static const jibL = 640.0;
  static const jibR = 1566.0;

  /// Y of the top slab of floor [n] (1-based); floor 0 is the ground.
  static double top(int n) => ground - n * floorH;

  /// The 7 footings of the foundation = the 7 pipeline stages.
  static Rect footing(int i) {
    const w = width / 7;
    return Rect.fromLTWH(left + i * w + 3, footTop, w - 6, footBottom - footTop);
  }
}

/// While floor [n] is at progress [p], the crane lowers its slab: returns the
/// slab's rect (null when not hanging / not placed yet) and whether it hangs.
(Rect?, bool) slabAt(int n, double p) {
  final y = Bld.top(n);
  final placed = Rect.fromLTRB(Bld.left - 8, y - 3, Bld.right + 8, y + 3);
  if (p <= 0.3) return (null, false);
  if (p >= 0.7) return (placed, false);
  final f = (p - 0.3) / 0.4;
  final hangY = Bld.jibY + 70;
  final yy = f < 0.8 ? lerpD(hangY, y - 16, eio(f / 0.8)) : lerpD(y - 16, y, backOut((f - 0.8) / 0.2));
  return (placed.shift(Offset(0, yy - y)), true);
}

/// Draws the building. [done] complete floors above ground, floor done+1 at
/// progress [p] (0..1), the roof at [roof] (0..1). [lit] 0..1 lights windows.
void paintBuilding(
  SiteKit k, {
  bool foundation = true,
  required int done,
  double p = 0,
  double roof = 0,
  bool ghost = true,
  double lit = 0,
  bool slab = true,
  Color accent = BP.line,
}) {
  final c = k.c;
  // The plan of what is still to come: dashed, faint.
  if (ghost) c.drawPath(_ghosts[done] ??= _ghost(done), strokeP(BP.lineFaint, 1));

  if (foundation) _foundation(k);

  for (var n = 1; n <= done; n++) {
    _floor(k, n, 1, lit, accent, slab: true);
  }
  if (p > 0 && done < Bld.floors) _floor(k, done + 1, p, 0, accent, slab: slab);
  if (roof > 0) _roof(k, roof);
}

final _ghosts = <int, Path>{};

Path _ghost(int done) {
  final g = Path();
  final topAll = Bld.top(Bld.floors) - 22;
  g.addRect(Rect.fromLTRB(Bld.left, topAll + 22, Bld.right, Bld.top(done)));
  for (var n = done + 1; n < Bld.floors; n++) {
    g
      ..moveTo(Bld.left, Bld.top(n))
      ..lineTo(Bld.right, Bld.top(n));
  }
  g.addRect(Rect.fromLTRB(Bld.left + 30, topAll, Bld.right - 30, topAll + 22));
  return dashPath(g, dash: 4, gap: 6);
}

void _foundation(SiteKit k) {
  final c = k.c;
  final band = Rect.fromLTRB(Bld.left - 10, Bld.ground, Bld.right + 10, Bld.footTop);
  c.drawRect(band, fillP(BP.paper));
  c.drawRect(band, strokeP(BP.lineDim, 1.2));
  final hatch = Path();
  for (var x = band.left + 6; x < band.right; x += 10) {
    hatch
      ..moveTo(x, band.bottom - 1)
      ..lineTo(x + 8, band.top + 1);
  }
  c.drawPath(hatch, strokeP(BP.lineFaint, 1));
  for (var i = 0; i < 7; i++) {
    final r = Bld.footing(i);
    final pad = Path()
      ..moveTo(r.left + 6, r.top)
      ..lineTo(r.right - 6, r.top)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
    c.drawPath(pad, fillP(BP.lineFaint.withValues(alpha: 0.35)));
    c.drawPath(pad, strokeP(BP.lineDim, 1));
  }
}

void _floor(SiteKit k, int n, double p, double lit, Color accent, {required bool slab}) {
  final c = k.c;
  final y1 = Bld.top(n - 1);
  final y0 = Bld.top(n);
  final col = strokeP(BP.lineDim, 1.4);
  final outer = strokeP(accent, 1.4);
  // Columns rise.
  final cols = Path();
  final outerCols = Path();
  for (var j = 0; j <= Bld.bays; j++) {
    final h = eo(seg01(p, j * 0.04, 0.2 + j * 0.03));
    if (h <= 0) continue;
    final x = Bld.left + j * Bld.bay;
    ((j == 0 || j == Bld.bays) ? outerCols : cols)
      ..moveTo(x, y1)
      ..lineTo(x, y1 - (y1 - y0) * h);
  }
  c.drawPath(cols, col);
  c.drawPath(outerCols, outer);
  // Slab.
  if (slab) {
    final (r, hanging) = slabAt(n, p);
    if (r != null) {
      if (hanging) {
        k.beam(r.inflate(2), color: accent);
      } else {
        c.drawLine(Offset(r.left, r.center.dy), Offset(r.right, r.center.dy), strokeP(accent, 2.6));
      }
    }
  }
  // Windows draw on.
  final w = seg01(p, 0.65, 1.0);
  if (w > 0) {
    final win = Path();
    final litPath = Path();
    for (var j = 0; j < Bld.bays; j++) {
      final r = Rect.fromLTWH(Bld.left + j * Bld.bay + 14, y0 + 16, Bld.bay - 28, Bld.floorH - 32);
      final wp = Path()
        ..addRect(r)
        ..moveTo(r.center.dx, r.top)
        ..lineTo(r.center.dx, r.bottom);
      win.addPath(w < 1 ? partialPath(wp, w) : wp, Offset.zero);
      if (lit > 0 && hash2(n.toDouble(), j.toDouble()) < lit) litPath.addRect(r.deflate(1));
    }
    c.drawPath(litPath, fillP(BP.amber.withValues(alpha: 0.1)));
    c.drawPath(litPath, strokeP(BP.amber.withValues(alpha: 0.75), 1.2));
    c.drawPath(win, strokeP(BP.lineDim, 1));
  }
  // Floor tag: "2F".
  if (p >= 1) {
    k.labels.draw(c, '${n}F', Offset(Bld.right + 16, (y0 + y1) / 2), size: 11, color: BP.inkFaint, ay: 0.5);
  }
}

void _roof(SiteKit k, double f) {
  final c = k.c;
  final y = Bld.top(Bld.floors);
  final e = eo(f);
  // Parapet + penthouse.
  final r = Rect.fromLTRB(Bld.left + 30, y - 22 * e, Bld.right - 30, y);
  c.drawRect(r, fillP(BP.paper));
  c.drawRect(r, strokeP(BP.line, 1.4));
  c.drawLine(Offset(Bld.left - 8, y), Offset(Bld.right + 8, y), strokeP(BP.line, 2.6));
  if (f < 1) return;
  // Flag pole with a waving flag.
  const px = Bld.right - 60;
  final top = y - 92;
  c.drawLine(Offset(px, y - 22), Offset(px, top), strokeP(BP.ink, 1.4));
  final flag = Path()..moveTo(px, top);
  for (var i = 0; i <= 10; i++) {
    final fx = i / 10;
    flag.lineTo(px + 44 * fx, top + 2 + math.sin(k.t * 5 - fx * 5) * 3 * fx);
  }
  for (var i = 10; i >= 0; i--) {
    final fx = i / 10;
    flag.lineTo(px + 44 * fx, top + 24 + math.sin(k.t * 5 - fx * 5) * 3 * fx);
  }
  flag.close();
  c.drawPath(flag, fillP(BP.amber.withValues(alpha: 0.85)));
}

/// Scaffold on the building's left side, up to [topY].
void paintScaffold(SiteKit k, double topY) {
  final c = k.c;
  const x0 = Bld.left - 34.0;
  const x1 = Bld.left - 6.0;
  final p = Path()
    ..moveTo(x0, Bld.ground)
    ..lineTo(x0, topY)
    ..moveTo(x1, Bld.ground)
    ..lineTo(x1, topY);
  final braces = Path();
  var prev = Bld.ground;
  var left = true;
  for (var y = Bld.ground - Bld.floorH; y >= topY - 1; y -= Bld.floorH) {
    p
      ..moveTo(x0 - 3, y)
      ..lineTo(x1 + 3, y);
    braces
      ..moveTo(left ? x0 : x1, prev)
      ..lineTo(left ? x1 : x0, y);
    left = !left;
    prev = y;
  }
  c.drawPath(p, strokeP(BP.lineDim, 1.2));
  c.drawPath(braces, strokeP(BP.lineFaint, 1));
  // Ladder.
  final l = Path()
    ..moveTo(x0 + 8, Bld.ground)
    ..lineTo(x0 + 8, topY)
    ..moveTo(x0 + 15, Bld.ground)
    ..lineTo(x0 + 15, topY);
  for (var y = Bld.ground - 8; y > topY; y -= 9) {
    l
      ..moveTo(x0 + 8, y)
      ..lineTo(x0 + 15, y);
  }
  c.drawPath(l, strokeP(BP.lineFaint, 1));
}

/// The ground of a section scene: terrain line, road lanes, earth hatch.
void paintGround(SiteKit k, {double from = 16, double to = 1584, bool pit = false}) {
  final c = k.c;
  const g = Bld.ground;
  if (pit) {
    c.drawLine(Offset(from, g), const Offset(Bld.left - 24, g), strokeP(BP.line, 1.4));
    c.drawLine(const Offset(Bld.right + 24, g), Offset(to, g), strokeP(BP.line, 1.4));
  } else {
    c.drawLine(Offset(from, g), Offset(to, g), strokeP(BP.line, 1.4));
  }
  k.dashed(Offset(from, g + 22), const Offset(Bld.left - 30, g + 22), BP.lineFaint, w: 1.2, dash: 16, gap: 12);
  c.drawLine(Offset(from, g + 46), Offset(to, g + 46), strokeP(BP.lineDim, 1));
}
