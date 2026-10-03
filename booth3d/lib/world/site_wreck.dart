import 'dart:math' as math;

import 'package:flutter_scene/physics.dart' show BodyType, BoxShape, CapsuleShape, PhysicsMaterial, PoseTarget, SphereShape;
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'physics.dart';

/// One brick of the name as the wrecking ball finds it: where it stands in
/// the wall (its letter, its cell), and when and how it's let go — the
/// ball's hit, or crumbling after it.
class WreckBrick {
  WreckBrick(this.at, this.letter, this.col, this.row, this.release, this.velocity, this.spin, {required this.hit});
  final vm.Vector3 at, velocity, spin;
  final int letter, col, row;
  final double release;
  final bool hit;
}

/// A rigid body of the wreck: one brick, or a chunk of them still mortared
/// together (their places relative to the body).
class _Piece implements PoseTarget {
  _Piece(this.wreck, this.bricks, this.offsets, vm.Vector3 at, this.release, this.velocity, this.spin) : t = at.clone();
  final Wreck wreck;
  final List<int> bricks;
  final List<vm.Vector3> offsets;
  final double release;
  final vm.Vector3 velocity, spin;
  final vm.Vector3 t;
  final q = vm.Quaternion.identity();
  int body = -1;
  bool released = false, landed = false;

  @override
  vm.Vector3 get worldTranslation => t;

  @override
  vm.Quaternion get worldRotation => q;

  @override
  void setWorldPose(vm.Vector3 translation, vm.Quaternion rotation) {
    t.setFrom(translation);
    q.setFrom(rotation);
    wreck._moved(this);
  }
}

/// 解体 · The wreck in real physics (Rapier): the name's bricks as rigid
/// bodies. Each letter is cut into chunks of a few bricks still mortared
/// together (single bricks where the ball goes through), held in the wall
/// until let go: then they tumble, knock into each other, the plinths and
/// the ground, and come to rest in piles. The ball (kinematic, on its
/// swing: a tonne against a brick) is solid: the bricks in its way are let
/// go as it touches them, and it knocks them flying. Whatever nothing
/// holds up any more — no longer joined, through standing bricks, to its
/// letter's foot — falls at once. A chunk that lands hard breaks into its
/// bricks. Fast bricks are swept (CCD) so they never pass through
/// anything. People nearby are capsules the rubble bounces off. The
/// cleanup picks the bricks up where they lie.
class Wreck {
  Wreck(this.physics, this.draw);

  final Physics physics;

  /// Draws brick [i] at a pose (as the physics moves it).
  final void Function(int i, vm.Vector3 t, vm.Quaternion q) draw;

  final _pieces = <_Piece>[];
  List<int> _pieceOf = const [];
  List<vm.Vector3> _pos = const [];
  List<vm.Quaternion> _rot = const [];
  final _shatter = <_Piece>[];
  int _ball = -1;
  double _b = 0.2, _now = 0;

  /// The bricks as planned, where each is in the wall (letter, column,
  /// row), and each letter's foot (its lowest row): for what holds what up.
  List<WreckBrick?> _src = const [];
  final _cell = <(int, int, int), int>{};
  final _foot = <int, int>{};
  bool _dirty = false;

  /// The people about: a kinematic capsule each (by their index), and
  /// where it was put last (null: parked out of the way).
  final _people = <int>[];
  final _peopleAt = <vm.Vector3?>[];

  /// Where bricks first hit the ground: (scene time, x, z), for dust.
  final impacts = <(double, double, double)>[];

  static const _mortar = PhysicsMaterial(friction: 0.78, restitution: 0.1, density: 1.9);

  bool get active => _pieces.isNotEmpty || _plain.isNotEmpty;

  /// Whether brick [i] has been let go (it's the physics' now).
  bool released(int i) {
    if (_plain.isNotEmpty) return i < _plain.length && _plain[i] != null && _u >= _plain[i]!.release;
    return i < _pieceOf.length && _pieceOf[i] >= 0 && _pieces[_pieceOf[i]].released;
  }

  // Without physics (its backend didn't load): each brick flies and falls
  // on its own, and lies where it lands.
  List<WreckBrick?> _plain = const [];
  double _u = 0;
  final _q = vm.Quaternion.identity();

  void _plainUpdate(double u) {
    _u = u;
    for (var i = 0; i < _plain.length; i++) {
      final br = _plain[i];
      if (br == null || u < br.release || _gone.contains(i)) continue;
      final tau = u - br.release, v = br.velocity;
      final y0 = br.at.y - _b / 2;
      final land = (v.y + math.sqrt(v.y * v.y + 2 * 9.81 * math.max(0, y0))) / 9.81;
      final f = math.min(tau, land), slide = tau > land ? 0.3 * (1 - math.exp(-(tau - land) * 4)) : 0.0;
      final p = _pos[i]..setValues(br.at.x + v.x * (f + slide), math.max(_b / 2, br.at.y + v.y * f - 4.905 * f * f), br.at.z + v.z * (f + slide));
      final spin = br.spin.length;
      if (spin > 1e-6) _q.setAxisAngle(br.spin / spin, spin * (f + slide * 0.5));
      _rot[i].setFrom(_q);
      draw(i, p, _q);
    }
  }

  final _gone = <int>{};

  /// Where brick [i] is (its place in the wall, or where the physics has
  /// it).
  vm.Vector3 positionOf(int i) => _pos[i];
  vm.Quaternion rotationOf(int i) => _rot[i];

  /// Builds the wreck from [bricks] (null: not standing), bricks [b] wide;
  /// the ball at [ballAt], [u] seconds into the wrecking.
  void start(List<WreckBrick?> bricks, double b, vm.Vector3 ballAt, double u, {List<(vm.Vector3, vm.Vector3)> solids = const []}) {
    end();
    _b = b;
    _src = bricks;
    for (var i = 0; i < bricks.length; i++) {
      final br = bricks[i];
      if (br == null) continue;
      _cell[(br.letter, br.col, br.row)] = i;
      final f = _foot[br.letter];
      if (f == null || br.row < f) _foot[br.letter] = br.row;
    }
    if (!Physics.available) {
      _plain = bricks;
      _pos = [for (final br in bricks) br?.at.clone() ?? vm.Vector3.zero()];
      _rot = [for (var i = 0; i < bricks.length; i++) vm.Quaternion.identity()];
      return;
    }
    final w = physics.world;
    physics.clock = u;
    final n = bricks.length;
    _pieceOf = List.filled(n, -1);
    _pos = [for (final br in bricks) br?.at.clone() ?? vm.Vector3.zero()];
    _rot = [for (var i = 0; i < n; i++) vm.Quaternion.identity()];
    // Chunks, as masonry breaks: within a letter, a run of a course or two
    // (1×1 … 4×1, 2×2, 3×2 bricks) from each brick on, rightwards and
    // down, over whatever's there and free (none across the ball's path).
    final cell = <(int, int, int), int>{};
    for (var i = 0; i < n; i++) {
      final br = bricks[i];
      if (br != null && !br.hit) cell[(br.letter, br.col, br.row)] = i;
    }
    final taken = List.filled(n, false);
    final order = [
      for (var i = 0; i < n; i++)
        if (bricks[i] != null) i,
    ]..sort((a, c) => bricks[a]!.row != bricks[c]!.row ? bricks[c]!.row.compareTo(bricks[a]!.row) : bricks[a]!.col.compareTo(bricks[c]!.col));
    const sizes = [(1, 1), (1, 1), (2, 1), (2, 1), (2, 1), (3, 1), (2, 2), (1, 2)];
    for (final i in order) {
      if (taken[i]) continue;
      final br = bricks[i]!;
      final group = [i];
      taken[i] = true;
      if (!br.hit) {
        final (cw, ch) = sizes[(rnd(i, 7) * sizes.length).floor() % sizes.length];
        for (var dr = 0; dr < ch; dr++) {
          for (var dc = 0; dc < cw; dc++) {
            if (dr == 0 && dc == 0) continue;
            final j = cell[(br.letter, br.col + dc, br.row - dr)];
            if (j == null || taken[j]) continue;
            taken[j] = true;
            group.add(j);
          }
        }
      }
      final mid = vm.Vector3.zero(), v = vm.Vector3.zero(), s = vm.Vector3.zero();
      var release = double.infinity;
      for (final j in group) {
        final g = bricks[j]!;
        mid.add(g.at);
        v.add(g.velocity);
        s.add(g.spin);
        release = math.min(release, g.release);
      }
      final k = 1 / group.length;
      mid.scale(k);
      v.scale(k);
      // (A chunk turns more slowly than a brick.)
      s.scale(k / math.sqrt(group.length));
      _add(group, [for (final j in group) bricks[j]!.at - mid], mid, vm.Quaternion.identity(), release, v, s, BodyType.fixed, later: true);
    }
    _ball = w.createBody(target: StillPose(ballAt), type: BodyType.kinematic);
    w.createColliders(_ball, SphereShape(radius: _ballRadius), material: const PhysicsMaterial(friction: 0.4, restitution: 0.12, density: 8));
    // The solid things the rubble meets.
    for (final (c, h) in solids) {
      final body = w.createBody(target: StillPose(c), type: BodyType.fixed);
      w.createColliders(body, BoxShape(halfExtents: h), material: const PhysicsMaterial(friction: 0.8, restitution: 0.05));
    }
  }

  static const _ballRadius = 1.0;

  /// Wall pieces not in the physics yet.
  final _unmade = <_Piece>[];

  void _make(_Piece p, BodyType type) {
    final w = physics.world;
    p.body = w.createBody(target: p, type: type);
    final half = vm.Vector3.all(_b * 0.48);
    for (final o in p.offsets) {
      w.createColliders(
        p.body,
        BoxShape(halfExtents: half),
        material: _mortar,
        localPose: vm.Matrix4.translation(o),
      );
    }
  }

  /// Puts up to [n] waiting wall pieces into the physics (all of them when
  /// one is due to be let go).
  void _makeSome(double u, int n) {
    if (_unmade.isEmpty) return;
    final due = _unmade.any((p) => u >= p.release);
    var k = 0;
    for (; k < _unmade.length && (due || k < n); k++) {
      _make(_unmade[k], BodyType.fixed);
    }
    _unmade.removeRange(0, k);
  }

  /// A piece of [bricks] at [offsets] from [at]; in the physics now, or
  /// ([later]) a few at a time over the next frames (the wall's pieces: all
  /// at once would stall a frame).
  _Piece _add(
    List<int> bricks,
    List<vm.Vector3> offsets,
    vm.Vector3 at,
    vm.Quaternion q,
    double release,
    vm.Vector3 v,
    vm.Vector3 s,
    BodyType type, {
    bool later = false,
  }) {
    final p = _Piece(this, bricks, offsets, at, release, v, s);
    p.q.setFrom(q);
    if (later) {
      _unmade.add(p);
    } else {
      _make(p, type);
    }
    final index = _pieces.length;
    _pieces.add(p);
    for (final i in bricks) {
      _pieceOf[i] = index;
    }
    return p;
  }

  /// [u] seconds into the wrecking, [dt] since the last: lets go of what's
  /// due (and whatever's no longer held up), moves the ball to [ballAt] and
  /// the [people] (their feet) where they are, steps the physics, breaks up
  /// chunks that landed hard.
  void update(double t, double u, double dt, vm.Vector3 Function(double u) ballAt, {List<vm.Vector3?> people = const []}) {
    if (!active) return;
    if (_plain.isNotEmpty) return _plainUpdate(u);
    final w = physics.world;
    _makeSome(u, 80);
    for (final p in _pieces) {
      if (p.released || u < p.release || p.body < 0) continue;
      _release(p);
    }
    if (_dirty && _unmade.isEmpty) _support();
    _place(people);
    _now = t;
    physics.advance(dt, beforeStep: (tu) => w.setBodyKinematicTargetPose(_ball, ballAt(tu), _q0));
    _breakUp();
  }

  /// Lets [p] fall: with its planned kick, or ([gentle]: it just lost its
  /// support) a little nudge of its own, so what comes down together
  /// doesn't stay in one sheet.
  void _release(_Piece p, {bool gentle = false}) {
    final w = physics.world;
    p.released = true;
    _dirty = true;
    final i = p.bricks.first;
    final v = gentle ? vm.Vector3((rnd(i, 41) - 0.5) * 0.9, rnd(i, 42) * 0.3, (rnd(i, 43) - 0.5) * 0.9) : p.velocity;
    final s = gentle ? p.spin * 0.15 + vm.Vector3(rnd(i, 44) - 0.5, rnd(i, 45) - 0.5, rnd(i, 46) - 0.5) * 2.4 : p.spin;
    w
      ..setBodyKind(p.body, BodyType.dynamic_)
      ..setBodyCcdEnabled(p.body, true)
      ..setBodyLinearVelocity(p.body, v)
      ..setBodyAngularVelocity(p.body, s)
      ..wakeBody(p.body);
  }

  /// Lets go of whatever nothing holds up: standing bricks not joined,
  /// side by side or one on another through standing bricks, to their
  /// letter's foot. (A chunk stands while any of its bricks is held.)
  void _support() {
    _dirty = false;
    final n = _src.length;
    final held = List<bool>.filled(n, false);
    bool standing(int i) {
      final k = i < _pieceOf.length ? _pieceOf[i] : -1;
      return k >= 0 && !_pieces[k].released;
    }

    final queue = <int>[];
    for (var i = 0; i < n; i++) {
      final br = _src[i];
      if (br == null || br.row != _foot[br.letter] || !standing(i)) continue;
      held[i] = true;
      queue.add(i);
    }
    while (queue.isNotEmpty) {
      final br = _src[queue.removeLast()]!;
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final j = _cell[(br.letter, br.col + dc, br.row + dr)];
        if (j == null || held[j] || !standing(j)) continue;
        held[j] = true;
        queue.add(j);
      }
    }
    for (final p in _pieces) {
      if (p.released || p.body < 0 || p.bricks.any((i) => held[i])) continue;
      _release(p, gentle: true);
    }
  }

  /// The people as capsules where they stand ([people]: their feet, by
  /// their index; null: not about). One walking moves its capsule (and
  /// shoves what it walks into); one appearing, or jumping somewhere,
  /// teleports it (nothing gets flung by a jump).
  void _place(List<vm.Vector3?> people) {
    final w = physics.world;
    while (_people.length < people.length && _people.length < 24) {
      final body = w.createBody(target: StillPose(_parked), type: BodyType.kinematic);
      w.createColliders(body, const CapsuleShape(radius: 0.26, halfHeight: 0.6), material: const PhysicsMaterial(friction: 0.6, restitution: 0.1));
      _people.add(body);
      _peopleAt.add(null);
    }
    for (var k = 0; k < _people.length; k++) {
      final feet = k < people.length ? people[k] : null, last = _peopleAt[k];
      if (feet == null) {
        if (last != null) w.setBodyPose(_people[k], _parked, _q0);
        _peopleAt[k] = null;
        continue;
      }
      final at = vm.Vector3(feet.x, feet.y + 0.86, feet.z);
      if (last == null || last.distanceTo(at) > 0.5) {
        w.setBodyPose(_people[k], at, _q0);
      } else {
        w.setBodyKinematicTargetPose(_people[k], at, _q0);
      }
      _peopleAt[k] = at;
    }
  }

  static final _parked = vm.Vector3(0, -60, 0);
  static final _q0 = vm.Quaternion.identity();

  /// Steps the physics without the ball (the cleanup), [beforeStep] moving
  /// anything kinematic.
  void settle(double t, double dt, {void Function(double t)? beforeStep}) {
    if (!active || _plain.isNotEmpty) return;
    _now = t;
    physics.advance(dt, beforeStep: beforeStep);
    _breakUp();
  }

  /// Where the rubble lies (capture runs): bricks sunk into the ground, or
  /// inside one of [solids] (centre, half extents).
  String report(List<(vm.Vector3, vm.Vector3)> solids) {
    var n = 0, sunk = 0, inside = 0;
    var deepest = 0.0;
    for (var i = 0; i < _src.length; i++) {
      if (_src[i] == null) continue;
      n++;
      final p = _pos[i];
      final low = p.y - _b * 0.48;
      if (low < -0.02) {
        sunk++;
        deepest = math.max(deepest, -low);
      }
      for (final (c, h) in solids) {
        if ((p.x - c.x).abs() < h.x - 0.02 && (p.y - c.y).abs() < h.y - 0.02 && (p.z - c.z).abs() < h.z - 0.02) {
          inside++;
          break;
        }
      }
    }
    return 'WRECK $n bricks: $sunk sunk into the ground (deepest ${(deepest * 100).round()} cm), $inside inside something solid';
  }

  /// Moves the ball to [at] (kinematic: it shoves what's in its way).
  void ballTo(vm.Vector3 at) {
    if (_ball >= 0 && _plain.isEmpty) physics.world.setBodyKinematicTargetPose(_ball, at, _q0);
  }

  /// Lets go of everything still standing.
  void releaseAll() {
    if (_plain.isNotEmpty) return;
    _makeSome(double.infinity, 0);
    for (final p in _pieces) {
      if (p.released || p.body < 0) continue;
      _release(p, gentle: true);
    }
  }

  /// Takes brick [i] out of the physics (picked up), from where it lies;
  /// its chunk, if it was in one, comes apart.
  void pickUp(int i) {
    if (_plain.isNotEmpty) {
      _gone.add(i);
      return;
    }
    final k = i < _pieceOf.length ? _pieceOf[i] : -1;
    if (k < 0) return;
    final p = _pieces[k];
    if (p.bricks.length > 1) {
      _split(p, scatter: false);
      return pickUp(i);
    }
    if (p.body >= 0) physics.world.destroyBody(p.body);
    p.body = -1;
    _pieceOf[i] = -1;
  }

  void end() {
    physics.reset();
    _plain = const [];
    _gone.clear();
    _pieces.clear();
    _unmade.clear();
    _src = const [];
    _cell.clear();
    _foot.clear();
    _people.clear();
    _peopleAt.clear();
    _dirty = false;
    _pieceOf = const [];
    _shatter.clear();
    _ball = -1;
    impacts.clear();
  }

  /// A piece moved: its bricks follow; one coming down on the ground for
  /// the first time raises dust (and breaks up a chunk that hit hard).
  void _moved(_Piece p) {
    var low = double.infinity;
    for (var k = 0; k < p.bricks.length; k++) {
      final i = p.bricks[k];
      final at = _pos[i]
        ..setFrom(p.offsets[k])
        ..applyQuaternion(p.q)
        ..add(p.t);
      _rot[i].setFrom(p.q);
      draw(i, at, p.q);
      low = math.min(low, at.y);
    }
    if (!p.landed && low < _b * 0.75) {
      p.landed = true;
      final i = p.bricks.first;
      if (i % 3 == 0 || p.bricks.length > 1) impacts.add((_now, p.t.x, p.t.z));
      if (p.bricks.length > 1) _shatter.add(p);
    }
  }

  /// Chunks that landed hard come apart into their bricks.
  void _breakUp() {
    if (_shatter.isEmpty) return;
    final w = physics.world;
    for (final p in [..._shatter]) {
      if (p.body < 0) continue;
      if (w.readBodyLinearVelocity(p.body).length2 < 1.2 * 1.2) continue;
      _split(p, scatter: true);
    }
    _shatter.clear();
  }

  /// Replaces chunk [p] by its bricks, each a body where it is, moving as
  /// the chunk did ([scatter]: a little apart).
  void _split(_Piece p, {required bool scatter}) {
    final w = physics.world;
    final v = p.body >= 0 ? w.readBodyLinearVelocity(p.body) : vm.Vector3.zero();
    final s = p.body >= 0 ? w.readBodyAngularVelocity(p.body) : vm.Vector3.zero();
    if (p.body >= 0) w.destroyBody(p.body);
    p.body = -1;
    for (var k = 0; k < p.bricks.length; k++) {
      final i = p.bricks[k];
      final r = p.offsets[k].clone()..applyQuaternion(p.q);
      final bv = v + s.cross(r);
      if (scatter) bv.add(vm.Vector3(rnd(i, 31) - 0.5, rnd(i, 32) * 0.8, rnd(i, 33) - 0.5) * 2.2);
      final single = _add([i], [vm.Vector3.zero()], _pos[i], p.q, 0, bv, s, BodyType.dynamic_)
        ..released = true
        ..landed = true;
      w
        ..setBodyLinearVelocity(single.body, bv)
        ..setBodyAngularVelocity(single.body, s + (scatter ? vm.Vector3(rnd(i, 34) - 0.5, rnd(i, 35) - 0.5, rnd(i, 36) - 0.5) * 8 : vm.Vector3.zero()));
    }
  }
}
