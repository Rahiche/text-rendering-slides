import 'dart:math' as math;
import 'dart:ui' show Color, FontWeight, FontVariation, Locale, Paint, PaintingStyle, Rect;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart' show Canvas, Offset, TextAlign, TextDirection, TextPainter, TextSelection, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/geometry.dart';
import 'package:text_slides/booth/craft/plan.dart' show vectorizeText, craftRasterSize, rasterPad;
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart' show OffDuty;
import 'kit.dart';
import 'motion.dart';
import 'prop_pool.dart';
import 'shot.dart';
import 'site_geo.dart';
import 'site_plan.dart';
import 'walk.dart';

/// The verdict: before the wrecking ball, the new manager arrives with two
/// planners carrying blueprint tubes. In through the site gate, they unroll
/// a blueprint of the next building — the next name in the queue (or the
/// next sample), drawn in white on blue — and hold it up in front of the
/// finished name. The foreman and the crew gather round to read it. The
/// manager turns and points at the wall: this has to make way. The foreman
/// nods and waves the crane in; the crane hooks up the wrecking ball (it
/// has been waiting by the yard) and lifts it, and only then does the
/// demolition start. The manager's party watches it from the front right,
/// and leaves during the cleanup.
///
/// It takes the demolition phase's first [CityPace.verdict] seconds; a
/// sample cut short (knocked down quickly) skips it. A pure function of
/// scene time; the blueprint's name is built once per name, a glyph a
/// frame.
class Verdict3D {
  Verdict3D(this.scene, this.crew, this.parts);

  final Scene scene;
  final Crew3D crew;
  final PropPool parts;

  /// Where the wrecking ball waits by the yard (its centre).
  static final ballRest = vm.Vector3(14.6, 1.0, 0.6);

  // The beats, in seconds into the verdict.
  static const _arrive = 4.6, _unrolled = 6.0, _gather = 4.4, _point = 10.0, _nod = 11.2, _signal = 11.8, _disperse = 12.8;

  /// When the crane goes for the ball, latches on and lifts (seconds before
  /// the verdict's end).
  static const hookFrom = 3.4, latchAt = 1.6, liftAt = 1.2;

  final _sheet = Node(name: 'blueprint');
  final _name = Node(name: 'blueprint name');
  late final PhysicallyBasedMaterial _sheetMat, _ink;

  /// The sheet's size.
  static const _w = 1.5, _h = 1.0;

  void init() {
    _ink = pbr(rgb(1, 1, 1), roughness: 0.6, emissive: rgb(1, 1, 1), emissiveStrength: 1.1);
    _sheetMat = pbr(rgb(1, 1, 1), roughness: 0.75, emissive: rgb(1, 1, 1), emissiveStrength: 0.35);
    scene
      ..add(
        _sheet
          ..castsShadows = false
          ..visible = false,
      )
      ..add(
        _name
          ..castsShadows = false
          ..visible = false,
      );
    paintedTexture(600, 400, (c, s) => _paint(c)).then((tex) {
      _sheetMat
        ..baseColorTexture = tex
        ..emissiveTexture = tex;
      _sheet.mesh = Mesh(boardGeometry(_w, _h, thick: 0.006), _sheetMat);
    });
  }

  // ── The next name ─────────────────────────────────────────────────────────

  String? _want, _built;
  List<(String, GlyphGeometry)>? _glyphs;
  final _parts = <MeshData>[];
  ({double left, double right, double top, double bottom, List<double> x})? _layout;
  int _k = 0;

  /// Builds the blueprint's name for [name] (when it changes), a glyph a
  /// frame.
  void _nameFor(String name) {
    if (name != _want) {
      _want = name;
      _glyphs = null;
      _parts.clear();
      _k = 0;
      vectorizeText(name, style: (size, color) => NameRaster.nameStyle(size, color: color)).then((g) {
        if (_want != name) return;
        _glyphs = g;
        _layout = _lay(name, g);
      });
      return;
    }
    final g = _glyphs, lay = _layout;
    if (g == null || lay == null || _built == name) return;
    if (_k < g.length) {
      final geo = g[_k].$2;
      if (!geo.isEmpty) {
        // Fitted into the drawing area, standing on its ground line.
        final k = math.min(1.12 / (lay.right - lay.left), 0.4 / (lay.bottom - lay.top));
        final mesh = extrudeGlyph(geo, unitsPerPx: k, depth: 0.004);
        final x = (lay.x[_k] - (lay.left + lay.right) / 2) * k - 0.04;
        final y = _ground + (lay.bottom - (geo.inkBottom - rasterPad)) * k;
        _parts.add(
          MeshData(
            positions: mesh.positions,
            vertexCount: mesh.vertexCount,
            normals: mesh.normals,
            texCoords: mesh.uvs,
            indices: mesh.indices,
          ).transformed(vm.Matrix4.translation(vm.Vector3(x, y, -0.007))),
        );
      }
      _k++;
      return;
    }
    _built = name;
    _name.mesh = _parts.isEmpty ? null : Mesh(MeshGeometry.fromMeshData(MeshData.merge(_parts)), _ink);
    _parts.clear();
  }

  /// The ground line on the sheet (its local y).
  static const _ground = -0.2;

  /// Where each glyph's ink centre is along the line, and the name's ink
  /// box (raster px of a [craftRasterSize] render, as the glyphs).
  static ({double left, double right, double top, double bottom, List<double> x}) _lay(String name, List<(String, GlyphGeometry)> g) {
    final tp = TextPainter(
      text: TextSpan(text: name, style: NameRaster.nameStyle(craftRasterSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final xs = <double>[];
    var left = double.infinity, right = -double.infinity, top = double.infinity, bottom = -double.infinity;
    var offset = 0, k = 0;
    for (final ch in name.characters) {
      final start = offset;
      offset += ch.length;
      if (ch.trim().isEmpty || k >= g.length) continue;
      final geo = g[k++].$2;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: offset));
      final bx = boxes.isEmpty ? 0.0 : boxes.first.left;
      xs.add(bx + (geo.inkLeft + geo.inkRight) / 2 - rasterPad);
      if (geo.isEmpty) continue;
      left = math.min(left, bx + geo.inkLeft - rasterPad);
      right = math.max(right, bx + geo.inkRight - rasterPad);
      top = math.min(top, geo.inkTop - rasterPad);
      bottom = math.max(bottom, geo.inkBottom - rasterPad);
    }
    tp.dispose();
    if (left > right) (left, right, top, bottom) = (0, 1, 0, 1);
    return (left: left, right: right, top: top, bottom: bottom, x: xs);
  }

  // ── Per frame ─────────────────────────────────────────────────────────────

  _Plan? _p;
  double _t = 0;
  double? _impact;

  /// Poses the manager's party, the blueprint and the tubes for [j] at [t];
  /// [w]: the wall's width. [held]: where someone else's scene has a
  /// builder or the foreman at a time (null: not theirs then), so the crew
  /// set off from there. Call before the crew's update.
  void update(BoothModel m, Job j, double t, {required double w, double? impact, vm.Vector3? Function(int who, double t)? held}) {
    _t = t;
    _impact = impact;
    _nameFor(m.upcoming);
    for (var i = 0; i < 3; i++) {
      crew.poses[Crew3D.manager + i].visible = false;
    }
    _sheet.visible = _name.visible = false;
    final d = _start(m, j);
    if (d == null) {
      _p = null;
      return;
    }
    var p = _p;
    if (p == null || p.d != d || p.w != w) p = _p = _Plan(d, w, crew, held);
    if (t < p.arrive.map((a) => a.start).reduce(math.min) || t >= p.leave.map((l) => l.end).reduce(math.max)) return;
    for (var i = 0; i < 3; i++) {
      _party(i, p, t);
    }
    _blueprint(p, t);
  }

  /// When this name's verdict starts (the demolition's start), or null when
  /// there's none: a cut short sample, or not yet near.
  double? _start(BoothModel m, Job j) {
    if (j.cutAt != null) return null;
    final pre = m.pace.phaseLen(Phase.demolish) - phaseSeconds[Phase.demolish]!;
    if (pre <= 0) return null;
    return switch (j.phase) {
      Phase.celebrate => j.phaseStart + j.phaseLen,
      Phase.demolish => CityPace.verdictOf(j) > 0 ? j.phaseStart : null,
      Phase.cleanup => j.phaseStart - m.pace.phaseLen(Phase.demolish),
      _ => null,
    };
  }

  // ── The manager's party ───────────────────────────────────────────────────

  static final _suit = v4(hex3(0x1C2741)), _tube = v4(hex3(0x3A5A8A)), _cap = v4(hex3(0xF4F1EA));
  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero();

  void _party(int i, _Plan p, double t) {
    final f = crew.poses[Crew3D.manager + i]
      ..rest()
      ..visible = true;
    final seed = 90 + i * 11;
    final arrive = p.arrive[i], post = p.toPost[i], leave = p.leave[i];
    if (t < arrive.end) {
      arrive.pose(f, t, seed);
      _carry(f, i, t);
      return;
    }
    if (t >= leave.start) {
      leave.pose(f, t, seed);
      _carry(f, i, t);
      return;
    }
    if (t >= post.start) {
      if (t < post.end) {
        post.pose(f, t, seed);
        _carry(f, i, t);
        return;
      }
      // Watching the demolition from the side: the manager's arms folded,
      // a flinch at the first hit.
      f.pos.setFrom(post.last);
      OffDuty.stand(f, t, seed);
      f.yaw = math.atan2(f.pos.x, f.pos.z) + Idle.facing(t, Manner.of(seed), 0.1);
      if (i == 0) {
        f.armPitch[0] = f.armPitch[1] = 1.0;
        f.armRoll[0] = f.armRoll[1] = -0.75;
      } else {
        _carry(f, i, t);
      }
      final hit = t - (_impact ?? double.infinity);
      if (hit > -0.2 && hit < 1.2) {
        // A flinch: back from it, a hand up in front.
        final k = math.sin(math.pi * c01((hit + 0.2) / 1.4));
        f.lean = -0.15 * k;
        f.handTo(0, -0.14, 0.3, -0.28, k);
      }
      return;
    }
    // At the meeting: the planners holding the blueprint up, the manager
    // presenting it, then pointing at the wall.
    f.pos.setFrom(arrive.last);
    OffDuty.stand(f, t, seed);
    final u = t - p.d;
    if (i == 0) {
      // Facing the crew (gathered at the blueprint's front right).
      final toCrew = math.atan2(-(p.x + 0.9 - f.pos.x), -(p.z - 2.0 - f.pos.z));
      f.yaw = toCrew;
      if (u < _point) {
        // Presenting it: a word to the crew, a hand that explains.
        OffDuty.talk(f, t, seed);
      } else {
        // "This has to make way": turning to the wall, pointing at it.
        final k = eio(seg(u, _point, _point + 0.6));
        f.yaw = lerp(toCrew, math.pi + 0.2, k);
        crew.point(f, 1, _b..setValues(p.x - 1.0, 3.6, 0), k);
        f.armPitch[0] = 0.15;
      }
      return;
    }
    // A planner: unrolling it (stepping apart), holding up its corners,
    // rolling it up again.
    f.yaw = 0;
    final side = i == 1 ? -1.0 : 1.0;
    final open = _open(u);
    f.pos.x = p.x + side * lerp(0.12, _w / 2 + 0.16, open);
    final top = _b..setValues(p.x + side * (_w / 2) * open, _top, p.z);
    final low = _a..setValues(p.x + side * (_w / 2) * open, _top - _h * 0.8, p.z);
    crew.aim(f, i == 1 ? 1 : 0, top);
    crew.aim(f, i == 1 ? 0 : 1, low);
    if (open < 0.05) _carry(f, i, t);
  }

  /// How far the blueprint is unrolled [u] seconds into the verdict.
  static double _open(double u) => eio(seg(u, _arrive + 0.3, _unrolled)) * (1 - eio(seg(u, _disperse, _disperse + 0.8)));

  /// The sheet's top edge, held up.
  static const _top = 1.24;

  /// A tube on a planner's shoulder; the manager's briefcase.
  void _carry(FigurePose f, int i, double t) {
    if (i == 0) {
      OffDuty.hand(f, 0, _a);
      parts.box(_a.x, _a.y - 0.1, _a.z, 0.3, 0.22, 0.07, _suit, yaw: f.yaw);
      return;
    }
    f.handTo(1, 0.2, 0.42, -0.2);
    OffDuty.hand(f, 1, _a);
    final bx = math.sin(f.yaw), bz = math.cos(f.yaw);
    _b.setValues(_a.x + bx * 0.55, _a.y + 0.38, _a.z + bz * 0.55);
    _a.setValues(_a.x - bx * 0.25, _a.y - 0.17, _a.z - bz * 0.25);
    parts.rod(_a, _b, 0.045, _tube);
    parts.rod(_b, vm.Vector3(_b.x + bx * 0.03, _b.y + 0.02, _b.z + bz * 0.03), 0.05, _cap);
  }

  // ── The blueprint ─────────────────────────────────────────────────────────

  void _blueprint(_Plan p, double t) {
    final open = _open(t - p.d);
    if (open <= 0.01) return;
    final y = _top - _h / 2 + 0.01 * math.sin(t * 1.7);
    _sheet
      ..visible = true
      ..place((m) => setTqs(m, p.x, y, p.z, _qi, open, 1, 1));
    // The rolled-up ends either side.
    for (final side in const [-1.0, 1.0]) {
      final x = p.x + side * (_w / 2) * open;
      parts.cyl(x, y, p.z, 0.035 * (1.6 - open * 0.6), _h, _tube);
    }
    if (open > 0.98 && _built == _want) {
      _name
        ..visible = true
        ..place((m) => setTrs(m, p.x, y, p.z));
    }
  }

  static final _qi = vm.Quaternion.identity();

  void _paint(Canvas c) {
    const w = 600.0, h = 400.0;
    c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF1A4F8F));
    final fine = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 1.5;
    for (var x = 20.0; x < w; x += 20) {
      c.drawLine(Offset(x, 0), Offset(x, h), x % 100 == 0 ? major : fine);
    }
    for (var y = 20.0; y < h; y += 20) {
      c.drawLine(Offset(0, y), Offset(w, y), y % 100 == 0 ? major : fine);
    }
    final line = Paint()
      ..color = const Color(0xEEFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    c.drawRect(const Rect.fromLTWH(12, 12, w - 24, h - 24), line);
    c.drawRect(const Rect.fromLTWH(20, 20, w - 40, h - 40), line..strokeWidth = 1.2);
    // The ground line the name stands on, and a dimension line over it.
    final gy = h * (0.5 - _ground / _h);
    c.drawLine(Offset(40, gy), Offset(w - 40, gy), line..strokeWidth = 2.4);
    final dim = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1.4;
    c.drawLine(const Offset(70, 46), const Offset(w - 90, 46), dim);
    for (final x in const [70.0, w - 90]) {
      c.drawLine(Offset(x, 38), Offset(x, 54), dim);
    }
    // The title block.
    const tb = Rect.fromLTWH(w - 250, h - 92, 226, 68);
    c.drawRect(tb, line..strokeWidth = 1.6);
    c.drawLine(Offset(tb.left, tb.top + 34), Offset(tb.right, tb.top + 34), line..strokeWidth = 1.2);
    _text(c, '次の建物 · NEXT BUILD', Rect.fromLTWH(tb.left + 8, tb.top + 3, tb.width - 16, 30), 26);
    _text(c, '名前の街 · NAME CITY · No.02', Rect.fromLTWH(tb.left + 8, tb.top + 37, tb.width - 16, 28), 20);
  }

  void _text(Canvas c, String s, Rect box, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: BP.display,
          fontSize: size,
          color: const Color(0xFFFFFFFF),
          locale: const Locale('ja'),
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 680)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: box.width * 3);
    final k = math.min(1.0, math.min(box.width / tp.width, box.height / tp.height));
    c.save();
    c.translate(box.center.dx, box.center.dy);
    c.scale(k);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }

  // ── The crew ──────────────────────────────────────────────────────────────

  /// The crew's stage hook: the builders and the foreman gather round the
  /// blueprint, look up at the wall when the manager points, and go back to
  /// their places; the foreman nods and waves the crane in, and the
  /// operator waves back.
  void pose(int who, FigurePose f) {
    final p = _p;
    if (p == null) return;
    final t = _t, u = t - p.d;
    if (who == Crew3D.operator) {
      // A nod back from the cab.
      f.headPitch += 0.2 * math.sin(math.pi * 2 * seg(u, _signal + 0.4, _signal + 1.2)).abs();
      return;
    }
    final walk = p.crew[who];
    if (walk == null || t < walk.go.start || t >= walk.back.end) return;
    final seed = who * 13 + 5;
    final foreman = who == Crew3D.foreman;
    f.rest();
    if (t < walk.go.end) {
      walk.go.pose(f, t, seed);
      f.clipboard = foreman;
      if (foreman) f.armPitch[0] = 1.0;
      return;
    }
    if (t >= walk.back.start) {
      walk.back.pose(f, t, seed);
      f.clipboard = foreman;
      if (foreman) f.armPitch[0] = 1.0;
      return;
    }
    // Round the blueprint, reading it.
    f.pos.setFrom(walk.go.last);
    OffDuty.stand(f, t, seed);
    f.yaw = math.atan2(-(p.x - f.pos.x), -(p.z - f.pos.z));
    final up = eio(seg(u, _point + 0.2, _point + 0.9));
    f.lean = lerp(0.1, -0.16, up);
    if (!foreman) {
      if (u < _point) {
        if ((who + (t / 2.6).floor()) % 4 == 0) {
          OffDuty.talk(f, t, seed);
        } else {
          OffDuty.listen(f, t, seed);
        }
      } else if (who.isEven) {
        // Up at the wall: hands on the hips.
        for (var s = 0; s < 2; s++) {
          f.armPitch[s] = lerp(f.armPitch[s], -0.3, up);
          f.armRoll[s] = lerp(f.armRoll[s], 0.85, up);
        }
      }
      return;
    }
    // The foreman: his clipboard up, reading; then two nods, and a beckon
    // to the crane.
    f.clipboard = true;
    f.armPitch[0] = 1.15;
    f.armRoll[0] = -0.15;
    final nod = seg(u, _nod, _nod + 0.6);
    if (nod > 0 && nod < 1) f.lean = 0.25 * math.sin(nod * math.pi * 2).abs();
    final wave = seg(u, _signal, _signal + 0.3) * (1 - seg(u, _disperse - 0.2, _disperse));
    if (wave > 0) {
      f.yaw = lerp(f.yaw, math.atan2(-(13 - f.pos.x), -(4.3 - f.pos.z)), wave);
      f.headPitch -= 0.3 * wave;
      f.handTo(1, 0.24, 0.28, -0.3 - 0.08 * math.sin(t * 7), wave);
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// The camera's requests (priority 2, cuts): following the party in, the
  /// unrolling, past the foreman at the blueprint, the crew's reaction as
  /// the manager points at the wall, the crane taking the ball.
  void focus(List<Focus> out, double t) {
    final p = _p;
    if (p == null) return;
    final u = t - p.d;
    if (u < 0 || u >= CityPace.verdict) return;
    final Shot shot;
    final String id;
    if (u < _arrive) {
      // From inside the plaza: in through the gate they come, towards us,
      // stopping a few steps short.
      final m = crew.poses[Crew3D.manager].pos;
      id = 'verdict arrive';
      shot = Shot(vm.Vector3(p.x - 4.2, 1.7, p.z - 2.2), vm.Vector3(m.x, 1.0, m.z), fov: 44, settle: 1.2, drift: 0.5);
    } else if (u < _unrolled + 0.2) {
      id = 'verdict unroll';
      shot = Shot(vm.Vector3(p.x + 0.9, 1.45, p.z - 4.0), vm.Vector3(p.x + 0.35, 0.95, p.z), fov: 42, settle: 1.4, drift: 0.4);
    } else if (u < _point) {
      // At eye height past the foreman (on the left, his clipboard clear of
      // it): the next name, readable, the planners over it.
      id = 'verdict read';
      shot = Shot(vm.Vector3(p.x + 0.1, 1.55, p.z - 3.4), vm.Vector3(p.x - 0.05, 0.95, p.z), fov: 38, settle: 1.2, drift: 0.3);
    } else if (u < _disperse - 0.2) {
      // From low at the left front: the manager pointing up at the name
      // towering over them, the crew looking up at it.
      id = 'verdict point';
      shot = Shot(vm.Vector3(p.x - 4.0, 0.95, p.z - 2.4), vm.Vector3(p.x - 0.4, 2.6, p.z + 1.8), fov: 52, settle: 1.6, drift: 0.5);
    } else {
      // The crane takes the ball.
      final b = ballRest;
      id = 'verdict ball';
      shot = Shot(vm.Vector3(b.x - 6.6, 2.4, b.z - 7.6), vm.Vector3(b.x - 1.2, 3.2, b.z), fov: 48, settle: 1.6, drift: 0.5);
    }
    out.add(Focus(id, shot, priority: 2));
  }

  /// How far the site gate should be open for the party at [t].
  double gateOpen(double t) {
    final p = _p;
    if (p == null) return 0;
    var open = 0.0;
    for (final (a, e) in p.gate) {
      open = math.max(open, seg(t, a - 1.2, a) * (1 - seg(t, e, e + 1.2)));
    }
    return open;
  }
}

/// The verdict starting at [d], for a wall [w] wide: where the blueprint is
/// held up, the party's walks (in, to their place to watch, out), the
/// crew's walks round the blueprint and back (from wherever [held] has them
/// when they set off: back from a photo cut short, say).
class _Plan {
  _Plan(this.d, this.w, Crew3D figures, vm.Vector3? Function(int who, double t)? held) : x = (w / 2 - 1.0).clamp(2.6, 8.6), z = -3.3 {
    // The party: along the front pavement from the east, in through the
    // site gate, to the blueprint's place; the manager in front.
    const gx = 13.0;
    final spots = [vm.Vector3(x - 1.4, 0, z - 0.3), vm.Vector3(x - 0.12, 0, z + 0.05), vm.Vector3(x + 0.12, 0, z + 0.05)];
    for (var i = 0; i < 3; i++) {
      final lag = i * 0.55, side = i == 0 ? 0.0 : (i == 1 ? -0.35 : 0.35);
      final pts = [vm.Vector3(19.4 + lag, 0, -10.3 + side * 0.5), vm.Vector3(gx + side, 0, -10.3 + side * 0.5), vm.Vector3(gx + side, 0, -6.2), spots[i]];
      // Arriving at the blueprint's place by [_arrive].
      final speed = 1.55;
      final start = d + Verdict3D._arrive - Walk.lengthOf(pts) / speed - lag * 0.6;
      arrive.add(Walk(pts, start, speed));
      // Then to the front right to watch, out of the way.
      final post = vm.Vector3(math.min(w / 2 + 2.3, 12.4) + 0.62 * i, 0, -4.4 - 0.4 * (i % 2));
      toPost.add(Walk([spots[i], post], d + Verdict3D._disperse + 0.5 + 0.2 * i, 1.3));
      // And away during the cleanup, the way they came.
      final out = [post, vm.Vector3(gx + side, 0, -6.2), vm.Vector3(gx + side, 0, -10.3 + side * 0.5), vm.Vector3(21 + lag, 0, -10.3 + side * 0.5)];
      leave.add(Walk(out, d + CityPace.verdict + phaseSeconds[Phase.demolish]! + 1.5 + 0.3 * i, 1.4));
    }
    gate
      ..add((arrive[0].at(1), arrive[2].at(2)))
      ..add((leave[0].at(1), leave[2].at(2)));
    // The crew round the blueprint's right front (the side they come
    // from: nobody crosses in front of it), in two staggered rows nearest
    // first; the foreman at its left front, the camera past him.
    final order = List.generate(Crew3D.builders, (z0) => z0)..sort((a, b) => figures.watchSpot(a, w).x.compareTo(figures.watchSpot(b, w).x));
    const arc = [(28.0, 1.9), (34.0, 2.7), (52.0, 1.9), (56.0, 2.7), (76.0, 1.9), (78.0, 2.7)];
    for (var r = 0; r < Crew3D.builders; r++) {
      final z0 = order[r];
      final a = arc[r].$1 * math.pi / 180, rad = arc[r].$2;
      final at = vm.Vector3(x + rad * math.sin(a), 0, z - rad * math.cos(a));
      final from = figures.watchSpot(z0, w);
      final face = math.atan2(-(x - at.x), -(z - at.z));
      final start = d + Verdict3D._gather + 0.15 * r;
      final go = Walk([held?.call(z0, start) ?? from, at], start, 1.6, face: face);
      final back = Walk([at, from], d + Verdict3D._disperse + 0.12 * r, 1.9, face: math.atan2(from.x, from.z));
      crew[z0] = (go: go, back: back);
    }
    // The foreman round the blueprint's right to its left front (straight
    // there if he comes from the left), there before it's unrolled.
    final fAt = vm.Vector3(x - 0.55, 0, z - 1.5), via = vm.Vector3(x + 1.5, 0, z - 1.7);
    final fFrom = vm.Vector3(w / 2 + 0.75, 0, -1.55);
    final fStart = d + 1.5, here = held?.call(Crew3D.foreman, fStart);
    final fWay = here == null ? [fFrom, via, fAt] : (here.x > x ? [here, via, fAt] : [here, fAt]);
    // Back round the far side of the blueprint and behind it (not across
    // the planners' and the builders' ways out), briskly: clear before the
    // ball swings.
    crew[Crew3D.foreman] = (
      go: Walk(fWay, fStart, (Walk.lengthOf(fWay) / (Verdict3D._arrive - 1.5)).clamp(1.8, 2.6), face: math.pi),
      back: Walk([fAt, vm.Vector3(x - 2.2, 0, z - 0.9), vm.Vector3(x - 2.2, 0, -1.75), vm.Vector3(fFrom.x, 0, -1.75), fFrom], d + Verdict3D._disperse + 0.2, 2.3, face: 0.8),
    );
  }

  final double d, w;

  /// Where the blueprint is held up (its middle, on the ground).
  final double x, z;
  final arrive = <Walk>[], toPost = <Walk>[], leave = <Walk>[];
  final crew = <int, ({Walk go, Walk back})>{};

  /// When the gate stands open for them, in and out.
  final gate = <(double, double)>[];
}
