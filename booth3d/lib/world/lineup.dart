import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';

import 'ease.dart' show smooth;
import 'figure.dart';
import 'kit.dart' show lerp;
import 'motion.dart';

/// Capture aid: --dart-define=BOOTH3D_LINEUP=x,z stands a row of the city's
/// people there (a metre apart along x, facing −z: an office worker, a
/// worker in hi-vis, a schoolchild, a woman in a long coat…) to check how
/// they're drawn. Every 4 s they turn on round: their front, three
/// quarters, their side, their back; the last walks on the spot.
class Lineup {
  Lineup._(Scene scene, this.x, this.z) : _figures = Figures.of(scene) {
    for (final l in _looks()) {
      _slots.add(_figures.add(l));
      _poses.add(FigurePose());
    }
  }

  /// The lineup the define asks for (null: none).
  static Lineup? of(Scene scene) {
    const at = String.fromEnvironment('BOOTH3D_LINEUP');
    if (at.isEmpty) return null;
    final v = at.split(',').map(double.parse).toList();
    return Lineup._(scene, v[0], v[1]);
  }

  final double x, z;
  final Figures _figures;
  final _slots = <int>[];
  final _poses = <FigurePose>[];

  static const _yaws = [0.0, 0.75, math.pi / 2, math.pi];

  void update(double t) {
    final step = (t / 4).floor(), f = smooth(0, 0.8, t - step * 4);
    final yaw = lerp(_yaws[(step + 3) % 4], _yaws[step % 4], f);
    final n = _slots.length;
    for (var i = 0; i < n; i++) {
      final look = _figures.lookOf(_slots[i]), m = Manner.of(300 + i);
      final p = _poses[i]..rest();
      p
        ..steer = false
        ..yaw = yaw;
      p.pos.setValues(x + (i - (n - 1) / 2) * 1.0, 0, z);
      if (i == n - 1) {
        Gait.walk(p, Gait.phaseAt(t * 1.3, 1.3, look.size, m), 1.3, m, size: look.size);
      } else {
        Idle.stand(p, t, m, size: look.size, look: 0.3);
      }
      _figures.draw(_slots[i], p);
    }
  }

  static List<FigureLook> _looks() => [
    // An office worker: an open navy jacket over a white shirt.
    FigureLook()
      ..skin = rgbHex(0xE0BB9E)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = Hair.short
      ..top = rgbHex(0xF2F0EA)
      ..sleeves = rgbHex(0x2B3A55)
      ..layer = rgbHex(0x2B3A55)
      ..legs = rgbHex(0x1E2B40)
      ..shoes = rgbHex(0x1B1C20)
      ..bag = rgbHex(0x1F2229),
    // A woman in a coral jumper and a skirt, long hair.
    FigureLook()
      ..slim = true
      ..skin = rgbHex(0xEFD0BA)
      ..hairColor = rgbHex(0x3D2B20)
      ..hair = Hair.long
      ..top = rgbHex(0xE58F6E)
      ..skirt = rgbHex(0x24304A)
      ..legs = rgbHex(0x2A2A30)
      ..shins = rgbHex(0x2A2A30)
      ..shoes = rgbHex(0x5A3A26),
    // The crew: hi-vis over navy, a hard hat, gloves.
    FigureLook()
      ..skin = rgbHex(0xC59A7C)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = Hair.short
      ..top = rgbHex(0x3E4A5E)
      ..layer = rgbHex(0xFFB020)
      ..stripes = true
      ..gloves = rgbHex(0xE9E4D6)
      ..hardHat = rgbHex(0xFFD23F)
      ..legs = rgbHex(0x2B3A55)
      ..shoes = rgbHex(0x24211F),
    // A schoolchild: a cap, a randoseru.
    FigureLook()
      ..size = 0.72
      ..girth = 0.95
      ..skin = rgbHex(0xF3D8C6)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = Hair.short
      ..top = rgbHex(0x6CB59A)
      ..legs = rgbHex(0x2E4766)
      ..shoes = rgbHex(0xEDEDEA)
      ..cap = rgbHex(0xF5D33C)
      ..backpack = rgbHex(0xB0222D),
    // A woman in a long camel coat, a bob.
    FigureLook()
      ..slim = true
      ..skin = rgbHex(0xE8C6AC)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = Hair.bob
      ..top = rgbHex(0xC8B79A)
      ..skirt = rgbHex(0xC8B79A)
      ..skirtLength = 1.2
      ..legs = rgbHex(0x1C1F26)
      ..shoes = rgbHex(0x1B1C20),
    // An older man, grey hair, a cardigan.
    FigureLook()
      ..girth = 1.12
      ..skin = rgbHex(0xE4C2A6)
      ..hairColor = rgbHex(0x8F8B86)
      ..hair = Hair.medium
      ..top = rgbHex(0x6B7B5A)
      ..legs = rgbHex(0xB5A27E)
      ..shoes = rgbHex(0x8C5A3C),
    // A man in a T-shirt, bare arms.
    FigureLook()
      ..skin = rgbHex(0x8E644B)
      ..hairColor = rgbHex(0x1A1714)
      ..hair = Hair.short
      ..top = rgbHex(0x2E6DA8)
      ..bareArms = true
      ..legs = rgbHex(0x5E6470)
      ..shoes = rgbHex(0xEDEDEA),
    // Walking: a student, a medium cut, a backpack.
    FigureLook()
      ..skin = rgbHex(0xD6AE90)
      ..hairColor = rgbHex(0x2A211B)
      ..hair = Hair.medium
      ..top = rgbHex(0x7A2E3A)
      ..legs = rgbHex(0x2E4766)
      ..shoes = rgbHex(0xEDEDEA)
      ..backpack = rgbHex(0x23262D),
  ];
}
