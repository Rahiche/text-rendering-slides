import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'devices.dart';
import 'engine_pages.dart';
import 'kit.dart';
import 'models.dart';
import 'shapes.dart' show bevelBox;
import 'shot.dart';
import 'vignette.dart';

/// Engine Town: the neighbouring town out along the avenue east, where the
/// talk's "How others do it" goes. On the way out a road sign says you're
/// leaving Flutter City, and another welcomes you in. Round its square
/// stand the four other engines' headquarters, each with its logo huge on
/// its front — Chrome, Figma, Apple (macOS), Android — and its ground
/// floor open to the square: its text rendering room, the engine's stack
/// on a console (lit stage by stage as the room's turn comes) and its
/// screen on the wall, showing what its way of setting text gives it:
///
/// * Chrome (20–30 s): a web page, its text in the DOM: a headline balanced
///   over two lines, a paragraph hyphenated, a column of vertical Japanese
///   with ruby, all CSS; then find (Ctrl+F) lights up every "text", and a
///   sentence is selected, to copy or to translate;
/// * Figma (32–42 s): a design tool's canvas, its own text engine: a text
///   layer, mixed English and Arabic, zoomed from 100% to 400% to 1600%,
///   sharp all the way (drawn from the outlines each time);
/// * macOS (44–54 s): a document in Core Text: an English paragraph
///   justified and hyphenated, beside vertical Japanese with ruby, all
///   built into the platform;
/// * Android (56–66 s): a phone with one paragraph three times, as
///   Minikin's three break strategies lay it out: simple (first fit, what
///   Flutter does), balanced, and high quality (hyphenated); each lit in
///   turn.
///
/// The camera drives out of the city along the avenue (0–10.5 s), past the
/// signs, rises to take in the town; then, a room a turn, crosses the
/// square and goes in. (Every room opens on the square and the camera
/// stands just inside: from one room to the next it flies out through one
/// front and in through the other; from the last, back west to the city,
/// clear of the others.) Only a talk calls on it; the town itself stands
/// there all along.
class TalkTown extends Vignette {
  TalkTown(super.kit);

  @override
  String get name => 'town';
  @override
  String get kick => 'HOW OTHERS DO IT';
  @override
  String get line => 'Engine Town: four engines, four rooms';
  @override
  String get note => 'each one shows what its way of setting text gives it';

  @override
  bool get talkOnly => true;

  @override
  double get loop => 70;
  @override
  double get visit => 68;

  /// The middle of the town's square (world): the frame's origin, unturned.
  static final _o = vm.Vector3(270, 0, 8);
  @override
  final frame = vm.Matrix4.translation(_o);

  /// The headquarters round the square: each one's bearing from its middle
  /// (degrees, clockwise from north: their fronts face it), the arc's
  /// radius to their fronts; their width, depth, height; the open ground
  /// floor's height and the room's depth (its back wall, the screen's).
  static const _bearings = [-10.0, 30.0, 70.0, 110.0];
  static const _r = 24.0, _bw = 15.0, _bd = 13.0, _lobby = 7.0, _roomD = 9.0;
  static const _heights = [34.0, 24.0, 28.0, 26.0];

  /// Whose they are: name, accent (the band over the room's opening), the
  /// facade's photograph and tint, the name's colour on the front, and the
  /// stack its console shows.
  static const _names = ['Chrome', 'Figma', 'macOS', 'Android'];
  static const _accents = [0x4285F4, 0xA259FF, 0xC9CCD1, 0x3DDC84];
  static const _facades = [('facade_glass', 0xFFFFFF), ('facade_panel', 0xFFFFFF), ('facade_glass', 0xDCE4EA), ('facade_glass', 0xD6E6E2)];
  static const _inks = [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF)];
  static const _stacks = [
    ['<p>', 'CSS', 'LayoutNG', 'HarfBuzz', 'Skia'],
    ['C++', 'WASM', 'HarfBuzz + ICU', 'WebGPU'],
    ['TextKit 2', 'CTFrame', 'CTLine', 'CTRun', 'CGGlyph'],
    ['StaticLayout', 'Minikin', 'HarfBuzz'],
  ];

  /// Each turn's start (0: the drive out and the town), and when its
  /// screen's steps come.
  static const _acts = [0.0, 20.0, 32.0, 44.0, 56.0];
  static const _findAt = 5.0, _selectAt = 7.4;
  static const _zoom1 = 4.2, _zoom2 = 6.6;
  static const _lit = [3.2, 5.6, 8.0];

  /// A window's size, the phone's (m).
  static const _ww = 5.6, _wh = 3.5, _pw = 1.81, _ph = 3.81;

  late final Window3D _chrome, _figma, _mac;
  late final Phone3D _android;
  late final List<Texture2D> _chromePages, _figmaPages, _androidScreens;
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => [
    ...EnginePages.fontRuns,
    ('YOU ARE NOW LEAVING FLUTTER CITY Come back soon WELCOME TO ENGINE TOWN how others render text TEXT RENDERING ROOM ${_names.join(' ')} ${[for (final s in _stacks) ...s].join(' ')}', _ui.copyWith(fontSize: 40)),
  ];

  static const _ui = TextStyle(fontFamily: BP.display);

  /// Building [k]'s frame in the town's: its front's middle on the ground,
  /// facing the square (its −z).
  static vm.Matrix4 _at(int k) {
    final b = _bearings[k] * math.pi / 180;
    return trs(vm.Vector3(_r * math.sin(b), 0, _r * math.cos(b)), rotY: b);
  }

  @override
  Future<void> init() async {
    makePool(boxes: 4, cyls: 2, glows: 40);
    final pages = await Future.wait([
      EnginePages.chromePage(),
      EnginePages.chromePage(find: true),
      EnginePages.chromePage(find: true, select: true),
      EnginePages.figmaPage(1),
      EnginePages.figmaPage(4),
      EnginePages.figmaPage(16),
      EnginePages.macWindow(),
      EnginePages.androidScreen(-1),
      for (var k = 0; k < 3; k++) EnginePages.androidScreen(k),
    ]);
    _chromePages = pages.sublist(0, 3);
    _figmaPages = pages.sublist(3, 6);
    _androidScreens = pages.sublist(7, 11);
    _chrome = Window3D(detail, w: _ww, h: _wh, page: _chromePages[0], name: 'town chrome');
    _figma = Window3D(detail, w: _ww, h: _wh, page: _figmaPages[0], name: 'town figma');
    _mac = Window3D(detail, w: _ww, h: _wh, page: pages[6], name: 'town macos');
    _android = Phone3D(detail, make: PhoneMake.pixel, w: _pw, h: _ph, screen: _androidScreens[0], name: 'town android');
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') EnginePages.logBreaks();
    await _build();
    _ready = true;
  }

  // ── The town ──────────────────────────────────────────────────────────────

  Future<void> _build() async {
    final b = Batch();
    final facades = await Future.wait([for (final (n, tint) in _facades) photoPbr(n, tint: v4(hex3(tint)))]);
    final backs = await Future.wait([photoPbr('facade_stone'), photoPbr('facade_tile')]);
    final paving = await photoPbr('pavement'), tiles = await photoPbr('plaza_tiles');
    final stone = pbr(rgb(1, 1, 1), roughness: 0.6), dark = pbr(rgb(1, 1, 1), roughness: 0.35, metallic: 0.1);
    final lamp = pbr(rgb(1, 1, 1), emissive: rgb(1, 0.96, 0.88), emissiveStrength: 2.2);
    // The town's ground paved, from the avenue to its back streets; the
    // square in tiles round its middle, out to the headquarters' fronts.
    b
      ..add(paving, _laid(CuboidGeometry(vm.Vector3(102, 0.3, 89)).extractMeshData(), vm.Vector3(15, -0.25, 25.5)).transformed(frame))
      ..add(tiles, _laid(CylinderGeometry(bottomRadius: _r + 0.6, topRadius: _r + 0.6, height: 0.3, radialSegments: 72).extractMeshData(), vm.Vector3(0, -0.23, 0)).transformed(frame));
    for (var k = 0; k < 4; k++) {
      final m = frame * _at(k);
      void box(Material mat, double w, double h, double d, double x, double y, double z, int rgb) =>
          b.add(mat, painted(bevelBox(w, h, d).transformed(m * trs(vm.Vector3(x, y, z))), v4(hex3(rgb))));
      final h = _heights[k];
      // Its floors over the room, faced in its photograph.
      b.add(facades[k], painted(_facade(_bw, h - _lobby, _bd).transformed(m * trs(vm.Vector3(0, _lobby, _bd / 2))), vm.Vector4(1, 1, 1, 1)));
      // The ground floor: stone sides and back, the room open to the
      // square; its floor, ceiling, dark walls, its back wall (the screen's).
      for (final s in [-1.0, 1.0]) {
        box(stone, 0.5, _lobby, _bd, s * (_bw / 2 - 0.25), _lobby / 2, _bd / 2, 0x8E9196);
        box(dark, 0.04, _lobby - 0.3, _roomD, s * (_bw / 2 - 0.52), (_lobby - 0.3) / 2, _roomD / 2, 0x262B33);
      }
      box(stone, _bw, _lobby, 0.3, 0, _lobby / 2, _bd - 0.15, 0x8E9196);
      box(dark, _bw - 1.0, _lobby, 0.3, 0, _lobby / 2, _roomD, 0x1A2230);
      box(dark, _bw - 1.0, 0.12, _roomD, 0, 0.06, _roomD / 2, 0x30343B);
      box(stone, _bw - 1.0, 0.3, _roomD, 0, _lobby - 0.15, _roomD / 2, 0x1C2026);
      // Over the opening, a band of the company's colour; a parapet on top.
      box(stone, _bw + 0.3, 0.6, 0.45, 0, _lobby - 0.3, -0.12, _accents[k]);
      box(stone, _bw + 0.3, 0.5, _bd + 0.3, 0, h + 0.25, _bd / 2, 0x4A4F57);
      // Light strips on the ceiling.
      for (final x in [-4.6, 0.9, 5.4]) {
        b.add(lamp, painted(bevelBox(0.18, 0.05, _roomD - 1.6).transformed(m * trs(vm.Vector3(x, _lobby - 0.33, _roomD / 2))), vm.Vector4(1, 1, 1, 1)));
      }
      // The console in front of the screen: a long desk, a light strip of
      // the company's colour along its front.
      box(dark, 7.6, 0.92, 1.0, 0.9, 0.46, 6.3, 0x2A2F38);
      box(dark, 7.7, 0.05, 1.1, 0.9, 0.945, 6.3, 0x3A404B);
      box(stone, 7.6, 0.04, 0.02, 0.9, 0.78, 5.79, _accents[k]);
    }
    // Lower blocks round them: the town round its square.
    for (final (i, (bearing, r, w, h)) in [
      (-36.0, 50.0, 18.0, 16.0),
      (10.0, 50.0, 20.0, 19.0),
      (50.0, 49.0, 18.0, 15.0),
      (90.0, 50.0, 20.0, 18.0),
      (132.0, 47.0, 16.0, 14.0),
      (-62.0, 48.0, 16.0, 12.0),
      (-12.0, 68.0, 22.0, 24.0),
      (32.0, 70.0, 20.0, 21.0),
      (72.0, 69.0, 22.0, 23.0),
      (112.0, 66.0, 18.0, 17.0),
    ].indexed) {
      final a = bearing * math.pi / 180;
      final m = frame * trs(vm.Vector3(r * math.sin(a), 0, r * math.cos(a)), rotY: a);
      b
        ..add(backs[i % 2], painted(_facade(w, h, 12, ou: 0.25 * i, ov: 0.375 * i).transformed(m * trs(vm.Vector3(0, 0, 6))), vm.Vector4(1, 1, 1, 1)))
        ..add(stone, painted(bevelBox(w + 0.3, 0.4, 12.3).transformed(m * trs(vm.Vector3(0, h + 0.2, 6))), v4(hex3(0x5A5E64))));
    }
    // The road signs' posts (their boards: [_signs]).
    for (final x in _signX) {
      for (final s in [-1.0, 1.0]) {
        b.add(stone, painted(bevelBox(0.2, 6.2, 0.2).transformed(frame * vm.Matrix4.translation(vm.Vector3(x + 0.14, 3.1, _signZ + s * 3.9))), v4(hex3(0x7C8288))));
      }
    }
    b.buildInto(shell, 'engine town', castsShadows: false, lightChannelMask: 0x01);
    await Future.wait([_logos(), _signs(), _rooms(), _trees()]);
  }

  /// Trees along the avenue's frontage and round the square's open side
  /// (none in front of a headquarters: the camera's way in), the city's.
  Future<void> _trees() async {
    final bark = pbr(lin(const Color(0xFF6A5442)), roughness: 0.92), leaves = pbr(rgb(1, 1, 1), roughness: 0.82);
    final models = await Future.wait([for (final m in ['round', 'tall', 'wide']) modelParts('assets/models/tree_$m.glb')]);
    final trunks = [for (final m in models) InstancedMesh(geometry: MeshGeometry.fromMeshData(m['trunk']!), material: bark)];
    final crowns = [for (final m in models) InstancedMesh(geometry: MeshGeometry.fromMeshData(m['crown']!), material: leaves)];
    const greens = [0x22705A, 0x2B8166, 0x338D6E, 0x1F6450, 0x3B9878];
    final spots = [
      for (var x = -32.0; x <= 62; x += 9.5) (x, -16.5),
      for (final bearing in [-48.0, -70.0, -92.0, -114.0, -136.0, -158.0, 152.0]) (21.5 * math.sin(bearing * math.pi / 180), 21.5 * math.cos(bearing * math.pi / 180)),
    ];
    for (final (i, (x, z)) in spots.indexed) {
      if (z < -10 && x > 12) continue; // (the south-east corner: the last headquarters' front)
      final v = i % 3, at = frame * trs(vm.Vector3(x, 0, z), rotY: rnd(i, 3) * 6, s: vm.Vector3.all(0.9 + 0.3 * rnd(i, 1)));
      trunks[v].addInstance(at);
      crowns[v].addInstance(at, color: v4(hex3(greens[i % greens.length])));
    }
    for (var v = 0; v < 3; v++) {
      for (final m in [trunks[v], crowns[v]]) {
        shell.add(
          Node(name: 'town trees')
            ..lightChannelMask = 0x01
            ..addComponent(InstancedMeshComponent(m)),
        );
      }
    }
  }

  /// A building [w]×[h]×[d] (its bottom middle at the origin) faced in a
  /// photographed facade, its windows at their real size: a texture holds
  /// 8×8 cells of 1.7 × 2.6 m (from [ou], [ov] into it); the roof plain.
  static MeshData _facade(double w, double h, double d, {double ou = 0, double ov = 0}) {
    const cw = 1.7 * 8, ch = 2.6 * 8;
    final pos = <double>[], nor = <double>[], uv = <double>[], idx = <int>[];
    void quad(vm.Vector3 o, vm.Vector3 u, vm.Vector3 v, vm.Vector3 n, double uw, double vh, {bool roof = false}) {
      final base = pos.length ~/ 3;
      for (final (a, c) in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]) {
        final p = o + u * (a * uw) + v * (c * vh);
        pos.addAll([p.x, p.y, p.z]);
        nor.addAll([n.x, n.y, n.z]);
        uv.addAll(roof ? [0.004, 0.004] : [ou + a * uw / cw, ov + (1 - c) * vh / ch]);
      }
      if (u.cross(v).dot(n) > 0) {
        idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
      } else {
        idx.addAll([base, base + 2, base + 1, base, base + 3, base + 2]);
      }
    }

    final x0 = -w / 2, z0 = -d / 2;
    final ux = vm.Vector3(1, 0, 0), uy = vm.Vector3(0, 1, 0), uz = vm.Vector3(0, 0, 1);
    quad(vm.Vector3(x0, 0, z0), ux, uy, vm.Vector3(0, 0, -1), w, h);
    quad(vm.Vector3(-x0, 0, -z0), -ux, uy, vm.Vector3(0, 0, 1), w, h);
    quad(vm.Vector3(x0, 0, -z0), -uz, uy, vm.Vector3(-1, 0, 0), d, h);
    quad(vm.Vector3(-x0, 0, z0), uz, uy, vm.Vector3(1, 0, 0), d, h);
    quad(vm.Vector3(x0, h, z0), ux, uz, vm.Vector3(0, 1, 0), w, d, roof: true);
    return MeshData(positions: Float32List.fromList(pos), vertexCount: pos.length ~/ 3, normals: Float32List.fromList(nor), texCoords: Float32List.fromList(uv), indices: idx);
  }

  /// [d] (a slab: paving) moved to [at] in the town's frame, its texture
  /// laid at 3 m a tile where it is in the world.
  static MeshData _laid(MeshData d, vm.Vector3 at) {
    final m = d.transformed(vm.Matrix4.translation(at));
    final uv = Float32List(m.vertexCount * 2);
    for (var i = 0; i < m.vertexCount; i++) {
      uv
        ..[i * 2] = (_o.x + m.positions[i * 3]) / 3
        ..[i * 2 + 1] = (_o.z + m.positions[i * 3 + 2]) / 3;
    }
    return painted(m, vm.Vector4(1, 1, 1, 1), uvs: uv);
  }

  // ── The logos ─────────────────────────────────────────────────────────────

  /// Each company's logo, huge on its front over the room, its name under
  /// it (cut out: the facade shows round them).
  Future<void> _logos() async {
    const painters = [_chromeLogo, _figmaLogo, _appleLogo, _androidLogo];
    for (var k = 0; k < 4; k++) {
      final tex = await paintedTexture(1024, 1024, (c, s) {
        painters[k](c, const Rect.fromLTWH(132, 30, 760, 760));
        Vignette.text(c, _names[k], const Rect.fromLTWH(40, 810, 944, 190), 150, _inks[k], weight: FontWeight.w700);
      });
      final mat = PhysicallyBasedMaterial()
        ..baseColorTexture = tex
        ..alphaMode = AlphaMode.mask
        ..alphaCutoff = 0.5
        ..metallicFactor = 0
        ..roughnessFactor = 0.45
        ..emissiveTexture = tex
        ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
        ..emissiveStrength = 0.45;
      kit.signs.add(mat);
      final size = math.min(11.0, _heights[k] - _lobby - 3.0), y = _lobby + (_heights[k] - _lobby) / 2 + 0.6;
      shell.add(
        Node(name: 'town logo ${_names[k]}', mesh: Mesh(boardGeometry(size, size, thick: 0.02), mat), localTransform: frame * _at(k) * vm.Matrix4.translation(vm.Vector3(0, y, -0.08)))..castsShadows = false,
      );
    }
  }

  /// Chrome's: three blades round a white ring and a blue middle, each
  /// blade's cut tangent to the ring.
  static void _chromeLogo(Canvas c, Rect box) {
    final o = box.center, rr = box.shortestSide / 2, ri = rr * 0.46, rb = rr * 0.37;
    // (Angles counter-clockwise from the right, as on paper: the canvas's y
    // runs down.)
    Offset at(double r, double a) => o + Offset(r * math.cos(a), -r * math.sin(a));
    const deg = math.pi / 180;
    const touch = [90 * deg, 210 * deg, 330 * deg], run = [0.0, 120 * deg, 240 * deg];
    final len = math.sqrt(rr * rr - ri * ri);
    final ends = [
      for (var k = 0; k < 3; k++)
        () {
          final e = at(ri, touch[k]) + Offset(len * math.cos(run[k]), -len * math.sin(run[k])) - o;
          return math.atan2(-e.dy, e.dx);
        }(),
    ];
    const colors = [Color(0xFFEA4335), Color(0xFF34A853), Color(0xFFFBBC04)];
    for (var k = 0; k < 3; k++) {
      final n = (k + 1) % 3;
      final p0 = at(ri, touch[k]);
      final path = Path()..moveTo(p0.dx, p0.dy);
      var a0 = ends[k], a1 = ends[n];
      while (a1 <= a0) {
        a1 += 2 * math.pi;
      }
      for (var i = 0; i <= 48; i++) {
        final p = at(rr, a0 + (a1 - a0) * i / 48);
        path.lineTo(p.dx, p.dy);
      }
      final p1 = at(ri, touch[n]);
      path
        ..lineTo(p1.dx, p1.dy)
        ..close();
      c.drawPath(path, Paint()..color = colors[k]);
    }
    c
      ..drawCircle(o, ri, Paint()..color = const Color(0xFFFFFFFF))
      ..drawCircle(o, rb, Paint()..color = const Color(0xFF4285F4));
  }

  /// Figma's: five shapes on a grid two wide and three tall.
  static void _figmaLogo(Canvas c, Rect box) {
    final a = math.min(box.width / 2, box.height / 3) * 0.92;
    final x0 = box.center.dx - a, y0 = box.center.dy - 1.5 * a;
    final r = Radius.circular(a / 2);
    RRect cell(int col, int row, {bool left = false, bool right = false, bool bottomRight = false}) => RRect.fromRectAndCorners(
      Rect.fromLTWH(x0 + col * a, y0 + row * a, a, a),
      topLeft: left ? r : Radius.zero,
      bottomLeft: left ? r : Radius.zero,
      topRight: right ? r : Radius.zero,
      bottomRight: right || bottomRight ? r : Radius.zero,
    );
    c
      ..drawRRect(cell(0, 0, left: true), Paint()..color = const Color(0xFFF24E1E))
      ..drawRRect(cell(1, 0, right: true), Paint()..color = const Color(0xFFFF7262))
      ..drawRRect(cell(0, 1, left: true), Paint()..color = const Color(0xFFA259FF))
      ..drawCircle(Offset(x0 + 1.5 * a, y0 + 1.5 * a), a / 2, Paint()..color = const Color(0xFF1ABCFE))
      ..drawRRect(cell(0, 2, left: true, bottomRight: true), Paint()..color = const Color(0xFF0ACF83));
  }

  /// Apple's: the apple, a bite out of its right side, its leaf.
  static void _appleLogo(Canvas c, Rect box) {
    final s = box.shortestSide, o = box.topLeft + Offset((box.width - s) / 2, (box.height - s) / 2);
    Offset p(double x, double y) => o + Offset(x * s, y * s);
    final body = Path()..moveTo(p(0.5, 0.30).dx, p(0.5, 0.30).dy);
    void curve(double x1, double y1, double x2, double y2, double x, double y) {
      final a = p(x1, y1), b = p(x2, y2), e = p(x, y);
      body.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
    }

    curve(0.43, 0.26, 0.33, 0.24, 0.25, 0.27);
    curve(0.13, 0.32, 0.08, 0.45, 0.09, 0.58);
    curve(0.10, 0.74, 0.20, 0.92, 0.32, 0.94);
    curve(0.40, 0.95, 0.44, 0.91, 0.50, 0.91);
    curve(0.56, 0.91, 0.60, 0.95, 0.68, 0.94);
    curve(0.78, 0.92, 0.86, 0.82, 0.91, 0.70);
    curve(0.82, 0.65, 0.76, 0.57, 0.77, 0.48);
    curve(0.78, 0.40, 0.82, 0.36, 0.86, 0.33);
    curve(0.80, 0.26, 0.71, 0.24, 0.63, 0.26);
    curve(0.58, 0.27, 0.54, 0.29, 0.50, 0.30);
    body.close();
    final white = Paint()..color = const Color(0xFFF5F5F7);
    c
      ..drawPath(body, white)
      ..save()
      ..translate(p(0.565, 0.135).dx, p(0.565, 0.135).dy)
      ..rotate(math.pi / 4)
      ..drawOval(Rect.fromCenter(center: Offset.zero, width: 0.11 * s, height: 0.22 * s), white)
      ..restore();
  }

  /// Android's: the robot's head, its antennae and eyes.
  static void _androidLogo(Canvas c, Rect box) {
    final r = box.width * 0.44, o = Offset(box.center.dx, box.center.dy + r * 0.38);
    final green = Paint()..color = const Color(0xFF3DDC84);
    c.drawArc(Rect.fromCircle(center: o, radius: r), math.pi, math.pi, true, green);
    final stroke = Paint()
      ..color = const Color(0xFF3DDC84)
      ..strokeWidth = r * 0.075
      ..strokeCap = StrokeCap.round;
    for (final sd in [-1.0, 1.0]) {
      final a = o + Offset(sd * r * 0.5, -r * 0.8);
      c.drawLine(a, a + Offset(sd * r * 0.2, -r * 0.32), stroke);
      c.drawCircle(o + Offset(sd * r * 0.42, -r * 0.42), r * 0.075, Paint()..color = const Color(0xFF202124));
    }
  }

  // ── The road signs ────────────────────────────────────────────────────────

  /// Where the two signs stand (town frame): beside the avenue going east,
  /// facing the traffic coming out of the city (its west).
  static const _signX = [-118.0, -70.0];
  static const _signZ = -12.5;

  Future<void> _signs() async {
    Future<void> board(double x, Color ground, String top, String big, String under) => sign(9.0, 3.4, trs(vm.Vector3(x, 4.3, _signZ), rotY: math.pi / 2), (c, s) {
      final r = Offset.zero & s;
      c
        ..drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s.height * 0.08)), Paint()..color = ground)
        ..drawRRect(
          RRect.fromRectAndRadius(r.deflate(s.height * 0.05), Radius.circular(s.height * 0.06)),
          Paint()
            ..color = const Color(0xFFF4F6F8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.height * 0.025,
        );
      Vignette.text(c, top, Rect.fromLTWH(0, s.height * 0.12, s.width, s.height * 0.2), s.height * 0.13, const Color(0xFFF4F6F8), weight: FontWeight.w600);
      Vignette.text(c, big, Rect.fromLTWH(0, s.height * 0.32, s.width, s.height * 0.36), s.height * 0.3, const Color(0xFFFFFFFF), weight: FontWeight.w800);
      Vignette.text(c, under, Rect.fromLTWH(0, s.height * 0.7, s.width, s.height * 0.18), s.height * 0.11, const Color(0xFFDDE6EE), weight: FontWeight.w500);
    }, px: 1500, glow: 0.3, thick: 0.08, shell: true);

    await Future.wait([
      board(_signX[0], const Color(0xFF0E6B3B), 'YOU ARE NOW LEAVING', 'FLUTTER CITY', 'Come back soon'),
      board(_signX[1], const Color(0xFF1B4F8C), 'WELCOME TO', 'ENGINE TOWN', 'how others render text'),
    ]);
  }

  // ── The rooms ─────────────────────────────────────────────────────────────

  /// Where each room's console stages stand along its desk (the
  /// building's x).
  final _stageX = <List<double>>[];

  Future<void> _rooms() async {
    final waits = <Future<void>>[];
    for (var k = 0; k < 4; k++) {
      final m = _at(k), stack = _stacks[k], n = stack.length;
      final xs = <double>[];
      for (var i = 0; i < n; i++) {
        // Upright on the desk, along it.
        final x = 0.9 + (i - (n - 1) / 2) * (6.6 / n);
        xs.add(x);
        waits.add(
          sign(math.min(1.3, 6.6 / n - 0.16), 0.46, m * trs(vm.Vector3(x, 1.2, 6.0)), (c, s) {
            c.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height * 0.16)), Paint()..color = const Color(0xFF111722));
            Vignette.text(c, stack[i], Rect.fromLTWH(s.width * 0.06, 0, s.width * 0.88, s.height), s.height * 0.42, const Color(0xFFF2F4F8), family: BP.mono, weight: FontWeight.w700);
          }, px: 420, glow: 0.7, thick: 0.05),
        );
      }
      _stageX.add(xs);
      // Over the screen: what the room is.
      waits.add(
        sign(5.4, 0.5, m * trs(vm.Vector3(0.9, 5.9, _roomD - 0.18)), (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0E1420));
          Vignette.text(c, 'TEXT RENDERING ROOM', Rect.fromLTWH(0, 0, s.width, s.height), s.height * 0.5, Color(0xFF000000 | _accents[k]), family: BP.mono, weight: FontWeight.w700);
        }, px: 1080, glow: 0.8, thick: 0.03),
      );
    }
    await Future.wait(waits);
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    pool.begin();
    if (!visited) {
      for (final w in [_chrome, _figma, _mac]) {
        w.hide();
      }
      _android.hide();
      pool.end();
      return;
    }
    // Each screen as far into its turn as it's got (before it, as it
    // starts; after it, as it ended).
    double into(int k) => u - _acts[k + 1];
    _chrome.page = _chromePages[into(0) < _findAt ? 0 : (into(0) < _selectAt ? 1 : 2)];
    _figma.page = _figmaPages[into(1) < _zoom1 ? 0 : (into(1) < _zoom2 ? 1 : 2)];
    final lit = into(3) < _lit[0] ? -1 : (into(3) < _lit[1] ? 0 : (into(3) < _lit[2] ? 1 : 2));
    _android.screen = _androidScreens[lit + 1];
    for (final (k, w) in [_chrome, _figma, _mac].indexed) {
      w.place(frame * _at(k) * vm.Matrix4.translation(vm.Vector3(0.9, 3.25, _roomD - 0.38)));
    }
    _android.place(frame * _at(3) * vm.Matrix4.translation(vm.Vector3(0.9, 2.95, _roomD - 0.45)));
    // The console's stages light up in turn as the room's turn comes; the
    // way on to the next one too.
    for (var k = 0; k < 4; k++) {
      final a = into(k), xs = _stageX[k], w = math.min(1.3, 6.6 / xs.length - 0.16);
      for (var i = 0; i < xs.length; i++) {
        final on = seg(a, 1.4 + 0.55 * i, 1.7 + 0.55 * i);
        if (on <= 0) continue;
        final c = v4(hex3(_accents[k])) * (3.0 * on);
        _glowIn(k, xs[i], 0.975, 5.72, w * 0.9, 0.025, 0.06, c);
        if (i + 1 < xs.length) _glowIn(k, (xs[i] + xs[i + 1]) / 2, 1.2, 6.0, 0.09, 0.03, 0.03, c);
      }
    }
    pool.end();
  }

  /// The prop pool's glowing box at (x, y, z) of building [k]'s frame,
  /// turned as it is (its sides along its front).
  void _glowIn(int k, double x, double y, double z, double sx, double sy, double sz, vm.Vector4 c) {
    final p = _at(k).transform3(vm.Vector3(x, y, z));
    pglow(p.x, p.y, p.z, sx, sy, sz, c, yaw: _bearings[k] * math.pi / 180);
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// The drive: out of the city along the avenue's eastbound lane (world),
  /// past the signs, then up and round to take in the town from its
  /// south-west; how long it takes; where the camera looks at the end.
  static final _drive = _Path([
    vm.Vector3(36, 4.6, -13),
    vm.Vector3(95, 4.6, -13),
    vm.Vector3(150, 4.6, -13),
    vm.Vector3(205, 5.0, -13),
    vm.Vector3(226, 9.5, -19),
    vm.Vector3(236, 17, -34),
    vm.Vector3(240, 21, -42),
  ]);
  static const _driveT = 10.5;
  static final _townAim = vm.Vector3(259.5, 13, 14.7);

  @override
  Shot shot(double u) {
    if (u < _acts[1] - 0.01) return _driving(u);
    final k = (_acts.lastIndexWhere((a) => u >= a - 0.01) - 1).clamp(0, 3);
    return _room(k, u - _acts[k + 1]);
  }

  Shot _driving(double u) {
    final f = _Path.pace(u / _driveT);
    final p = _drive.at(f * _drive.length, vm.Vector3.zero());
    final ahead = p + vm.Vector3(40, -3.2, 0);
    final k = smooth(0.6, 1.0, f);
    final target = ahead + (_townAim - ahead) * k;
    return Shot(p - _o, target - _o, fov: 50, settle: 1.0, drift: lerp(0.1, 0.6, k));
  }

  /// The way into a room (its building's frame): from the square, in
  /// through its open front, to just inside.
  static final _in = _Path([vm.Vector3(0, 2.6, -12.0), vm.Vector3(-1.5, 2.7, -0.8), vm.Vector3(-3.0, 2.8, 1.4)]);

  /// Room [k]'s turn, [a] seconds in: in at its front, the screen and the
  /// console right of the card.
  Shot _room(int k, double a) {
    final m = _at(k);
    final f = eio(seg(a, 0.3, 3.8));
    final eye = _in.at(f * _in.length, vm.Vector3.zero());
    // (Its end framed so the screen, the console and the room's sign all sit
    // right of the card: the room a little wide-angle, as a room is.)
    final t0 = vm.Vector3(0, 3.2, _roomD), t1 = vm.Vector3(-1.0, 2.8, _roomD - 0.4);
    final target = t0 + (t1 - t0) * eio(seg(f, 0.2, 1.0));
    return Shot(m.transform3(eye), m.transform3(target), fov: lerp(50, 56, f), settle: 1.0, drift: lerp(0.4, 0.2, f));
  }
}

/// A smooth way through points (Catmull-Rom), measured along its length.
class _Path {
  _Path(List<vm.Vector3> pts) {
    vm.Vector3 p(int i) => pts[i.clamp(0, pts.length - 1)];
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = p(i - 1), b = p(i), c = p(i + 1), d = p(i + 2);
      for (var k = 0; k < 16; k++) {
        final u = k / 16, u2 = u * u, u3 = u2 * u;
        _pts.add((b * 2.0 + (c - a) * u + (a * 2.0 - b * 5.0 + c * 4.0 - d) * u2 + (b * 3.0 - a - c * 3.0 + d) * u3) * 0.5);
      }
    }
    _pts.add(pts.last.clone());
    _len.add(0);
    for (var i = 1; i < _pts.length; i++) {
      _len.add(_len.last + _pts[i].distanceTo(_pts[i - 1]));
    }
  }

  final _pts = <vm.Vector3>[];
  final _len = <double>[];

  double get length => _len.last;

  /// The point [s] metres along it, into [out].
  vm.Vector3 at(double s, vm.Vector3 out) {
    final x = s.clamp(0.0, length);
    var i = 1;
    while (i < _len.length - 1 && _len[i] < x) {
      i++;
    }
    final f = (x - _len[i - 1]) / math.max(1e-6, _len[i] - _len[i - 1]);
    return out
      ..setFrom(_pts[i - 1])
      ..add((_pts[i] - _pts[i - 1]) * f);
  }

  /// How far along (0..1) [u] of the way through its time: speeding up,
  /// a steady pace, slowing down to stop.
  static double pace(double u) {
    const a = 0.14, d = 0.3, v = 1 / (1 - a / 2 - d / 2);
    final x = u.clamp(0.0, 1.0);
    if (x < a) return v * x * x / (2 * a);
    if (x > 1 - d) return 1 - v * (1 - x) * (1 - x) / (2 * d);
    return v * (a / 2 + x - a);
  }
}
