import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Real rigid-body physics (Rapier) on the scene's clock: stepped from the
/// world's update with the model's time, not the wall clock, so capture runs
/// and fast-forward see the same simulation. One world at a time (made for
/// a scene that needs it, dropped after); the ground is a fixed slab whose
/// top is y = 0.
class Physics {
  RapierWorld? _world;
  double _acc = 0;

  /// The simulation's own clock (scene seconds): set when a scene starts
  /// its simulation, advanced a step at a time (for kinematic bodies'
  /// paths).
  double clock = 0;

  /// One step (seconds), and the most steps taken in one update (more time
  /// than that is dropped: fast-forward lets the simulation lag behind).
  static const step = 1 / 60.0, maxSteps = 8;

  /// Loads the backend (the web fetches its WebAssembly module); await once
  /// at start-up.
  static Future<void> ensureReady() => RapierWorld.ensureInitialized();

  /// The world, made on first use with the ground in it.
  RapierWorld get world {
    final existing = _world;
    if (existing != null) return existing;
    final w = _world = RapierWorld(gravity: vm.Vector3(0, -9.81, 0))
      ..fixedTimestep = step
      ..maxSubsteps = maxSteps;
    final ground = w.createBody(target: StillPose(vm.Vector3(0, -0.5, 0)), type: BodyType.fixed);
    w.createColliders(ground, BoxShape(halfExtents: vm.Vector3(200, 0.5, 200)), material: const PhysicsMaterial(friction: 0.8, restitution: 0.1));
    return w;
  }

  bool get active => _world != null;

  /// Advances by [dt] seconds of scene time in fixed steps (calling
  /// [beforeStep] with the clock at each step's end, to move kinematic
  /// bodies), then writes the dynamic bodies' poses (blended between the
  /// last two steps).
  void advance(double dt, {void Function(double t)? beforeStep}) {
    final w = _world;
    if (w == null || dt <= 0) return;
    _acc += dt;
    var n = 0;
    while (_acc >= step && n < maxSteps) {
      clock += step;
      beforeStep?.call(clock);
      w.step(step);
      _acc -= step;
      n++;
    }
    if (_acc > step * maxSteps) _acc = 0;
    w.interpolatePoses(_acc / step);
  }

  /// Drops the world and everything in it.
  void reset() {
    _world?.dispose();
    _world = null;
    _acc = 0;
    clock = 0;
  }

  /// A box dropped from 2 m for a second: where it ends up (for a capture
  /// log, to see the backend works). Leaves no world behind.
  static String selfTest() {
    final p = Physics();
    final box = StillPose(vm.Vector3(0, 2, 0));
    final h = p.world.createBody(target: box, type: BodyType.dynamic_);
    p.world.createColliders(h, BoxShape(halfExtents: vm.Vector3.all(0.1)));
    for (var i = 0; i < 60; i++) {
      p.advance(1 / 60);
    }
    final (t, _) = p.world.readBodyPose(h);
    p.reset();
    return 'PHYSICS ${p.runtimeType} rapier: a box dropped from 2 m is at ${t.y.toStringAsFixed(3)} m after 1 s';
  }
}

/// A pose that sits still until the simulation moves it (a body's start;
/// what it last wrote).
class StillPose implements PoseTarget {
  StillPose(vm.Vector3 at, [vm.Quaternion? rotation]) : _t = at.clone(), _q = rotation?.clone() ?? vm.Quaternion.identity();
  final vm.Vector3 _t;
  final vm.Quaternion _q;

  @override
  vm.Vector3 get worldTranslation => _t;

  @override
  vm.Quaternion get worldRotation => _q;

  @override
  void setWorldPose(vm.Vector3 translation, vm.Quaternion rotation) {
    _t.setFrom(translation);
    _q.setFrom(rotation);
  }
}
