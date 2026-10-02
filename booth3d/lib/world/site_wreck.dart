import 'dart:math' as math;

import 'package:flutter_scene/physics.dart' show BodyType, BoxShape, PhysicsMaterial, PoseTarget, SphereShape;
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
/// until let go: then they tumble, knock into each other and the ground,
/// and come to rest in piles. A chunk that lands hard breaks into its
/// bricks. After its first pass the ball (kinematic, on its swing) shoves
/// whatever it meets. The cleanup picks the bricks up where they lie.
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
  List<int> _ballColliders = const [];
  bool _ballSolid = false;
  double _b = 0.2, _now = 0;

  /// Where bricks first hit the ground: (scene time, x, z), for dust.
  final impacts = <(double, double, double)>[];

  static const _mortar = PhysicsMaterial(friction: 0.78, restitution: 0.1, density: 1.9);

  bool get active => _pieces.isNotEmpty;

  /// Whether brick [i] has been let go (it's the physics' now).
  bool released(int i) => i < _pieceOf.length && _pieceOf[i] >= 0 && _pieces[_pieceOf[i]].released;

  /// Where brick [i] is (its place in the wall, or where the physics has
  /// it).
  vm.Vector3 positionOf(int i) => _pos[i];
  vm.Quaternion rotationOf(int i) => _rot[i];

  /// Builds the wreck from [bricks] (null: not standing), bricks [b] wide;
  /// the ball at [ballAt], [u] seconds into the wrecking.
  void start(List<WreckBrick?> bricks, double b, vm.Vector3 ballAt, double u) {
    end();
    _b = b;
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
    const sizes = [(1, 1), (2, 1), (2, 1), (3, 1), (3, 1), (4, 1), (2, 2), (3, 2)];
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
    _ballColliders = w.createColliders(_ball, SphereShape(radius: _ballRadius), material: const PhysicsMaterial(friction: 0.4, restitution: 0.05, density: 8), collisionMask: 0);
  }

  static const _ballRadius = 1.0;

  /// Wall pieces not in the physics yet.
  final _unmade = <_Piece>[];

  void _make(_Piece p, BodyType type) {
    final w = physics.world;
    p.body = w.createBody(target: p, type: type);
    final half = vm.Vector3.all(_b * 0.48);
    for (final o in p.offsets) {
      w.createColliders(p.body, BoxShape(halfExtents: half), material: _mortar, localPose: vm.Matrix4.translation(o));
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
  _Piece _add(List<int> bricks, List<vm.Vector3> offsets, vm.Vector3 at, vm.Quaternion q, double release, vm.Vector3 v, vm.Vector3 s, BodyType type, {bool later = false}) {
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
  /// due, moves the ball to [ballAt] (solid from [solidFrom] on), steps the
  /// physics, breaks up chunks that landed hard.
  void update(double t, double u, double dt, vm.Vector3 Function(double u) ballAt, {required double solidFrom}) {
    if (!active) return;
    final w = physics.world;
    _makeSome(u, 80);
    for (final p in _pieces) {
      if (p.released || u < p.release || p.body < 0) continue;
      p.released = true;
      w
        ..setBodyKind(p.body, BodyType.dynamic_)
        ..setBodyLinearVelocity(p.body, p.velocity * 0.85)
        ..setBodyAngularVelocity(p.body, p.spin)
        ..wakeBody(p.body);
    }
    if (!_ballSolid && u >= solidFrom) {
      _ballSolid = true;
      for (final c in _ballColliders) {
        w.setColliderFilter(c, 0xFFFFFFFF, 0xFFFFFFFF);
      }
    }
    _now = t;
    physics.advance(dt, beforeStep: (tu) => w.setBodyKinematicTargetPose(_ball, ballAt(tu), _q0));
    _breakUp();
  }
  static final _q0 = vm.Quaternion.identity();

  /// Steps the physics without the ball (the cleanup), [beforeStep] moving
  /// anything kinematic.
  void settle(double t, double dt, {void Function(double t)? beforeStep}) {
    if (!active) return;
    _now = t;
    physics.advance(dt, beforeStep: beforeStep);
    _breakUp();
  }

  /// Lets go of everything still standing.
  void releaseAll() {
    _makeSome(double.infinity, 0);
    final w = physics.world;
    for (final p in _pieces) {
      if (p.released || p.body < 0) continue;
      p.released = true;
      w
        ..setBodyKind(p.body, BodyType.dynamic_)
        ..wakeBody(p.body);
    }
  }

  /// Takes brick [i] out of the physics (picked up), from where it lies;
  /// its chunk, if it was in one, comes apart.
  void pickUp(int i) {
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
    _pieces.clear();
    _unmade.clear();
    _pieceOf = const [];
    _shatter.clear();
    _ball = -1;
    _ballColliders = const [];
    _ballSolid = false;
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
      if (w.readBodyLinearVelocity(p.body).length2 < 2.0 * 2.0) continue;
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
      if (scatter) bv.add(vm.Vector3(rnd(i, 31) - 0.5, rnd(i, 32) * 0.8, rnd(i, 33) - 0.5) * 1.6);
      final single = _add([i], [vm.Vector3.zero()], _pos[i], p.q, 0, bv, s, BodyType.dynamic_)
        ..released = true
        ..landed = true;
      w
        ..setBodyLinearVelocity(single.body, bv)
        ..setBodyAngularVelocity(single.body, s + (scatter ? vm.Vector3(rnd(i, 34) - 0.5, rnd(i, 35) - 0.5, rnd(i, 36) - 0.5) * 6 : vm.Vector3.zero()));
    }
  }
}
