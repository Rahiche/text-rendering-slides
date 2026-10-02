import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'crew.dart';
import 'crew_breaks.dart';
import 'kit.dart';
import 'life.dart' show StreetWork, TrafficLights;
import 'shot.dart';
import 'site_geo.dart';
import 'site_plan.dart';

/// The brick deliveries. A flatbed truck with its own little crane (a
/// ユニック車) brings each name's pallets: it comes along the avenue from
/// the east, turns in through the site gate, parks by the brick yard and
/// swings the pallets off its bed onto their yard slots before the tower
/// crane needs them. The driver works the crane from beside the truck, has a
/// can of coffee at the vending machines, maybe a chat, and drives off. The
/// first pallets of a name are already in the yard (stock); a name with many
/// pallets gets a second load.
///
/// Everything is a pure function of scene time, planned once per build from
/// the plan's trips ([BuildPlan.tripA], [BuildPlan.t0]). The truck times its
/// trips by the traffic lights ([TrafficLights]) and keeps its stretch of
/// the avenue clear ([StreetWork]: traffic and pedestrians make way).
class Delivery3D implements StreetWork {
  Delivery3D(this.scene, this.crew, this.breaks);

  final Scene scene;
  final Crew3D crew;
  final CrewBreaks breaks;

  /// The truck turns in through the gate at x = [gateX] and parks heading
  /// north, its middle at z = [parkZ] (nose by the yard, tail inside the
  /// gate).
  static const gateX = 13.4, parkZ = -5.9;

  /// The gate's opening in the front fence (x), for the city.
  static const gateFrom = 11.1, gateTo = 14.9;

  static const _half = 2.8; // half its length
  static const _far = 165.0; // where it comes from and goes (east)
  static const _turn = 4.0, _backTurn = 2.5;
  static const _lane = Plan.laneWest, _laneOut = Plan.laneEast;
  static const _bedTop = 1.05;

  final _truck = Node(name: 'delivery truck');

  /// Its sprung body (dips as it brakes, leans in turns) and its wheels
  /// (rolling; the front pair steers): node, axle x, side z.
  final _body = Node(name: 'delivery truck body');
  final _wheels = <(Node, double, double)>[];
  static const _wheelR = 0.38;
  late final InstancedMesh _parts; // the crane, the door, the slings
  late final UnlitMaterial _lampMat, _blinkMat;

  // ── The truck ─────────────────────────────────────────────────────────────

  void init() {
    // Body, cab and bed: one vertex-coloured mesh (truck-local: x forward,
    // y up, z to its left); the wheels after.
    final white = v4(hex3(0xF4F1EA)), navy = v4(hex3(0x2B4C7E)), dark = v4(hex3(0x1B2233));
    final glass = v4(hex3(0x1A2C46)), steel = v4(hex3(0x8A96A6)), wood = v4(hex3(0x8F6A44)), yellow = v4(hex3(0xFFC23D));
    MeshData box(double x, double y, double z, double w, double h, double d, vm.Vector4 c) =>
        part(CuboidGeometry(vm.Vector3(w, h, d)), vm.Matrix4.translation(vm.Vector3(x, y, z)), c);
    final body = merged([
      box(0, 0.62, 0, 5.3, 0.22, 0.9, dark), // chassis
      box(2.76, 0.62, 0, 0.12, 0.28, 2.06, dark), // bumper
      box(2.1, 1.56, 0, 1.3, 1.56, 2.0, white), // cab
      box(2.1, 1.25, 0, 1.32, 0.12, 2.02, navy), // stripe
      box(2.7, 2.3, 0, 0.22, 0.1, 1.9, navy), // visor
      box(2.765, 1.88, 0, 0.04, 0.62, 1.84, glass), // windscreen
      box(2.15, 1.9, 1.005, 0.9, 0.55, 0.03, glass), // left window
      box(2.77, 1.05, 0, 0.03, 0.34, 1.2, dark), // grille
      for (final z in [-1.05, 1.05]) box(2.0, 0.52, z, 0.38, 0.05, 0.24, steel), // steps
      box(1.1, 1.02, 0, 0.62, 0.42, 1.9, yellow), // crane base
      box(-1.03, 0.99, 0, 3.55, 0.12, 2.1, wood), // bed
      for (final z in [-1.05, 1.05]) box(-1.03, 0.82, z, 3.55, 0.26, 0.05, steel), // folded side gates
      box(0.4, 0.55, -0.72, 0.6, 0.32, 0.3, steel), // fuel tank
      for (final z in [-0.86, 0.86]) box(-1.8, 0.86, z, 1.5, 0.05, 0.4, dark), // mudguards
    ]);
    final paint = pbr(rgb(1, 1, 1), roughness: 0.5, metallic: 0.1);
    _body.add(Node(name: 'truck body', mesh: Mesh(body, paint)));
    _truck.add(_body);
    // The wheels (axle along z): tyre, hub, and nuts on the outside so you
    // see them turn.
    MeshGeometry wheelOf(double side) => merged([
      part(CylinderGeometry(bottomRadius: _wheelR, topRadius: _wheelR, height: 0.28, radialSegments: 16), trs(vm.Vector3.zero(), rotX: math.pi / 2), dark),
      part(CylinderGeometry(bottomRadius: 0.17, topRadius: 0.17, height: 0.3, radialSegments: 8), trs(vm.Vector3.zero(), rotX: math.pi / 2), steel),
      for (var k = 0; k < 5; k++)
        part(CuboidGeometry(vm.Vector3.all(0.045)), vm.Matrix4.translation(vm.Vector3(0.1 * math.cos(k * 2 * math.pi / 5), 0.1 * math.sin(k * 2 * math.pi / 5), side * 0.16)), steel),
    ]);
    final wheels = {-1.0: wheelOf(-1), 1.0: wheelOf(1)};
    for (final x in [1.95, -1.45, -2.15]) {
      for (final z in [-0.86, 0.86]) {
        final w = Node(name: 'delivery wheel', mesh: Mesh(wheels[z.sign]!, paint), localTransform: trs(vm.Vector3(x, _wheelR, z)));
        _wheels.add((w, x, z));
        _truck.add(w);
      }
    }
    // Lamps: head and tail lights (lit at night), the hazards and the roof
    // beacon (blinking while it works).
    _lampMat = UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    _blinkMat = UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1);
    final head = vm.Vector4(1, 0.95, 0.8, 1), tail = vm.Vector4(1, 0.1, 0.1, 1), hazard = vm.Vector4(1, 0.55, 0.1, 1);
    _body
      ..add(
        Node(
          name: 'truck lamps',
          mesh: Mesh(
            merged([
              for (final z in [-0.72, 0.72]) box(2.83, 0.88, z, 0.04, 0.16, 0.3, head),
              for (final z in [-0.85, 0.85]) box(-2.82, 0.75, z, 0.04, 0.12, 0.22, tail),
            ]),
            _lampMat,
          ),
        )..castsShadows = false,
      )
      ..add(
        Node(
          name: 'truck hazards',
          mesh: Mesh(
            merged([
              for (final z in [-0.98, 0.98]) box(2.83, 0.88, z, 0.04, 0.1, 0.1, hazard),
              for (final z in [-0.97, 0.97]) box(-2.82, 0.9, z, 0.04, 0.1, 0.1, hazard),
              part(CylinderGeometry(bottomRadius: 0.11, topRadius: 0.09, height: 0.14, radialSegments: 10), trs(vm.Vector3(2.1, 2.42, 0)), hazard),
            ]),
            _blinkMat,
          ),
        )..castsShadows = false,
      );
    _truck.visible = false;
    scene.add(_truck);
    // The crane's moving parts, the driver's door and the slings: unit cubes.
    _parts = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(rgb(1, 1, 1), roughness: 0.45, metallic: 0.1));
    final colors = [yellow, yellow, white, white, steel, lin(BP.coral), dark, dark, dark, dark, dark, white, glass];
    for (final c in colors) {
      _parts.addInstance(hidden, color: c);
    }
    scene.add(_partsNode..addComponent(InstancedMeshComponent(_parts)));
  }

  final _partsNode = Node(name: 'truck crane');
  static const _column = 0, _outer = 1, _inner1 = 2, _inner2 = 3, _ram = 4, _hookBlock = 5, _cable = 6, _sling0 = 7, _door = 11, _doorGlass = 12;

  // ── Per build ─────────────────────────────────────────────────────────────

  BuildPlan? _plan;
  final _runs = <_Run>[];
  final _stock = <int>{};
  final _runOf = <int, (_Run, int)>{}; // pallet → its run and place in it
  double _cutAt = double.infinity;

  /// The driver's time off (for the crew's breaks).
  final driverBreaks = <DriverBreak>[];

  /// When the camera follows the deliveries (the breaks keep clear).
  final camWindows = <(double, double)>[];

  /// Plans this build's deliveries (once, when its plan is ready).
  void planFor(BuildPlan plan) {
    _plan = plan;
    _runs.clear();
    _stock.clear();
    _runOf.clear();
    driverBreaks.clear();
    camWindows.clear();
    _cutAt = double.infinity;
    final j = plan.job;
    final n = math.min(plan.trips, 12);
    final s = 4 * plan.b + 0.12;
    final cap = _bedSlots(s).length;
    // The camera follows each load in; not across a kerning close-up.
    final kerns = [
      for (final st in plan.steps)
        if (st != null && st.filmed) (st.a - 2.0, st.e + 2.0),
    ];
    bool clashes(double a) => kerns.any((r) => a + 3 > r.$1 && a - 12 < r.$2);
    var earliest = j.startedAt + 11;
    var k = 0;
    while (k < n && cap > 0) {
      // It parks 16.7–25.3 s into the lights' cycle: it passes the lights
      // east of the plaza well after they turned green (the cars that
      // waited there are long gone), and starts across the eastbound lane
      // before it turns amber (its stretch then holds that lane's cars).
      var arrive = _next(earliest, 21.0, 4.3);
      final first = _firstLoad(plan, arrive, k, n, s);
      if (first >= n) break;
      // A little later, if that keeps it clear of the kerning (and the
      // first pallet still makes it).
      for (var a = arrive; clashes(arrive) && a < arrive + TrafficLights.cycle; a = _next(a + 0.5, 21.0, 4.3)) {
        if (!clashes(a) && _firstLoad(plan, a, first, n, s) == first) arrive = a;
      }
      final run = _Run(arrive, s);
      var u = arrive + 2.6;
      while (k < n && run.pallets.length < cap) {
        final start = _unloadFrom(plan, run, run.pallets.length, k, u);
        if (start + _unload > _need(plan, k) - 0.4) {
          if (run.pallets.isEmpty) {
            _stock.add(k++); // too soon for this load: it's in the yard already
            continue;
          }
          break;
        }
        _runOf[k] = (run, run.pallets.length);
        run.pallets.add(k++);
        run.unload.add(start);
        u = start + _unload + 0.15;
      }
      if (run.pallets.isEmpty) break;
      run.stowEnd = u + 1.2;
      // Off again after a coffee (at least 16 s at the truck), 5.6–12.8 s
      // into the lights' cycle: backing into the eastbound lane once the
      // cars that waited at its red are gone, through the crossroads east
      // before the side streets' green.
      run.depart = _next(run.stowEnd + 16, 9.2, 3.6);
      final breakFrom = run.stowEnd + 0.4, breakTo = run.depart - 3.4;
      if (breakTo - breakFrom > 6) driverBreaks.add(DriverBreak(breakFrom, breakTo, _toWorld(_controls, vm.Vector3.zero(), parked: true)));
      run.filmed = !clashes(run.arrive);
      _runs.add(run);
      if (run.filmed) camWindows.add((run.arrive - 12, run.arrive + 3));
      earliest = run.depart + 48; // to the depot and back
    }
    while (k < n) {
      _stock.add(k++);
    }
    // The plan, in capture mode's log.
    if (const String.fromEnvironment('BOOTH3D_TIMES') == '') return;
    // ignore: avoid_print
    print(
      'PLAN delivery ${j.name} start=${j.startedAt.toStringAsFixed(1)} t0=${plan.t0.toStringAsFixed(1)} len=${plan.len.toStringAsFixed(1)} trips=${plan.trips} b=${plan.b.toStringAsFixed(3)} stock=$_stock '
      'need=${[for (var q = 0; q < n; q++) _need(plan, q).toStringAsFixed(1)]} '
      'runs=${[for (final r in _runs) 'A=${r.arrive.toStringAsFixed(1)} p=${r.pallets} u=${r.unload.map((u) => u.toStringAsFixed(1)).toList()} stow=${r.stowEnd.toStringAsFixed(1)} D=${r.depart.toStringAsFixed(1)} filmed=${r.filmed}']}',
    );
  }

  /// The first of pallets [k]…[n] a load parking at [arrive] could bring
  /// in time ([n] if none).
  int _firstLoad(BuildPlan plan, double arrive, int k, int n, double s) {
    final probe = _Run(arrive, s);
    for (; k < n; k++) {
      if (_unloadFrom(plan, probe, 0, k, arrive + 2.6) + _unload <= _need(plan, k) - 0.4) return k;
    }
    return n;
  }

  /// When to start swinging pallet [k] (the [i]th on [run]'s bed) off, at
  /// or after [u]: when its swing over to the yard keeps clear of the tower
  /// crane, whose hook works low over the yard picking pallets up and waits
  /// there between trips.
  double _unloadFrom(BuildPlan p, _Run run, int i, int k, double u) {
    final deadline = _need(p, k);
    var start = u;
    while (start + _unload < deadline && _inTheWay(p, run, i, k, start)) {
      start += 0.2;
    }
    return start;
  }

  /// Whether the swing of pallet [k] (bed slot [i]) from [start] comes
  /// within reach of the tower crane's hook (and what hangs from it).
  bool _inTheWay(BuildPlan p, _Run run, int i, int k, double start) {
    final bed = _toWorld(run.slots[i], _ca, parked: true);
    final yard = SiteLayout.yard(k);
    for (var u = 1.45; u <= _unload + 0.4; u += 0.15) {
      final tower = p.hookPath(start + u);
      if (u < 2.55) {
        _swing(bed.x, bed.z, yard.x, yard.z, 0, eio((u - 1.45) / 1.1), _cb);
      } else {
        _cb.setValues(yard.x, 0, yard.z);
      }
      final dx = tower.x - _cb.x, dz = tower.z - _cb.z;
      if (dx * dx + dz * dz < 1.7 * 1.7) return true;
    }
    return false;
  }

  final _ca = vm.Vector3.zero(), _cb = vm.Vector3.zero();

  /// Seconds to swing one pallet off the bed onto its slot.
  static const _unload = 3.6;

  /// The first time ≥ [t] at [cycle] ± [slack] seconds into the traffic
  /// lights' cycle.
  static double _next(double t, double cycle, double slack) {
    const c = TrafficLights.cycle;
    final into = t % c;
    if ((into - cycle).abs() <= slack) return t;
    final base = t - into + cycle - slack;
    return base >= t ? base : base + c;
  }

  /// When pallet [k] must stand in its slot: before the tower crane's hook
  /// heads over for it (near the end of the trip before).
  static double _need(BuildPlan p, int k) {
    if (k == 0) return p.job.startedAt;
    final a = p.t0 + p.tripA(k - 1), e = p.t0 + p.tripB(k - 1);
    return math.min(a + 0.8 * (e - a), p.t0 + p.tripA(k)) - 0.5;
  }

  /// Places on the bed for pallets [s] across (truck-local, in unloading
  /// order: front row first).
  static List<vm.Vector3> _bedSlots(double s) {
    final out = <vm.Vector3>[];
    final across = 2 * s + 0.06 <= 2.3 ? 2 : 1;
    for (var row = 0; ; row++) {
      final x = 0.72 - s / 2 - row * (s + 0.08);
      if (x - s / 2 < -_half - 0.05) break;
      for (var c = 0; c < across; c++) {
        out.add(vm.Vector3(x, _bedTop, across == 1 ? 0 : (c == 0 ? 1 : -1) * (s / 2 + 0.03)));
      }
    }
    return out;
  }

  // ── Where the truck is ────────────────────────────────────────────────────

  // The pose cache: the truck at [_pt] (world, its middle on the ground),
  // heading [_pYaw], in view [_pShown], working run [_pRun].
  double _pt = double.nan;
  final _pPos = vm.Vector3.zero();
  double _pYaw = 0;

  /// How far it has rolled (signed: back is negative; for the wheels), its
  /// front wheels' steering (−1 full left … 1 full right), and its body's
  /// pitch (nose down +) and lean (left +).
  double _pOdo = 0, _pSteer = 0, _pPitch = 0, _pLean = 0;
  bool _pShown = false;
  _Run? _pRun;

  /// Poses the truck at [t] (cached).
  void _at(double t) {
    if (t == _pt) return;
    _pt = t;
    _pShown = false;
    _pRun = null;
    _pOdo = _pSteer = _pPitch = _pLean = 0;
    for (final r in _runs) {
      if (t < r.arrive - _approachTime || t > r.depart + 25) continue;
      _pRun = r;
      if (t < r.arrive) {
        _arriving(r.arrive - t);
      } else if (t < r.depart) {
        _pPos.setValues(gateX, 0, parkZ);
        _pYaw = -math.pi / 2;
        // Rocking to rest on its springs.
        final since = t - r.arrive;
        _pPitch = 0.007 * math.exp(-since * 3) * math.cos(since * 10);
      } else {
        _leaving(t - r.depart);
      }
      _pShown = _pPos.x < 140;
      return;
    }
  }

  // The arrival, backwards from parking: creep to a stop up the last
  // straight, the right turn in from the westbound lane, braking, cruising.
  static const _l3 = parkZ - (_lane + _turn), _l2 = _turn * math.pi / 2;
  static const _v1 = 8.0, _v2 = 4.0, _brake = 2.6; // (slower than any traffic ahead)
  static const _t3 = 2 * _l3 / _v2, _t2 = _l2 / _v2, _tb = (_v1 - _v2) / _brake, _db = (_v1 * _v1 - _v2 * _v2) / (2 * _brake);
  static const _approachTime = _t3 + _t2 + _tb + (_far - gateX - _turn - _db) / _v1;

  /// The truck [tau] seconds before it parks.
  void _arriving(double tau) {
    final double r; // the way left to go
    if (tau <= _t3) {
      r = 0.5 * (_v2 / _t3) * tau * tau;
    } else if (tau <= _t3 + _t2) {
      r = _l3 + _v2 * (tau - _t3);
    } else if (tau <= _t3 + _t2 + _tb) {
      final u = tau - _t3 - _t2;
      r = _l3 + _l2 + _v2 * u + 0.5 * _brake * u * u;
    } else {
      r = _l3 + _l2 + _db + _v1 * (tau - _t3 - _t2 - _tb);
    }
    _pOdo = -r;
    // Right lock for the turn in (winding on before it, off after it).
    _pSteer = smooth(_l3 + _l2 + 1.2, _l3 + _l2 - 0.4, r) * smooth(_l3 - 1.4, _l3 + 0.2, r);
    if (tau <= _t3) {
      _pPitch = 0.006 * _v2 / _t3; // creeping to a stop
    } else if (tau > _t3 + _t2 && tau <= _t3 + _t2 + _tb) {
      _pPitch = 0.006 * _brake * smooth(0, 0.3, tau - _t3 - _t2) * smooth(_tb, _tb - 0.3, tau - _t3 - _t2);
    }
    if (r <= _l3) {
      _pPos.setValues(gateX, 0, parkZ - r);
      _pYaw = -math.pi / 2;
    } else if (r <= _l3 + _l2) {
      final a = -math.pi + (r - _l3) / _turn;
      _pPos.setValues(gateX + _turn + _turn * math.cos(a), 0, _lane + _turn + _turn * math.sin(a));
      _pYaw = headingTo(math.sin(a), -math.cos(a));
      // Leaning out of the turn (to its left).
      _pLean = 0.008 * _v2 * _v2 / _turn * _pSteer;
    } else {
      _pPos.setValues(gateX + _turn + (r - _l3 - _l2), 0, _lane);
      _pYaw = math.pi;
    }
  }

  // Leaving: reverse straight out, back round into the eastbound lane, a
  // pause, then off east.
  static const _rz = _laneOut + _backTurn, _ls = parkZ - _rz, _la = _backTurn * math.pi / 2;
  static const _vr = 2.0, _ar = 2.0;
  static const _tr = 2 * _vr / _ar + (_ls + _la - _vr * _vr / _ar) / _vr;
  static const _go = 2.5;

  /// The truck [sigma] seconds after it starts to leave.
  void _leaving(double sigma) {
    if (sigma < _tr) {
      // Backing out.
      final double d;
      if (sigma < _vr / _ar) {
        d = 0.5 * _ar * sigma * sigma;
      } else if (sigma < _tr - _vr / _ar) {
        d = 0.5 * _vr * _vr / _ar + _vr * (sigma - _vr / _ar);
      } else {
        final w = _tr - sigma;
        d = _ls + _la - 0.5 * _ar * w * w;
      }
      _pOdo = -d;
      // Left lock to swing its tail round into the lane, backing.
      _pSteer = -smooth(_ls - 1.0, _ls + 0.3, d);
      _pPitch = sigma < _vr / _ar ? 0.006 * _ar : (sigma > _tr - _vr / _ar ? -0.006 * _ar : 0);
      if (d <= _ls) {
        _pPos.setValues(gateX, 0, parkZ - d);
        _pYaw = -math.pi / 2;
      } else {
        final b = -(d - _ls) / _backTurn;
        _pPos.setValues(gateX - _backTurn + _backTurn * math.cos(b), 0, _rz + _backTurn * math.sin(b));
        _pYaw = headingTo(-math.sin(b), math.cos(b));
      }
      return;
    }
    final u = math.max(0.0, sigma - _tr - 0.5);
    final tAcc = _v1 / _go;
    final x = u < tAcc ? 0.5 * _go * u * u : 0.5 * _go * tAcc * tAcc + _v1 * (u - tAcc);
    _pPos.setValues(gateX - _backTurn + x, 0, _laneOut);
    _pYaw = 0;
    _pOdo = -(_ls + _la) + x;
    // The wheel straightening as it pulls away; squatting as it accelerates.
    _pSteer = -(1 - smooth(0, 1.5, x));
    _pPitch = u > 0 && u < tAcc ? -0.006 * _go : 0;
  }

  final _tq = vm.Quaternion.identity();

  /// Truck-local [p] (at the current pose) into world [out].
  vm.Vector3 _toWorld(vm.Vector3 p, vm.Vector3 out, {bool parked = false}) {
    final yaw = parked ? -math.pi / 2 : _pYaw;
    final base = parked ? _parkedAt : _pPos;
    final c = math.cos(yaw), s = math.sin(yaw);
    return out..setValues(base.x + p.x * c + p.z * s, base.y + p.y, base.z - p.x * s + p.z * c);
  }

  static final _parkedAt = vm.Vector3(gateX, 0, parkZ);

  // The driver's places (truck-local): the seat, the step out of the door,
  // the crane's controls.
  static final _seat = vm.Vector3(2.0, 1.06, -0.45), _step = vm.Vector3(2.05, 0, -1.55), _controls = vm.Vector3(0.95, 0, -1.6);

  // ── The hook for the plan ─────────────────────────────────────────────────

  /// For [BuildPlan.palletOnTheWay]: pallet [k] on the truck's bed, or
  /// swinging off it, at [t].
  bool palletAt(int k, double t, PalletPose out) {
    final at = _runOf[k];
    if (at == null) return false;
    final (run, i) = at;
    final start = run.unload[i];
    final cancelled = start >= _cutAt;
    if (!cancelled && t >= start + _landed) return false;
    _at(t);
    if (!cancelled && t >= start + _hooked && identical(_pRun, run)) {
      // On the crane: hanging from the hook.
      _hookAt(run, t, _hp);
      out.base.setValues(_hp.x, _hp.y - _hangOf(k), _hp.z);
      out
        ..yaw = -math.pi / 2
        ..shown = true;
      return true;
    }
    // On the bed (at the depot, out of sight).
    if (!identical(_pRun, run)) {
      out
        ..base.setValues(_far + 40, 0, _lane)
        ..yaw = 0
        ..shown = false;
      return true;
    }
    _toWorld(run.slots[i], out.base);
    out
      ..yaw = _pYaw
      ..shown = _pShown;
    return true;
  }

  final _hp = vm.Vector3.zero();

  // When, into an unload, the pallet leaves the bed and lands in the yard.
  static const _hooked = 1.0, _landed = 3.15;

  /// How far a pallet's base hangs below the hook.
  double _hangOf(int k) {
    final p = _plan!;
    return 0.14 + p.layers(k) * p.b + 0.55;
  }

  /// The truck-crane's hook for [run] at [t] (world; parked).
  void _hookAt(_Run run, double t, vm.Vector3 out) {
    final p = _plan!;
    // Resting over the bed, stowed.
    final rest = _toWorld(vm.Vector3(-0.6, 2.95, 0), _hr, parked: true);
    final unfold = seg(t, run.arrive + 1.2, run.arrive + 2.6) * (1 - seg(t, run.stowEnd - 1.2, run.stowEnd));
    var i = -1;
    for (var n = 0; n < run.pallets.length; n++) {
      if (t >= run.unload[n] && run.unload[n] < _cutAt) i = n;
    }
    if (i < 0) {
      out.setFrom(rest);
      out.y = lerp(2.95, 4.2, unfold);
      return;
    }
    final k = run.pallets[i];
    final u = t - run.unload[i];
    final hang = _hangOf(k);
    final onBed = _toWorld(run.slots[i], _hb, parked: true)..y += hang;
    final yard = SiteLayout.yard(k);
    final travel = _bedTop + 0.14 + p.layers(k) * p.b + 0.25 + hang + 0.05;
    // From where the last one was let go (or the rest), down to this one.
    final from = i == 0 ? (rest..y = 4.2) : _released(run, i - 1, _hf);
    if (u < 0.8) {
      _lerp3(from, onBed..y += 0.5 * (1 - eio(u / 0.8)), eio(u / 0.8), out);
    } else if (u < _hooked) {
      out.setFrom(onBed);
    } else if (u < 1.45) {
      out.setFrom(onBed);
      out.y = lerp(onBed.y, travel, eio((u - _hooked) / 0.45));
    } else if (u < 2.55) {
      // Slewing round the truck's left, over to the slot.
      _swing(onBed.x, onBed.z, yard.x, yard.z, travel, eio((u - 1.45) / 1.1), out);
    } else if (u < _landed) {
      out.setValues(yard.x, lerp(travel, hang, eio((u - 2.55) / (_landed - 2.55))), yard.z);
    } else {
      out.setValues(yard.x, hang + 0.8 * eio((u - _landed) / 0.45), yard.z);
    }
    if (t > run.stowEnd - 1.4) {
      // Back to rest.
      final f = eio(seg(t, run.stowEnd - 1.4, run.stowEnd));
      _hf.setFrom(out);
      _lerp3(_hf, rest..y = lerp(4.2, 2.95, f), f, out);
    }
  }

  final _hr = vm.Vector3.zero(), _hb = vm.Vector3.zero(), _hf = vm.Vector3.zero();

  vm.Vector3 _released(_Run run, int i, vm.Vector3 out) {
    final y = SiteLayout.yard(run.pallets[i]);
    return out..setValues(y.x, _hangOf(run.pallets[i]) + 0.8, y.z);
  }

  static void _lerp3(vm.Vector3 a, vm.Vector3 b, double f, vm.Vector3 out) => out.setValues(lerp(a.x, b.x, f), lerp(a.y, b.y, f), lerp(a.z, b.z, f));

  /// Swings the hook round the crane's column (on the truck's left, west),
  /// from (ax, az) to (bx, bz) at height [y].
  void _swing(double ax, double az, double bx, double bz, double y, double f, vm.Vector3 out) {
    final c = _toWorld(vm.Vector3(1.1, 0, 0), _hc, parked: true);
    final ra = math.sqrt((ax - c.x) * (ax - c.x) + (az - c.z) * (az - c.z)), rb = math.sqrt((bx - c.x) * (bx - c.x) + (bz - c.z) * (bz - c.z));
    final ta = math.atan2(az - c.z, ax - c.x);
    var tb = math.atan2(bz - c.z, bx - c.x);
    // The bed is south of the column, the yard north: go round by the west.
    while (tb < ta) {
      tb += 2 * math.pi;
    }
    if (tb - ta > 2 * math.pi - 0.01) tb -= 2 * math.pi;
    final th = ta + (tb - ta) * f, r = ra + (rb - ra) * f;
    out.setValues(c.x + math.cos(th) * r, y, c.z + math.sin(th) * r);
  }

  final _hc = vm.Vector3.zero();

  // ── Per frame ─────────────────────────────────────────────────────────────

  final _m = vm.Matrix4.identity(), _l = vm.Matrix4.identity();
  final _a = vm.Vector3.zero(), _b = vm.Vector3.zero(), _c = vm.Vector3.zero();

  /// Moves the truck, its crane and its pallets' driver for [j] at [t].
  void update(Job j, BuildPlan? plan, double t, double night) {
    final p = crew.poses[Crew3D.driver]..rest();
    p.visible = false;
    if (plan == null || !identical(plan, _plan)) {
      _truck.visible = _partsNode.visible = false;
      return;
    }
    // A sample cut short: no more unloading (the rest stays on the bed).
    if (j.cutAt != null && j.phase.index >= Phase.demolish.index && _cutAt.isInfinite) _cutAt = j.phase == Phase.demolish ? j.phaseStart : t;
    _at(t);
    final run = _pRun;
    _truck.visible = _partsNode.visible = _pShown;
    if (!_pShown || run == null) return;
    _truck.place((m) => setTrs(m, _pPos.x, _pPos.y, _pPos.z, yaw: _pYaw));
    _body.place((m) => setTrs(m, 0, 0, 0, pitch: _pLean, roll: -_pPitch));
    for (final (w, x, z) in _wheels) {
      final steer = x > 0 ? 0.55 * _pSteer : 0.0;
      w.place((m) => setTrs(m, x, _wheelR, z, yaw: steer, roll: -_pOdo / _wheelR));
    }
    final parked = t >= run.arrive && t < run.depart;
    final blink = (t * 1.6) % 1.0 < 0.5;
    final working = t > run.arrive - 0.6 && t < run.depart + 1.2;
    final k = 1 + 4 * smooth(0.15, 0.5, night);
    _lampMat.baseColorFactor = vm.Vector4(k, k, k, 1);
    final h = working && blink ? 4.0 + 4 * night : 0.35;
    _blinkMat.baseColorFactor = vm.Vector4(h, h, h, 1);
    _crane(run, t, parked);
    _poseDriver(p, run, t);
  }

  /// The crane: column, two-stage telescopic boom, its ram, the hook on its
  /// cable, the slings to a pallet; and the driver's door.
  void _crane(_Run run, double t, bool parked) {
    // Truck-local column foot and boom pivot.
    final col = _toWorld(vm.Vector3(1.1, 1.2, 0), _a);
    final pivot = _toWorld(vm.Vector3(1.1, 2.5, 0), vm.Vector3.zero());
    final hook = _c;
    if (parked) {
      _hookAt(run, t, hook);
    } else {
      // Stowed over the bed.
      _toWorld(vm.Vector3(-0.6, 2.95, 0), hook);
    }
    // The boom points from the pivot to a tip over the hook (on its cable).
    final dx = hook.x - pivot.x, dz = hook.z - pivot.z;
    final reach = math.max(0.3, math.sqrt(dx * dx + dz * dz));
    var tipY = hook.y + 0.7;
    final minLen = 2.6;
    var len = math.sqrt(reach * reach + (tipY - pivot.y) * (tipY - pivot.y));
    if (len < minLen) {
      tipY = pivot.y + math.sqrt(math.max(0.0, minLen * minLen - reach * reach));
      len = minLen;
    }
    final stowed = !parked || t < run.arrive + 1.2 || t > run.stowEnd;
    final tip = vm.Vector3(pivot.x + dx / reach * reach, tipY, pivot.z + dz / reach * reach);
    if (stowed) {
      // Lying on its rest, pointing back over the bed.
      _toWorld(vm.Vector3(-1.5, 2.62, 0), tip);
      len = pivot.distanceTo(tip);
    }
    final dir = (tip - pivot)..normalize();
    void beam(int i, vm.Vector3 a, vm.Vector3 b, double thick) => _parts.setInstanceTransform(i, setSpan(_m, a, b, thickness: thick));
    // Column: from the base to the pivot.
    _parts.setInstanceTransform(_column, setTqs(_m, col.x, (col.y + pivot.y) / 2, col.z, _tq..setAxisAngle(_up, _pYaw), 0.44, pivot.y - col.y, 0.44));
    final outer = math.min(2.7, len);
    beam(_outer, pivot, pivot + dir * outer, 0.3);
    final ext = math.max(0.0, len - 2.6);
    beam(_inner1, pivot + dir * (0.4 + ext * 0.5), pivot + dir * (2.4 + ext * 0.5), 0.24);
    beam(_inner2, pivot + dir * (0.6 + ext), tip, 0.19);
    beam(_ram, _toWorld(vm.Vector3(1.4, 1.5, 0), _b), pivot + dir * 1.1 - vm.Vector3(0, 0.12, 0), 0.12);
    if (stowed) {
      for (final i in [_hookBlock, _cable, _sling0, _sling0 + 1, _sling0 + 2, _sling0 + 3]) {
        _parts.setInstanceTransform(i, hidden);
      }
    } else {
      _parts.setInstanceTransform(_hookBlock, setTqs(_m, hook.x, hook.y + 0.12, hook.z, _tq..setAxisAngle(_up, _pYaw), 0.22, 0.3, 0.16));
      beam(_cable, tip, hook + vm.Vector3(0, 0.25, 0), 0.03);
      // Slings, while a pallet hangs (or is being hooked).
      final i = _carrying(run, t);
      for (var c = 0; c < 4; c++) {
        if (i < 0) {
          _parts.setInstanceTransform(_sling0 + c, hidden);
          continue;
        }
        final k = run.pallets[i];
        final s = run.size / 2 - 0.05;
        final top = hook.y - _hangOf(k) + 0.14 + _plan!.layers(k) * _plan!.b;
        final corner = vm.Vector3(hook.x + (c.isEven ? -s : s), top, hook.z + (c < 2 ? -s : s));
        beam(_sling0 + c, corner, hook, 0.016);
      }
    }
    // The driver's door swings open as they get in and out.
    final open = _doorOpen(run, t);
    final hinge = _toWorld(vm.Vector3(2.45, 1.55, -1.03), vm.Vector3.zero());
    final yaw = _pYaw - 1.2 * open;
    _l.setIdentity();
    setTrs(_m, hinge.x, hinge.y, hinge.z, yaw: yaw);
    _parts.setInstanceTransform(
      _door,
      _l
        ..setFrom(_m)
        ..multiply(setTqs(vm.Matrix4.identity(), -0.45, -0.1, 0, _tq0, 0.9, 1.35, 0.04)),
    );
    _parts.setInstanceTransform(_doorGlass, (_l..setFrom(_m))..multiply(setTqs(vm.Matrix4.identity(), -0.42, 0.33, -0.012, _tq0, 0.8, 0.5, 0.03)));
  }

  static final _up = vm.Vector3(0, 1, 0);
  static final _tq0 = vm.Quaternion.identity();

  /// Which of [run]'s pallets hangs from the hook at [t] (slings on), or -1.
  int _carrying(_Run run, double t) {
    for (var i = 0; i < run.pallets.length; i++) {
      final u = t - run.unload[i];
      if (run.unload[i] < _cutAt && u >= 0.8 && u < _landed + 0.25) return i;
    }
    return -1;
  }

  double _doorOpen(_Run run, double t) {
    double bump(double a, double b) => seg(t, a, a + 0.3) * (1 - seg(t, b - 0.3, b));
    return math.max(bump(run.arrive + 0.2, run.arrive + 1.6), bump(run.depart - 1.9, run.depart - 0.3));
  }

  // ── The driver ────────────────────────────────────────────────────────────

  final _dp = vm.Vector3.zero(), _dq = vm.Vector3.zero();

  void _poseDriver(FigurePose p, _Run run, double t) {
    p.visible = true;
    final seatYaw = _pYaw - math.pi / 2;
    void seated() {
      _toWorld(_seat, p.pos);
      p
        ..yaw = seatYaw
        ..legPitch[0] = 1.45
        ..legPitch[1] = 1.45;
      p.armPitch[0] = p.armPitch[1] = 1.1;
      p.armRoll[0] = p.armRoll[1] = -0.12;
    }

    final out0 = run.arrive + 0.3, out1 = run.arrive + 1.5;
    final in0 = run.depart - 1.8, in1 = run.depart - 0.3;
    if (t < out0 || t >= in1) {
      seated();
      return;
    }
    if (t < out1 || t >= in0) {
      // Climbing down from the cab (or back up), through the open door.
      final f = t < out1 ? (t - out0) / (out1 - out0) : 1 - (t - in0) / (in1 - in0);
      _toWorld(_seat, _dp);
      _toWorld(_step, _dq);
      final e = eio(f);
      p.pos.setValues(lerp(_dp.x, _dq.x, e), lerp(_dp.y, 0, eio(c01(f * 1.4 - 0.3))), lerp(_dp.z, _dq.z, e));
      p.yaw = seatYaw - math.pi / 2 * eio(c01(f * 2));
      p.legPitch[0] = p.legPitch[1] = 1.45 * (1 - e);
      p.armPitch[1] = 1.0 + 0.6 * math.sin(f * math.pi);
      return;
    }
    // On a break (coffee at the machines)?
    if (breaks.poseDriver(p, t)) return;
    final ctl = _toWorld(_controls, _dp);
    final step = _toWorld(_step, _dq);
    final toCtl = run.arrive + 2.4;
    if (t < toCtl) {
      _walk(p, step, ctl, out1, toCtl, t);
      return;
    }
    if (t >= in0 - 1.5) {
      _walk(p, ctl, step, in0 - 1.5, in0, t);
      return;
    }
    // At the controls: a radio remote at the chest, eyes on the load.
    p.pos.setFrom(ctl);
    OffDuty.stand(p, t, 5);
    _hookAt(run, t, _hp);
    p.yaw = math.atan2(-(_hp.x - p.pos.x), -(_hp.z - p.pos.z));
    if (t < run.stowEnd + 0.3) {
      p.armPitch[0] = p.armPitch[1] = 0.95 + 0.05 * math.sin(t * 6);
      p.armRoll[0] = p.armRoll[1] = -0.2;
      p.lean = -0.05;
    } else {
      // Done: a stretch.
      OffDuty.stretch(p, ((t - run.stowEnd) % 6) / 6, 3);
    }
  }

  void _walk(FigurePose p, vm.Vector3 a, vm.Vector3 b, double t0, double t1, double t) {
    final f = c01((t - t0) / math.max(t1 - t0, 1e-3));
    p.pos.setValues(lerp(a.x, b.x, f), 0, lerp(a.z, b.z, f));
    if (f < 1) {
      OffDuty.walk(p, t, a.distanceTo(b) / math.max(t1 - t0, 1e-3), 5);
      p.yaw = math.atan2(-(b.x - a.x), -(b.z - a.z));
    } else {
      OffDuty.stand(p, t, 5);
    }
  }

  // ── The city: the gate, the lanes, the camera ─────────────────────────────

  /// How far the site gate is open at [t] (0 shut … 1 open).
  double gateOpen(double t) {
    var open = 0.0;
    for (final r in _runs) {
      open = math.max(open, seg(t, r.arrive - 7, r.arrive - 5.8) * (1 - seg(t, r.arrive + 0.6, r.arrive + 1.8)));
      open = math.max(open, seg(t, r.depart - 1.6, r.depart - 0.4) * (1 - seg(t, r.depart + 5.5, r.depart + 6.7)));
    }
    return open;
  }

  @override
  (double, double)? gateBusy(double t) {
    for (final r in _runs) {
      if (t > r.arrive - 7.5 && t < r.arrive - 0.3) return (gateFrom - 0.5, gateTo + 0.6);
      if (t > r.depart - 1.8 && t < r.depart + 6.2) return (gateFrom - 0.5, gateTo + 0.6);
    }
    return null;
  }

  @override
  (double, double)? laneBlock(bool eastbound, double t) {
    for (final r in _runs) {
      if (eastbound) {
        // Turning in across it, then backing out into it and driving off.
        if (t > r.arrive - 8 && t < r.arrive - 1.8) return (gateX - 2.4, gateX + _turn + 2.6);
        if (t > r.depart - 1.5 && t < r.depart + _tr + 0.6) return (gateX - _backTurn - _half - 0.6, gateX + 1.6);
        if (t >= r.depart + _tr + 0.6 && t < r.depart + 30) {
          _at(t);
          if (_pPos.x < 160) return (_pPos.x - _half - 0.4, _pPos.x + _half + 0.4);
        }
      } else if (t > r.arrive - _approachTime && t < r.arrive - _t3 - _t2 * 0.5) {
        // Coming along the westbound lane (cars behind follow it).
        _at(t);
        return (_pPos.x - _half - 0.4, _pPos.x + _half + 0.4);
      }
    }
    return null;
  }

  /// The camera's request at [t] (priority 2): behind the truck as it comes
  /// along the avenue, then alongside as it turns in and pulls up by the
  /// yard; then away (to the Glyph Works, where a letter's journey starts,
  /// or the build). Nothing during a kerning close-up.
  void focus(List<Focus> out, double t) {
    if (out.any((f) => f.priority > 2)) return;
    for (var n = 0; n < _runs.length; n++) {
      final r = _runs[n];
      final a = r.arrive;
      if (!r.filmed || t < a - 11 || t >= a + 2.5) continue;
      _at(t);
      final px = _pPos.x, pz = _pPos.z;
      if (t < a - 5) {
        // Behind and above, looking ahead along the avenue (a little lead);
        // cut to from whatever was on.
        final eye = vm.Vector3(px + 10.5, 5.0, pz + 2.2), tg = vm.Vector3(px - 7, 1.2, pz + 1.0);
        out.add(Focus('delivery $n chase', Shot(eye, tg, fov: 48, settle: 0.45, drift: 0.5), priority: 2));
        return;
      }
      // Cut to alongside, from inside the plaza: it turns in through the
      // gate and pulls up by the yard.
      final eye = vm.Vector3(5.8, 5.2, -7.6), tg = vm.Vector3(lerp(px, gateX, 0.5), 1.4, lerp(pz, parkZ, 0.4));
      out.add(Focus('delivery $n', Shot(eye, tg, fov: 44, settle: 1.3, drift: 0.5), priority: 2));
      return;
    }
  }
}

/// One load: parked at [arrive], pallets [pallets] swung off from [unload]
/// (one per [Delivery3D._unload]), the crane stowed at [stowEnd], off at
/// [depart].
class _Run {
  _Run(this.arrive, this.size) : slots = Delivery3D._bedSlots(size);
  final double arrive, size;
  final List<vm.Vector3> slots;
  final pallets = <int>[];
  final unload = <double>[];
  double stowEnd = 0, depart = 0;

  /// Whether the camera follows it in (not across a kerning close-up).
  bool filmed = true;
}
