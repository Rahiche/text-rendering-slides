import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Shared helpers for the 3D city: colours, materials, meshes, maths.

/// An sRGB colour as a linear RGBA factor (PBR materials work in linear).
vm.Vector4 lin(Color c, [double? alpha]) {
  double f(double v) => math.pow(v, 2.2).toDouble();
  return vm.Vector4(f(c.r), f(c.g), f(c.b), alpha ?? c.a);
}

vm.Vector4 rgb(double r, double g, double b, [double a = 1]) => vm.Vector4(r, g, b, a);

PhysicallyBasedMaterial pbr(
  vm.Vector4 color, {
  double metallic = 0,
  double roughness = 0.7,
  vm.Vector4? emissive,
  double emissiveStrength = 1,
}) {
  final m = PhysicallyBasedMaterial()
    ..baseColorFactor = color
    ..metallicFactor = metallic
    ..roughnessFactor = roughness;
  if (emissive != null) {
    m
      ..emissiveFactor = emissive
      ..emissiveStrength = emissiveStrength;
  }
  return m;
}

/// A glyph mesh (from the booth's extruder) as engine geometry.
MeshGeometry glyphGeometry(GlyphMesh m) => MeshGeometry.fromArrays(
  positions: m.positions,
  normals: m.normals,
  texCoords: m.uvs,
  indices: m.indices,
);

vm.Matrix4 trs(vm.Vector3 t, {double rotY = 0, double rotX = 0, double rotZ = 0, vm.Vector3? s}) {
  final q = vm.Quaternion.euler(rotY, rotX, rotZ);
  return vm.Matrix4.compose(t, q, s ?? vm.Vector3.all(1));
}

vm.Matrix4 trsQ(vm.Vector3 t, vm.Quaternion q, vm.Vector3 s) => vm.Matrix4.compose(t, q, s);

/// A zero-size transform (hidden instance).
final hidden = vm.Matrix4.compose(vm.Vector3(0, -1000, 0), vm.Quaternion.identity(), vm.Vector3.zero());

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
double approach(double v, double target, double dt, double settle) =>
    target + (v - target) * math.exp(-dt / math.max(settle, 1e-3));
