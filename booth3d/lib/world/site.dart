import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextDirection, TextSelection;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/geometry.dart';
import 'package:text_slides/booth/craft/plan.dart' show vectorizeText, craftRasterSize, rasterPad;
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

/// The name being built in the plaza: a wall of the name's real raster
/// pixels as bricks dropped from a tower crane, the smooth extruded letters
/// rising through it (pixels → outlines), fireworks, a wrecking ball, and
/// the rubble hauled away.
class Site3D {
  Site3D(this.scene);

  final Scene scene;

  // Wall: one instanced cube per raster pixel.
  late final InstancedMesh _bricks;
  // Smooth letters (one node per character of the current name).
  final _letters = <Node>[];
  final _letterMats = <PhysicallyBasedMaterial>[];
  final _letterRoot = Node(name: 'letters');

  // Crane.
  final _crane = Node(name: 'crane');
  final _trolley = Node(name: 'trolley');
  final _cable = Node(name: 'cable');
  final _hook = Node(name: 'hook');
  final _ball = Node(name: 'wrecking ball');

  // Fireworks: a few instanced batches of glowing sparks, one colour each.
  final _sparks = <InstancedMesh>[];
  static const _bursts = 7, _perBurst = 42;

  // Recycling truck.
  final _truck = Node(name: 'truck');

  // Per-job state.
  Job? _job;
  NameRaster? _r;
  int _placed = 0;
  int _shown = 0; // instances currently holding a real brick
  double b = 0.25; // brick size
  List<(String, GlyphGeometry)>? _glyphs;
  bool _lettersBuilt = false;
  List<_Fall>? _falls;

  /// Where the hook is now (bricks drop from it).
  vm.Vector3 hookAt = vm.Vector3(4, 10, 0);

  /// Bounds of the wall (for the camera).
  double wallWidth = 12, wallHeight = 5;

  void init() {
    final brickMat = pbr(rgb(1, 1, 1), roughness: 0.55);
    _bricks = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: brickMat);
    scene.add(Node(name: 'bricks')..addComponent(InstancedMeshComponent(_bricks)));
    scene.add(_letterRoot);
    _buildCrane();
    _buildTruck();
    const colors = [BP.amber, BP.pink, BP.green, BP.line, BP.violet, BP.coral, Color(0xFFFFFFFF)];
    for (var k = 0; k < _bursts; k++) {
      final mat = pbr(lin(colors[k % colors.length]), emissive: lin(colors[k % colors.length]), emissiveStrength: 14);
      final im = InstancedMesh(geometry: SphereGeometry(radius: 0.5, segments: 8, rings: 6), material: mat);
      for (var i = 0; i < _perBurst; i++) {
        im.addInstance(hidden);
      }
      _sparks.add(im);
      scene.add(Node(name: 'sparks $k')..addComponent(InstancedMeshComponent(im)));
    }
  }

  // ── Crane & truck ─────────────────────────────────────────────────────────

  static const _mastX = 13.0, _mastZ = 3.2, _jibY = 15.0;

  void _buildCrane() {
    final yellow = pbr(lin(const Color(0xFFFFC66D)), roughness: 0.5, metallic: 0.2);
    final dark = pbr(rgb(0.08, 0.1, 0.14), roughness: 0.6, metallic: 0.4);
    _crane.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.7, _jibY, 0.7)), yellow), localTransform: trs(vm.Vector3(_mastX, _jibY / 2, _mastZ))));
    // Jib towards the plaza and the counter-jib behind.
    _crane.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(26, 0.55, 0.55)), yellow), localTransform: trs(vm.Vector3(_mastX - 9, _jibY + 0.3, _mastZ))));
    _crane.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.6, 1.4, 1.2)), dark), localTransform: trs(vm.Vector3(_mastX + 4.8, _jibY - 0.2, _mastZ))));
    _crane.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.4, 1.1, 1.1)), pbr(lin(BP.line), roughness: 0.3)), localTransform: trs(vm.Vector3(_mastX - 0.2, _jibY - 0.6, _mastZ - 0.6))));
    _trolley.mesh = Mesh(CuboidGeometry(vm.Vector3(0.9, 0.4, 0.9)), dark);
    _crane.add(_trolley);
    _cable.mesh = Mesh(CylinderGeometry(bottomRadius: 0.03, topRadius: 0.03, height: 1), dark);
    _crane.add(_cable);
    _hook.mesh = Mesh(CuboidGeometry(vm.Vector3(0.35, 0.45, 0.35)), yellow);
    _crane.add(_hook);
    _ball.mesh = Mesh(SphereGeometry(radius: 0.9), pbr(rgb(0.05, 0.05, 0.06), metallic: 0.8, roughness: 0.35));
    _ball.visible = false;
    _crane.add(_ball);
    scene.add(_crane);
  }

  void _buildTruck() {
    final body = pbr(lin(BP.green), roughness: 0.5);
    final dark = pbr(rgb(0.04, 0.05, 0.07), roughness: 0.8);
    _truck.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(4.2, 1.6, 2.2)), body), localTransform: trs(vm.Vector3(-0.6, 1.4, 0))));
    _truck.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.6, 1.8, 2.2)), pbr(lin(BP.amber), roughness: 0.4)), localTransform: trs(vm.Vector3(2.4, 1.5, 0))));
    for (final x in [-1.8, 0.4, 2.4]) {
      for (final z in [-1.1, 1.1]) {
        _truck.add(Node(mesh: Mesh(CylinderGeometry(bottomRadius: 0.45, topRadius: 0.45, height: 0.35), dark), localTransform: trs(vm.Vector3(x, 0.45, z), rotX: math.pi / 2)));
      }
    }
    _truck.visible = false;
    scene.add(_truck);
  }

  void _placeHook(vm.Vector3 hook, {bool ball = false}) {
    hookAt = hook;
    _trolley.localTransform = trs(vm.Vector3(hook.x, _jibY - 0.1, _mastZ + 0.0));
    final top = vm.Vector3(hook.x, _jibY - 0.3, _mastZ);
    final d = hook - top;
    final len = d.length;
    // Cable: a unit cylinder along Y, scaled to length and aimed at the hook.
    final up = vm.Vector3(0, -1, 0);
    final q = vm.Quaternion.fromTwoVectors(up, d.normalized());
    _cable.localTransform = trsQ(top + d * 0.5, q * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi), vm.Vector3(1, len, 1));
    _hook.localTransform = trs(hook);
    _ball.visible = ball;
    if (ball) _ball.localTransform = trs(hook + vm.Vector3(0, -1.0, 0));
  }

  // ── Per job ───────────────────────────────────────────────────────────────

  void _startJob(Job j) {
    _job = j;
    _r = null;
    _glyphs = null;
    _lettersBuilt = false;
    _falls = null;
    _placed = 0;
    for (final n in _letters) {
      _letterRoot.remove(n);
    }
    _letters.clear();
    _letterMats.clear();
    _bricks.clearInstances();
    _shown = 0;
    vectorizeText(j.name, style: (size, color) => NameRaster.nameStyle(size, color: color)).then((g) {
      if (identical(_job, j)) _glyphs = g;
    });
  }

  void _setupRaster(NameRaster r) {
    _r = r;
    b = math.min(0.32, math.min(19.0 / r.cols, 7.6 / r.rows));
    wallWidth = r.cols * b;
    wallHeight = r.rows * b;
    for (var i = 0; i < r.bricks.length; i++) {
      final k = r.bricks[i];
      _bricks.addInstance(hidden, color: _brickColor(k));
    }
  }

  vm.Vector4 _brickColor(Brick k) {
    final full = rgb(0.86, 0.83, 0.76);
    final glass = rgb(0.12, 0.33, 0.85);
    final f = c01((k.cover - 0.15) / 0.7);
    return glass + (full - glass) * f;
  }

  vm.Vector3 cell(Brick k) {
    final r = _r!;
    return vm.Vector3((k.col - r.cols / 2 + 0.5) * b, (r.rows - k.row - 0.5) * b, 0);
  }

  vm.Matrix4 _at(vm.Vector3 p, [double s = 1, vm.Quaternion? q]) => trsQ(p, q ?? vm.Quaternion.identity(), vm.Vector3.all(b * 0.96 * s));

  /// The smooth letters, placed exactly over the raster.
  void _buildLetters() {
    final r = _r!, g = _glyphs!;
    final tp = TextPainter(
      text: TextSpan(text: r.name, style: NameRaster.nameStyle(r.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final s = r.fontSize / craftRasterSize;
    var offset = 0;
    var k = 0;
    for (final ch in r.name.characters) {
      if (ch.trim().isEmpty) {
        offset += ch.length;
        continue;
      }
      if (k >= g.length) break;
      final geo = g[k++].$2;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: offset, extentOffset: offset + ch.length));
      offset += ch.length;
      if (geo.isEmpty || boxes.isEmpty) continue;
      final mesh = extrudeGlyph(geo, unitsPerPx: s * b, depth: b * 1.7);
      // Ink centre-bottom of this glyph, in the name's raster px.
      final px = boxes.first.left + ((geo.inkLeft + geo.inkRight) / 2 - rasterPad) * s - r.inkOffset.dx;
      final py = (geo.inkBottom - rasterPad) * s - r.inkOffset.dy;
      final at = vm.Vector3((px - r.cols / 2) * b, (r.rows - py) * b, 0);
      final hue = [BP.amber, BP.line, BP.green, BP.pink, BP.violet, BP.coral][k % 6];
      final mat = pbr(lin(const Color(0xFFF4F1EA)), roughness: 0.32, metallic: 0.05, emissive: lin(hue), emissiveStrength: 0);
      final node = Node(name: 'letter $ch', mesh: Mesh(glyphGeometry(mesh), mat), localTransform: trs(at));
      node.visible = false;
      _letters.add(node);
      _letterMats.add(mat);
      _letterRoot.add(node);
    }
    tp.dispose();
    _lettersBuilt = true;
  }

  // ── Update ────────────────────────────────────────────────────────────────

  void update(BoothModel m, double dt) {
    final j = m.job;
    final t = m.t;
    if (j == null) return;
    if (!identical(j, _job)) _startJob(j);
    final r = j.raster;
    if (r != null && _r == null) _setupRaster(r);
    if (_r != null && _glyphs != null && !_lettersBuilt) _buildLetters();

    _truck.visible = false;
    for (final im in _sparks) {
      if (im.instanceCount > 0 && _sparksOn) {
        for (var i = 0; i < im.instanceCount; i++) {
          im.setInstanceTransform(i, hidden);
        }
      }
    }
    _sparksOn = false;

    switch (j.phase) {
      case Phase.intake:
        _placeHook(vm.Vector3(_mastX - 6, 6 + 1.5 * math.sin(t), _mastZ - 1));
      case Phase.build:
        _build(j, t);
      case Phase.reveal:
        _showAll(j);
        _reveal(j.progress(t));
        _placeHook(vm.Vector3(_mastX - 4, _jibY - 4, _mastZ - 1));
      case Phase.celebrate:
        _reveal(1);
        _celebrate(j, t);
        _placeHook(vm.Vector3(_mastX - 4, _jibY - 4, _mastZ - 1));
      case Phase.demolish:
        _demolish(j, t);
      case Phase.cleanup:
        _cleanup(j, t);
    }
  }

  bool _sparksOn = false;

  void _build(Job j, double t) {
    final r = _r;
    if (r == null) return;
    final laid = j.laid(t);
    for (; _placed < laid && _placed < r.bricks.length; _placed++) {
      _bricks.setInstanceTransform(_placed, _at(cell(r.bricks[_placed])));
    }
    _shown = math.max(_shown, _placed);
    // Bricks in the air: from the hook to their cell over 0.7 s.
    var focus = _placed < r.bricks.length ? cell(r.bricks[_placed]) : vm.Vector3(0, wallHeight, 0);
    for (var n = _placed; n < math.min(r.bricks.length, _placed + 40); n++) {
      final at = j.brickTime(n);
      if (at == null || t < at - 0.7) break;
      final f = c01((t - (at - 0.7)) / 0.7);
      final end = cell(r.bricks[n]);
      final start = hookAt + vm.Vector3(0, -0.5, 0);
      final p = start + (end - start) * eio(f) + vm.Vector3(0, 1.2 * math.sin(f * math.pi), 0);
      _bricks.setInstanceTransform(n, _at(p, 1, vm.Quaternion.axisAngle(vm.Vector3(0.3, 1, 0.2).normalized(), (1 - f) * 4)));
      _shown = math.max(_shown, n + 1);
    }
    // The hook hovers above where the bricks are going.
    final hx = focus.x.clamp(-wallWidth / 2, wallWidth / 2) + 0.6 * math.sin(t * 0.7);
    _placeHook(vm.Vector3(hx, focus.y + 2.6 + 0.25 * math.sin(t * 1.3), -0.4));
  }

  /// All laid bricks in place (after a fast-forward or cut).
  void _showAll(Job j) {
    final r = _r;
    if (r == null) return;
    final n = j.cutAt ?? r.bricks.length;
    for (; _placed < n; _placed++) {
      _bricks.setInstanceTransform(_placed, _at(cell(r.bricks[_placed])));
    }
  }

  /// Bricks shrink row by row from the bottom while the smooth letters rise.
  void _reveal(double p) {
    final r = _r;
    if (r == null) return;
    final level = p * 1.25; // 0 → rows+
    for (var i = 0; i < _placed; i++) {
      final k = r.bricks[i];
      final h = (r.rows - k.row) / r.rows; // 0 bottom … 1 top
      final s = 1 - seg(level - h, 0, 0.18);
      _bricks.setInstanceTransform(i, s <= 0 ? hidden : _at(cell(k), s));
    }
    final rise = eo(seg(p, 0.05, 0.95));
    for (final n in _letters) {
      n.visible = rise > 0;
      final at = n.localTransform.getTranslation();
      n.localTransform = trs(at, s: vm.Vector3(1, math.max(0.001, rise), 1));
    }
  }

  void _celebrate(Job j, double t) {
    final u = j.since(t);
    for (var i = 0; i < _letterMats.length; i++) {
      final pulse = 0.5 + 0.5 * math.sin(u * 4 - i * 0.7);
      _letterMats[i].emissiveStrength = 0.15 + 0.6 * pulse * (1 - seg(u, 10, 14));
    }
    _sparksOn = true;
    for (var k = 0; k < _bursts; k++) {
      final im = _sparks[k];
      final start = 0.6 + k * 1.5;
      final tau = u - start;
      final center = vm.Vector3((rnd(k, j.serial) - 0.5) * wallWidth * 1.2, wallHeight + 3 + 3 * rnd(k, 3), 1 + 2 * rnd(k, 5));
      for (var i = 0; i < _perBurst; i++) {
        if (tau < 0 || tau > 2.2) {
          im.setInstanceTransform(i, hidden);
          continue;
        }
        // Fibonacci sphere directions.
        final y = 1 - 2 * (i + 0.5) / _perBurst;
        final rr = math.sqrt(1 - y * y);
        final a = i * 2.39996;
        final d = vm.Vector3(math.cos(a) * rr, y, math.sin(a) * rr);
        final p = center + d * (6.5 * eo(tau / 1.1)) + vm.Vector3(0, -1.4 * tau * tau, 0);
        final s = 0.32 * (1 - seg(tau, 0.9, 2.2));
        im.setInstanceTransform(i, s <= 0 ? hidden : trs(p, s: vm.Vector3.all(s)));
      }
    }
  }

  // ── Demolition: a wrecking ball, then ballistic bricks ─────────────────────

  void _demolish(Job j, double t) {
    final r = _r;
    if (r == null) return;
    for (final n in _letters) {
      n.visible = false;
    }
    final len = math.max(j.phaseLen, 0.01);
    final u = j.since(t);
    _falls ??= _planFalls(j, len);
    // Ball: swings from the right, through the wall at mid height, to the left.
    final swing = seg(u, len * 0.05, len * 0.55);
    final bx = lerp(wallWidth / 2 + 5, -wallWidth / 2 - 4, eio(swing));
    final by = wallHeight * 0.45 + 2.5 * math.sin(swing * math.pi) * 0.3;
    _placeHook(vm.Vector3(bx, by + 2.2, 0.0), ball: true);
    for (var i = 0; i < _falls!.length; i++) {
      _bricks.setInstanceTransform(i, _falls![i].at(u, b));
    }
  }

  List<_Fall> _planFalls(Job j, double len) {
    final r = _r!;
    final n = j.cutAt ?? r.bricks.length;
    final out = <_Fall>[];
    for (var i = 0; i < r.bricks.length; i++) {
      final k = r.bricks[i];
      final p = cell(k);
      if (i >= n) {
        out.add(_Fall.never());
        continue;
      }
      // The ball passes x = p.x at this fraction of the swing.
      final pass = (wallWidth / 2 + 5 - p.x) / (wallWidth + 9);
      final hit = (p.y - wallHeight * 0.45).abs() < 1.6;
      final release = len * (0.05 + 0.5 * eio(pass)) + (hit ? 0 : 0.25 + 0.6 * rnd(i, 2)) + (wallHeight - p.y) * 0.03;
      final v = vm.Vector3(
        -3.5 * (hit ? 1.6 : 0.6) + (rnd(i, 7) - 0.5) * 3,
        (hit ? 3.5 : 0.8) * rnd(i, 9),
        (rnd(i, 11) - 0.5) * (hit ? 6 : 2.5),
      );
      out.add(_Fall(p, v, release, vm.Vector3(rnd(i, 3) - 0.5, rnd(i, 4) - 0.5, rnd(i, 5) - 0.5).normalized(), 3 + 6 * rnd(i, 6)));
    }
    return out;
  }

  // ── Cleanup: rubble flies into the recycling truck ─────────────────────────

  void _cleanup(Job j, double t) {
    final len = math.max(j.phaseLen, 0.01);
    final u = j.since(t);
    // The ball is unhooked; the hook goes back up.
    _placeHook(vm.Vector3(lerp(-wallWidth / 2 - 4, _mastX - 5, eio(u / len)), lerp(4, _jibY - 4, eio(u / len)), -1));
    final falls = _falls;
    if (falls == null) return;
    final f = u / len;
    // The truck comes in from the left, waits, and leaves to the right.
    final tx = f < 0.2 ? lerp(-wallWidth - 16, -wallWidth / 2 - 3, eo(f / 0.2)) : (f > 0.82 ? lerp(-wallWidth / 2 - 3, wallWidth + 20, (f - 0.82) / 0.18) : -wallWidth / 2 - 3);
    final truckAt = vm.Vector3(tx, 0, -4.5);
    _truck.visible = true;
    _truck.localTransform = trs(truckAt);
    final hopper = truckAt + vm.Vector3(-0.6, 2.4, 0);
    for (var i = 0; i < falls.length; i++) {
      final fall = falls[i];
      if (!fall.ever) {
        _bricks.setInstanceTransform(i, hidden);
        continue;
      }
      final rest = fall.restPoint(b);
      final go = len * (0.2 + 0.55 * rnd(i, 13));
      final k = seg(u, go, go + 0.9);
      if (k <= 0) {
        _bricks.setInstanceTransform(i, fall.at(99, b));
      } else if (k >= 1) {
        _bricks.setInstanceTransform(i, hidden);
      } else {
        final p = rest + (hopper - rest) * eio(k) + vm.Vector3(0, 2.2 * math.sin(k * math.pi), 0);
        _bricks.setInstanceTransform(i, trs(p, s: vm.Vector3.all(b * 0.96 * (1 - 0.4 * k))));
      }
    }
  }

  /// Where the camera should look while building (the top of the wall).
  vm.Vector3 get focus => vm.Vector3(0, wallHeight * 0.55, 0);
}

/// One brick's flight after the ball: ballistic, a bounce, then rest.
class _Fall {
  _Fall(this.p0, this.v0, this.release, this.axis, this.spin) : ever = true;
  _Fall.never()
    : p0 = vm.Vector3.zero(),
      v0 = vm.Vector3.zero(),
      release = 1e9,
      axis = vm.Vector3(0, 1, 0),
      spin = 0,
      ever = false;

  final vm.Vector3 p0, v0, axis;
  final double release, spin;
  final bool ever;
  static const g = 9.8;

  /// Time from release to first touching the ground (y = b/2).
  double _land(double b) {
    final y0 = p0.y - b / 2;
    // y0 + vy t − g t²/2 = 0
    final vy = v0.y;
    return (vy + math.sqrt(vy * vy + 2 * g * math.max(0, y0))) / g;
  }

  vm.Vector3 restPoint(double b) {
    final tl = _land(b);
    final h = vm.Vector3(v0.x, 0, v0.z);
    return vm.Vector3(p0.x + h.x * tl, b / 2, p0.z + h.z * tl) + vm.Vector3(h.x, 0, h.z) * 0.25;
  }

  vm.Matrix4 at(double u, double b) {
    if (!ever) return hidden;
    final s = vm.Vector3.all(b * 0.96);
    final tau = u - release;
    if (tau <= 0) return trsQ(p0, vm.Quaternion.identity(), s);
    final tl = _land(b);
    if (tau < tl) {
      final p = p0 + v0 * tau + vm.Vector3(0, -0.5 * g * tau * tau, 0);
      return trsQ(p, vm.Quaternion.axisAngle(axis, spin * tau), s);
    }
    // After landing: one small hop and a slide to rest.
    final after = tau - tl;
    final land = vm.Vector3(p0.x + v0.x * tl, b / 2, p0.z + v0.z * tl);
    final slide = vm.Vector3(v0.x, 0, v0.z) * (0.25 * (1 - math.exp(-after * 4)));
    final hop = math.max(0.0, 0.6 * math.sin(math.min(after, 0.35) / 0.35 * math.pi)) * (v0.y.abs() + 1) * 0.15;
    final ang = spin * tl + spin * 0.3 * (1 - math.exp(-after * 3));
    return trsQ(land + slide + vm.Vector3(0, hop, 0), vm.Quaternion.axisAngle(axis, ang), s);
  }
}
