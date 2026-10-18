import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shapes.dart';

/// Every device made (their roots), for the loading screen's warm-up: the
/// glass's clear coat is a pipeline of its own, compiled then, not the
/// first time a device appears on stage.
final deviceRoots = <Node>[];

/// Whose phone: an iPhone (titanium, a flat-sided frame, the Dynamic
/// Island, three lenses in a square bump) or a Pixel (a rounder aluminium
/// frame, a punch-hole camera, the camera bar across its back).
enum PhoneMake { iphone, pixel }

/// A phone made like one, any size: the metal frame with its edges
/// rounded off, the front all glass (a thin black border round the screen,
/// the island or the punch hole), the back glass with its cameras, the
/// buttons on its sides. Its screen takes a texture upright; [wide] shows
/// the screen as the phone's turned on its side (a quarter turn about its
/// face's normal), laid out again, upright.
class Phone3D {
  Phone3D(Node parent, {required this.make, required this.w, required this.h, this.d = 0.16, required Texture2D screen, Texture2D? wide, String name = 'phone'})
    : root = Node(name: name) {
    screenMat = deviceScreen(screen);
    wideMat = deviceScreen(wide ?? screen);
    final ip = make == PhoneMake.iphone;
    final cr = (ip ? 0.135 : 0.12) * w, edge = (ip ? 0.24 : 0.45) * d;
    final glass = 0.008 * w, bezel = 0.03 * w;
    final sw = w - 2 * bezel, sh = h - 2 * bezel;
    // (What stands proud of its faces, in proportion: a phone of any size.)
    final e = d / 80;
    final frame = ip ? _titanium : _aluminium, back = ip ? _frostedBack : _obsidianBack;
    void add(MeshData m, Material mat, vm.Matrix4 at, {bool shadow = false}) => root.add(
      Node(name: '$name part', mesh: Mesh(geometryOf(m), mat), localTransform: at)..castsShadows = shadow,
    );
    vm.Matrix4 at(double x, double y, double z, {double rotX = 0, double rotZ = 0}) => trs(vm.Vector3(x, y, z), rotX: rotX, rotZ: rotZ);
    // The frame; the glass over its front and its back.
    add(roundedSlab(w, h, d, corner: cr, edge: edge, cornerSteps: 10, edgeSteps: 5), frame, at(0, 0, 0), shadow: true);
    add(roundedPlate(w - 2 * glass, h - 2 * glass, cr - glass), _blackGlass, at(0, 0, -d / 2 - e));
    add(roundedPlate(w - 2 * glass, h - 2 * glass, cr - glass, back: true), back, at(0, 0, d / 2 + e));
    // The screen, upright and on its side.
    _portrait = Node(name: '$name screen', mesh: Mesh(geometryOf(roundedPlate(sw, sh, cr - bezel)), screenMat), localTransform: at(0, 0, -d / 2 - 2 * e))
      ..castsShadows = false;
    _landscape = Node(name: '$name screen wide', mesh: Mesh(geometryOf(roundedPlate(sh, sw, cr - bezel)), wideMat), localTransform: at(0, 0, -d / 2 - 2 * e, rotZ: -math.pi / 2))
      ..castsShadows = false
      ..visible = false;
    root
      ..add(_portrait)
      ..add(_landscape);
    // The front camera: the island, or a punch hole.
    final top = h / 2 - bezel;
    if (ip) {
      add(roundedPlate(0.3 * sw, 0.085 * sw, 0.0425 * sw), _blackGlass, at(0, top - 0.028 * sw - 0.0425 * sw, -d / 2 - 3 * e));
    } else {
      add(disc(0.026 * sw), _blackGlass, at(0, top - 0.055 * sw, -d / 2 - 3 * e));
    }
    // The cameras on the back.
    final bz = d / 2 + e;
    if (ip) {
      final b = 0.44 * w, bd = 0.028 * w;
      final cx = -w / 2 + glass + 0.06 * w + b / 2, cy = h / 2 - glass - 0.06 * w - b / 2;
      add(roundedSlab(b, b, bd, corner: 0.27 * b, edge: 0.3 * bd), _bump, at(cx, cy, bz + bd / 2));
      for (final (lx, ly) in [(-0.22, 0.22), (-0.22, -0.22), (0.22, 0.0)]) {
        _lens(cx + lx * b, cy + ly * b, bz + bd, 0.165 * b, frame);
      }
      add(disc(0.055 * b, back: true), _flash, at(cx + 0.22 * b, cy + 0.25 * b, bz + bd + e));
      add(disc(0.06 * b, back: true), _blackGlass, at(cx + 0.22 * b, cy - 0.25 * b, bz + bd + e));
    } else {
      final bw = w - 2 * glass - 0.04 * w, bh = 0.2 * w, bd = 0.03 * w, cy = h / 2 - 0.36 * w;
      add(roundedSlab(bw, bh, bd, corner: bh / 2, edge: 0.4 * bd), _visor, at(0, cy, bz + bd / 2));
      for (final lx in [-0.24, -0.05]) {
        _lens(lx * w, cy, bz + bd, 0.33 * bh, frame);
      }
      add(disc(0.09 * bh, back: true), _flash, at(0.2 * w, cy, bz + bd + e));
    }
    // The buttons on the sides.
    final bt = 0.012 * w, bdz = 0.42 * d;
    final buttons = ip
        ? [(-1.0, 0.33, 0.055), (-1.0, 0.24, 0.085), (-1.0, 0.13, 0.085), (1.0, 0.2, 0.14)]
        : [(1.0, 0.25, 0.07), (1.0, 0.08, 0.14)];
    for (final (side, y, len) in buttons) {
      add(roundedSlab(bt * 2, len * h, bdz, corner: bt, edge: bt * 0.9), frame, at(side * (w / 2 + bt * 0.3), y * h, 0));
    }
    parent.add(root..visible = false);
    deviceRoots.add(root);
  }

  final PhoneMake make;
  final double w, h, d;
  final Node root;
  late final PhysicallyBasedMaterial screenMat, wideMat;
  late final Node _portrait, _landscape;

  /// A lens: its barrel (the frame's metal) standing out of the back, the
  /// glass in it (centred at x, y; its foot at [z]).
  void _lens(double x, double y, double z, double r, Material metal) {
    final depth = 0.22 * d;
    final barrel = CylinderGeometry(bottomRadius: r, topRadius: r * 0.96, height: depth, radialSegments: 28);
    root
      ..add(Node(name: 'phone lens', mesh: Mesh(barrel, metal), localTransform: trs(vm.Vector3(x, y, z + depth / 2), rotX: math.pi / 2))..castsShadows = false)
      ..add(Node(name: 'phone lens glass', mesh: Mesh(geometryOf(disc(r * 0.78, back: true)), _lensGlass), localTransform: trs(vm.Vector3(x, y, z + depth + d / 160)))..castsShadows = false);
  }

  /// Which screen shows: upright, or on its side.
  set wide(bool v) {
    _portrait.visible = !v;
    _landscape.visible = v;
  }

  set screen(Texture2D t) => screenMat
    ..baseColorTexture = t
    ..emissiveTexture = t;

  set wideScreen(Texture2D t) => wideMat
    ..baseColorTexture = t
    ..emissiveTexture = t;

  /// Shown, its middle placed by [m].
  void place(vm.Matrix4 m) => root
    ..visible = true
    ..localTransform = m;

  void hide() => root.visible = false;

  static final _titanium = pbr(lin3v(0x9A968F), metallic: 0.92, roughness: 0.3);
  static final _aluminium = pbr(lin3v(0x2B2E33), metallic: 0.8, roughness: 0.34);
  static final _blackGlass = glossy(vm.Vector4(0.006, 0.006, 0.008, 1));
  static final _frostedBack = pbr(lin3v(0xC9C4BB), roughness: 0.52);
  static final _obsidianBack = pbr(lin3v(0x1A1C20), roughness: 0.42);
  static final _bump = pbr(lin3v(0xBDB8AE), roughness: 0.32);
  static final _visor = glossy(vm.Vector4(0.012, 0.013, 0.016, 1));
  static final _lensGlass = glossy(vm.Vector4(0.01, 0.012, 0.03, 1));
  static final _flash = pbr(lin3v(0xF2E6C8), roughness: 0.35, emissive: lin3v(0xF2E6C8), emissiveStrength: 0.15);
}

/// A window floating in the air, as on a headset: the page on a pane of
/// frosted glass with its edges rounded off, and under it the bar you'd
/// take it by, a close button beside.
class Window3D {
  Window3D(Node parent, {required this.w, required this.h, required Texture2D page, String name = 'window'}) : root = Node(name: name) {
    pageMat = deviceScreen(page);
    const m = 0.09, depth = 0.05;
    void add(MeshData data, Material mat, double x, double y, double z) => root.add(
      Node(name: '$name part', mesh: Mesh(geometryOf(data), mat), localTransform: trs(vm.Vector3(x, y, z)))..castsShadows = false,
    );
    add(roundedSlab(w + 2 * m, h + 2 * m, depth, corner: 0.16, edge: 0.022, cornerSteps: 10), _pane, 0, 0, 0);
    root.add(Node(name: '$name page', mesh: Mesh(geometryOf(roundedPlate(w, h, 0.1)), pageMat), localTransform: trs(vm.Vector3(0, 0, -depth / 2 - 0.003)))..castsShadows = false);
    final by = -(h / 2 + m + 0.16);
    add(roundedSlab(0.62, 0.075, 0.035, corner: 0.0375, edge: 0.014), _bar, 0, by, 0);
    add(roundedSlab(0.1, 0.1, 0.035, corner: 0.05, edge: 0.014), _bar, -0.46, by, 0);
    parent.add(root..visible = false);
    deviceRoots.add(root);
  }

  final double w, h;
  final Node root;
  late final PhysicallyBasedMaterial pageMat;

  set page(Texture2D t) => pageMat
    ..baseColorTexture = t
    ..emissiveTexture = t;

  void place(vm.Matrix4 m) => root
    ..visible = true
    ..localTransform = m;

  void hide() => root.visible = false;

  static final _pane = PhysicallyBasedMaterial()
    ..baseColorFactor = lin3v(0xD5DBE3)
    ..metallicFactor = 0
    ..roughnessFactor = 0.36
    ..clearcoat = 0.7
    ..clearcoatRoughness = 0.12;
  static final _bar = pbr(lin3v(0xEEF1F5), roughness: 0.3, emissive: lin3v(0xEEF1F5), emissiveStrength: 0.25);
}

/// A laptop, open on a table: its base (the keyboard's well, the trackpad)
/// on the table, the lid [tilt] back from upright, the page on its screen
/// ([w]×[h], facing −z, as the lid's), all in proportion to the screen.
/// Its middle front edge at its origin, on the table.
class Laptop3D {
  Laptop3D(Node parent, {required this.w, required this.h, required Texture2D page, double tilt = 0.26, String name = 'laptop'}) : root = Node(name: name) {
    pageMat = deviceScreen(page);
    final bezel = 0.03 * w, lw = w + 2 * bezel, lh = h + 2 * bezel + 0.05 * w, ld = 0.017 * w;
    final bd = 0.7 * lw, bt = 0.034 * w, e = ld / 6;
    void add(Node to, MeshData data, Material mat, vm.Matrix4 at, {bool shadow = false}) =>
        to.add(Node(name: '$name part', mesh: Mesh(geometryOf(data), mat), localTransform: at)..castsShadows = shadow);
    // (A quarter turn about x lays a slab or a plate flat, its face up.)
    const flat = math.pi / 2;
    // The base; the keyboard's well and the trackpad set in its top.
    add(root, roundedSlab(lw, bd, bt, corner: 0.03 * w, edge: 0.4 * bt), _shell, trs(vm.Vector3(0, bt / 2, bd / 2), rotX: flat), shadow: true);
    add(root, roundedPlate(0.86 * lw, 0.42 * bd, 0.01 * w), _keys, trs(vm.Vector3(0, bt + e, 0.62 * bd), rotX: flat));
    add(root, roundedPlate(0.36 * lw, 0.28 * bd, 0.012 * w), _pad, trs(vm.Vector3(0, bt + e, 0.2 * bd), rotX: flat));
    // The lid, from the hinge at the base's back edge: its shell, the black
    // glass round the screen, the page.
    final lid = Node(name: '$name lid', localTransform: trs(vm.Vector3(0, bt, bd), rotX: tilt));
    add(lid, roundedSlab(lw, lh, ld, corner: 0.03 * w, edge: 0.4 * ld), _shell, trs(vm.Vector3(0, lh / 2, 0)), shadow: true);
    add(lid, roundedPlate(lw - 0.004 * w, lh - 0.004 * w, 0.028 * w), Phone3D._blackGlass, trs(vm.Vector3(0, lh / 2, -ld / 2 - e)));
    lid.add(Node(name: '$name page', mesh: Mesh(geometryOf(roundedPlate(w, h, 0.006 * w)), pageMat), localTransform: trs(vm.Vector3(0, bezel + 0.05 * w + h / 2, -ld / 2 - 2 * e)))..castsShadows = false);
    root.add(lid);
    parent.add(root..visible = false);
    deviceRoots.add(root);
  }

  final double w, h;
  final Node root;
  late final PhysicallyBasedMaterial pageMat;

  set page(Texture2D t) => pageMat
    ..baseColorTexture = t
    ..emissiveTexture = t;

  /// Shown, its origin placed by [m].
  void place(vm.Matrix4 m) => root
    ..visible = true
    ..localTransform = m;

  void hide() => root.visible = false;

  static final _shell = pbr(lin3v(0xC8CBD0), metallic: 0.9, roughness: 0.32);
  static final _keys = pbr(lin3v(0x1E2024), roughness: 0.6);
  static final _pad = pbr(lin3v(0xB9BCC2), metallic: 0.6, roughness: 0.28);
}

/// A sign's frame: a slim aluminium edge round a board [w]×[h] (its face
/// at z = 0, the frame just behind it), its edges rounded off.
Node signFrame(double w, double h, {double rim = 0.035, double depth = 0.06, double corner = 0}) => Node(
  name: 'sign frame',
  mesh: Mesh(geometryOf(roundedSlab(w + 2 * rim, h + 2 * rim, depth, corner: corner + rim, edge: math.min(0.4 * rim, 0.03))), _brushed),
  localTransform: trs(vm.Vector3(0, 0, depth / 2 - 0.01)),
)..castsShadows = false;

final _brushed = pbr(lin3v(0xB8BEC6), metallic: 0.85, roughness: 0.35);

/// A device's screen: it lights itself (barely lit by the sun: its colour
/// is its own glow, the same whichever way it faces), under glass.
PhysicallyBasedMaterial deviceScreen(Texture2D t) => PhysicallyBasedMaterial()
  ..baseColorTexture = t
  ..baseColorFactor = vm.Vector4(0.1, 0.1, 0.1, 1)
  ..metallicFactor = 0
  ..roughnessFactor = 0.6
  ..clearcoat = 1
  ..clearcoatRoughness = 0.04
  ..emissiveTexture = t
  ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
  ..emissiveStrength = 0.82;

/// Black glass, or anything glossy: a sharp clear coat over it.
PhysicallyBasedMaterial glossy(vm.Vector4 color) => PhysicallyBasedMaterial()
  ..baseColorFactor = color
  ..metallicFactor = 0
  ..roughnessFactor = 0.08
  ..clearcoat = 1
  ..clearcoatRoughness = 0.02;

/// A plain sRGB colour as a linear one (for a material's factor).
vm.Vector4 lin3v(int rgb) => v4(hex3(rgb));
