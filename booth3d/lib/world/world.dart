import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';

import 'city.dart';
import 'director.dart';
import 'life.dart';
import 'site.dart';
import 'sky.dart';
import 'typing.dart';

/// 名前の街 · Name City: the whole 3D world, driven by the booth model.
class World3D {
  final scene = Scene();
  late final city = City3D(scene);
  late final sky = Sky3D(scene);
  late final site = Site3D(scene);
  late final typing = Typing3D(scene);
  late final life = Life3D(scene);
  final director = Director();
  bool ready = false;

  Future<void> init() async {
    await Scene.initializeStaticResources();
    sky.init();
    site.init();
    typing.init();
    await city.init();
    await life.init();
    ready = true;
  }

  /// Call once per frame after stepping the model.
  void update(BoothModel m, double dt) {
    if (!ready) return;
    sky.update(m.t, dt);
    city.update(sky, m.t);
    site.fx.begin();
    site.update(m, dt, night: sky.night);
    typing
      ..attach(BoothUi.of(m))
      ..update(m, dt, site.fx);
    site.fx.end();
    director
      ..typingWeight = typing.weight
      ..night = sky.night
      ..update(m, dt, site);
    life.update(m, dt, camera: director.camera.position, wallWidth: site.wallWidth, night: sky.night);
  }
}
