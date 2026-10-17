import 'dart:convert' show json, utf8;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// A rigged person's mesh: their parts (the body, each garment, the city's
// head and hair) put together into one skinned mesh, one draw, its cloth
// from one atlas (tool/blender/people_atlas.py) and its colours (skin, hair,
// a tinted garment) in the vertices.

/// One skinned part, as its glTF has it (model space): places, normals,
/// UVs, tangents, four bones and weights a vertex; triangles; colours if
/// it has its own (the head's shading).
class RigPart {
  RigPart(this.name, this.positions, this.normals, this.uvs, this.tangents, this.joints, this.weights, this.indices, [this.colors]);

  final String name;
  final Float32List positions, normals, uvs, tangents, weights;
  final Uint16List joints;
  final Uint32List indices;
  final Float32List? colors;

  int get vertexCount => positions.length ~/ 3;

  /// The city's head part [d] (people.glb's, in the city's frame: modelled
  /// for a figure of size 1, its origin at the neck's base) hung on bone
  /// [joint]: at the model-space [neck], [size] times its size, the
  /// import's flip undone (and so the triangles' winding).
  static RigPart head(String name, MeshData d, int joint, vm.Vector3 neck, double size) {
    final n = d.vertexCount, p = d.positions, nr = d.normals;
    final positions = Float32List(n * 3), normals = Float32List(n * 3), uvs = Float32List(n * 2), tangents = Float32List(n * 4);
    final joints = Uint16List(n * 4), weights = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      positions[i * 3] = neck.x + size * p[i * 3];
      positions[i * 3 + 1] = neck.y + size * p[i * 3 + 1];
      positions[i * 3 + 2] = neck.z - size * p[i * 3 + 2];
      if (nr != null) {
        normals[i * 3] = nr[i * 3];
        normals[i * 3 + 1] = nr[i * 3 + 1];
        normals[i * 3 + 2] = -nr[i * 3 + 2];
      }
      uvs[i * 2] = uvs[i * 2 + 1] = 0.5;
      tangents[i * 4] = 1;
      tangents[i * 4 + 3] = 1;
      joints[i * 4] = joint;
      weights[i * 4] = 1;
    }
    final src = d.indices ?? List<int>.generate(n, (i) => i);
    final indices = Uint32List(src.length);
    for (var i = 0; i + 2 < src.length; i += 3) {
      indices[i] = src[i];
      indices[i + 1] = src[i + 2];
      indices[i + 2] = src[i + 1];
    }
    return RigPart(name, positions, normals, uvs, tangents, joints, weights, indices, d.colors);
  }
}

/// A person's glTF (tool/blender/humans.py): each mesh node's part, and the
/// skin: its bones' names and inverse bind matrices.
class RigMeshes {
  RigMeshes._(this.parts, this.joints, this.inverseBinds);

  final Map<String, RigPart> parts;
  final List<String> joints;
  final List<vm.Matrix4> inverseBinds;

  static RigMeshes parse(Uint8List glb) {
    final data = ByteData.sublistView(glb);
    final jlen = data.getUint32(12, Endian.little);
    final g = json.decode(utf8.decode(glb.sublist(20, 20 + jlen))) as Map<String, dynamic>;
    final bin = 20 + jlen + 8;
    final nodes = (g['nodes'] as List).cast<Map<String, dynamic>>();
    final accessors = (g['accessors'] as List).cast<Map<String, dynamic>>();
    final views = (g['bufferViews'] as List).cast<Map<String, dynamic>>();
    const comps = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16};
    const sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4};

    // Accessor [i]'s values, as doubles (normalised integers scaled).
    List<double> read(int i) {
      final a = accessors[i], v = views[a['bufferView'] as int];
      final n = a['count'] as int, c = comps[a['type']]!, type = a['componentType'] as int, size = sizes[type]!;
      final start = bin + (v['byteOffset'] as int? ?? 0) + (a['byteOffset'] as int? ?? 0);
      final stride = v['byteStride'] as int? ?? c * size;
      final norm = a['normalized'] == true;
      final out = List<double>.filled(n * c, 0);
      for (var k = 0; k < n; k++) {
        for (var j = 0; j < c; j++) {
          final at = start + k * stride + j * size;
          out[k * c + j] = switch (type) {
            5126 => data.getFloat32(at, Endian.little),
            5121 => norm ? data.getUint8(at) / 255 : data.getUint8(at).toDouble(),
            5123 => norm ? data.getUint16(at, Endian.little) / 65535 : data.getUint16(at, Endian.little).toDouble(),
            5125 => data.getUint32(at, Endian.little).toDouble(),
            _ => throw UnsupportedError('glTF component type $type'),
          };
        }
      }
      return out;
    }

    final parts = <String, RigPart>{};
    for (final n in nodes) {
      final m = n['mesh'] as int?;
      if (m == null) continue;
      final prim = ((g['meshes'] as List)[m]['primitives'] as List).first as Map<String, dynamic>;
      final at = (prim['attributes'] as Map).cast<String, int>();
      final count = accessors[at['POSITION']!]['count'] as int;
      Float32List f32(String key, int width, [double fill = 0]) =>
          at.containsKey(key) ? Float32List.fromList(read(at[key]!)) : (Float32List(count * width)..fillRange(0, count * width, fill));
      final tangents = at.containsKey('TANGENT') ? f32('TANGENT', 4) : (Float32List(count * 4)..setAll(0, [for (var i = 0; i < count; i++) ...[1.0, 0.0, 0.0, 1.0]]));
      final idx = prim['indices'] as int?;
      parts[n['name'] as String] = RigPart(
        n['name'] as String,
        f32('POSITION', 3),
        f32('NORMAL', 3),
        f32('TEXCOORD_0', 2),
        tangents,
        Uint16List.fromList([for (final v in read(at['JOINTS_0']!)) v.round()]),
        f32('WEIGHTS_0', 4),
        idx == null ? Uint32List.fromList(List.generate(count, (i) => i)) : Uint32List.fromList([for (final v in read(idx)) v.round()]),
      );
    }
    final skin = (g['skins'] as List).first as Map<String, dynamic>;
    final joints = [for (final j in (skin['joints'] as List).cast<int>()) nodes[j]['name'] as String];
    final ibm = read(skin['inverseBindMatrices'] as int);
    final binds = [for (var i = 0; i < joints.length; i++) vm.Matrix4.fromList(ibm.sublist(i * 16, i * 16 + 16))];
    return RigMeshes._(parts, joints, binds);
  }
}

/// Where each garment is in the atlas (atlas.json), and how it's tinted.
class RigAtlas {
  RigAtlas(Map<String, dynamic> j)
    : cols = j['cols'] as int,
      rows = j['rows'] as int,
      grey = (j['grey'] as num).toDouble(),
      tiles = (j['tiles'] as Map).cast<String, int>(),
      tinted = {...(j['tinted'] as List).cast<String>()};

  final int cols, rows;
  final double grey;
  final Map<String, int> tiles;
  final Set<String> tinted;
}

/// One part of a person's mesh as they wear it: in which of the atlas's
/// tiles its UVs are, and its colour (times the part's own, if it has
/// them).
typedef RigPiece = (RigPart part, int tile, vm.Vector4 color);

/// The skinned mesh of [pieces] together (their vertices one after the
/// other: their bones are the same skin's).
int rigGeometries = 0;

SkinnedGeometry rigGeometry(List<RigPiece> pieces, RigAtlas atlas) {
  rigGeometries++;
  var n = 0, m = 0;
  for (final (p, _, _) in pieces) {
    n += p.vertexCount;
    m += p.indices.length;
  }
  final v = Float32List(n * 26);
  final wide = n > 65535;
  final ix = wide ? Uint32List(m) : Uint16List(m);
  // (UVs kept two texels inside their tile: mipmaps don't bleed in from the
  // next.)
  const inset = 2 / 512;
  var base = 0, at = 0;
  final lo = vm.Vector3.all(double.infinity), hi = vm.Vector3.all(-double.infinity);
  for (final (p, tile, c) in pieces) {
    final col = tile % atlas.cols, row = tile ~/ atlas.cols, cols = atlas.cols.toDouble(), rows = atlas.rows.toDouble();
    final k = p.colors;
    for (var i = 0; i < p.vertexCount; i++) {
      final o = (base + i) * 26;
      final x = p.positions[i * 3], y = p.positions[i * 3 + 1], z = p.positions[i * 3 + 2];
      v[o] = x;
      v[o + 1] = y;
      v[o + 2] = z;
      lo.setValues(math.min(lo.x, x), math.min(lo.y, y), math.min(lo.z, z));
      hi.setValues(math.max(hi.x, x), math.max(hi.y, y), math.max(hi.z, z));
      v[o + 3] = p.normals[i * 3];
      v[o + 4] = p.normals[i * 3 + 1];
      v[o + 5] = p.normals[i * 3 + 2];
      final u = p.uvs[i * 2].clamp(0.0, 1.0), w = p.uvs[i * 2 + 1].clamp(0.0, 1.0);
      v[o + 6] = (col + inset + u * (1 - 2 * inset)) / cols;
      v[o + 7] = (row + inset + w * (1 - 2 * inset)) / rows;
      // (o + 8, 9: the second UVs, unused.)
      v[o + 10] = c.x * (k == null ? 1 : k[i * 4]);
      v[o + 11] = c.y * (k == null ? 1 : k[i * 4 + 1]);
      v[o + 12] = c.z * (k == null ? 1 : k[i * 4 + 2]);
      v[o + 13] = 1;
      for (var j = 0; j < 4; j++) {
        v[o + 14 + j] = p.tangents[i * 4 + j];
        v[o + 18 + j] = p.joints[i * 4 + j].toDouble();
        v[o + 22 + j] = p.weights[i * 4 + j];
      }
    }
    for (final t in p.indices) {
      ix[at++] = base + t;
    }
    base += p.vertexCount;
  }
  final g = SkinnedGeometry()
    ..uploadVertexData(
      ByteData.sublistView(v),
      n,
      ByteData.sublistView(ix),
      indexType: wide ? gpu.IndexType.int32 : gpu.IndexType.int16,
    );
  // (Wherever the bones take it, a person stays within this.)
  final mid = (lo + hi) * 0.5;
  final box = vm.Aabb3.minMax(vm.Vector3(lo.x - 1, lo.y - 0.6, lo.z - 1), vm.Vector3(hi.x + 1, hi.y + 0.6, hi.z + 1));
  g.setLocalBounds(box, vm.Sphere.centerRadius(mid, (box.max - box.min).length / 2));
  return g;
}
