import 'dart:math' as math;

import '../../worlds/factory/factory_kit.dart';
import '../model.dart';

/// Street geometry (canvas y): the site apron, the road's two lanes and the
/// near sidewalk, all between the ground line and the name input band.
abstract final class Street {
  static const apronBottom = 722.0;
  static const roadTop = 725.0;
  static const centre = 755.0;
  static const roadBottom = 786.0;

  /// Where pedestrians' feet are (near sidewalk).
  static const walkY = 800.0;
  static const sidewalkBottom = 805.0;

  /// Wheel contact line of each lane: 0 far (eastbound, →), 1 near (←).
  /// Japan drives on the left, so seen from the near sidewalk the far lane
  /// runs left to right.
  static const laneY = [752.0, 783.0];
  static const laneDir = [1, -1];

  /// The bus stop on the near sidewalk; buses stop with their nose here.
  static const busStopX = 400.0;
  static const busPoleX = 494.0;
  static const benchL = 446.0, benchR = 482.0;

  /// Where the traffic guard stands (between factory and site).
  static const guardX = 646.0;
}

/// Kinds of vehicles.
enum CarKind { kei, sedan, taxi, van, truck, scooter, bus, yakiimo }

class Car {
  Car(this.kind, this.seed, this.x, this.v, this.v0);

  final CarKind kind;
  final int seed;

  /// Front bumper x.
  double x;
  double v;
  final double v0;
  double roll = 0;

  /// A bus serving the stop: seconds left at the stop (> 0 while there).
  double dwell = 0;
  bool served = false;
  bool alighted = false;

  double get len => switch (kind) {
    CarKind.kei => 44,
    CarKind.sedan || CarKind.taxi => 58,
    CarKind.van => 60,
    CarKind.truck || CarKind.yakiimo => 54,
    CarKind.scooter => 28,
    CarKind.bus => 124,
  };
}

/// Kinds of pedestrians.
enum WalkerKind { plain, letter, balloon, briefcase, dog, camera, bike, parasol }

enum WalkerState { walk, look, wait, board }

class Walker {
  Walker(this.kind, this.seed, this.x, this.dir, this.v, this.h);

  final WalkerKind kind;
  final int seed;
  double x;
  int dir;
  final double v;
  final double h;

  /// Distance walked (drives the gait).
  double dist = 0;
  WalkerState state = WalkerState.walk;
  double timer = 0;
  double target = 0;
  bool looked = false;
  bool askedBus = false;

  /// 0..1 fade (boarding the bus).
  double fade = 1;

  /// Seconds standing still (for idle animation).
  double still = 0;
}

/// Traffic and pedestrians on the street, simulated (stepped with the model
/// so live frames, fast-forward and capture agree). Bounded: vehicles and
/// people leave the screen and are dropped.
class StreetSim extends BoothSystem {
  StreetSim() {
    // Start with a lived-in street.
    for (var i = 0; i < 60 * 30; i++) {
      _step(-60 + i / 30, 1 / 30, null);
    }
    _now = 0;
  }

  final lanes = [<Car>[], <Car>[]];
  final walkers = <Walker>[];

  double _now = 0;
  int _serial = 0;
  final _nextCar = [-60.0, -58.5];
  double _nextBus = -34;
  double _nextWalker = -60;

  /// True while the site's trucks need the road (no new traffic).
  bool closed = false;

  /// A bus at the stop, if any.
  Car? get busAtStop {
    for (final c in lanes[1]) {
      if (c.kind == CarKind.bus && c.dwell > 0) return c;
    }
    return null;
  }

  bool get _busComing =>
      lanes[1].any((c) => c.kind == CarKind.bus && !c.served) || _nextBus - _now < 35;

  int get waiting => walkers.where((w) => w.state == WalkerState.wait).length;

  @override
  void update(BoothModel m, double dt) => _step(m.t, dt, m.job?.phase);

  void _step(double t, double dt, Phase? phase) {
    _now = t;
    closed = phase == Phase.demolish || phase == Phase.cleanup;
    for (var l = 0; l < 2; l++) {
      _spawnCar(l, t);
      _drive(l, dt);
    }
    _spawnWalker(t);
    _walk(dt, phase);
  }

  // ── Vehicles ──────────────────────────────────────────────────────────────

  void _spawnCar(int lane, double t) {
    if (closed || t < _nextCar[lane]) return;
    final cars = lanes[lane];
    final dir = Street.laneDir[lane];
    final entry = dir > 0 ? -40.0 : 1640.0;
    // Room at the entry?
    if (cars.isNotEmpty) {
      final last = cars.last;
      if (dir * last.x - last.len < dir * entry + 30) return;
    }
    final n = _serial++;
    final r = rnd(n, 1);
    CarKind kind;
    if (lane == 1 && t >= _nextBus) {
      kind = CarKind.bus;
      _nextBus = t + 62 + 26 * rnd(n, 2);
    } else if (r < 0.04) {
      kind = CarKind.bus;
    } else if (r < 0.085) {
      // The sweet-potato truck crawls along (and holds up the traffic).
      kind = CarKind.yakiimo;
    } else {
      const kinds = [CarKind.kei, CarKind.sedan, CarKind.taxi, CarKind.van, CarKind.truck, CarKind.scooter];
      const weights = [0.22, 0.18, 0.16, 0.12, 0.14, 0.18];
      var acc = 0.0;
      kind = kinds.last;
      final q = rnd(n, 3);
      for (var i = 0; i < kinds.length; i++) {
        acc += weights[i];
        if (q < acc) {
          kind = kinds[i];
          break;
        }
      }
    }
    final v0 = switch (kind) {
      CarKind.bus => 66.0,
      CarKind.yakiimo => 40.0,
      CarKind.truck => 74 + 10 * rnd(n, 4),
      CarKind.scooter => 82 + 12 * rnd(n, 4),
      _ => 80 + 18 * rnd(n, 4),
    };
    cars.add(Car(kind, n, entry, v0 * 0.9, v0));
    _nextCar[lane] = t + 3.8 + 6.5 * rnd(n, 5);
  }

  void _drive(int lane, double dt) {
    final cars = lanes[lane];
    final dir = Street.laneDir[lane];
    const aMax = 55.0, brake = 120.0, s0 = 12.0, headway = 0.9;
    for (var i = 0; i < cars.length; i++) {
      final c = cars[i];
      final s = dir * c.x;
      var gap = 1e9;
      var dv = 0.0;
      if (i > 0) {
        final lead = cars[i - 1];
        gap = dir * lead.x - lead.len - s;
        dv = c.v - lead.v;
      }
      // Buses pull in at the stop on the near side.
      if (lane == 1 && c.kind == CarKind.bus && !c.served) {
        final g = dir * Street.busStopX - s;
        if (g > -2 && g < gap) {
          gap = math.max(0.01, g + s0);
          dv = c.v;
        }
        if (g.abs() < 2.5 && c.v < 4 && c.dwell <= 0) c.dwell = 6.5;
      }
      if (c.dwell > 0) {
        c.dwell -= dt;
        c.v = 0;
        if (c.dwell <= 0) {
          c.dwell = 0;
          c.served = true;
        }
        continue;
      }
      final sStar = s0 + c.v * headway + c.v * dv / (2 * math.sqrt(aMax * brake));
      final ratio = math.max(0.0, sStar) / math.max(gap, 0.5);
      final a = (aMax * (1 - math.pow(c.v / c.v0, 4) - ratio * ratio)).clamp(-400.0, aMax);
      c.v = math.max(0.0, c.v + a * dt);
      c.x += dir * c.v * dt;
      c.roll += c.v * dt / 5;
    }
    cars.removeWhere((c) => dir > 0 ? c.x - c.len > 1660 : c.x + c.len < -60);
  }

  // ── Pedestrians ───────────────────────────────────────────────────────────

  void _spawnWalker(double t) {
    if (t < _nextWalker || walkers.length >= 14) return;
    final n = _serial++;
    final dir = rnd(n, 11) < 0.5 ? 1 : -1;
    final r = rnd(n, 12);
    final kind = r < 0.27
        ? WalkerKind.plain
        : r < 0.42
        ? WalkerKind.letter
        : r < 0.5
        ? WalkerKind.balloon
        : r < 0.62
        ? WalkerKind.briefcase
        : r < 0.71
        ? WalkerKind.dog
        : r < 0.8
        ? WalkerKind.camera
        : r < 0.9
        ? WalkerKind.bike
        : WalkerKind.parasol;
    final v = kind == WalkerKind.bike ? 50 + 12 * rnd(n, 13) : 19 + 8 * rnd(n, 13);
    final h = kind == WalkerKind.balloon ? 18.0 : 24 + 4 * rnd(n, 14);
    walkers.add(Walker(kind, n, dir > 0 ? -30 : 1630, dir, v, h));
    _nextWalker = t + 3.2 + 5 * rnd(n, 15);
  }

  void _walk(double dt, Phase? phase) {
    final bus = busAtStop;
    final busComing = _busComing;
    final show = phase == Phase.build || phase == Phase.reveal || phase == Phase.celebrate;
    for (final w in walkers) {
      switch (w.state) {
        case WalkerState.walk:
          final k = phase == Phase.celebrate ? 0.6 : 1.0;
          w.x += w.dir * w.v * k * dt;
          w.dist += w.v * k * dt;
          w.still = 0;
          // Stop to look at the name going up.
          if (!w.looked && w.x > 730 && w.x < 1400 && w.kind != WalkerKind.bike) {
            w.looked = true;
            final p = w.kind == WalkerKind.camera ? 0.9 : 0.28;
            if (show && rnd(w.seed, 21) < p) {
              w.state = WalkerState.look;
              w.timer = 3.5 + 4 * rnd(w.seed, 22);
            }
          }
          // Wait for the bus?
          if (!w.askedBus && w.x > Street.benchL - 6 && w.x < Street.busPoleX && w.kind != WalkerKind.bike) {
            w.askedBus = true;
            final queue = waiting;
            if (busComing && queue < 3 && rnd(w.seed, 23) < 0.4) {
              w.state = WalkerState.wait;
              w.target = Street.benchL + 6 + 13.0 * queue;
            }
          }
        case WalkerState.look:
          w.timer -= dt;
          w.still += dt;
          if (w.timer <= 0) w.state = WalkerState.walk;
        case WalkerState.wait:
          if ((w.x - w.target).abs() > 1) {
            final d = (w.target - w.x).sign;
            w.dir = d.toInt();
            w.x += d * math.min((w.target - w.x).abs(), w.v * dt);
            w.dist += w.v * dt;
            w.still = 0;
          } else {
            w.dir = 1; // looking out for the bus
            w.still += dt;
          }
          if (bus != null) {
            w.state = WalkerState.board;
            w.target = Street.busStopX + 16;
          } else if (w.still > 100) {
            // Gave up on the bus.
            w.state = WalkerState.walk;
          }
        case WalkerState.board:
          final d = (w.target - w.x).sign;
          w.dir = d == 0 ? -1 : d.toInt();
          w.x += d * math.min((w.target - w.x).abs(), 28 * dt);
          w.dist += 28 * dt;
          if ((w.x - w.target).abs() < 2) w.fade -= dt * 3;
      }
    }
    // Passengers getting off.
    if (bus != null && !bus.alighted && bus.dwell < 6) {
      bus.alighted = true;
      final n = (rnd(bus.seed, 31) * 3).floor();
      for (var i = 0; i < n && walkers.length < 16; i++) {
        final s = _serial++;
        final dir = rnd(s, 32) < 0.5 ? 1 : -1;
        walkers.add(
          Walker(rnd(s, 33) < 0.3 ? WalkerKind.briefcase : WalkerKind.plain, s, Street.busStopX + 16 + i * 6, dir, 20 + 6 * rnd(s, 34), 24 + 4 * rnd(s, 35))
            ..askedBus = true,
        );
      }
    }
    walkers.removeWhere((w) => w.fade <= 0 || w.x < -60 || w.x > 1660);
  }
}
