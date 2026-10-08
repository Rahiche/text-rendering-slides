import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';

/// A model made in Blender (tool/blender/*.py): its parts by name, as mesh
/// data in the city's frame (the import's handedness flip in their
/// vertices: Blender's x, y, z are the city's x, z, y).
Future<Map<String, MeshData>> modelParts(String asset) async {
  final bytes = await rootBundle.load(asset);
  final root = await Node.fromGlbBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  final out = <String, MeshData>{};
  void walk(Node n) {
    if (n.mesh != null) out[n.name] = n.extractMeshData(transform: n.globalTransform);
    n.children.forEach(walk);
  }

  walk(root);
  if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
    for (final MapEntry(:key, :value) in out.entries) {
      final p = value.positions;
      final lo = [double.infinity, double.infinity, double.infinity], hi = [-double.infinity, -double.infinity, -double.infinity];
      for (var i = 0; i < p.length; i++) {
        final k = i % 3;
        if (p[i] < lo[k]) lo[k] = p[i];
        if (p[i] > hi[k]) hi[k] = p[i];
      }
      String f(List<double> v) => v.map((x) => x.toStringAsFixed(3)).join(',');
      debugPrint('MODEL $asset $key: ${value.vertexCount} vertices, ${f(lo)} … ${f(hi)}');
    }
  }
  return out;
}
