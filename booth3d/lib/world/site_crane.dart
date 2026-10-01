import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_geo.dart';
import 'site_plan.dart';

/// The tower crane: a lattice mast on a concrete footing, a slewing jib
/// with its trolley, a counter-jib with concrete counterweights, the tower
/// head with its pendant ties, an operator's cab, the hoist cable and hook
/// block, and the wrecking ball. Driven by a hook target each frame; the
/// slew, the trolley and the hoist follow from it, and the hook swings a
/// little behind when the crane moves.
class Crane3D {
  Crane3D(this.scene);

  final Scene scene;

  final _root = Node(name: 'crane');
  final _slew = Node(name: 'crane slew');
  final _trolley = Node(name: 'crane trolley');
  final _cable = Node(name: 'hoist cable');
  final _hook = Node(name: 'hook block');
  final _ball = Node(name: 'wrecking ball');
  late final InstancedMesh _slings;
  late final PhysicallyBasedMaterial _beacon;

  static const mx = SiteLayout.mastX, mz = SiteLayout.mastZ, jibY = SiteLayout.jibY;

  /// Where the hook block is now (world), with its swing.
  final hook = vm.Vector3(mx - 6, 9, mz);

  /// The swing: how far the hook hangs off the vertical under the trolley.
  final sway = vm.Vector3.zero();

  /// Slew angle (radians, 0 = jib towards −x) and trolley radius.
  double slew = 0, radius = 6;

  /// The operator's seat (world) and which way it faces, refreshed every
  /// frame.
  final seat = vm.Vector3.zero();
  double seatYaw = 0;

  bool get ballOn => _ball.visible;

  void init() {
    final yellow = pbr(lin(const Color(0xFFFFC23D)), roughness: 0.45, metallic: 0.25);
    final dark = pbr(rgb(0.05, 0.06, 0.08), roughness: 0.5, metallic: 0.6);
    final concrete = pbr(rgb(0.42, 0.42, 0.40), roughness: 0.95);
    final white = pbr(rgb(0.85, 0.86, 0.88), roughness: 0.5);

    // Footing and mast (static).
    final foot = MeshBatch()..box(vm.Vector3(0, 0.3, 0), vm.Vector3(2.8, 0.6, 2.8));
    _root.add(Node(name: 'crane footing', mesh: Mesh(foot.build(), concrete), localTransform: trs(vm.Vector3(mx, 0, mz)))..shadowStatic = true);
    final mast = MeshBatch();
    latticeMast(mast, w: 1.15, y0: 0.6, y1: jibY - 0.5, section: 1.3, post: 0.12, brace: 0.06);
    _root.add(Node(name: 'crane mast', mesh: Mesh(mast.build(), yellow), localTransform: trs(vm.Vector3(mx, 0, mz)))..shadowStatic = true);

    // The slewing part, in its own frame (jib towards −x).
    final steel = MeshBatch();
    triangularTruss(steel, x0: -0.7, x1: -24.6, w: 0.95, h: 1.15, chord: 0.11, brace: 0.055, panel: 1.15);
    // Counter-jib: two chords, cross members, a walkway.
    for (final z in [-0.5, 0.5]) {
      steel.beam(vm.Vector3(0.7, 0.05, z), vm.Vector3(8.0, 0.05, z), 0.13);
    }
    for (var x = 0.9; x <= 8.0; x += 1.0) {
      steel.beam(vm.Vector3(x, 0.05, -0.5), vm.Vector3(x, 0.05, 0.5), 0.07);
    }
    // Tower head and pendant ties.
    final apex = vm.Vector3(0, 4.6, 0);
    for (final c in [vm.Vector3(-0.55, 0.2, -0.55), vm.Vector3(0.55, 0.2, -0.55), vm.Vector3(0.55, 0.2, 0.55), vm.Vector3(-0.55, 0.2, 0.55)]) {
      steel.beam(c, apex, 0.12);
    }
    steel.beam(vm.Vector3(-0.55, 2.2, -0.55), vm.Vector3(0.55, 2.2, 0.55), 0.06);
    steel.beam(vm.Vector3(0.55, 2.2, -0.55), vm.Vector3(-0.55, 2.2, 0.55), 0.06);
    _slew.add(Node(name: 'jib', mesh: Mesh(steel.build(), yellow)));
    final ties = MeshBatch()
      ..beam(apex, vm.Vector3(-15.5, 1.25, 0), 0.05)
      ..beam(apex, vm.Vector3(-7.5, 1.25, 0), 0.05)
      ..beam(apex, vm.Vector3(7.8, 0.15, -0.45), 0.05)
      ..beam(apex, vm.Vector3(7.8, 0.15, 0.45), 0.05);
    final deck = MeshBatch()
      ..box(vm.Vector3(4.4, 0.13, 0), vm.Vector3(7.2, 0.05, 1.0)) // walkway
      ..box(vm.Vector3(0, -0.1, 0), vm.Vector3(1.9, 0.3, 1.9)) // turntable
      ..box(vm.Vector3(2.0, 0.45, 0), vm.Vector3(1.4, 0.75, 0.9)); // hoist winch house
    _slew.add(Node(name: 'jib ties', mesh: Mesh(ties.build(), dark)));
    _slew.add(Node(name: 'jib deck', mesh: Mesh(deck.build(), dark)));
    final weights = MeshBatch();
    for (var i = 0; i < 4; i++) {
      weights.box(vm.Vector3(5.7 + i * 0.62, -0.55, 0), vm.Vector3(0.56, 1.7, 1.3));
    }
    _slew.add(Node(name: 'counterweights', mesh: Mesh(weights.build(), concrete)));
    // A slewing ring under the turntable.
    _slew.add(Node(name: 'slewing ring', mesh: Mesh(CylinderGeometry(bottomRadius: 0.75, topRadius: 0.75, height: 0.3, radialSegments: 20), dark), localTransform: trs(vm.Vector3(0, -0.4, 0))));
    // The operator's cab: a frame with glass all round, at the side of the
    // mast head, looking down the jib.
    final cabFrame = MeshBatch();
    const cw = 1.25, ch = 1.25, cd = 1.25;
    final c0 = vm.Vector3(-0.95, -1.45, 1.2); // cab floor centre
    for (final sx in [-1, 1]) {
      for (final sz in [-1, 1]) {
        final p = c0 + vm.Vector3(sx * cw / 2, 0, sz * cd / 2);
        cabFrame.beam(p, p + vm.Vector3(0, ch, 0), 0.08);
      }
    }
    cabFrame
      ..box(c0 + vm.Vector3(0, ch, 0), vm.Vector3(cw + 0.1, 0.12, cd + 0.1)) // roof
      ..box(c0 + vm.Vector3(0, 0.05, 0), vm.Vector3(cw + 0.06, 0.1, cd + 0.06)) // floor
      ..box(c0 + vm.Vector3(0.2, 0.35, 0.45), vm.Vector3(0.75, 0.55, 0.3)); // console
    _slew.add(Node(name: 'cab frame', mesh: Mesh(cabFrame.build(), white)));
    final glass = pbr(rgb(0.25, 0.45, 0.6, 0.28), roughness: 0.08, metallic: 0.1)
      ..alphaMode = AlphaMode.blend
      ..emissiveFactor = rgb(0.2, 0.5, 0.8)
      ..emissiveStrength = 0.06;
    final panes = MeshBatch()..box(c0 + vm.Vector3(0, ch * 0.55, 0), vm.Vector3(cw - 0.02, ch * 0.8, cd - 0.02));
    _slew.add(Node(name: 'cab glass', mesh: Mesh(panes.build(), glass))..castsShadows = false);
    // Aviation lights: the apex and the jib tip.
    _beacon = pbr(rgb(1, 0.1, 0.08), emissive: rgb(1, 0.08, 0.05), emissiveStrength: 4);
    final bulb = SphereGeometry(radius: 0.13, segments: 10, rings: 6);
    _slew.add(Node(name: 'beacon apex', mesh: Mesh(bulb, _beacon), localTransform: trs(apex + vm.Vector3(0, 0.15, 0)))..castsShadows = false);
    _slew.add(Node(name: 'beacon tip', mesh: Mesh(bulb, _beacon), localTransform: trs(vm.Vector3(-24.6, 1.35, 0)))..castsShadows = false);

    // Trolley (rides the jib's bottom chords).
    final trolley = MeshBatch()
      ..box(vm.Vector3(0, -0.05, 0), vm.Vector3(0.95, 0.22, 1.15))
      ..box(vm.Vector3(0, -0.28, 0), vm.Vector3(0.5, 0.3, 0.32));
    _trolley.mesh = Mesh(trolley.build(), dark);
    _slew.add(_trolley);
    _root.add(_slew);

    // Hoist cable, hook block, wrecking ball (world space).
    _cable.mesh = Mesh(CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 6, topCap: false, bottomCap: false), dark);
    _root.add(_cable);
    final block = MeshBatch()
      ..box(vm.Vector3(0, 0.2, 0), vm.Vector3(0.42, 0.5, 0.3))
      ..box(vm.Vector3(0, -0.12, 0), vm.Vector3(0.12, 0.2, 0.12));
    _hook.add(Node(mesh: Mesh(block.build(), pbr(lin(BP.coral), roughness: 0.5, metallic: 0.2))));
    _hook.add(Node(mesh: Mesh(TorusGeometry(radius: 0.13, tubeRadius: 0.04, radialSegments: 14, tubularSegments: 8), dark), localTransform: trs(vm.Vector3(0, -0.32, 0), rotX: math.pi / 2)));
    _root.add(_hook);
    _ball
      ..add(Node(mesh: Mesh(SphereGeometry(radius: 1.0, segments: 28, rings: 16), pbr(rgb(0.04, 0.04, 0.05), metallic: 0.85, roughness: 0.32))))
      ..add(Node(mesh: Mesh(TorusGeometry(radius: 0.22, tubeRadius: 0.07, radialSegments: 16, tubularSegments: 8), dark), localTransform: trs(vm.Vector3(0, 1.05, 0))))
      ..visible = false;
    _root.add(_ball);
    // Four slings for whatever hangs from the hook.
    _slings = InstancedMesh(geometry: CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 5, topCap: false, bottomCap: false), material: dark);
    for (var i = 0; i < 4; i++) {
      _slings.addInstance(hidden);
    }
    _root.add(Node(name: 'slings')..addComponent(InstancedMeshComponent(_slings)));
    scene.add(_root);
  }

  final _m = vm.Matrix4.identity();
  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero(), _up = vm.Vector3.zero();

  // The hook's own horizontal position and velocity: a damped pendulum
  // pulled along under the trolley.
  final _p = vm.Vector3.zero(), _v = vm.Vector3.zero();
  bool _first = true;
  bool _ballHanging = false;

  /// Moves the crane so the hook block heads for [target]: slews, runs the
  /// trolley out or in, hoists, and lets the hook swing behind a little.
  /// [ballAt] puts the wrecking ball there on its cable (a free swing).
  void update(vm.Vector3 target, double t, double dt, {double night = 0, vm.Vector3? ballAt}) {
    final dx = target.x - mx, dz = target.z - mz;
    radius = math.max(2.6, math.sqrt(dx * dx + dz * dz));
    slew = math.atan2(dz, -dx);
    _slew.place((m) => setTrs(m, mx, jibY, mz, yaw: slew));
    _trolley.place((m) => setTrs(m, -radius, -0.02, 0));
    final c = math.cos(slew), s = math.sin(slew);
    final tx = mx - radius * c, tz = mz + radius * s, ty = jibY - 0.45;

    // Pendulum: spring towards the trolley, underdamped, small steps.
    if (_first || (_p.x - tx).abs() + (_p.z - tz).abs() > 4) {
      _first = false;
      _p.setValues(tx, 0, tz);
      _v.setZero();
    }
    var left = math.min(dt, 0.5);
    while (left > 1e-6) {
      final h = math.min(left, 1 / 60);
      left -= h;
      const k = 7.0, damp = 2.2;
      _v.x += (k * (tx - _p.x) - damp * _v.x) * h;
      _v.z += (k * (tz - _p.z) - damp * _v.z) * h;
      _p.x += _v.x * h;
      _p.z += _v.z * h;
    }
    sway.setValues((_p.x - tx).clamp(-0.5, 0.5), 0, (_p.z - tz).clamp(-0.5, 0.5));
    if (ballAt != null) {
      sway.setZero();
      _p.setValues(tx, 0, tz);
      _v.setZero();
    }

    hook.setValues(tx + sway.x, math.min(target.y, jibY - 1.2), tz + sway.z);
    if (ballAt != null) hook.setFrom(ballAt);
    _a.setValues(tx, ty, tz);
    _b.setValues(hook.x, hook.y + 0.45, hook.z);
    _cable.place((m) => setSpan(m, _a, _b, thickness: 0.035));
    // The hook block hangs along its cable.
    _up
      ..setFrom(_a)
      ..sub(_b)
      ..normalize()
      ..add(hook);
    _hook.place((m) => setSpan(m, hook, _up, stretch: false).setTranslationRaw(hook.x, hook.y, hook.z));
    _ball.visible = ballAt != null || _ballHanging;
    if (_ball.visible) {
      _ball.place((m) => setTrs(m, hook.x, hook.y - 1.55, hook.z));
    }
    // The operator's seat (world): in the cab, facing down the jib.
    const sx = -0.8, sy = -1.33, sz = 1.0;
    seat.setValues(mx + sx * c + sz * s, jibY + sy, mz - sx * s + sz * c);
    seatYaw = slew + math.pi / 2;
    // The beacons blink, brighter at night.
    final blink = (t * 0.8) % 1.0 < 0.18 ? 1.0 : 0.12;
    _beacon.emissiveStrength = (1.5 + 10 * night) * blink;
  }

  /// The wrecking ball hangs from the hook (when not swinging free).
  set ballHanging(bool v) => _ballHanging = v;

  /// Where the ball is when hanging from the hook.
  vm.Vector3 get ballCenter => vm.Vector3(hook.x, hook.y - 1.55, hook.z);

  /// Slings from the hook down to the four corners of a load whose top
  /// centre is [top] (half-size [hx] × [hz]); null hides them.
  void slings(vm.Vector3? top, {double hx = 0.5, double hz = 0.5}) {
    for (var i = 0; i < 4; i++) {
      if (top == null) {
        _slings.setInstanceTransform(i, hidden);
        continue;
      }
      _a.setValues(top.x + (i.isEven ? -hx : hx), top.y, top.z + (i < 2 ? -hz : hz));
      _b.setValues(hook.x, hook.y - 0.36, hook.z);
      _slings.setInstanceTransform(i, setSpan(_m, _a, _b, thickness: 0.018));
    }
  }

  /// A swinging ball: its cable runs from the trolley to the ball.
  void swingBall(vm.Vector3 pivot, vm.Vector3 center, double t, double dt, {double night = 0}) {
    // Put the trolley over the pivot, then draw the cable to the ball.
    update(vm.Vector3(pivot.x, pivot.y, pivot.z), t, dt, night: night, ballAt: center + vm.Vector3(0, 1.55, 0));
  }
}
