import 'method.dart';
import 'methods/blocks.dart';
import 'methods/bricks.dart';
import 'methods/calligraphy.dart';
import 'methods/carpentry.dart';
import 'methods/carving.dart';
import 'methods/casting.dart';
import 'methods/concrete.dart';
import 'methods/embroidery.dart';
import 'methods/kintsugi.dart';
import 'methods/laser.dart';
import 'methods/marquee.dart';
import 'methods/neon.dart';
import 'methods/print3d.dart';
import 'methods/stencil.dart';
import 'methods/topiary.dart';
import 'methods/welding.dart';

/// Every craft in the workshop. A name gets a shuffled tour of these, so no
/// craft repeats within 16 characters.
const craftMethods = <CraftMethod>[
  CalligraphyCraft(),
  WeldingCraft(),
  NeonCraft(),
  CastingCraft(),
  Print3dCraft(),
  CarvingCraft(),
  CarpentryCraft(),
  BricksCraft(),
  EmbroideryCraft(),
  LaserCraft(),
  ConcreteCraft(),
  BlocksCraft(),
  KintsugiCraft(),
  StencilCraft(),
  MarqueeCraft(),
  TopiaryCraft(),
];
