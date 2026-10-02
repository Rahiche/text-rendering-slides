import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, FontWeight, FontVariation, Locale, Paint, PaintingStyle, RRect, Radius, Rect, StrokeCap;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextDirection, TextAlign, Offset, Canvas;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/web_fonts.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'kit.dart';

/// Signs: rooftop neon in many languages (solid letters made from the real
/// text outlines, glowing at night), vertical blade signs for the text
/// trades of the street (書店, 活字, 印刷…), and the site's own boards —
/// 工事中 and a 安全第一 banner.
class CitySigns {
  CitySigns(this.scene);

  final Scene scene;

  /// Everything static is merged: rooftop letters by their flicker habit,
  /// lightboxes, ink and steel; colours come from vertex colours and, for the
  /// glow, from a swatch texture.
  final _batch = Batch();
  static const _palette = [BP.amber, BP.pink, BP.green, BP.coral, BP.violet, BP.line, BP.red];
  late final Texture2D _swatches;
  final _habits = <PhysicallyBasedMaterial>[];
  late final PhysicallyBasedMaterial _lightbox, _ink;
  final _boardMats = <PhysicallyBasedMaterial>[];

  /// Rooftop words and their colours.
  static const _words = <(String, Color, String?)>[
    ('テキスト', BP.amber, 'ja'),
    ('Hello', BP.pink, null),
    ('مرحبا', BP.green, null),
    ('文字', BP.coral, 'ja'),
    ('नमस्ते', BP.violet, null),
    ('Flutter', BP.line, null),
    ('你好', BP.red, 'zh'),
    ('ようこそ', BP.pink, 'ja'),
    ('안녕', BP.line, 'ko'),
    ('Привет', BP.amber, null),
    ('שלום', BP.violet, null),
    ('Γεια σου', BP.green, null),
    ('こんにちは', BP.coral, 'ja'),
    ('Unicode', BP.amber, null),
  ];

  /// Blade signs: the street's text trades.
  static const _blades = <(String, Color)>[
    ('書店', BP.amber),
    ('活字', BP.green),
    ('印刷', BP.pink),
    ('喫茶', BP.coral),
    ('文具', BP.line),
    ('フォント', BP.violet),
  ];

  late final _steel = pbr(rgb(1, 1, 1), metallic: 0.7, roughness: 0.45);
  static final _steelColor = v4(hex3(0x1C2638));

  /// The back of a rooftop sign: painted sheet.
  static final _backColor = v4(hex3(0x7B8597));

  PhysicallyBasedMaterial _glowing(double roughness) => PhysicallyBasedMaterial()
    ..metallicFactor = 0
    ..roughnessFactor = roughness
    ..emissiveTexture = _swatches
    ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
    ..emissiveStrength = 0;

  /// [d] with every texture coordinate on [color]'s swatch.
  MeshData _onSwatch(MeshData d, Color color) {
    final u = swatchU(_palette.indexOf(color), _palette.length);
    final uv = Float32List(d.vertexCount * 2);
    for (var i = 0; i < d.vertexCount; i++) {
      uv
        ..[i * 2] = u
        ..[i * 2 + 1] = 0.5;
    }
    return painted(d, lin(color), uvs: uv);
  }

  TextStyle _style(String? lang, {double size = 120}) => TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: const [BP.arabic],
    fontSize: size,
    height: 1.15,
    locale: lang == null ? null : Locale(lang),
    fontWeight: FontWeight.w700,
    fontVariations: const [FontVariation('wght', 700)],
  );

  /// The words the signs draw, per script: the web fetches their fonts
  /// before the city is built (the world's warm-up, all at once).
  static List<(String, TextStyle)> get fontRuns => [
    for (final locale in [null, 'ja', 'zh', 'ko'])
      if ([
            for (final (w, _, l) in _words)
              if (l == locale) w,
            if (locale == 'ja') ...[for (final (w, _) in _blades) w, '工事中', '安全第一'],
          ]
          case final words when words.isNotEmpty)
        (words.join(' '), TextStyle(fontFamily: BP.display, fontSize: 40, locale: locale == null ? null : Locale(locale))),
  ];

  Future<void> init(List<({vm.Vector3 at, double rotY, double width})> roofs) async {
    // Web: the fallback fonts these words need (signs are drawn once).
    await awaitFallbackFontsAll(fontRuns);
    _swatches = swatchTexture([for (final c in _palette) lin3(c)]);
    for (var h = 0; h < 4; h++) {
      _habits.add(_glowing(0.35));
    }
    _lightbox = _glowing(0.6);
    _ink = pbr(lin(const Color(0xFF14203A)), roughness: 0.5);
    await Future.wait([_rooftops(roofs), _bladeSigns(), _boards()]);
    _batch.build(scene, 'signs', castsShadows: false, lightChannelMask: 0x01);
  }

  // ── Rooftop neon ──────────────────────────────────────────────────────────

  Future<void> _rooftops(List<({vm.Vector3 at, double rotY, double width})> roofs) async {
    // One word per roof, nearest roofs first, alternating sides.
    final picks = [
      for (var i = 0; i < roofs.length; i++)
        if (roofs[i].width > 6) i,
    ]..sort((a, b) => (roofs[a].at.z + (roofs[a].at.x > 0 ? 3 : 0)).compareTo(roofs[b].at.z + (roofs[b].at.x > 0 ? 3 : 0)));
    final n = math.min(picks.length, _words.length);
    final specs = <TextSolid>[];
    for (var k = 0; k < n; k++) {
      final (word, _, lang) = _words[k];
      specs.add(TextSolid(word, _style(lang), height: 1, depth: 0.35, simplify: 0.7));
    }
    // Measure at unit height, then fit each word to its roof.
    final unit = await extrudeTexts(specs);
    final sized = <TextSolid>[];
    final heights = <double>[];
    for (var k = 0; k < n; k++) {
      final r = roofs[picks[k]];
      final aspect = unit[k].width / math.max(unit[k].height, 1e-3);
      final h = math.min(3.4, (r.width - 0.6) / math.max(aspect, 0.1));
      heights.add(h);
      final (word, _, lang) = _words[k];
      sized.add(TextSolid(word, _style(lang), height: h, depth: 0.4, simplify: 0.7));
    }
    final meshes = await extrudeTexts(sized);
    for (var k = 0; k < n; k++) {
      final r = roofs[picks[k]];
      final m = meshes[k];
      if (m.vertexCount == 0) continue;
      final (_, color, _) = _words[k];
      final root = trs(r.at, rotY: r.rotY);
      // A steel rack: two posts and the rails the letters stand on.
      final w = m.width + 0.8, h = heights[k];
      void steel(vm.Vector3 size, vm.Vector3 at) => _batch.add(_steel, part(CuboidGeometry(size), root * vm.Matrix4.translation(at), _steelColor));
      steel(vm.Vector3(w, 0.16, 0.16), vm.Vector3(0, 0.55, 0.3));
      steel(vm.Vector3(w, 0.12, 0.12), vm.Vector3(0, 0.62 + h * 0.7, 0.45));
      for (final px in [-w / 2 + 0.3, w / 2 - 0.3]) {
        steel(vm.Vector3(0.12, 0.62 + h * 0.75, 0.12), vm.Vector3(px, (0.62 + h * 0.75) / 2, 0.45));
      }
      // Its back, on the rack: from behind, a sign's back (painted sheet on
      // a frame, not the word in mirror writing).
      _batch.add(_steel, part(CuboidGeometry(vm.Vector3(w, h + 0.3, 0.06)), root * vm.Matrix4.translation(vm.Vector3(0, 0.64 + h / 2, 0.56)), _backColor));
      for (final f in const [0.18, 0.5, 0.82]) {
        steel(vm.Vector3(w + 0.1, 0.1, 0.1), vm.Vector3(0, 0.49 + (h + 0.3) * f, 0.64));
      }
      for (var k = 0; k <= (w / 2.2).floor(); k++) {
        final x = -w / 2 + 0.05 + k * (w - 0.1) / math.max(1, (w / 2.2).floor());
        steel(vm.Vector3(0.1, h + 0.3, 0.1), vm.Vector3(x, 0.64 + h / 2, 0.64));
      }
      final letters = MeshData(positions: m.positions, vertexCount: m.vertexCount, normals: m.normals, texCoords: m.uvs, indices: m.indices);
      _batch.add(_habits[k % _habits.length], _onSwatch(letters, color).transformed(root * vm.Matrix4.translation(vm.Vector3(0, 0.64, 0))));
    }
  }

  // ── Blade signs (縦看板) on the blocks along the side streets ────────────

  Future<void> _bladeSigns() async {
    final specs = [
      for (final (word, _) in _blades) TextSolid(word.split('').join('\n'), _style('ja', size: 110).copyWith(height: 1.0), height: 1, depth: 0.22),
    ];
    final unit = await extrudeTexts(specs);
    final sized = <TextSolid>[];
    for (var k = 0; k < _blades.length; k++) {
      final chars = _blades[k].$1.length;
      final h = 1.15 * chars;
      final aspect = unit[k].width / math.max(unit[k].height, 1e-3);
      sized.add(TextSolid(specs[k].text, specs[k].style, height: math.min(h, 1.3 / math.max(aspect, 0.05)), depth: 0.22));
    }
    final meshes = await extrudeTexts(sized);
    for (var k = 0; k < _blades.length; k++) {
      final m = meshes[k];
      if (m.vertexCount == 0) continue;
      final (_, color) = _blades[k];
      final side = k.isEven ? 1.0 : -1.0;
      final z = -6.0 + 13.0 * (k ~/ 2) + 4 * rnd(k, 3);
      final x = side * (Plan.walkBlock + 0.9);
      // (None on the mini world's buildings.)
      if (Plan.inLot(x, z, 1.5)) continue;
      const y = 3.4;
      final panelH = m.height + 0.7, panelW = m.width + 0.6;
      // A lightbox panel sticking out over the sidewalk, facing the camera,
      // with a coloured cap and a bracket to the wall.
      final root = vm.Matrix4.translation(vm.Vector3(x - side * (panelW / 2 + 0.25), y, z));
      MeshData box(vm.Vector3 size, vm.Vector3 at) => CuboidGeometry(size).extractMeshData().transformed(root * vm.Matrix4.translation(at));
      _batch.add(_lightbox, _onSwatch(box(vm.Vector3(panelW, panelH, 0.3), vm.Vector3(0, panelH / 2, 0)), color));
      final cap = _onSwatch(box(vm.Vector3(panelW + 0.1, 0.18, 0.36), vm.Vector3(0, panelH + 0.09, 0)), color);
      _batch.add(_lightbox, cap);
      _batch.add(_steel, part(CuboidGeometry(vm.Vector3(0.6, 0.1, 0.1)), root * vm.Matrix4.translation(vm.Vector3(side * (panelW / 2 + 0.25), panelH - 0.3, 0)), _steelColor));
      final letters = MeshData(positions: m.positions, vertexCount: m.vertexCount, normals: m.normals, texCoords: m.uvs, indices: m.indices);
      _batch.add(_ink, painted(letters, vm.Vector4(1, 1, 1, 1)).transformed(root * vm.Matrix4.translation(vm.Vector3(0, 0.35, -0.24))));
    }
  }

  // ── The site's boards ─────────────────────────────────────────────────────

  Future<void> _boards() async {
    // 工事中: a yellow standing board at the plaza's front-left corner.
    final kouji = await paintedTexture(512, 680, (c, s) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width, s.height), const Radius.circular(36));
      c.drawRRect(r, Paint()..color = const Color(0xFFFFC94A));
      c.drawRRect(r.deflate(18), Paint()
        ..color = const Color(0xFF1B2233)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14);
      // Hazard stripes along the top.
      c.save();
      c.clipRect(Rect.fromLTWH(32, 32, s.width - 64, 70));
      for (var x = -80.0; x < s.width; x += 56) {
        c.drawLine(Offset(x, 110), Offset(x + 80, 20), Paint()
          ..color = const Color(0xFF1B2233)
          ..strokeWidth = 24
          ..strokeCap = StrokeCap.butt);
      }
      c.restore();
      _text(c, '工事中', Rect.fromLTWH(0, 130, s.width, 260), 190, const Color(0xFF1B2233));
      _text(c, 'ご迷惑をおかけします', Rect.fromLTWH(0, 420, s.width, 70), 44, const Color(0xFF1B2233));
      _text(c, '名前を建設しています', Rect.fromLTWH(0, 490, s.width, 60), 38, const Color(0xFF7A4A10));
      _text(c, 'NAME CITY · UNDER CONSTRUCTION', Rect.fromLTWH(0, 585, s.width, 50), 26, const Color(0xFF1B2233));
    });
    final koujiMat = PhysicallyBasedMaterial()
      ..baseColorTexture = kouji
      ..metallicFactor = 0
      ..roughnessFactor = 0.6
      ..emissiveTexture = kouji
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0;
    _boardMats.add(koujiMat);
    final at = trs(vm.Vector3(-13.8, 0, Plan.plazaZ0 + 0.45), rotY: 0.18);
    scene.add(Node(name: '工事中', mesh: Mesh(boardGeometry(1.25, 1.66), koujiMat), localTransform: at * vm.Matrix4.translation(vm.Vector3(0, 1.2, 0))));
    for (final x in [-0.55, 0.55]) {
      _batch.add(_steel, part(CuboidGeometry(vm.Vector3(0.07, 2.1, 0.07)), at * vm.Matrix4.translation(vm.Vector3(x, 1.05, 0.06)), _steelColor));
    }
    _batch.add(_steel, part(CuboidGeometry(vm.Vector3(1.4, 0.08, 0.5)), at * vm.Matrix4.translation(vm.Vector3(0, 0.04, 0.06)), _steelColor));

    // 安全第一: a white banner with the green cross, on the front barriers.
    final anzen = await paintedTexture(1024, 256, (c, s) {
      c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), Paint()..color = const Color(0xFFF7F4EC));
      c.drawRect(Rect.fromLTWH(10, 10, s.width - 20, s.height - 20), Paint()
        ..color = const Color(0xFF21A86B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10);
      // The green cross.
      final cross = Paint()..color = const Color(0xFF21A86B);
      c.drawRect(const Rect.fromLTWH(70, 108, 150, 40), cross);
      c.drawRect(const Rect.fromLTWH(125, 53, 40, 150), cross);
      _text(c, '安全第一', Rect.fromLTWH(250, 30, s.width - 290, 190), 150, const Color(0xFF167A4C));
    });
    final anzenMat = PhysicallyBasedMaterial()
      ..baseColorTexture = anzen
      ..metallicFactor = 0
      ..roughnessFactor = 0.75
      ..emissiveTexture = anzen
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0;
    _boardMats.add(anzenMat);
    scene.add(
      Node(
        name: '安全第一',
        mesh: Mesh(boardGeometry(3.6, 0.9), anzenMat),
        localTransform: trs(vm.Vector3(7.6, 0.75, Plan.plazaZ0 - 0.39)), // (left of the site gate)
      ),
    );
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
    )..layout(maxWidth: box.width);
    var scale = 1.0;
    if (tp.width > box.width * 0.94) scale = box.width * 0.94 / tp.width;
    c.save();
    c.translate(box.center.dx, box.center.dy);
    c.scale(scale);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }

  // ── Night ────────────────────────────────────────────────────────────────

  void update(double night, double t) {
    final on = smooth(0.12, 0.5, night);
    for (final b in _boardMats) {
      b.emissiveStrength = 0.22 * on;
    }
    _lightbox.emissiveStrength = 1.6 * on;
    // Each group of signs has its habit: steady, a slow breath, a blink, or a
    // tube that stutters now and then.
    for (var h = 0; h < _habits.length; h++) {
      var k = 1.0;
      switch (h) {
        case 1:
          k = 0.8 + 0.2 * math.sin(t * 1.7);
        case 2:
          k = (t * 0.5) % 4 < 3.2 ? 1 : 0.15;
        case 3:
          final w = (t + 7) % 23;
          k = w < 1.2 ? (rnd((t * 14).floor(), 3) > 0.45 ? 1 : 0.1) : 1;
      }
      _habits[h].emissiveStrength = 0.35 + 4.2 * on * k;
    }
  }
}
