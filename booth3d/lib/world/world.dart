import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';

import 'city.dart';
import 'director.dart';
import 'site.dart';
import 'sky.dart';

/// 名前の街 · Name City: the whole 3D world, driven by the booth model.
class World3D {
  final scene = Scene();
  late final city = City3D(scene);
  late final sky = Sky3D(scene);
  late final site = Site3D(scene);
  final director = Director();
  bool ready = false;

  Future<void> init() async {
    await Scene.initializeStaticResources();
    sky.init();
    site.init();
    await city.init();
    ready = true;
  }

  /// Call once per frame after stepping the model.
  void update(BoothModel m, double dt) {
    if (!ready) return;
    sky.update(m.t);
    city.update(sky.night, m.t);
    site.update(m, dt);
    director.update(m, dt, wallWidth: site.wallWidth, wallHeight: site.wallHeight);
  }
}
