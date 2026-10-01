import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_geo.dart';
import 'site_kern.dart';
import 'site_plan.dart';

/// One figure's pose: where it stands, which way it faces (yaw 0 = towards
/// −z, the camera side), and its joints.
class FigurePose {
  final pos = vm.Vector3.zero();
  double yaw = 0;

  /// Torso pitch forward (radians) and a vertical bob.
  double lean = 0, bob = 0;

  /// Per side (0 = −x, 1 = +x): arm pitch (0 down, π/2 forward, π up) and
  /// roll (outwards), leg pitch (forward swing).
  final armPitch = [0.0, 0.0], armRoll = [0.0, 0.0], legPitch = [0.0, 0.0];
  bool visible = true;
  bool clipboard = false;

  /// The hard hat tossed in the air: how high above the head, and its spin.
  double hatUp = 0, hatSpin = 0;

  void rest() {
    hatUp = 0;
    hatSpin = 0;
    lean = 0;
    bob = 0;
    armPitch[0] = armPitch[1] = 0.08;
    armRoll[0] = armRoll[1] = 0.12;
    legPitch[0] = legPitch[1] = 0;
    clipboard = false;
    visible = true;
  }
}

/// The site crew: six builders (one per stretch of wall, zone colours on
/// their vests), the foreman with his clipboard, and the crane operator in
/// the cab. Stylised figures (capsule body, sphere head, hard hat) drawn
/// instanced, one draw per body part. Also the climbing platform the
/// builders work on: two lattice masts and a deck that rises with the wall.
///
/// The name goes up a letter at a time: its team lays it (a handful of
/// bricks a swing), then two of them stretch the tape across the gap while
/// the foreman checks his clipboard, and they heave the letter into place.
/// Where everyone is comes from the plan ([BuildPlan.crewAt]).
class Crew3D {
  Crew3D(this.scene);

  final Scene scene;

  static const builders = NameRaster.zones, foreman = builders, operator = builders + 1, count = builders + 2;

  /// One vest colour per zone, as on the 2D booth's hard hats.
  static const vests = [BP.amber, BP.coral, BP.green, BP.violet, BP.pink, BP.line];

  final poses = List.generate(count, (_) => FigurePose()..rest());

  late final InstancedMesh _torso, _head, _hat, _brim, _arm, _leg, _hand, _eye, _board;
  late final InstancedMesh _deck, _bulbs;
  final _masts = <Node>[];
  static const _maxBulbs = 44;
  double _night = 0;

  void init() {
    final cloth = pbr(rgb(1, 1, 1), roughness: 0.75);
    final skin = pbr(rgb(1, 1, 1), roughness: 0.6);
    final hard = pbr(rgb(1, 1, 1), roughness: 0.32, metallic: 0.05);
    InstancedMesh im(Geometry g, Material m, int n, String name) {
      final mesh = InstancedMesh(geometry: g, material: m);
      for (var i = 0; i < n; i++) {
        mesh.addInstance(hidden);
      }
      scene.add(Node(name: name)..addComponent(InstancedMeshComponent(mesh)));
      return mesh;
    }

    _torso = im(CapsuleGeometry(radius: 0.155, height: 0.27, radialSegments: 14, capRings: 5), cloth, count, 'crew torsos');
    _head = im(SphereGeometry(radius: 0.14, segments: 14, rings: 10), skin, count, 'crew heads');
    _hat = im(domeGeometry(radius: 0.168, segments: 16, rings: 5), hard, count, 'crew hats');
    _brim = im(CylinderGeometry(bottomRadius: 0.205, topRadius: 0.205, height: 0.022, radialSegments: 16), hard, count, 'crew hat brims');
    _arm = im(CapsuleGeometry(radius: 0.05, height: 0.24, radialSegments: 8, capRings: 3), cloth, count * 2, 'crew arms');
    _leg = im(CapsuleGeometry(radius: 0.064, height: 0.2, radialSegments: 8, capRings: 3), cloth, count * 2, 'crew legs');
    _hand = im(SphereGeometry(radius: 0.058, segments: 8, rings: 6), skin, count * 2, 'crew hands');
    _eye = im(SphereGeometry(radius: 0.021, segments: 6, rings: 4), pbr(rgb(0.02, 0.02, 0.03), roughness: 0.3), count * 2, 'crew eyes');
    _board = im(CuboidGeometry(vm.Vector3(0.2, 0.27, 0.025)), pbr(lin(const Color(0xFFF4F1EA)), roughness: 0.8), 1, 'clipboard');
    const skins = [Color(0xFFF1C9A5), Color(0xFFC68E63), Color(0xFF8D5A3B), Color(0xFFE8B98F), Color(0xFFAF7550), Color(0xFFF6D3B5), Color(0xFFD9A47C), Color(0xFF9C6B47)];
    const pants = Color(0xFF243650);
    for (var i = 0; i < count; i++) {
      final vest = i < builders ? vests[i] : (i == foreman ? const Color(0xFFF4F1EA) : const Color(0xFFFF8A3D));
      final hat = i == foreman ? const Color(0xFFFFFFFF) : const Color(0xFFFFD43B);
      _torso.setInstanceColor(i, lin(vest));
      _head.setInstanceColor(i, lin(skins[i % skins.length]));
      _hat.setInstanceColor(i, lin(hat));
      _brim.setInstanceColor(i, lin(hat));
      for (var s = 0; s < 2; s++) {
        _arm.setInstanceColor(2 * i + s, lin(vest));
        _leg.setInstanceColor(2 * i + s, lin(pants));
        _hand.setInstanceColor(2 * i + s, lin(skins[i % skins.length]));
      }
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

  static const _deckParts = 40;

  // ── Drawing ───────────────────────────────────────────────────────────────

  final _root = vm.Matrix4.identity(), _torsoM = vm.Matrix4.identity(), _m = vm.Matrix4.identity();
  final _l = vm.Matrix4.identity(), _arm0 = vm.Matrix4.identity();
  final _rz = vm.Matrix4.identity(), _rx = vm.Matrix4.identity();

  void _draw(int i) {
    final p = poses[i];
    if (!p.visible) {
      for (final im in [_torso, _head, _hat, _brim]) {
        im.setInstanceTransform(i, hidden);
      }
      for (var s = 0; s < 2; s++) {
        for (final im in [_arm, _leg, _hand, _eye]) {
          im.setInstanceTransform(2 * i + s, hidden);
        }
      }
      return;
    }
    setTrs(_root, p.pos.x, p.pos.y + p.bob, p.pos.z, yaw: p.yaw);
    // Legs from the hips.
    for (var s = 0; s < 2; s++) {
      final side = s == 0 ? -1.0 : 1.0;
      _m
        ..setFrom(_root)
        ..multiply(setTrs(_l, side * 0.085, 0.36, 0, pitch: p.legPitch[s]))
        ..multiply(setTrs(_l, 0, -0.165, 0));
      _leg.setInstanceTransform(2 * i + s, _m);
    }
    // Torso (leans forward = towards local −z).
    _torsoM
      ..setFrom(_root)
      ..multiply(setTrs(_l, 0, 0.36, 0, pitch: -p.lean));
    _torso.setInstanceTransform(
      i,
      _m
        ..setFrom(_torsoM)
        ..multiply(setTrs(_l, 0, 0.29, 0)),
    );
    _head.setInstanceTransform(
      i,
      _m
        ..setFrom(_torsoM)
        ..multiply(setTrs(_l, 0, 0.72, 0)),
    );
    _hat.setInstanceTransform(
      i,
      _m
        ..setFrom(_torsoM)
        ..multiply(setTrs(_l, 0, 0.752 + p.hatUp, 0.004, yaw: p.hatSpin, roll: 0.3 * math.sin(p.hatSpin))),
    );
    _brim.setInstanceTransform(
      i,
      _m
        ..setFrom(_torsoM)
        ..multiply(setTrs(_l, 0, 0.755 + p.hatUp, -0.03, yaw: p.hatSpin, pitch: -0.08, roll: 0.3 * math.sin(p.hatSpin))),
    );
    for (var s = 0; s < 2; s++) {
      final side = s == 0 ? -1.0 : 1.0;
      _eye.setInstanceTransform(
        2 * i + s,
        _m
          ..setFrom(_torsoM)
          ..multiply(setTrs(_l, side * 0.05, 0.738, -0.126)),
      );
      // Arm: shoulder, roll outwards (z), pitch forward (x).
      _rz.setRotationZ(side * p.armRoll[s]);
      _rx.setRotationX(p.armPitch[s]);
      _arm0
        ..setFrom(_torsoM)
        ..multiply(setTrs(_l, side * 0.205, 0.5, 0))
        ..multiply(_rz)
        ..multiply(_rx);
      _arm.setInstanceTransform(
        2 * i + s,
        _m
          ..setFrom(_arm0)
          ..multiply(setTrs(_l, 0, -0.17, 0)),
      );
      _hand.setInstanceTransform(
        2 * i + s,
        _m
          ..setFrom(_arm0)
          ..multiply(setTrs(_l, 0, -0.36, 0)),
      );
      if (p.clipboard && s == 0) {
        _board.setInstanceTransform(
          0,
          _m
            ..setFrom(_arm0)
            ..multiply(setTrs(_l, 0.02, -0.4, -0.06, pitch: 0.6)),
        );
      }
    }
    if (i == foreman && !p.clipboard) _board.setInstanceTransform(0, hidden);
  }

  final _sh = vm.Vector3.zero(), _d = vm.Vector3.zero();

  /// Points arm [s] of [p] at [target] (world).
  void _aim(FigurePose p, int s, vm.Vector3 target) {
    final side = s == 0 ? -1.0 : 1.0;
    // Shoulder in world space and the torso's rotation (yaw, then lean).
    final cy = math.cos(p.yaw), sy = math.sin(p.yaw);
    final cl = math.cos(-p.lean), sl = math.sin(-p.lean);
    // Local shoulder offset from the hip: (side·0.205, 0.5, 0) under Rx(-lean).
    final lx = side * 0.205, ly = 0.5 * cl, lz = 0.5 * sl;
    _sh.setValues(p.pos.x + lx * cy + lz * sy, p.pos.y + p.bob + 0.36 + ly, p.pos.z - lx * sy + lz * cy);
    _d
      ..setFrom(target)
      ..sub(_sh);
    if (_d.length2 < 1e-6) return;
    _d.normalize();
    // Into the torso frame: undo yaw, then undo the lean.
    final x1 = _d.x * cy - _d.z * sy, z1 = _d.x * sy + _d.z * cy, y1 = _d.y;
    final y2 = y1 * cl + z1 * sl, z2 = -y1 * sl + z1 * cl;
    final pitch = math.asin((-z2).clamp(-1.0, 1.0));
    final roll = math.atan2(x1, -y2);
    p.armPitch[s] = pitch;
    p.armRoll[s] = side * roll;
  }

  // ── Behaviour ─────────────────────────────────────────────────────────────

  /// Where builder [z] stands to work at the start of a build of width [w].
  vm.Vector3 _workSpot(int z, double w) => vm.Vector3(((z + 0.5) / builders - 0.5) * w, 0, SiteLayout.crewZ);

  /// Where builder [z] watches from (front right of the wall).
  vm.Vector3 _watchSpot(int z, double w) => vm.Vector3(w / 2 + 1.5 + (z % 3) * 0.8 + (z ~/ 3) * 0.4, 0, -0.9 - (z ~/ 3) * 0.85);

  /// Around the right end of the wall, between the platform and the front
  /// (from or to [from] on the platform, else their rest spot).
  List<vm.Vector3> _route(int z, double w, {required bool toWall, vm.Vector3? from}) {
    final work = from ?? _workSpot(z, w), watch = _watchSpot(z, w);
    final corner = vm.Vector3(w / 2 + 1.25, 0, SiteLayout.crewZ);
    final pts = [work, corner, vm.Vector3(w / 2 + 1.35, 0, -0.5), watch];
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

  void _gait(FigurePose p, double t, double speed, int seed) {
    final ph = t * speed * 4.2 + seed;
    final sw = math.sin(ph) * 0.55;
    p.legPitch[0] = sw;
    p.legPitch[1] = -sw;
    p.armPitch[0] = -sw * 0.8;
    p.armPitch[1] = sw * 0.8;
    p.armRoll[0] = p.armRoll[1] = 0.1;
    p.bob = 0.03 * math.cos(ph * 2).abs();
    p.lean = 0.08;
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
    _night = night;
    _t = t;
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
        final top = plan?.deckY(plan.t0 + plan.len) ?? 0;
        deck = top * (1 - eio(seg(since, 0, 1.4)));
        sink = -10 * eio(seg(since, 3.6, 5.8));
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
    _platform(w, deck, sink);
    final floor = math.max(0.0, deck + sink + 0.05);

    for (var z = 0; z < builders; z++) {
      final p = poses[z]..rest();
      final seed = z * 13;
      switch (j.phase) {
        case Phase.intake:
          final (moving, heading) = _walk(_route(z, w, toWall: true), j.phaseStart + 0.3 + z * 0.18, 3.4, t, p.pos);
          p.pos.y = _onDeck(p.pos, w) ? floor : 0;
          if (moving) {
            _gait(p, t, 3.4, seed);
            p.yaw = heading;
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
          final (moving, heading) = _walk(_route(z, w, toWall: false, from: from), leave, speed, t, p.pos);
          p.pos.y = _onDeck(p.pos, w) ? floor : 0;
          if (moving) {
            _gait(p, t, speed, seed);
            p.yaw = heading;
          } else {
            _watch(p, z, j, t, impact, seed, w);
          }
      }
      _draw(z);
    }
    _foremanPose(j, t, w, impact, trip, plan);
    _draw(foreman);
    _operatorPose(j, t, seat, seatYaw);
    _draw(operator);
  }

  bool _onDeck(vm.Vector3 p, double w) => p.z > SiteLayout.deckZ0 && p.z < SiteLayout.deckZ1 && p.x.abs() < w / 2 + 1.0;

  void _idle(FigurePose p, double t, int seed) {
    p.yaw = 0.25 * math.sin(t * 0.5 + seed);
    p.bob = 0.008 * math.sin(t * 2 + seed);
    p.armPitch[0] = 0.15 + 0.05 * math.sin(t + seed);
    p.armPitch[1] = 0.12;
  }

  final _place = CrewPlace(), _cutPlace = CrewPlace();

  /// Where builder [z] was on the platform at [at] (for a build cut short).
  vm.Vector3 _fromCut(int z, BuildPlan plan, double at) {
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
      _gait(p, t, 2.4, seed);
      p.yaw = c.heading;
      return;
    }
    final st = c.letter >= 1 ? plan.steps[c.letter] : null;
    switch (c.mode) {
      case CrewMode.work:
        _lay(p, z, plan, t, floor, seed);
      case CrewMode.hook || CrewMode.holdCase:
        _tapePose(p, st!, plan, t, c.mode == CrewMode.hook, seed);
      case CrewMode.push1 || CrewMode.push2:
        _pushPose(p, st!, plan, t, floor, c.mode == CrewMode.push1, seed);
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

  /// Laying: steps along to the next handful, takes it off the pile in
  /// front, swings it up onto the wall, pats it down.
  void _lay(FigurePose p, int z, BuildPlan plan, double t, double floor, int seed) {
    final list = plan.zoneBricks[z];
    final x0 = p.pos.x;
    // The next brick this builder handles (binary search by lay time).
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (plan.layAt(list[mid]) < t - 0.15) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo >= list.length || plan.layAt(list[lo]) > t + 1.5) {
      // Nothing coming yet, or done: hands on hips, watching the wall.
      _idle(p, t, seed);
      _akimbo(p);
      _catch(p, z, plan, t);
      return;
    }
    // A step towards each brick's column, from where they stand.
    double cell(int i) => plan.cellX[i] + plan.offsetAt(plan.letter[i], plan.layAt(i));
    double spot(int q) => x0 + (cell(list[q.clamp(0, list.length - 1)]) - x0).clamp(-0.6, 0.6) * 0.45;
    final i = list[lo];
    final lay = plan.layAt(i);
    final prevLay = lo > 0 ? plan.layAt(list[lo - 1]) : lay - 1.0;
    final f = seg(t, prevLay + 0.05, math.max(prevLay + 0.1, lay - BuildPlan.flight - 0.05));
    p.pos.x = lerp(spot(lo - 1), spot(lo), eio(f));
    final stepping = f > 0 && f < 1 && (spot(lo) - spot(lo - 1)).abs() > 0.05;
    if (stepping) {
      final ph = f * math.pi * 2;
      p.legPitch[0] = 0.35 * math.sin(ph);
      p.legPitch[1] = -0.35 * math.sin(ph);
    }
    final wait = lay - BuildPlan.flight - t; // > 0: not yet picked up
    final pose = plan.brickAt(i, t, _pose);
    if (wait > 0) {
      // Bending to the pile for the next handful.
      final bend = 1 - c01(wait / 0.35);
      p.lean = 0.15 + 0.55 * eio(bend);
      p.bob = -0.08 * eio(bend);
      for (var s = 0; s < 2; s++) {
        plan.pileSlot(plan.pileOf[i], plan.pile[i], floor - 0.05, _tgt);
        _tgt.x += s == 0 ? -0.08 : 0.08;
        _aim(p, s, _tgt);
      }
      // Blend from the follow-through of the last swing.
      for (var s = 0; s < 2; s++) {
        p.armPitch[s] = lerp(1.9, p.armPitch[s], eio(c01(bend * 1.6)));
      }
    } else {
      final fl = c01((t - (lay - BuildPlan.flight)) / BuildPlan.flight);
      // Up from the bend, reaching out over the wall.
      p.lean = lerp(0.7, 0.32, eio(c01(fl * 2)));
      p.bob = -0.08 * (1 - eio(c01(fl * 2)));
      final hold = fl < 0.5;
      for (var s = 0; s < 2; s++) {
        if (hold) {
          _tgt
            ..setFrom(pose.pos)
            ..x += (s == 0 ? -0.09 : 0.09);
        } else {
          _tgt.setValues(cell(i) + (s == 0 ? -0.12 : 0.12), plan.cellY[i] + 0.1, 0);
        }
        _aim(p, s, _tgt);
      }
      if (t >= lay) {
        // Pat it down.
        final pat = math.sin((t - lay) * 30) * 0.12 * (1 - c01((t - lay) / 0.2));
        p.armPitch[0] += pat;
        p.armPitch[1] -= pat;
      }
    }
    p.yaw = (-(cell(i) - p.pos.x) * 0.25).clamp(-0.5, 0.5);
    _catch(p, z, plan, t);
  }

  /// When the crane pours this builder's batch onto the pile in front, they
  /// look up and reach for it.
  void _catch(FigurePose p, int z, BuildPlan plan, double t) {
    final at = plan.tripAt(t);
    if (at == null) return;
    final drop = plan.dropFor(z, at.$1, t);
    if (drop == null) return;
    final w = math.sin(math.pi * c01((t - drop + 0.35) / 1.4));
    if (w <= 0) return;
    final hook = plan.hookPath(t);
    for (var s = 0; s < 2; s++) {
      final pitch = p.armPitch[s], roll = p.armRoll[s];
      _tgt
        ..setFrom(hook)
        ..x += s == 0 ? -0.3 : 0.3;
      _aim(p, s, _tgt);
      p.armPitch[s] = lerp(pitch, p.armPitch[s], w);
      p.armRoll[s] = lerp(roll, p.armRoll[s], w);
    }
    p.lean = lerp(p.lean, -0.15, w);
    p.bob = lerp(p.bob, 0.02, w);
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
        final hx = Kern3D.hookAt(st, t);
        _tgt.setValues(hx, y + 0.02, zt);
        _aim(p, 1, _tgt);
        _tgt.setValues(hx - 0.08, y - 0.04, zt + 0.04);
        _aim(p, 0, _tgt);
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

  /// Heaving the letter home: the first in line leans on its edge, the
  /// second on the first one's back, legs driving while it slides; then the
  /// first gives it a final tap.
  void _pushPose(FigurePose p, KernStep st, BuildPlan plan, double t, double floor, bool first, int seed) {
    p.yaw = math.pi / 2; // along the wall, towards −x
    final set = eio(seg(t, st.pushA - 0.7, st.pushA - 0.1));
    final done = seg(t, st.pushB, st.pushB + 0.35);
    p.lean = 0.1 + 0.5 * set * (1 - done);
    if (first) {
      final ex = st.pushX + st.offset(t);
      for (var s = 0; s < 2; s++) {
        _tgt.setValues(ex + 0.02, st.pushY + (s == 0 ? -0.06 : 0.08), plan.b * 0.5 + 0.03);
        _aim(p, s, _tgt);
      }
    } else {
      final fx = st.pushX + 0.42 + st.offset(t);
      for (var s = 0; s < 2; s++) {
        _tgt.setValues(fx + 0.12, floor + 0.78, SiteLayout.kernZ + (s == 0 ? 0.1 : -0.1));
        _aim(p, s, _tgt);
      }
    }
    if (t >= st.pushA - 0.1 && t < st.pushB + 0.05) {
      // Short, hard steps.
      final ph = t * 8 + seed;
      p.legPitch[0] = 0.45 * math.sin(ph) - 0.3;
      p.legPitch[1] = -0.45 * math.sin(ph) - 0.3;
      p.bob = 0.025 * math.cos(ph * 2).abs() - 0.05;
    }
    if (first) {
      // The tap: up, and down on the edge.
      final tap = Kern3D.tapAt(st);
      final k = t < tap - 0.08 ? eio(seg(t, tap - 0.32, tap - 0.08)) : 1 - eio(seg(t, tap - 0.08, tap));
      p.armPitch[1] = lerp(p.armPitch[1], 2.7, k);
    }
    if (t >= st.tapB) {
      // Done: dusting off the hands.
      final d = math.sin((t - st.tapB) * 18) * 0.25 * (1 - seg(t, st.tapB, st.retractB + 0.2));
      p.armPitch[0] = 0.9 + d;
      p.armPitch[1] = 0.9 - d;
      p.armRoll[0] = p.armRoll[1] = -0.35;
    }
  }

  /// Watching the wall, or the kerning crew at work (a cheer at the tap).
  void _onlooker(FigurePose p, double t, int seed, KernStep? st) {
    _idle(p, t, seed);
    if (st == null || t < st.a || t >= st.e) {
      _akimbo(p);
      return;
    }
    _face(p, (st.gapL + st.gapR + st.offset(t)) / 2, 0);
    final tap = Kern3D.tapAt(st);
    final cheer = seg(t, tap, tap + 0.2) * (1 - seg(t, tap + 0.7, tap + 1.0));
    p.armPitch[1] = lerp(p.armPitch[1], 2.6, cheer);
    p.armRoll[1] = lerp(p.armRoll[1], 0.3, cheer);
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
      if (st != null) go(st.a - 0.8, st.gapL - 0.85, -0.8);
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
        _gait(p, t, 2.4, 3);
        p.yaw = math.atan2(-(_fX[q] - fx), -(_fZ[q] - fz));
        p.armPitch[0] = 1.0; // the clipboard under his arm
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
    if (point > 0) {
      _tgt.setValues((st.gapL + st.gapR + st.offset(t)) / 2, st.tapeY, 0);
      _aim(p, 1, _tgt);
      p.armPitch[1] *= point;
      p.bob = -0.03 * math.sin(point * math.pi * 2);
    }
    if (t >= st.checkB + 0.2 && t < st.pushB) {
      p.armPitch[1] = 1.25 + 0.35 * math.sin(t * 9);
      p.armRoll[1] = -0.2;
    }
    final thumbs = seg(t, Kern3D.tapAt(st), Kern3D.tapAt(st) + 0.2);
    if (thumbs > 0) {
      p.armPitch[1] = lerp(p.armPitch[1], 2.75, thumbs);
      p.armRoll[1] = lerp(p.armRoll[1], 0.25, thumbs);
    }
    return true;
  }

  final _pose = BrickPose();
  final _tgt = vm.Vector3.zero();

  /// Watching from the side: cheering at the celebration, ducking when the
  /// ball hits, then chatting.
  void _watch(FigurePose p, int z, Job j, double t, double? impact, int seed, double w) {
    // Face the middle of the wall.
    p.yaw = math.atan2(p.pos.x, p.pos.z);
    switch (j.phase) {
      case Phase.reveal || Phase.celebrate:
        // Hats in the air!
        if (j.phase == Phase.celebrate) {
          final f = (j.since(t) - 0.6 - z * 0.17) / 1.15;
          if (f > 0 && f < 1) {
            p.hatUp = 2.2 * 4 * f * (1 - f);
            p.hatSpin = f * math.pi * 4;
          }
        }
        // Jump and wave, each to their own beat.
        final beat = t * (2.6 + 0.3 * (z % 3)) + seed;
        final jump = math.max(0.0, math.sin(beat));
        p.bob = 0.22 * jump * jump;
        p.legPitch[0] = -0.25 * jump;
        p.legPitch[1] = 0.25 * jump;
        p.armPitch[0] = math.pi * 0.85 + 0.2 * math.sin(beat * 2);
        p.armPitch[1] = math.pi * 0.85 - 0.2 * math.sin(beat * 2 + 1);
        p.armRoll[0] = 0.35 + 0.25 * math.sin(beat * 2);
        p.armRoll[1] = 0.35 + 0.25 * math.cos(beat * 2);
      case Phase.demolish:
        final hit = impact == null ? 1e9 : t - impact;
        if (hit > -0.2 && hit < 1.6) {
          // Flinch: a hop back, hands up to the hard hat.
          final f = c01((hit + 0.2) / 0.3);
          p.bob = 0.12 * math.sin(c01(hit / 0.5) * math.pi);
          p.pos.z -= 0.25 * eo(f);
          p.lean = -0.25 * f;
          p.armPitch[0] = p.armPitch[1] = 2.6 * f;
          p.armRoll[0] = p.armRoll[1] = 0.55 * f;
        } else if (hit >= 1.6) {
          // Then a happy little cheer.
          final beat = t * 3 + seed;
          p.armPitch[0] = 2.4 + 0.3 * math.sin(beat);
          p.armRoll[0] = 0.4;
          p.bob = 0.06 * math.max(0, math.sin(beat));
        } else {
          _idle(p, t, seed);
          p.armRoll[0] = p.armRoll[1] = 0.9;
          p.armPitch[0] = p.armPitch[1] = -0.3;
        }
      case Phase.cleanup || Phase.intake || Phase.build:
        _idle(p, t, seed);
        p.yaw += 0.4 * math.sin(t * 0.7 + seed);
        if ((z + (t / 4).floor()) % 3 == 0) {
          // Chatting with a gesture.
          p.armPitch[1] = 1.2 + 0.3 * math.sin(t * 5 + seed);
          p.armRoll[1] = 0.3;
        }
    }
  }

  void _foremanPose(Job j, double t, double w, double? impact, double trip, BuildPlan? plan) {
    final p = poses[foreman]..rest();
    p.clipboard = true;
    p.pos.setValues(w / 2 + 0.75, 0, -1.55);
    p.yaw = math.atan2(-(0 - p.pos.x), -(0.4 - p.pos.z)) * 0.8;
    _idle(p, t, 3);
    // Clipboard up, reading.
    p.armPitch[0] = 1.15;
    p.armRoll[0] = -0.15;
    p.lean = 0.12;
    switch (j.phase) {
      case Phase.intake || Phase.build:
        // Following the letters, kerning each one.
        if (plan != null && _rounding(p, plan, t, w)) break;
        if (trip >= 0 && trip < 0.22) {
          // Waving the crane in.
          final wave = math.sin(t * 9);
          p.yaw = 2.6;
          p.armPitch[1] = 2.7 + 0.25 * wave;
          p.armRoll[1] = 0.35 + 0.25 * wave;
          p.lean = -0.1;
        } else if ((t / 7).floor() % 3 == 1) {
          // Pointing at the wall.
          p.armPitch[1] = 1.45;
          p.armRoll[1] = -0.35;
        }
      case Phase.reveal || Phase.celebrate:
        final beat = t * 3.1;
        final jump = math.max(0.0, math.sin(beat));
        p.bob = 0.16 * jump * jump;
        p.armPitch[1] = math.pi * 0.9;
        p.armRoll[1] = 0.3 + 0.2 * math.sin(beat * 2);
        p.armPitch[0] = 2.2;
      case Phase.demolish:
        final hit = impact == null ? 1e9 : t - impact;
        if (hit > -0.2 && hit < 1.4) {
          p.armPitch[1] = 2.7;
          p.armRoll[1] = 0.5;
          p.lean = -0.2;
        }
      case Phase.cleanup:
        break;
    }
  }

  void _operatorPose(Job j, double t, vm.Vector3 seat, double yaw) {
    final p = poses[operator]..rest();
    p.pos.setFrom(seat);
    p.yaw = yaw;
    p.pos.y -= 0.3; // seated
    p.legPitch[0] = p.legPitch[1] = 1.45;
    p.armPitch[0] = 0.95 + 0.08 * math.sin(t * 3.1);
    p.armPitch[1] = 0.95 + 0.08 * math.sin(t * 2.3 + 1);
    p.armRoll[0] = p.armRoll[1] = 0.05;
    if (j.phase == Phase.celebrate) {
      p.armPitch[1] = 2.8 + 0.3 * math.sin(t * 8);
      p.armRoll[1] = 0.3;
    }
  }

  // ── The platform ──────────────────────────────────────────────────────────

  void _platform(double w, double deck, double sink) {
    final y = deck + sink;
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
    // Deck planks (three boards) and the toe board along the back.
    for (var k = 0; k < 3; k++) {
      box(0, y - 0.05, z0 + dz * (k + 0.5) / 3, half * 2, 0.1, dz / 3 - 0.03, k.isEven ? wood : _wood2);
    }
    box(0, y + 0.08, z1 - 0.03, half * 2, 0.16, 0.04, dark);
    // Guard rails: back and ends, top and middle.
    for (final h in [0.55, 1.05]) {
      box(0, y + h, z1 - 0.03, half * 2, 0.05, 0.05, rail);
      for (final sx in [-1.0, 1.0]) {
        box(sx * half, y + h, zc, 0.05, 0.05, dz, rail);
      }
    }
    // Posts.
    final posts = math.max(2, (half * 2 / 1.6).ceil());
    for (var k = 0; k <= posts; k++) {
      box(-half + half * 2 * k / posts, y + 0.53, z1 - 0.03, 0.06, 1.06, 0.06, rail);
    }
    for (final sx in [-1.0, 1.0]) {
      box(sx * half, y + 0.53, z0 + 0.05, 0.06, 1.06, 0.06, rail);
      // Climbing gear on the masts.
      box(sx * mx, y + 0.28, zc, 0.62, 0.46, 0.66, motor);
    }
    for (; n < _deckParts; n++) {
      _deck.setInstanceTransform(n, hidden);
    }
    // Festoon bulbs along the back rail, glowing after dark.
    final count = math.min(_maxBulbs, (half * 2 / 0.62).floor());
    final glow = 0.4 + 7 * c01((_night - 0.1) / 0.4);
    for (var k = 0; k < _maxBulbs; k++) {
      if (!visible || k >= count) {
        _bulbs.setInstanceTransform(k, hidden);
        continue;
      }
      final x = -half + (k + 0.5) * half * 2 / count;
      final sag = 0.07 * math.sin(((k % 4) + 0.5) / 4 * math.pi);
      _bulbs.setInstanceTransform(k, setTrs(_m, x, y + 1.13 - sag, z1 - 0.03));
      final c = _bulbColors[k % _bulbColors.length];
      final tw = 0.85 + 0.15 * math.sin(_t * 3 + k * 1.7);
      _bulbs.setInstanceColor(k, vm.Vector4(c.x * glow * tw, c.y * glow * tw, c.z * glow * tw, 1));
    }
  }

  double _t = 0;
  static final _bulbColors = [lin(BP.amber), lin(const Color(0xFFFFF1D6)), lin(BP.coral), lin(const Color(0xFFFFF1D6))];

  static final _qi = vm.Quaternion.identity();
  static final _wood = lin(const Color(0xFF9C6B3C)), _wood2 = lin(const Color(0xFF8A5C32));
  static final _rail = lin(const Color(0xFFFFC23D)), _dark = lin(const Color(0xFF1A2230)), _motor = lin(const Color(0xFF2E6DA8));
}
