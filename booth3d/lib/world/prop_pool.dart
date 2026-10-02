import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_geo.dart';

/// Small moving props drawn instanced, re-placed every frame: lit boxes and
/// cylinders (coloured per instance) and glowing boxes (unlit, HDR colours).
/// Three draws for the lot, none while a kind is unused. Call [begin], add,
/// then [end] once per frame.
///
/// Unused instances are parked (shrunk to nothing) at [home] rather than far
/// away, so the batches' bounds stay where the props are and they're culled
/// when out of view. Nothing here casts a shadow.
class PropPool {
  PropPool(this.scene, this.name, {required this.home, this.maxBoxes = 128, this.maxCyls = 32, this.maxGlows = 32, this.parent});

  final Scene scene;

  /// Where its nodes go (null: the scene's root).
  final Node? parent;
  final String name;
  final vm.Vector3 home;
  final int maxBoxes, maxCyls, maxGlows;

  late final InstancedMesh _boxes, _cyls, _glows;
  final _nodes = <Node>[];
  int _nBox = 0, _nCyl = 0, _nGlow = 0, _hiBox = 0, _hiCyl = 0, _hiGlow = 0;
  late final vm.Matrix4 _parked = vm.Matrix4.compose(home, vm.Quaternion.identity(), vm.Vector3.zero());

  void init() {
    InstancedMesh pool(Geometry g, Material m, int n, String what) {
      final im = InstancedMesh(geometry: g, material: m);
      for (var i = 0; i < n; i++) {
        im.addInstance(_parked);
      }
      final node = Node(name: '$name $what')
        ..addComponent(InstancedMeshComponent(im))
        ..castsShadows = false
        ..visible = false;
      _nodes.add(node);
      final p = parent;
      if (p != null) {
        p.add(node);
      } else {
        scene.add(node);
      }
      return im;
    }

    _boxes = pool(CuboidGeometry(vm.Vector3.all(1)), pbr(rgb(1, 1, 1), roughness: 0.5, metallic: 0.2), maxBoxes, 'boxes');
    _cyls = pool(
      CylinderGeometry(bottomRadius: 1, topRadius: 1, height: 1, radialSegments: 14),
      pbr(rgb(1, 1, 1), roughness: 0.45, metallic: 0.25),
      maxCyls,
      'cylinders',
    );
    _glows = pool(CuboidGeometry(vm.Vector3.all(1)), UnlitMaterial(), maxGlows, 'glows');
  }

  void begin() => _nBox = _nCyl = _nGlow = 0;

  void end() {
    for (var i = _nBox; i < _hiBox; i++) {
      _boxes.setInstanceTransform(i, _parked);
    }
    for (var i = _nCyl; i < _hiCyl; i++) {
      _cyls.setInstanceTransform(i, _parked);
    }
    for (var i = _nGlow; i < _hiGlow; i++) {
      _glows.setInstanceTransform(i, _parked);
    }
    _hiBox = _nBox;
    _hiCyl = _nCyl;
    _hiGlow = _nGlow;
    _nodes[0].visible = _nBox > 0;
    _nodes[1].visible = _nCyl > 0;
    _nodes[2].visible = _nGlow > 0;
  }

  final _m = vm.Matrix4.identity();
  final _q = vm.Quaternion.identity();

  vm.Matrix4 _at(double x, double y, double z, double sx, double sy, double sz, double yaw, double pitch, double roll) {
    _q.setEuler(yaw, pitch, roll);
    return setTqs(_m, x, y, z, _q, sx, sy, sz);
  }

  /// A box [sx]×[sy]×[sz] centred at (x, y, z), turned by yaw/pitch/roll.
  void box(double x, double y, double z, double sx, double sy, double sz, vm.Vector4 color, {double yaw = 0, double pitch = 0, double roll = 0}) {
    if (_nBox >= maxBoxes || sx <= 0 || sy <= 0 || sz <= 0) return;
    _boxes.setInstanceTransform(_nBox, _at(x, y, z, sx, sy, sz, yaw, pitch, roll));
    _boxes.setInstanceColor(_nBox, color);
    _nBox++;
  }

  /// An upright cylinder of radius [r] and height [h] centred at (x, y, z),
  /// turned by yaw/pitch/roll.
  void cyl(double x, double y, double z, double r, double h, vm.Vector4 color, {double yaw = 0, double pitch = 0, double roll = 0}) {
    if (_nCyl >= maxCyls || r <= 0 || h <= 0) return;
    _cyls.setInstanceTransform(_nCyl, _at(x, y, z, r, h, r, yaw, pitch, roll));
    _cyls.setInstanceColor(_nCyl, color);
    _nCyl++;
  }

  /// A rod of radius [r] from [a] to [b].
  void rod(vm.Vector3 a, vm.Vector3 b, double r, vm.Vector4 color) {
    if (_nCyl >= maxCyls) return;
    _cyls.setInstanceTransform(_nCyl, setSpan(_m, a, b, thickness: r));
    _cyls.setInstanceColor(_nCyl, color);
    _nCyl++;
  }

  /// A glowing box (unlit: [color] is linear HDR, brighter than 1 blooms).
  void glow(double x, double y, double z, double sx, double sy, double sz, vm.Vector4 color, {double yaw = 0, double pitch = 0, double roll = 0}) {
    if (_nGlow >= maxGlows || sx <= 0 || sy <= 0 || sz <= 0) return;
    _glows.setInstanceTransform(_nGlow, _at(x, y, z, sx, sy, sz, yaw, pitch, roll));
    _glows.setInstanceColor(_nGlow, color);
    _nGlow++;
  }
}
