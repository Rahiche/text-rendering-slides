import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextDirection, TextSelection;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart';
import 'package:text_slides/booth/craft/geometry.dart';
import 'package:text_slides/booth/craft/plan.dart' show vectorizeText, craftRasterSize, rasterPad;
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart';
import 'delivery.dart';
import 'glyph_works.dart';
import 'kit.dart';
import 'life.dart' show StreetWork;
import 'photo_op.dart';
import 'physics.dart';
import 'prop_pool.dart';
import 'scene_caption.dart';
import 'script_alley.dart';
import 'shot.dart';
import 'site_crane.dart';
import 'site_finish.dart';
import 'site_fx.dart';
import 'site_geo.dart';
import 'site_kern.dart';
import 'site_lights.dart';
import 'site_loader.dart';
import 'site_plan.dart';
import 'site_plinths.dart';
import 'site_props.dart';
import 'site_wreck.dart';
import 'v_atlas.dart';
import 'v_bidi.dart';
import 'v_family.dart';
import 'v_farm.dart';
import 'v_forge.dart';
import 'v_gym.dart';
import 'v_hyphen.dart';
import 'v_itemize.dart';
import 'v_locale.dart';
import 'v_relay.dart';
import 'v_ruby.dart';
import 'v_tofu.dart';
import 'v_tower.dart';
import 'v_tram.dart';
import 'verdict.dart';
import 'vignette.dart';

/// The name being built in the plaza.
///
/// A tower crane brings the name's bricks (its real raster pixels) from the
/// yard on pallets, a letter's worth a trip, and drops them onto the piles
/// of the builders on a climbing platform behind the wall. The name goes up
/// one letter at a time, left to right: the builders whose stretch of wall
/// it covers lay it bottom-up, a little too far right; then two of them
/// stretch a measuring tape across the gap to the letter before, the
/// foreman checks his clipboard, and they push the letter along its skid
/// into its kerned place (the camera comes in close, a caption gives the
/// pair's kerning). Then the crew finish it (site_finish.dart): plasterers
/// smooth the stair-stepped edges (pixels → outlines) and painters roll each
/// letter its colour, top-down; fireworks burst (some in the shapes of the
/// name's own characters), confetti flies and the crane lowers a 完成！
/// sign; a wrecking ball swings through the wall, knocking down painted
/// bricks, and a recycling truck hauls the rubble away. Meanwhile a
/// delivery truck brings the pallets (delivery.dart), builders the build
/// doesn't need go for a coffee, a smoke or a chat (crew_breaks.dart,
/// site_props.dart), and the Glyph Works crafts a mini name in gold, letter
/// by letter with the wall (glyph_works.dart).
class Site3D {
  Site3D(this.scene);

  final Scene scene;

  late final crane = Crane3D(scene);
  late final crew = Crew3D(scene);
  late final fx = Fx3D(scene);
  late final lights = SiteLights(scene);
  late final props = SiteProps(scene);
  late final breaks = CrewBreaks(scene, fx, crew);
  late final delivery = Delivery3D(scene, crew, breaks);

  /// Small moving props of the works and the scenes round the finished
  /// name (one pool: three draws).
  late final parts = PropPool(scene, 'site parts', home: vm.Vector3(WorksLayout.cx, 0.5, WorksLayout.z1 - 1));
  late final works = GlyphWorks(scene, crew, fx, parts);

  /// The finale: the team's photo with the mini name.
  late final photo = PhotoOp(crew, works, fx, parts);

  /// Before the wrecking ball: the new manager with the next blueprint.
  late final verdict = Verdict3D(scene, crew, parts);

  /// After the last brick: plaster and paint.
  late final finish = Finish3D(scene, crew, fx);

  /// 文字横丁 · Script Alley in the park: a stall for each rule a script
  /// breaks (built by the world, as it waits for its letters).
  late final alley = ScriptAlley(scene, fx);

  /// The rest of the mini world: small scenes round the city, each acting
  /// out an idea from the talk (vignette.dart); the camera visits one or
  /// two each build, and all of them in turn while no one's name is up.
  late final vignettes = Vignettes(
    scene,
    fx,
    crew,
    (kit) => [
      TofuShop(kit),
      LineTram(kit),
      LigatureForge(kit),
      UnicodeTower(kit),
      ZwjFamily(kit),
      WeightGym(kit),
      BidiWorks(kit),
      GlyphAtlas(kit),
      PixelFarm(kit),
      TextRelay(kit),
      ItemizeWorks(kit),
      LocaleOffice(kit),
      RubyCable(kit),
      HyphenMill(kit),
    ],
  );

  /// Where the camera was last frame (set by the world).
  final camera = vm.Vector3(0, 8, -30);

  /// The kerning step's props, and its caption (for the 2D overlay).
  late final kern = Kern3D(scene);

  // Every brick of the name, wherever it is (yard, crane, pile, wall…).
  late final InstancedMesh _bricks;
  late final InstancedMesh _pallets;
  static const _maxPallets = 12;

  // Smooth letters (and their shapes, for the works' mini name).
  final _letterRoot = Node(name: 'letters');
  final _letters = <_Letter>[];
  final _shapes = <LetterShape>[];

  // 完成！ sign and the recycling truck.
  final _banner = Node(name: 'banner 完成');
  final _truck = Node(name: 'truck');

  /// The truck's body (sprung: it dips when it brakes) and its wheels
  /// (rolling; the front pair steers): node, axle x, side z.
  final _truckBody = Node(name: 'truck body');
  final _truckWheels = <(Node, double, double)>[];
  late final PhysicallyBasedMaterial _truckBeacon, _bannerGlow;

  // Shapes for glyph fireworks: other scripts (once) and the name (per job).
  var _scriptShapes = <List<vm.Vector2>>[];
  var _nameShapes = <List<vm.Vector2>>[];

  // ── Per job ───────────────────────────────────────────────────────────────
  Job? _job;
  NameRaster? _r;
  BuildPlan? _plan;
  List<(String, GlyphGeometry)>? _glyphs;
  int _lettersMade = 0;
  bool _lettersReady = false;
  List<_Fall>? _falls;
  _Swing? _swing;

  /// The wreck in real physics (see [Wreck]), and the cleanup's loader.
  final physics = Physics();
  late final wreck = Wreck(physics, _placeBrick);
  late final loader = Loader3D(scene);

  /// What the letters stand on (the ones whose feet are off the ground),
  /// and when they came up.
  late final plinths = Plinths(scene);
  double _plinthsAt = double.infinity;

  /// The cleanup: which bricks are gone (taken off camera).
  List<bool> _gone = const [];

  /// Where the camera looks (set by the world, with [camera]).
  final cameraTarget = vm.Vector3.zero();
  int _finalized = 0;

  /// Per letter: how far right of its place its settled bricks were last
  /// written (−1: not yet).
  List<double> _slid = [];
  bool _yardDone = false;
  bool _wallHidden = false;
  double b = 0.25;

  /// The finish's plan; when the reveal started (once seen); each brick's
  /// size as the finish last set it (−1: not yet); whether the bricks have
  /// had their paint for the demolition; per plan letter, its smooth
  /// letter (if it has one).
  FinishPlan? _finishPlan;
  double? _revealSeen;
  Float32List _brickScale = Float32List(0);
  bool _bricksPainted = false;
  List<bool> _smooth = [];

  /// Bounds of the wall (for the camera).
  double wallWidth = 12, wallHeight = 5;

  /// What the camera may want to look at: the hook, the wall's height so
  /// far, the middle of the letter at work.
  final hookAt = vm.Vector3(4, 10, 0);
  double level = 0;
  double activeX = 0;

  /// When the ball first hits the wall (scene time), once known.
  double? impactAt;

  /// When the wrecking starts (after the manager's visit; scene time) and
  /// how long it takes, in the demolition phase.
  double wreckAt = 0, wreckLen = 12;

  /// The model's pace (how long each phase lasts), as of this frame.
  BuildPace _pace = const BuildPace();

  /// What the camera should follow this frame (see [Focus]): filled during
  /// [update] by the site, the crew and the deliveries.
  final focus = <Focus>[];

  /// The lower third for the shots without one of their own.
  final caption = SceneCaption();

  /// Which of BOOTH3D_LOOK's views to take (capture mode sets it per frame).
  static int lookIndex = 0;
  final ballAt = vm.Vector3.zero();
  final truckAt = vm.Vector3(-40, 0, -4.5);

  void init() {
    // Bricks with chamfered edges: they catch the light, and in the wall
    // neighbours meet in a groove (the joints read).
    _bricks = InstancedMesh(geometry: (MeshBatch()..chamferedCube(0.075)).build(), material: pbr(rgb(1, 1, 1), roughness: 0.55));
    scene.add(Node(name: 'bricks')..addComponent(InstancedMeshComponent(_bricks)));
    _pallets = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: pbr(lin(const Color(0xFFA77445)), roughness: 0.85));
    for (var i = 0; i < _maxPallets; i++) {
      _pallets.addInstance(hidden);
    }
    scene.add(Node(name: 'pallets')..addComponent(InstancedMeshComponent(_pallets)));
    scene.add(_letterRoot);
    crane.init();
    crew.init();
    fx.init();
    lights.init();
    kern.init();
    props.init();
    breaks.init();
    delivery.init();
    parts.init();
    works.init();
    verdict.init();
    finish.init();
    loader.init();
    plinths.init();
    crew
      ..offDuty = breaks.pose
      ..stage = (who, p) {
        photo.pose(who, p);
        verdict.pose(who, p);
        finish.pose(who, p);
      }
      ..finishAt = (z, t) {
        final j = _job, plan = _plan;
        return j == null || plan == null || t < plan.t0 + plan.len ? null : finish.whereAt(z, t, _revealAt(j));
      };
    _buildTruck();
    _buildBanner();
    vectorizeText('Aあ字ЖΩب한कก♥').then((gs) {
      _scriptShapes = [
        for (final g in gs)
          if (!g.$2.isEmpty) Fx3D.shapeOf(g.$2),
      ]..removeWhere((s) => s.length < 20);
    });
  }

  // ── Truck & banner ────────────────────────────────────────────────────────

  void _buildTruck() {
    final body = pbr(lin(BP.green), roughness: 0.45, metallic: 0.15);
    final cab = pbr(lin(BP.amber), roughness: 0.4, metallic: 0.15);
    final dark = pbr(rgb(0.03, 0.035, 0.05), roughness: 0.75);
    final glass = pbr(rgb(0.08, 0.16, 0.24), roughness: 0.1, metallic: 0.3);
    final steel = pbr(rgb(0.6, 0.62, 0.66), roughness: 0.35, metallic: 0.8);
    final chassis = MeshBatch()..box(vm.Vector3(0.1, 0.62, 0), vm.Vector3(5.6, 0.32, 1.7));
    _truckBody.add(Node(mesh: Mesh(chassis.build(), dark)));
    // Tipper body with ribs.
    final tub = MeshBatch()
      ..box(vm.Vector3(-0.85, 1.05, 0), vm.Vector3(3.6, 0.14, 2.2)) // floor
      ..box(vm.Vector3(-0.85, 1.75, 1.06), vm.Vector3(3.6, 1.3, 0.1))
      ..box(vm.Vector3(-0.85, 1.75, -1.06), vm.Vector3(3.6, 1.3, 0.1))
      ..box(vm.Vector3(-2.6, 1.75, 0), vm.Vector3(0.1, 1.3, 2.2))
      ..box(vm.Vector3(0.9, 1.85, 0), vm.Vector3(0.12, 1.5, 2.2));
    for (var k = 0; k < 4; k++) {
      final x = -2.3 + k * 0.95;
      tub
        ..box(vm.Vector3(x, 1.75, 1.13), vm.Vector3(0.12, 1.3, 0.06))
        ..box(vm.Vector3(x, 1.75, -1.13), vm.Vector3(0.12, 1.3, 0.06));
    }
    _truckBody.add(Node(mesh: Mesh(tub.build(), body)));
    final cabin = MeshBatch()
      ..box(vm.Vector3(2.05, 1.45, 0), vm.Vector3(1.55, 1.5, 2.05))
      ..box(vm.Vector3(2.95, 1.0, 0), vm.Vector3(0.35, 0.5, 2.05)); // bonnet
    _truckBody.add(Node(mesh: Mesh(cabin.build(), cab)));
    final windows = MeshBatch()
      ..box(vm.Vector3(2.84, 1.72, 0), vm.Vector3(0.04, 0.62, 1.8))
      ..box(vm.Vector3(2.15, 1.72, 1.03), vm.Vector3(1.05, 0.58, 0.04))
      ..box(vm.Vector3(2.15, 1.72, -1.03), vm.Vector3(1.05, 0.58, 0.04));
    _truckBody.add(Node(mesh: Mesh(windows.build(), glass)));
    final grill = MeshBatch()..box(vm.Vector3(3.13, 0.95, 0), vm.Vector3(0.04, 0.32, 1.5));
    _truckBody.add(Node(mesh: Mesh(grill.build(), steel)));
    final lamp = pbr(rgb(1, 0.95, 0.8), emissive: rgb(1, 0.9, 0.7), emissiveStrength: 3);
    for (final z in [-0.72, 0.72]) {
      _truckBody.add(Node(mesh: Mesh(SphereGeometry(radius: 0.13, segments: 10, rings: 6), lamp), localTransform: trs(vm.Vector3(3.13, 1.12, z)))..castsShadows = false);
    }
    _truckBeacon = pbr(lin(BP.amber), emissive: lin(BP.amber), emissiveStrength: 4);
    _truckBody.add(Node(mesh: Mesh(CylinderGeometry(bottomRadius: 0.14, topRadius: 0.1, height: 0.18, radialSegments: 12), _truckBeacon), localTransform: trs(vm.Vector3(2.05, 2.29, 0)))..castsShadows = false);
    // Wheels (their axle along z): a tyre, and a hub with its nuts on the
    // outside, so you can see them turn.
    final tyre = CylinderGeometry(bottomRadius: 0.46, topRadius: 0.46, height: 0.34, radialSegments: 20);
    final white = vm.Vector4(1, 1, 1, 1);
    MeshGeometry hubOf(double side) => merged([
      part(CylinderGeometry(bottomRadius: 0.21, topRadius: 0.21, height: 0.36, radialSegments: 8), trs(vm.Vector3.zero(), rotX: math.pi / 2), white),
      for (var k = 0; k < 6; k++)
        part(CuboidGeometry(vm.Vector3(0.05, 0.05, 0.05)), vm.Matrix4.translation(vm.Vector3(0.13 * math.cos(k * math.pi / 3), 0.13 * math.sin(k * math.pi / 3), side * 0.195)), white),
      part(CuboidGeometry(vm.Vector3(0.06, 0.06, 0.06)), vm.Matrix4.translation(vm.Vector3(0, 0, side * 0.2)), white),
    ]);
    final hubs = {-1.0: hubOf(-1), 1.0: hubOf(1)};
    final rim = pbr(rgb(1, 1, 1), roughness: 0.35, metallic: 0.8)..baseColorFactor = rgb(0.62, 0.64, 0.68);
    for (final x in [-1.9, -0.9, 2.2]) {
      for (final z in [-0.92, 0.92]) {
        final w = Node(name: 'truck wheel', localTransform: trs(vm.Vector3(x, 0.46, z)))
          ..add(Node(mesh: Mesh(tyre, dark), localTransform: trs(vm.Vector3.zero(), rotX: math.pi / 2)))
          ..add(Node(mesh: Mesh(hubs[z.sign]!, rim)));
        _truckWheels.add((w, x, z));
        _truck.add(w);
      }
    }
    _truck.add(_truckBody);
    _truck.visible = false;
    scene.add(_truck);
    // ♻ on both sides of the tipper.
    vectorizeText('♻').then((gs) {
      if (gs.isEmpty || gs.first.$2.isEmpty) return;
      final g = gs.first.$2;
      final mesh = extrudeGlyph(g, unitsPerPx: 0.95 / g.inkHeight, depth: 0.05);
      final mat = pbr(rgb(0.95, 0.97, 0.96), roughness: 0.4, emissive: rgb(0.5, 0.9, 0.7), emissiveStrength: 0.4);
      for (final z in [-1.13, 1.13]) {
        _truckBody.add(Node(mesh: Mesh(glyphGeometry(mesh), mat), localTransform: trs(vm.Vector3(-0.85, 1.28, z * 1.03), rotY: z < 0 ? 0 : math.pi)));
      }
    });
  }

  void _buildBanner() {
    final navy = pbr(lin(BP.panel), roughness: 0.6);
    final trim = pbr(lin(BP.amber), roughness: 0.35, metallic: 0.3, emissive: lin(BP.amber), emissiveStrength: 0.5);
    _bannerGlow = pbr(lin(const Color(0xFFFFE3A3)), roughness: 0.3, emissive: lin(BP.amber), emissiveStrength: 2.2);
    const w = 5.2, h = 1.9;
    final board = MeshBatch()..box(vm.Vector3(0, 0, 0.06), vm.Vector3(w, h, 0.12));
    _banner.add(Node(mesh: Mesh(board.build(), navy)));
    final frame = MeshBatch()
      ..box(vm.Vector3(0, h / 2, 0), vm.Vector3(w + 0.12, 0.1, 0.18))
      ..box(vm.Vector3(0, -h / 2, 0), vm.Vector3(w + 0.12, 0.1, 0.18))
      ..box(vm.Vector3(w / 2, 0, 0), vm.Vector3(0.1, h, 0.18))
      ..box(vm.Vector3(-w / 2, 0, 0), vm.Vector3(0.1, h, 0.18));
    _banner.add(Node(mesh: Mesh(frame.build(), trim)));
    // Bulbs round the edge, like the 2D board.
    final bulb = SphereGeometry(radius: 0.055, segments: 8, rings: 5);
    final bulbs = InstancedMesh(geometry: bulb, material: pbr(rgb(1, 0.9, 0.6), emissive: rgb(1, 0.8, 0.45), emissiveStrength: 5));
    for (var k = 0; k < 15; k++) {
      final x = -w / 2 + 0.3 + k * (w - 0.6) / 14;
      bulbs.addInstance(trs(vm.Vector3(x, h / 2 - 0.16, -0.04)));
      bulbs.addInstance(trs(vm.Vector3(x, -h / 2 + 0.16, -0.04)));
    }
    _banner.add(Node()..addComponent(InstancedMeshComponent(bulbs)));
    _banner.visible = false;
    scene.add(_banner);
    vectorizeText('完成！').then((gs) {
      // Lay the characters out side by side, 1.15 tall.
      final metas = [for (final g in gs) (g.$1, g.$2, extrudeGlyph(g.$2, unitsPerPx: 1.15 / 105, depth: 0.22))];
      var total = 0.0;
      for (final m in metas) {
        total += m.$3.width + 0.18;
      }
      var x = -total / 2;
      for (final m in metas) {
        if (m.$2.isEmpty) continue;
        final cx = x + m.$3.width / 2;
        _banner.add(Node(name: 'banner ${m.$1}', mesh: Mesh(glyphGeometry(m.$3), _bannerGlow), localTransform: trs(vm.Vector3(cx, -0.62, -0.1))));
        x += m.$3.width + 0.18;
      }
    });
  }

  // ── Per job ───────────────────────────────────────────────────────────────

  void _startJob(Job j) {
    _job = j;
    _r = null;
    _plan = null;
    _glyphs = null;
    _lettersMade = 0;
    _lettersReady = false;
    _falls = null;
    _swing = null;
    wreck.end();
    loader.end(physics);
    _plinthsAt = double.infinity;
    _gone = const [];
    _swaps = null;
    _finalized = 0;
    _slid = [];
    _yardDone = false;
    _wallHidden = false;
    _wayOn.fillRange(0, _maxPallets, false);
    impactAt = null;
    _nameShapes = [];
    _finishPlan = null;
    _revealSeen = null;
    _brickScale = Float32List(0);
    _bricksPainted = false;
    _smooth = [];
    for (final l in _letters) {
      _letterRoot.remove(l.node);
    }
    _letters.clear();
    _shapes.clear();
    _bricks.clearInstances();
    vectorizeText(j.name, style: (size, color) => NameRaster.nameStyle(size, color: color)).then((g) {
      if (!identical(_job, j)) return;
      _glyphs = g;
      _nameShapes = [
        for (final e in g)
          if (!e.$2.isEmpty) Fx3D.shapeOf(e.$2, count: 120),
      ]..removeWhere((s) => s.length < 20);
    });
  }

  void _setupRaster(Job j, NameRaster r, double t) {
    _r = r;
    b = SiteLayout.brick(r);
    wallWidth = r.cols * b;
    wallHeight = r.rows * b;
    final plan = _plan = BuildPlan(j, r, b)..palletOnTheWay = delivery.palletAt;
    plinths.plan(plan);
    _plinthsAt = t;
    delivery.planFor(plan);
    // Every other sample word (no one waiting), a tour of the mini world
    // instead of a letter's journey through the works.
    final tour = j.sample && j.serial.isOdd;
    if (tour) {
      vignettes.planFor(plan, busyCam: delivery.camWindows, sample: true);
      works.planFor(plan, busyCam: [...delivery.camWindows, ...vignettes.camWindows], journey: false);
      alley.planFor(plan, busyCam: [...delivery.camWindows, ...works.camWindows, ...vignettes.camWindows]);
    } else {
      works.planFor(plan, busyCam: delivery.camWindows);
      alley.planFor(plan, busyCam: [...delivery.camWindows, ...works.camWindows]);
      vignettes.planFor(plan, busyCam: [...delivery.camWindows, ...works.camWindows, ...alley.camWindows]);
    }
    breaks.planFor(
      plan,
      driverBreaks: delivery.driverBreaks,
      busyCam: [...delivery.camWindows, ...works.camWindows, ...alley.camWindows, ...vignettes.camWindows],
    );
    final fp = _finishPlan = finish.planFor(
      plan,
      len: CityPace.reveal,
      watch: [for (var z = 0; z < Crew3D.builders; z++) crew.watchSpot(z, wallWidth)],
      corner: vm.Vector3(wallWidth / 2 + 0.75, 0, -1.55),
      paint: [for (final l in plan.letters.letters) paintOf(_hues[l.glyph % _hues.length])],
    );
    finish.face = -b * 0.85;
    _smooth = List.filled(plan.letterCount, false);
    // Instances in laying order.
    for (var i = 0; i < plan.total; i++) {
      _bricks.addInstance(hidden, color: _brickColor(r.bricks[plan.src[i]]));
    }
    _slid = List.filled(plan.letterCount, -1.0);
    // Capture runs log the timeline (when each letter goes up and is kerned,
    // and finished).
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') debugPrint('${plan.describe()}${fp.describe()}${finish.describeShots()}${alley.describe()}${vignettes.describe()}');
  }

  /// The letters' colours, in the order of the name's characters.
  static const _hues = [BP.amber, BP.line, BP.green, BP.pink, BP.violet, BP.coral];

  /// Bricks standing (the first n, in laying order): all of them, unless
  /// the build was cut short.
  int _standing(Job j, BuildPlan plan) => j.cutAt == null ? plan.total : plan.laidBy(_cutT(j, plan));

  /// When the build was cut short (a letter caught mid-slide stays there).
  double _cutT(Job j, BuildPlan plan) => plan.t0 + (j.cutFrac ?? 1) * plan.len;

  vm.Vector4 _brickColor(Brick k) {
    final full = rgb(0.86, 0.83, 0.76);
    final glass = rgb(0.12, 0.33, 0.85);
    final f = c01((k.cover - 0.15) / 0.7);
    return glass + (full - glass) * f;
  }

  vm.Vector3 cell(int i) => vm.Vector3(_plan!.cellX[i], _plan!.cellY[i], 0);

  final _m = vm.Matrix4.identity();
  final _q = vm.Quaternion.identity();
  static final _axes = [vm.Vector3(0.3, 1, 0.2).normalized(), vm.Vector3(1, 0.2, -0.4).normalized(), vm.Vector3(-0.3, 0.5, 1).normalized()];

  vm.Matrix4 _brickM(double x, double y, double z, double s, [double spin = 0, int axis = 0]) {
    if (s <= 0) return hidden;
    if (spin == 0) {
      _q.setValues(0, 0, 0, 1);
    } else {
      _q.setAxisAngle(_axes[axis % 3], spin);
    }
    final k = b * 0.96 * s;
    return setTqs(_m, x, y, z, _q, k, k, k);
  }

  /// One letter of the smooth name, placed exactly over the raster, and cut
  /// into bands of brick rows for the finish. Made one per frame.
  void _makeNextLetter() {
    final r = _r!, g = _glyphs!;
    final tp = TextPainter(
      text: TextSpan(text: r.name, style: NameRaster.nameStyle(r.fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final s = r.fontSize / craftRasterSize;
    var offset = 0;
    var k = 0;
    for (final ch in r.name.characters) {
      if (ch.trim().isEmpty) {
        offset += ch.length;
        continue;
      }
      if (k >= g.length) break;
      final idx = k++;
      final geo = g[idx].$2;
      final start = offset;
      offset += ch.length;
      if (idx < _lettersMade) continue;
      _lettersMade++;
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + ch.length));
      if (geo.isEmpty || boxes.isEmpty) break;
      final mesh = extrudeGlyph(geo, unitsPerPx: s * b, depth: b * 1.7);
      // Ink centre-bottom of this glyph, in the name's raster px.
      final px = boxes.first.left + ((geo.inkLeft + geo.inkRight) / 2 - rasterPad) * s - r.inkOffset.dx;
      final py = (geo.inkBottom - rasterPad) * s - r.inkOffset.dy;
      final at = vm.Vector3((px - r.cols / 2) * b, (r.rows - py) * b, 0);
      final paint = paintOf(_hues[idx % _hues.length]);
      // Painted: the paint's colour, a satin finish.
      final mat = pbr(paint.clone(), roughness: 0.5, emissive: paint.clone(), emissiveStrength: 0);
      // Bands of brick rows (at most ~12 per letter, to keep the draw
      // count down): world rows → the mesh's own y. The finish plasters and
      // paints them top-down; the works prints them bottom-up.
      final fp = _finishPlan!;
      final per = fp.per;
      final cuts = [for (var rr = per; rr < r.rows; rr += per) rr * b - at.y];
      final bands = sliceGlyph(mesh, cuts);
      final geos = <Geometry>[];
      final rows = <int>[];
      for (var k = 0; k < bands.length; k++) {
        final bg = bands[k];
        if (bg == null) continue;
        geos.add(bg);
        rows.add(math.min(r.rows - 1, (k + 1) * per - 1)); // its top row
      }
      // Its pieces for the finish: the bands (cut into strips too where two
      // pairs share the letter), each with its own material — plaster, then
      // paint, wet, then dry.
      final wall = _wallOf(idx, at.x);
      final xCuts = wall < 0 ? const <double>[] : [for (final x in fp.stripCuts(wall)) x - at.x];
      final grid = xCuts.isEmpty ? [bands] : sliceGlyphGrid(mesh, xCuts, cuts);
      final pieces = <_Piece>[];
      for (var s = 0; s < grid.length && wall >= 0; s++) {
        for (var k = 0; k < grid[s].length; k++) {
          final g = grid[s][k];
          if (g == null) continue;
          final m = pbr(_dryPlaster.clone(), roughness: 0.9, emissive: paint.clone(), emissiveStrength: 0);
          pieces.add(_Piece(MeshPrimitive(g, m), m, fp.unitFor(wall, s), k));
        }
      }
      if (wall >= 0) _smooth[wall] = true;
      final solid = glyphGeometry(mesh);
      final full = Mesh(solid, mat);
      final pieced = pieces.isEmpty ? full : Mesh.primitives(primitives: [for (final p in pieces) p.prim]);
      _shapes.add(
        LetterShape(
          glyph: idx,
          geometry: solid,
          bands: geos,
          bandTops: [for (final row in rows) (row + 1) * b - at.y],
          at: at,
          width: mesh.width,
          height: mesh.height,
          depth: b * 1.7,
        ),
      );
      final node = Node(name: 'letter $ch', mesh: full, localTransform: trs(at))..visible = false;
      _letters.add(_Letter(node, full, pieced, pieces, mat, paint, at, wall));
      _letterRoot.add(node);
      break;
    }
    tp.dispose();
    if (_lettersMade >= g.length) _lettersReady = true;
  }

  /// The plan's letter for smooth letter [glyph] at [x]: the one made of
  /// its ink, else the nearest (−1: the plan has none).
  int _wallOf(int glyph, double x) {
    final plan = _plan!, ls = plan.letters.letters;
    var best = -1;
    var bestD = double.infinity;
    for (var k = 0; k < ls.length; k++) {
      if (ls[k].glyph == glyph) return k;
      final d = (((ls[k].col0 + ls[k].col1 + 1) / 2 - plan.r.cols / 2) * b - x).abs();
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  // ── Update ────────────────────────────────────────────────────────────────

  void update(BoothModel m, double dt, {double night = 0}) {
    final j = m.job;
    final t = m.t;
    focus.clear();
    _pace = m.pace;
    alley.update(t, night);
    vignettes.update(t, night, camera: camera);
    parts.begin();
    if (j == null) {
      parts.end();
      return;
    }
    if (!identical(j, _job)) _startJob(j);
    final r = j.raster;
    if (r != null && _r == null && j.buildStart != null) _setupRaster(j, r, t);
    if (_r != null && _glyphs != null && !_lettersReady) _makeNextLetter();

    _truck.visible = false;
    _banner.visible = false;
    crane.slings(null);
    crane
      ..ballHanging = false
      ..ballRest = null;
    final plan = _plan;
    level = plan?.level(t) ?? 0;
    activeX = plan?.activeX(t) ?? 0;
    double trip = -1;

    switch (j.phase) {
      case Phase.intake || Phase.build:
        trip = _build(j, t, dt, night);
      case Phase.reveal:
        _finishing(j, t, night);
        _idleCrane(vm.Vector3(wallWidth / 2 + 3.5, 12.5, 2.5), t, dt, night);
      case Phase.celebrate:
        _hideWall();
        _celebrate(j, t, dt, night);
      case Phase.demolish:
        _demolish(j, t, dt, night);
      case Phase.cleanup:
        _cleanup(j, t, dt, night);
    }
    // The plinths: up out of the ground as the plan's made, gone with the
    // rubble at the cleanup's cut to the swept plaza.
    final cleaning = j.phase == Phase.cleanup && j.since(t) >= 0.78 * j.phaseLen;
    plinths.update(_plan == null || cleaning ? 0 : eio(seg(t, _plinthsAt, _plinthsAt + 2.4)));
    breaks
      ..camera.setFrom(camera)
      ..begin(t, night);
    delivery.update(j, plan, t, night);
    _drawPallets(j, t);
    final fp = _finishPlan;
    final revealAt = plan == null ? 0.0 : _revealAt(j);
    kern.update(plan, j, t, fx, skidGone: fp == null ? null : (k) => revealAt + fp.footAt(k));
    photo.update(m, j, plan, t);
    works.update(j, plan, t, night, _shapes);
    verdict.update(m, j, t, w: wallWidth, impact: impactAt, held: photo.whereAt);
    finish.update(j, plan, t, revealAt);
    crew.update(m, plan, w: wallWidth, seat: crane.seat, seatYaw: crane.seatYaw, impact: impactAt, trip: trip, night: night);
    finish.drawTools();
    breaks.end();
    parts.end();
    props.update(night);
    lights.update(night, t, fx.flashes);
    hookAt.setFrom(crane.hook);
    // The finish up close, the team photo; now and then the camera follows
    // the delivery, visits the works, or follows someone on a break.
    finish.focus(focus);
    photo.focus(focus, t, w: wallWidth, h: wallHeight);
    verdict.focus(focus, t);
    delivery.focus(focus, t);
    works.focus(focus, t);
    if (j.phase == Phase.build) {
      alley.focus(focus, t);
      vignettes.focus(focus, t);
    }
    breaks.focus(focus, t);
    _pin();
  }

  /// Framing aid: --dart-define=BOOTH3D_LOOK=ex,ey,ez,tx,ty,tz[,fov] pins
  /// the camera (with capture mode, to check a spot from a fixed eye);
  /// several views split by '|' are taken in turn, one per captured frame
  /// ('-': not pinned).
  void _pin() {
    const look = String.fromEnvironment('BOOTH3D_LOOK');
    if (look.isEmpty) return;
    final views = look.split('|'), view = views[math.min(lookIndex, views.length - 1)];
    // ('-': this frame, the director's own shot.)
    if (view == '-') return;
    final v = view.split(',').map(double.parse).toList();
    focus.add(
      Focus('look $lookIndex', Shot(vm.Vector3(v[0], v[1], v[2]), vm.Vector3(v[3], v[4], v[5]), fov: v.length > 6 ? v[6] : 40, settle: 0.3), priority: 9),
    );
  }

  /// What [caption] says, for [shot] (the director's name for what's on
  /// screen): the bricks arriving, the finish, the next name's plans, the
  /// demolition and the cleanup.
  void captionFor(BoothModel m, String shot) {
    final j = m.job, plan = _plan, t = m.t;
    if (vignettes.captionFor(shot) case final c?) {
      caption.update(t, c.topic, kick: c.kick, line: c.line, note: c.note);
      return;
    }
    if (j == null || plan == null) {
      caption.update(t, null);
      return;
    }
    final close = shot.startsWith('finish') ? finish.closeUpAt(shot.substring(7)) : null;
    if (shot.startsWith('delivery')) {
      caption.update(t, 'delivery ${shot.split(' ')[1]}', kick: '資材搬入 · DELIVERY', line: '${plan.total} bricks', note: 'one for each pixel of “${j.name}”');
    } else if (close case final s?) {
      if (s.plaster) {
        caption.update(t, shot, kick: '左官 · PLASTER', line: 'Anti-aliasing', note: 'the jagged pixel edges, smoothed over');
      } else {
        final hue = _hues[plan.letters.letters[s.letter].glyph % _hues.length];
        final hex = (hue.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
        caption.update(t, shot, kick: '塗装 · PAINT', line: '#$hex', note: "the letter's fill, from the top down", swatch: hue);
      }
    } else if (shot.startsWith('alley ')) {
      final a = shot.split(' ').last, stall = alley.stallAt(a);
      if (stall == null) {
        caption.update(t, null);
      } else {
        final r = alleyRules[stall];
        caption.update(t, 'alley $a', kick: '文字横丁 · SCRIPT ALLEY', line: r.en, note: r.note);
      }
    } else if (shot.startsWith('verdict')) {
      caption.update(t, 'verdict', kick: '次の建物 · NEXT BUILD', line: m.upcoming, note: "the new manager's blueprint");
    } else if (shot.startsWith('director demolish')) {
      caption.update(t, 'demolish', kick: '解体 · DEMOLITION', line: 'Making way', note: 'for “${m.upcoming}”, next in line');
    } else if (shot.startsWith('director cleanup')) {
      caption.update(t, 'cleanup', kick: '片付け · CLEANUP', line: '${plan.total} bricks recycled', note: 'back to the yard for the next name');
    } else {
      caption.update(t, null);
    }
  }

  // ── Intake & build ────────────────────────────────────────────────────────

  final _cmd = vm.Vector3(9, 9, 0);
  bool _cmdInit = false;

  /// Moves the hook towards [target] like a crane (slew/trolley/hoist, eased).
  void _idleCrane(vm.Vector3 target, double t, double dt, double night, {double settle = 0.9}) {
    if (!_cmdInit) {
      _cmd.setFrom(target);
      _cmdInit = true;
    }
    final f = 1 - math.exp(-math.min(dt, 0.5) / settle);
    _cmd.setFrom(polarLerp(_cmd, target, f));
    crane.update(_cmd, t, dt, night: night);
  }

  final _pose = BrickPose();

  /// Returns the crane's trip progress (for the foreman), or -1.
  double _build(Job j, double t, double dt, double night) {
    final plan = _plan;
    if (plan == null) {
      _idleCrane(vm.Vector3(SiteLayout.mastX - 5, 9, SiteLayout.mastZ - 4), t, dt, night);
      return -1;
    }
    // The crane: on a trip, waiting over the next pallet between trips, or
    // by the wall after the last.
    final at = plan.tripAt(t);
    if (at != null) {
      _cmd.setFrom(plan.hookPath(t));
      _cmdInit = true;
      crane.update(_cmd, t, dt, night: night);
    } else if (t < plan.t0 + plan.tripB(plan.trips - 1)) {
      _idleCrane(plan.hookPath(t), t, dt, night, settle: 0.6);
    } else {
      _idleCrane(vm.Vector3(wallWidth / 2 + 3, math.max(9.0, level + 5), 3.2), t, dt, night);
    }
    final sway = crane.sway;
    // Bricks: the wall's settled ones once (and again while their letter
    // slides into place), the moving ones every frame.
    final settled = plan.settledBy(t);
    for (; _finalized < settled; _finalized++) {
      final i = _finalized;
      _bricks.setInstanceTransform(i, _brickM(plan.cellX[i] + plan.offsetAt(plan.letter[i], t), plan.cellY[i], 0, 1));
    }
    for (var k = 1; k < plan.letterCount; k++) {
      final o = plan.offsetAt(k, t);
      if (o == _slid[k]) continue;
      _slid[k] = o;
      for (var i = plan.letterStart[k]; i < math.min(plan.letterStart[k + 1], _finalized); i++) {
        _bricks.setInstanceTransform(i, _brickM(plan.cellX[i] + o, plan.cellY[i], 0, 1));
      }
    }
    final kNow = plan.tripNow(t);
    final dynEnd = plan.tripStart[math.min(kNow + 1, plan.trips)];
    for (var i = _finalized; i < dynEnd; i++) {
      final p = plan.brickAt(i, t, _pose);
      var x = p.pos.x, z = p.pos.z;
      // Riding the crane: swing with the hook.
      if (at != null && plan.trip[i] == at.$1 && t < plan.t0 + plan.dropRel[i] && at.$2 >= 0.1) {
        x += sway.x;
        z += sway.z;
      }
      _bricks.setInstanceTransform(i, _brickM(x, p.pos.y, z, p.scale, p.spin, p.spinAxis));
    }
    if (!_yardDone) {
      for (var i = dynEnd; i < plan.total; i++) {
        final p = plan.brickAt(i, t, _pose);
        _bricks.setInstanceTransform(i, _brickM(p.pos.x, p.pos.y, p.pos.z, p.scale));
      }
      if (t > j.startedAt + 4.6) _yardDone = true;
    }
    // Dust: bricks landing in the wall (a puff a handful), batches landing
    // on the piles.
    for (var i = plan.laidBy(t - 0.5), e = plan.laidBy(t); i < e; i++) {
      final age = (t - plan.layAt(i)) / 0.5;
      if (i % 2 != 0) continue;
      fx.puff(plan.cellX[i] + plan.offsetAt(plan.letter[i], t), plan.cellY[i] - b * 0.4, -b * 0.6, age, b * 1.3, seed: i, n: 2);
    }
    for (final k in [kNow - 1, kNow]) {
      if (k < 0) continue;
      for (var i = plan.tripStart[k]; i < plan.tripStart[k + 1]; i++) {
        final age = (t - plan.pileLandAt(i)) / 0.45;
        if (age < 0 || age >= 1 || plan.pile[i] % 3 != 0) continue;
        plan.pileSlot(plan.pileOf[i], plan.pile[i], plan.deckY(t), _tmp);
        fx.puff(_tmp.x, _tmp.y - b * 0.3, _tmp.z, age, b * 1.6, seed: i, n: 2);
      }
    }
    // The kerning close-ups.
    for (final st in plan.steps) {
      if (st == null || !st.filmed || t < st.a - 1.2 || t > st.e + 0.7) continue;
      final (eye, target, fov, w) = Kern3D.shot(st, t);
      // (Cut in halfway through the ease in, out halfway through the out.)
      if (w < 0.5) continue;
      final shot = Shot(eye, target, fov: fov, settle: st.full ? 1.2 : 1.7, drift: 0.5);
      focus.add(Focus('kern ${st.letter}', shot, priority: 3));
    }
    return at == null ? -1 : at.$2;
  }

  final _tmp = vm.Vector3.zero();

  /// The pallets: in the yard, on the tower crane's hook, or still on the
  /// delivery truck (and its crane) with their bricks riding on them.
  void _drawPallets(Job j, double t) {
    final plan = _plan;
    final late = j.phase.index > Phase.celebrate.index;
    var slung = false;
    for (var k = 0; k < _maxPallets; k++) {
      if (plan == null || k >= plan.trips) {
        _pallets.setInstanceTransform(k, hidden);
        continue;
      }
      if (delivery.palletAt(k, t, _way)) {
        final s = 4 * b + 0.12, w = _way;
        _q.setAxisAngle(_yAxis, w.yaw);
        _pallets.setInstanceTransform(k, w.shown ? setTqs(_m, w.base.x, w.base.y + 0.07, w.base.z, _q, s, 0.14, s) : hidden);
        // Its bricks, when it moves (and every frame after a cut, when the
        // site's own phases hide whatever isn't in the wall).
        final moved = !_wayOn[k] || w.shown != _wayShown[k] || w.yaw != _wayYaw[k] || w.base.distanceToSquared(_wayBase[k]) > 1e-8;
        if (moved || late) _rideBricks(plan, k, w);
        _wayOn[k] = true;
        _wayShown[k] = w.shown;
        _wayYaw[k] = w.yaw;
        _wayBase[k].setFrom(w.base);
        continue;
      }
      if (_wayOn[k]) {
        // Just set down in the yard: its bricks there, once.
        _wayOn[k] = false;
        for (var i = plan.tripStart[k]; i < plan.tripStart[k + 1] && !late; i++) {
          final p = plan.brickAt(i, t, _pose);
          _bricks.setInstanceTransform(i, _brickM(p.pos.x, p.pos.y, p.pos.z, p.scale, p.spin, p.spinAxis));
        }
      }
      if (late) {
        _pallets.setInstanceTransform(k, hidden);
        continue;
      }
      final appear = c01((t - (j.startedAt + 0.4 + 0.08 * k)) / 0.3);
      final base = plan.palletBase(k, t);
      final onHook = base.y > 0.01;
      final s = 4 * b + 0.12;
      final x = base.x + (onHook ? crane.sway.x : 0), z = base.z + (onHook ? crane.sway.z : 0);
      _pallets.setInstanceTransform(k, appear <= 0 ? hidden : setTqs(_m, x, base.y + 0.07, z, _qi, s * appear, 0.14 * appear, s * appear));
      if (onHook && !slung) {
        slung = true;
        crane.slings(vm.Vector3(x, base.y + 0.12, z), hx: s / 2 - 0.05, hz: s / 2 - 0.05);
      }
    }
  }

  static final _qi = vm.Quaternion.identity();
  static final _yAxis = vm.Vector3(0, 1, 0);
  final _way = PalletPose();
  final _wayOn = List.filled(_maxPallets, false), _wayShown = List.filled(_maxPallets, false);
  final _wayYaw = List.filled(_maxPallets, 0.0);
  final _wayBase = List.generate(_maxPallets, (_) => vm.Vector3.zero());

  /// Pallet [k]'s bricks where it is now ([w]: on the delivery truck).
  void _rideBricks(BuildPlan plan, int k, PalletPose w) {
    final count = plan.tripCount(k), size = w.shown ? b * 0.96 : 0.0;
    _q.setAxisAngle(_yAxis, w.yaw);
    for (var i = plan.tripStart[k]; i < plan.tripStart[k + 1]; i++) {
      plan.palletSlotPos(w.base, plan.palletSlot[i], count, _tmp);
      w.turn(_tmp);
      _bricks.setInstanceTransform(i, size == 0 ? hidden : setTqs(_m, _tmp.x, _tmp.y, _tmp.z, _q, size, size, size));
    }
  }

  /// No bricks (while the smooth letters stand), set once.
  void _hideWall() {
    final plan = _plan;
    if (plan == null || _wallHidden) return;
    for (var i = 0; i < plan.total; i++) {
      _bricks.setInstanceTransform(i, hidden);
    }
    _wallHidden = true;
  }

  // ── The finish: plaster, then paint ───────────────────────────────────────

  /// When [j]'s reveal started (as seen), or will (or must have).
  double _revealAt(Job j) {
    if (j.phase == Phase.reveal) return _revealSeen = j.phaseStart;
    if (_revealSeen case final at?) return at;
    if (j.phase == Phase.celebrate) return j.phaseStart - CityPace.reveal;
    final plan = _plan!;
    return plan.t0 + plan.len;
  }

  /// Fresh render (a darker grey while it's wet) and dry.
  static final _wetPlaster = lin(const Color(0xFF746E67)), _dryPlaster = lin(const Color(0xFFCBC5BA));

  /// How long the plaster and the paint take to dry.
  static const _plasterDries = 3.5, _paintDries = 2.0;

  /// The finish at [t]: the letters' bands plastered and painted as the
  /// work comes down them, the edge bricks smoothed away.
  void _finishing(Job j, double t, double night) {
    final plan = _plan, fp = _finishPlan;
    if (plan == null || fp == null) return;
    final u = t - _revealAt(j);
    _finishLetters(fp, u, night);
    _finishBricks(j, plan, fp, u);
  }

  /// The letters [u] seconds into the finish: nothing until the plaster
  /// reaches them, then band by band (each piece its own material), whole
  /// again once painted and dry.
  void _finishLetters(FinishPlan fp, double u, double night) {
    for (final l in _letters) {
      if (l.pieces.isEmpty) {
        // Nothing to piece: whole once its letter is painted.
        final done = l.wall < 0 || u >= fp.doneAt(l.wall);
        l.node.visible = done;
        if (done) _paintFull(l, night, 0);
        continue;
      }
      var shown = false, settled = true;
      for (final p in l.pieces) {
        final pa = fp.plasterAt(p.unit, p.band);
        final on = u >= pa;
        p.prim
          ..visible = on
          ..castsShadow = on;
        if (!on) {
          settled = false;
          continue;
        }
        shown = true;
        final ca = fp.paintAt(p.unit, p.band), dur = fp.bandTime(p.unit, p.band);
        if (u < ca + dur + _paintDries) settled = false;
        _shade(p.mat, u - pa, u - ca, dur, l.paint, night);
      }
      final mesh = settled ? l.full : l.pieced;
      if (!identical(l.node.mesh, mesh)) l.node.mesh = mesh;
      l.node.visible = shown;
      if (settled) _paintFull(l, night, 0);
    }
  }

  /// A piece [sinceP] seconds after its plaster went on and [sinceC] after
  /// the paint got to it (negative: not yet), taking [dur] to cross it:
  /// grey wet plaster drying pale, then the paint, darker and glossy while
  /// it's wet, drying to satin.
  void _shade(PhysicallyBasedMaterial m, double sinceP, double sinceC, double dur, vm.Vector4 paint, double night) {
    final dryP = eo(sinceP / _plasterDries), cover = c01(sinceC / dur), dryC = eo((sinceC - dur) / _paintDries);
    final wet = 0.8 + 0.2 * dryC;
    final c = m.baseColorFactor;
    for (var k = 0; k < 3; k++) {
      c[k] = lerp(lerp(_wetPlaster[k], _dryPlaster[k], dryP), paint[k] * wet, cover);
    }
    m
      ..roughnessFactor = lerp(lerp(0.6, 0.92, dryP), lerp(0.16, 0.5, dryC), cover)
      ..emissiveStrength = cover * _glow(night);
  }

  /// [l] whole: painted and dry ([shine]: a festive sheen on top).
  void _paintFull(_Letter l, double night, double shine) {
    l.mat.baseColorFactor.setFrom(l.paint);
    l.mat
      ..roughnessFactor = 0.5
      ..emissiveStrength = _glow(night) + shine;
  }

  /// Painted, not lit: only after dark a faint glow of their own keeps the
  /// letters readable between the floods.
  static double _glow(double night) => 0.2 * smooth(0.25, 0.8, night);

  /// The bricks [u] seconds into the finish: the edges, poking out of the
  /// plaster, shrink away as it passes; the rest stay inside the smooth
  /// letter. (Written only when they change.)
  void _finishBricks(Job j, BuildPlan plan, FinishPlan fp, double u) {
    final n = plan.total;
    if (_brickScale.length != n) _brickScale = Float32List(n)..fillRange(0, n, -1);
    final standing = _standing(j, plan);
    for (var i = 0; i < n; i++) {
      final h = fp.hideAt[i];
      final s = i >= standing ? 0.0 : (h.isInfinite || !_smooth[plan.letter[i]] ? 1.0 : 1 - seg(u, h, h + 0.18));
      if (s == _brickScale[i]) continue;
      _brickScale[i] = s;
      _bricks.setInstanceTransform(i, _brickM(plan.cellX[i], plan.cellY[i], 0, s));
    }
    _wallHidden = false;
  }

  // ── Celebrate ─────────────────────────────────────────────────────────────

  void _celebrate(Job j, double t, double dt, double night) {
    final u = j.since(t);
    final len = j.phaseLen;
    // The painted letters: one after another a little hop, then a festive
    // sheen travelling along (paint catching the lights, not a glow).
    for (var i = 0; i < _letters.length; i++) {
      final l = _letters[i];
      if (!identical(l.node.mesh, l.full)) l.node.mesh = l.full;
      l.node.visible = true;
      final on = c01((u - 0.2 - i * 0.22) / 0.35);
      final hop = math.sin(on * math.pi) * (1 - on * 0.3);
      l.node.place((m) => setTrs(m, l.at.x, l.at.y + 0.35 * hop, l.at.z, s: 1 + 0.1 * hop));
      final wave = 0.5 + 0.5 * math.sin(u * 3.2 - i * 0.9);
      _paintFull(l, night, on * wave * (0.06 + 0.1 * night) * (1 - seg(u, len - 2.5, len)));
    }
    fx.fireworks(u, wallWidth, wallHeight, j.serial, _nameShapes, _scriptShapes);
    fx.confettiShow(u, wallWidth, j.serial);
    // The crane brings the 完成！ sign over the name, then takes it away.
    final show = vm.Vector3(0, wallHeight + 4.4, -0.7);
    final park = vm.Vector3(wallWidth / 2 + 4.5, 13.5, -1.5);
    final inF = eio(seg(u, 0.0, 2.6)), outF = eio(seg(u, len - 2.4, len - 0.2));
    final target = polarLerp(polarLerp(park, show, inF), vm.Vector3(show.x + 3, 16, show.z), outF);
    _cmd.setFrom(target);
    _cmdInit = true;
    crane.update(_cmd, t, dt, night: night);
    final hk = crane.hook;
    final sw = 0.04 * math.sin(u * 1.7);
    _banner
      ..visible = true
      ..place((m) => setTrs(m, hk.x, hk.y - 1.45 - 0.95, hk.z, roll: sw));
    crane.slings(vm.Vector3(hk.x, hk.y - 1.45, hk.z), hx: 2.2, hz: 0.04);
    _bannerGlow.emissiveStrength = 1.6 + 0.9 * (0.5 + 0.5 * math.sin(u * 5));
  }

  // ── Demolition: a wrecking ball, then ballistic bricks ─────────────────────

  void _demolish(Job j, double t, double dt, double night) {
    final plan = _plan;
    // First the manager's visit (not after a cut): the name still stands.
    final pre = CityPace.verdictOf(j);
    final len = math.max(j.phaseLen - pre, 0.01);
    final u = j.since(t) - pre;
    wreckAt = j.phaseStart + pre;
    wreckLen = len;
    if (u < 0 && plan != null) {
      _verdict(j, t, dt, night, pre + u, pre);
      return;
    }
    for (final l in _letters) {
      l.node.visible = false;
    }
    final fp = _finishPlan;
    if (plan == null || fp == null) {
      _idleCrane(vm.Vector3(wallWidth / 2 + 4, 12, -1), t, dt, night);
      return;
    }
    _swing ??= _Swing(wallWidth, wallHeight, len, from: pre > 0 ? _lifted : null, floor: plinths.runs.fold(0.0, (m, r) => math.max(m, r.top)));
    final sw = _swing!;
    if (_falls == null) {
      _falls = _planFalls(j, sw);
      final fs = _falls!;
      wreck.start([
        for (var i = 0; i < fs.length; i++)
          if (!fs[i].ever) null else WreckBrick(fs[i].p0, plan.letter[i], (plan.cellX[i] / b).round(), (plan.cellY[i] / b).round(), fs[i].release, fs[i].v0, fs[i].axis * fs[i].spin, hit: fs[i].hit),
      ], b, sw.ballAt(u), u, solids: _solids());
      impactAt = j.phaseStart + pre + sw.firstHit;
      _swaps = [for (final l in plan.letters.letters) sw.passTime((l.col1 + 1 - plan.r.cols / 2) * b) - 0.03];
    }
    // The name stands as the finish left it (painted, unless a sample was
    // cut short in it) until the ball gets to each letter; then, under a
    // burst of dust, it's bricks again — painted bricks — and down they go.
    final done = _finishedBy(j, fp);
    if (!_bricksPainted && _lettersReady) {
      // (Once the letters are all made: they say which bricks are smoothed.)
      _bricksPainted = true;
      if (done >= 0) _paintBricks(plan, fp, done);
    }
    final swaps = _swaps!;
    if (done >= 0) {
      _finishLetters(fp, done, night);
      for (final l in _letters) {
        if (l.wall < 0 || u >= swaps[l.wall]) l.node.visible = false;
      }
    }
    // The ball: lowered at the right, then swung through the wall.
    final ball = sw.ballAt(u);
    ballAt.setFrom(ball);
    crane.swingBall(sw.pivotAt(u), ball, t, dt, night: night);
    // Bricks: in the wall (under their letter until it's hit) until the
    // wreck lets them go, then the physics' (the wreck draws them).
    final falls = _falls!;
    for (var i = 0; i < falls.length; i++) {
      final f = falls[i];
      if (!f.ever) {
        _bricks.setInstanceTransform(i, hidden);
        continue;
      }
      if (wreck.released(i)) continue;
      final k = plan.letter[i];
      _bricks.setInstanceTransform(i, u < swaps[k] && _plastered(plan, fp, i, done) ? hidden : _brickM(f.p0.x, f.p0.y, f.p0.z, 1));
    }
    wreck.update(t, u, dt, sw.ballAt, people: _peopleAbout());
    _wallHidden = false;
    // The dust each letter turns to bricks under.
    for (var k = 0; k < swaps.length && done >= 0; k++) {
      final age = (u - swaps[k]) / 1.3;
      if (age < 0 || age >= 1 || !_smooth[k]) continue;
      final l = plan.letters.letters[k];
      final x0 = (l.col0 - plan.r.cols / 2) * b, x1 = (l.col1 + 1 - plan.r.cols / 2) * b, y0 = l.row0 * b, y1 = (l.row1 + 1) * b;
      final size = math.max(0.7, math.min(1.5, (y1 - y0) * 0.32));
      for (var q = 0; q < 4; q++) {
        fx.puff(lerp(x0, x1, 0.25 + 0.5 * (q % 2)), lerp(y0, y1, q < 2 ? 0.28 : 0.72), -0.35, age, size, seed: k * 5 + q, n: 2);
      }
    }
    // Dust where the ball hits and where bricks land.
    if (u >= sw.firstHit && u < sw.firstHit + 1.4) {
      final x = sw.ballAt(u).x;
      if (x.abs() < wallWidth / 2 + 0.5) fx.puff(x, wallHeight * 0.4, -0.3, (u - sw.firstHit) % 0.7 / 0.7, 1.2, seed: (u * 3).floor(), n: 4);
    }
    _impactDust(t);
    // Confetti from the celebration still lies about.
    if (j.cutAt == null) fx.confettiShow(u + pre + _pace.phaseLen(Phase.celebrate), wallWidth, j.serial);
    // The cleanup's truck on its way along the avenue (it was never in
    // the picture from nowhere).
    final ahead = j.phaseStart + j.phaseLen - t, clen = _pace.phaseLen(Phase.cleanup);
    if (ahead < _truckLead) _poseTruck(-ahead / clen, clen, t);
  }

  /// Brick [i] where the physics has it.
  void _placeBrick(int i, vm.Vector3 t, vm.Quaternion q) {
    final k = b * 0.96;
    _bricks.setInstanceTransform(i, setTqs(_m, t.x, t.y, t.z, q, k, k, k));
  }

  /// What's in the street's way: the delivery truck, and the cleanup's
  /// truck (cars stop behind it in the lane, people wait while it crosses
  /// the pavement).
  late final StreetWork streetWork = _SiteWork(this);

  /// The cleanup truck's pose at [t], if it's about.
  ({double x, double z, double yaw, double odo, double steer, double pitch})? _truckNow(double t) {
    final j = _job;
    if (j == null) return null;
    if (j.phase == Phase.demolish) {
      final ahead = j.phaseStart + j.phaseLen - t, clen = _pace.phaseLen(Phase.cleanup);
      if (ahead >= _truckLead) return null;
      return _truckPose(-ahead / clen, clen, SiteLayout.bayX, SiteLayout.bayZ);
    }
    if (j.phase != Phase.cleanup) return null;
    final len = math.max(j.phaseLen, 0.01);
    return _truckPose(j.since(t) / len, len, SiteLayout.bayX, SiteLayout.bayZ);
  }

  /// How far the bay gate should be open at [t]: from as the cleanup's
  /// truck comes along the avenue until it has driven out again.
  double bayGateOpen(double t) {
    final j = _job;
    if (j == null || j.phase != Phase.cleanup) return 0;
    final len = math.max(j.phaseLen, 0.01), u = j.since(t);
    return seg(u, 0.1 * len, 0.1 * len + 1.2) * (1 - seg(u, 0.93 * len, 0.93 * len + 1.2));
  }

  /// The cleanup's truck [f] through the cleanup ([len] long; before 0: on
  /// its way along the avenue, as the wrecking ends).
  void _poseTruck(double f, double len, double t) {
    final tp = _truckPose(f, len, SiteLayout.bayX, SiteLayout.bayZ);
    final yaw = tp.yaw;
    truckAt.setValues(tp.x, 0, tp.z);
    _truck
      ..visible = tp.x > -120
      ..place((m) => setTrs(m, tp.x, 0, tp.z, yaw: yaw));
    // Its body dips forward as it brakes and rocks back as it stops; the
    // wheels roll, the front pair steers.
    _truckBody.place((m) => setTrs(m, 0, 0, 0, roll: -tp.pitch));
    for (final (w, x, z) in _truckWheels) {
      final steer = x > 0 ? -0.5 * tp.steer : 0.0;
      w.place((m) => setTrs(m, x, 0.46, z, yaw: steer, roll: -tp.odo / 0.46));
    }
    _truckBeacon.emissiveStrength = (t * 2.2) % 1.0 < 0.5 ? 6 : 0.4;
  }

  /// How long before the cleanup the truck comes into the picture.
  static const _truckLead = 6.0;

  /// The wrecking ball [f] through the cleanup: from wherever the swing
  /// left it, up at once (settling under the hook as it rises), over to the
  /// yard and down onto its place there.
  vm.Vector3 _homeBall(_Swing sw, double f) {
    final rest = Verdict3D.ballRest, c = sw.ballAt(sw.len);
    final high = vm.Vector3(5.0, math.min(c.y + 3, 10.5), 1.5), over = vm.Vector3(rest.x, rest.y + 4.0, rest.z);
    if (f < 0.16) {
      final up = eio(f / 0.16);
      return vm.Vector3(lerp(c.x, high.x, up), lerp(c.y, high.y, up), lerp(c.z, high.z, up));
    }
    if (f < 0.38) return polarLerp(high, over, eio(seg(f, 0.16, 0.38)));
    return over + (rest - over) * eio(seg(f, 0.38, 0.5));
  }

  /// The cleanup truck's frame [f] through it (for its physics).
  vm.Matrix4 _truckMatrix(double f, double len, double park, double bay) {
    final p = _truckPose(f, len, park, bay);
    return trs(vm.Vector3(p.x, 0, p.z), rotY: p.yaw);
  }

  /// The truck's turn into the bay (radius, metres), the lane it comes
  /// along and its speed on it (m/s).
  static const _turnR = 4.2, _lane = -13.0, _cruise = 9.0;

  /// The recycling truck [f] through a cleanup [len] seconds long: braking
  /// along the eastbound lane to a stop just past the bay; reversing round
  /// into it (a quarter turn, then straight back) to stand tub first by the
  /// rubble (yaw π/2: its cab, local +x, towards the avenue); out the same
  /// way, forwards, from 0.8. Also: how far it has rolled (signed: back is
  /// negative), its front wheels' steering (0..1) and its body's pitch.
  ({double x, double z, double yaw, double odo, double steer, double pitch}) _truckPose(double f, double len, double park, double bay) {
    final cx = park + _turnR, cz = _lane + _turnR;
    final arc = math.pi / 2 * _turnR, total = arc + (bay - cz);
    final tIn = 0.14 * len, brake = _cruise * tIn * 0.7;
    // [k] metres back along the way in from where it stopped: round the arc
    // (full lock), then straight (the wheel unwinding as it comes out).
    ({double x, double z, double yaw, double steer}) along(double k) {
      final steer = smooth(0.0, 0.6, k) * (1 - smooth(arc - 0.4, arc + 1.0, k));
      if (k <= arc) {
        final a = k / _turnR;
        return (x: cx - _turnR * math.sin(a), z: cz - _turnR * math.cos(a), yaw: a, steer: steer);
      }
      return (x: park, z: cz + (k - arc), yaw: math.pi / 2, steer: steer);
    }

    // The body's pitch (nose down +): down while braking and springing
    // back through level after the stop; a little rock as it stops backing.
    double settle(double since) => since < 0 ? 0 : 0.024 * math.exp(-since * 3.2) * math.cos(since * 11);
    double backed(double since) => since < 0 ? 0 : -0.01 * math.exp(-since * 3) * math.sin(since * 10);
    if (f < 0.14) {
      // At speed (from off to the left), then braking to the stop.
      final t = f * len, tc = 0.4 * tIn;
      final s = t < tc ? _cruise * t : _cruise * t - 0.5 * (_cruise / (tIn - tc)) * (t - tc) * (t - tc);
      return (x: cx - brake + s, z: _lane, yaw: 0.0, odo: s, steer: 0.0, pitch: 0.024 * smooth(tc, tc + 0.2, t));
    }
    if (f < 0.8) {
      final k = eio(seg(f, 0.14, 0.36)) * total;
      final p = along(k);
      return (x: p.x, z: p.z, yaw: p.yaw, odo: brake - k, steer: p.steer, pitch: settle(f * len - tIn) + backed(f * len - 0.36 * len));
    }
    // Out: forwards back along the way in, accelerating, then east.
    final g = seg(f, 0.8, 1.0), run = g * g * (total + 14);
    if (run <= total) {
      final p = along(total - run);
      return (x: p.x, z: p.z, yaw: p.yaw, odo: brake - total + run, steer: p.steer, pitch: -0.012 * (1 - g));
    }
    return (x: cx + (run - total), z: _lane, yaw: 0.0, odo: brake - total + run, steer: 0.0, pitch: 0.0);
  }

  /// Whether the camera (last frame) has [p] in its picture (roughly).
  bool _inView(vm.Vector3 p) {
    final d = p - camera, look = cameraTarget - camera;
    if (d.length2 < 1e-6 || look.length2 < 1e-6) return true;
    return d.normalized().dot(look.normalized()) > 0.62;
  }

  /// The solid things near the wall the rubble meets: the plinths, the
  /// crane's footing and mast (centre, half extents).
  List<(vm.Vector3, vm.Vector3)> _solids() => [
    for (final r in plinths.runs) (vm.Vector3((r.x0 + r.x1) / 2, r.top / 2, 0), vm.Vector3((r.x1 - r.x0) / 2, r.top / 2, plinths.depth / 2)),
    (vm.Vector3(SiteLayout.mastX, 0.3, SiteLayout.mastZ), vm.Vector3(1.4, 0.3, 1.4)),
    (vm.Vector3(SiteLayout.mastX, (0.6 + SiteLayout.jibY - 0.5) / 2, SiteLayout.mastZ), vm.Vector3(0.6, (SiteLayout.jibY - 1.1) / 2, 0.6)),
  ];

  /// Where the crew and the manager's party stand (last frame), by their
  /// index (null: not about, or up in the crane), for the rubble to bounce
  /// off.
  List<vm.Vector3?> _peopleAbout() => [
    for (var i = 0; i < crew.poses.length; i++)
      if (i != Crew3D.operator && crew.poses[i].visible) crew.poses[i].pos else null,
  ];

  /// Dust where bricks first came down on the ground.
  void _impactDust(double t) {
    wreck.impacts.removeWhere((e) => t - e.$1 >= 0.9 || t < e.$1);
    for (final (at, x, z) in wreck.impacts) {
      fx.puff(x, 0.05, z, (t - at) / 0.9, 0.5, seed: (x * 31 + z * 17).round(), n: 2);
    }
  }

  /// When (seconds into the wrecking) the ball gets to each of the plan's
  /// letters.
  List<double>? _swaps;

  /// How far into the finish [j] got (seconds): all of it (and dry), or as
  /// far as a sample cut short in it had got (−1: cut short before it).
  double _finishedBy(Job j, FinishPlan fp) {
    if (j.cutAt == null) return fp.len + 60;
    final plan = _plan!;
    final revealAt = _revealSeen ?? plan.t0 + plan.len;
    return j.phaseStart < revealAt ? -1 : math.min(j.phaseStart - revealAt, fp.len);
  }

  /// Whether brick [i] was under plaster [done] seconds into the finish.
  bool _plastered(BuildPlan plan, FinishPlan fp, int i, double done) {
    if (done < 0 || !_smooth[plan.letter[i]]) return false;
    return done >= fp.plasterAt(fp.unitOf[i], (plan.r.rows - 1 - plan.r.bricks[plan.src[i]].row) ~/ fp.per);
  }

  /// The bricks take the finish's colours for the wrecking — painted, or
  /// plastered where a sample cut short got no further — so painted bricks
  /// fly and lie in the rubble. Once a job (the next job's bricks start
  /// afresh).
  void _paintBricks(BuildPlan plan, FinishPlan fp, double done) {
    final r = plan.r;
    for (var i = 0; i < plan.total; i++) {
      final k = plan.letter[i];
      if (!_smooth[k]) continue;
      final u = fp.unitOf[i], g = (r.rows - 1 - r.bricks[plan.src[i]].row) ~/ fp.per;
      final shade = 0.9 + 0.14 * rnd(i, 17);
      final vm.Vector4 c;
      if (done >= fp.paintAt(u, g) + fp.bandTime(u, g)) {
        c = finish.paint[k];
      } else if (done >= fp.plasterAt(u, g)) {
        c = _dryPlaster;
      } else {
        continue;
      }
      _tint.setValues(c.x * shade, c.y * shade, c.z * shade, 1);
      _bricks.setInstanceColor(i, _tint);
    }
  }

  final _tint = vm.Vector4.zero();

  // ── The manager's visit (verdict.dart): the name stands; the ball ──────────

  /// Where the crane waits during the visit, and the ball's centre once it
  /// has been lifted off the ground by the yard (the swing takes it from
  /// there).
  vm.Vector3 get _parked => vm.Vector3(wallWidth / 2 + 3.5, 12.5, 2.0);
  static final _lifted = Verdict3D.ballRest + vm.Vector3(0, 3.9, 0);

  /// [u] seconds into the visit ([pre] long): the painted letters; the
  /// confetti; the crane waiting, then fetching the wrecking ball from
  /// beside the yard: over it, down to it, hooked on, lifted.
  void _verdict(Job j, double t, double dt, double night, double u, double pre) {
    _hideWall();
    for (final l in _letters) {
      if (!identical(l.node.mesh, l.full)) l.node.mesh = l.full;
      l.node
        ..visible = true
        ..place((m) => setTrs(m, l.at.x, l.at.y, l.at.z));
      _paintFull(l, night, 0);
    }
    fx.confettiShow(u + _pace.phaseLen(Phase.celebrate), wallWidth, j.serial);
    final g = Verdict3D.ballRest;
    final go = pre - Verdict3D.hookFrom, lower = pre - Verdict3D.latchAt - 0.6, down = pre - Verdict3D.latchAt, lift = pre - Verdict3D.liftAt;
    final above = vm.Vector3(g.x, g.y + 1.55 + 3.0, g.z), latch = vm.Vector3(g.x, g.y + 1.55, g.z);
    if (u < go) {
      crane.ballRest = g;
      _idleCrane(_parked, t, dt, night);
      return;
    }
    _cmdInit = true;
    if (u < lift) {
      crane.ballRest = g;
      if (u < lower) {
        _cmd.setFrom(polarLerp(_parked, above, eio(seg(u, go, lower))));
      } else {
        _cmd.setFrom(above + (latch - above) * eio(seg(u, lower, down)));
      }
      crane.update(_cmd, t, dt, night: night);
      return;
    }
    // Hooked on: up it goes.
    final ball = g + (_lifted - g) * eio(seg(u, lift, pre));
    ballAt.setFrom(ball);
    crane.swingBall(vm.Vector3(ball.x, 14, ball.z), ball, t, dt, night: night);
    if (u < lift + 0.5) fx.puff(g.x, 0.05, g.z, (u - lift) / 0.5, 0.9, seed: 7, n: 3);
  }

  List<_Fall> _planFalls(Job j, _Swing sw) {
    final plan = _plan!;
    final n = _standing(j, plan), cut = _cutT(j, plan);
    final out = <_Fall>[];
    for (var i = 0; i < plan.total; i++) {
      if (i >= n) {
        out.add(_Fall.never());
        continue;
      }
      final p = vm.Vector3(plan.cellX[i] + plan.offsetAt(plan.letter[i], cut), plan.cellY[i], 0);
      final pass = sw.passTime(p.x);
      final ballY = sw.yAtX(p.x);
      final dy = p.y - ballY, dz = 0 - sw.z;
      // In the ball's way if its surface comes within reach of the brick.
      final r = _Swing.radius + b * 0.55;
      final d2 = r * r - dy * dy - dz * dz;
      final hit = d2 > 0;
      vm.Vector3 v;
      double release;
      if (hit) {
        // Let go just as the ball (coming from the right) touches it: the
        // ball itself knocks it flying (it's solid; it barely notices a
        // brick). A little scatter of its own.
        release = math.max(sw.release, sw.passTime(p.x + math.sqrt(d2)) - 1 / 60);
        final away = vm.Vector3(0, dy, dz)..normalize();
        v = away * (0.5 + 0.8 * rnd(i, 4)) + vm.Vector3(0, 0.3 * rnd(i, 5), (rnd(i, 6) - 0.5) * 1.2);
      } else {
        // Shaken loose: it crumbles a moment after the ball passes (or as
        // soon as nothing holds it up: the wreck checks).
        final below = p.y < ballY;
        release = pass + 0.12 + (below ? 0.5 + 1.1 * rnd(i, 7) : 0.05 + 0.35 * rnd(i, 7)) + (wallHeight - p.y) * 0.03;
        v = vm.Vector3(-1.2 * rnd(i, 8) - 0.3, 0.8 * rnd(i, 9), (rnd(i, 10) - 0.5) * 2.0);
      }
      final fall = _Fall(p, v, release, _axesFor(i), 3 + 6 * rnd(i, 11), hit: hit);
      out.add(fall);
    }
    return out;
  }

  vm.Vector3 _axesFor(int i) => vm.Vector3(rnd(i, 3) - 0.5, rnd(i, 4) - 0.5, rnd(i, 5) - 0.5).normalized();

  // ── Cleanup: rubble flies into the recycling truck ─────────────────────────

  void _cleanup(Job j, double t, double dt, double night) {
    final len = math.max(j.phaseLen, 0.01);
    final u = j.since(t);
    final f = u / len;
    for (final l in _letters) {
      l.node.visible = false;
    }
    // The ball is hoisted away at once, up and over towards the crane, out
    // of the loader's way (it starts right where the ball came to hang);
    // carried back to its place by the yard and set down there.
    final sw = _swing;
    final rest = Verdict3D.ballRest;
    if (sw != null && f < 0.5) {
      final ball = _homeBall(sw, f);
      ballAt.setFrom(ball);
      crane.swingBall(vm.Vector3(ball.x, 14, ball.z), ball, t, dt, night: night);
    } else {
      if (sw != null) crane.ballRest = rest;
      _idleCrane(vm.Vector3(SiteLayout.mastX - 5, 9, SiteLayout.mastZ - 4), t, dt, night);
    }
    final falls = _falls;
    // The truck: in along the avenue's eastbound lane, braking; reversing
    // round into the bay by the rubble, tub first; out the same way.
    const park = SiteLayout.bayX, bay = SiteLayout.bayZ;
    _poseTruck(f, len, t);
    if (falls == null || !wreck.active) return;
    // The loader's bucketful: the bricks nearest where it starts. Whatever
    // else lies where the machine stands goes too (scooped in the cut):
    // nothing may start inside it.
    if (_gone.length != falls.length) {
      if (const String.fromEnvironment('BOOTH3D_TIMES') != '') debugPrint(wreck.report(_solids()));
      wreck.releaseAll();
      _gone = List.filled(falls.length, false);
      final from = loader.startAt(park);
      double away(int i) => (wreck.positionOf(i) - from).length2;
      final near = [
        for (var i = 0; i < falls.length; i++)
          if (falls[i].ever) i,
      ]..sort((a, c) => away(a).compareTo(away(c)));
      // (Without physics there's no loader: the rubble just goes at the cut.)
      final load = Physics.available ? near.take(40).toList() : const <int>[];
      for (final i in load) {
        wreck.pickUp(i);
        _gone[i] = true;
      }
      if (Physics.available) {
        for (final i in near) {
          if (_gone[i] || !loader.inTheWay(wreck.positionOf(i), park)) continue;
          wreck.pickUp(i);
          _gone[i] = true;
          _bricks.setInstanceTransform(i, hidden);
        }
        physics.clock = u;
        loader.start(physics, load, b, park, bay, (g) => _truckMatrix(g, len, park, bay), _placeBrick, (i) => _bricks.setInstanceTransform(i, hidden));
      }
    }
    // The rest of the rubble goes off camera (and whatever's left at the
    // cut to the swept plaza).
    var taken = 0;
    for (var i = 0; i < falls.length; i++) {
      if (!falls[i].ever) {
        _bricks.setInstanceTransform(i, hidden);
        continue;
      }
      if (_gone[i]) continue;
      if (f < 0.78 && (taken >= 30 || _inView(wreck.positionOf(i)))) continue;
      wreck.pickUp(i);
      _gone[i] = true;
      _bricks.setInstanceTransform(i, hidden);
      taken++;
    }
    loader.update(physics, f, cut: 0.78);
    final sw2 = _swing;
    wreck.settle(
      t,
      dt,
      beforeStep: (tu) {
        loader.beforeStep(physics, tu / len);
        if (sw2 != null) wreck.ballTo(_homeBall(sw2, math.min(tu / len, 0.5)));
      },
    );
    _wallHidden = false;
    if (j.cutAt == null) {
      fx.confettiShow(u + _pace.phaseLen(Phase.celebrate) + _pace.phaseLen(Phase.demolish), wallWidth, j.serial, fade: c01(f / 0.3));
    }
  }
}

/// The site's street works: the delivery's, else the cleanup truck's.
class _SiteWork implements StreetWork {
  _SiteWork(this.site);
  final Site3D site;

  @override
  (double, double)? laneBlock(bool eastbound, double t) {
    final d = site.delivery.laneBlock(eastbound, t);
    if (d != null || !eastbound) return d;
    final p = site._truckNow(t);
    if (p == null) return null;
    // In the lane (and, from a little before it pulls out of the bay,
    // the stretch it pulls out across).
    if (p.z <= -9.5) return (p.x - 4.2, p.x + 4.2);
    final j = site._job!;
    final f = j.phase == Phase.cleanup ? j.since(t) / math.max(j.phaseLen, 0.01) : 0.0;
    if (f > 0.74) return (SiteLayout.bayX - 2.0, SiteLayout.bayX + 8.4);
    return null;
  }

  @override
  (double, double)? gateBusy(double t) {
    final d = site.delivery.gateBusy(t);
    if (d != null) return d;
    final p = site._truckNow(t);
    if (p == null || p.z < -14 || p.z > -6.5) return null;
    const park = SiteLayout.bayX;
    // (Only while it's turning in or out across the pavement.)
    if ((p.x - park).abs() > 6) return null;
    return (math.min(p.x, park) - 3.2, math.max(p.x, park) + 3.2);
  }
}

class _Letter {
  _Letter(this.node, this.full, this.pieced, this.pieces, this.mat, this.paint, this.at, this.wall);
  final Node node;
  final vm.Vector3 at;

  /// Whole, and in pieces for the finish ([pieces]' primitives).
  final Mesh full, pieced;
  final List<_Piece> pieces;

  /// The whole letter's material, and its paint (linear).
  final PhysicallyBasedMaterial mat;
  final vm.Vector4 paint;

  /// The plan's letter it is (−1: none).
  final int wall;
}

/// A piece of a smooth letter for the finish: a band of brick rows (global
/// band [band], [FinishPlan.per] rows each) of the finish's unit [unit],
/// with its own material.
class _Piece {
  _Piece(this.prim, this.mat, this.unit, this.band);
  final MeshPrimitive prim;
  final PhysicallyBasedMaterial mat;
  final int unit, band;
}

/// The wrecking ball's swing: lowered at the right of the wall, then
/// released as a pendulum from above the middle, through the wall.
class _Swing {
  _Swing(this.w, this.h, this.len, {this.from, double floor = 0}) {
    pivotY = SiteLayout.jibY - 0.45 - 1.55 + 1.0;
    // (Its lowest point clears the plinths, whatever the wall's height.)
    l = pivotY - math.max(h * 0.42, floor + radius + 0.12);
    theta0 = math.asin(math.min(0.97, (w / 2 + 2.4) / l));
    omega = math.sqrt(SiteLayout.g / l);
    release = len * 0.26;
    // The first brick it reaches: the wall's right end at the ball's height.
    var first = double.infinity;
    for (var x = w / 2; x > -w / 2; x -= 0.1) {
      final y = yAtX(x);
      if (y - radius < h && y + radius > 0) {
        first = passTime(x);
        break;
      }
    }
    firstHit = first.isFinite ? first : release + 1;
  }

  final double w, h, len;
  late final double pivotY, l, theta0, omega, release, firstHit;

  /// Where the ball starts from (lifted off the ground by the yard, after
  /// the manager's visit), or null: lowered from above.
  final vm.Vector3? from;
  static const radius = 1.0;
  final z = -0.3;

  double get startX => l * math.sin(theta0);
  double get startY => pivotY - l * math.cos(theta0);

  double theta(double u) {
    final tau = u - release;
    if (tau <= 0) return theta0;
    return theta0 * math.cos(omega * tau) * math.exp(-0.09 * tau);
  }

  /// Where the trolley (the pendulum's pivot) is: over the start while the
  /// ball comes down, then over the middle.
  vm.Vector3 pivotAt(double u) {
    if (from != null && u < len * 0.2) {
      // Carried over on the hook, its cable straight up.
      final b = ballAt(u);
      return vm.Vector3(b.x, pivotY, b.z);
    }
    final shift = eio(seg(u, len * 0.2, release));
    return vm.Vector3(startX * (1 - shift), pivotY, z);
  }

  vm.Vector3 ballAt(double u) {
    final f = from;
    if (f != null && u < release) {
      // Swung over from where it was lifted, to its start.
      return polarLerp(f, vm.Vector3(startX, startY, z), eio(seg(u, 0, len * 0.2)));
    }
    if (u < release) {
      // Lowered from above to its start, hanging still.
      final down = eo(seg(u, 0, len * 0.2));
      return vm.Vector3(startX, lerp(startY + 5.5, startY, down), z);
    }
    final th = theta(u);
    // The last of it: hoisted (the crane takes up the cable as the swing
    // dies down), out of the way of the cleanup.
    final up = eio(seg(u, len - 1.8, len));
    return vm.Vector3(l * math.sin(th), pivotY - l * math.cos(th) + up * 5.0, z);
  }

  vm.Vector3 velocityAt(double u) {
    final tau = u - release;
    final th = theta(u);
    final dth = -theta0 * omega * math.sin(omega * tau) * math.exp(-0.09 * tau);
    return vm.Vector3(l * dth * math.cos(th), l * dth * math.sin(th), 0);
  }

  /// The ball's height where its arc crosses [x].
  double yAtX(double x) {
    final s = (x / l).clamp(-1.0, 1.0);
    return pivotY - l * math.cos(math.asin(s));
  }

  /// When (seconds into the demolition) the ball first passes [x].
  double passTime(double x) {
    final th = math.asin((x / l).clamp(-1.0, 1.0));
    final c = (th / theta0).clamp(-1.0, 1.0);
    return release + math.acos(c) / omega;
  }
}

/// How one brick comes out of the wall when the ball gets to it: when it's
/// let go, its velocity and spin then (the wreck's physics takes it from
/// there), and whether it was in the ball's way.
class _Fall {
  _Fall(this.p0, this.v0, this.release, this.axis, this.spin, {this.hit = false}) : ever = true;
  _Fall.never()
    : p0 = vm.Vector3.zero(),
      v0 = vm.Vector3.zero(),
      release = 1e9,
      axis = vm.Vector3(0, 1, 0),
      spin = 0,
      ever = false,
      hit = false;

  final vm.Vector3 p0, v0, axis;
  final double release, spin;
  final bool ever, hit;
  static const g = SiteLayout.g;

  /// Time from release to first touching the ground (y = b/2), flying free
  /// (to aim where the hit sends it).
  double landAt(double b) {
    final y0 = p0.y - b / 2;
    final vy = v0.y;
    return (vy + math.sqrt(vy * vy + 2 * g * math.max(0, y0))) / g;
  }
}
