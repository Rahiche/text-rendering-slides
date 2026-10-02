import 'dart:math' as math;

// The city's small maths (no Flutter in it: the figures' rig and motion use
// it, and run in plain Dart for tests).

double c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double seg(double t, double a, double b) => c01((t - a) / (b - a));
double lerp(double a, double b, double t) => a + (b - a) * t;
double eio(double t) {
  t = c01(t);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

double eo(double t) => 1 - math.pow(1 - c01(t), 3).toDouble();

/// Deterministic pseudo-random in [0, 1).
double rnd(int a, [int b = 0, int c = 0]) {
  final v = math.sin(a * 12.9898 + b * 78.233 + c * 37.719 + 0.5) * 43758.5453;
  return v - v.floorToDouble();
}

/// Smoothly approaches [target] (frame-rate independent).
double approach(double v, double target, double dt, double settle) => target + (v - target) * math.exp(-dt / math.max(settle, 1e-3));

/// Hermite smoothstep of [x] between [e0] and [e1].
double smooth(double e0, double e1, double x) {
  final t = c01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}
