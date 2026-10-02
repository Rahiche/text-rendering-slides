import 'dart:math' as math;

import 'package:flutter_scene/physics.dart' show BodyType, BoxShape, PhysicsMaterial, PoseTarget;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'physics.dart';
import 'site_geo.dart';

/// A brick riding in the loader's bucket, then dropping into the truck: a
/// rigid body drawn where the physics has it.
class _Load implements PoseTarget {
  _Load(this.i, this.draw, vm.Vector3 at, vm.Quaternion q) : t = at.clone(), r = q.clone();
  final int i;
  final void Function(int i, vm.Vector3 t, vm.Quaternion q) draw;
  final vm.Vector3 t;
  final vm.Quaternion r;
  int body = -1;

  @override
  vm.Vector3 get worldTranslation => t;

  @override
  vm.Quaternion get worldRotation => r;

  @override
  void setWorldPose(vm.Vector3 translation, vm.Quaternion rotation) {
    t.setFrom(translation);
    r.setFrom(rotation);
    draw(i, t, r);
  }
}

/// 片付け · The cleanup's wheel loader: its bucket full of the wreck's
/// bricks (real bodies, in a real bucket), it drives over to the truck,
/// lifts, and tips them into the tub — they tumble in, and ride away with
/// the truck. The rest of the rubble goes off camera (the cut to the swept
/// plaza is the time it took).
///
/// Its frame: forward +x, up +y; the arms hinge on the front frame and lift
/// the bucket, which tilts on its own (a parallel linkage: level unless
/// tilted). Placed facing the truck from the rubble's side.
class Loader3D {
  Loader3D(this.scene);
  final Scene scene;

  final _root = Node(name: 'wheel loader');
  final _arms = Node(name: 'loader arms');
  final _bucket = Node(name: 'loader bucket');
  final _wheels = <Node>[];

  /// The arms' hinge (x, y), their length; the wheels' radius; the bucket:
  /// width, depth (hinge to lip), height.
  static const _px = 0.95, _py = 1.65, _arm = 2.35, _wr = 0.62;
  static const _bw = 2.5, _bd = 1.05, _bh = 0.85;

  void init() {
    final yellow = pbr(lin(BP.amber), roughness: 0.45, metallic: 0.2);
    final dark = pbr(rgb(0.035, 0.04, 0.05), roughness: 0.8);
    final steel = pbr(rgb(0.55, 0.57, 0.6), roughness: 0.35, metallic: 0.8);
    final glass = pbr(rgb(0.08, 0.15, 0.22), roughness: 0.1, metallic: 0.3);
    final body = MeshBatch()
      ..box(vm.Vector3(-1.15, 1.2, 0), vm.Vector3(2.1, 1.1, 1.85)) // engine
      ..box(vm.Vector3(-2.27, 1.05, 0), vm.Vector3(0.3, 0.95, 1.8)) // counterweight
      ..box(vm.Vector3(1.0, 0.95, 0), vm.Vector3(1.45, 0.55, 1.15)) // front frame
      ..box(vm.Vector3(0.0, 1.5, 0), vm.Vector3(0.7, 0.5, 1.6)) // articulation
      ..box(vm.Vector3(-0.05, 3.1, 0), vm.Vector3(1.4, 0.1, 1.62)); // cab roof
    for (final (x, z) in const [(-0.65, -0.72), (-0.65, 0.72), (0.55, -0.72), (0.55, 0.72)]) {
      body.box(vm.Vector3(x, 2.4, z), vm.Vector3(0.09, 1.35, 0.09)); // cab posts
    }
    _root.add(Node(mesh: Mesh(body.build(), yellow)));
    final panes = MeshBatch()..box(vm.Vector3(-0.05, 2.4, 0), vm.Vector3(1.15, 1.25, 1.38));
    _root.add(Node(mesh: Mesh(panes.build(), glass))..castsShadows = false);
    final trim = MeshBatch()
      ..box(vm.Vector3(-1.2, 1.79, 0), vm.Vector3(2.0, 0.08, 1.7)) // engine hood line
      ..box(vm.Vector3(-1.55, 2.2, 0.55), vm.Vector3(0.12, 0.8, 0.12)) // exhaust
      ..box(vm.Vector3(0.0, 1.85, 0), vm.Vector3(0.5, 0.12, 1.75)); // step
    _root.add(Node(mesh: Mesh(trim.build(), dark)));
    // Tyres with chunky tread (their axle along z) and hubs with bolts on
    // the outside: you see them turn.
    final white = vm.Vector4(1, 1, 1, 1);
    final tyre = merged([
      part(
        CylinderGeometry(bottomRadius: _wr - 0.05, topRadius: _wr - 0.05, height: 0.48, radialSegments: 20),
        trs(vm.Vector3.zero(), rotX: math.pi / 2),
        white,
      ),
      for (var k = 0; k < 14; k++)
        for (final side in const [-1.0, 1.0])
          part(
            CuboidGeometry(vm.Vector3(0.1, 0.13, 0.22)),
            trs(
              vm.Vector3((_wr - 0.04) * math.cos(k * math.pi / 7), (_wr - 0.04) * math.sin(k * math.pi / 7), side * 0.12),
              rotZ: k * math.pi / 7 + side * 0.35,
            ),
            white,
          ),
    ]);
    MeshGeometry hubOf(double side) => merged([
      part(CylinderGeometry(bottomRadius: 0.3, topRadius: 0.3, height: 0.5, radialSegments: 10), trs(vm.Vector3.zero(), rotX: math.pi / 2), white),
      for (var k = 0; k < 8; k++)
        part(
          CuboidGeometry(vm.Vector3(0.06, 0.06, 0.06)),
          vm.Matrix4.translation(vm.Vector3(0.2 * math.cos(k * math.pi / 4), 0.2 * math.sin(k * math.pi / 4), side * 0.26)),
          white,
        ),
    ]);
    final rubber = pbr(rgb(1, 1, 1), roughness: 0.85)..baseColorFactor = rgb(0.035, 0.04, 0.05);
    for (final x in const [-1.3, 1.3]) {
      for (final z in const [-1.05, 1.05]) {
        final w = Node(name: 'loader wheel', localTransform: trs(vm.Vector3(x, _wr, z)))
          ..add(Node(mesh: Mesh(tyre, rubber)))
          ..add(Node(mesh: Mesh(hubOf(z.sign), yellow)));
        _wheels.add(w);
        _root.add(w);
      }
    }
    // The arms (along their +x from the hinge), a cross tube, the rams.
    final arms = MeshBatch()
      ..box(vm.Vector3(_arm / 2, 0, 0.62), vm.Vector3(_arm, 0.22, 0.16))
      ..box(vm.Vector3(_arm / 2, 0, -0.62), vm.Vector3(_arm, 0.22, 0.16))
      ..box(vm.Vector3(_arm * 0.62, 0.05, 0), vm.Vector3(0.18, 0.18, 1.24));
    _arms.add(Node(mesh: Mesh(arms.build(), yellow)));
    _root.add(_arms);
    // The bucket (its hinge at the origin, opening along +x and up), its
    // steel cutting edge.
    final bucket = MeshBatch()
      ..box(vm.Vector3(_bd / 2, 0.04, 0), vm.Vector3(_bd, 0.08, _bw))
      ..box(vm.Vector3(0.04, _bh / 2, 0), vm.Vector3(0.08, _bh, _bw))
      ..box(vm.Vector3(_bd / 2, _bh / 2, _bw / 2), vm.Vector3(_bd, _bh, 0.07))
      ..box(vm.Vector3(_bd / 2, _bh / 2, -_bw / 2), vm.Vector3(_bd, _bh, 0.07));
    _bucket.add(Node(mesh: Mesh(bucket.build(), yellow)));
    _bucket.add(Node(mesh: Mesh((MeshBatch()..box(vm.Vector3(_bd - 0.04, 0.03, 0), vm.Vector3(0.12, 0.06, _bw + 0.04))).build(), steel)));
    _root.add(_bucket);
    _root.visible = false;
    scene.add(_root);
  }

  // ── The cleanup ───────────────────────────────────────────────────────────

  final _loads = <_Load>[];
  void Function(int i) _hide = _noHide;
  static void _noHide(int i) {}

  /// Its solid parts: the bucket, the machine itself, and the truck (all
  /// kinematic: they shove whatever's in their way, and the load rides in
  /// the truck's tub when it drives off).
  int _bucketBody = -1, _machine = -1, _truck = -1;
  vm.Matrix4 Function(double f) _truckAt = _noTruck;
  static vm.Matrix4 _noTruck(double f) => vm.Matrix4.identity();

  double _x = 0, _z = 0, _yaw = 0, _theta = 0, _phi = 0;
  double _spin = 0;

  bool get active => _loads.isNotEmpty;

  /// Where it starts (scooping at the rubble's end) and where it tips into
  /// the truck parked at ([park], [bay]); the path between, an S along x.
  late vm.Vector3 _from, _to;

  /// Where it starts, for the site to clear the rubble it's standing in.
  /// (In front of the plinths: its bucket and its side clear of them.)
  vm.Vector3 startAt(double park) => vm.Vector3(park + 7.6, 0, -1.8);

  /// Whether [p] (world) is where the machine stands at the start (with a
  /// margin): bricks there are in its way.
  bool inTheWay(vm.Vector3 p, double park) {
    final o = startAt(park);
    // It starts facing −x (yaw π): its length along x, from its tail at +x,
    // the bucket out in front.
    final lx = o.x - p.x, lz = p.z - o.z;
    return lx > -2.7 && lx < 4.9 && lz.abs() < 1.6 && p.y < 2.4;
  }

  /// Starts the cleanup's load: the loader at the rubble's left end with
  /// [bricks] (their instance indices) in its bucket (bricks [b] wide);
  /// the truck where [truckAt] has it [f] through the cleanup (its tub
  /// ready once it's backed in at ([park], [bay])).
  void start(
    Physics physics,
    List<int> bricks,
    double b,
    double park,
    double bay,
    vm.Matrix4 Function(double f) truckAt,
    void Function(int i, vm.Vector3 t, vm.Quaternion q) draw,
    void Function(int i) hide,
  ) {
    end(physics);
    _hide = hide;
    _truckAt = truckAt;
    _from = startAt(park);
    _to = vm.Vector3(park + 3.55, 0, bay + 0.85);
    _pose(0);
    final w = physics.world;
    const steel = PhysicsMaterial(friction: 0.6, restitution: 0.05);
    void boxes(int body, List<(vm.Vector3, vm.Vector3)> parts) {
      for (final (c, h) in parts) {
        w.createColliders(
          body,
          BoxShape(halfExtents: h),
          material: steel,
          localPose: vm.Matrix4.translation(c),
        );
      }
    }

    // The bucket: floor, back, sides.
    _bucketBody = w.createBody(target: StillPose(_bucketPos(), _bucketRot()), type: BodyType.kinematic);
    boxes(_bucketBody, [
      (vm.Vector3(_bd / 2, 0.04, 0), vm.Vector3(_bd / 2, 0.04, _bw / 2)),
      (vm.Vector3(0.04, _bh / 2, 0), vm.Vector3(0.04, _bh / 2, _bw / 2)),
      (vm.Vector3(_bd / 2, _bh / 2, _bw / 2), vm.Vector3(_bd / 2, _bh / 2, 0.035)),
      (vm.Vector3(_bd / 2, _bh / 2, -_bw / 2), vm.Vector3(_bd / 2, _bh / 2, 0.035)),
    ]);
    // The machine: its body and wheels, its front frame.
    _machine = w.createBody(target: StillPose(vm.Vector3(_x, 0, _z), _rootRot()), type: BodyType.kinematic);
    boxes(_machine, [(vm.Vector3(-0.6, 1.0, 0), vm.Vector3(1.95, 0.75, 1.3)), (vm.Vector3(1.0, 0.95, 0), vm.Vector3(0.75, 0.3, 0.6))]);
    // The truck: chassis, cab, and the tub (hollow: the load goes in).
    final m0 = truckAt(0);
    _truck = w.createBody(target: StillPose(m0.getTranslation(), vm.Quaternion.fromRotation(m0.getRotation())), type: BodyType.kinematic);
    boxes(_truck, [
      (vm.Vector3(0.1, 0.62, 0), vm.Vector3(2.8, 0.16, 0.85)),
      (vm.Vector3(2.05, 1.45, 0), vm.Vector3(0.78, 0.75, 1.03)),
      (vm.Vector3(2.95, 1.0, 0), vm.Vector3(0.18, 0.25, 1.03)),
      (vm.Vector3(-0.85, 1.05, 0), vm.Vector3(1.8, 0.07, 1.1)),
      (vm.Vector3(-0.85, 1.75, 1.06), vm.Vector3(1.8, 0.65, 0.05)),
      (vm.Vector3(-0.85, 1.75, -1.06), vm.Vector3(1.8, 0.65, 0.05)),
      (vm.Vector3(-2.6, 1.75, 0), vm.Vector3(0.05, 0.65, 1.1)),
      (vm.Vector3(0.9, 1.85, 0), vm.Vector3(0.06, 0.75, 1.1)),
    ]);
    // The load, heaped in the bucket.
    final half = vm.Vector3.all(b * 0.48);
    const brick = PhysicsMaterial(friction: 0.78, restitution: 0.08, density: 1.9);
    final m = _bucketMatrix();
    for (var k = 0; k < bricks.length; k++) {
      final layer = k < 32 ? 0 : 1, n = k < 32 ? k : k - 32;
      final cols = layer == 0 ? 4 : 3;
      final lx = 0.2 + (n % cols) * (layer == 0 ? 0.21 : 0.23) + 0.03 * rnd(k, 1);
      final lz = (layer == 0 ? -0.84 : -0.5) + (n ~/ cols) * (layer == 0 ? 0.24 : 0.26) + 0.04 * (rnd(k, 2) - 0.5);
      final at = m.transformed3(vm.Vector3(lx, 0.1 + b * 0.5 + layer * b * 1.02, lz));
      final q = _bucketRot() * vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), (rnd(k, 3) - 0.5) * 0.6);
      final load = _Load(bricks[k], draw, at, q);
      load.body = w.createBody(target: load, type: BodyType.dynamic_);
      w
        ..createColliders(load.body, BoxShape(halfExtents: half), material: brick)
        ..setBodyCcdEnabled(load.body, true);
      _loads.add(load);
      draw(load.i, at, q);
    }
    _swept = false;
    _root.visible = true;
  }

  /// [f] through the cleanup (0..1): drives, lifts, tips (the bodies follow
  /// in [beforeStep]). [cut]: the cut to the swept plaza (the loader has
  /// gone, and anything it spilt; the load rides away in the truck).
  void update(Physics physics, double f, {required double cut}) {
    if (!active) return;
    _pose(f);
    if (f >= cut && !_swept) {
      _swept = true;
      _root.visible = false;
      final w = physics.world;
      for (final b in [_bucketBody, _machine]) {
        if (b >= 0) w.destroyBody(b);
      }
      _bucketBody = _machine = -1;
      final inv = vm.Matrix4.inverted(_truckAt(f));
      _loads.removeWhere((l) {
        final local = inv.transformed3(l.t.clone());
        final inTub = local.x > -2.7 && local.x < 1.0 && local.z.abs() < 1.15 && local.y > 0.9;
        if (inTub) return false;
        if (l.body >= 0) w.destroyBody(l.body);
        l.body = -1;
        _hide(l.i);
        return true;
      });
    }
  }

  bool _swept = false;

  /// Moves the bucket, the machine and the truck to where they are at
  /// [f] (each physics step).
  void beforeStep(Physics physics, double f) {
    if (_truck < 0) return;
    final w = physics.world;
    final m = _truckAt(f);
    w.setBodyKinematicTargetPose(_truck, m.getTranslation(), vm.Quaternion.fromRotation(m.getRotation()));
    if (_bucketBody < 0) return;
    _pose(f);
    w
      ..setBodyKinematicTargetPose(_bucketBody, _bucketPos(), _bucketRot())
      ..setBodyKinematicTargetPose(_machine, vm.Vector3(_x, 0, _z), _rootRot());
  }

  vm.Quaternion _rootRot() => vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _yaw);

  void end(Physics physics) {
    // (The physics world goes with the wreck's; only forget the handles.)
    _swept = false;
    _loads.clear();
    _bucketBody = _machine = _truck = -1;
    _root.visible = false;
  }

  /// Where the loader is at [f], how high its arms, how tipped its bucket.
  void _pose(double f) {
    // Down at the rubble; curl and lift to carry; over to the truck (once
    // it has backed in); up; tip; a shake; back.
    final drive = eio(seg(f, 0.34, 0.56));
    final back = eio(seg(f, 0.74, 0.86));
    final s = drive - 0.35 * back;
    // An S from the rubble to the truck, nose first (−x in the world).
    final p0 = _from, p3 = _to;
    final p1 = p0 + vm.Vector3(-2.2, 0, 0), p2 = p3 + vm.Vector3(2.2, 0, 0);
    vm.Vector3 at(double u) => p0 * math.pow(1 - u, 3).toDouble() + p1 * (3 * u * (1 - u) * (1 - u)) + p2 * (3 * u * u * (1 - u)) + p3 * (u * u * u);
    final here = at(s), ahead = at(math.min(1.0, s + 0.02)), behind = at(math.max(0.0, s - 0.02));
    final dir = ahead - behind;
    // (Yaw turns its +x to the way it goes.)
    _yaw = dir.length2 > 1e-8 ? math.atan2(-dir.z, dir.x) : math.pi;
    _x = here.x;
    _z = here.z;
    _spin = -(s * 6.0) / _wr;
    final lift = eio(seg(f, 0.44, 0.6)) * (1 - eio(seg(f, 0.76, 0.86)));
    _theta = lerp(-0.69 + 0.43 * eio(seg(f, 0.08, 0.18)), 0.87, lift);
    final tip = eio(seg(f, 0.6, 0.69)) * (1 - eio(seg(f, 0.74, 0.8)));
    final shake = seg(f, 0.69, 0.71) * (1 - seg(f, 0.72, 0.74)) * 0.08 * math.sin(f * 600);
    _phi = lerp(0.14 + 0.46 * eio(seg(f, 0.08, 0.18)), -1.08, tip) + shake;
    _root.place((m) => setTrs(m, _x, 0, _z, yaw: _yaw));
    for (final w in _wheels) {
      final o = w.localTransform.getTranslation();
      w.place((m) => setTrs(m, o.x, o.y, o.z, roll: _spin));
    }
    _arms.place((m) => setTrs(m, _px, _py, 0, roll: _theta));
    final e = _hinge();
    _bucket.place((m) => setTrs(m, e.x, e.y, 0, roll: _phi));
  }

  /// The bucket's hinge (the loader's frame).
  vm.Vector2 _hinge() => vm.Vector2(_px + _arm * math.cos(_theta), _py + _arm * math.sin(_theta));

  vm.Matrix4 _bucketMatrix() {
    final e = _hinge();
    return trs(vm.Vector3(_x, 0, _z), rotY: _yaw) * trs(vm.Vector3(e.x, e.y, 0), rotZ: _phi);
  }

  vm.Vector3 _bucketPos() => _bucketMatrix().getTranslation();
  vm.Quaternion _bucketRot() => vm.Quaternion.fromRotation(_bucketMatrix().getRotation());
}
