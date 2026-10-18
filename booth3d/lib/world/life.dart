import 'dart:math' as math;
import 'dart:typed_data';
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
import 'models.dart';

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
  late final _figures = Figures.of(scene);
  final _traffic = _Traffic();
  final _inRoad = <(double, double)>[];
  late final _Signals _signals;
  late final _Birds _birds;
  late final _Blimp _blimp;
  double _t = 0;

  Future<void> init() async {
    _people.build(scene);
    await _traffic.build(scene);
    _signals = _Signals(scene);
    _birds = _Birds(scene);
    _blimp = _Blimp(scene);
    await _blimp.build();
  }

  /// How often people walked into each other (capture runs).
  String overlapReport() =>
      '${_people.overlapReport()}\nWALKER jumps: ${_people.jumpLog.length}${[for (final j in _people.jumpLog) '\n  $j'].join()}'
      '\nWALKER in gates: ${_people.gateLog.length}${[for (final j in _people.gateLog) '\n  $j'].join()}';

  /// Steps the life by [dt] (sub-stepped when fast-forwarding) and poses it
  /// for [camera] (anything right at the camera steps out of its way).
  /// Traffic and people make way for [work] (the site's delivery truck);
  /// people walk round each other and [others] (the site's people out on
  /// the pavement: the new manager's party, the driver).
  void update(BoothModel m, double dt, {required vm.Vector3 camera, required double wallWidth, required double night, StreetWork? work, List<(vm.Vector3, double, double)> others = const []}) {
    var left = dt;
    while (left > 1e-6) {
      final h = math.min(left, 0.1);
      _t = m.t - left + h;
      _people.inRoad(_inRoad, others);
      _traffic.step(_t, h, m.job?.phase, work, _inRoad);
      _traffic.near(40, _people.cars);
      _people.step(_t, h, m, wallWidth, work, others);
      left -= h;
    }
    _t = m.t;
    _traffic.pose(camera, night);
    // (Capture runs: nobody under a car.)
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') _figures.vehicles['cars'] = _traffic.footprints();
    _people.pose(_t, camera, m, night, work);
    _signals.pose(_t, night);
    _birds.pose(_t, night, camera);
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

  /// Whether the avenue's crosswalk at x = [x] is in the truck's way at
  /// [t], or soon will be (people wait at the kerb).
  bool crosswalkBusy(double x, double t);

  /// The trucks about at [t], into [out]: round each one's footprint (centre,
  /// half extents), for people to keep out of.
  void trucks(double t, List<(vm.Vector3, vm.Vector3)> out);
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

  /// Where along it a car must never be left standing (crosswalks, the
  /// junctions it crosses): from, to, nearest first. A car that couldn't
  /// get clear of one (the queue ahead) waits before it.
  final keepClear = <(double, double)>[];

  /// Distance along the lane of the point (x, z).
  double along(double x, double z) => (x - x0) * dx + (z - z0) * dz;

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

  Future<void> build(Scene scene) async {
    _lightMat = UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    _taxiSignMat = pbr(lin(BP.amber), roughness: 0.4, emissive: lin(BP.amber), emissiveStrength: 0.2);
    // Each part as what it's made of (vehicles.py puts its class in the UVs,
    // u = (class + 0.5) / 8): paint (a little metallic, under a clear coat),
    // glass (smooth, so it mirrors the sky), plastic trim, rubber, alloy
    // hubs. A row of texels each for roughness and metal, and for the coat.
    Texture2D row(List<(double, double, double)> texels) {
      final px = Uint8List(8 * 4);
      for (var i = 0; i < texels.length; i++) {
        final (r, g, b) = texels[i];
        px
          ..[i * 4] = (r * 255).round()
          ..[i * 4 + 1] = (g * 255).round()
          ..[i * 4 + 2] = (b * 255).round()
          ..[i * 4 + 3] = 255;
      }
      return Texture2D.fromPixels(px, 8, 1, content: TextureContent.data, sampling: const TextureSampling(mipmaps: false));
    }

    // (Occlusion, roughness, metal.)
    final surface = row([(1, 0.3, 0.15), (1, 0.04, 0), (1, 0.55, 0), (1, 0.9, 0), (1, 0.3, 0.85)]);
    final coat = row([(1, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0)]);
    final paint = pbr(rgb(1, 1, 1), roughness: 1, metallic: 1)
      ..metallicRoughnessTexture = surface
      ..clearcoat = 0.8
      ..clearcoatTexture = coat
      ..clearcoatRoughness = 0.06;
    // The vehicles, made in Blender (tool/blender/vehicles.py): the same
    // sizes, their lamps where they were.
    final models = await modelParts('assets/models/vehicles.glb');
    for (final k in _Kind.values) {
      final body = InstancedMesh(geometry: MeshGeometry.fromMeshData(models[k.name]!), material: paint);
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
    // Where they mustn't be left standing: the crosswalks at the plaza's
    // corners and the junctions on the avenue; the far sidewalk's crossing
    // and the avenue's junction on the side streets.
    for (final lane in _lanes) {
      final zones = lane.avenue
          ? [
              for (final x in Plan.crossX) (x, Plan.crossHalf + 0.6),
              for (final s in [-1.0, 1.0]) (s * sx, sh + 0.4),
            ].map((z) => (lane.along(z.$1, lane.z0), z.$2))
          : [((Plan.peopleFar[0] + Plan.peopleFar[1]) / 2, 1.3), ((Plan.aveZ0 + Plan.aveZ1) / 2, (Plan.aveZ1 - Plan.aveZ0) / 2 + 0.4)].map((z) => (lane.along(lane.x0, z.$1), z.$2));
      lane.keepClear.addAll([for (final (c, h) in zones) (c - h, c + h)]..sort((a, b) => a.$1.compareTo(b.$1)));
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
  /// kept clear. Anyone out in the road ([people]: x, z) is stopped for.
  void step(double t, double dt, Phase? phase, StreetWork? work, List<(double, double)> people) {
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
        // Someone in the road ahead (still on a crossing, say): it stops
        // short of them, and never moves off into anyone beside it.
        final front = c.s + c.length / 2, wide = (c.kind == _Kind.bus ? 1.25 : 0.85) + 0.5;
        for (final (x, z) in people) {
          final a = lane.along(x, z), across = (z - lane.z0) * lane.dx - (x - lane.x0) * lane.dz;
          if (across.abs() > wide || a < c.s - c.length / 2 - 0.4 || a > front + 30) continue;
          limit = math.min(limit, a > front ? a - 1.8 - c.length / 2 : c.s);
        }
        // Not left standing on a crosswalk or in a junction: if where it'd
        // have to stop leaves it on one it hasn't reached, it waits before
        // it (the farthest first, so a wait before one isn't in the next).
        for (var k = lane.keepClear.length - 1; k >= 0; k--) {
          final (a, b) = lane.keepClear[k];
          if (front > a - 0.3) continue;
          if (limit + c.length / 2 > a && limit - c.length / 2 < b) limit = math.min(limit, a - 0.4 - c.length / 2);
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

  /// The cars within [reach] of the plaza (x), into [out]: round each one's
  /// footprint (centre, half extents), for people to keep out of.
  void near(double reach, List<(vm.Vector3, vm.Vector3)> out) {
    out.clear();
    for (final c in _cars) {
      final x = c.lane.x0 + c.lane.dx * c.s, z = c.lane.z0 + c.lane.dz * c.s;
      if (x.abs() > reach || z.abs() > reach) continue;
      final l = c.length / 2 + 0.05, w = (c.kind == _Kind.bus ? 1.25 : 0.85) + 0.05;
      out.add((vm.Vector3(x, 0.8, z), vm.Vector3(c.lane.dx.abs() * l + c.lane.dz.abs() * w, 0.8, c.lane.dz.abs() * l + c.lane.dx.abs() * w)));
    }
  }

  /// Each car shown, where it is: its middle, half its length and width,
  /// its heading (see [Figures.vehicles]).
  List<(double, double, double, double, double)> footprints() => [
    for (final c in _cars)
      if (c.shown) (c.lane.x0 + c.lane.dx * c.s, c.lane.z0 + c.lane.dz * c.s, c.length / 2, c.kind == _Kind.bus ? 1.25 : 0.85, c.lane.heading),
  ];

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

  // ── The vehicles' lamps (their bodies: tool/blender/vehicles.py) ──────────

  static MeshData _box(double x, double y, double z, double w, double h, double d, vm.Vector4 c) =>
      part(CuboidGeometry(vm.Vector3(w, h, d)), vm.Matrix4.translation(vm.Vector3(x, y, z)), c);

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
      if (a.$2 == Plan.peopleFront && b.$2 == Plan.peopleFront) front = i;
    }
  }

  /// The segment along the front sidewalk, past the site's gates (−1: none).
  int front = -1;

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

  /// Where they were last drawn, and when; how fast they've lately been
  /// moved other than by walking (pushed aside, creeping up at the kerb):
  /// their feet step for it.
  double lastX = double.nan, lastZ = 0, posedAt = 0, shuffle = 0;

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
  bool onWay = false; // a walker placed on their way (after that, they walk back onto it)
  double lag = 0; // how far behind (or off) their way they are (m)
  double wx = 0, wz = 0; // where their way had them, last step
  bool pressing = false; // out in the road, or in a truck's way: on out of it
  int gate = 0; // a truck coming through the gate: 1 waiting for it, 2 getting out of its way
  bool atKerb = false; // waiting at a crossing for the lights
  double offLogged = -9, gateLogged = -9; // (capture runs: when they were last logged off their way, in a gate)
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
      // (Its watch points between the front's bollards, away from the
      // gates and the spectators.)
      _Route([(-fx, fz), (fx, fz), (fx, Plan.parkZ0 + 15.5), (-fx, Plan.parkZ0 + 15.5)], watch: [8.6, 19.4, 41, 50, 117, 125]),
      // Over the avenue at the plaza's corners and back along the far side
      // (a plain loop: no doubling back, where keeping left would swap
      // sides). (Over the east crosswalk on its outer half: the queue at its
      // kerb kept clear of the site gate's driveway beside it. Its watch
      // points between the front's bollards, away from the gates and the
      // spectators.)
      _Route([
        (Plan.crossX[1] + 0.8, far1),
        (Plan.crossX[1] + 0.8, fz),
        (Plan.crossX[0], fz),
        (Plan.crossX[0], far1),
      ], crossing: {0: true, 2: true}, watch: [24.4, 32.8]),
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
    const counts = [24, 14, 5, 5, 8, 8, 8];
    var seed = 0;
    for (var r = 0; r < routes.length; r++) {
      final route = routes[r];
      // (Nobody starts out in the road: whoever would be on a crossing has
      // just got over it, a step apart.)
      final over = <(int, double), int>{};
      for (var i = 0; i < counts[r]; i++) {
        seed++;
        final kid = rnd(seed, 9) < 0.1;
        final dir = rnd(seed, 2) < 0.5 ? 1.0 : -1.0;
        var d = route.length * (i + 0.5 * rnd(seed, 1)) / counts[r];
        final seg = route.segmentAt(d);
        if (route.crossing.containsKey(seg)) {
          final k = over[(seg, dir)] = (over[(seg, dir)] ?? -1) + 1;
          d = ((dir > 0 ? route.cum[seg + 1] : route.cum[seg]) + dir * (0.5 + 0.9 * k)) % route.length;
        }
        final p = _Person(
          _Role.walker,
          route,
          d,
          dir,
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
        // (Not in front of the site gate, nor the bay gate on the left; nor
        // by the top of the crosswalks, where people queue for the lights;
        // nor where a bollard stands out from the kerb: room for people to
        // pass both ways between them.)
        p.homeX = (s > 0 ? const [6.0, 6.6, 9.4, 10.1] : const [-9.75, -10.35, -10.95, -13.0])[k] + jitter;
        p.homeZ = Plan.plazaZ0 - 0.62 + 0.12 * rnd(seed, 2);
      } else {
        // (Not in front of the vending machines on the right, nor beside a
        // bench, its bin or a lamp the far side of the pavement.)
        p.homeX = s * (Plan.plazaX - 0.02 + 0.08 * rnd(seed, 3));
        p.homeZ = (s > 0 ? -4.0 + 1.2 * k : -7.2 + 2.4 * k) + jitter;
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
      // A happi in the stall's colour over a white shirt (the city's
      // figures' own).
      final c = lin(alleyRules[p.stall].color);
      return l
        ..rigged = false
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

  /// Others about (the site's people): where they are, and how fast they
  /// go (x, z, m/s).
  List<(vm.Vector3, double, double)> _others = const [];

  /// The site's trucks, for the gates and the crossings they use, and where
  /// they are (nobody walks into one).
  StreetWork? _street;
  final _trucks = <(vm.Vector3, vm.Vector3)>[];

  /// The cars near the plaza this step (set by [Life3D]): nobody walks into
  /// one, nor onto a crossing one's standing on.
  final cars = <(vm.Vector3, vm.Vector3)>[];

  /// Walking round people (BOOTH3D_AVOID=0: not, to compare).
  static const _avoidOn = String.fromEnvironment('BOOTH3D_AVOID', defaultValue: '1') != '0';

  /// Capture runs count people walking into each other: frames looked at,
  /// pairs overlapping (summed over the frames), the deepest overlap.
  int _frames = 0, _bumps = 0;
  double _deepest = 0;

  final _kinds = <String, int>{};
  final _where = <String, int>{};
  final _when = <int, int>{};
  double _t = 0, _deepLogged = -9;
  final deepLog = <String>[];
  final _worst = <String, (double, double, double)>{};

  String overlapReport() =>
      'PEOPLE overlap: ${_frames == 0 ? 0 : (_bumps / _frames).toStringAsFixed(2)} pairs a frame over $_frames frames, deepest ${(_deepest * 100).round()} cm '
      '(${[for (final e in _kinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) '${e.key} ${(e.value / math.max(_frames, 1)).toStringAsFixed(2)} [worst ${(_worst[e.key]!.$1 * 100).round()} cm at ${_worst[e.key]!.$2.toStringAsFixed(1)},${_worst[e.key]!.$3.toStringAsFixed(1)}]'].join(', ')})'
      '\nPEOPLE overlap where: ${[for (final e in (_where.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(12)) '${e.key} ${(e.value / math.max(_frames, 1)).toStringAsFixed(2)}'].join(', ')}'
      '\nPEOPLE overlap when: ${[for (final e in _when.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) 't${e.key} ${e.value}'].join(', ')}'
      '${[for (final l in deepLog) '\n  $l'].join()}';

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
          final cell = '${a.x.round()},${a.z.round()} ${a.waiting || b.waiting ? 'waiting' : (a.vel < 0.1 && b.vel < 0.1 ? 'stopped' : 'moving')}';
          _where[cell] = (_where[cell] ?? 0) + 1;
          _when[(_t / 20).floor() * 20] = (_when[(_t / 20).floor() * 20] ?? 0) + 1;
          if (minD - d > 0.15 && _t - _deepLogged > 2 && deepLog.length < 30) {
            _deepLogged = _t;
            String who(_Person q) =>
                '#${q.index} ${q.role.name} at ${q.x.toStringAsFixed(2)},${q.z.toStringAsFixed(2)} d ${q.d.toStringAsFixed(1)} dir ${q.dir} vel ${q.vel.toStringAsFixed(2)} waiting ${q.waiting} kerb ${q.atKerb} gate ${q.gate} pressing ${q.pressing} lag ${q.lag.toStringAsFixed(2)} dodge ${q.dodge.toStringAsFixed(2)} pause ${q.pause.toStringAsFixed(1)}';
            deepLog.add('t=${_t.toStringAsFixed(1)} ${((minD - d) * 100).round()} cm: ${who(a)} + ${who(b)}');
          }
        }
      }
    }
  }

  void step(double t, double dt, BoothModel m, double wallWidth, StreetWork? work, [List<(vm.Vector3, double, double)> others = const []]) {
    _others = others;
    _street = work;
    _t = t;
    _trucks
      ..clear()
      ..addAll(cars);
    work?.trucks(t, _trucks);
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
        // (Eased apart over a frame or two, never in one jump.)
        final move = math.min((minD - d) * (moves(q) ? 0.5 : 1.0), 0.1);
        if (p.role == _Role.worker) {
          p
            ..x += dx * move
            ..z += dz * move;
          continue;
        }
        final along = move * (dx * p.fx + dz * p.fz), across = move * (dx * -p.fz + dz * p.fx);
        final dodge = (p.dodge + across).clamp(-0.3 - p.side, 0.8 - p.side);
        if (p.pressing) {
          // (Out in the road, or in a truck's way: aside, or on (their way
          // with them), never back.)
          final on = math.max(0.0, along);
          p
            ..dodge = dodge
            ..d += on * p.dir
            ..x += -p.fz * across + p.fx * on
            ..z += p.fx * across + p.fz * on;
          continue;
        }
        // (Their way waits for them while they're held back: see [_walk].)
        p
          ..dodge = dodge
          ..x += dx * move
          ..z += dz * move;
      }
    }
  }

  void _walk(_Person p, double t, double dt, BoothModel m, (double, double)? gate) {
    final r = p.route!;
    final span = gate == null ? null : _gateSpan(r, gate);
    if (_debugJumps && span != null && p.d > span.$1 && p.d < span.$2 && t - p.gateLogged > 1 && gateLog.length < 60) {
      p.gateLogged = t;
      gateLog.add('walker #${p.index} t=${t.toStringAsFixed(2)} in the gate at ${p.x.toStringAsFixed(1)},${p.z.toStringAsFixed(1)}: d ${p.d.toStringAsFixed(1)} span ${span.$1.toStringAsFixed(1)}..${span.$2.toStringAsFixed(1)} dir ${p.dir} waiting ${p.waiting} pause ${p.pause.toStringAsFixed(1)} lag ${p.lag.toStringAsFixed(2)} vel ${p.vel.toStringAsFixed(2)}');
    }
    // (Not stopping to watch where a truck's about to come through.)
    if (p.pause > 0 && span != null && p.d > span.$1 - 0.3 && p.d < span.$2 + 0.3) p.pause = 0;
    if (p.pause > 0 && p.vel < 0.05) {
      // Stopped to watch for a while.
      p.vel = p.v = 0;
      p.pause -= dt;
      p.heading = _turn(p.heading, r.alley ? headingTo(p.x < 0 ? -1 : 1, 0) : headingTo(-p.x * 0.6, 2 - p.z), dt);
      // (Not leaning into a bollard after making way for someone.)
      _figures.outOfSolids(p.x, 0, p.z, 0.24 * p.scale, _out, extra: _trucks);
      p
        ..x = _out[0]
        ..z = _out[1];
      return;
    }
    final onCrossing = r.crossing.containsKey(r.segmentAt(p.d));
    // Round whoever's in the way: a step aside, or (no room) slowing to
    // keep a step behind; but out in the road, or where a truck's about to
    // come through, on out of its way regardless (whoever's in the way
    // makes room).
    // (A truck about to come through: they wait short of its way; caught
    // just inside where it'll be kept clear, they stay put; further in, on
    // out the far side. Once waiting, they wait till it's gone, however its way
    // grows as more of it comes in sight.)
    var pastWait = double.negativeInfinity;
    if (span == null) {
      p.gate = 0;
    } else {
      final wait = (p.dir > 0 ? span.$1 : span.$2) - p.dir * _gateRoom;
      if (!r.crossing.containsKey(r.segmentAt(wait))) pastWait = (p.d - wait) * p.dir;
      final inSpan = p.d > span.$1 && p.d < span.$2;
      final inFrom = (p.d - (p.dir > 0 ? span.$1 : span.$2)) * p.dir;
      if (p.gate == 0 && (inSpan || (pastWait >= -1e-6 && pastWait < _gateRoom))) p.gate = inSpan && inFrom >= 0.4 ? 2 : 1;
      if (p.gate == 2 && !inSpan) p.gate = 0;
    }
    final hold = p.gate == 1, inWay = p.gate == 2;
    p.pressing = onCrossing || inWay;
    var cap = _avoidOn ? _avoid(p, dt) : 1.0;
    // (Over a crossing, slowing behind someone but never stopping in the
    // road; in a truck's way, on out of it whoever's there.)
    if (onCrossing) cap = math.max(cap, 0.15);
    if (inWay) cap = 1.0;
    // Their pace (quicker over a crossing), slowed by whoever's ahead;
    // slowing to a stop to watch, or at the kerb on red (or at the gate
    // while the truck goes through); speeding up and slowing down taking a
    // moment (stopping short for someone in the way, less). Held up (round
    // something, by someone), their way waits for them: never running on
    // ahead, to be caught up with in a beeline (over a road).
    var want = p.pause > 0 ? 0.0 : p.speed * (onCrossing ? 1.35 : 1) * cap * c01(1.6 - p.lag);
    final stop = _stopAhead(p, r, t, span);
    if (stop < 4) want = math.min(want, math.sqrt(2 * 2.0 * math.max(0.0, stop - 0.03)));
    p.vel = want > p.vel ? math.min(want, p.vel + 1.3 * dt) : math.max(want, p.vel - (cap < 0.7 ? 6.0 : 2.4) * dt);
    var next = p.d + p.dir * p.vel * dt;
    // The crossings: wait at the kerb for the walk signal (and while a
    // truck goes through the gate the far side, at its corner).
    p
      ..waiting = false
      ..atKerb = false;
    for (final MapEntry(key: seg, value: avenue) in r.crossing.entries) {
      // (How far ahead its kerb is, round the end of the loop too.)
      final ahead = ((p.dir > 0 ? r.cum[seg] : r.cum[seg + 1]) - p.d) * p.dir % r.length;
      if (ahead > 0 && ahead <= (next - p.d).abs() && !_mayCross(r, seg, p.dir, avenue, t, span)) {
        next = p.d + p.dir * (ahead - 0.02);
        p
          ..waiting = true
          ..atKerb = true;
      }
    }
    // Waiting at the kerb: a step behind (or beside) whoever got there first.
    if (p.waiting) {
      final ahead = p.dir * (next - p.d);
      if (ahead > 0 && _taken(p, p.x + p.fx * ahead, p.z + p.fz * ahead, 0.55)) {
        next = p.d;
      }
    }
    // The site gates: wait either side while a truck goes through, a step
    // back from its way (room for whoever's coming out of it); where that's
    // over a crossing's kerb, before the crossing (above).
    if (hold) {
      next = p.d;
      p.waiting = true;
    } else if (pastWait < 0 && pastWait + (next - p.d) * p.dir > 0) {
      next = p.d - pastWait * p.dir;
      p.waiting = true;
      p.gate = 1;
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
        if (rnd(p.index, p.lap, k) < keen && !_taken(p, p.x, p.z, 0.62) && (span == null || w < span.$1 - 0.3 || w > span.$2 + 0.3)) {
          p.pause = 6 + 22 * rnd(p.index, p.lap, k + 50);
        }
      }
    }
    final moved = (next - p.d).abs();
    if (_debugJumps && moved > 0.5 && jumpLog.length < 60) {
      jumpLog.add('walker #${p.index} t=${t.toStringAsFixed(2)}: d ${p.d.toStringAsFixed(2)} → ${next.toStringAsFixed(2)} vel ${p.vel.toStringAsFixed(2)} dir ${p.dir} waiting ${p.waiting} pause ${p.pause.toStringAsFixed(2)} lap ${p.lap}');
    }
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
    final wasX = p.x, wasZ = p.z;
    // Where their way has them; back onto it, if something moved them off
    // it (someone they made way for, stopping to watch), at no more than a
    // brisk step: never a jump.
    final wx = a.$1 + dx * f + nx * off * p.dir, wz = a.$2 + dz * f + nz * off * p.dir;
    p
      ..wx = wx
      ..wz = wz;
    // (Not pushing into whoever's ahead to get there.)
    final ex = wx - p.x, ez = wz - p.z, e = math.sqrt(ex * ex + ez * ez), most = (p.vel + 1.2 * math.max(cap, 0.25)) * dt;
    if (_debugJumps && e > 1.5 && t > 0.5 && (t - p.offLogged) > 2 && jumpLog.length < 60) {
      p.offLogged = t;
      jumpLog.add('walker #${p.index} t=${t.toStringAsFixed(2)}: ${e.toStringAsFixed(1)} m off its way at ${p.x.toStringAsFixed(1)},${p.z.toStringAsFixed(1)} (way ${wx.toStringAsFixed(1)},${wz.toStringAsFixed(1)} seg $i d ${p.d.toStringAsFixed(1)} dir ${p.dir} vel ${p.vel.toStringAsFixed(2)} waiting ${p.waiting} pause ${p.pause.toStringAsFixed(1)} placed ${p.placed})');
    }
    if (p.onWay && e > most) {
      p
        ..x += ex / e * most
        ..z += ez / e * most;
    } else {
      p
        ..x = wx
        ..z = wz;
    }
    p.onWay = true;
    // (Round anything solid by the way, a sign post, a pallet: out by its
    // nearer side, so they slide past it.)
    _figures.outOfSolids(p.x, 0, p.z, 0.24 * p.scale, _out, extra: _trucks);
    if (_debugJumps && t > 0.5 && ((_out[0] - p.x).abs() > 0.3 || (_out[1] - p.z).abs() > 0.3) && jumpLog.length < 60) {
      jumpLog.add('walker #${p.index} t=${t.toStringAsFixed(2)} pushed out of a solid: ${p.x.toStringAsFixed(2)},${p.z.toStringAsFixed(2)} → ${_out[0].toStringAsFixed(2)},${_out[1].toStringAsFixed(2)}: ${_figures.solidsAt(p.x, p.z)}');
    }
    p
      ..x = _out[0]
      ..z = _out[1]
      ..lag = math.sqrt((wx - _out[0]) * (wx - _out[0]) + (wz - _out[1]) * (wz - _out[1]));
    if (_debugJumps) {
      final jx = p.x - wasX, jz = p.z - wasZ;
      if (t > 0.5 && jx * jx + jz * jz > 0.25 && jumpLog.length < 60) {
        jumpLog.add('walker #${p.index} t=${t.toStringAsFixed(2)}: ${math.sqrt(jx * jx + jz * jz).toStringAsFixed(2)} m (${wasX.toStringAsFixed(2)},${wasZ.toStringAsFixed(2)} → ${p.x.toStringAsFixed(2)},${p.z.toStringAsFixed(2)}) seg $i/$n len ${(r.cum[i + 1] - r.cum[i]).toStringAsFixed(2)} into ${(p.d - r.cum[i]).toStringAsFixed(2)} off ${off.toStringAsFixed(2)} dir ${p.dir} waiting ${p.waiting}');
      }
    }
    p.fx = dx / l * p.dir;
    p.fz = dz / l * p.dir;
    if (!p.waiting) p.heading = _turn(p.heading, headingTo(dx * p.dir, dz * p.dir), dt);
  }

  /// How far along their way [p] has to stop: at a crossing on red, at the
  /// site gate while a truck goes through ([span]: see [_gateSpan])
  /// (infinity: nowhere near).
  double _stopAhead(_Person p, _Route r, double t, (double, double)? span) {
    var best = double.infinity;
    for (final MapEntry(key: seg, value: avenue) in r.crossing.entries) {
      if (_mayCross(r, seg, p.dir, avenue, t, span)) continue;
      final ahead = ((p.dir > 0 ? r.cum[seg] : r.cum[seg + 1]) - p.d) * p.dir % r.length;
      if (ahead > 0 && ahead < best) best = ahead;
    }
    if (span != null) {
      final edge = (p.dir > 0 ? span.$1 : span.$2) - p.dir * _gateRoom;
      final ahead = (edge - p.d) * p.dir;
      if (ahead > 0 && ahead < best && !r.crossing.containsKey(r.segmentAt(edge))) best = ahead;
    }
    return best;
  }

  /// How far short of a busy gate's stretch people wait.
  static const _gateRoom = 0.6;

  /// Whether someone going [dir] along [r] may step onto the crossing [seg]
  /// at [t]: on the walk signal, and not while a car stands on it, nor while
  /// the truck's about to cross it, or going through the gate where it
  /// comes out ([span]).
  bool _mayCross(_Route r, int seg, double dir, bool avenue, double t, (double, double)? span) {
    if (!(avenue ? TrafficLights.walkAve(t) : TrafficLights.walkSide(t))) return false;
    // (Nor while a car stands on it, caught there by the queue ahead.)
    final a = r.pts[seg], b = r.pts[(seg + 1) % r.pts.length];
    final x0 = math.min(a.$1, b.$1) - 1.9, x1 = math.max(a.$1, b.$1) + 1.9, z0 = math.min(a.$2, b.$2), z1 = math.max(a.$2, b.$2);
    for (final (c, h) in cars) {
      if (c.x + h.x > x0 && c.x - h.x < x1 && c.z + h.z > z0 && c.z - h.z < z1) return false;
    }
    if (avenue && (_street?.crosswalkBusy(Plan.crossX[r.pts[seg].$1 > 0 ? 1 : 0], t) ?? false)) return false;
    final exit = dir > 0 ? r.cum[seg + 1] : r.cum[seg];
    return span == null || exit <= span.$1 || exit >= span.$2;
  }

  /// Where along [r] the stretch of the front sidewalk [gate] (x from..to)
  /// is, kept clear while a truck goes through a site gate there: from..to
  /// along the route (past the ends of the front, round the corner), or
  /// null if [r] doesn't go along the front.
  static (double, double)? _gateSpan(_Route r, (double, double) gate) {
    final i = r.front;
    if (i < 0) return null;
    final a = r.pts[i], b = r.pts[(i + 1) % r.pts.length];
    final s = b.$1 > a.$1 ? 1.0 : -1.0;
    final u = r.cum[i] + (gate.$1 - a.$1) * s, v = r.cum[i] + (gate.$2 - a.$1) * s;
    return (math.min(u, v), math.max(u, v));
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
    // (Measured across from where their way has them, not where something
    // may be holding them back: else the step aside would grow and grow.)
    final across = p.onWay ? (p.wx - p.x) * lx + (p.wz - p.z) * lz : 0.0;
    final px = p.x + lx * across, pz = p.z + lz * across;
    // Things standing in the way (a bollard, a lamp post, a bin, a bench's
    // end): round them too, a step aside in good time (round all of them,
    // where a few stand together), and kept aside while the next one along
    // is near (no weaving down a row of bollards). No waiting behind them:
    // they never move off. Each is in the way across from here
    // lat ± clear, for the next few steps.
    const look = 4.5;
    final ax = px + p.fx * look, az = pz + p.fz * look;
    _figures.solidsIn(math.min(px, ax) - 1.6, math.min(pz, az) - 1.6, math.max(px, ax) + 1.6, math.max(pz, az) + 1.6, _near);
    _blocked.clear();
    var close = double.infinity;
    final line0 = math.min(0.0, -p.dodge), line1 = math.max(0.0, -p.dodge);
    for (final (c, h) in _near) {
      if (c.y + h.y < 0.05 || c.y - h.y > 1.6) continue; // (flat on the ground, or overhead)
      final rx = c.x - px, rz = c.z - pz;
      final along = rx * p.fx + rz * p.fz, lat = rx * lx + rz * lz;
      // (How far it reaches along the way, and across it.)
      final deep = (p.fx * h.x).abs() + (p.fz * h.z).abs(), wide = (lx * h.x).abs() + (lz * h.z).abs();
      final clear = 0.25 * p.scale + wide + 0.06;
      if (along + deep < -0.35 || along - deep > look) continue;
      // (Between here and their line: not back into line past it yet.)
      if (lat - clear < line1 && lat + clear > line0) lineBlocked = true;
      final gap = math.max(0.0, along - deep);
      if (gap > 2.4) continue;
      _blocked.add((lat - clear, lat + clear));
      if (lat.abs() < clear) close = math.min(close, gap);
    }
    bool free(double s) {
      for (final (lo, hi) in _blocked) {
        if (s > lo + 1e-6 && s < hi - 1e-6) return false;
      }
      return true;
    }

    // (On the pavement, never stepping off the kerb for it; over a
    // crossing, or getting onto one, anywhere on it. Never into anything.)
    final r = p.route!;
    final crossing = r.crossing.containsKey(r.segmentAt(p.d));
    final kerbFree = crossing || _offKerb(px, pz);
    bool onPavement(double shift) => (kerbFree || !_offKerb(px + lx * shift, pz + lz * shift)) && free(shift);
    bool fits(double shift) => off + shift <= 0.8 && off + shift >= -0.3 && onPavement(shift);

    // The nearest place across to [s] clear of everything standing there: in
    // their half of the pavement if there's one, else anywhere on it.
    double clearOf(double s) {
      double? best, fallback;
      void consider(double c) {
        if (fits(c) && (best == null || (c - s).abs() < (best! - s).abs())) best = c;
        if (onPavement(c) && (fallback == null || (c - s).abs() < (fallback! - s).abs())) fallback = c;
      }

      consider(s);
      for (final (lo, hi) in _blocked) {
        consider(lo);
        consider(hi);
      }
      return best ?? fallback ?? s;
    }

    void obstacle(double x, double z, double vx, double vz, double r, int who) {
      final rx = x - px, rz = z - pz;
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
        // No room in their half: over a crossing, aside anyway (it's wide);
        // meeting someone head on in a narrow place, one of the two waits,
        // the other squeezes by; else keep a step behind.
        final okLeft = onPavement(left), okRight = onPavement(right);
        if ((okLeft || okRight) && (crossing || (away < -0.2 && who >= 0 && p.index > who))) {
          want = p.dodge + (!okRight || (okLeft && left.abs() < right.abs()) ? left : right);
        } else {
          want = p.dodge;
          cap = math.min(cap, c01((along - 0.6) / 0.7));
        }
      }
      // Too close to step round in time: slow down meanwhile.
      if (along < 0.9) cap = math.min(cap, c01((along - 0.45) / 0.45) + 0.25);
    }

    for (final q in _all) {
      if (identical(q, p)) continue;
      obstacle(q.x, q.z, q.fx * q.v, q.fz * q.v, 0.27 * q.scale, q.index);
    }
    for (final (o, vx, vz) in _others) {
      obstacle(o.x, o.z, vx, vz, 0.3, -1);
      // Coming across (the site's people walk briskly, and not along the
      // pavement): where they'll be when nearest, within a second.
      final rx = o.x - p.x, rz = o.z - p.z, wx = vx - p.fx * p.v, wz = vz - p.fz * p.v, w2 = wx * wx + wz * wz;
      if (w2 > 0.25) {
        final tc = (-(rx * wx + rz * wz) / w2).clamp(0.0, 1.0);
        if (tc > 0.05) obstacle(p.x + rx + wx * tc, p.z + rz + wz * tc, vx, vz, 0.3, -1);
      }
    }
    final w = want;
    if (w != null) {
      // (Stepping round someone, not into something.)
      if (!free(w - p.dodge)) want = p.dodge + clearOf(w - p.dodge);
    } else if (close.isFinite) {
      want = p.dodge + clearOf(0);
    }
    // Too close to step round something in time: slow down meanwhile.
    if (close < 0.6) cap = math.min(cap, 0.3 + close);
    // Back into line once past (and only then). Waiting at the kerb for the
    // lights: as far to their side as there's room (the way off the
    // crossing clear for those coming over).
    var aside = 0.0;
    if (p.atKerb) {
      // (Only into room nobody's standing in.)
      for (var s = 0.8 - off; s > 0.05; s -= 0.05) {
        if (fits(s) && !_taken(p, px + lx * s, pz + lz * s, 0.56 * p.scale)) {
          aside = p.dodge + s;
          break;
        }
      }
    }
    final target = want ?? (p.atKerb && aside != 0 ? aside : (lineBlocked ? p.dodge : 0.0));
    final step = 0.9 * dt;
    p.dodge = (p.dodge + (target - p.dodge).clamp(-step, step)).clamp(-0.9 - p.side, 1.4 - p.side);
    return cap;
  }

  final _near = <(vm.Vector3, vm.Vector3)>[];
  final _blocked = <(double, double)>[];

  /// Whether (x, z) is in the road, or so near its kerb that someone there
  /// would stand over it.
  static bool _offKerb(double x, double z) =>
      (z > Plan.aveZ0 - 0.28 && z < Plan.aveZ1 + 0.28) || (x.abs() - Plan.streetX).abs() < Plan.streetHalf + 0.28;

  /// Who's out in the road (a late crosser, someone off the pavement), for
  /// the traffic to stop for: where they are.
  void inRoad(List<(double, double)> out, List<(vm.Vector3, double, double)> others) {
    out.clear();
    bool road(double x, double z) => (z > Plan.aveZ0 - 0.3 && z < Plan.aveZ1 + 0.3) || (x.abs() - Plan.streetX).abs() < Plan.streetHalf + 0.3;
    for (final p in _all) {
      if (road(p.x, p.z)) out.add((p.x, p.z));
    }
    for (final (o, _, _) in others) {
      if (road(o.x, o.z)) out.add((o.x, o.z));
    }
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
    final half = wallWidth / 2;
    final cycle = 16 + 6 * (p.phase % 1);
    final u = ((t + p.phase * 7) % cycle) / cycle;
    // 0–0.35 stand at home, 0.35–0.5 walk out, 0.5–0.85 stand, 0.85–1 back.
    final w = u < 0.35 ? 0.0 : (u < 0.5 ? eio((u - 0.35) / 0.15) : (u < 0.85 ? 1.0 : 1 - eio((u - 0.85) / 0.15)));
    // By the wall's ends: in front of it (on the right, in front of the
    // builders' places and the brick yard), and by the platform's end (clear
    // of its rail and mast; on the right, where the yard leaves no room,
    // behind the platform), strolling out a little now and then.
    final front = p.crewNo < 2, right = p.homeX > 0;
    var hx = front ? p.homeX * (half + 1.2) : (right ? half - 0.6 : -(half + 1.75));
    var hz = front ? (right ? p.homeZ - 2.6 : p.homeZ) : (right ? 3.2 : p.homeZ.clamp(0.4, 1.6));
    var ax = right && !front ? hx - 0.8 - 0.5 * p.awayX : hx + p.homeX * (right ? math.min(p.awayX, 2.5) : p.awayX);
    var az = front ? (right ? hz - 0.5 : p.awayZ) : (right ? 3.35 : hz - 0.8 * (p.awayX / 4));
    if (phase == Phase.demolish || phase == Phase.cleanup) {
      // Stand well clear while the ball swings and the rubble goes: behind
      // the crane on the right (beside its footing); on the left, out of
      // where the rubble flies (along the wall), in the plaza's front corner
      // by the 工事中 board. (Each in a place of their own: the three on a
      // side in a row.)
      final k = p.crewNo ~/ 2;
      hx = right ? 15.1 + 0.85 * k : -15.2 - 0.75 * k;
      hz = right ? 4.4 + 0.7 * k : -6.4 - 0.65 * k;
      ax = right ? hx : hx + 0.8;
      az = hz + (right ? 0.9 : -0.35);
    } else if ((phase == Phase.reveal || phase == Phase.celebrate) && p.job == 0 && !right) {
      // At the wall's left end, behind its front (clear of the platform's
      // end): out of the way of the Glyph Works' tray coming round to the
      // front.
      hx = ax = -(half + 1.75);
      hz = az = 0.6 + 0.9 * (p.crewNo ~/ 2);
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
    // (Never in the delivery truck's way: where it turns in at the gate and
    // parks by the yard, a long name's wall end or not: both their spots
    // this side of it, so they don't pace across it either.)
    if ((hz < -2.2 || az < -2.2) && math.max(hx, ax) > 11.0 && math.min(hx, ax) < 15.6) {
      hx = math.min(hx, 10.9);
      ax = math.min(ax, 10.9);
    }
    var nx = lerp(hx, ax, w), nz = lerp(hz, az, w);
    // Walk (never jump) to wherever the spot moved to: round anything solid
    // in the way (along it; head-on, to its side).
    final gx = nx - p.x, gz = nz - p.z;
    final gap = math.sqrt(gx * gx + gz * gz);
    final step = 1.5 * dt;
    if (gap > step && p.placed) {
      nx = p.x + gx / gap * step;
      nz = p.z + gz / gap * step;
      _figures.outOfSolids(nx, 0, nz, 0.25 * p.scale, _out, fromX: p.x, fromZ: p.z, extra: _trucks);
      if ((_out[0] - p.x) * gx + (_out[1] - p.z) * gz < 0.3 * step * gap) {
        // Blocked: a step to the side instead.
        _figures.outOfSolids(p.x - gz / gap * step, 0, p.z + gx / gap * step, 0.25 * p.scale, _out, fromX: p.x, fromZ: p.z, extra: _trucks);
      }
      nx = _out[0];
      nz = _out[1];
    } else if (p.placed) {
      _figures.outOfSolids(nx, 0, nz, 0.25 * p.scale, _out, extra: _trucks);
      nx = _out[0];
      nz = _out[1];
    }
    p.placed = true;
    if (_debugJumps && nx > 11.9 && nx < 14.9 && nz > -9.0 && nz < -2.6 && _t - p.gateLogged > 2 && gateLog.length < 100) {
      p.gateLogged = _t;
      gateLog.add('worker ${p.crewNo} job ${p.job} t=${_t.toStringAsFixed(1)} at ${nx.toStringAsFixed(1)},${nz.toStringAsFixed(1)} phase $phase home ${hx.toStringAsFixed(1)},${hz.toStringAsFixed(1)} away ${ax.toStringAsFixed(1)},${az.toStringAsFixed(1)} wall ${wallWidth.toStringAsFixed(1)}');
    }
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

  final _out = [0.0, 0.0];

  /// Capture runs: walkers that jumped between two steps, and why.
  static const _debugJumps = String.fromEnvironment('BOOTH3D_TIMES') != '';
  final jumpLog = <String>[];
  final gateLog = <String>[];

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
      var speed = p.role == _Role.walker ? p.vel : (p.moving ? 1.5 : 0.0);
      // (Moved further than their walk took them: a step or two for it,
      // not a slide; eased off over a moment after.)
      final since = t - p.posedAt;
      if (p.lastX.isFinite && since > 1e-4 && since < 0.25) {
        final mx = p.x - p.lastX, mz = p.z - p.lastZ, moved = math.sqrt(mx * mx + mz * mz);
        final extra = moved - speed * since;
        if (extra > 0.005) {
          p
            ..stride += extra / Gait.stepLength(0.6, p.scale, p.manner) * math.pi
            ..shuffle = math.max(p.shuffle, 0.6);
        }
      }
      if (since > 0) p.shuffle = math.max(0.0, p.shuffle - since * 1.8);
      p
        ..lastX = p.x
        ..lastZ = p.z
        ..posedAt = t;
      speed = math.max(speed, p.shuffle);
      final amount = smooth(0.0, 0.45, speed);
      final watcher = p.role == _Role.spectator || p.role == _Role.keeper || (p.role == _Role.walker && p.pause > 0);
      // A third of those watching the celebration hold their phones up to
      // take it, the rest clap.
      final snap = cheering && watcher && rnd(p.index, 77) < 0.33;
      final cheer = cheering && watcher && !snap;
      f.rest();
      // (The crowd steers itself: see [_separate].)
      f.steer = false;
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
      // (Dark against the sky, as birds are seen.)
      material: pbr(lin(const Color(0xFF2B3442)), roughness: 0.6),
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

  /// The flock at [t]; any bird near the [camera] gone (one flying past
  /// the lens would fill the frame).
  void pose(double t, double night, vm.Vector3 camera) {
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
        final cx = x - camera.x, cy = y - camera.y, cz = z - camera.z;
        final s = 2.2 * smooth(14, 24, math.sqrt(cx * cx + cy * cy + cz * cz));
        if (s < 0.01) {
          list[i * 2].setFrom(hidden);
          list[i * 2 + 1].setFrom(hidden);
          continue;
        }
        setTrsYX(list[i * 2], x, y, z, hdg, flap + 0.15, s);
        setTrsYX(list[i * 2 + 1], x, y, z, hdg + math.pi, -flap - 0.15, s);
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
