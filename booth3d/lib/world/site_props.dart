import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, FontWeight, FontVariation, Locale, Paint, PaintingStyle, RRect, Radius, Rect, StrokeCap;

import 'package:flutter/painting.dart' show Canvas, Offset, TextAlign, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/web_fonts.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';

/// Where the crew goes on a break (world units; see [SiteProps]).
abstract final class BreakSpots {
  /// The vending machines stand against the plaza's right edge, facing into
  /// it (−x), south of the brick yard and right of the delivery gate.
  static const vendX = 16.45;
  static const vendZ = [-7.1, -6.05];

  /// Where a customer stands to buy from machine `m` (facing it, +x).
  static vm.Vector3 buyAt(int m) => vm.Vector3(vendX - 0.92, 0, vendZ[m]);

  /// The can bin beside the machines.
  static final bin = vm.Vector3(vendX + 0.02, 0, -5.12);

  /// Standing about by the machines with a can: a loose ring (facing its
  /// middle), clear of a parked delivery truck.
  static final vendRing = [vm.Vector3(15.25, 0, -4.5), vm.Vector3(15.95, 0, -3.85), vm.Vector3(16.25, 0, -4.75)];

  /// The smoking corner (喫煙所), off to the left behind the wall, by the
  /// plaza's edge (out of the camera's way into the Glyph Works): the
  /// standing ashtray, and four places round it.
  static final ashtray = vm.Vector3(-16.1, 0, 2.6);
  static final smokeRing = [
    for (final a in const [-2.2, -0.95, 2.15, 0.75]) vm.Vector3(ashtray.x + 0.66 * math.cos(a), 0, ashtray.z + 0.66 * math.sin(a)),
  ];

  /// The bench on the plaza's left edge (the city's, facing the build):
  /// two seats, and a place to stand chatting with whoever sits there.
  static final seats = [vm.Vector3(-18.66, 0, -0.42), vm.Vector3(-18.66, 0, 0.42)];
  static final benchSide = vm.Vector3(-17.45, 0, 0.05);
}

/// Props for the crew's breaks: two vending machines (自動販売機) with a can
/// bin, and the smoking corner (喫煙所) — a standing ashtray, its sign and
/// an upturned beer crate to sit on. Everything is one merged mesh with
/// vertex colours and one texture atlas (the machines' lit fronts and the
/// signs), so the lot is a single draw; the fronts glow after dark. No
/// lights.
class SiteProps {
  SiteProps(this.scene);

  final Scene scene;
  PhysicallyBasedMaterial? _mat;

  static const _atlas = 512;

  // Atlas regions (px): the two machine fronts, the 喫煙所 sign, the bin's
  // label, and a white patch that untextured parts sample.
  static const _front0 = Rect.fromLTWH(8, 8, 200, 256), _front1 = Rect.fromLTWH(216, 8, 200, 256);
  static const _sign = Rect.fromLTWH(8, 280, 256, 120), _label = Rect.fromLTWH(280, 280, 128, 64);
  static const _white = Rect.fromLTWH(464, 464, 48, 48);

  void init() => _build();

  Future<void> _build() async {
    await awaitFallbackFonts(
      '喫煙所 あきかん',
      style: const TextStyle(fontFamily: BP.display, fontSize: 40, locale: Locale('ja')),
    );
    final base = await paintedTexture(_atlas, _atlas, (c, s) => _paint(c, glow: false));
    final glow = await paintedTexture(_atlas, _atlas, (c, s) => _paint(c, glow: true));
    final mat = PhysicallyBasedMaterial()
      ..baseColorTexture = base
      ..emissiveTexture = glow
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.6
      ..metallicFactor = 0.05
      ..roughnessFactor = 0.5;
    _mat = mat;
    scene.add(Node(name: 'break props', mesh: Mesh(merged(_parts()), mat)));
  }

  /// The machines' fronts glow, brighter after dark.
  void update(double night) => _mat?.emissiveStrength = 0.55 + 2.2 * smooth(0.1, 0.5, night);

  // ── Geometry ──────────────────────────────────────────────────────────────

  static final _whiteUv = vm.Vector2((_white.left + _white.width / 2) / _atlas, (_white.top + _white.height / 2) / _atlas);

  /// A coloured box (sampling the atlas' white patch).
  MeshData _box(vm.Matrix4 at, double w, double h, double d, int rgb) => _solid(CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData(), at, rgb);

  MeshData _cyl(vm.Matrix4 at, double r, double h, int rgb, {double? top, int segments = 14}) =>
      _solid(CylinderGeometry(bottomRadius: r, topRadius: top ?? r, height: h, radialSegments: segments).extractMeshData(), at, rgb);

  MeshData _solid(MeshData d, vm.Matrix4 at, int rgb) {
    final uv = Float32List(d.vertexCount * 2);
    for (var i = 0; i < d.vertexCount; i++) {
      uv
        ..[i * 2] = _whiteUv.x
        ..[i * 2 + 1] = _whiteUv.y;
    }
    return painted(d, v4(hex3(rgb)), uvs: uv).transformed(at);
  }

  /// A thin board whose front (local −z) shows [region] of the atlas; its
  /// edges and back are [edge].
  MeshData _board(vm.Matrix4 at, double w, double h, Rect region, {int edge = 0xF4F1EA, double thick = 0.02}) {
    final d = CuboidGeometry(vm.Vector3(w, h, thick)).extractMeshData();
    final uv = Float32List(d.vertexCount * 2), n = d.normals!, p = d.positions;
    for (var i = 0; i < d.vertexCount; i++) {
      if (n[i * 3 + 2] < -0.5) {
        uv[i * 2] = (region.left + (p[i * 3] / w + 0.5) * region.width) / _atlas;
        uv[i * 2 + 1] = (region.top + (0.5 - p[i * 3 + 1] / h) * region.height) / _atlas;
      } else {
        uv[i * 2] = _whiteUv.x;
        uv[i * 2 + 1] = _whiteUv.y;
      }
    }
    final front = vm.Vector4(1, 1, 1, 1), side = v4(hex3(edge));
    final colors = Float32List(d.vertexCount * 4);
    for (var i = 0; i < d.vertexCount; i++) {
      final c = n[i * 3 + 2] < -0.5 ? front : side;
      colors
        ..[i * 4] = c.x
        ..[i * 4 + 1] = c.y
        ..[i * 4 + 2] = c.z
        ..[i * 4 + 3] = 1;
    }
    return MeshData(positions: p, vertexCount: d.vertexCount, normals: n, texCoords: uv, colors: colors, indices: d.indices).transformed(at);
  }

  static vm.Matrix4 _at(double x, double y, double z, [double yaw = 0]) => trs(vm.Vector3(x, y, z), rotY: yaw);

  List<MeshData> _parts() {
    final parts = <MeshData>[];
    // Vending machines, facing −x (local −z turned to −x: yaw π/2).
    const face = math.pi / 2;
    const bodies = [0x1E2C52, 0xD83A4A];
    for (var m = 0; m < 2; m++) {
      final root = _at(BreakSpots.vendX, 0.02, BreakSpots.vendZ[m], face);
      vm.Matrix4 local(double x, double y, double z) => root * vm.Matrix4.translation(vm.Vector3(x, y, z));
      parts
        ..add(_box(local(0, 0.925, 0), 1.0, 1.85, 0.75, bodies[m]))
        ..add(_box(local(0, 1.9, -0.04), 1.04, 0.1, 0.8, 0x2A3344)) // a cap
        ..add(_board(local(0, 1.22, -0.385), 0.82, 1.05, m == 0 ? _front0 : _front1, edge: 0x2A3344))
        ..add(_box(local(0, 0.3, -0.39), 0.62, 0.22, 0.06, 0x0E131C)) // the can tray
        ..add(_box(local(0, 0.43, -0.4), 0.66, 0.035, 0.05, 0xB9C3D0))
        ..add(_box(local(0.3, 0.62, -0.39), 0.12, 0.2, 0.04, 0x2A3344)); // coins
    }
    // The can bin: white with a blue lid and a round mouth, its label.
    final bin = _at(BreakSpots.bin.x, 0.02, BreakSpots.bin.z, face);
    vm.Matrix4 inBin(double x, double y, double z, {double pitch = 0}) => bin * trs(vm.Vector3(x, y, z), rotX: pitch);
    parts
      ..add(_box(inBin(0, 0.42, 0), 0.5, 0.84, 0.44, 0xEEF3F7))
      ..add(_box(inBin(0, 0.86, 0), 0.54, 0.06, 0.48, 0x2E6DA8))
      ..add(_cyl(inBin(0, 0.7, -0.222, pitch: math.pi / 2), 0.075, 0.02, 0x111827))
      ..add(_board(inBin(0, 0.42, -0.225), 0.36, 0.18, _label, edge: 0xEEF3F7));

    // The smoking corner: a red standing ashtray, its sign on a post, a
    // beer crate.
    final a = BreakSpots.ashtray;
    parts
      ..add(_cyl(_at(a.x, 0.02, a.z), 0.2, 0.04, 0x1B2233, segments: 16))
      ..add(_cyl(_at(a.x, 0.22, a.z), 0.035, 0.36, 0x3A4558, segments: 8))
      ..add(_cyl(_at(a.x, 0.66, a.z), 0.17, 0.52, 0xD8343F, segments: 18))
      ..add(_cyl(_at(a.x, 0.93, a.z), 0.18, 0.03, 0xC9CED6, segments: 18))
      ..add(_cyl(_at(a.x, 0.95, a.z), 0.06, 0.02, 0x14181F, segments: 10));
    const signYaw = -0.5;
    final sign = _at(a.x - 0.95, 0, a.z + 0.75, signYaw);
    parts
      ..add(_box(sign * vm.Matrix4.translation(vm.Vector3(0, 0.95, 0.03)), 0.06, 1.9, 0.06, 0x3A4558))
      ..add(_board(sign * vm.Matrix4.translation(vm.Vector3(0, 1.62, -0.01)), 0.8, 0.375, _sign, edge: 0x1B2233, thick: 0.03))
      ..add(_box(sign * vm.Matrix4.translation(vm.Vector3(0, 0.02, 0.03)), 0.34, 0.04, 0.34, 0x1B2233));
    final crate = _at(a.x + 0.95, 0, a.z + 0.55, 0.4);
    parts
      ..add(_box(crate * vm.Matrix4.translation(vm.Vector3(0, 0.17, 0)), 0.46, 0.32, 0.34, 0xF2B233))
      ..add(_box(crate * vm.Matrix4.translation(vm.Vector3(0, 0.335, 0)), 0.4, 0.012, 0.28, 0x6B4B12));
    return parts;
  }

  // ── The atlas ─────────────────────────────────────────────────────────────

  void _paint(Canvas c, {required bool glow}) {
    c.drawRect(const Rect.fromLTWH(0, 0, _atlas + 0.0, _atlas + 0.0), Paint()..color = const Color(0xFF000000));
    // Untextured parts sample this (white for colour, black for glow).
    c.drawRect(_white, Paint()..color = glow ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    _front(c, _front0, coffee: true, glow: glow);
    _front(c, _front1, coffee: false, glow: glow);
    _signBoard(c, glow: glow);
    _binLabel(c, glow: glow);
  }

  /// A machine's lit window: three shelves of drinks with their price
  /// buttons (red: hot, blue: cold), coin slot and change cup below.
  void _front(Canvas c, Rect r, {required bool coffee, required bool glow}) {
    final k = glow ? 1.0 : 0.85;
    Color dim(Color col) => Color.from(alpha: 1, red: col.r * k, green: col.g * k, blue: col.b * k);
    c.drawRect(r, Paint()..color = dim(const Color(0xFFEAF4FF)));
    const cans = [
      [0xFF5B3A29, 0xFF1C2433, 0xFFC9A227, 0xFF7A4A2B, 0xFF2B3A55, 0xFFB5651D],
      [0xFF2E8B57, 0xFF9ACD32, 0xFFF4F1EA, 0xFF3A7BD5, 0xFFE8505F, 0xFFFFB347],
      [0xFFE8505F, 0xFF5FB8FF, 0xFF6CE5B1, 0xFFFFD43B, 0xFFF4F1EA, 0xFFC39BFF],
    ];
    for (var row = 0; row < 3; row++) {
      final y = r.top + 14 + row * 66.0;
      // The shelf behind, softly lit.
      c.drawRect(Rect.fromLTWH(r.left + 4, y - 4, r.width - 8, 52), Paint()..color = dim(const Color(0xFFFFFFFF)));
      final hot = coffee ? row < 2 : row == 0;
      for (var i = 0; i < 6; i++) {
        final x = r.left + 9 + i * 31.0;
        final colors = cans[(row + (coffee ? 0 : 1)) % 3];
        final col = Color(colors[(i + (coffee ? 0 : 3)) % 6]);
        final bottle = !coffee && (i + row).isOdd;
        final can = bottle ? Rect.fromLTWH(x + 4, y + 2, 16, 38) : Rect.fromLTWH(x + 2, y + 10, 20, 30);
        c.drawRRect(RRect.fromRectAndRadius(can, Radius.circular(bottle ? 6 : 3)), Paint()..color = dim(col));
        if (bottle) c.drawRect(Rect.fromLTWH(x + 8, y - 2, 8, 6), Paint()..color = dim(const Color(0xFFF4F1EA)));
        c.drawRect(Rect.fromLTWH(can.left + 3, can.top + 3, 3, can.height - 6), Paint()..color = const Color(0x66FFFFFF));
        // Price button.
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y + 44, 22, 8), const Radius.circular(2)),
          Paint()..color = dim(hot ? const Color(0xFFE8414F) : const Color(0xFF2E7BE6)),
        );
      }
    }
    // Below the window: a dark band with the coin slot and the money display.
    c.drawRect(Rect.fromLTWH(r.left, r.bottom - 50, r.width, 50), Paint()..color = const Color(0xFF1B2233));
    c.drawRect(Rect.fromLTWH(r.left + 130, r.bottom - 40, 40, 14), Paint()..color = glow ? const Color(0xFFFF6A3D) : const Color(0xFFB04020));
    c.drawRect(Rect.fromLTWH(r.left + 20, r.bottom - 38, 60, 10), Paint()..color = const Color(0xFF8DA3BC));
  }

  void _signBoard(Canvas c, {required bool glow}) {
    final r = _sign;
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), Paint()..color = glow ? const Color(0xFF2A3A2E) : const Color(0xFFF7F4EC));
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(6), const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF21A86B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    // A cigarette with its smoke.
    final cx = r.left + 46, cy = r.top + 66;
    c.drawRect(Rect.fromLTWH(cx - 30, cy, 46, 10), Paint()..color = glow ? const Color(0xFF555555) : const Color(0xFFFFFFFF));
    c.drawRect(
      Rect.fromLTWH(cx - 30, cy, 46, 10),
      Paint()
        ..color = const Color(0xFF1B2233)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    c.drawRect(Rect.fromLTWH(cx + 16, cy, 10, 10), Paint()..color = const Color(0xFFFF6A3D));
    final smoke = Paint()
      ..color = const Color(0xFF8DA3BC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 2; k++) {
      final x = cx + 18 + k * 9.0;
      c.drawLine(Offset(x, cy - 6), Offset(x - 5, cy - 18), smoke);
      c.drawLine(Offset(x - 5, cy - 18), Offset(x + 2, cy - 32), smoke);
    }
    _text(c, '喫煙所', Rect.fromLTWH(r.left + 88, r.top + 14, r.width - 100, 68), 56, glow ? const Color(0xFF6CE5B1) : const Color(0xFF14203A));
    _text(c, 'SMOKING AREA', Rect.fromLTWH(r.left + 88, r.top + 80, r.width - 100, 26), 18, glow ? const Color(0xFF6CE5B1) : const Color(0xFF167A4C));
  }

  void _binLabel(Canvas c, {required bool glow}) {
    final r = _label;
    c.drawRect(r, Paint()..color = glow ? const Color(0xFF000000) : const Color(0xFFF7F4EC));
    _text(c, 'あきかん', r.deflate(6), 34, glow ? const Color(0xFF000000) : const Color(0xFF2E6DA8));
  }

  void _text(Canvas c, String s, Rect box, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: BP.display,
          fontSize: size,
          color: color,
          locale: const Locale('ja'),
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 760)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: box.width * 2);
    final scale = math.min(1.0, box.width * 0.96 / tp.width);
    c.save();
    c.translate(box.center.dx, box.center.dy);
    c.scale(scale);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }
}
