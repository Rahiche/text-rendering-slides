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

import 'crew.dart';
import 'kit.dart';
import 'site_crane.dart';
import 'site_fx.dart';
import 'site_geo.dart';
import 'site_lights.dart';
import 'site_plan.dart';

/// The name being built in the plaza.
///
/// A tower crane brings the name's bricks (its real raster pixels) from the
/// yard on pallets and drops them, a batch at a time, onto the piles of six
/// builders on a climbing platform behind the wall; the builders lay them
/// row by row. Then a glowing scan plane sweeps up and the pixels dissolve
/// into smooth extruded letters (pixels → outlines), fireworks burst (some
/// in the shapes of the name's own characters), confetti flies and the
/// crane lowers a 完成！ sign; a wrecking ball swings through the wall, and
/// a recycling truck hauls the rubble away.
class Site3D {
  Site3D(this.scene);

  final Scene scene;

  late final crane = Crane3D(scene);
  late final crew = Crew3D(scene);
  late final fx = Fx3D(scene);
  late final lights = SiteLights(scene);

  // Every brick of the name, wherever it is (yard, crane, pile, wall…).
  late final InstancedMesh _bricks;
  late final InstancedMesh _pallets;
  static const _maxPallets = 12;

  // Smooth letters.
  final _letterRoot = Node(name: 'letters');
  final _letters = <_Letter>[];

  // 完成！ sign and the recycling truck.
  final _banner = Node(name: 'banner 完成');
  final _truck = Node(name: 'truck');
  late final PhysicallyBasedMaterial _truckBeacon, _bannerGlow;

  // Shapes for glyph fireworks: other scripts (once) and the name (per job).
  var _scriptShapes = <List<vm.Vector2>>[];
  var _nameShapes = <List<vm.Vector2>>[];

  // ── Per job ───────────────────────────────────────────────────────────────
  Job? _job;
  NameRaster? _r;
  BuildPlan? _plan;
  List<(String, GlyphGeometry)>? _glyphs;
  int _lettersMade = 0;
  bool _lettersReady = false;
  List<_Fall>? _falls;
  List<int>? _landOrder;
  _Swing? _swing;
  int _finalized = 0;
  bool _yardDone = false;
  bool _wallHidden = false;
  double b = 0.25;

  /// Bounds of the wall (for the camera).
  double wallWidth = 12, wallHeight = 5;

  /// What the camera may want to look at.
  final hookAt = vm.Vector3(4, 10, 0);
  double level = 0;
  double scanY = -1;

  /// When the ball first hits the wall (scene time), once known.
  double? impactAt;
  final ballAt = vm.Vector3.zero();
  final truckAt = vm.Vector3(-40, 0, -4.5);

  void init() {
    _bricks = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(rgb(1, 1, 1), roughness: 0.55));
    scene.add(Node(name: 'bricks')..addComponent(InstancedMeshComponent(_bricks)));
    _pallets = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(lin(const Color(0xFFA77445)), roughness: 0.85));
    for (var i = 0; i < _maxPallets; i++) {
      _pallets.addInstance(hidden);
    }
    scene.add(Node(name: 'pallets')..addComponent(InstancedMeshComponent(_pallets)));
    scene.add(_letterRoot);
    crane.init();
    crew.init();
    fx.init();
    lights.init();
    _buildTruck();
    _buildBanner();
    vectorizeText('Aあ字ЖΩب한कก♥').then((gs) {
      _scriptShapes = [
        for (final g in gs)
          if (!g.$2.isEmpty) Fx3D.shapeOf(g.$2),
      ]..removeWhere((s) => s.length < 20);
    });
  }

  // ── Truck & banner ────────────────────────────────────────────────────────

  void _buildTruck() {
    final body = pbr(lin(BP.green), roughness: 0.45, metallic: 0.15);
    final cab = pbr(lin(BP.amber), roughness: 0.4, metallic: 0.15);
    final dark = pbr(rgb(0.03, 0.035, 0.05), roughness: 0.75);
    final glass = pbr(rgb(0.08, 0.16, 0.24), roughness: 0.1, metallic: 0.3);
    final steel = pbr(rgb(0.6, 0.62, 0.66), roughness: 0.35, metallic: 0.8);
    final chassis = MeshBatch()..box(vm.Vector3(0.1, 0.62, 0), vm.Vector3(5.6, 0.32, 1.7));
    _truck.add(Node(mesh: Mesh(chassis.build(), dark)));
    // Tipper body with ribs.
    final tub = MeshBatch()
      ..box(vm.Vector3(-0.85, 1.05, 0), vm.Vector3(3.6, 0.14, 2.2)) // floor
      ..box(vm.Vector3(-0.85, 1.75, 1.06), vm.Vector3(3.6, 1.3, 0.1))
      ..box(vm.Vector3(-0.85, 1.75, -1.06), vm.Vector3(3.6, 1.3, 0.1))
      ..box(vm.Vector3(-2.6, 1.75, 0), vm.Vector3(0.1, 1.3, 2.2))
      ..box(vm.Vector3(0.9, 1.85, 0), vm.Vector3(0.12, 1.5, 2.2));
    for (var k = 0; k < 4; k++) {
      final x = -2.3 + k * 0.95;
      tub
        ..box(vm.Vector3(x, 1.75, 1.13), vm.Vector3(0.12, 1.3, 0.06))
        ..box(vm.Vector3(x, 1.75, -1.13), vm.Vector3(0.12, 1.3, 0.06));
    }
    _truck.add(Node(mesh: Mesh(tub.build(), body)));
    final cabin = MeshBatch()
      ..box(vm.Vector3(2.05, 1.45, 0), vm.Vector3(1.55, 1.5, 2.05))
      ..box(vm.Vector3(2.95, 1.0, 0), vm.Vector3(0.35, 0.5, 2.05)); // bonnet
    _truck.add(Node(mesh: Mesh(cabin.build(), cab)));
    final windows = MeshBatch()
      ..box(vm.Vector3(2.84, 1.72, 0), vm.Vector3(0.04, 0.62, 1.8))
      ..box(vm.Vector3(2.15, 1.72, 1.03), vm.Vector3(1.05, 0.58, 0.04))
      ..box(vm.Vector3(2.15, 1.72, -1.03), vm.Vector3(1.05, 0.58, 0.04));
    _truck.add(Node(mesh: Mesh(windows.build(), glass)));
    final grill = MeshBatch()..box(vm.Vector3(3.13, 0.95, 0), vm.Vector3(0.04, 0.32, 1.5));
    _truck.add(Node(mesh: Mesh(grill.build(), steel)));
    final lamp = pbr(rgb(1, 0.95, 0.8), emissive: rgb(1, 0.9, 0.7), emissiveStrength: 3);
    for (final z in [-0.72, 0.72]) {
      _truck.add(Node(mesh: Mesh(SphereGeometry(radius: 0.13, segments: 10, rings: 6), lamp), localTransform: trs(vm.Vector3(3.13, 1.12, z)))..castsShadows = false);
    }
    _truckBeacon = pbr(lin(BP.amber), emissive: lin(BP.amber), emissiveStrength: 4);
    _truck.add(Node(mesh: Mesh(CylinderGeometry(bottomRadius: 0.14, topRadius: 0.1, height: 0.18, radialSegments: 12), _truckBeacon), localTransform: trs(vm.Vector3(2.05, 2.29, 0)))..castsShadows = false);
    final wheel = CylinderGeometry(bottomRadius: 0.46, topRadius: 0.46, height: 0.34, radialSegments: 18);
    final hub = CylinderGeometry(bottomRadius: 0.2, topRadius: 0.2, height: 0.36, radialSegments: 12);
    for (final x in [-1.9, -0.9, 2.2]) {
      for (final z in [-0.92, 0.92]) {
        _truck.add(Node(mesh: Mesh(wheel, dark), localTransform: trs(vm.Vector3(x, 0.46, z), rotX: math.pi / 2)));
        _truck.add(Node(mesh: Mesh(hub, steel), localTransform: trs(vm.Vector3(x, 0.46, z), rotX: math.pi / 2)));
      }
    }
    _truck.visible = false;
    scene.add(_truck);
    // ♻ on both sides of the tipper.
    vectorizeText('♻').then((gs) {
      if (gs.isEmpty || gs.first.$2.isEmpty) return;
      final g = gs.first.$2;
      final mesh = extrudeGlyph(g, unitsPerPx: 0.95 / g.inkHeight, depth: 0.05);
      final mat = pbr(rgb(0.95, 0.97, 0.96), roughness: 0.4, emissive: rgb(0.5, 0.9, 0.7), emissiveStrength: 0.4);
      for (final z in [-1.13, 1.13]) {
        _truck.add(Node(mesh: Mesh(glyphGeometry(mesh), mat), localTransform: trs(vm.Vector3(-0.85, 1.28, z * 1.03), rotY: z < 0 ? 0 : math.pi)));
      }
    });
  }

  void _buildBanner() {
    final navy = pbr(lin(BP.panel), roughness: 0.6);
    final trim = pbr(lin(BP.amber), roughness: 0.35, metallic: 0.3, emissive: lin(BP.amber), emissiveStrength: 0.5);
    _bannerGlow = pbr(lin(const Color(0xFFFFE3A3)), roughness: 0.3, emissive: lin(BP.amber), emissiveStrength: 2.2);
    const w = 5.2, h = 1.9;
    final board = MeshBatch()..box(vm.Vector3(0, 0, 0.06), vm.Vector3(w, h, 0.12));
    _banner.add(Node(mesh: Mesh(board.build(), navy)));
    final frame = MeshBatch()
      ..box(vm.Vector3(0, h / 2, 0), vm.Vector3(w + 0.12, 0.1, 0.18))
      ..box(vm.Vector3(0, -h / 2, 0), vm.Vector3(w + 0.12, 0.1, 0.18))
      ..box(vm.Vector3(w / 2, 0, 0), vm.Vector3(0.1, h, 0.18))
      ..box(vm.Vector3(-w / 2, 0, 0), vm.Vector3(0.1, h, 0.18));
    _banner.add(Node(mesh: Mesh(frame.build(), trim)));
    // Bulbs round the edge, like the 2D board.
    final bulb = SphereGeometry(radius: 0.055, segments: 8, rings: 5);
    final bulbs = InstancedMesh(geometry: bulb, material: pbr(rgb(1, 0.9, 0.6), emissive: rgb(1, 0.8, 0.45), emissiveStrength: 5));
    for (var k = 0; k < 15; k++) {
      final x = -w / 2 + 0.3 + k * (w - 0.6) / 14;
      bulbs.addInstance(trs(vm.Vector3(x, h / 2 - 0.16, -0.04)));
      bulbs.addInstance(trs(vm.Vector3(x, -h / 2 + 0.16, -0.04)));
    }
    _banner.add(Node()..addComponent(InstancedMeshComponent(bulbs)));
    _banner.visible = false;
    scene.add(_banner);
    vectorizeText('完成！').then((gs) {
      // Lay the characters out side by side, 1.15 tall.
      final metas = [for (final g in gs) (g.$1, g.$2, extrudeGlyph(g.$2, unitsPerPx: 1.15 / 105, depth: 0.22))];
      var total = 0.0;
      for (final m in metas) {
        total += m.$3.width + 0.18;
      }
      var x = -total / 2;
      for (final m in metas) {
        if (m.$2.isEmpty) continue;
        final cx = x + m.$3.width / 2;
        _banner.add(Node(name: 'banner ${m.$1}', mesh: Mesh(glyphGeometry(m.$3), _bannerGlow), localTransform: trs(vm.Vector3(cx, -0.62, -0.1))));
        x += m.$3.width + 0.18;
      }
    });
  }

  // ── Per job ───────────────────────────────────────────────────────────────

  void _startJob(Job j) {
    _job = j;
    _r = null;
    _plan = null;
    _glyphs = null;
    _lettersMade = 0;
    _lettersReady = false;
    _falls = null;
    _landOrder = null;
    _swing = null;
    _finalized = 0;
    _yardDone = false;
    _wallHidden = false;
    impactAt = null;
    _nameShapes = [];
    _rowPass = [];
    for (final l in _letters) {
      _letterRoot.remove(l.node);
    }
    _letters.clear();
    _bricks.clearInstances();
    vectorizeText(j.name, style: (size, color) => NameRaster.nameStyle(size, color: color)).then((g) {
      if (!identical(_job, j)) return;
      _glyphs = g;
      _nameShapes = [
        for (final e in g)
          if (!e.$2.isEmpty) Fx3D.shapeOf(e.$2, count: 120),
      ]..removeWhere((s) => s.length < 20);
    });
  }

  void _setupRaster(Job j, NameRaster r) {
    _r = r;
    b = math.min(0.32, math.min(19.0 / r.cols, 7.6 / r.rows));
    wallWidth = r.cols * b;
    wallHeight = r.rows * b;
    _plan = BuildPlan(j, r, b);
    for (var i = 0; i < r.bricks.length; i++) {
      _bricks.addInstance(hidden, color: _brickColor(r.bricks[i]));
    }
  }

  vm.Vector4 _brickColor(Brick k) {
    final full = rgb(0.86, 0.83, 0.76);
    final glass = rgb(0.12, 0.33, 0.85);
    final f = c01((k.cover - 0.15) / 0.7);
    return glass + (full - glass) * f;
  }

  vm.Vector3 cell(int i) => vm.Vector3(_plan!.cellX[i], _plan!.cellY[i], 0);

  static final _cream = lin(const Color(0xFFF4F1EA));

  final _m = vm.Matrix4.identity();
  final _q = vm.Quaternion.identity();
  static final _axes = [vm.Vector3(0.3, 1, 0.2).normalized(), vm.Vector3(1, 0.2, -0.4).normalized(), vm.Vector3(-0.3, 0.5, 1).normalized()];

  vm.Matrix4 _brickM(double x, double y, double z, double s, [double spin = 0, int axis = 0]) {
    if (s <= 0) return hidden;
    if (spin == 0) {
      _q.setValues(0, 0, 0, 1);
    } else {
      _q.setAxisAngle(_axes[axis % 3], spin);
    }
    final k = b * 0.96 * s;
    return setTqs(_m, x, y, z, _q, k, k, k);
  }

  /// One letter of the smooth name, placed exactly over the raster, and cut
  /// into one band per brick row for the reveal. Made one per frame.
  void _makeNextLetter() {
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
      final idx = k++;
      final geo = g[idx].$2;
      final start = offset;
      offset += ch.length;
      if (idx < _lettersMade) continue;
      _lettersMade++;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + ch.length));
      if (geo.isEmpty || boxes.isEmpty) break;
      final mesh = extrudeGlyph(geo, unitsPerPx: s * b, depth: b * 1.7);
      // Ink centre-bottom of this glyph, in the name's raster px.
      final px = boxes.first.left + ((geo.inkLeft + geo.inkRight) / 2 - rasterPad) * s - r.inkOffset.dx;
      final py = (geo.inkBottom - rasterPad) * s - r.inkOffset.dy;
      final at = vm.Vector3((px - r.cols / 2) * b, (r.rows - py) * b, 0);
      final hue = [BP.amber, BP.line, BP.green, BP.pink, BP.violet, BP.coral][idx % 6];
      final mat = pbr(lin(const Color(0xFFF4F1EA)), roughness: 0.3, metallic: 0.05, emissive: lin(hue), emissiveStrength: 0);
      // Bands of brick rows (at most ~12 per letter, to keep the draw
      // count down): world rows → the mesh's own y.
      final per = math.max(1, (r.rows / 12).ceil());
      final cuts = [for (var rr = per; rr < r.rows; rr += per) rr * b - at.y];
      final bands = sliceGlyph(mesh, cuts);
      final prims = <MeshPrimitive>[];
      final rows = <int>[];
      for (var k = 0; k < bands.length; k++) {
        final bg = bands[k];
        if (bg == null) continue;
        prims.add(MeshPrimitive(bg, mat));
        rows.add(math.min(r.rows - 1, (k + 1) * per - 1)); // its top row
      }
      final full = Mesh(glyphGeometry(mesh), mat);
      final banded = prims.isEmpty ? full : Mesh.primitives(primitives: prims);
      final node = Node(name: 'letter $ch', mesh: full, localTransform: trs(at))..visible = false;
      _letters.add(_Letter(node, full, banded, rows, mat, lin(hue), at, per));
      _letterRoot.add(node);
      break;
    }
    tp.dispose();
    if (_lettersMade >= g.length) _lettersReady = true;
  }

  // ── Update ────────────────────────────────────────────────────────────────

  void update(BoothModel m, double dt, {double night = 0}) {
    final j = m.job;
    final t = m.t;
    if (j == null) return;
    if (!identical(j, _job)) _startJob(j);
    final r = j.raster;
    if (r != null && _r == null && j.buildStart != null) _setupRaster(j, r);
    if (_r != null && _glyphs != null && !_lettersReady) _makeNextLetter();

    _truck.visible = false;
    _banner.visible = false;
    crane.slings(null);
    crane.ballHanging = false;
    scanY = -1;
    final plan = _plan;
    level = plan?.level(t) ?? 0;
    double trip = -1;

    switch (j.phase) {
      case Phase.intake || Phase.build:
        trip = _build(j, t, dt, night);
      case Phase.reveal:
        _reveal(j, t);
        _idleCrane(vm.Vector3(wallWidth / 2 + 3.5, 12.5, 2.5), t, dt, night);
      case Phase.celebrate:
        _hideWall();
        _celebrate(j, t, dt, night);
      case Phase.demolish:
        _demolish(j, t, dt, night);
      case Phase.cleanup:
        _cleanup(j, t, dt, night);
    }
    _drawPallets(j, t);
    crew.update(m, plan, w: wallWidth, seat: crane.seat, seatYaw: crane.seatYaw, impact: impactAt, trip: trip, night: night);
    lights.update(night, t, fx.flashes);
    hookAt.setFrom(crane.hook);
  }

  // ── Intake & build ────────────────────────────────────────────────────────

  final _cmd = vm.Vector3(9, 9, 0);
  bool _cmdInit = false;

  /// Moves the hook towards [target] like a crane (slew/trolley/hoist, eased).
  void _idleCrane(vm.Vector3 target, double t, double dt, double night, {double settle = 0.9}) {
    if (!_cmdInit) {
      _cmd.setFrom(target);
      _cmdInit = true;
    }
    final f = 1 - math.exp(-math.min(dt, 0.5) / settle);
    _cmd.setFrom(polarLerp(_cmd, target, f));
    crane.update(_cmd, t, dt, night: night);
  }

  final _pose = BrickPose();

  /// Returns the crane's trip progress (for the foreman), or -1.
  double _build(Job j, double t, double dt, double night) {
    final plan = _plan;
    if (plan == null) {
      _idleCrane(vm.Vector3(SiteLayout.mastX - 5, 9, SiteLayout.mastZ - 4), t, dt, night);
      return -1;
    }
    // The crane: on a trip, or waiting by the yard / after the last trip.
    final at = plan.tripAt(t);
    if (at != null) {
      _cmd.setFrom(plan.hookPath(t));
      _cmdInit = true;
      crane.update(_cmd, t, dt, night: night);
    } else if (t < plan.t0) {
      _idleCrane(plan.yardHook(0), t, dt, night, settle: 0.6);
    } else {
      _idleCrane(vm.Vector3(wallWidth / 2 + 3, math.max(9.0, level + 5), 3.2), t, dt, night);
    }
    final sway = crane.sway;
    // Bricks: the wall's settled ones once, the moving ones every frame.
    final settled = plan.settledBy(t);
    for (; _finalized < settled; _finalized++) {
      _bricks.setInstanceTransform(_finalized, _brickM(plan.cellX[_finalized], plan.cellY[_finalized], 0, 1));
    }
    final kNow = at?.$1 ?? (t < plan.t0 ? 0 : plan.trips - 1);
    final dynEnd = plan.tripStart[math.min(kNow + 1, plan.trips)];
    for (var i = _finalized; i < dynEnd; i++) {
      final p = plan.brickAt(i, t, _pose);
      var x = p.pos.x, z = p.pos.z;
      // Riding the crane: swing with the hook.
      if (at != null && plan.trip[i] == at.$1 && t < plan.t0 + plan.dropRel[i] && at.$2 >= 0.1) {
        x += sway.x;
        z += sway.z;
      }
      _bricks.setInstanceTransform(i, _brickM(x, p.pos.y, z, p.scale, p.spin, p.spinAxis));
    }
    if (!_yardDone) {
      for (var i = dynEnd; i < plan.total; i++) {
        final p = plan.brickAt(i, t, _pose);
        _bricks.setInstanceTransform(i, _brickM(p.pos.x, p.pos.y, p.pos.z, p.scale));
      }
      if (t > j.startedAt + 4.6) _yardDone = true;
    }
    // Dust: bricks landing in the wall, batches landing on the piles.
    final laidNow = plan.laidF(t).floor();
    for (var i = math.max(0, plan.laidF(t - 0.5).floor() - 1); i <= laidNow && i < plan.total; i++) {
      final age = (t - plan.layAt(i)) / 0.5;
      if (age < 0) continue;
      fx.puff(plan.cellX[i], plan.cellY[i] - b * 0.4, -b * 0.6, age, b * 1.3, seed: i, n: 2);
    }
    for (final k in [kNow - 1, kNow]) {
      if (k < 0) continue;
      for (var i = plan.tripStart[k]; i < plan.tripStart[k + 1]; i++) {
        final age = (t - plan.pileLandAt(i)) / 0.45;
        if (age < 0 || age >= 1 || plan.pile[i] % 3 != 0) continue;
        plan.pileSlot(plan.zone[i], k, plan.pile[i], plan.deckY(t), _tmp);
        fx.puff(_tmp.x, _tmp.y - b * 0.3, _tmp.z, age, b * 1.6, seed: i, n: 2);
      }
    }
    return at == null ? -1 : at.$2;
  }

  final _tmp = vm.Vector3.zero();

  void _drawPallets(Job j, double t) {
    final plan = _plan;
    final show = plan != null && j.phase.index <= Phase.celebrate.index;
    var slung = false;
    for (var k = 0; k < _maxPallets; k++) {
      if (!show || k >= plan.trips) {
        _pallets.setInstanceTransform(k, hidden);
        continue;
      }
      final appear = c01((t - (j.startedAt + 0.4 + 0.08 * k)) / 0.3);
      final base = plan.palletBase(k, t);
      final onHook = base.y > 0.01;
      final s = 4 * b + 0.12;
      final x = base.x + (onHook ? crane.sway.x : 0), z = base.z + (onHook ? crane.sway.z : 0);
      _pallets.setInstanceTransform(k, appear <= 0 ? hidden : setTqs(_m, x, base.y + 0.07, z, _qi, s * appear, 0.14 * appear, s * appear));
      if (onHook && !slung) {
        slung = true;
        crane.slings(vm.Vector3(x, base.y + 0.12, z), hx: s / 2 - 0.05, hz: s / 2 - 0.05);
      }
    }
  }

  static final _qi = vm.Quaternion.identity();

  /// No bricks (while the smooth letters stand), set once.
  void _hideWall() {
    final plan = _plan;
    if (plan == null || _wallHidden) return;
    for (var i = 0; i < plan.total; i++) {
      _bricks.setInstanceTransform(i, hidden);
    }
    _wallHidden = true;
  }

  // ── Reveal: pixels → outlines ─────────────────────────────────────────────

  /// The scan plane's height [since] seconds into the reveal.
  double _scanAt(double since) => -0.15 + (wallHeight + 0.5) * _sweep(seg(since, 0.35, 4.7));

  /// A gentle ease in and out (gentler than cubic at the ends).
  static double _sweep(double f) => 0.5 - 0.5 * math.cos(f * math.pi);

  void _reveal(Job j, double t) {
    final plan = _plan;
    if (plan == null) return;
    final since = j.since(t);
    final y = _scanAt(since);
    scanY = y;
    fx.scan(y, wallWidth, b * 2.2, 1 - seg(since, 4.6, 5.3));
    // Bricks the plane has passed shrink away, each letting go of a pixel
    // of light that floats up and fades.
    if (_rowPass.length != plan.r.rows) {
      _rowPass = [for (var rr = 0; rr < plan.r.rows; rr++) _passTime((rr + 1) * b)];
    }
    final n = j.cutAt ?? plan.total;
    for (var i = 0; i < plan.total; i++) {
      final cy = plan.cellY[i];
      final passT = _rowPass[(cy / b).floor().clamp(0, plan.r.rows - 1)];
      final tau = since - passT;
      if (tau < 0) {
        _bricks.setInstanceTransform(i, i < n ? _brickM(plan.cellX[i], cy, 0, 1) : hidden);
        continue;
      }
      final shrink = 1 - c01(tau / 0.32);
      _bricks.setInstanceTransform(i, _brickM(plan.cellX[i], cy, 0, shrink));
      if (tau < 1.1) {
        final f = tau / 1.1;
        final r1 = rnd(i, 5), r2 = rnd(i, 9);
        final color = r1 < 0.6 ? fxPalette[5] : (r1 < 0.85 ? fxPalette[6] : fxPalette[0]);
        fx.pixel(
          plan.cellX[i] + (r2 - 0.5) * 0.6 * f,
          cy + 0.15 + 1.2 * eo(f) + 0.3 * r1 * f,
          -b - 0.35 * f,
          b * 0.42 * (1 - f) * (0.7 + 0.6 * r2),
          color,
          glow: 4 + 4 * (1 - f),
          spin: tau * (3 + 4 * r2),
        );
      }
    }
    _wallHidden = false;
    // The letters appear band by band below the plane.
    for (final l in _letters) {
      if (!identical(l.node.mesh, l.banded)) l.node.mesh = l.banded;
      l.node.visible = true;
      final prims = l.banded.primitives;
      for (var k = 0; k < prims.length; k++) {
        final on = y >= (l.rows[k] + 1 - l.per * 0.5) * b;
        prims[k].visible = on;
        prims[k].castsShadow = on;
      }
      // Cream, with a cool glow that settles.
      l.mat.baseColorFactor = _cream;
      l.mat.emissiveFactor = fxPalette[5];
      l.mat.emissiveStrength = 1.4 * (1 - seg(since, 3.5, 6.0)) + 0.1;
    }
  }

  var _rowPass = <double>[];

  /// When (seconds into the reveal) the plane passes height [y].
  double _passTime(double y) {
    final f = c01((y + 0.15) / (wallHeight + 0.5));
    // Invert the ease (bisection; monotonic).
    var lo = 0.0, hi = 1.0;
    for (var k = 0; k < 18; k++) {
      final mid = (lo + hi) / 2;
      if (_sweep(mid) < f) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return 0.35 + (lo + hi) / 2 * (4.7 - 0.35);
  }

  // ── Celebrate ─────────────────────────────────────────────────────────────

  void _celebrate(Job j, double t, double dt, double night) {
    final u = j.since(t);
    final len = j.phaseLen;
    // Smooth letters: one after another they burst into the palette with a
    // little hop, then glow in a travelling wave.
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (!identical(l.node.mesh, l.full)) l.node.mesh = l.full;
      l.node.visible = true;
      final on = c01((u - 0.2 - i * 0.22) / 0.35);
      final hop = math.sin(on * math.pi) * (1 - on * 0.3);
      l.node.place((m) => setTrs(m, l.at.x, l.at.y + 0.35 * hop, l.at.z, s: 1 + 0.1 * hop));
      final wave = 0.5 + 0.5 * math.sin(u * 3.2 - i * 0.9);
      final cream = _cream;
      l.mat.baseColorFactor = cream + (l.hue * 0.8 - cream) * on;
      l.mat.emissiveFactor = l.hue;
      l.mat.emissiveStrength = on * (0.3 + 0.9 * wave) * (1 - 0.5 * seg(u, len - 2.5, len)) + (1 - on) * 0.15;
    }
    fx.fireworks(u, wallWidth, wallHeight, j.serial, _nameShapes, _scriptShapes);
    fx.confettiShow(u, wallWidth, j.serial);
    // The crane brings the 完成！ sign over the name, then takes it away.
    final show = vm.Vector3(0, wallHeight + 4.4, -0.7);
    final park = vm.Vector3(wallWidth / 2 + 4.5, 13.5, -1.5);
    final inF = eio(seg(u, 0.0, 2.6)), outF = eio(seg(u, len - 2.4, len - 0.2));
    final target = polarLerp(polarLerp(park, show, inF), vm.Vector3(show.x + 3, 16, show.z), outF);
    _cmd.setFrom(target);
    _cmdInit = true;
    crane.update(_cmd, t, dt, night: night);
    final hk = crane.hook;
    final sw = 0.04 * math.sin(u * 1.7);
    _banner
      ..visible = true
      ..place((m) => setTrs(m, hk.x, hk.y - 1.45 - 0.95, hk.z, roll: sw));
    crane.slings(vm.Vector3(hk.x, hk.y - 1.45, hk.z), hx: 2.2, hz: 0.04);
    _bannerGlow.emissiveStrength = 1.6 + 0.9 * (0.5 + 0.5 * math.sin(u * 5));
  }

  // ── Demolition: a wrecking ball, then ballistic bricks ─────────────────────

  void _demolish(Job j, double t, double dt, double night) {
    final plan = _plan;
    final len = math.max(j.phaseLen, 0.01);
    final u = j.since(t);
    for (final l in _letters) {
      l.node.visible = false;
    }
    if (plan == null) {
      _idleCrane(vm.Vector3(wallWidth / 2 + 4, 12, -1), t, dt, night);
      return;
    }
    _swing ??= _Swing(wallWidth, wallHeight, len);
    final sw = _swing!;
    if (_falls == null) {
      _falls = _planFalls(j, sw);
      final order = List.generate(_falls!.length, (i) => i)..removeWhere((i) => !_falls![i].ever);
      order.sort((a, c) => _falls![a].landAt(b).compareTo(_falls![c].landAt(b)));
      _landOrder = order;
      impactAt = j.phaseStart + sw.firstHit;
    }
    // Outlines → pixels again: the smooth letters turn back into bricks as
    // a quick scan runs down the wall (not after a cut: no letters then).
    final wasRevealed = j.cutAt == null;
    final back = wasRevealed ? wallHeight + 0.3 - (wallHeight + 0.6) * eio(seg(u, 0.1, 1.3)) : -1.0;
    if (wasRevealed && u < 1.5) {
      fx.scan(back, wallWidth, b * 2.2, 1 - seg(u, 1.2, 1.5));
      for (final l in _letters) {
        if (!identical(l.node.mesh, l.banded)) l.node.mesh = l.banded;
        l.node.visible = true;
        l.mat.emissiveStrength = 0.6;
        final prims = l.banded.primitives;
        for (var k = 0; k < prims.length; k++) {
          final on = back < (l.rows[k] + 0.5) * b;
          prims[k].visible = !on;
          prims[k].castsShadow = !on;
        }
      }
    }
    // The ball: lowered at the right, then swung through the wall.
    final ball = sw.ballAt(u);
    ballAt.setFrom(ball);
    crane.swingBall(sw.pivotAt(u), ball, t, dt, night: night);
    // Bricks.
    final falls = _falls!;
    for (var i = 0; i < falls.length; i++) {
      final f = falls[i];
      if (!f.ever) {
        _bricks.setInstanceTransform(i, hidden);
        continue;
      }
      if (wasRevealed && u < 1.5) {
        // Popping back in under the descending scan.
        final appear = c01((back < f.p0.y + b * 0.5 ? 1.0 : 0.0));
        if (appear <= 0) {
          _bricks.setInstanceTransform(i, hidden);
          continue;
        }
      }
      _bricks.setInstanceTransform(i, f.at(u, b, _m, _q));
    }
    _wallHidden = false;
    // Dust where the ball hits and where bricks land.
    if (u >= sw.firstHit && u < sw.firstHit + 1.4) {
      final x = sw.ballAt(u).x;
      if (x.abs() < wallWidth / 2 + 0.5) fx.puff(x, wallHeight * 0.4, -0.3, (u - sw.firstHit) % 0.7 / 0.7, 1.2, seed: (u * 3).floor(), n: 4);
    }
    final order = _landOrder!;
    for (var n = 0; n < order.length; n += 5) {
      final i = order[n];
      final landT = falls[i].release + falls[i].landAt(b);
      final age = (u - landT) / 0.9;
      if (age < 0) break;
      if (age >= 1) continue;
      final p = falls[i].landPoint(b);
      fx.puff(p.x, 0.05, p.z, age, 0.55, seed: i, n: 2);
    }
    // Confetti from the celebration still lies about.
    if (wasRevealed) fx.confettiShow(u + phaseSeconds[Phase.celebrate]!, wallWidth, j.serial);
  }

  List<_Fall> _planFalls(Job j, _Swing sw) {
    final plan = _plan!;
    final n = j.cutAt ?? plan.total;
    final out = <_Fall>[];
    for (var i = 0; i < plan.total; i++) {
      if (i >= n) {
        out.add(_Fall.never());
        continue;
      }
      final p = vm.Vector3(plan.cellX[i], plan.cellY[i], 0);
      final pass = sw.passTime(p.x);
      final ballY = sw.yAtX(p.x);
      final dy = p.y - ballY, dz = 0 - sw.z;
      final dist = math.sqrt(dy * dy + dz * dz);
      final hit = dist < _Swing.radius + b * 1.2;
      vm.Vector3 v;
      double release;
      if (hit) {
        final bv = sw.velocityAt(pass);
        final away = vm.Vector3(0, dy, dz)..normalize();
        final k = 0.55 + 0.5 * rnd(i, 3);
        v = bv * k + away * (2.0 + 2.5 * rnd(i, 4)) + vm.Vector3(0, 1.5 + 3.0 * rnd(i, 5), (rnd(i, 6) - 0.5) * 5);
        release = pass;
      } else {
        // Its support is gone: it crumbles a moment after the ball passes.
        final below = p.y < ballY;
        release = pass + 0.12 + (below ? 0.5 + 1.1 * rnd(i, 7) : 0.05 + 0.35 * rnd(i, 7)) + (wallHeight - p.y) * 0.03;
        v = vm.Vector3(-1.2 * rnd(i, 8) - 0.3, 0.8 * rnd(i, 9), (rnd(i, 10) - 0.5) * 2.0);
      }
      out.add(_Fall(p, v, release, _axesFor(i), 3 + 6 * rnd(i, 11)));
    }
    return out;
  }

  vm.Vector3 _axesFor(int i) => vm.Vector3(rnd(i, 3) - 0.5, rnd(i, 4) - 0.5, rnd(i, 5) - 0.5).normalized();

  // ── Cleanup: rubble flies into the recycling truck ─────────────────────────

  void _cleanup(Job j, double t, double dt, double night) {
    final len = math.max(j.phaseLen, 0.01);
    final u = j.since(t);
    final f = u / len;
    for (final l in _letters) {
      l.node.visible = false;
    }
    // The ball is hoisted away.
    final sw = _swing;
    if (sw != null && f < 0.35) {
      final up = eio(f / 0.35);
      // From wherever the swing left it, settling under the hook as it rises.
      final c = sw.ballAt(sw.len);
      final ball = vm.Vector3(c.x * (1 - up), c.y + up * 14, c.z);
      ballAt.setFrom(ball);
      crane.swingBall(vm.Vector3(ball.x, 14, ball.z), ball, t, dt, night: night);
    } else {
      _idleCrane(vm.Vector3(SiteLayout.mastX - 5, 9, SiteLayout.mastZ - 4), t, dt, night);
    }
    final falls = _falls;
    // The truck drives in along the avenue (the city's eastbound lane), backs
    // into the plaza next to the rubble, and drives out again east — it never
    // cuts through the city blocks beside the plaza.
    final park = -wallWidth / 2 - 2.6;
    const lane = -13.0, bay = -4.6, far = 70.0;
    double tx, tz, yaw;
    if (f < 0.12) {
      tx = lerp(-far, park, eo(f / 0.12));
      tz = lane;
      yaw = 0;
    } else if (f < 0.2) {
      final k = (f - 0.12) / 0.08;
      tx = park;
      tz = lerp(lane, bay, eio(k));
      yaw = math.pi / 2 * eo(k / 0.35); // swings round, then reverses in
    } else if (f < 0.82) {
      tx = park;
      tz = bay;
      yaw = math.pi / 2;
    } else if (f < 0.9) {
      final k = (f - 0.82) / 0.08;
      tx = park;
      tz = lerp(bay, lane, eio(k));
      yaw = math.pi / 2;
    } else {
      final k = (f - 0.9) / 0.1;
      tx = lerp(park, far, eio(k));
      tz = lane;
      yaw = math.pi / 2 * (1 - eo(k / 0.25));
    }
    truckAt.setValues(tx, 0, tz);
    _truck
      ..visible = true
      ..place((m) => setTrs(m, truckAt.x, truckAt.y, truckAt.z, yaw: yaw));
    _truckBeacon.emissiveStrength = (t * 2.2) % 1.0 < 0.5 ? 6 : 0.4;
    if (falls == null) return;
    // The tub sits behind the cab: −0.85 m along the truck's length.
    final hopper = truckAt + vm.Vector3(-0.85 * math.cos(yaw), 2.2, 0.85 * math.sin(yaw));
    for (var i = 0; i < falls.length; i++) {
      final fall = falls[i];
      if (!fall.ever) {
        _bricks.setInstanceTransform(i, hidden);
        continue;
      }
      final rest = fall.restPoint(b);
      final go = len * (0.22 + 0.55 * rnd(i, 13));
      final k = seg(u, go, go + 0.85);
      if (k <= 0) {
        _bricks.setInstanceTransform(i, fall.at(99, b, _m, _q));
      } else if (k >= 1) {
        _bricks.setInstanceTransform(i, hidden);
      } else {
        final p = rest + (hopper - rest) * eio(k) + vm.Vector3(0, 2.4 * math.sin(k * math.pi), 0);
        _bricks.setInstanceTransform(i, _brickM(p.x, p.y, p.z, 1 - 0.35 * k, k * 6, i));
        if (k < 0.3 && i % 4 == 0) fx.puff(rest.x, 0.05, rest.z, k / 0.3, 0.35, seed: i, n: 1);
      }
    }
    _wallHidden = false;
    if (j.cutAt == null) {
      fx.confettiShow(u + phaseSeconds[Phase.celebrate]! + phaseSeconds[Phase.demolish]!, wallWidth, j.serial, fade: c01(f / 0.3));
    }
  }

  /// Where the camera should look while building (the top of the wall).
  vm.Vector3 get focus => vm.Vector3(0, math.max(level, wallHeight * 0.35), 0);
}

class _Letter {
  _Letter(this.node, this.full, this.banded, this.rows, this.mat, this.hue, this.at, this.per);
  final Node node;

  /// Brick rows per band.
  final int per;
  final vm.Vector3 at;
  final Mesh full, banded;

  /// The brick row (from the bottom) of each of [banded]'s primitives.
  final List<int> rows;
  final PhysicallyBasedMaterial mat;
  final vm.Vector4 hue;
}

/// The wrecking ball's swing: lowered at the right of the wall, then
/// released as a pendulum from above the middle, through the wall.
class _Swing {
  _Swing(this.w, this.h, this.len) {
    pivotY = SiteLayout.jibY - 0.45 - 1.55 + 1.0;
    l = pivotY - h * 0.42;
    theta0 = math.asin(math.min(0.97, (w / 2 + 2.4) / l));
    omega = math.sqrt(SiteLayout.g / l);
    release = len * 0.26;
    // The first brick it reaches: the wall's right end at the ball's height.
    var first = double.infinity;
    for (var x = w / 2; x > -w / 2; x -= 0.1) {
      final y = yAtX(x);
      if (y - radius < h && y + radius > 0) {
        first = passTime(x);
        break;
      }
    }
    firstHit = first.isFinite ? first : release + 1;
  }

  final double w, h, len;
  late final double pivotY, l, theta0, omega, release, firstHit;
  static const radius = 1.0;
  final z = -0.3;

  double get startX => l * math.sin(theta0);
  double get startY => pivotY - l * math.cos(theta0);

  double theta(double u) {
    final tau = u - release;
    if (tau <= 0) return theta0;
    return theta0 * math.cos(omega * tau) * math.exp(-0.09 * tau);
  }

  /// Where the trolley (the pendulum's pivot) is: over the start while the
  /// ball comes down, then over the middle.
  vm.Vector3 pivotAt(double u) {
    final shift = eio(seg(u, len * 0.2, release));
    return vm.Vector3(startX * (1 - shift), pivotY, z);
  }

  vm.Vector3 ballAt(double u) {
    if (u < release) {
      // Lowered from above to its start, hanging still.
      final down = eo(seg(u, 0, len * 0.2));
      return vm.Vector3(startX, lerp(startY + 5.5, startY, down), z);
    }
    final th = theta(u);
    return vm.Vector3(l * math.sin(th), pivotY - l * math.cos(th), z);
  }

  vm.Vector3 velocityAt(double u) {
    final tau = u - release;
    final th = theta(u);
    final dth = -theta0 * omega * math.sin(omega * tau) * math.exp(-0.09 * tau);
    return vm.Vector3(l * dth * math.cos(th), l * dth * math.sin(th), 0);
  }

  /// The ball's height where its arc crosses [x].
  double yAtX(double x) {
    final s = (x / l).clamp(-1.0, 1.0);
    return pivotY - l * math.cos(math.asin(s));
  }

  /// When (seconds into the demolition) the ball first passes [x].
  double passTime(double x) {
    final th = math.asin((x / l).clamp(-1.0, 1.0));
    final c = (th / theta0).clamp(-1.0, 1.0);
    return release + math.acos(c) / omega;
  }
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
  static const g = SiteLayout.g;

  /// Time from release to first touching the ground (y = b/2).
  double landAt(double b) {
    final y0 = p0.y - b / 2;
    final vy = v0.y;
    return (vy + math.sqrt(vy * vy + 2 * g * math.max(0, y0))) / g;
  }

  vm.Vector3 landPoint(double b) {
    final tl = landAt(b);
    return vm.Vector3(p0.x + v0.x * tl, b / 2, p0.z + v0.z * tl);
  }

  vm.Vector3 restPoint(double b) {
    final tl = landAt(b);
    return vm.Vector3(p0.x + v0.x * tl, b / 2, p0.z + v0.z * tl) + vm.Vector3(v0.x, 0, v0.z) * 0.25;
  }

  vm.Matrix4 at(double u, double b, vm.Matrix4 out, vm.Quaternion q) {
    if (!ever) return hidden;
    final s = b * 0.96;
    final tau = u - release;
    if (tau <= 0) return setTqs(out, p0.x, p0.y, p0.z, q..setValues(0, 0, 0, 1), s, s, s);
    final tl = landAt(b);
    if (tau < tl) {
      q.setAxisAngle(axis, spin * tau);
      return setTqs(out, p0.x + v0.x * tau, p0.y + v0.y * tau - 0.5 * g * tau * tau, p0.z + v0.z * tau, q, s, s, s);
    }
    // After landing: one small hop and a slide to rest.
    final after = tau - tl;
    final slide = 0.25 * (1 - math.exp(-after * 4));
    final hop = math.max(0.0, 0.6 * math.sin(math.min(after, 0.35) / 0.35 * math.pi)) * (v0.y.abs() + 1) * 0.15;
    final ang = spin * tl + spin * 0.3 * (1 - math.exp(-after * 3));
    q.setAxisAngle(axis, ang);
    return setTqs(out, p0.x + v0.x * tl + v0.x * slide, b / 2 + hop, p0.z + v0.z * tl + v0.z * slide, q, s, s, s);
  }
}
