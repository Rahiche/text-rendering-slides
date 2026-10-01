import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show Image, ImageByteFormat, PictureRecorder;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart' show Canvas, Offset, Size, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/geometry.dart';
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

// ── Colour ─────────────────────────────────────────────────────────────────

/// An sRGB colour as a linear RGB vector (for skies, fog, lights).
vm.Vector3 lin3(Color c, [double k = 1]) {
  double f(double v) => math.pow(v, 2.2).toDouble() * k;
  return vm.Vector3(f(c.r), f(c.g), f(c.b));
}

/// 0xRRGGBB (sRGB) as a linear RGB vector.
vm.Vector3 hex3(int rgb, [double k = 1]) => lin3(Color(0xFF000000 | rgb), k);

vm.Vector3 mix3(vm.Vector3 a, vm.Vector3 b, double t) =>
    vm.Vector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

vm.Vector4 v4(vm.Vector3 c, [double a = 1]) => vm.Vector4(c.x, c.y, c.z, a);

/// Hermite smoothstep of [x] between [e0] and [e1].
double smooth(double e0, double e1, double x) {
  final t = c01((x - e0) / (e1 - e0));
  return t * t * (3 - 2 * t);
}

// ── Transforms written in place (per-frame instance updates, no garbage) ──

/// [m] = translate(x, y, z) · rotateY(rotY) · scale(s).
void setTrsY(vm.Matrix4 m, double x, double y, double z, double rotY, [double s = 1]) {
  final c = math.cos(rotY) * s, n = math.sin(rotY) * s;
  m.storage
    ..[0] = c
    ..[1] = 0
    ..[2] = -n
    ..[3] = 0
    ..[4] = 0
    ..[5] = s
    ..[6] = 0
    ..[7] = 0
    ..[8] = n
    ..[9] = 0
    ..[10] = c
    ..[11] = 0
    ..[12] = x
    ..[13] = y
    ..[14] = z
    ..[15] = 1;
}

/// [m] = translate · rotateY(rotY) · rotateZ(rotZ) · scale(s): a part that
/// swings about its owner's sideways axis (legs, arms).
void setTrsYZ(vm.Matrix4 m, double x, double y, double z, double rotY, double rotZ, [double s = 1]) {
  final c = math.cos(rotY), n = math.sin(rotY), cz = math.cos(rotZ), sz = math.sin(rotZ);
  m.storage
    ..[0] = c * cz * s
    ..[1] = sz * s
    ..[2] = -n * cz * s
    ..[3] = 0
    ..[4] = -c * sz * s
    ..[5] = cz * s
    ..[6] = n * sz * s
    ..[7] = 0
    ..[8] = n * s
    ..[9] = 0
    ..[10] = c * s
    ..[11] = 0
    ..[12] = x
    ..[13] = y
    ..[14] = z
    ..[15] = 1;
}

/// [m] = translate · rotateY(rotY) · rotateX(rotX) · scale(s): a part that
/// rolls about its owner's forward (+X) axis (wings).
void setTrsYX(vm.Matrix4 m, double x, double y, double z, double rotY, double rotX, [double s = 1]) {
  final c = math.cos(rotY), n = math.sin(rotY), cx = math.cos(rotX), sx = math.sin(rotX);
  m.storage
    ..[0] = c * s
    ..[1] = 0
    ..[2] = -n * s
    ..[3] = 0
    ..[4] = n * sx * s
    ..[5] = cx * s
    ..[6] = c * sx * s
    ..[7] = 0
    ..[8] = n * cx * s
    ..[9] = -sx * s
    ..[10] = c * cx * s
    ..[11] = 0
    ..[12] = x
    ..[13] = y
    ..[14] = z
    ..[15] = 1;
}

/// Heading (rotY) that turns local +X towards the direction (dx, dz).
double headingTo(double dx, double dz) => math.atan2(-dz, dx);

// ── Meshes ────────────────────────────────────────────────────────────────

/// [g]'s triangles moved by [xf] and painted [color] (vertex colours), ready
/// to merge with other parts into one geometry.
MeshData part(MeshGeometry g, vm.Matrix4 xf, [vm.Vector4? color]) {
  final d = g.extractMeshData().transformed(xf);
  final c = color ?? vm.Vector4(1, 1, 1, 1);
  final colors = Float32List(d.vertexCount * 4);
  for (var i = 0; i < d.vertexCount; i++) {
    colors
      ..[i * 4] = c.x
      ..[i * 4 + 1] = c.y
      ..[i * 4 + 2] = c.z
      ..[i * 4 + 3] = c.w;
  }
  return MeshData(
    positions: d.positions,
    vertexCount: d.vertexCount,
    normals: d.normals,
    texCoords: d.texCoords ?? Float32List(d.vertexCount * 2),
    colors: colors,
    indices: d.indices,
  );
}

/// Several [part]s as one geometry (one draw).
MeshGeometry merged(List<MeshData> parts) => MeshGeometry.fromMeshData(MeshData.merge(parts));

// ── Text → outlines → solid 3D text ───────────────────────────────────────

/// What to extrude: [text] in [style] (rendered at the style's size),
/// [height] world units tall (ink), [depth] thick.
class TextSolid {
  const TextSolid(this.text, this.style, {required this.height, required this.depth, this.simplify = 0.8});
  final String text;
  final TextStyle style;
  final double height;
  final double depth;
  final double simplify;
}

class _SolidJob {
  _SolidJob(this.input, this.height, this.depth, this.simplify);
  final VectorizeInput input;
  final double height, depth, simplify;
}

/// Each [TextSolid] rendered whole with the real text stack (so scripts are
/// shaped: Arabic joins, Devanagari conjuncts…), traced to outlines and
/// extruded to a solid on a background isolate. Empty text gives an empty
/// mesh.
Future<List<GlyphMesh>> extrudeTexts(List<TextSolid> specs) async {
  const pad = 6;
  final jobs = <_SolidJob>[];
  for (final s in specs) {
    final tp = TextPainter(
      text: TextSpan(text: s.text, style: s.style.copyWith(color: const Color(0xFFFFFFFF))),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width.ceil() + 2 * pad, h = tp.height.ceil() + 2 * pad;
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), const Offset(6, 6));
    tp.dispose();
    final image = await rec.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final rgba = data!.buffer.asUint8List();
    final alpha = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      alpha[i] = rgba[i * 4 + 3];
    }
    jobs.add(_SolidJob(VectorizeInput(w, h, alpha), s.height, s.depth, s.simplify));
  }
  return compute(_solids, jobs);
}

List<GlyphMesh> _solids(List<_SolidJob> jobs) => [
  for (final j in jobs)
    () {
      final g = _outline(j.input);
      if (g.isEmpty) return extrudeGlyph(g);
      return extrudeGlyph(g, unitsPerPx: j.height / g.inkHeight, depth: j.depth, simplify: j.simplify);
    }(),
];

GlyphGeometry _outline(VectorizeInput input) {
  final w = input.w, h = input.h, a = input.alpha;
  var l = w, t = h, r = -1, b = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (a[y * w + x] >= 128) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  final empty = r < 0;
  return GlyphGeometry(
    w: w,
    h: h,
    contours: empty ? const [] : traceContours(w, h, a),
    strokes: const [],
    spans: const [],
    inkLeft: empty ? 0 : l.toDouble(),
    inkTop: empty ? 0 : t.toDouble(),
    inkRight: empty ? 0 : r + 1.0,
    inkBottom: empty ? 0 : b + 1.0,
  );
}

/// A thin board [w]×[h] whose front (−Z, the side the camera sees) shows a
/// whole texture upright; its edges and back take the texture's corner.
MeshGeometry boardGeometry(double w, double h, {double thick = 0.05}) {
  final d = CuboidGeometry(vm.Vector3(w, h, thick)).extractMeshData();
  final uv = d.texCoords!, n = d.normals!, p = d.positions;
  for (var i = 0; i < d.vertexCount; i++) {
    if (n[i * 3 + 2] < -0.5) {
      uv[i * 2] = p[i * 3] / w + 0.5;
      uv[i * 2 + 1] = 0.5 - p[i * 3 + 1] / h;
    } else {
      uv[i * 2] = 0.01;
      uv[i * 2 + 1] = 0.01;
    }
  }
  return MeshGeometry.fromMeshData(d);
}

/// A texture painted with a Flutter canvas ([w]×[h] px).
Future<Texture2D> paintedTexture(int w, int h, void Function(Canvas c, Size s) paint) async {
  final rec = ui.PictureRecorder();
  paint(Canvas(rec), Size(w.toDouble(), h.toDouble()));
  final ui.Image image = await rec.endRecording().toImage(w, h);
  try {
    return await Texture2D.fromImage(image);
  } finally {
    image.dispose();
  }
}

// ── Batching static geometry ───────────────────────────────────────────────

/// [d] painted [color] (vertex colours) with texture coordinates present, so
/// it merges with any other part.
MeshData painted(MeshData d, vm.Vector4 color, {Float32List? uvs}) {
  final colors = Float32List(d.vertexCount * 4);
  for (var i = 0; i < d.vertexCount; i++) {
    colors
      ..[i * 4] = color.x
      ..[i * 4 + 1] = color.y
      ..[i * 4 + 2] = color.z
      ..[i * 4 + 3] = color.w;
  }
  return MeshData(
    positions: d.positions,
    vertexCount: d.vertexCount,
    normals: d.normals,
    texCoords: uvs ?? d.texCoords ?? Float32List(d.vertexCount * 2),
    colors: colors,
    indices: d.indices,
  );
}

/// A glyph mesh's triangles [indices] as mesh data with [uvs].
MeshData glyphData(GlyphMesh m, List<int> indices, Float32List uvs) => MeshData(
  positions: m.positions,
  vertexCount: m.vertexCount,
  normals: m.normals,
  texCoords: uvs,
  indices: indices,
);

/// Static parts gathered per material and merged, so a whole district is a
/// handful of draws (the engine encodes every draw in every pass: colour,
/// depth, each shadow cascade).
class Batch {
  final _parts = <Material, List<MeshData>>{};

  void add(Material m, MeshData d) => (_parts[m] ??= []).add(d);

  /// Adds one merged node per material to [scene].
  void build(Scene scene, String name, {bool castsShadows = true, int lightChannelMask = 0xFF}) {
    for (final e in _parts.entries) {
      scene.add(
        Node(name: name, mesh: Mesh(merged(e.value), e.key))
          ..castsShadows = castsShadows
          ..lightChannelMask = lightChannelMask,
      );
    }
    _parts.clear();
  }
}

/// A strip of flat colours as a texture ([px] px per colour, [rows] tall,
/// each row scaled by [profile]), so differently coloured parts can share
/// one material: point a part's u at its colour with [swatchU].
Texture2D swatchTexture(List<vm.Vector3> colors, {int px = 8, int rows = 4, double Function(double v)? profile}) {
  final w = colors.length * px;
  final out = Uint8List(w * rows * 4);
  for (var y = 0; y < rows; y++) {
    final k = profile?.call((y + 0.5) / rows) ?? 1.0;
    for (var x = 0; x < w; x++) {
      final c = colors[x ~/ px];
      final i = (y * w + x) * 4;
      // Linear colour stored as sRGB (the sampler linearises it).
      int enc(double v) => (math.pow(c01(v * k), 1 / 2.2) * 255).round();
      out
        ..[i] = enc(c.x)
        ..[i + 1] = enc(c.y)
        ..[i + 2] = enc(c.z)
        ..[i + 3] = 255;
    }
  }
  return Texture2D.fromPixels(out, w, rows, sampling: const TextureSampling(maxMipmapLevels: 4));
}

/// The u of colour [i] of [n] in a [swatchTexture].
double swatchU(int i, int n) => (i + 0.5) / n;
