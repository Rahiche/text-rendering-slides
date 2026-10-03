import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'figure.dart';
import 'kit.dart';
import 'motion.dart';
import 'site_geo.dart';
import 'site_kern.dart';
import 'site_plan.dart';

export 'figure_rig.dart' show FigurePose;

/// The site crew: six builders (one per stretch of wall, zone colours on
/// their vests), the foreman with his clipboard, the crane operator in the
/// cab, and the driver who brings the bricks (posed by the delivery, see
/// delivery.dart); and, posed by their own scenes, the Glyph Works' three
/// makers (glyph_works.dart), the new manager and his two planners
/// (verdict.dart). They're drawn with everyone else in the city (see
/// figure.dart), each in their work clothes: the builders in hi-vis vests
/// over work shirts, gloves and hard hats, the foreman in white with his
/// clipboard, the makers in lab coats and caps, the manager in a suit.
/// Also the climbing platform the builders work on: two lattice masts and a
/// deck that rises with the wall.
///
/// The name goes up a letter at a time: its team lays it (a handful of
/// bricks a swing), then two of them stretch the tape across the gap while
/// the foreman checks his clipboard, and they heave the letter into place.
/// Where everyone is comes from the plan ([BuildPlan.crewAt]).
class Crew3D {
  Crew3D(this.scene);

  final Scene scene;

  static const builders = NameRaster.zones, foreman = builders, operator = builders + 1, driver = builders + 2;

  /// The Glyph Works' makers (three), the manager and his planners (two).
  static const makers = builders + 3, manager = builders + 6, planners = builders + 7, count = builders + 9;

  /// One vest colour per zone, as on the 2D booth's hard hats.
  static const vests = [BP.amber, BP.coral, BP.green, BP.violet, BP.pink, BP.line];

  final poses = List.generate(
    count,
    (i) => FigurePose()
      ..rest()
      ..visible = i <= operator,
  );

  /// Builders the build doesn't need right now go on a break (see
  /// crew_breaks.dart): called once builder [z] is posed for the job, it may
  /// pose them for their break instead. Set by the site.
  void Function(FigurePose p, int z, BuildPlan plan, double t, double floor)? offDuty;

  /// The scenes that need the whole crew (the finish, the team photo, the
  /// manager's visit): called for every figure [who] just before it's
  /// drawn, it may pose them instead. Set by the site.
  void Function(int who, FigurePose p)? stage;

  /// Where the finish (site_finish.dart) has builder [z] at [t], if it has
  /// them then: where they set off from when it's called off. Set by the
  /// site.
  vm.Vector3? Function(int z, double t)? finishAt;

  late final Figures _figures;
  final _slots = <int>[];
  late final InstancedMesh _deck, _bulbs;
  final _masts = <Node>[];
  static const _maxBulbs = 44;
  double _night = 0;

  void init() {
    _figures = Figures.of(scene);
    for (var i = 0; i < count; i++) {
      _slots.add(_figures.add(_lookOf(i)));
    }

    // The climbing platform: masts (static lattice) and the deck parts.
    final mast = MeshBatch();
    latticeMast(mast, w: 0.42, y0: 0, y1: 9.6, section: 0.7, post: 0.06, brace: 0.03);
    final mastGeo = mast.build();
    final steel = pbr(rgb(0.55, 0.58, 0.62), roughness: 0.45, metallic: 0.6);
    for (var i = 0; i < 2; i++) {
      final n = Node(name: 'platform mast $i', mesh: Mesh(mastGeo, steel))..visible = false;
      _masts.add(n);
      scene.add(n);
    }
    _deck = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(rgb(1, 1, 1), roughness: 0.7, metallic: 0.05));
    for (var i = 0; i < _deckParts; i++) {
      _deck.addInstance(hidden);
    }
    scene.add(Node(name: 'platform deck')..addComponent(InstancedMeshComponent(_deck)));
    _bulbs = InstancedMesh(geometry: SphereGeometry(radius: 0.055, segments: 8, rings: 5), material: UnlitMaterial());
    for (var i = 0; i < _maxBulbs; i++) {
      _bulbs.addInstance(hidden);
    }
    scene.add(
      Node(name: 'platform bulbs')
        ..addComponent(InstancedMeshComponent(_bulbs))
        ..castsShadows = false,
    );
  }

  static const _deckParts = 72;

  /// The gates in the platform's back rail: one behind each builder's rest
  /// spot (where they step on and off it), [gateHalf] either side of it.
  static const gateHalf = 0.45;
  List<double> _gates = const [];

  /// Where the builders walk along behind the platform (off its back).
  static const behindZ = 2.4;

  /// How far out from the middle the way round an end of the platform
  /// goes, for a wall [w] wide: clear of its end rail, the mast's climbing
  /// gear and (on the right) the brick yard's pallets.
  static double endX(double w) => w / 2 + 1.4;

  /// The way off the platform from a rest spot at x [restX]: back through
  /// its gate, along behind the platform to its end [e] (−1 left, +1
  /// right), round it to the front corner of the wall.
  static List<vm.Vector3> offPlatform(double restX, double w, double e) => [
    vm.Vector3(restX, 0, SiteLayout.crewZ),
    vm.Vector3(restX, 0, behindZ),
    vm.Vector3(e * endX(w), 0, behindZ),
    vm.Vector3(e * endX(w), 0, -0.6),
  ];

  /// How high someone at [p] stands: on the deck (its floor at [floor]),
  /// stepping down off its back edge, else on the ground.
  static double standY(vm.Vector3 p, double w, double floor) {
    if (p.x.abs() > w / 2 + 1.0 || p.z <= SiteLayout.deckZ0 || p.z >= SiteLayout.deckZ1 + 0.3) return 0;
    return floor * smooth(SiteLayout.deckZ1 + 0.3, SiteLayout.deckZ1 - 0.05, p.z);
  }

  /// What figure [i] wears: the builders a hi-vis vest in their zone's
  /// colour over a work shirt, gloves and a yellow hard hat; the foreman a
  /// white jacket and hat; the crane operator orange; the driver navy; the
  /// makers lab coats and teal caps; the manager a navy suit and a white
  /// hat, his planners light blue shirts.
  static FigureLook _lookOf(int i) {
    const skins = [0xEAC9AE, 0xC59A7C, 0xE0BB9E, 0x9A6C52, 0xF0D2BC, 0xD6AE90, 0xB88B6E, 0xE8C6AC, 0xDDB89C, 0xF2D4C0, 0xC09073, 0xE6C2A6, 0xD9B194, 0xEFCDB4, 0xA97A5E];
    const hairs = [0x1A1714, 0x2A211B, 0x1A1714, 0x3D2B20, 0x1A1714, 0x2A211B, 0x8F8B86, 0x1A1714, 0x2A211B, 0x1A1714, 0x5A3F2C, 0x2A211B, 0x3D2B20, 0x1A1714, 0x2A211B];
    final l = FigureLook()
      ..skin = rgbHex(skins[i % skins.length])
      ..hairColor = rgbHex(hairs[i % hairs.length])
      ..girth = 0.94 + 0.14 * rnd(i, 3)
      ..hair = rnd(i, 4) < 0.7 ? Hair.short : Hair.medium
      ..legs = rgbHex(0x243650)
      ..shoes = rgbHex(0x24211F);
    if (i < builders) {
      return l
        ..top = rgbHex(0x3E4A5E)
        ..layer = lin(vests[i])
        ..stripes = true
        ..gloves = rgbHex(0xE9E4D6)
        ..hardHat = lin(const Color(0xFFFFD43B))
        ..slim = i == 4
        ..hair = i == 4 ? Hair.bob : l.hair;
    }
    switch (i) {
      case foreman:
        l
          ..top = lin(const Color(0xFFF4F1EA))
          ..legs = rgbHex(0x3A4252)
          ..hardHat = rgbHex(0xFFFFFF)
          ..clipboard = true
          ..girth = 1.08;
      case operator:
        l
          ..top = lin(const Color(0xFFFF8A3D))
          ..hardHat = lin(const Color(0xFFFFD43B))
          ..gloves = rgbHex(0xE9E4D6);
      case driver:
        l
          ..top = lin(const Color(0xFF2B4C7E))
          ..hardHat = lin(BP.line);
      case manager:
        l
          ..top = rgbHex(0xF2F0EA)
          ..sleeves = lin(const Color(0xFF1C2741))
          ..layer = lin(const Color(0xFF1C2741))
          ..legs = lin(const Color(0xFF141A28))
          ..shoes = rgbHex(0x141416)
          ..hardHat = rgbHex(0xFFFFFF)
          ..girth = 1.05;
      case >= planners:
        l
          ..top = lin(const Color(0xFFA9CBEA))
          ..legs = rgbHex(0x4A5466)
          ..hardHat = lin(BP.line)
          ..slim = i == planners + 1
          ..hair = i == planners + 1 ? Hair.bob : l.hair;
      default:
        // The makers.
        final coat = lin(const Color(0xFFD7E3EC));
        l
          ..top = coat
          ..skirt = coat
          ..skirtLength = 1.05
          ..legs = rgbHex(0x2B3442)
          ..cap = lin(const Color(0xFF2BB3A3))
          ..slim = i == makers + 1
          ..hair = i == makers + 1 ? Hair.bob : l.hair;
    }
    return l;
  }

  // ── Drawing ───────────────────────────────────────────────────────────────

  final _m = vm.Matrix4.identity();

  void _draw(int i) => _figures.draw(_slots[i], poses[i]);

  /// How fast figure [i] was going in the last frame (x, z, m/s).
  (double, double) velocityOf(int i) => _figures.velocityOf(_slots[i]);

  final _rig = FigureRig();
  final _sh = vm.Vector3.zero(), _d = vm.Vector3.zero();

  /// Points arm [s] of [p] at [target] (world) and bends its elbow so the
  /// hand gets there (when it's in reach); crouching no lower than
  /// [maxStoop] for it (at a workbench, say: they lean over it instead of
  /// going under it).
  void aim(FigurePose p, int s, vm.Vector3 target, {double maxStoop = 0.7, double maxLean = 0.75}) => _aim(p, s, target, maxStoop: maxStoop, maxLean: maxLean);

  /// Where builder [z] watches from, beside a wall [w] wide (the front right).
  vm.Vector3 watchSpot(int z, double w) => _watchSpot(z, w);

  /// Poses the skeleton for [p] and returns how far [target] is from
  /// shoulder [s] (left in [_sh], the way in [_d]).
  double _reach(FigurePose p, int s, vm.Vector3 target) {
    _rig.solve(p, arms: false);
    _rig.shoulder(s, 1, _sh);
    _d
      ..setFrom(target)
      ..sub(_sh);
    return _d.length;
  }

  /// Points arm [s] of [p] at [target] (world). Out of reach in front, they
  /// lean towards it (crouching and bending to it, if it's low), as far as
  /// [maxLean] and [maxStoop] go.
  void _aim(FigurePose p, int s, vm.Vector3 target, {double maxStoop = 0.7, double maxLean = 0.75}) {
    // The shoulder as the figure stands, and the chest's turn.
    var r = _reach(p, s, target);
    final hx = target.x - p.pos.x, hz = target.z - p.pos.z, ahead = -math.sin(p.yaw) * hx - math.cos(p.yaw) * hz;
    if (r > FigureRig.maxReach && hx * hx + hz * hz < 1.44 && ahead > 0.2) {
      if (target.y < _sh.y - 0.55) {
        // Low: a crouch and a bend.
        if (p.stoop < maxStoop) {
          var lo = p.stoop, hi = math.min(p.stoop + 0.7, maxStoop);
          for (var k = 0; k < 6; k++) {
            p.stoop = (lo + hi) / 2;
            if (_reach(p, s, target) > FigureRig.maxReach) {
              lo = p.stoop;
            } else {
              hi = p.stoop;
            }
          }
          p.stoop = hi;
        }
      } else if (target.y < _sh.y + 0.2 && p.lean < maxLean) {
        // Out in front: a lean towards it.
        var lo = p.lean, hi = maxLean;
        for (var k = 0; k < 6; k++) {
          p.lean = (lo + hi) / 2;
          if (_reach(p, s, target) > FigureRig.maxReach) {
            lo = p.lean;
          } else {
            hi = p.lean;
          }
        }
        p.lean = hi;
      }
      r = _reach(p, s, target);
    }
    if (r < 1e-6) return;
    _d.scale(1 / r);
    // Into the chest's frame (its rotation's transpose).
    final c = _rig.chest.storage;
    final x1 = c[0] * _d.x + c[1] * _d.y + c[2] * _d.z, y1 = c[4] * _d.x + c[5] * _d.y + c[6] * _d.z, z1 = c[8] * _d.x + c[9] * _d.y + c[10] * _d.z;
    final side = s == 0 ? -1.0 : 1.0;
    p.armPitch[s] = math.asin((-z1).clamp(-1.0, 1.0));
    p.armRoll[s] = side * math.atan2(x1, -y1);
    p.elbow[s] = FigureRig.bendFor(r.clamp(FigureRig.minReach, FigureRig.maxReach));
    p.aimed(s, target);
  }

  // ── Behaviour ─────────────────────────────────────────────────────────────

  /// Where builder [z] stands to work at the start of a build of width [w].
  vm.Vector3 _workSpot(int z, double w) => vm.Vector3(((z + 0.5) / builders - 0.5) * w, 0, SiteLayout.crewZ);

  /// Where builder [z] watches from: front right of the wall, in a row in
  /// front of the brick yard (its pallets are there till the celebration's
  /// over), builder 0 nearest the wall.
  vm.Vector3 _watchSpot(int z, double w) => vm.Vector3(w / 2 + 1.95 + 0.85 * z, 0, watchZ);

  /// The watchers' row, and the lane in front of it they come and go by
  /// (each turning into their place from it: nobody walks through anyone
  /// already standing there).
  static const watchZ = -2.75, watchLane = -3.5;

  /// Between the platform and where builder [z] watches from: through
  /// their gate in the back rail, along behind the platform, round its
  /// right end to the front (from or to [from] on the platform: along the
  /// deck to the gate first; else their rest spot); from the front of the
  /// wall (the finish called off), along it.
  List<vm.Vector3> _route(int z, double w, {required bool toWall, vm.Vector3? from, double? watchW}) {
    final rest = _workSpot(z, w), watch = _watchSpot(z, watchW ?? w);
    final work = from ?? rest;
    if (work.z < 0) return toWall ? [watch, vm.Vector3(work.x, 0, -2.6), work] : [work, vm.Vector3(work.x, 0, -2.6), watch];
    final gate = _gates.length > z ? _gates[z] : rest.x;
    final off = offPlatform(gate, w, 1);
    final pts = [
      if (work.distanceTo(off.first) > 0.05) work,
      ...off,
      // (Down past the yard's front corner, along the lane, up into place.)
      vm.Vector3(off.last.x, 0, watchLane),
      vm.Vector3(watch.x, 0, watchLane),
      watch,
    ];
    return toWall ? pts.reversed.toList() : pts;
  }

  /// Position along a walked route started at [start] at [speed]; returns
  /// whether still walking and the heading.
  (bool, double) _walk(List<vm.Vector3> pts, double start, double speed, double t, vm.Vector3 out) {
    var s = math.max(0.0, (t - start) * speed);
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final l = a.distanceTo(b);
      if (s <= l || i + 2 == pts.length) {
        final f = l > 0 ? c01(s / l) : 1.0;
        out.setValues(a.x + (b.x - a.x) * f, 0, a.z + (b.z - a.z) * f);
        final moving = t >= start && !(i + 2 == pts.length && f >= 1);
        return (moving, math.atan2(-(b.x - a.x), -(b.z - a.z)));
      }
      s -= l;
    }
    out.setFrom(pts.last);
    return (false, 0);
  }

  /// Walking (or running) at [speed], [dist] metres into a walk [total]
  /// long (its steps fitted to end with the feet passing).
  void _gait(FigurePose p, double dist, double speed, int seed, double total) {
    final m = Manner.of(seed);
    Gait.walk(p, Gait.phaseOver(dist, total, speed, 1, m), speed, m);
  }

  /// How far along [route] its way round the platform's end begins (the
  /// gap between it and the brick yard).
  static double _toCorner(List<vm.Vector3> route) {
    var l = 0.0;
    for (var i = 0; i + 1 < route.length; i++) {
      if ((route[i].z - -0.6).abs() < 1e-6 || route[i].z > -0.6) return l;
      l += route[i].distanceTo(route[i + 1]);
    }
    return l;
  }

  static double _lengthOf(List<vm.Vector3> pts) {
    var l = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      l += pts[i].distanceTo(pts[i + 1]);
    }
    return l;
  }

  /// Poses everybody for [m]'s current job and draws them.
  ///
  /// [plan] is the build plan (null before the raster), [w] the wall width,
  /// [seat] and [seatYaw] the crane cab's seat, [impact] when the wrecking
  /// ball first hits (or null), [trip] how far the crane is through a trip
  /// (or -1), [night] 0 by day … 1 at night.
  void update(BoothModel m, BuildPlan? plan, {required double w, required vm.Vector3 seat, required double seatYaw, double? impact, double trip = -1, double night = 0}) {
    final j = m.job;
    final t = m.t;
    if (j == null) return;
    // A new name (its wall another width): the builders set off from where
    // the last one had them watching, the foreman from his corner then.
    if (!identical(j, _jobOf)) {
      _jobOf = j;
      _fromW = _lastW.isNaN ? w : _lastW;
    }
    _lastW = w;
    _night = night;
    _t = t;
    _figures.night = night;
    final since = j.since(t);
    final cut = j.cutAt != null;

    // Platform height (top of the deck) and its masts' offset.
    var deck = 0.0, sink = 0.0;
    switch (j.phase) {
      case Phase.intake:
        sink = -10 * (1 - eio(seg(since, 0.4, 2.8)));
      case Phase.build:
        deck = plan?.deckY(t) ?? 0;
      case Phase.reveal:
        // Down, and away once the crew have gone round to finish the front.
        final top = plan?.deckY(plan.t0 + plan.len) ?? 0;
        deck = top * (1 - eio(seg(since, 0, 1.4)));
        sink = -10 * eio(seg(since, 4.5, 6.7));
      case Phase.demolish:
        if (cut) {
          final top = plan?.deckY(j.phaseStart) ?? 0;
          deck = top * (1 - eio(seg(since, 0, 0.7)));
          sink = -10 * eio(seg(since, 3.4, 5.6));
        } else {
          sink = -10;
        }
      case Phase.celebrate || Phase.cleanup:
        sink = -10;
    }
    _gates = [for (var z = 0; z < builders; z++) plan?.restX(z) ?? _workSpot(z, w).x];
    _platform(w, deck, sink);
    final floor = math.max(0.0, deck + sink + SiteLayout.deckRest + 0.05);

    for (var z = 0; z < builders; z++) {
      final p = poses[z]..rest();
      final seed = z * 13;
      switch (j.phase) {
        case Phase.intake:
          // (Through the gap by the yard one after another, the farthest
          // going first: nobody catches anybody up. From where they were
          // watching the last name go.)
          final route = _route(z, w, toWall: true, watchW: _fromW);
          final start = j.phaseStart + 0.3 + z * 0.3 - (_toCorner(route) - _toCorner(_route(0, w, toWall: true, watchW: _fromW))) / 3.4;
          final (moving, heading) = _walk(route, start, 3.4, t, p.pos);
          p.pos.y = standY(p.pos, w, floor);
          if (moving) {
            _gait(p, (t - start) * 3.4, 3.4, seed, _lengthOf(route));
            p.yaw = heading;
          } else if (plan != null && t >= start) {
            // There: the plan has them from now (stepping over to their first
            // place as the build's about to start).
            _work(p, z, plan, t, floor, seed);
          } else {
            _idle(p, t, seed);
          }
        case Phase.build:
          if (plan == null) {
            p.pos.setFrom(_workSpot(z, w));
            _idle(p, t, seed);
          } else {
            _work(p, z, plan, t, floor, seed);
          }
        case Phase.reveal || Phase.celebrate || Phase.demolish || Phase.cleanup:
          final leave = j.phase == Phase.reveal
              ? j.phaseStart + 1.5 + (builders - 1 - z) * 0.12
              : (j.phase == Phase.demolish && cut ? j.phaseStart + 0.75 + (builders - 1 - z) * 0.08 : -1e9);
          final speed = cut ? 5.0 : 3.6;
          // Cut short: from wherever they were on the platform.
          final from = cut && plan != null && j.phase == Phase.demolish && j.phaseStart >= plan.t0 ? _fromCut(z, plan, j.phaseStart) : null;
          final route = _route(z, w, toWall: false, from: from);
          final (moving, heading) = _walk(route, leave, speed, t, p.pos);
          p.pos.y = standY(p.pos, w, floor);
          if (moving) {
            _gait(p, (t - leave) * speed, speed, seed, _lengthOf(route));
            p.yaw = heading;
          } else {
            _watch(p, z, j, t, impact, seed, w);
          }
      }
      if (plan != null) offDuty?.call(p, z, plan, t, floor);
      stage?.call(z, p);
      _draw(z);
    }
    _foremanPose(j, t, w, impact, trip, plan);
    _operatorPose(j, t, seat, seatYaw);
    // The others are posed by their own scenes (the driver by the delivery,
    // the makers by the works, the manager's party by the verdict).
    for (var i = foreman; i < count; i++) {
      stage?.call(i, poses[i]);
      _draw(i);
    }
  }


  /// Standing about, facing [face] (yaw; −z by default) give or take a
  /// turn now and then: breathing, the weight on one foot then the other,
  /// a look round (see [Idle]).
  void _idle(FigurePose p, double t, int seed, {double face = 0}) {
    final m = Manner.of(seed);
    p.yaw = face + Idle.facing(t, m);
    Idle.stand(p, t, m);
  }

  final _place = CrewPlace(), _cutPlace = CrewPlace();

  /// The job last seen, the wall's width last frame, and the width the
  /// builders stood watching for when this job started.
  Job? _jobOf;
  double _lastW = double.nan, _fromW = double.nan;

  /// Where builder [z] was at [at] (for a build cut short): on the
  /// platform, or at the finish.
  vm.Vector3 _fromCut(int z, BuildPlan plan, double at) {
    if (finishAt?.call(z, at) case final p?) return p;
    final c = plan.crewAt(z, at, _cutPlace);
    return vm.Vector3(c.x, 0, c.z);
  }

  /// Builder [z] in the build, wherever the plan has them: walking along
  /// the platform, laying their share of a letter, on the kerning crew or
  /// watching it, or waiting at their rest spot when not needed.
  void _work(FigurePose p, int z, BuildPlan plan, double t, double floor, int seed) {
    final c = plan.crewAt(z, t, _place);
    p.pos.setValues(c.x, floor, c.z);
    if (c.walking) {
      _gait(p, c.walked, c.walkSpeed, seed, c.walkLength);
      p.yaw = c.heading;
      return;
    }
    final st = c.letter >= 1 ? plan.steps[c.letter] : null;
    switch (c.mode) {
      case CrewMode.work:
        _lay(p, z, plan, t, floor, seed);
      case CrewMode.hook || CrewMode.holdCase:
        _tapePose(p, st!, plan, t, c.mode == CrewMode.hook, seed);
      case CrewMode.push:
        _pushPose(p, st!, plan, t, seed);
      case CrewMode.watch:
        _onlooker(p, t, seed, st);
      case CrewMode.free:
        _idle(p, t, seed);
        _akimbo(p);
    }
  }

  void _akimbo(FigurePose p) {
    p.armRoll[0] = p.armRoll[1] = 0.9;
    p.armPitch[0] = p.armPitch[1] = -0.3;
  }

  /// Turns [p] to face the point (x, z).
  void _face(FigurePose p, double x, double z) => p.yaw = math.atan2(-(x - p.pos.x), -(z - p.pos.z));

  /// The point [ahead] metres in front of [p], [right] to its right and [up]
  /// above its feet (world, into [out]).
  static vm.Vector3 _front(FigurePose p, double right, double up, double ahead, vm.Vector3 out) {
    final c = math.cos(p.yaw), s = math.sin(p.yaw);
    return out..setValues(p.pos.x + right * c - ahead * s, p.pos.y + up, p.pos.z - right * s - ahead * c);
  }

  /// Points arm [s] of [p] at [target] (as [aim]), [k] (0..1) of the way
  /// from where it was.
  void aimBy(FigurePose p, int s, vm.Vector3 target, double k, {double maxStoop = 0.7, double maxLean = 0.75}) {
    if (k <= 0) return;
    final pitch = p.armPitch[s], roll = p.armRoll[s], bend = p.elbow[s].isNaN ? 0.58 : p.elbow[s];
    final stoop = p.stoop, lean = p.lean;
    _aim(p, s, target, maxStoop: maxStoop, maxLean: maxLean);
    if (k >= 1) return;
    p.armPitch[s] = lerp(pitch, p.armPitch[s], k);
    p.armRoll[s] = lerp(roll, p.armRoll[s], k);
    p.elbow[s] = lerp(bend, p.elbow[s], k);
    // (Bending to it as far as reaching for it.)
    p.stoop = lerp(stoop, p.stoop, k);
    p.lean = lerp(lean, p.lean, k);
  }

  /// Points arm [s] of [p] towards [target] ([k] of it): the hand out
  /// towards it, the elbow easy, no higher than the chest.
  void point(FigurePose p, int s, vm.Vector3 target, [double k = 1]) {
    if (k <= 0) return;
    _rig.solve(p, arms: false);
    _rig.shoulder(s, 1, _sh);
    _d
      ..setFrom(target)
      ..sub(_sh);
    final l = _d.length;
    if (l < 1e-3) return;
    _hand
      ..setFrom(_d)
      ..scale(0.46 / l)
      ..add(_sh);
    _hand.y = math.min(_hand.y, _sh.y - 0.14);
    aimBy(p, s, _hand, k);
  }

  /// A step to the side while moving from [from] to [to] (x, along the
  /// wall; [f] of the way): the leading foot first, then the other one.
  static void _sideStep(FigurePose p, double from, double to, double f) {
    final d = to - from;
    if (d.abs() < 0.02 || f <= 0 || f >= 1) return;
    final lead = d > 0 ? 1 : 0, trail = 1 - lead, dir = d.sign;
    final body = lerp(from, to, eio(f));
    final a = seg(f, 0, 0.6), b = seg(f, 0.4, 1);
    p.footOut[lead] = (lerp(from, to, eio(a)) - body) * dir;
    p.footOut[trail] = -(lerp(from, to, eio(b)) - body) * dir;
    p.footLift[lead] = 0.05 * math.sin(math.pi * a);
    p.footLift[trail] = 0.05 * math.sin(math.pi * b);
  }

  final _hand = vm.Vector3.zero();

  /// Laying, in one rhythm: bending to the pile for the next brick while
  /// the last one's still flying, lifting it (hands on its top, then its
  /// sides) and coming up with it, tossing it onto the wall (the arms
  /// following it out and dropping back) as they step along to the next
  /// one's column. Every part of it eases into the next: no pops.
  void _lay(FigurePose p, int z, BuildPlan plan, double t, double floor, int seed) {
    final list = plan.zoneBricks[z];
    final x0 = p.pos.x;
    const fly = BuildPlan.flight, lift = BuildPlan.flight * BuildPlan.release;
    // The next brick to pick up (binary search by pick-up time); the one
    // before it is in their hands, or flying, or laid.
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (plan.layAt(list[mid]) - fly <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final next = lo < list.length ? list[lo] : null, prev = lo > 0 ? list[lo - 1] : null;
    final pickNext = next == null ? double.infinity : plan.layAt(next) - fly;
    final layPrev = prev == null ? -double.infinity : plan.layAt(prev), pickPrev = layPrev - fly;
    if (pickNext - t > 1.0 && t - layPrev > 0.15) {
      // Nothing coming yet, or done: hands on hips, watching the wall.
      _idle(p, t, seed);
      _akimbo(p);
      return;
    }
    // Along to each brick's column (a step towards it, from where they
    // stand), while the last one's tossed.
    double cell(int i) => plan.cellX[i] + plan.offsetAt(plan.letter[i], plan.layAt(i));
    double spot(int i) => x0 + (cell(i) - x0).clamp(-0.6, 0.6) * 0.45;
    var aim = cell(next ?? prev!);
    if (next != null && prev != null) {
      final from = spot(prev), to = spot(next);
      final f = seg(t, math.max(pickPrev + lift, pickNext - 0.6), pickNext - 0.03);
      p.pos.x = lerp(from, to, eio(f));
      _sideStep(p, from, to, f);
      aim = lerp(cell(prev), cell(next), eio(f));
    } else {
      p.pos.x = spot(next ?? prev!);
    }
    // Turned a little towards it, the shoulders more than the hips.
    final turn = (-(aim - p.pos.x) * 0.25).clamp(-0.45, 0.45);
    p.yaw = 0.35 * turn;
    p.twist = 0.65 * turn;
    final m = Manner.of(seed);
    Idle.breathe(p, t, m);
    // How far down: bending to the pile for the next, coming up with the
    // last; only as far as the brick is low (a full pile's top is at their
    // chest), and with the knees more than the back.
    final down = eio(seg(t, pickNext - 0.3, pickNext)), up = 1 - eio(c01((t - pickPrev) / lift));
    double depth(int i) {
      plan.pileSlot(plan.pileOf[i], plan.pile[i], floor - 0.05 - SiteLayout.deckRest, _tgt);
      return smooth(1.0, 0.3, _tgt.y - floor);
    }
    final low = math.max(next == null ? 0.0 : down * depth(next), prev == null ? 0.0 : up * depth(prev));
    p.lean = lerp(0.2, 0.42, low);
    p.bob = -0.36 * low;
    // The arms, at ease (as they drop back after a toss).
    for (var s = 0; s < 2; s++) {
      p.armPitch[s] = 0.1;
      p.armRoll[s] = 0.12;
      p.elbow[s] = 0.5;
    }
    final hb = plan.b / 2;
    final held = prev == null ? 1.0 : (t - pickPrev) / lift;
    if (held < 1) {
      // Holding it: on its top, then (clear of the pile) its sides.
      final pose = plan.brickAt(prev!, t, _pose);
      final g = smooth(0, 0.4, held);
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        _hand.setValues(pose.pos.x + side * lerp(0.55 * hb, hb + 0.03, g), pose.pos.y + (hb + 0.03) * (1 - g), pose.pos.z + 0.5 * hb * (1 - g));
        _aim(p, s, _hand, maxStoop: 0.2, maxLean: 0.55);
      }
      return;
    }
    if (prev != null && t < layPrev + 0.15) {
      // Let go: the hands follow it out a little, then drop back.
      final k = seg(t, pickPrev + lift, layPrev);
      plan.releaseOf(prev, _tgt);
      for (var s = 0; s < 2; s++) {
        _hand.setValues(_tgt.x + (s == 0 ? -1 : 1) * (hb + 0.03), _tgt.y + 0.06 * math.sin(math.pi * c01(k * 2)), _tgt.z - 0.08 * c01(k * 2));
        aimBy(p, s, _hand, 1 - smooth(0.3, 1, k), maxStoop: 0.2, maxLean: 0.55);
      }
    }
    if (next != null && down > 0) {
      // Down to the pile for the next: the hands to its top.
      plan.pileSlot(plan.pileOf[next], plan.pile[next], floor - 0.05 - SiteLayout.deckRest, _tgt);
      for (var s = 0; s < 2; s++) {
        _hand.setValues(_tgt.x + (s == 0 ? -0.55 : 0.55) * hb, _tgt.y + hb + 0.03, _tgt.z + 0.5 * hb);
        aimBy(p, s, _hand, smooth(0, 0.6, down), maxStoop: 0.2, maxLean: 0.55);
      }
    }
  }

  // ── Kerning ───────────────────────────────────────────────────────────────

  /// The tape: the hook builder runs it out of the case to the letter before
  /// and holds the hook there; the case holder keeps the case against the
  /// new letter's edge. Both nod when the foreman's happy.
  void _tapePose(FigurePose p, KernStep st, BuildPlan plan, double t, bool hook, int seed) {
    final y = st.tapeY, zt = plan.b * 0.5 + 0.035;
    _idle(p, t, seed);
    _face(p, (st.gapL + st.gapR + st.offset(t)) / 2, -0.8);
    p.lean = 0.22;
    if (hook) {
      if (t >= st.tapeA - 0.15 && t < st.tapB + 0.1) {
        // The hook in the near hand, the other on the hip.
        _tgt.setValues(Kern3D.hookAt(st, t), y + 0.02, zt);
        _aim(p, 1, _tgt);
        p.armPitch[0] = -0.3;
        p.armRoll[0] = 0.85;
      }
    } else if (t >= st.tapeA - 0.3) {
      final cx = st.gapR + st.offset(t) - 0.075;
      for (var s = 0; s < 2; s++) {
        _tgt.setValues(cx + (s == 0 ? -0.05 : 0.05), y, zt);
        _aim(p, s, _tgt);
      }
    }
    p.bob -= 0.035 * math.max(0, math.sin(seg(t, st.checkB - 0.6, st.checkB) * math.pi * 2));
  }

  /// Heaving the letter home: the pusher leans on its edge, hands flat on
  /// it, and walks it along as it slides; then gives it a couple of pats
  /// with one hand, and dusts their hands off.
  void _pushPose(FigurePose p, KernStep st, BuildPlan plan, double t, int seed) {
    final m = Manner.of(seed);
    final set = eio(seg(t, st.pushA - 0.7, st.pushA - 0.1));
    final done = seg(t, st.pushB, st.pushB + 0.35);
    final pushing = t >= st.pushA && t < st.pushB;
    if (pushing) {
      // Steps as far as the letter goes.
      final moved = st.slide - st.offset(t), speed = st.slide / math.max(0.2, st.pushB - st.pushA);
      Gait.walk(p, Gait.phaseOver(moved, math.max(st.slide, 0.05), math.max(speed, 0.2), 1, m), math.max(speed, 0.2), m);
    } else {
      Idle.stand(p, t, m, look: 0.2, shift: 0.3);
    }
    final ex = st.pushX + st.offset(t), zt = plan.b * 0.5;
    // Along the wall (towards −x), turned to the edge.
    _face(p, ex, zt - 0.06);
    p.lean = lerp(p.lean, 0.38, set * (1 - done));
    // Hands flat on the edge (palms just off it), towards its back.
    final on = set * (1 - seg(t, st.tapB, st.tapB + 0.25));
    final tap = Kern3D.tapAt(st);
    for (var s = 0; s < 2; s++) {
      final pat = s == 1 ? 0.07 * math.max(0.0, math.sin(seg(t, tap - 0.3, tap + 0.1) * math.pi * 2)) : 0.0;
      _hand.setValues(ex + 0.035 + pat, st.pushY + (s == 0 ? -0.07 : 0.07), zt - 0.06);
      aimBy(p, s, _hand, s == 0 ? on * (1 - seg(t, st.pushB, st.pushB + 0.2)) : on, maxStoop: 0.12);
    }
    if (t >= st.tapB) {
      // Done: dusting off the hands.
      final d = math.sin((t - st.tapB) * 18) * 0.03, k = 1 - seg(t, st.retractB, st.retractB + 0.3);
      for (var s = 0; s < 2; s++) {
        aimBy(p, s, _front(p, (s == 0 ? -1 : 1) * 0.04 + (s == 0 ? d : -d), 1.0, 0.28, _hand), k * smooth(st.tapB, st.tapB + 0.2, t));
      }
    }
  }

  /// Watching the wall, or the kerning crew at work (a clap at the tap).
  void _onlooker(FigurePose p, double t, int seed, KernStep? st) {
    _idle(p, t, seed);
    if (st == null || t < st.a || t >= st.e) {
      _akimbo(p);
      return;
    }
    _face(p, (st.gapL + st.gapR + st.offset(t)) / 2, 0);
    final tap = Kern3D.tapAt(st);
    Idle.clap(p, t, 2.6, seg(t, tap, tap + 0.2) * (1 - seg(t, tap + 1.0, tap + 1.3)), seed * 0.1);
  }

  // ── The foreman's rounds ──────────────────────────────────────────────────

  BuildPlan? _rounds;
  final _fT = <double>[], _fX = <double>[], _fZ = <double>[], _fWalk = <double>[];

  /// Where the foreman goes during [plan]: in front of each letter as it's
  /// laid, to the gap for its kerning, back to the corner at the end.
  void _planRounds(BuildPlan plan, double w) {
    _rounds = plan;
    _fT.clear();
    _fX.clear();
    _fZ.clear();
    _fWalk.clear();
    final sc = plan.sched;
    void go(double t, double x, double z) {
      _fT.add(t);
      _fX.add(x);
      _fZ.add(z);
    }

    for (var k = 0; k < plan.letterCount; k++) {
      final l = plan.letters.letters[k];
      final cx = ((l.col0 + l.col1 + 1) / 2 - plan.r.cols / 2) * plan.b + plan.slides[k];
      go(k == 0 ? plan.t0 - 3 : plan.at(sc.downB[k - 1]), cx + 1.4, -1.75);
      final st = plan.steps[k];
      // In front of the letter before, beside the gap (out of the close-up's
      // line of sight).
      if (st != null) go(st.a - 0.8, st.gapL - 1.15, -0.7);
    }
    go(plan.at(sc.downB[plan.letterCount - 1]), w / 2 + 0.75, -1.55);
    var px = w / 2 + 0.75, pz = -1.55;
    for (var q = 0; q < _fT.length; q++) {
      final d = math.sqrt((_fX[q] - px) * (_fX[q] - px) + (_fZ[q] - pz) * (_fZ[q] - pz));
      final room = q + 1 < _fT.length ? _fT[q + 1] - _fT[q] - 0.05 : 1e9;
      _fWalk.add(math.min(d / 2.4, math.max(0.05, room)));
      px = _fX[q];
      pz = _fZ[q];
    }
  }

  /// When the foreman's back at his corner after his rounds of [plan]'s
  /// build (the last letter down, and the walk back), wall [w] wide.
  double roundsDone(BuildPlan plan, double w) {
    if (!identical(plan, _rounds)) _planRounds(plan, w);
    return _fT.isEmpty ? double.negativeInfinity : _fT.last + _fWalk.last;
  }

  /// The foreman on his rounds during a build. Returns whether he's busy
  /// (walking or at a kerning), else he's standing by a letter.
  bool _rounding(FigurePose p, BuildPlan plan, double t, double w) {
    if (!identical(plan, _rounds)) _planRounds(plan, w);
    var q = _fT.length - 1;
    while (q >= 0 && _fT[q] > t) {
      q--;
    }
    if (q < 0) return false;
    final f = (t - _fT[q]) / _fWalk[q];
    if (f < 1) {
      final fx = q > 0 ? _fX[q - 1] : w / 2 + 0.75, fz = q > 0 ? _fZ[q - 1] : -1.55;
      final e = smooth(0, 1, f);
      p.pos.setValues(fx + (_fX[q] - fx) * e, 0, fz + (_fZ[q] - fz) * e);
      if ((_fX[q] - fx).abs() + (_fZ[q] - fz).abs() > 0.06) {
        final d = math.sqrt((_fX[q] - fx) * (_fX[q] - fx) + (_fZ[q] - fz) * (_fZ[q] - fz));
        _gait(p, d * e, d / _fWalk[q], 3, d);
        p.yaw = math.atan2(-(_fX[q] - fx), -(_fZ[q] - fz));
        // The clipboard under his arm.
        p.armPitch[0] = 1.0;
        p.armRoll[0] = 0.12;
        p.elbow[0] = double.nan;
        return true;
      }
    }
    p.pos.setValues(_fX[q], 0, _fZ[q]);
    final st = plan.stepAt(t + 0.8);
    if (st == null || t > st.e + 0.3) {
      // By the letter going up: facing it.
      _face(p, p.pos.x - 1.2, 0.4);
      return false;
    }
    // At the gap: watching the tape come out, checking his clipboard,
    // pointing; urging the push on; a thumbs up at the tap.
    _face(p, (st.gapL + st.gapR + st.offset(t)) / 2, 0.2);
    final check = seg(t, st.tapeB - 0.1, st.tapeB + 0.3) * (1 - seg(t, st.checkB - 0.55, st.checkB - 0.3));
    p.armPitch[0] = lerp(0.7, 1.4, check);
    p.lean = 0.12 + 0.18 * check;
    final point = seg(t, st.checkB - 0.55, st.checkB - 0.3) * (1 - seg(t, st.checkB + 0.1, st.checkB + 0.3));
    // A point at the gap.
    this.point(p, 1, _tgt..setValues((st.gapL + st.gapR + st.offset(t)) / 2, st.tapeY, 0), point);
    // A nod when it's home.
    final tap = Kern3D.tapAt(st);
    p.headPitch += 0.18 * math.sin(math.pi * seg(t, tap, tap + 0.5));
    return true;
  }

  final _pose = BrickPose();
  final _tgt = vm.Vector3.zero();

  /// Watching from the side: clapping at the celebration, flinching when
  /// the ball hits, then chatting.
  void _watch(FigurePose p, int z, Job j, double t, double? impact, int seed, double w) {
    // Face the middle of the wall.
    final face = math.atan2(p.pos.x, p.pos.z);
    switch (j.phase) {
      case Phase.reveal || Phase.celebrate:
        _idle(p, t, seed, face: face);
        // Clapping, each to their own beat, a happy bounce with it.
        final beat = t * (2.4 + 0.25 * (z % 3)) + seed;
        p.bob = -0.025 * (0.5 + 0.5 * math.sin(beat * 2 * math.pi));
        Idle.clap(p, t, 2.4 + 0.25 * (z % 3), 1, seed * 0.1);
      case Phase.demolish:
        _idle(p, t, seed, face: face);
        final hit = impact == null ? 1e9 : t - impact;
        if (hit > -0.2 && hit < 1.6) {
          // Flinch: back from it, the hands up in front.
          final f = c01((hit + 0.2) / 0.3) * (1 - seg(hit, 1.0, 1.6));
          p.lean = lerp(p.lean, -0.12, f);
          p.bob = -0.05 * f;
          for (var s = 0; s < 2; s++) {
            aimBy(p, s, _front(p, (s == 0 ? -1 : 1) * 0.16, 1.2, 0.28, _hand), f);
          }
        } else if (hit >= 1.6) {
          // Then a clap.
          Idle.clap(p, t, 2.2, seg(hit, 1.6, 1.9), seed * 0.1);
        } else {
          _akimbo(p);
        }
      case Phase.cleanup || Phase.intake || Phase.build:
        _idle(p, t, seed, face: face);
        if ((z + (t / 4).floor()) % 3 == 0) {
          // Chatting, a hand going with it.
          final u = t / 4 - (t / 4).floor(), k = smooth(0, 0.12, u) * (1 - smooth(0.85, 1, u));
          aimBy(p, 1, _front(p, 0.2, 1.02 + 0.04 * math.sin(t * 5 + seed), 0.3 + 0.04 * math.sin(t * 3.1 + seed), _hand), k);
        }
    }
  }

  void _foremanPose(Job j, double t, double w, double? impact, double trip, BuildPlan? plan) {
    final p = poses[foreman]..rest();
    p.clipboard = true;
    p.pos.setValues(w / 2 + 0.75, 0, -1.55);
    // A new name, its wall another width: over to the new corner.
    final from = _fromW.isNaN ? w : _fromW;
    if (j.phase == Phase.intake && (from - w).abs() > 0.05) {
      final d = (w - from).abs() / 2, a = j.phaseStart + 0.6, e = a + d / 1.4;
      if (t < e) {
        p.pos.x = lerp(from / 2 + 0.75, w / 2 + 0.75, c01((t - a) / (e - a)));
        if (t >= a) {
          _gait(p, (t - a) * 1.4, 1.4, 3, d);
          p.yaw = w > from ? -math.pi / 2 : math.pi / 2;
          p.armPitch[0] = 1.0;
          p.armRoll[0] = 0.12;
          p.elbow[0] = double.nan;
          return;
        }
      }
    }
    _idle(p, t, 3, face: math.atan2(-(0 - p.pos.x), -(0.4 - p.pos.z)) * 0.8);
    // Clipboard up, reading.
    p.armPitch[0] = 1.15;
    p.armRoll[0] = -0.15;
    p.lean = 0.12;
    switch (j.phase) {
      case Phase.intake || Phase.build:
        // Following the letters, kerning each one.
        if (plan != null && _rounding(p, plan, t, w)) break;
        if (trip >= 0 && trip < 0.22) {
          // Watching the crane bring it in, beckoning it on.
          p.yaw = 2.6;
          p.headPitch -= 0.35;
          final k = smooth(0, 0.03, trip) * (1 - smooth(0.19, 0.22, trip));
          aimBy(p, 1, _front(p, 0.22, 1.12, 0.3 + 0.07 * math.sin(t * 7), _hand), k);
        }
      case Phase.reveal || Phase.celebrate:
        // (Still on his way back to the corner from the last letter.)
        if (plan != null && identical(plan, _rounds) && _fT.isNotEmpty && t < _fT.last + _fWalk.last && _rounding(p, plan, t, w)) break;
        // Pleased: the clipboard tapped with the other hand.
        p.bob = -0.02 * (0.5 + 0.5 * math.sin(t * 3.1 * 2 * math.pi));
        final c = 0.5 + 0.5 * math.cos(t * 2.2 * 2 * math.pi);
        aimBy(p, 1, _front(p, 0.05 + 0.1 * c * c, 1.18, 0.34, _hand), 1);
      case Phase.demolish:
        final hit = impact == null ? 1e9 : t - impact;
        if (hit > -0.2 && hit < 1.4) {
          final f = c01((hit + 0.2) / 0.3) * (1 - seg(hit, 0.9, 1.4));
          p.lean = lerp(p.lean, -0.12, f);
          p.bob = -0.04 * f;
        }
      case Phase.cleanup:
        break;
    }
  }

  void _operatorPose(Job j, double t, vm.Vector3 seat, double yaw) {
    final p = poses[operator]..rest();
    p.pos.setFrom(seat);
    p.yaw = yaw;
    // On the seat (its hips a chair's height over the cab floor), the
    // knees bent: the feet on the floor, inside the cab.
    p.pos.y += 0.09;
    p.legPitch[0] = p.legPitch[1] = 1.45;
    p.armPitch[0] = 0.95 + 0.08 * math.sin(t * 3.1);
    p.armPitch[1] = 0.95 + 0.08 * math.sin(t * 2.3 + 1);
    p.armRoll[0] = p.armRoll[1] = 0.05;
    // Breathing; a look out of the cab now and then, mostly down at the
    // hook.
    final m = Manner.of(71);
    Idle.breathe(p, t, m);
    Idle.glance(p, t, m, look: 0.6);
    p.headPitch += 0.25;
  }

  // ── The platform ──────────────────────────────────────────────────────────

  void _platform(double w, double deck, double sink) {
    final y = deck + sink + SiteLayout.deckRest;
    final mx = w / 2 + 0.78;
    final z0 = SiteLayout.deckZ0, z1 = SiteLayout.deckZ1, zc = (z0 + z1) / 2, dz = z1 - z0;
    final visible = sink > -9.9;
    for (var i = 0; i < 2; i++) {
      _masts[i]
        ..visible = visible
        ..place((m) => setTrs(m, i == 0 ? -mx : mx, sink, zc));
    }
    var n = 0;
    void box(double x, double yy, double z, double sx, double sy, double sz, vm.Vector4 c) {
      if (n >= _deckParts) return;
      _deck.setInstanceTransform(n, visible ? setTqs(_m, x, yy, z, _qi, sx, sy, sz) : hidden);
      _deck.setInstanceColor(n, c);
      n++;
    }

    final wood = _wood, rail = _rail, dark = _dark, motor = _motor;
    final half = w / 2 + 1.05;
    // Deck planks (three boards).
    for (var k = 0; k < 3; k++) {
      box(0, y - 0.05, z0 + dz * (k + 0.5) / 3, half * 2, 0.1, dz / 3 - 0.03, k.isEven ? wood : _wood2);
    }
    // Along the back, between the gates: the toe board, the guard rail (top
    // and middle), a post at each end of a run and between.
    for (final (a, b) in _backRuns(half)) {
      final c = (a + b) / 2, l = b - a;
      box(c, y + 0.08, z1 - 0.03, l, 0.16, 0.04, dark);
      for (final h in [0.55, 1.05]) {
        box(c, y + h, z1 - 0.03, l, 0.05, 0.05, rail);
      }
      final posts = math.max(1, (l / 1.6).ceil());
      for (var k = 0; k <= posts; k++) {
        box(a + l * k / posts, y + 0.53, z1 - 0.03, 0.06, 1.06, 0.06, rail);
      }
    }
    // The ends' rails.
    for (final h in [0.55, 1.05]) {
      for (final sx in [-1.0, 1.0]) {
        box(sx * half, y + h, zc, 0.05, 0.05, dz, rail);
      }
    }
    for (final sx in [-1.0, 1.0]) {
      box(sx * half, y + 0.53, z0 + 0.05, 0.06, 1.06, 0.06, rail);
      // Climbing gear on the masts.
      box(sx * mx, y + 0.28, zc, 0.62, 0.46, 0.66, motor);
    }
    for (; n < _deckParts; n++) {
      _deck.setInstanceTransform(n, hidden);
    }
    // Solid: its ends, the masts and their gear, the back between the
    // gates.
    _figures.solids['platform'] = [
      if (visible) ...[
        for (final sx in [-1.0, 1.0]) ...[
          (vm.Vector3(sx * half, y + 0.6, zc), vm.Vector3(0.04, 0.6, dz / 2)),
          (vm.Vector3(sx * mx, y + 0.28, zc), vm.Vector3(0.31, 0.23, 0.33)),
          (vm.Vector3(sx * mx, sink + 4.8, zc), vm.Vector3(0.21, 4.8, 0.21)),
        ],
        for (final (a, b) in _backRuns(half)) (vm.Vector3((a + b) / 2, y + 0.6, z1 - 0.03), vm.Vector3((b - a) / 2, 0.6, 0.04)),
      ],
    ];
    // Festoon bulbs along the back rail, glowing after dark.
    final count = math.min(_maxBulbs, (half * 2 / 0.62).floor());
    final glow = 0.4 + 7 * c01((_night - 0.1) / 0.4);
    for (var k = 0; k < _maxBulbs; k++) {
      if (!visible || k >= count) {
        _bulbs.setInstanceTransform(k, hidden);
        continue;
      }
      final x = -half + (k + 0.5) * half * 2 / count;
      // (None over a gate: whoever goes through would walk into it.)
      if (_gates.any((g) => (x - g).abs() < gateHalf + 0.06)) {
        _bulbs.setInstanceTransform(k, hidden);
        continue;
      }
      final sag = 0.07 * math.sin(((k % 4) + 0.5) / 4 * math.pi);
      _bulbs.setInstanceTransform(k, setTrs(_m, x, y + 1.13 - sag, z1 - 0.03));
      final c = _bulbColors[k % _bulbColors.length];
      final tw = 0.85 + 0.15 * math.sin(_t * 3 + k * 1.7);
      _bulbs.setInstanceColor(k, vm.Vector4(c.x * glow * tw, c.y * glow * tw, c.z * glow * tw, 1));
    }
  }

  /// The back rail's runs between the gates (x from, to), the platform
  /// [half] wide each side.
  List<(double, double)> _backRuns(double half) {
    final runs = <(double, double)>[];
    var from = -half;
    for (final g in [..._gates]..sort()) {
      final a = g - gateHalf, b = g + gateHalf;
      if (a - from > 0.1) runs.add((from, a));
      from = math.max(from, b);
    }
    if (half - from > 0.1) runs.add((from, half));
    return runs;
  }

  double _t = 0;
  static final _bulbColors = [lin(BP.amber), lin(const Color(0xFFFFF1D6)), lin(BP.coral), lin(const Color(0xFFFFF1D6))];

  static final _qi = vm.Quaternion.identity();
  static final _wood = lin(const Color(0xFF9C6B3C)), _wood2 = lin(const Color(0xFF8A5C32));
  static final _rail = lin(const Color(0xFFFFC23D)), _dark = lin(const Color(0xFF1A2230)), _motor = lin(const Color(0xFF2E6DA8));
}
