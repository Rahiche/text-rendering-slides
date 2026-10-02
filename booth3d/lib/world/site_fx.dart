import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/geometry.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'site_geo.dart';

/// The palette the celebrations use (linear, for emissive/HDR colours).
final fxPalette = [for (final c in const [BP.amber, BP.coral, BP.green, BP.violet, BP.pink, BP.line, Color(0xFFFFFFFF)]) lin(c)];

/// Particle pools for the site, drawn instanced and rebuilt from scene time
/// every frame (so they're deterministic and bounded): dust and smoke (soft
/// billboards: a flipbook of billowy puffs, lit from above, dissolving where
/// they meet the ground), glowing sparks (fireworks, pops), glowing pixels,
/// and confetti (and paint drips). Call [begin], emit, then [end] once per
/// frame.
class Fx3D {
  Fx3D(this.scene);

  final Scene scene;

  static const _maxDust = 280, _maxSparks = 2600, _maxPixels = 700, _maxConfetti = 440;

  late final InstancedMesh _sparks, _pixels, _confetti;
  late final BillboardGeometry _dust;
  late final SpriteMaterial _dustMat;

  /// 0 by day … 1 at night: the dust takes the light it's in.
  double night = 0;
  final _nodes = <Node>[];
  int _nDust = 0, _nSparks = 0, _nPixels = 0, _nConfetti = 0;
  int _hiSparks = 0, _hiPixels = 0, _hiConfetti = 0;

  void init() {
    InstancedMesh pool(Geometry g, Material m, int n, String name) {
      final im = InstancedMesh(geometry: g, material: m, sortTransparentInstances: !m.isOpaque());
      for (var i = 0; i < n; i++) {
        im.addInstance(hidden);
      }
      final node = Node(name: name)..addComponent(InstancedMeshComponent(im))..castsShadows = false;
      _nodes.add(node);
      scene.add(node);
      return im;
    }

    _dustMat = SpriteMaterial(colorTexture: _smokeAtlas())
      ..blendMode = SpriteBlendMode.alpha
      ..softDepthFade = 0.35
      ..cameraNearFade = 1.2;
    _dust = BillboardGeometry(capacity: _maxDust)
      ..flipbookColumns = 4
      ..flipbookRows = 4;
    final dustNode = Node(name: 'dust', mesh: Mesh(_dust, _dustMat))..castsShadows = false;
    _nodes.add(dustNode);
    scene.add(dustNode);
    _sparks = pool(SphereGeometry(radius: 0.5, segments: 6, rings: 4), UnlitMaterial(), _maxSparks, 'sparks');
    _pixels = pool(CuboidGeometry(vm.Vector3.all(1)), UnlitMaterial(), _maxPixels, 'pixels');
    final confettiMat = pbr(rgb(1, 1, 1), roughness: 0.45, metallic: 0.2);
    _confetti = InstancedMesh(geometry: CuboidGeometry(vm.Vector3(1, 0.62, 0.05)), material: confettiMat);
    for (var i = 0; i < _maxConfetti; i++) {
      _confetti.addInstance(hidden);
    }
    final confettiNode = Node(name: 'confetti')..addComponent(InstancedMeshComponent(_confetti));
    _nodes.add(confettiNode);
    scene.add(confettiNode);
  }

  /// The fireworks' bursts this frame, brightest first: where, what colour,
  /// how strong (for lights).
  final flashes = <(vm.Vector3, vm.Vector4, double)>[];

  void begin() {
    _nDust = _nSparks = _nPixels = _nConfetti = 0;
    flashes.clear();
  }

  void end() {
    _dust.commit(_nDust);
    // Dust is lit by the sky: warm by day, a dim blue at night.
    final k = smooth(0.1, 0.8, night);
    _dustMat.tint = vm.Vector4(lerp(0.95, 0.2, k), lerp(0.9, 0.23, k), lerp(0.84, 0.32, k), 1);
    for (var i = _nSparks; i < _hiSparks; i++) {
      _sparks.setInstanceTransform(i, hidden);
    }
    for (var i = _nPixels; i < _hiPixels; i++) {
      _pixels.setInstanceTransform(i, hidden);
    }
    for (var i = _nConfetti; i < _hiConfetti; i++) {
      _confetti.setInstanceTransform(i, hidden);
    }
    _hiSparks = _nSparks;
    _hiPixels = _nPixels;
    _hiConfetti = _nConfetti;
    // Empty pools skip the renderer's per-frame work entirely.
    _nodes[0].visible = _nDust > 0;
    _nodes[1].visible = _nSparks > 0;
    _nodes[2].visible = _nPixels > 0;
    _nodes[3].visible = _nConfetti > 0;
  }

  final _m = vm.Matrix4.identity();
  final _c = vm.Vector4.zero();

  /// A puff of dust [age] (0..1 through its life) of size [r], tinted by
  /// [tint] (rgb, and alpha for its opacity): a few soft billows that swell,
  /// rise, drift with the air, turn slowly and thin out.
  void puff(double x, double y, double z, double age, double r, {int seed = 0, int n = 3, vm.Vector4? tint}) {
    if (age < 0 || age >= 1) return;
    final e = eo(age);
    for (var k = 0; k < n; k++) {
      if (_nDust >= _maxDust) return;
      final a = seed * 7 + k * 2.39996;
      final spread = r * (0.3 + 0.85 * e);
      final px = x + math.cos(a) * spread * 0.7 + 0.25 * r * age, pz = z + math.sin(a) * spread * 0.7;
      final py = y + r * 0.3 + r * 0.65 * e + 0.05 * k;
      final s = 1.7 * r * (0.6 + 1.0 * e) * (0.8 + 0.3 * rnd(seed, k));
      // In fast, out slowly.
      final alpha = (tint?.w ?? 0.6) * seg(age, 0, 0.1) * math.pow(1 - age, 1.4).toDouble();
      _p.setValues(px, py, pz);
      _c.setValues(tint?.x ?? 1, tint?.y ?? 1, tint?.z ?? 1, alpha);
      _dust.setInstance(_nDust, center: _p, width: s, height: s, rotation: rnd(seed, k, 3) * 6.283 + (rnd(seed, k, 4) - 0.5) * 1.4 * age, color: _c, frame: (rnd(seed, k, 5) * 16).floorToDouble());
      _nDust++;
    }
  }

  final _p = vm.Vector3.zero();

  /// The dust's flipbook: 4 × 4 billows, each a lumpy disc of fractal noise,
  /// lighter on top (lit from above), soft at the edge.
  static Texture2D _smokeAtlas() {
    const cells = 4, cell = 64, n = cells * cell;
    final px = Uint8List(n * n * 4);
    for (var c = 0; c < cells * cells; c++) {
      final ox = (c % cells) * cell, oy = (c ~/ cells) * cell;
      for (var y = 0; y < cell; y++) {
        for (var x = 0; x < cell; x++) {
          final u = (x + 0.5) / cell * 2 - 1, v = (y + 0.5) / cell * 2 - 1;
          final rr = math.sqrt(u * u + v * v), ang = math.atan2(v, u);
          final edge = 0.58 + 0.3 * _fbm(math.cos(ang) * 1.4 + c * 3.1, math.sin(ang) * 1.4 + c * 1.7, 2);
          var d = 1 - smooth(edge * 0.3, edge, rr);
          d *= 0.5 + 0.5 * _fbm(u * 2.4 + c * 5.3, v * 2.4 - c * 2.9, 4);
          final shade = 0.72 + 0.28 * (0.5 - 0.5 * v) + 0.1 * (_fbm(u * 3 + c, v * 3 - c, 2) - 0.5);
          final i = ((oy + y) * n + ox + x) * 4;
          final g = (255 * shade.clamp(0.0, 1.0)).round();
          px[i] = g;
          px[i + 1] = g;
          px[i + 2] = g;
          px[i + 3] = (255 * d.clamp(0.0, 1.0)).round();
        }
      }
    }
    return Texture2D.fromPixels(px, n, n);
  }

  static double _hash(int x, int y) {
    var h = (x * 374761393 + y * 668265263) & 0x7fffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return ((h ^ (h >> 16)) & 0xffff) / 65535.0;
  }

  static double _noise(double x, double y) {
    final xi = x.floor(), yi = y.floor();
    final fx = x - xi, fy = y - yi;
    final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    final a = _hash(xi, yi), b = _hash(xi + 1, yi), c = _hash(xi, yi + 1), d = _hash(xi + 1, yi + 1);
    return lerp(lerp(a, b, sx), lerp(c, d, sx), sy);
  }

  static double _fbm(double x, double y, int octaves) {
    var sum = 0.0, amp = 0.5, f = 1.0, norm = 0.0;
    for (var o = 0; o < octaves; o++) {
      sum += amp * _noise(x * f, y * f);
      norm += amp;
      amp *= 0.5;
      f *= 2.03;
    }
    return sum / norm;
  }

  /// A glowing spark of [size] in linear HDR [color] times [glow].
  void spark(double x, double y, double z, double size, vm.Vector4 color, [double glow = 6]) {
    if (_nSparks >= _maxSparks || size <= 0.001) return;
    _sparks.setInstanceTransform(_nSparks, setTrs(_m, x, y, z, s: size));
    _c.setValues(color.x * glow, color.y * glow, color.z * glow, 1);
    _sparks.setInstanceColor(_nSparks, _c);
    _nSparks++;
  }

  /// A glowing pixel (a little cube), [size] across, spun by [spin].
  void pixel(double x, double y, double z, double size, vm.Vector4 color, {double glow = 5, double spin = 0}) {
    if (_nPixels >= _maxPixels || size <= 0.001) return;
    _pixels.setInstanceTransform(_nPixels, setTrs(_m, x, y, z, yaw: spin, pitch: spin * 0.7, s: size));
    _c.setValues(color.x * glow, color.y * glow, color.z * glow, 1);
    _pixels.setInstanceColor(_nPixels, _c);
    _nPixels++;
  }

  void confetti(double x, double y, double z, double yaw, double pitch, double roll, double size, vm.Vector4 color) {
    if (_nConfetti >= _maxConfetti) return;
    _confetti.setInstanceTransform(_nConfetti, setTrs(_m, x, y, z, yaw: yaw, pitch: pitch, roll: roll, s: size));
    _confetti.setInstanceColor(_nConfetti, color);
    _nConfetti++;
  }

  // ── Fireworks ─────────────────────────────────────────────────────────────

  /// Shapes for glyph bursts: points along a character's strokes,
  /// normalised to unit height around the origin (y up).
  static List<vm.Vector2> shapeOf(GlyphGeometry g, {int count = 110}) {
    final lines = <List<double>>[];
    if (g.strokes.isNotEmpty) {
      for (final s in g.strokes) {
        lines.add(s.pts);
      }
    } else {
      for (final c in g.contours) {
        lines.add([...c.pts, c.pts[0], c.pts[1]]);
      }
    }
    var total = 0.0;
    for (final l in lines) {
      for (var i = 2; i + 1 < l.length; i += 2) {
        total += math.sqrt(math.pow(l[i] - l[i - 2], 2) + math.pow(l[i + 1] - l[i - 1], 2));
      }
    }
    if (total <= 0) return const [];
    final step = total / count;
    final cx = (g.inkLeft + g.inkRight) / 2, cy = (g.inkTop + g.inkBottom) / 2, h = math.max(g.inkHeight, 1);
    final out = <vm.Vector2>[];
    var carry = 0.0;
    for (final l in lines) {
      for (var i = 2; i + 1 < l.length; i += 2) {
        final x0 = l[i - 2], y0 = l[i - 1], x1 = l[i], y1 = l[i + 1];
        final seg = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
        var d = carry;
        while (d < seg) {
          final f = d / seg;
          out.add(vm.Vector2((x0 + (x1 - x0) * f - cx) / h, -(y0 + (y1 - y0) * f - cy) / h));
          d += step;
        }
        carry = d - seg;
      }
    }
    return out;
  }

  /// A celebration's fireworks [u] seconds in, over a wall [w] wide and [h]
  /// tall: rockets, then bursts — spheres, rings, willows, crackles and
  /// glyphs (the name's own characters and other scripts).
  void fireworks(double u, double w, double h, int serial, List<List<vm.Vector2>> nameShapes, List<List<vm.Vector2>> scriptShapes) {
    const every = 0.82, first = 0.35, life = 2.7;
    final n = ((11.2 - first) / every).floor() + 1;
    for (var k = 0; k < n; k++) {
      final at = first + k * every;
      final tau = u - at;
      if (tau < -1.0 || tau > life) continue;
      final r1 = rnd(k, serial, 1), r2 = rnd(k, serial, 2), r3 = rnd(k, serial, 3);
      final side = k.isEven ? -1.0 : 1.0;
      final cx = side * (0.12 + 0.3 * r1) * w * 0.9 + (k % 3 == 0 ? -side * 0.3 * w : 0);
      final cy = h + 3.2 + 2.6 * r2, cz = 1.2 + 1.6 * r3;
      final c1 = fxPalette[(k * 3 + serial) % 6], c2 = fxPalette[(k * 3 + serial + 2) % 7];
      if (tau < 0) {
        // The rocket: rising from behind the wall, slowing near the top.
        final f = 1 + tau; // 0..1 over the last second
        final x0 = cx * 0.8, y0 = 0.6, z0 = cz + 0.6;
        for (var s = 0; s < 7; s++) {
          final g = c01(f - s * 0.035);
          final e = eo(g);
          final px = x0 + (cx - x0) * e + 0.05 * math.sin(g * 30);
          final py = y0 + (cy - y0) * e;
          final pz = z0 + (cz - z0) * e;
          spark(px, py, pz, (s == 0 ? 0.16 : 0.1 * (1 - s / 7)), s == 0 ? fxPalette[6] : fxPalette[0], s == 0 ? 9 : 4);
        }
        continue;
      }
      if (tau < 0.8) flashes.add((vm.Vector3(cx, cy, cz), c1, math.pow(1 - tau / 0.8, 2).toDouble()));
      // The flash at the burst, and coloured smoke that lingers (it's what
      // reads by day).
      if (tau < 0.14) spark(cx, cy, cz, 1.3 * (1 - tau / 0.14), fxPalette[6], 12);
      _smoke.setValues(c1.x * 1.4, c1.y * 1.4, c1.z * 1.4, 0.32);
      for (var p = 0; p < 7; p++) {
        final a = p * 0.9 + k, e = (1.2 + 2.6 * eo(tau / 1.8)) * (0.6 + 0.4 * rnd(p, k));
        puff(cx + math.cos(a) * e, cy + math.sin(a) * e * 0.8 - 0.35 * tau, cz + 0.3, c01(tau / (life + 0.6)), 1.1 + 0.25 * p % 3, seed: k * 7 + p, n: 1, tint: _smoke);
      }
      final kind = k % 6;
      if (kind == 1 && nameShapes.isNotEmpty) {
        _glyphBurst(tau, cx, cy, cz, nameShapes[(k ~/ 6) % nameShapes.length], c1, fxPalette[6], k, serial, 4.6);
      } else if (kind == 4 && scriptShapes.isNotEmpty) {
        _glyphBurst(tau, cx, cy, cz, scriptShapes[(k ~/ 6 + serial) % scriptShapes.length], c2, c1, k, serial, 4.2);
      } else if (kind == 2) {
        _ring(tau, cx, cy, cz, c1, c2, k);
      } else if (kind == 3) {
        _willow(tau, cx, cy, cz, k);
      } else if (kind == 5) {
        _crackle(tau, cx, cy, cz, k, serial);
      } else {
        _sphere(tau, cx, cy, cz, c1, c2, k);
      }
    }
    _sortFlashes();
  }

  final _smoke = vm.Vector4.zero();

  void _sortFlashes() => flashes.sort((a, b) => b.$3.compareTo(a.$3));

  void _sphere(double tau, double cx, double cy, double cz, vm.Vector4 c1, vm.Vector4 c2, int k) {
    const n = 96;
    for (var i = 0; i < n; i++) {
      final y = 1 - 2 * (i + 0.5) / n, rr = math.sqrt(1 - y * y), a = i * 2.39996 + k;
      final dx = math.cos(a) * rr, dz = math.sin(a) * rr;
      for (var s = 0; s < 3; s++) {
        final tt = tau - s * 0.045;
        if (tt < 0) break;
        final e = 7.0 * eo(tt / 1.15);
        final drop = 1.3 * tt * tt;
        final size = (0.23 - s * 0.06) * (1 - seg(tt, 1.2, 2.6));
        spark(cx + dx * e, cy + y * e - drop, cz + dz * e * 0.8, size, i.isEven ? c1 : c2, s == 0 ? 7 : 4);
      }
    }
  }

  void _ring(double tau, double cx, double cy, double cz, vm.Vector4 c1, vm.Vector4 c2, int k) {
    const n = 64;
    final tilt = 0.35 * math.sin(k * 1.7);
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2;
      for (var s = 0; s < 3; s++) {
        final tt = tau - s * 0.05;
        if (tt < 0) break;
        final e = 5.4 * eo(tt / 1.0);
        final dx = math.cos(a) * e, dy = math.sin(a) * e * math.cos(tilt), dz = math.sin(a) * e * math.sin(tilt);
        final size = (0.21 - s * 0.05) * (1 - seg(tt, 1.1, 2.4));
        spark(cx + dx, cy + dy - 1.1 * tt * tt, cz + dz, size, i % 4 < 2 ? c1 : c2, s == 0 ? 7 : 4);
      }
      // An inner ring of white.
      if (i.isEven) {
        final e = 2.6 * eo(tau / 1.0);
        spark(cx + math.cos(a) * e, cy + math.sin(a) * e - 1.1 * tau * tau, cz, 0.1 * (1 - seg(tau, 0.9, 2.0)), fxPalette[6], 6);
      }
    }
  }

  void _willow(double tau, double cx, double cy, double cz, int k) {
    const n = 70;
    final gold = vm.Vector4(1.0, 0.62, 0.22, 1);
    for (var i = 0; i < n; i++) {
      final y = 1 - 2 * (i + 0.5) / n, rr = math.sqrt(1 - y * y), a = i * 2.39996 + k;
      for (var s = 0; s < 6; s++) {
        final tt = tau - s * 0.07;
        if (tt < 0) break;
        final e = 5.0 * eo(tt / 0.9);
        final drop = 2.2 * tt * tt;
        final size = (0.17 - s * 0.022) * (1 - seg(tt, 1.6, 2.7));
        spark(cx + math.cos(a) * rr * e, cy + y * e * 0.8 - drop, cz + math.sin(a) * rr * e * 0.7, size, gold, s == 0 ? 6 : 3);
      }
    }
  }

  void _crackle(double tau, double cx, double cy, double cz, int k, int serial) {
    const n = 110;
    for (var i = 0; i < n; i++) {
      final y = 1 - 2 * (i + 0.5) / n, rr = math.sqrt(1 - y * y), a = i * 2.39996 + k * 0.7;
      final e = 4.8 * eo(tau / 1.0) * (0.6 + 0.4 * rnd(i, k));
      // Each spark blinks on its own clock once it's out.
      final on = tau < 0.5 || rnd(i, (tau * 14).floor(), serial) > 0.45;
      if (!on) continue;
      final size = 0.17 * (1 - seg(tau, 1.3, 2.6));
      spark(cx + math.cos(a) * rr * e, cy + y * e - 1.2 * tau * tau, cz + math.sin(a) * rr * e * 0.8, size, fxPalette[(i + k) % 7], 8);
    }
  }

  void _glyphBurst(double tau, double cx, double cy, double cz, List<vm.Vector2> shape, vm.Vector4 c, vm.Vector4 twinkle, int k, int serial, double scale) {
    for (var i = 0; i < shape.length; i++) {
      final p = shape[i];
      // Out from the centre to the character, hold and twinkle, then fall.
      final out = eo(c01(tau / 0.45));
      final fall = math.max(0.0, tau - 1.65);
      final x = cx + p.x * scale * out, y = cy + p.y * scale * out - 1.6 * fall * fall, z = cz + 0.4 * (1 - out);
      final tw = rnd(i, (tau * 10).floor(), k) > 0.82;
      final size = 0.2 * (1 - seg(tau, 1.8, 2.7)) * (tw ? 1.4 : 1);
      spark(x, y, z, size, tw ? twinkle : c, tw ? 10 : 7);
      if (tau < 0.5) spark(cx + p.x * scale * eo(c01((tau - 0.06) / 0.45)), cy + p.y * scale * eo(c01((tau - 0.06) / 0.45)), z, size * 0.6, c, 4);
    }
  }

  // ── Confetti ──────────────────────────────────────────────────────────────

  /// Confetti from two cannons beside the wall, [u] seconds after the
  /// celebration started; [fade] (0..1) shrinks what lies on the ground.
  void confettiShow(double u, double w, int serial, {double fade = 0}) {
    const perVolley = 105;
    for (var v = 0; v < 2; v++) {
      final at = v == 0 ? 0.25 : 5.4;
      final tau = u - at;
      if (tau < 0) continue;
      for (var side = 0; side < 2; side++) {
        final sx = side == 0 ? -1.0 : 1.0;
        final x0 = sx * (w / 2 + 0.9), y0 = 0.5, z0 = -0.9;
        for (var i = 0; i < perVolley; i++) {
          final r1 = rnd(i, v * 2 + side, serial), r2 = rnd(i, 11, v + side * 3), r3 = rnd(i, 23, serial + v);
          // Launch up and inwards, then air drag to a slow, swaying fall.
          final v0x = -sx * (1.5 + 4.0 * r1), v0y = 8.5 + 5.5 * r2, v0z = (r3 - 0.5) * 4.5;
          const k = 1.5, vt = -1.0;
          final e = (1 - math.exp(-k * tau)) / k;
          var x = x0 + v0x * e + 0.35 * math.sin(tau * 2.1 + i);
          var y = y0 + vt * tau + (v0y - vt) * e;
          final z = z0 + v0z * e + 0.3 * math.cos(tau * 1.7 + i);
          final spin = tau * (4 + 5 * r1);
          var pitch = spin, roll = spin * 0.7;
          final size = 0.15 + 0.05 * r2;
          if (y < 0.06) {
            y = 0.06;
            pitch = math.pi / 2;
            roll = 0;
            x += 0;
          }
          final s = size * (1 - fade);
          if (s <= 0.002) continue;
          confetti(x, y, z, r3 * 6, pitch, roll, s, fxPalette[(i + v + side) % 6]);
        }
      }
    }
  }
}
