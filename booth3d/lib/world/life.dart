import 'dart:math' as math;
import 'dart:ui' show Color, FontWeight, FontVariation, Paint, Rect, RRect, Radius;

import 'package:flutter/painting.dart' show Alignment, LinearGradient, Offset, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'figure.dart';
import 'motion.dart';
import 'kit.dart';
import 'script_alley.dart' show AlleyLayout, alleyRules;
import 'site_geo.dart' show NodePlace;

/// Life in Name City: people walking the sidewalks and the park (in jackets,
/// coats and skirts, with bags, backpacks and the odd parasol; children
/// with school caps and randoseru), stopping to watch the build and
/// cheering when a name is done; workers in hard hats round the site; cars,
/// taxis and buses that stop at the lights (Japan keeps left) while people
/// cross; birds by day and a blimp for the talk.
///
/// Everything is instanced (a handful of draws), stepped with the model so
/// frames, fast-forward and capture agree, and bounded (fixed populations).
class Life3D {
  Life3D(this.scene);

  final Scene scene;

  final _people = _People();
  final _traffic = _Traffic();
  late final _Signals _signals;
  late final _Birds _birds;
  late final _Blimp _blimp;
  double _t = 0;

  Future<void> init() async {
    _people.build(scene);
    _traffic.build(scene);
    _signals = _Signals(scene);
    _birds = _Birds(scene);
    _blimp = _Blimp(scene);
    await _blimp.build();
  }

  /// How often people walked into each other (capture runs).
  String overlapReport() => _people.overlapReport();

  /// Steps the life by [dt] (sub-stepped when fast-forwarding) and poses it
  /// for [camera] (anything right at the camera steps out of its way).
  /// Traffic and people make way for [work] (the site's delivery truck);
  /// people walk round each other and [others] (the site's people out on
  /// the pavement: the new manager's party, the driver).
  void update(BoothModel m, double dt, {required vm.Vector3 camera, required double wallWidth, required double night, StreetWork? work, List<vm.Vector3> others = const []}) {
    var left = dt;
    while (left > 1e-6) {
      final h = math.min(left, 0.1);
      _t = m.t - left + h;
      _traffic.step(_t, h, m.job?.phase, work);
      _people.step(_t, h, m, wallWidth, work, others);
      left -= h;
    }
    _t = m.t;
    _traffic.pose(camera, night);
    _people.pose(_t, camera, m, night, work);
    _signals.pose(_t, night);
    _birds.pose(_t, night);
    _blimp.pose(_t, night);
  }
}

/// Something on the city's streets that traffic and people make way for
/// (the site's delivery truck): asked at every step of the simulation.
abstract interface class StreetWork {
  /// The stretch of the eastbound (else westbound) avenue lane blocked at
  /// [t], as x from..to, or null. Cars coming up to it stop short and
  /// follow it; cars already level with it carry on.
  (double, double)? laneBlock(bool eastbound, double t);

  /// The site gate on the front sidewalk at [t]: x from..to while the truck
  /// is about to go or is going through it (people wait either side), or
  /// null.
  (double, double)? gateBusy(double t);
}

// ── Signals ─────────────────────────────────────────────────────────────────

/// One 34 s cycle for both intersections: the avenue, then the side streets.
/// People cross the avenue while it is red, the side streets while they are.
/// (The site's delivery truck times its trips by it too.)
abstract final class TrafficLights {
  static const cycle = 34.0;
  static double _p(double t) => t % cycle;
  static bool aveGo(double t) => _p(t) < 18;
  static bool aveAmber(double t) => _p(t) >= 18 && _p(t) < 21;
  static bool sideGo(double t) => _p(t) >= 22.5 && _p(t) < 30;
  static bool sideAmber(double t) => _p(t) >= 30 && _p(t) < 32;

  /// People may step onto the avenue's crossings: once cars that went
  /// through on amber are clear, and early enough to be over before green.
  static bool walkAve(double t) => _p(t) >= 23 && _p(t) < 26.5;

  /// …and the side streets, while the avenue has its green.
  static bool walkSide(double t) => _p(t) >= 1.5 && _p(t) < 15;
}

class _Signals {
  _Signals(Scene scene) {
    final dark = pbr(lin(const Color(0xFF1B2433)), metallic: 0.5, roughness: 0.5);
    final poles = InstancedMesh(geometry: CylinderGeometry(bottomRadius: 0.1, topRadius: 0.08, height: 5.4, radialSegments: 10), material: dark);
    final arms = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(1, 1, 1)), material: dark);
    final heads = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(1.25, 0.42, 0.3)), material: dark);
    _lampMat = UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    _lamps = InstancedMesh(geometry: SphereGeometry(radius: 0.13, segments: 10, rings: 6), material: _lampMat);
    // Poles on the outer corners; mast arms reach over the avenue.
    for (final s in [-1.0, 1.0]) {
      final px = s * (Plan.streetX + Plan.streetHalf + 0.9);
      for (final (pz, lane, face) in [(Plan.aveZ1 + 0.9, Plan.laneEast, 1.0), (Plan.aveZ0 - 2.15, Plan.laneWest, -1.0)]) {
        poles.addInstance(trs(vm.Vector3(px, 2.7, pz)));
        final reach = (pz - lane).abs() + 0.6;
        arms.addInstance(trs(vm.Vector3(px, 5.25, pz - face * reach / 2), s: vm.Vector3(0.12, 0.12, reach)));
        // A head over the lane, facing the oncoming traffic (along x).
        final hz = lane;
        final hx = px;
        heads.addInstance(trs(vm.Vector3(hx, 5.0, hz), rotY: math.pi / 2));
        for (var k = 0; k < 3; k++) {
          // Green, amber, red from the kerb side outwards.
          final at = vm.Vector3(hx - s * 0.17, 5.0, hz + (k - 1) * 0.38 * face);
          _heads.add(_Head(_lamps.addInstance(trs(at)), k, avenue: true));
        }
        // A head on the pole for the side street, facing it.
        final sz = pz + face * 0.25;
        heads.addInstance(trs(vm.Vector3(px - s * 0.35, 4.2, sz)));
        for (var k = 0; k < 3; k++) {
          final at = vm.Vector3(px - s * 0.35 + (k - 1) * 0.38, 4.2, sz - face * 0.17);
          _heads.add(_Head(_lamps.addInstance(trs(at)), k, avenue: false));
        }
      }
    }
    for (final m in [poles, arms, heads, _lamps]) {
      scene.add(
        Node(name: 'signals')
          ..lightChannelMask = 0x01
          ..addComponent(InstancedMeshComponent(m)),
      );
    }
  }

  late final UnlitMaterial _lampMat;
  late final InstancedMesh _lamps;
  final _heads = <_Head>[];
  static final _off = vm.Vector4(0.08, 0.09, 0.11, 1);
  static final _colors = [vm.Vector4(0.15, 1.0, 0.55, 1), vm.Vector4(1.0, 0.72, 0.1, 1), vm.Vector4(1.0, 0.12, 0.12, 1)];

  void pose(double t, double night) {
    final k = 1.8 + 3.5 * night;
    _lampMat.baseColorFactor = vm.Vector4(k, k, k, 1);
    for (final h in _heads) {
      final go = h.avenue ? TrafficLights.aveGo(t) : TrafficLights.sideGo(t);
      final amber = h.avenue ? TrafficLights.aveAmber(t) : TrafficLights.sideAmber(t);
      final which = go ? 0 : (amber ? 1 : 2);
      _lamps.setInstanceColor(h.index, which == h.kind ? _colors[h.kind] : _off);
    }
  }
}

class _Head {
  _Head(this.index, this.kind, {required this.avenue});
  final int index, kind;
  final bool avenue;
}

// ── Traffic ─────────────────────────────────────────────────────────────────

enum _Kind { sedan, kei, taxi, van, bus }

class _Car {
  _Car(this.kind, this.lane, this.s, this.length);
  final _Kind kind;
  final _Lane lane;
  double s; // along the lane
  double v = 0;
  final double length;
  int index = 0; // instance index within its kind
  bool shown = true;
}

class _Lane {
  _Lane(this.x0, this.z0, this.dx, this.dz, this.length, this.stops, {required this.avenue});
  final double x0, z0, dx, dz, length;

  /// Stop lines (distance along the lane) and whether they belong to an
  /// avenue signal (or the side streets').
  final List<double> stops;
  final bool avenue;
  final cars = <_Car>[];
  double get heading => headingTo(dx, dz);
}

class _Traffic {
  final _lanes = <_Lane>[];
  final _meshes = <_Kind, (InstancedMesh, InstancedMesh)>{};
  final _cars = <_Car>[];
  late final UnlitMaterial _lightMat;
  late final PhysicallyBasedMaterial _taxiSignMat;

  static const _vmax = 11.0, _accel = 2.6, _brake = 3.4;

  static double _len(_Kind k) => switch (k) {
    _Kind.sedan => 4.4,
    _Kind.kei => 3.4,
    _Kind.taxi => 4.5,
    _Kind.van => 4.8,
    _Kind.bus => 10.5,
  };

  void build(Scene scene) {
    _lightMat = UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    _taxiSignMat = pbr(lin(BP.amber), roughness: 0.4, emissive: lin(BP.amber), emissiveStrength: 0.2);
    final paint = pbr(rgb(1, 1, 1), roughness: 0.32, metallic: 0.25);
    for (final k in _Kind.values) {
      final body = InstancedMesh(geometry: _bodyGeometry(k), material: paint);
      final lights = InstancedMesh(geometry: _lightGeometry(k), material: _lightMat);
      _meshes[k] = (body, lights);
      // (Cars take the street lamps' light at night, unlike the city.)
      for (final m in [body, lights]) {
        scene.add(Node(name: 'traffic ${k.name}')..addComponent(InstancedMeshComponent(m)));
      }
    }
    // Roof signs for the taxis (andon).
    _taxiSigns = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(0.5, 0.22, 0.18)), material: _taxiSignMat);
    scene.add(Node(name: 'taxi signs')..addComponent(InstancedMeshComponent(_taxiSigns)));

    const far = 300.0;
    final sx = Plan.streetX, sh = Plan.streetHalf;
    // The avenue: eastbound stops before the west intersection and before
    // the crosswalk at the east corner of the plaza; westbound mirrored.
    final ex = Plan.crossX[1] - Plan.crossHalf - 1.0;
    _lanes.add(_Lane(-far, Plan.laneEast, 1, 0, 2 * far, [far - sx - sh - 1.0, far + ex], avenue: true));
    _lanes.add(_Lane(far, Plan.laneWest, -1, 0, 2 * far, [far - sx - sh - 1.0, far + ex], avenue: true));
    // Side streets (both sides), each way.
    for (final s in [-1.0, 1.0]) {
      final xc = s * sx;
      // Northbound keeps to the west half, southbound the east half.
      _lanes.add(_Lane(xc - 1.75, -far, 0, 1, 2 * far, [far + Plan.aveZ0 - 3.8], avenue: false));
      _lanes.add(_Lane(xc + 1.75, far, 0, -1, 2 * far, [far - Plan.aveZ1 - 3.6], avenue: false));
    }
    var seed = 0;
    for (final lane in _lanes) {
      final n = lane.avenue ? 22 : 11;
      for (var i = 0; i < n; i++) {
        seed++;
        final r = rnd(seed, 1);
        final kind = lane.avenue
            ? (r < 0.4 ? _Kind.sedan : r < 0.62 ? _Kind.taxi : r < 0.82 ? _Kind.kei : r < 0.94 ? _Kind.van : _Kind.bus)
            : (r < 0.45 ? _Kind.sedan : r < 0.65 ? _Kind.kei : r < 0.85 ? _Kind.taxi : _Kind.van);
        final color = switch (kind) {
          _Kind.taxi => vm.Vector4(1, 1, 1, 1),
          _Kind.bus => vm.Vector4(1, 1, 1, 1),
          _ => v4(hex3(_paints[seed % _paints.length])),
        };
        final car = _Car(kind, lane, lane.length * (i + 0.3 * rnd(seed, 2)) / n, _len(kind));
        lane.cars.add(car);
        _cars.add(car);
        final (body, lights) = _meshes[kind]!;
        car.index = body.addInstance(hidden, color: color);
        lights.addInstance(hidden);
        if (kind == _Kind.taxi) _taxiSigns.addInstance(hidden);
      }
    }
  }

  late final InstancedMesh _taxiSigns;

  static const _paints = [0xF4F1EA, 0xD9DEE6, 0x2B3A55, 0xE8505F, 0x5FB8FF, 0x6CE5B1, 0x111827, 0xFFC66D, 0xC39BFF, 0xF4F1EA, 0x8DA3BC];

  /// Cars follow the one ahead and stop at red (or amber, when they can).
  /// During the site's cleanup the side streets are held so the truck can
  /// cross them; the delivery truck's stretch of an avenue lane ([work]) is
  /// kept clear.
  void step(double t, double dt, Phase? phase, StreetWork? work) {
    final holdSides = phase == Phase.cleanup;
    for (final lane in _lanes) {
      final cars = lane.cars;
      cars.sort((a, b) => a.s.compareTo(b.s));
      final go = lane.avenue ? TrafficLights.aveGo(t) : (TrafficLights.sideGo(t) && !holdSides);
      final amber = lane.avenue ? TrafficLights.aveAmber(t) : TrafficLights.sideAmber(t);
      // Where the blocked stretch begins, along the lane (cars come from below).
      var blockAt = double.infinity;
      if (lane.avenue) {
        if (work?.laneBlock(lane.dx > 0, t) case (final x0, final x1)) {
          blockAt = lane.dx > 0 ? x0 - lane.x0 : lane.x0 - x1;
        }
      }
      for (var i = cars.length - 1; i >= 0; i--) {
        final c = cars[i];
        // The car ahead (the first wraps round to the last, a lap ahead).
        final ahead = i == cars.length - 1 ? cars.first : cars[i + 1];
        final aheadS = i == cars.length - 1 ? ahead.s + lane.length : ahead.s;
        var limit = aheadS - ahead.length / 2 - c.length / 2 - 2.2;
        if (c.s + c.length / 2 < blockAt - 0.3) limit = math.min(limit, blockAt - 1.6 - c.length / 2);
        if (!go) {
          for (final stop in lane.stops) {
            final front = c.s + c.length / 2;
            final gap = stop - front;
            if (gap < -0.5) continue; // already past it
            // On amber, go on if too close to stop comfortably.
            if (amber && gap < c.v * c.v / (2 * _brake * 1.6)) continue;
            limit = math.min(limit, stop - c.length / 2);
            break;
          }
        }
        final room = math.max(0.0, limit - c.s);
        final cap = math.min(_vmax * (c.kind == _Kind.bus ? 0.8 : 1), math.sqrt(2 * _brake * room));
        c.v = c.v < cap ? math.min(cap, c.v + _accel * dt) : cap;
        c.s = math.min(c.s + c.v * dt, math.max(c.s, limit));
      }
      for (final c in cars) {
        if (c.s >= lane.length) c.s -= lane.length;
      }
    }
  }

  void pose(vm.Vector3 camera, double night) {
    final k = 1.0 + 7.0 * night;
    _lightMat.baseColorFactor = vm.Vector4(k, k, k, 1);
    _taxiSignMat.emissiveStrength = 0.25 + 5 * night;
    final low = camera.y < 6.5;
    for (final kind in _Kind.values) {
      final (body, lights) = _meshes[kind]!;
      body.updateInstanceTransforms((list) {
        for (final c in _cars) {
          if (c.kind != kind) continue;
          final l = c.lane;
          final x = l.x0 + l.dx * c.s, z = l.z0 + l.dz * c.s;
          final cdx = x - camera.x, cdz = z - camera.z;
          final r = c.length / 2 + (c.kind == _Kind.bus ? 7 : 3.5);
          // Right at a low camera: step out of the shot (never seen: the car
          // is then beside or under the lens).
          c.shown = !(low && cdx * cdx + cdz * cdz < r * r);
          setTrsY(list[c.index], x, Plan.road, z, l.heading, c.shown ? 1 : 0);
        }
      });
      lights.updateInstanceTransforms((list) {
        for (final c in _cars) {
          if (c.kind != kind) continue;
          final l = c.lane;
          setTrsY(list[c.index], l.x0 + l.dx * c.s, Plan.road, l.z0 + l.dz * c.s, l.heading, c.shown ? 1 : 0);
        }
      });
    }
    _taxiSigns.updateInstanceTransforms((list) {
      var i = 0;
      for (final c in _cars) {
        if (c.kind != _Kind.taxi) continue;
        final l = c.lane;
        setTrsY(list[i++], l.x0 + l.dx * c.s, Plan.road + 1.58, l.z0 + l.dz * c.s, l.heading, c.shown ? 1 : 0);
      }
    });
  }

  // ── Vehicle models (one merged, vertex-coloured mesh per kind) ───────────

  static final _glass = v4(hex3(0x1A2C46));
  static final _tyre = v4(hex3(0x14171D));
  static final _trim = v4(hex3(0x2A3344));

  static MeshData _wheel(double x, double z, double r) => part(
    CylinderGeometry(bottomRadius: r, topRadius: r, height: 0.24, radialSegments: 12),
    trs(vm.Vector3(x, r, z), rotX: math.pi / 2),
    _tyre,
  );

  static MeshData _box(double x, double y, double z, double w, double h, double d, vm.Vector4 c) =>
      part(CuboidGeometry(vm.Vector3(w, h, d)), vm.Matrix4.translation(vm.Vector3(x, y, z)), c);

  /// Length along +X; the body colour is white (tinted per instance).
  static MeshGeometry _bodyGeometry(_Kind k) {
    final white = vm.Vector4(1, 1, 1, 1);
    switch (k) {
      case _Kind.sedan:
        return merged([
          _box(0, 0.62, 0, 4.4, 0.62, 1.78, white),
          _box(-0.25, 1.15, 0, 2.3, 0.5, 1.6, _glass),
          _box(-0.25, 1.41, 0, 2.1, 0.06, 1.5, white),
          _box(2.18, 0.45, 0, 0.12, 0.24, 1.7, _trim),
          _box(-2.18, 0.45, 0, 0.12, 0.24, 1.7, _trim),
          for (final x in [-1.35, 1.35]) for (final z in [-0.82, 0.82]) _wheel(x, z, 0.33),
        ]);
      case _Kind.taxi:
        final indigo = v4(hex3(0x1E2C52));
        return merged([
          _box(0, 0.62, 0, 4.5, 0.62, 1.74, indigo),
          _box(-0.2, 1.17, 0, 2.4, 0.52, 1.58, _glass),
          _box(-0.2, 1.44, 0, 2.2, 0.06, 1.5, indigo),
          _box(0, 0.6, 0, 4.52, 0.08, 1.76, v4(lin3(BP.amber))),
          for (final x in [-1.4, 1.4]) for (final z in [-0.8, 0.8]) _wheel(x, z, 0.33),
        ]);
      case _Kind.kei:
        return merged([
          _box(0, 0.75, 0, 3.4, 0.9, 1.48, white),
          _box(-0.15, 1.45, 0, 2.6, 0.55, 1.4, _glass),
          _box(-0.15, 1.75, 0, 2.6, 0.08, 1.44, white),
          for (final x in [-1.1, 1.1]) for (final z in [-0.66, 0.66]) _wheel(x, z, 0.29),
        ]);
      case _Kind.van:
        return merged([
          _box(0, 1.05, 0, 4.8, 1.55, 1.8, white),
          _box(1.75, 1.45, 0, 1.0, 0.6, 1.82, _glass),
          _box(-0.6, 1.5, 0, 2.8, 0.45, 1.82, _glass),
          for (final x in [-1.55, 1.55]) for (final z in [-0.82, 0.82]) _wheel(x, z, 0.34),
        ]);
      case _Kind.bus:
        final cream = v4(hex3(0xF2EEE4));
        final stripe = v4(lin3(BP.green));
        return merged([
          _box(0, 1.75, 0, 10.5, 2.75, 2.5, cream),
          _box(0, 2.15, 0, 10.52, 0.95, 2.52, _glass),
          _box(0, 0.78, 0, 10.52, 0.22, 2.52, stripe),
          _box(5.2, 1.6, 0, 0.12, 2.0, 2.3, _glass),
          _box(0, 3.15, 0, 9.5, 0.08, 2.3, v4(hex3(0xDCD6C8))),
          for (final x in [-3.6, 3.4]) for (final z in [-1.15, 1.15]) _wheel(x, z, 0.5),
        ]);
    }
  }

  /// Head lamps (warm white) and tail lamps (red), lit at night.
  static MeshGeometry _lightGeometry(_Kind k) {
    final l = _len(k) / 2;
    final (y, w, gap) = switch (k) {
      _Kind.bus => (0.95, 0.3, 0.95),
      _Kind.van => (0.75, 0.24, 0.7),
      _Kind.kei => (0.7, 0.2, 0.56),
      _ => (0.66, 0.24, 0.66),
    };
    final front = vm.Vector4(1.0, 0.94, 0.78, 1), rear = vm.Vector4(1.0, 0.1, 0.12, 1);
    return merged([
      for (final z in [-gap, gap]) ...[
        _box(l + 0.02, y, z, 0.06, 0.14, w, front),
        _box(-l - 0.02, y, z, 0.06, 0.14, w, rear),
      ],
    ]);
  }
}

// ── People ──────────────────────────────────────────────────────────────────

class _Route {
  _Route(this.pts, {this.crossing = const {}, this.watch = const [], this.alley = false}) {
    var acc = 0.0;
    cum.add(0);
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      acc += math.sqrt((b.$1 - a.$1) * (b.$1 - a.$1) + (b.$2 - a.$2) * (b.$2 - a.$2));
      cum.add(acc);
    }
  }

  /// A closed loop of (x, z).
  final List<(double, double)> pts;

  /// Segments that cross a road (index of the segment's start point): true
  /// for the avenue, false for a side street.
  final Map<int, bool> crossing;

  /// Distances along the route where people may stop to watch the build.
  final List<double> watch;

  /// The park's long path: its stops are at the alley's stalls (people
  /// there turn to the stall on their side).
  final bool alley;
  final cum = <double>[];
  double get length => cum.last;

  int segmentAt(double d) {
    var i = 0;
    while (i < pts.length - 1 && d >= cum[i + 1]) {
      i++;
    }
    return i;
  }
}

enum _Role { walker, spectator, worker, keeper }

class _Person {
  _Person(this.role, this.route, this.d, this.dir, this.speed, this.side, this.scale);
  final _Role role;
  final _Route? route;
  double d; // along the route
  final double dir; // +1 or −1
  final double speed;
  final double side; // how far left of the route's line (keeping left)
  final double scale;
  double x = 0, z = 0, heading = 0;

  /// The walk's phase (radians, π a step: see [Gait]).
  double stride = 0;

  /// How fast they're going now (m/s, along the way: speeding up and
  /// slowing down take a moment), and their way of moving.
  double vel = 0;
  late final Manner manner;
  double pause = 0; // seconds left watching
  bool waiting = false;
  int lap = 0;
  int lastWatch = -1;
  double phase = 0; // idle animation offset
  // Workers and spectators stand at a spot (relative for workers).
  double homeX = 0, homeZ = 0, awayX = 0, awayZ = 0;
  bool hat = false;
  bool moving = false;
  bool placed = false;
  bool guiding = false; // the corner's worker, guiding the delivery truck
  int job = 0; // workers: 0 by the wall, 1 at the corner, 2 behind the wall
  int index = 0;
  int slot = 0; // among the figures (figure.dart)
  int stall = -1; // keepers: their stall in the alley
  int crewNo = 0; // workers: which of them
  // Walking round people: how far aside of their line (left +), which way
  // they face along it (unit x, z), and how fast they go (m/s).
  double dodge = 0, fx = 1, fz = 0, v = 0;
  bool bag = false, parasol = false;
}

class _People {
  final _all = <_Person>[];
  late final Figures _figures;

  /// The walk past the plaza's front (its first leg runs along the front
  /// sidewalk, past the site gate).
  late final _Route _front;

  /// The flagman's light baton (誘導灯), lit while he guides the truck.
  final _baton = Node(name: 'light baton');
  late final UnlitMaterial _batonMat;

  void build(Scene scene) {
    _figures = Figures.of(scene);
    _batonMat = UnlitMaterial()..baseColorFactor = vm.Vector4(4, 0.4, 0.2, 1);
    scene.add(
      _baton
        ..mesh = Mesh(CylinderGeometry(bottomRadius: 0.028, topRadius: 0.028, height: 0.5, radialSegments: 8), _batonMat)
        ..castsShadows = false
        ..visible = false,
    );

    const fx = Plan.peopleFlank, fz = Plan.peopleFront;
    final far0 = Plan.peopleFar[0], far1 = Plan.peopleFar[1];
    // The far sidewalk's kerbs either side of each side street.
    const ex = Plan.streetX + Plan.streetHalf + 0.4, ix = Plan.streetX - Plan.streetHalf - 0.4;
    final routes = [
      // Round the plaza block and through the park.
      _Route([(-fx, fz), (fx, fz), (fx, Plan.parkZ0 + 15.5), (-fx, Plan.parkZ0 + 15.5)], watch: [5, 26, 41, 50, 117, 125]),
      // Over the avenue at the plaza's corners and back along the far side.
      _Route([
        (ix, far1),
        (Plan.crossX[1], far1),
        (Plan.crossX[1], fz),
        (Plan.crossX[0], fz),
        (Plan.crossX[0], far1),
        (-ix, far1),
      ], crossing: {1: true, 3: true}, watch: [14, 42]),
      // The far side beyond the side streets (crossing them on their green).
      for (final s in [-1.0, 1.0])
        _Route([
          (s * ix, far0),
          (s * ex, far0),
          (s * 95, far0),
          (s * 95, far1),
          (s * ex, far1),
          (s * ix, far1),
        ], crossing: {0: false, 4: false}),
      // The outer blocks' sidewalks.
      for (final s in [-1.0, 1.0])
        _Route([
          (s * Plan.peopleBlock[0], Plan.aveZ1 + 1.6),
          (s * Plan.peopleBlock[0], 86),
          (s * Plan.peopleBlock[1], 86),
          (s * Plan.peopleBlock[1], Plan.aveZ1 + 1.6),
        ]),
      // The park's long path, past the alley's stalls (stopping at them).
      _Route(
        [(-0.9, Plan.parkZ0 + 1), (-0.9, Plan.parkZ1 - 1), (0.9, Plan.parkZ1 - 1), (0.9, Plan.parkZ0 + 1)],
        watch: [
          for (final z in AlleyLayout.rowZ) z - Plan.parkZ0 - 1,
          for (final z in AlleyLayout.rowZ.reversed) 2 * (Plan.parkZ1 - Plan.parkZ0 - 2) + 1.8 - (z - Plan.parkZ0 - 1),
        ],
        alley: true,
      ),
    ];
    _front = routes[0];
    const counts = [24, 14, 5, 5, 8, 8, 8];
    var seed = 0;
    for (var r = 0; r < routes.length; r++) {
      for (var i = 0; i < counts[r]; i++) {
        seed++;
        final kid = rnd(seed, 9) < 0.1;
        final p = _Person(
          _Role.walker,
          routes[r],
          routes[r].length * (i + 0.5 * rnd(seed, 1)) / counts[r],
          rnd(seed, 2) < 0.5 ? 1 : -1,
          (1.05 + 0.4 * rnd(seed, 3)) * (kid ? 0.85 : 1),
          0.1 + 0.25 * rnd(seed, 4),
          kid ? 0.66 : 0.92 + 0.14 * rnd(seed, 5),
        )..phase = rnd(seed, 6) * 10;
        _add(p, seed);
      }
    }
    // Spectators at the plaza's front corners and flanks, each in a place
    // of their own (a step apart at least).
    for (var i = 0; i < 14; i++) {
      seed++;
      final s = i.isEven ? 1.0 : -1.0;
      final front = i < 8, k = front ? i ~/ 2 : (i - 8) ~/ 2;
      final p = _Person(_Role.spectator, null, 0, 1, 0, 0, 0.9 + 0.16 * rnd(seed, 5))..phase = rnd(seed, 6) * 10;
      final jitter = 0.1 * (rnd(seed, 1) - 0.5);
      // Leaning on the front fence, or at the plaza's edge on its flanks
      // (out of the walkers' way).
      if (front) {
        // (Not in front of the site gate, right of the 安全第一 banner, nor
        // the bay gate on the left.)
        // (Nor at the top of the crosswalks, by the plaza's corners.)
        p.homeX = s > 0 ? const [6.6, 8.5, 9.2, 9.9][k] + jitter : -(11.4 + 1.4 * k) + jitter;
        p.homeZ = Plan.plazaZ0 - 0.62 + 0.12 * rnd(seed, 2);
      } else {
        // (Not in front of the vending machines on the right, nor the bench
        // on the left.)
        p.homeX = s * (Plan.plazaX - 0.02 + 0.08 * rnd(seed, 3));
        p.homeZ = (s > 0 ? -4.0 : -7.2) + 2.4 * k + jitter;
      }
      _add(p, seed);
    }
    // The alley's keepers, behind their counters.
    for (var i = 0; i < 6; i++) {
      seed++;
      final at = AlleyLayout.keeper(i);
      final p = _Person(_Role.keeper, null, 0, 1, 0, 0, 0.94 + 0.1 * rnd(seed, 5))
        ..phase = rnd(seed, 6) * 10
        ..stall = i
        ..homeX = at.x
        ..homeZ = at.z
        ..heading = AlleyLayout.keeperHeading(i);
      _add(p, seed);
    }
    // Workers, in hard hats: two at each end of the wall, one minding the
    // corner by the 工事中 board, one walking the back of the site.
    for (var i = 0; i < 6; i++) {
      seed++;
      final p = _Person(_Role.worker, null, 0, 1, 0.9, 0, 0.98)
        ..phase = rnd(seed, 6) * 10
        ..crewNo = i;
      p.hat = true;
      p.job = i < 4 ? 0 : i - 3;
      final s = i.isEven ? 1.0 : -1.0;
      p.homeX = s; // which end of the wall
      p.homeZ = i < 2 ? -2.4 + 1.2 * rnd(seed, 2) : 0.4 + 1.4 * rnd(seed, 2);
      p.awayZ = p.homeZ + (rnd(seed, 3) - 0.5) * 2.5;
      p.awayX = 1.0 + 3.0 * rnd(seed, 4); // metres beyond the wall's end
      _add(p, seed);
    }
  }

  // Autumn in Tokyo: mostly muted, some colour (sRGB).
  static const _tops = [
    0x2B3A55, 0x1F2430, 0x5B6573, 0xC8B79A, 0x6B7B5A, 0xEDEBE6, 0xD9CDB8, 0x8C5A3C, 0x7A2E3A, 0x8DB7DA, //
    0x3A4C6E, 0x2E2E33, 0xB9BEC6, 0xE8505F, 0x2E6DA8, 0xC9A13E, 0x6CB59A, 0xA88FC9, 0xE58F6E, 0x4F6B4A,
  ];
  static const _shirts = [0xF2F0EA, 0xE4E6EA, 0x22262E, 0xB9BEC6, 0xDCE6F0, 0xEFE3CF];
  static const _bottoms = [0x2E4766, 0x1E2B40, 0x1C1F26, 0x24304A, 0xB5A27E, 0x5E6470, 0x5B4B3A, 0x2E4766, 0x1C1F26, 0x3B4250];
  static const _skirts = [0x24304A, 0x1C1F26, 0xC8B79A, 0xC9A13E, 0x6B6B45, 0x7A2E3A, 0x8C8F96, 0xD9CDB8];
  static const _shoes = [0xEDEDEA, 0x1B1C20, 0x5A3A26, 0x1B1C20, 0x7A7E86, 0xEDEDEA, 0x2A3348, 0x1B1C20, 0x8C5A3C, 0xB8343F];
  static const _skins = [0xEFD0BA, 0xE8C6AC, 0xF3D8C6, 0xE0BB9E, 0xD6AE90, 0xECCBB2, 0xC59A7C, 0x8E644B, 0xE4C2A6, 0xF5DCCB, 0xB08466, 0x6F4C39];
  static const _hairs = [0x1A1714, 0x1A1714, 0x2A211B, 0x1A1714, 0x3D2B20, 0x2A211B, 0x5A3F2C, 0x1A1714, 0x8F8B86, 0x7A5638, 0x1A1714, 0xC8C4BE, 0x2A211B, 0xB89462];
  static const _packs = [0x23262D, 0x2B3A55, 0x6B7280, 0x5B6A48, 0x7A2E3A, 0xC8B79A];
  static const _bags = [0xA87A4F, 0x1F2229, 0xD8CDB4, 0x2B3A55, 0x8C5A3C, 0xE8E2D4];

  /// What a person wears, from their seed: workers in the crew's hi-vis
  /// and hard hats; everyone else a top (or an open jacket over a shirt, or
  /// a long coat), trousers or a skirt, shoes, a hairstyle, maybe a bag, a
  /// backpack, a cap or a parasol. Children are smaller, with big heads,
  /// school caps and randoseru.
  FigureLook _lookOf(_Person p, int seed) {
    double r(int k) => rnd(seed, 20 + k);
    vm.Vector4 pick(List<int> from, int k) => rgbHex(from[(r(k) * from.length).floor() % from.length]);
    final kid = p.scale < 0.8;
    final l = FigureLook()
      ..size = p.scale
      ..girth = kid ? 0.95 : 0.9 + 0.25 * r(0) * r(0)
      ..slim = r(1) < 0.5
      ..skin = pick(_skins, 2)
      ..hairColor = pick(kid ? _hairs.sublist(0, 7) : _hairs, 3)
      ..shoes = pick(_shoes, 4);
    if (p.role == _Role.worker) {
      return l
        ..slim = false
        ..girth = 1.0
        ..hair = Hair.short
        ..top = rgbHex(0x3E4A5E)
        ..layer = lin(rnd(seed, 7) < 0.5 ? BP.amber : BP.coral)
        ..stripes = true
        ..gloves = rgbHex(0xE9E4D6)
        ..hardHat = rgbHex(0xFFD23F)
        ..legs = rgbHex(0x2B3A55)
        ..shoes = rgbHex(0x24211F);
    }
    l.hair = l.slim
        ? (r(5) < 0.35
              ? Hair.bob
              : r(5) < 0.75
              ? Hair.long
              : Hair.medium)
        : (r(5) < 0.65 ? Hair.short : Hair.medium);
    l.top = pick(_tops, 6);
    final style = r(7);
    if (style < 0.28) {
      // An open jacket over a shirt.
      l
        ..sleeves = l.top
        ..layer = l.top
        ..top = pick(_shirts, 8);
    } else if (style < 0.42 && !kid) {
      // A long coat.
      l
        ..skirt = l.top
        ..skirtLength = 1.2;
    }
    l.legs = pick(_bottoms, 9);
    if (p.role == _Role.keeper) {
      // A happi in the stall's colour over a white shirt.
      final c = lin(alleyRules[p.stall].color);
      return l
        ..top = rgbHex(0xF2F0EA)
        ..layer = c
        ..sleeves = c
        ..skirt = null;
    }
    if (l.slim && l.skirt == null && r(10) < 0.45) {
      l
        ..skirt = pick(_skirts, 11)
        ..skirtLength = r(12) < 0.5 ? 1.0 : 1.3
        ..shins = r(13) < 0.5 ? l.skin : rgbHex(0x2A2A30);
      l.legs = l.shins!;
    }
    if (kid) {
      if (r(14) < 0.7) l.backpack = r(15) < 0.5 ? rgbHex(0xB0222D) : rgbHex(0x1F2229);
      if (r(16) < 0.6) l.cap = rgbHex(0xF5D33C);
    } else {
      if (r(14) < 0.24) {
        l.backpack = pick(_packs, 15);
      } else if (r(16) < (l.slim ? 0.35 : 0.15)) {
        l.bag = pick(_bags, 17);
        p.bag = true;
      }
      if (r(18) < 0.07) l.cap = pick(const [0x1F2229, 0x2B3A55, 0xD9CDB8, 0xEDEBE6], 19);
      if (l.slim && p.role == _Role.walker && l.cap == null && r(20) < 0.08) {
        l.parasol = pick(const [0xF4F1EA, 0xF2B8C6, 0x2B3A55, 0xD9CDB8], 21);
        p.parasol = true;
      }
    }
    return l;
  }

  void _add(_Person p, int seed) {
    p
      ..index = _all.length
      ..manner = Manner.of(seed * 7 + 3)
      ..slot = _figures.add(_lookOf(p, seed));
    _all.add(p);
  }

  List<vm.Vector3> _others = const [];

  /// Walking round people (BOOTH3D_AVOID=0: not, to compare).
  static const _avoidOn = String.fromEnvironment('BOOTH3D_AVOID', defaultValue: '1') != '0';

  /// Capture runs count people walking into each other: frames looked at,
  /// pairs overlapping (summed over the frames), the deepest overlap.
  int _frames = 0, _bumps = 0;
  double _deepest = 0;

  final _kinds = <String, int>{};
  final _worst = <String, (double, double, double)>{};

  String overlapReport() =>
      'PEOPLE overlap: ${_frames == 0 ? 0 : (_bumps / _frames).toStringAsFixed(2)} pairs a frame over $_frames frames, deepest ${(_deepest * 100).round()} cm '
      '(${[for (final e in _kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) '${e.key} ${(e.value / math.max(_frames, 1)).toStringAsFixed(2)} [worst ${(_worst[e.key]!.$1 * 100).round()} cm at ${_worst[e.key]!.$2.toStringAsFixed(1)},${_worst[e.key]!.$3.toStringAsFixed(1)}]'].join(', ')})';

  void _countOverlaps() {
    _frames++;
    for (var i = 0; i < _all.length; i++) {
      final a = _all[i];
      for (var k = i + 1; k < _all.length; k++) {
        final b = _all[k];
        final dx = a.x - b.x, dz = a.z - b.z;
        if (dx.abs() > 0.6 || dz.abs() > 0.6) continue;
        final d = math.sqrt(dx * dx + dz * dz), minD = 0.25 * (a.scale + b.scale);
        if (d < minD) {
          _bumps++;
          _deepest = math.max(_deepest, minD - d);
          String kind(_Person q) => q.role == _Role.walker ? (q.pause > 0 ? 'watching' : (q.waiting ? 'waiting' : 'walking')) : q.role.name;
          final ka = kind(a), kb = kind(b);
          final key = ka.compareTo(kb) < 0 ? '$ka+$kb' : '$kb+$ka';
          _kinds[key] = (_kinds[key] ?? 0) + 1;
          if (minD - d > (_worst[key]?.$1 ?? 0)) _worst[key] = (minD - d, a.x, a.z);
        }
      }
    }
  }

  void step(double t, double dt, BoothModel m, double wallWidth, StreetWork? work, [List<vm.Vector3> others = const []]) {
    _others = others;
    final gate = work?.gateBusy(t);
    for (final p in _all) {
      switch (p.role) {
        case _Role.walker:
          _walk(p, t, dt, m, gate);
        case _Role.spectator:
          p.x = p.homeX;
          p.z = p.homeZ;
          p.heading = _turn(p.heading, headingTo(-p.x, 2 - p.z), dt);
        case _Role.keeper:
          p.x = p.homeX;
          p.z = p.homeZ;
        case _Role.worker:
          _work(p, t, dt, wallWidth, m.job?.phase, gate);
      }
    }
    if (_avoidOn) _separate();
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') _countOverlaps();
  }

  /// Whoever still bumped into someone this step is eased apart: a walker
  /// steps aside (within the pavement), or back (never on, past a kerb); a
  /// site worker steps aside; spectators and keepers stand their ground.
  /// Between two who move each gives half.
  void _separate() {
    bool moves(_Person q) => q.role == _Role.walker || q.role == _Role.worker;
    for (final p in _all) {
      if (!moves(p)) continue;
      for (final q in _all) {
        if (identical(p, q)) continue;
        var dx = p.x - q.x, dz = p.z - q.z;
        if (dx.abs() > 0.6 || dz.abs() > 0.6) continue;
        final d = math.sqrt(dx * dx + dz * dz), minD = 0.25 * (p.scale + q.scale) + 0.02;
        if (d >= minD) continue;
        if (d < 1e-4) {
          // Right on top of each other: apart sideways.
          dx = -p.fz;
          dz = p.fx;
        } else {
          dx /= d;
          dz /= d;
        }
        final move = (minD - d) * (moves(q) ? 0.5 : 1.0);
        if (p.role == _Role.worker) {
          p
            ..x += dx * move
            ..z += dz * move;
          continue;
        }
        final along = move * (dx * p.fx + dz * p.fz), across = move * (dx * -p.fz + dz * p.fx);
        final dodge = (p.dodge + across).clamp(-0.3 - p.side, 0.8 - p.side);
        final back = math.min(0.0, along);
        p
          ..dodge = dodge
          ..d += back * p.dir
          ..x += dx * move
          ..z += dz * move;
      }
    }
  }

  void _walk(_Person p, double t, double dt, BoothModel m, (double, double)? gate) {
    final r = p.route!;
    if (p.pause > 0 && p.vel < 0.05) {
      // Stopped to watch for a while.
      p.vel = p.v = 0;
      p.pause -= dt;
      p.heading = _turn(p.heading, r.alley ? headingTo(p.x < 0 ? -1 : 1, 0) : headingTo(-p.x * 0.6, 2 - p.z), dt);
      return;
    }
    final onCrossing = r.crossing.containsKey(r.segmentAt(p.d));
    // Round whoever's in the way: a step aside, or (no room) slowing to
    // keep a step behind.
    final cap = _avoidOn ? _avoid(p, dt) : 1.0;
    // Their pace (quicker over a crossing), slowed by whoever's ahead;
    // slowing to a stop to watch, or at the kerb on red (or at the gate
    // while the truck goes through); speeding up and slowing down taking a
    // moment (stopping short for someone in the way, less).
    var want = p.pause > 0 ? 0.0 : p.speed * (onCrossing ? 1.35 : 1) * cap;
    final stop = _stopAhead(p, r, t, gate);
    if (stop < 4) want = math.min(want, math.sqrt(2 * 2.0 * math.max(0.0, stop - 0.03)));
    p.vel = want > p.vel ? math.min(want, p.vel + 1.3 * dt) : math.max(want, p.vel - (cap < 0.7 ? 6.0 : 2.4) * dt);
    var next = p.d + p.dir * p.vel * dt;
    // The crossings: wait at the kerb for the walk signal.
    p.waiting = false;
    for (final MapEntry(key: seg, value: avenue) in r.crossing.entries) {
      final entry = p.dir > 0 ? r.cum[seg] : r.cum[seg + 1];
      final crossesIn = p.dir > 0 ? (p.d < entry && next >= entry) : (p.d > entry && next <= entry);
      if (crossesIn && !(avenue ? TrafficLights.walkAve(t) : TrafficLights.walkSide(t))) {
        next = entry - p.dir * 0.02;
        p.waiting = true;
      }
    }
    // Waiting at the kerb: a step behind (or beside) whoever got there first.
    if (p.waiting) {
      final ahead = p.dir * (next - p.d);
      if (ahead > 0 && _taken(p, p.x + p.fx * ahead, p.z + p.fz * ahead, 0.55)) {
        next = p.d;
      }
    }
    // The site gate: wait either side while the delivery truck goes through.
    if (gate != null && identical(r, _front) && p.d <= r.cum[1]) {
      final a = gate.$1 - r.pts[0].$1, b = gate.$2 - r.pts[0].$1;
      if (p.dir > 0 ? (p.d < a && next >= a) : (p.d > b && next <= b)) {
        next = p.dir > 0 ? a - 0.02 : b + 0.02;
        p.waiting = true;
      }
    }
    if (p.waiting) p.vel = math.min(p.vel, (next - p.d).abs() / math.max(dt, 1e-6));
    // Watch points: now and then, stop and watch the build for a while.
    for (var k = 0; k < r.watch.length; k++) {
      final w = r.watch[k];
      final passes = p.dir > 0 ? (p.d < w && next >= w) : (p.d > w && next <= w);
      if (passes && k != p.lastWatch) {
        p.lastWatch = k;
        final busy = m.job?.phase;
        final keen = busy == Phase.celebrate || busy == Phase.reveal ? 0.75 : 0.32;
        // (Not right where someone's already standing.)
        if (rnd(p.index, p.lap, k) < keen && !_taken(p, p.x, p.z, 0.62)) {
          p.pause = 6 + 22 * rnd(p.index, p.lap, k + 50);
        }
      }
    }
    final moved = (next - p.d).abs();
    p.v = moved / math.max(dt, 1e-6);
    p.d = next;
    if (p.d >= r.length) {
      p.d -= r.length;
      p.lap++;
    } else if (p.d < 0) {
      p.d += r.length;
      p.lap++;
    }
    p.stride += moved / Gait.stepLength(math.max(p.vel, 0.3), p.scale, p.manner) * math.pi;
    final i = r.segmentAt(p.d), n = r.pts.length;
    final a = r.pts[i], b = r.pts[(i + 1) % n];
    final f = (p.d - r.cum[i]) / math.max(r.cum[i + 1] - r.cum[i], 1e-6);
    final dx = b.$1 - a.$1, dz = b.$2 - a.$2;
    final l = math.max(math.sqrt(dx * dx + dz * dz), 1e-6);
    // Keep left (as in Japan), so the two directions pass each other;
    // round a corner (not stepping across it), the way the next leg goes
    // blended in over the last and first of a step either side.
    var nx = -dz / l, nz = dx / l;
    const round = 0.7;
    final into = p.d - r.cum[i], left = r.cum[i + 1] - p.d;
    if (left < round || into < round) {
      final j = left < round ? (i + 1) % n : (i - 1 + n) % n;
      final c = r.pts[j], e = r.pts[(j + 1) % n];
      final ex = e.$1 - c.$1, ez = e.$2 - c.$2, el = math.max(math.sqrt(ex * ex + ez * ez), 1e-6);
      final k = 0.5 * (1 - math.min(left, into) / round);
      nx += (-ez / el - nx) * k;
      nz += (ex / el - nz) * k;
      final nl = math.max(math.sqrt(nx * nx + nz * nz), 1e-6);
      nx /= nl;
      nz /= nl;
    }
    final off = p.side + p.dodge;
    p.x = a.$1 + dx * f + nx * off * p.dir;
    p.z = a.$2 + dz * f + nz * off * p.dir;
    p.fx = dx / l * p.dir;
    p.fz = dz / l * p.dir;
    if (!p.waiting) p.heading = _turn(p.heading, headingTo(dx * p.dir, dz * p.dir), dt);
  }

  /// How far along their way [p] has to stop: at a crossing on red, at the
  /// site gate while the truck goes through (infinity: nowhere near).
  double _stopAhead(_Person p, _Route r, double t, (double, double)? gate) {
    var best = double.infinity;
    for (final MapEntry(key: seg, value: avenue) in r.crossing.entries) {
      if (avenue ? TrafficLights.walkAve(t) : TrafficLights.walkSide(t)) continue;
      final ahead = ((p.dir > 0 ? r.cum[seg] : r.cum[seg + 1]) - p.d) * p.dir;
      if (ahead > 0 && ahead < best) best = ahead;
    }
    if (gate != null && identical(r, _front) && p.d <= r.cum[1]) {
      final ahead = p.dir > 0 ? gate.$1 - r.pts[0].$1 - p.d : p.d - (gate.$2 - r.pts[0].$1);
      if (ahead > 0 && ahead < best) best = ahead;
    }
    return best;
  }

  /// Walking round the people ahead of [p]: anyone within a step or two in
  /// front, close enough across to bump into and not walking away as fast,
  /// is passed with a step aside (whichever side needs less, keeping to the
  /// pavement), or — no room — followed a step behind. Returns the speed
  /// factor (0 stop … 1 free) and moves [p]'s step aside towards where it
  /// should be.
  double _avoid(_Person p, double dt) {
    var cap = 1.0, nearest = double.infinity;
    double? want;
    var lineBlocked = false;
    final lx = -p.fz, lz = p.fx, off = p.side + p.dodge;
    bool fits(double shift) => off + shift <= 0.8 && off + shift >= -0.3;
    void obstacle(double x, double z, double vx, double vz, double r) {
      final rx = x - p.x, rz = z - p.z;
      if (rx.abs() > 2.4 || rz.abs() > 2.4) return;
      final along = rx * p.fx + rz * p.fz;
      if (along <= -0.8 || along > 2.0) return;
      final lat = rx * lx + rz * lz;
      final clear = 0.27 * p.scale + r + 0.06;
      final away = vx * p.fx + vz * p.fz;
      // Still alongside, or ahead, of where we'd be back in line.
      if ((lat + p.dodge).abs() < clear && !(along > 0.45 && away >= p.speed * 0.85)) lineBlocked = true;
      if (lat.abs() >= clear) return;
      if (along.abs() <= 0.45) {
        // Shoulder to shoulder: step apart (away from them).
        final shift = lat > 0 ? lat - clear : lat + clear;
        if (fits(shift) && along.abs() < nearest) {
          nearest = along.abs();
          want = p.dodge + shift;
        }
        return;
      }
      // Ahead, and walking away from us at least as fast: no bother.
      if (along < 0.45 || away >= p.speed * 0.85 || along >= nearest) return;
      nearest = along;
      // Our new place across, past them on either side (left: +).
      final left = lat + clear, right = lat - clear;
      final canLeft = fits(left), canRight = fits(right);
      if (canLeft || canRight) {
        want = p.dodge + (!canRight || (canLeft && left.abs() < right.abs()) ? left : right);
      } else {
        // No room either side: keep a step behind.
        want = p.dodge;
        cap = math.min(cap, c01((along - 0.6) / 0.7));
      }
      // Too close to step round in time: slow down meanwhile.
      if (along < 0.9) cap = math.min(cap, c01((along - 0.45) / 0.45) + 0.25);
    }

    for (final q in _all) {
      if (identical(q, p)) continue;
      obstacle(q.x, q.z, q.fx * q.v, q.fz * q.v, 0.27 * q.scale);
    }
    for (final o in _others) {
      obstacle(o.x, o.z, 0, 0, 0.3);
    }
    // Back into line once past (and only then).
    final target = want ?? (lineBlocked ? p.dodge : 0.0);
    final step = 0.9 * dt;
    p.dodge += (target - p.dodge).clamp(-step, step);
    return cap;
  }

  /// Whether someone (but [p]) stands within [r] of (x, z).
  bool _taken(_Person p, double x, double z, double r) {
    for (final q in _all) {
      if (identical(q, p)) continue;
      final dx = q.x - x, dz = q.z - z;
      if (dx * dx + dz * dz < r * r) return true;
    }
    return false;
  }

  /// Workers pace between two spots, stopping to look up at the work. The
  /// one at the corner guides the delivery truck through the gate.
  void _work(_Person p, double t, double dt, double wallWidth, Phase? phase, (double, double)? gate) {
    final end = p.homeX * (wallWidth / 2 + 1.2);
    final cycle = 16 + 6 * (p.phase % 1);
    final u = ((t + p.phase * 7) % cycle) / cycle;
    // 0–0.35 stand at home, 0.35–0.5 walk out, 0.5–0.85 stand, 0.85–1 back.
    final w = u < 0.35 ? 0.0 : (u < 0.5 ? eio((u - 0.35) / 0.15) : (u < 0.85 ? 1.0 : 1 - eio((u - 0.85) / 0.15)));
    var hx = end, hz = p.homeZ;
    var ax = end + p.homeX * p.awayX, az = p.awayZ;
    if (phase == Phase.demolish || phase == Phase.cleanup) {
      // Stand well clear while the ball swings and the rubble goes: behind
      // the crane on the right; on the left, out of where the rubble flies
      // (along the wall), in the plaza's front corner by the 工事中 board.
      // (Each in a place of their own: the three on a side in a row.)
      final k = p.crewNo ~/ 2;
      hx = p.homeX > 0 ? 14.0 + 0.9 * k : -15.2 - 0.75 * k;
      hz = p.homeX > 0 ? 5.0 + 0.6 * k : -6.4 - 0.65 * k;
      ax = hx - p.homeX * (p.homeX > 0 ? 1.0 : 0.8);
      az = hz + (p.homeX > 0 ? 0.9 : -0.35);
    } else if ((phase == Phase.reveal || phase == Phase.celebrate) && p.job == 0 && p.homeX < 0) {
      // At the wall's left end, behind its front: out of the way of the
      // Glyph Works' tray coming round to the front.
      hz = az = 0.6 + 0.9 * (p.crewNo ~/ 2);
      ax = hx;
    } else if (p.job == 1) {
      // By the safety banner, keeping an eye on the street (left of the
      // gate); while the truck comes or goes, at the gate post, guiding it.
      p.guiding = gate != null;
      hx = gate == null ? 11.4 : gate.$1 - 0.45;
      hz = gate == null ? Plan.plazaZ0 + 1.7 : Plan.plazaZ0 + 0.55;
      ax = gate == null ? 9.6 : hx;
      az = gate == null ? Plan.plazaZ0 + 2.0 : hz;
    } else if (p.job == 2) {
      // Along the back of the site.
      hx = -6;
      hz = 4.6;
      ax = 7;
      az = 4.9;
    }
    var nx = lerp(hx, ax, w), nz = lerp(hz, az, w);
    // Walk (never jump) to wherever the spot moved to.
    final gx = nx - p.x, gz = nz - p.z;
    final gap = math.sqrt(gx * gx + gz * gz);
    final step = 1.5 * dt;
    if (gap > step && p.placed) {
      nx = p.x + gx / gap * step;
      nz = p.z + gz / gap * step;
    }
    p.placed = true;
    final moved = math.sqrt((nx - p.x) * (nx - p.x) + (nz - p.z) * (nz - p.z));
    p.moving = moved > 1e-4;
    if (p.moving) {
      p.stride += moved / Gait.stepLength(1.5, p.scale, p.manner) * math.pi;
      p.heading = _turn(p.heading, headingTo(nx - p.x, nz - p.z), dt);
    } else if (p.job == 1) {
      p.heading = _turn(p.heading, p.guiding ? headingTo(0.8, -0.6) : headingTo(0.2, -1), dt); // faces the street
    } else {
      p.heading = _turn(p.heading, headingTo(-nx, -0.4 - nz), dt); // faces the wall
    }
    p.x = nx;
    p.z = nz;
  }

  static double _turn(double from, double to, double dt) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return from + d * (1 - math.exp(-dt * 6));
  }

  final _fp = FigurePose();
  final _at = vm.Vector3.zero();

  void pose(double t, vm.Vector3 camera, BoothModel m, double night, StreetWork? work) {
    _baton.visible = false;
    final phase = m.job?.phase;
    final cheering = phase == Phase.celebrate;
    final low = camera.y < 3.2;
    final f = _fp;
    for (final p in _all) {
      final cdx = p.x - camera.x, cdz = p.z - camera.z;
      if (low && cdx * cdx + cdz * cdz < 2.6) {
        _figures.hide(p.slot);
        continue;
      }
      final speed = p.role == _Role.walker ? p.vel : (p.moving ? 1.5 : 0.0);
      final amount = smooth(0.0, 0.45, speed);
      final watcher = p.role == _Role.spectator || p.role == _Role.keeper || (p.role == _Role.walker && p.pause > 0);
      // A third of those watching the celebration hold their phones up to
      // take it, the rest clap.
      final snap = cheering && watcher && rnd(p.index, 77) < 0.33;
      final cheer = cheering && watcher && !snap;
      f.rest();
      f.pos.setValues(p.x, 0, p.z);
      f.yaw = p.heading - math.pi / 2;
      if (amount < 1) {
        // Standing about, never quite still: watching the build (or the
        // stall, the lights across the road, the alley), now and then a
        // look away, a look at the watch or the phone.
        var fidget = 0.5;
        final r = p.route;
        if (p.role == _Role.walker && p.waiting) {
          _at.setValues(p.x + p.fx * 8, 1.6, p.z + p.fz * 8);
          fidget = 0.9;
        } else if (p.role == _Role.walker && r != null && r.alley) {
          _at.setValues(p.x < 0 ? -AlleyLayout.rowX : AlleyLayout.rowX, 1.3, p.z);
        } else if (p.role == _Role.keeper) {
          _at.setValues(0, 1.5, p.z);
          fidget = 0.25;
        } else if (p.role == _Role.worker) {
          _at.setValues(0, 2.2, 0);
          fidget = 0.2;
        } else {
          _at.setValues(0, 2.6, 0);
        }
        Idle.stand(f, t, p.manner, size: p.scale, at: _at, fidget: cheer || snap ? 0 : fidget, shift: cheer ? 0 : 1);
      }
      if (amount > 0) {
        Gait.walk(f, p.stride, math.max(speed, 0.3), p.manner, size: p.scale, amount: amount);
        if (p.bag) {
          // The bag's arm hangs, swinging a little.
          f.armPitch[0] *= 0.35;
          f.elbow[0] = lerp(f.elbow[0], 0.12, amount);
        }
      }
      if (cheer) {
        // Clapping, a happy bounce with it.
        final rate = 2.2 + 0.6 * rnd(p.index, 78);
        f.bob = -0.02 * p.scale * (0.5 + 0.5 * math.sin((t * rate + p.phase) * 2 * math.pi));
        Idle.clap(f, t, rate, 1, p.phase);
      } else if (snap) {
        // The phone held up in both hands in front of the face, the build on
        // its screen.
        final d = 0.01 * math.sin(t * 1.7 + p.phase);
        f.handTo(0, -0.04, 0.62 + d, -0.33);
        f.handTo(1, 0.04, 0.62 + d, -0.33);
        f.headPitch -= 0.05;
      }
      if (p.parasol && !cheer) {
        f.armPitch[1] = 0.95;
        f.armRoll[1] = -0.22;
        f.elbow[1] = double.nan;
      }
      if (p.role == _Role.keeper && !cheer) {
        // Now and then, a hand out over the counter: look at this.
        final show = math.sin(math.pi * seg((t + p.phase * 3) % 9, 0, 2.4));
        f.handTo(1, 0.16, 0.26, -0.42, show);
      }
      final guide = p.guiding && !p.moving;
      if (p.role == _Role.worker && !p.moving) {
        if (guide) {
          // Guiding the truck in: the baton swept to and fro, low.
          f.handTo(1, 0.3 + 0.08 * math.sin(t * 4.2), 0.18, -0.3 + 0.1 * math.cos(t * 4.2));
        } else if (p.job == 1) {
          // At the corner, minding the traffic: a hand out, now and then.
          final out = math.sin(math.pi * seg((t + p.phase * 5) % 7, 0, 2.6));
          f.handTo(1, 0.36, 0.16, -0.18, out);
        }
      }
      _figures.draw(p.slot, f);
      if (guide) _batonIn(night);
    }
  }

  /// The flagman's baton, out from the hand of his waving arm (the last
  /// figure drawn).
  void _batonIn(double night) {
    final rig = _figures.rig;
    _baton
      ..visible = true
      ..place(
        (m) => m
          ..setFrom(rig.lower[1])
          ..translateByDouble(0.0, -(FigureRig.lowerArm + 0.2), 0.0, 1.0),
      );
    final k = 2.5 + 6 * night;
    _batonMat.baseColorFactor = vm.Vector4(k, k * 0.12, k * 0.05, 1);
  }
}

// ── Birds ───────────────────────────────────────────────────────────────────

class _Birds {
  _Birds(Scene scene) {
    _wings = InstancedMesh(
      geometry: merged([part(CuboidGeometry(vm.Vector3(0.22, 0.03, 0.62)), vm.Matrix4.translation(vm.Vector3(0, 0, 0.31)), vm.Vector4(1, 1, 1, 1))]),
      material: pbr(lin(BP.ink), roughness: 0.6),
    );
    for (var i = 0; i < _n * 2; i++) {
      _wings.addInstance(hidden);
    }
    scene.add(
      Node(name: 'birds')
        ..castsShadows = false
        ..lightChannelMask = 0x01
        ..addComponent(InstancedMeshComponent(_wings)),
    );
  }

  static const _n = 11;
  late final InstancedMesh _wings;

  void pose(double t, double night) {
    final show = night < 0.45;
    _wings.updateInstanceTransforms((list) {
      for (var i = 0; i < _n; i++) {
        if (!show) {
          list[i * 2].setFrom(hidden);
          list[i * 2 + 1].setFrom(hidden);
          continue;
        }
        // A loose flock wheeling over the park.
        final a = t * 0.11 + i * 0.16 + 0.3 * math.sin(t * 0.05 + i);
        final r = 24 + 5 * math.sin(i * 1.7) + 3 * math.sin(t * 0.2 + i);
        final x = math.sin(a) * r, z = 38 + math.cos(a) * r * 0.7;
        final y = 15 + 2.5 * math.sin(i * 2.3) + 1.2 * math.sin(t * 0.7 + i);
        final dx = math.cos(a), dz = -math.sin(a) * 0.7;
        final hdg = headingTo(dx, dz);
        final flap = math.sin(t * 9 + i * 1.3) * 0.55;
        setTrsYX(list[i * 2], x, y, z, hdg, flap + 0.15, 2.2);
        setTrsYX(list[i * 2 + 1], x, y, z, hdg + math.pi, -flap - 0.15, 2.2);
      }
    });
  }
}

// ── The blimp ───────────────────────────────────────────────────────────────

class _Blimp {
  _Blimp(this.scene);
  final Scene scene;
  final _node = Node(name: 'blimp');
  late final PhysicallyBasedMaterial _banner, _bodyMat;

  Future<void> build() async {
    final body = SphereGeometry(radius: 1, segments: 40, rings: 20).extractMeshData().transformed(vm.Matrix4.diagonal3Values(8, 2.3, 2.3));
    _bodyMat = pbr(lin(const Color(0xFFE9EEF5)), roughness: 0.4, metallic: 0.15, emissive: lin(BP.line), emissiveStrength: 0);
    _node.add(Node(mesh: Mesh(MeshGeometry.fromMeshData(body), _bodyMat)));
    final navy = pbr(lin(const Color(0xFF16345A)), roughness: 0.5);
    // Tail fins, a gondola, and a navy band.
    for (final (rx, w, h) in [(0.0, 0.12, 2.6), (math.pi / 2, 0.12, 2.6)]) {
      _node.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(2.2, h, w)), navy), localTransform: trs(vm.Vector3(-7.0, 0, 0), rotX: rx)));
    }
    _node.add(Node(mesh: Mesh(CuboidGeometry(vm.Vector3(3.0, 0.8, 1.1)), navy), localTransform: trs(vm.Vector3(0.8, -2.45, 0))));
    final band = TorusGeometry(radius: 1, tubeRadius: 0.06, radialSegments: 48, tubularSegments: 8).extractMeshData();
    _node.add(Node(mesh: Mesh(MeshGeometry.fromMeshData(band.transformed(trs(vm.Vector3(4.6, 0, 0), rotZ: math.pi / 2, s: vm.Vector3(1.9, 1.9, 1.9)))), pbr(lin(BP.amber), roughness: 0.4))));

    // The banner: the talk's title, on both flanks.
    final tex = await paintedTexture(1024, 192, (c, s) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width, s.height), const Radius.circular(28));
      c.drawRRect(r, Paint()..shader = const LinearGradient(colors: [Color(0xFF0C2137), Color(0xFF16345A)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));
      final tp = TextPainter(
        text: const TextSpan(
          text: "Inside Flutter's Text Pipeline",
          style: TextStyle(fontFamily: BP.display, fontSize: 84, color: BP.amber, fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final k = math.min(1.0, (s.width - 70) / tp.width);
      c.save();
      c.translate(s.width / 2, s.height / 2);
      c.scale(k);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
      tp.dispose();
    });
    _banner = PhysicallyBasedMaterial()
      ..baseColorTexture = tex
      ..metallicFactor = 0
      ..roughnessFactor = 0.5
      ..emissiveTexture = tex
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.4;
    final panel = boardGeometry(9.0, 1.7);
    // Left flank faces local −Z; the right flank is the same panel turned.
    _node.add(Node(mesh: Mesh(panel, _banner), localTransform: trs(vm.Vector3(0.2, 0.1, -2.12))));
    _node.add(Node(mesh: Mesh(panel, _banner), localTransform: trs(vm.Vector3(0.2, 0.1, 2.12), rotY: math.pi)));
    _node.castsShadows = false;
    for (final c in [_node, ..._node.children]) {
      c.lightChannelMask = 0x01;
    }
    scene.add(_node);
  }

  void pose(double t, double night) {
    // A slow lap over the skyline the camera faces: above the middle ring,
    // in front of the tall towers, low enough to be in the shots.
    final a = t * 2 * math.pi / 260 + 2.2;
    const cx = 0.0, cz = 138.0, rx = 150.0, rz = 28.0;
    final x = cx + math.cos(a) * rx, z = cz + math.sin(a) * rz;
    final dx = -math.sin(a) * rx, dz = math.cos(a) * rz;
    final y = 32 + 1.5 * math.sin(t * 0.13);
    _node.localTransform = trs(vm.Vector3(x, y, z), rotY: headingTo(dx, dz), rotZ: 0.03 * math.sin(t * 0.4));
    _banner.emissiveStrength = 0.35 + 2.6 * night;
    _bodyMat.emissiveStrength = 0.06 * night;
  }
}
