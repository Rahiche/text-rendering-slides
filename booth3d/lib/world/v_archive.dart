import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'city_plan.dart';
import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// 地下書庫 · The Unicode archive: a warehouse under the Unicode tower's lot,
/// down a stair from the side street, every code point a crate on its
/// racks. A rack holds 128 crates, so ASCII (1963) is one rack; the
/// codespace (1,114,112 code points) is 8,704 racks, in 32 rows 109
/// metres long, one behind another 170 metres back into the dark.
///
/// Only a talk plays it. The camera comes down the stair into the dark,
/// and the light comes on over one rack: ASCII, 128. Then, as the
/// camera pulls back and up, over what each version filled: Unicode 1.0
/// (1991, 7,161: 56 racks along the first row), 6.0 (2010, 109,449: the
/// emoji first, in colour, then three rows and more), 18 (2026, 172,808:
/// five rows). Last, the lights over the rest of the hall: rack after
/// empty rack to the far wall. All of that is 15.5 percent of it.
///
/// It's all lit by itself (unlit materials, their shading painted on, a
/// light switched on a crate's brightness), so nothing of the sun's or
/// the sky's light gets down here; the sky makes the air dark down here
/// ([undergroundAt]).
class UnicodeArchive extends Vignette {
  UnicodeArchive(super.kit);

  @override
  String get name => 'archive';
  @override
  String get kick => 'UNICODE ARCHIVE';
  @override
  String get line => '128 → 172,808 → 1,114,112';
  @override
  String get note => 'one rack is ASCII; the codespace is 8,704 racks, 15.5% in use';

  @override
  bool get talkOnly => true;
  @override
  double get loop => 50;
  @override
  double get visit => 46.6;

  /// The stair's top on the tower's lot, by the side street, going down
  /// eastwards (the frame's +z: world +x; its +x is world −z).
  @override
  final frame = trs(vm.Vector3(33.7, 0, 88), rotY: math.pi / 2);

  // ── The hall ──────────────────────────────────────────────────────────────

  /// The floor and the ceiling (y).
  static const _floor = -14.5, _ceil = -0.5;

  /// The racks: rows ("lines") along x, one behind another in z, each a
  /// double-sided rack [_depth] deep; [_bays] bays [_bayW] wide along a
  /// line, [_levels] levels [_levelH] high (the first a little off the
  /// floor). A rack ("unit") is one bay's level on one side: 16 crates by
  /// 8, 128.
  static const _lines = 32, _bays = 34, _levels = 4;
  static const _bayW = 3.2, _levelH = 1.6, _base = 0.15, _depth = 2.4, _pitch = 5.4, _z0 = 25.0;
  static const _perSide = _bays * _levels, _perLine = 2 * _perSide;
  static const _units = _lines * _perLine; // 8,704: 1,114,112 / 128

  /// The hall's walls.
  static const _x0 = -5.0, _x1 = _bays * _bayW + 5.0, _zFront = -5.0, _zBack = _z0 + (_lines - 1) * _pitch + _depth / 2 + 4.0;

  /// The stair: from the street (z [_s0], y 0) down to the floor ([_s1]),
  /// between x [_sx0] and [_sx1]; open overhead as far as [_sOpen] (the
  /// ground's opening, Plan.archiveHole).
  static const _s0 = -4.2, _s1 = 17.8, _sx0 = 0.5, _sx1 = 3.5, _sOpen = 0.0;

  /// Line [k]'s middle (z).
  static double _lineZ(int k) => _z0 + k * _pitch;

  // ── The eras ──────────────────────────────────────────────────────────────

  /// What each version filled (racks, counted from the first: the code
  /// points / 128, rounded up), what it holds, when its lights come on and
  /// how long they take to reach its last rack; the empty rest of the hall
  /// last. Timed to the narration, which holds between its sentences for
  /// the picture (tool/narration/script.py's PAUSES): "…ASCII had 128
  /// characters." (held on the rack) "Unicode 1, in '91, had about 7,000."
  /// "Emoji arrived with Unicode 6, in 2010." "And today Unicode 18 has
  /// 172,808 characters…" "And all of that is still only 15 and a half
  /// percent of the code space."
  static const _eras = [
    (1, 128, 6.9, 0.3),
    (56, 7161, 14.6, 3.4),
    (856, 109449, 20.7, 4.6),
    (1351, 172808, 26.6, 3.8),
    (_units, 1114112, 35.9, 4.4),
  ];

  /// Unicode 6.0's emoji: its first racks (722 of them).
  static const _emoji0 = 56, _emoji1 = 62;

  /// When rack [n]'s light comes on, and whether it's in use.
  static double _onAt(int n) {
    var first = 0;
    for (final (last, _, at, len) in _eras) {
      if (n < last) return at + len * (n - first) / math.max(1, last - 1 - first);
      first = last;
    }
    return 1e9;
  }

  static bool _used(int n) => n < _eras[3].$1;

  /// Rack [n]'s line, side (0 the front, facing −z; 1 the back), bay and
  /// level.
  static (int, int, int, int) _cell(int n) {
    final r = n % _perLine, q = r % _perSide;
    return (n ~/ _perLine, r ~/ _perSide, q ~/ _levels, q % _levels);
  }

  // ── Built ─────────────────────────────────────────────────────────────────

  /// Everything underground (shown only while the talk's down here).
  final _hall = Node(name: 'archive hall');

  /// The crates, a mesh per texture (the instance: rack n), and the racks'
  /// steel: a frame at every bay's edge, the beams of every bay (a line's
  /// each), the lights over the aisles, the floor in front of each bay.
  final _crates = <InstancedMesh>[];
  final _crateMesh = Int32List(_units)..fillRange(0, _units, -1), _crateIndex = Int32List(_units);
  late final InstancedMesh _frames, _beams, _lamps, _floorTiles, _shell, _stair;

  /// Each rack's brightness now (for what changed), each cell's (a line's
  /// bay), each aisle bay's lamp and floor.
  final _unitB = Float32List(_units)..fillRange(0, _units, -1);
  final _cellB = Float32List(_lines * _bays);
  final _aisleB = Float32List((_lines + 1) * _bays), _aisleWas = Float32List((_lines + 1) * _bays)..fillRange(0, (_lines + 1) * _bays, -1);
  final _cellWas = Float32List(_lines * _bays)..fillRange(0, _lines * _bays, -1);
  double _shellWas = -1;

  /// The signs: what each era filled, the counter's board; their
  /// materials (lit with their era).
  final _signs = <(UnlitMaterial, double)>[];
  late final Node _curtain;
  bool _ready = false;

  static const _ink = TextStyle(fontFamily: BP.display, fontFamilyFallback: [BP.arabic], fontWeight: FontWeight.w600);

  @override
  List<(String, TextStyle)> get fontRuns => [
    for (final (_, g) in _scripts) (g.join(), _ink.copyWith(fontSize: 40)),
    ('UNICODE ARCHIVE B1 one crate per code point 1963 ASCII 1991 Unicode 1.0 2010 6.0 2026 18 characters in use the rest still empty 0123456789,·%', _ink.copyWith(fontSize: 40)),
  ];

  @override
  Future<void> init() async {
    makePool(boxes: 4, cyls: 2, glows: 160);
    detail.add(_hall);
    _hall
      ..visible = false
      ..localTransform = frame;
    final textures = await Future.wait([
      _asciiTexture(),
      for (final (crate, glyphs) in _scripts) _rackTexture(glyphs, crate),
    ]);
    // The crates: a box a rack (its front the texture, its sides and top
    // the crates' cardboard), a mesh per texture.
    final crateGeo = MeshGeometry.fromMeshData(_shaded(_crateBox(_bayW - 0.1, _levelH - 0.2, _depth / 2 - 0.08), vm.Vector4(1, 1, 1, 1)));
    for (final tex in textures) {
      final m = InstancedMesh(geometry: crateGeo, material: UnlitMaterial(colorTexture: tex), cullInstances: true);
      _crates.add(m);
    }
    for (var n = 0; n < _eras[3].$1; n++) {
      final (k, side, bay, level) = _cell(n);
      final t = _textureOf(n);
      final z = _lineZ(k) + (side == 0 ? -1 : 1) * (_depth / 4 + 0.02);
      final at = trs(
        vm.Vector3((bay + 0.5) * _bayW, _floor + _base + 0.06 + level * _levelH + (_levelH - 0.2) / 2, z),
        rotY: side == 0 ? 0 : math.pi,
      );
      _crateMesh[n] = t;
      _crateIndex[n] = _crates[t].addInstance(at, color: _dark);
    }
    _buildSteel();
    _buildRoom();
    for (final m in [..._crates, _frames, _beams, _lamps, _floorTiles, _shell]) {
      _hall.add(Node(name: 'archive part')
        ..castsShadows = false
        ..addComponent(InstancedMeshComponent(m)));
    }
    // (The stair's always there, from the street: steps going down into
    // the dark, the curtain part way down.)
    shell.add(Node(name: 'archive stair', localTransform: frame)
      ..castsShadows = false
      ..addComponent(InstancedMeshComponent(_stair)));
    await _buildSigns();
    await _buildEntrance();
    _ready = true;
  }

  static final _dark = vm.Vector4(0.02, 0.02, 0.024, 1);

  /// How bright the empty rest of the hall gets once its lights are on.
  static const _emptyLit = 0.5;

  /// The racks' steel lit [b]: in use, as painted; empty, dim and cool.
  vm.Vector4 _steel(double b) {
    // (Unlit, just made out in the dark: the hall's size before its lights.)
    final s = 0.06 + 0.91 * b;
    return b > _emptyLit + 1e-3 || b < 1e-3 ? (_c..setValues(s, s, s, 1)) : (_c..setValues(s * 0.7, s * 0.8, s * 0.95, 1));
  }

  /// Which texture rack [n] wears: ASCII; then the scripts Unicode 1.0
  /// brought; the emoji; then mostly CJK, with the rest of the world's
  /// scripts among them.
  static int _textureOf(int n) {
    if (n == 0) return 0;
    if (n >= _emoji0 && n < _emoji1) return 1 + _emojiScript;
    if (n < _eras[1].$1) return 1 + (n - 1) % _firstScripts;
    final r = rnd(n, 17);
    if (r < 0.62) return 1 + _cjkScript + (n % 2);
    if (r < 0.7) return 1 + _hangulScript;
    if (r < 0.74 && n >= _eras[2].$1) return 1 + _emojiScript;
    if (r < 0.82 && n >= _eras[2].$1) return 1 + _historicScript;
    return 1 + (n * 7) % _firstScripts;
  }

  /// The racks' scripts: a crate colour and 128 characters each (the
  /// first [_firstScripts] Unicode 1.0's).
  static final _scripts = <(int, List<String>)>[
    (0xC9A27A, _range([(0x00C0, 0x017F)])), // Latin-1, Latin Extended-A
    (0xBFA57E, _range([(0x0391, 0x03A9), (0x03B1, 0x03C9), (0x0410, 0x044F)], skip: {0x03A2})), // Greek, Cyrillic
    (0xC4A07A, _range([(0x0531, 0x0556), (0x05D0, 0x05EA), (0x0627, 0x064A)])), // Armenian, Hebrew, Arabic
    (0xCDA77C, _range([(0x0905, 0x0939), (0x0985, 0x09B9)], skip: {0x098D, 0x098E, 0x0991, 0x0992, 0x09A9, 0x09B1, 0x09B3, 0x09B4, 0x09B5})), // Devanagari, Bengali
    (0xC29E78, _range([(0x0E01, 0x0E2E), (0x10D0, 0x10FA), (0x0E81, 0x0EA3)], skip: {0x0E83, 0x0E85, 0x0E8B, 0x0E8C, 0x0E8E, 0x0E8F, 0x0E90, 0x0E91, 0x0E92, 0x0E93, 0x0E98, 0x0EA0})), // Thai, Georgian, Lao
    (0xB8A07E, _range([(0x2190, 0x21FF), (0x2200, 0x2232)])), // arrows, maths
    (0xC8A47C, _range([(0x4E00, 0x4E7F)])), // CJK
    (0xCCA982, _range([(0x6F22, 0x6FA1)])), // CJK, further on
    (0xC5A27B, _range([(0xAC00, 0xAC7F)])), // Hangul syllables
    (0xF2B8C8, _range([(0x1F600, 0x1F64F), (0x1F330, 0x1F35F)])), // emoji
    (0xA9B4BF, _range([(0x13A0, 0x13F4), (0x16A0, 0x16EA), (0x2D30, 0x2D5D)])), // Cherokee, Runic, Tifinagh
  ];
  static const _firstScripts = 6, _cjkScript = 6, _hangulScript = 8, _emojiScript = 9, _historicScript = 10;

  /// 128 characters from [ranges] (inclusive), repeating if short.
  static List<String> _range(List<(int, int)> ranges, {Set<int> skip = const {}}) {
    final all = [
      for (final (a, b) in ranges)
        for (var c = a; c <= b; c++)
          if (!skip.contains(c)) String.fromCharCode(c),
    ];
    return [for (var i = 0; i < 128; i++) all[i % all.length]];
  }

  // ── Textures ──────────────────────────────────────────────────────────────

  /// A rack's front as its crates show it: 16 by 8, each a crate with its
  /// character on a label; a strip of the crates' cardboard under it (the
  /// boxes' sides and tops).
  Future<Texture2D> _rackTexture(List<String> glyphs, int crate, {int w = 1024}) {
    final cell = w / 16;
    return paintedTexture(w, (w / 2 + cell / 2).round(), (c, s) {
      final face = Rect.fromLTWH(0, 0, s.width, cell * 8);
      c.drawRect(face, Paint()..color = const Color(0xFF1A1C20));
      for (var i = 0; i < 128; i++) {
        final x = (i % 16) * cell, y = (i ~/ 16) * cell;
        final r = Rect.fromLTWH(x + cell * 0.04, y + cell * 0.06, cell * 0.92, cell * 0.9);
        final tone = 0.9 + 0.2 * rnd(i, crate & 0xFF, 3);
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * 0.06)), Paint()..color = _tint(crate, tone));
        // (A seam across the top, the flaps.)
        c.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.1, r.width, cell * 0.025), Paint()..color = const Color(0x33000000));
        final label = Rect.fromLTWH(r.left + r.width * 0.16, r.top + r.height * 0.24, r.width * 0.68, r.height * 0.62);
        c.drawRRect(RRect.fromRectAndRadius(label, Radius.circular(cell * 0.04)), Paint()..color = const Color(0xFFF7F4EC));
        _glyph(c, glyphs[i], label, cell * 0.36, const Color(0xFF1E2128));
      }
      c.drawRect(Rect.fromLTWH(0, cell * 8, s.width, s.height - cell * 8), Paint()..color = _tint(crate, 0.82));
    });
  }

  /// ASCII's rack, larger (seen close): its 128 in order, eight rows of
  /// 16 (0x00 top left … 0x7F bottom right), each crate's code under its
  /// character; the control codes (and DEL) as their pictures, in grey.
  Future<Texture2D> _asciiTexture() {
    const w = 2048, cell = w / 16;
    return paintedTexture(w, (w / 2 + cell / 2).round(), (c, s) {
      c.drawRect(Rect.fromLTWH(0, 0, s.width, cell * 8), Paint()..color = const Color(0xFF1A1C20));
      for (var i = 0; i < 128; i++) {
        final x = (i % 16) * cell, y = (i ~/ 16) * cell;
        final r = Rect.fromLTWH(x + cell * 0.04, y + cell * 0.06, cell * 0.92, cell * 0.9);
        final control = i < 32 || i == 127;
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * 0.06)), Paint()..color = control ? const Color(0xFFB9A585) : const Color(0xFFD9B98C));
        c.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.08, r.width, cell * 0.02), Paint()..color = const Color(0x33000000));
        final label = Rect.fromLTWH(r.left + r.width * 0.12, r.top + r.height * 0.18, r.width * 0.76, r.height * 0.7);
        c.drawRRect(RRect.fromRectAndRadius(label, Radius.circular(cell * 0.05)), Paint()..color = const Color(0xFFFBF9F3));
        final ch = i < 32 ? String.fromCharCode(0x2400 + i) : (i == 32 ? '␠' : (i == 127 ? '␡' : String.fromCharCode(i)));
        _glyph(c, ch, Rect.fromLTWH(label.left, label.top, label.width, label.height * 0.72), cell * (control || i == 32 ? 0.3 : 0.42), control || i == 32 ? const Color(0xFF7A7F8A) : const Color(0xFF14161B));
        _glyph(
          c,
          '0x${i.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          Rect.fromLTWH(label.left, label.top + label.height * 0.7, label.width, label.height * 0.28),
          cell * 0.11,
          const Color(0xFF8A6A2A),
          family: BP.mono,
        );
      }
      c.drawRect(Rect.fromLTWH(0, cell * 8, s.width, s.height - cell * 8), Paint()..color = const Color(0xFFC9AE84));
    });
  }

  static Color _tint(int rgb, double k) {
    int ch(int v) => (v * k).round().clamp(0, 255);
    return Color.fromARGB(255, ch((rgb >> 16) & 0xFF), ch((rgb >> 8) & 0xFF), ch(rgb & 0xFF));
  }

  /// [s] centred in [box], [size] px (shrunk to fit).
  static void _glyph(Canvas c, String s, Rect box, double size, Color color, {String? family}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: _ink.copyWith(fontSize: size, color: color, fontFamily: family ?? BP.display),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final k = tp.width > box.width * 0.9 ? box.width * 0.9 / tp.width : 1.0;
    c
      ..save()
      ..translate(box.center.dx, box.center.dy)
      ..scale(k);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }

  // ── Geometry ──────────────────────────────────────────────────────────────

  /// A crate box [w]×[h]×[d], its front (−z) the texture's face (all but
  /// its bottom strip), the rest the strip's cardboard.
  static MeshData _crateBox(double w, double h, double d) {
    final m = CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData();
    final uv = m.texCoords!, n = m.normals!, p = m.positions;
    const faceV = 8 / 8.5;
    for (var i = 0; i < m.vertexCount; i++) {
      if (n[i * 3 + 2] < -0.5) {
        uv[i * 2] = p[i * 3] / w + 0.5;
        uv[i * 2 + 1] = (0.5 - p[i * 3 + 1] / h) * faceV;
      } else {
        uv[i * 2] = 0.5;
        uv[i * 2 + 1] = (1 + faceV) / 2;
      }
    }
    return m;
  }

  /// [d] painted [color], shaded as if lit from above and in front (an
  /// unlit material shows what's painted).
  static MeshData _shaded(MeshData d, vm.Vector4 color, {double floor = 0.56}) {
    final colors = Float32List(d.vertexCount * 4), n = d.normals!;
    for (var i = 0; i < d.vertexCount; i++) {
      final lit = n[i * 3] * 0.3 + n[i * 3 + 1] * 0.85 - n[i * 3 + 2] * 0.43;
      final k = floor + (1 - floor) * math.max(0.0, lit);
      colors
        ..[i * 4] = color.x * k
        ..[i * 4 + 1] = color.y * k
        ..[i * 4 + 2] = color.z * k
        ..[i * 4 + 3] = color.w;
    }
    return MeshData(
      positions: d.positions,
      vertexCount: d.vertexCount,
      normals: d.normals,
      texCoords: d.texCoords ?? Float32List(d.vertexCount * 2),
      colors: colors,
      indices: d.indices,
    );
  }

  static MeshData _boxAt(double w, double h, double d, double x, double y, double z, vm.Vector4 color, {double floor = 0.56}) =>
      _shaded(CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData().transformed(vm.Matrix4.translation(vm.Vector3(x, y, z))), color, floor: floor);

  /// The racks' steel: an upright frame at each bay's edge (two posts, the
  /// line's depth apart, tied across), the orange beams of each bay (at
  /// every level, both sides); a light over each aisle's bay.
  void _buildSteel() {
    final blue = Vignette.c(0x2F5D8C), orange = Vignette.c(0xE07B2A), grey = Vignette.c(0x9AA1AA);
    const top = _base + _levels * _levelH + 0.12;
    final frame = <MeshData>[
      for (final s in [-1.0, 1.0]) _boxAt(0.09, top, 0.09, 0, top / 2, s * (_depth / 2 - 0.05), blue),
      for (var y = 0.6; y < top; y += 1.6) _boxAt(0.05, 0.05, _depth - 0.1, 0, y, 0, blue),
      for (final s in [-1.0, 1.0]) _boxAt(0.2, 0.02, 0.2, 0, 0.01, s * (_depth / 2 - 0.05), grey),
    ];
    final beam = <MeshData>[
      for (var l = 0; l <= _levels; l++)
        for (final s in [-1.0, 1.0]) _boxAt(_bayW - 0.09, 0.12, 0.06, _bayW / 2, _base + l * _levelH, s * (_depth / 2 - 0.03), orange),
    ];
    _frames = InstancedMesh(geometry: merged(frame), material: UnlitMaterial(), cullInstances: true);
    _beams = InstancedMesh(geometry: merged(beam), material: UnlitMaterial(), cullInstances: true);
    for (var k = 0; k < _lines; k++) {
      for (var j = 0; j <= _bays; j++) {
        _frames.addInstance(vm.Matrix4.translation(vm.Vector3(j * _bayW, _floor, _lineZ(k))), color: _dark);
      }
      for (var j = 0; j < _bays; j++) {
        _beams.addInstance(vm.Matrix4.translation(vm.Vector3(j * _bayW, _floor, _lineZ(k))), color: _dark);
      }
    }
    // A strip light over every aisle's bay (the front aisle, those between
    // lines, the back one): lit (HDR) with what's under it.
    final lamp = merged([_boxAt(_bayW * 0.72, 0.05, 0.2, 0, -0.05, 0, vm.Vector4(1, 1, 1, 1), floor: 1)]);
    _lamps = InstancedMesh(geometry: lamp, material: UnlitMaterial(), cullInstances: true);
    // The floor in front of each bay, along each aisle (its concrete's
    // tone painted; lit with the lamp over it).
    final tile = merged([_boxAt(_bayW, 0.02, 1, _bayW / 2, 0, 0.5, Vignette.c(0x8C8880), floor: 1)]);
    _floorTiles = InstancedMesh(geometry: tile, material: UnlitMaterial(), cullInstances: true);
    for (var a = 0; a <= _lines; a++) {
      final (za, zb) = _aisle(a);
      for (var j = 0; j < _bays; j++) {
        _lamps.addInstance(vm.Matrix4.translation(vm.Vector3((j + 0.5) * _bayW, _ceil - 0.06, (za + zb) / 2)), color: _dark);
        _floorTiles.addInstance(vm.Matrix4.translation(vm.Vector3(j * _bayW, _floor, za)) * vm.Matrix4.diagonal3Values(1, 1, zb - za), color: _dark);
      }
    }
  }

  /// Aisle [a]'s span in z: the front one (from the front wall to line
  /// 0), those between lines, the back one (to the back wall).
  static (double, double) _aisle(int a) {
    final za = a == 0 ? _zFront : _lineZ(a - 1) + _depth / 2;
    final zb = a == _lines ? _zBack : _lineZ(a) - _depth / 2;
    return (za, zb);
  }

  /// The room: the floor under it all, the walls, the ceiling (dark
  /// concrete, lit a little once the hall's lights are on); the stair down
  /// with its rails, open overhead where it comes down from the street.
  void _buildRoom() {
    final concrete = Vignette.c(0x4A4A4C), wall = Vignette.c(0x5A5C60), ceiling = Vignette.c(0x3C3E44);
    const w = _x1 - _x0, d = _zBack - _zFront, h = _ceil - _floor;
    const cx = (_x0 + _x1) / 2, cz = (_zFront + _zBack) / 2;
    final parts = <MeshData>[
      _boxAt(w, 0.2, d, cx, _floor - 0.1, cz, concrete, floor: 1),
      _boxAt(0.3, h, d, _x0, (_floor + _ceil) / 2, cz, wall),
      _boxAt(0.3, h, d, _x1, (_floor + _ceil) / 2, cz, wall),
      _boxAt(w, h, 0.3, cx, (_floor + _ceil) / 2, _zBack, wall),
      _boxAt(w, h, 0.3, cx, (_floor + _ceil) / 2, _zFront, wall),
      // The ceiling round the stair's opening.
      _boxAt(_sx0 - _x0, 0.3, d, (_x0 + _sx0) / 2, _ceil + 0.15, cz, ceiling),
      _boxAt(_x1 - _sx1, 0.3, d, (_sx1 + _x1) / 2, _ceil + 0.15, cz, ceiling),
      _boxAt(_sx1 - _sx0, 0.3, _s0 - _zFront, (_sx0 + _sx1) / 2, _ceil + 0.15, (_zFront + _s0) / 2, ceiling),
      _boxAt(_sx1 - _sx0, 0.3, _zBack - _sOpen, (_sx0 + _sx1) / 2, _ceil + 0.15, (_sOpen + _zBack) / 2, ceiling),
    ];
    _shell = InstancedMesh(geometry: merged(parts), material: UnlitMaterial())..addInstance(vm.Matrix4.identity(), color: vm.Vector4(0.05, 0.05, 0.05, 1));
    // The stair: steps (on a sloping slab), its two side walls up to the
    // street, rails along it once it's in the hall; lit by the daylight
    // falling in at the top, fading down it.
    final stair = <MeshData>[];
    const steps = 80;
    const run = (_s1 - _s0) / steps, rise = -_floor / steps;
    for (var i = 0; i < steps; i++) {
      final z = _s0 + (i + 0.5) * run, y = -(i + 1) * rise;
      // (Lighter where the daylight falls in from the street.)
      final k = 0.25 + 0.75 * c01(1 - i / 28), c = Vignette.c(0x8A8780);
      stair.add(_boxAt(_sx1 - _sx0, rise, run, (_sx0 + _sx1) / 2, y + rise / 2, z, vm.Vector4(c.x * k, c.y * k, c.z * k, 1), floor: 0.7));
    }
    final len = math.sqrt((_s1 - _s0) * (_s1 - _s0) + _floor * _floor), pitch = math.atan2(-_floor, _s1 - _s0);
    stair.add(
      _shaded(
        CuboidGeometry(vm.Vector3(_sx1 - _sx0 + 0.3, 0.3, len))
            .extractMeshData()
            .transformed(vm.Matrix4.translation(vm.Vector3((_sx0 + _sx1) / 2, _floor / 2 - 0.35, (_s0 + _s1) / 2)) * vm.Matrix4.rotationX(pitch)),
        Vignette.c(0x5A5852),
      ),
    );
    // (A centimetre into the opening: in front of the ground's cut edge.)
    for (final x in [_sx0 - 0.07, _sx1 + 0.07]) {
      // The wall beside it down from the street to the ceiling, and the
      // rail along it below.
      stair.add(_boxAt(0.16, 0.5 - _ceil, _sOpen - _s0, x, _ceil / 2 + 0.25, (_s0 + _sOpen) / 2, Vignette.c(0x77756F)));
      stair.add(
        _shaded(
          CuboidGeometry(vm.Vector3(0.06, 0.06, len))
              .extractMeshData()
              .transformed(vm.Matrix4.translation(vm.Vector3(x, _floor / 2 + 1.0, (_s0 + _s1) / 2)) * vm.Matrix4.rotationX(pitch)),
          Vignette.c(0xC9CDD4),
        ),
      );
    }
    // The lintel where the street's opening ends over the stair (the
    // ground's cut edge behind it).
    stair.add(_boxAt(_sx1 - _sx0 + 0.32, 0.5, 0.08, (_sx0 + _sx1) / 2, -0.25, _sOpen - 0.04, Vignette.c(0x77756F)));
    _stair = InstancedMesh(geometry: merged(stair), material: UnlitMaterial())..addInstance(vm.Matrix4.identity());
  }

  /// The signs over each era's racks (lit with it), and the counter's
  /// board.
  Future<void> _buildSigns() async {
    Future<void> board(double w, double h, vm.Vector3 at, double era, void Function(Canvas c, Size s) paint, {int px = 1024, double yaw = 0}) async {
      final tex = await paintedTexture(px, math.max(8, (px * h / w).round()), paint);
      final mat = UnlitMaterial(colorTexture: tex)..baseColorFactor = vm.Vector4(0.03, 0.03, 0.03, 1);
      _hall.add(Node(name: 'archive sign', mesh: Mesh(boardGeometry(w, h, thick: 0.06), mat), localTransform: trs(at, rotY: yaw))..castsShadows = false);
      _signs.add((mat, era));
    }

    void plate(Canvas c, Size s, String year, String what, String count, Color accent) {
      c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF101722));
      c.drawRect(Rect.fromLTWH(0, 0, s.width * 0.025, s.height), Paint()..color = accent);
      Vignette.text(c, '$year · $what', Rect.fromLTWH(s.width * 0.05, s.height * 0.08, s.width * 0.9, s.height * 0.46), s.height * 0.34, const Color(0xFFF2F4F8));
      Vignette.text(c, count, Rect.fromLTWH(s.width * 0.05, s.height * 0.54, s.width * 0.9, s.height * 0.38), s.height * 0.28, accent);
    }

    final front = _lineZ(0) - _depth / 2 - 0.12;
    await Future.wait([
      board(3.0, 0.42, vm.Vector3(1.6, _floor + _base + _levelH + 0.3, front - 0.05), _eras[0].$3, (c, s) => plate(c, s, '1963', 'ASCII', '128 characters', const Color(0xFFF2C94C))),
      board(6.4, 1.1, vm.Vector3(22.4, _floor + 8.0, front - 0.4), _eras[1].$3, (c, s) => plate(c, s, '1991', 'Unicode 1.0', '7,161 characters', const Color(0xFF5FB8FF))),
      board(7.4, 1.3, vm.Vector3(40, _floor + 8.4, _lineZ(1) - _depth / 2 - 0.4), _eras[2].$3, (c, s) => plate(c, s, '2010', 'Unicode 6.0', '109,449 · emoji 😀', const Color(0xFFF2994A))),
      board(7.4, 1.3, vm.Vector3(62, _floor + 8.4, _lineZ(4) - _depth / 2 - 0.4), _eras[3].$3, (c, s) => plate(c, s, '2026', 'Unicode 18', '172,808 characters', const Color(0xFF6FCF97))),
      // (Out over the empty racks, ahead as the camera sets off over them.)
      board(10.0, 1.7, vm.Vector3(74, _floor + 9.4, _lineZ(8) - _depth / 2 - 0.4), _eras[4].$3, (c, s) => plate(c, s, '1,114,112', 'code points', '15.5% in use · the rest still empty', const Color(0xFFBB6BD9))),
      // The counter's board (its digits are lit from the pool, both sides).
      board(9.6, 2.0, vm.Vector3(_counterX, _floor + 9.4, _edgeZ), 4.0, (c, s) => c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0B0F16)), px: 256),
    ]);
  }

  /// The street's way in: the opening's rails, a glass canopy on posts, its
  /// sign; a dark curtain at the stair's foot while the hall's not shown.
  Future<void> _buildEntrance() async {
    final b = Batch();
    final steel = pbr(rgb(1, 1, 1), metallic: 0.8, roughness: 0.35), stone = pbr(rgb(1, 1, 1), roughness: 0.7);
    final glass = pbr(rgb(0.85, 0.92, 0.96, 0.18), roughness: 0.06)..alphaMode = AlphaMode.blend;
    const xa = _sx0 - 0.2, xb = _sx1 + 0.2, za = _s0 - 0.25, zb = _sOpen + 0.25;
    // The kerb round the opening, rails on its sides and back.
    for (final (x, z, w, d) in [
      (xa, (za + zb) / 2, 0.3, zb - za),
      (xb, (za + zb) / 2, 0.3, zb - za),
      ((xa + xb) / 2, zb, xb - xa, 0.3),
    ]) {
      box(b, stone, w, 0.16, d, x, 0.08, z, Vignette.c(0x8C8A84));
      box(b, steel, w * 0.4 + 0.03, 0.06, d * 0.98, x, 1.05, z, Vignette.c(0xC9CDD4));
    }
    for (var z = za + 0.1; z <= zb; z += 1.0) {
      for (final x in [xa, xb]) {
        box(b, steel, 0.05, 1.0, 0.05, x, 0.55, z, Vignette.c(0xC9CDD4));
      }
    }
    // The canopy: four posts, a glass roof, a fascia for the sign.
    for (final (x, z) in [(xa, za), (xb, za), (xa, zb), (xb, zb)]) {
      box(b, steel, 0.12, 2.9, 0.12, x, 1.45, z, Vignette.c(0x3A4252));
    }
    box(b, steel, xb - xa + 0.3, 0.12, zb - za + 0.3, (xa + xb) / 2, 2.95, (za + zb) / 2, Vignette.c(0x3A4252));
    b.buildInto(shell, 'archive entrance');
    final roof = Batch();
    box(roof, glass, xb - xa + 0.1, 0.03, zb - za + 0.1, (xa + xb) / 2, 3.03, (za + zb) / 2, Vignette.c(0xFFFFFF));
    roof.buildInto(shell, 'archive canopy', castsShadows: false);
    await sign(
      xb - xa + 0.3,
      0.62,
      trs(vm.Vector3((xa + xb) / 2, 2.62, za - 0.09)),
      (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF14203A));
        Vignette.text(c, 'UNICODE ARCHIVE', Rect.fromLTWH(0, s.height * 0.08, s.width, s.height * 0.5), s.height * 0.38, const Color(0xFFF2C94C));
        Vignette.text(c, 'B1 · one crate per code point', Rect.fromLTWH(0, s.height * 0.56, s.width, s.height * 0.36), s.height * 0.24, const Color(0xFFE8ECF4));
      },
      px: 900,
      glow: 0.45,
      shell: true,
    );
    // (While the hall's not shown: the stair goes down into the dark.)
    _curtain = Node(
      name: 'archive curtain',
      mesh: Mesh(CuboidGeometry(vm.Vector3(_sx1 - _sx0 + 0.4, 4.0, 0.05)), UnlitMaterial()..baseColorFactor = vm.Vector4(0.004, 0.004, 0.005, 1)),
      localTransform: place(vm.Matrix4.translation(vm.Vector3((_sx0 + _sx1) / 2, _floor * 0.55 + 1.4, _s0 + (_s1 - _s0) * 0.55))),
    )..castsShadows = false;
    shell.add(_curtain);
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  final _c = vm.Vector4.zero();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    // (Still shown while the camera's down here after the talk's moved
    // on: it flies up out of the hall.)
    final shown = visited || _down;
    _hall.visible = shown;
    _curtain.visible = !shown;
    if (!shown) return;
    // Each rack's light: off until its era's wave reaches it, then on over
    // a moment (used: full; the empty rest of the hall: dim, and cool).
    for (var n = 0; n < _units; n++) {
      final on = seg(u, _onAt(n), _onAt(n) + 0.45);
      final b = on * (_used(n) ? 1.0 : _emptyLit);
      if ((b - _unitB[n]).abs() < 0.004) continue;
      _unitB[n] = b;
      final m = _crateMesh[n];
      if (m >= 0) {
        final k = 0.02 + 0.98 * b;
        _crates[m].setInstanceColor(_crateIndex[n], _c..setValues(k, k * 0.98, k * 0.94, 1));
      }
    }
    // The steel and the lamps follow the racks they're by: a line's bay is
    // as lit as its brightest rack; an aisle's bay as the bays either side.
    _cellB.fillRange(0, _cellB.length, 0);
    for (var n = 0; n < _units; n++) {
      final (k, _, j, _) = _cell(n);
      final i = k * _bays + j;
      if (_unitB[n] > _cellB[i]) _cellB[i] = _unitB[n];
    }
    for (var k = 0; k < _lines; k++) {
      for (var j = 0; j < _bays; j++) {
        final i = k * _bays + j, b = _cellB[i];
        if ((b - _cellWas[i]).abs() < 0.004) continue;
        _cellWas[i] = b;
        _beams.setInstanceColor(i, _steel(b));
      }
      for (var j = 0; j <= _bays; j++) {
        final a = j > 0 ? _cellB[k * _bays + j - 1] : 0.0, c = j < _bays ? _cellB[k * _bays + j] : 0.0;
        _frames.setInstanceColor(k * (_bays + 1) + j, _steel(math.max(a, c)));
      }
    }
    for (var a = 0; a <= _lines; a++) {
      for (var j = 0; j < _bays; j++) {
        final front = a > 0 ? _cellB[(a - 1) * _bays + j] : 0.0, back = a < _lines ? _cellB[a * _bays + j] : 0.0;
        final b = math.max(front, back), i = a * _bays + j;
        _aisleB[i] = b;
        if ((b - _aisleWas[i]).abs() < 0.004) continue;
        _aisleWas[i] = b;
        // In use: warm and bright; the empty rest of the hall: a dim, cool
        // white over bare racks.
        if (b > _emptyLit + 1e-3) {
          final l = 0.06 + 5.4 * b, f = 0.03 + 0.85 * b;
          _lamps.setInstanceColor(i, _c..setValues(l, l * 0.93, l * 0.8, 1));
          _floorTiles.setInstanceColor(i, _c..setValues(f, f * 0.98, f * 0.95, 1));
        } else {
          final l = 0.06 + 4.4 * b, f = 0.04 + 0.5 * b;
          _lamps.setInstanceColor(i, _c..setValues(l * 0.75, l * 0.88, l * 1.1, 1));
          _floorTiles.setInstanceColor(i, _c..setValues(f * 0.8, f * 0.88, f, 1));
        }
      }
    }
    // The room itself: just visible in the dark, lit as the hall's lights
    // come on.
    final room = 0.05 + 0.4 * seg(u, _eras[4].$3, _eras[4].$3 + 3.0) + 0.12 * seg(u, _eras[1].$3, _eras[3].$3 + 2);
    if ((room - _shellWas).abs() > 0.004) {
      _shellWas = room;
      _shell.setInstanceColor(0, _c..setValues(room, room, room * 1.02, 1));
    }
    for (final (m, at) in _signs) {
      final k = 0.03 + 0.97 * seg(u, at, at + 0.6);
      m.baseColorFactor = vm.Vector4(k, k, k, 1);
    }
    // The counter: the characters lit so far, counting up with the
    // lights; at the end, the whole codespace.
    pool.begin();
    final text = _group(_count(u)), on = vm.Vector4(2.4, 1.3, 0.35, 1);
    _sevenSeg(text, _counterX, _floor + 9.4, _edgeZ - 0.05, 0.95, -1, on);
    _sevenSeg(text, _counterX, _floor + 9.4, _edgeZ + 0.05, 0.95, 1, on);
    pool.end();
  }

  /// Where the counter and the codespace's sign hang: over the aisle where
  /// the racks in use end (z), the counter towards the right (x).
  static final _edgeZ = (_lineZ(4) + _lineZ(5)) / 2;
  static const _counterX = 76.0;

  /// The characters lit at [u]: each era's count once its wave is done,
  /// counting up through the wave.
  static int _count(double u) {
    var before = 0;
    for (final (_, count, at, len) in _eras) {
      if (u < at) return before;
      if (u < at + len + 0.45) return (before + (count - before) * eio(seg(u, at, at + len + 0.45))).round();
      before = count;
    }
    return before;
  }

  static String _group(int n) {
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  /// [s] (digits and commas) as lit seven-segment digits [size] high,
  /// centred at (x, y), on a face at depth z looking towards −z ([toward]
  /// −1) or +z (1): read the right way round from that side.
  void _sevenSeg(String s, double x, double y, double z, double size, double toward, vm.Vector4 on) {
    const segs = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F];
    final dw = size * 0.62, th = size * 0.12, gap = size * 0.24, comma = size * 0.32;
    var w = -gap;
    for (final ch in s.split('')) {
      w += ch == ',' ? comma : dw + gap;
    }
    // (Seen from +z, its left is the frame's +x: laid out the other way.)
    final side = toward < 0 ? 1.0 : -1.0;
    var at = -w / 2;
    for (final ch in s.split('')) {
      if (ch == ',') {
        pglow(x + side * (at + comma * 0.3), y - size * 0.56, z, th, size * 0.22, 0.02, on);
        at += comma;
        continue;
      }
      final d = int.tryParse(ch), cx = x + side * (at + dw / 2);
      if (d != null) {
        final bits = segs[d];
        void bar(int b, double ox, double oy, bool across) {
          if (bits & (1 << b) == 0) return;
          pglow(cx + side * ox, y + oy, z, across ? dw * 0.8 : th, across ? th : size * 0.45, 0.02, on);
        }

        bar(0, 0, size / 2, true);
        bar(1, dw / 2 - th / 2, size / 4, false);
        bar(2, dw / 2 - th / 2, -size / 4, false);
        bar(3, 0, -size / 2, true);
        bar(4, -dw / 2 + th / 2, -size / 4, false);
        bar(5, -dw / 2 + th / 2, size / 4, false);
        bar(6, 0, 0, true);
      }
      at += dw + gap;
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// Where it goes (u, eye, target, fov): from the street, down the stair
  /// to ASCII's rack; back along the first row as Unicode 1.0 lights it;
  /// up over the racks for 6.0 and 18; to where they end, and out over
  /// the rest of the hall after its lights. (Each framed with what it
  /// shows right of the middle, clear of the talk's card on the left: the
  /// beat doesn't slide the camera aside for it, down here.)
  static final _keys = <(double, vm.Vector3, vm.Vector3, double)>[
    (0.0, vm.Vector3(2.0, 1.8, -13.0), vm.Vector3(0.6, 0.4, 0.0), 50),
    // Down the stair, slowly, into the dark; ASCII's rack lights up ahead.
    (3.8, vm.Vector3(2.0, 1.7, -6.2), vm.Vector3(1.4, -4.2, 6.0), 52),
    (5.5, vm.Vector3(2.0, -0.3, -1.4), vm.Vector3(1.2, _floor + 1.4, 19.0), 52),
    (8.0, vm.Vector3(2.0, -7.3, 9.5), vm.Vector3(0.4, _floor + 1.1, 23.8), 48),
    (10.2, vm.Vector3(1.9, _floor + 1.75, 18.4), vm.Vector3(-0.6, _floor + 1.05, 23.8), 46),
    // (Held on it, closing in, while the narration waits.)
    (14.2, vm.Vector3(2.1, _floor + 1.7, 19.6), vm.Vector3(-0.4, _floor + 1.05, 23.8), 44),
    (18.6, vm.Vector3(9.0, _floor + 3.4, 13.0), vm.Vector3(26.0, _floor + 2.4, 23.8), 54),
    (24.6, vm.Vector3(30.0, _floor + 12.4, 14.0), vm.Vector3(44.0, _floor + 3.5, 38.0), 56),
    (30.6, vm.Vector3(52.0, _floor + 12.2, 12.0), vm.Vector3(62.0, _floor + 2.5, 50.0), 58),
    // Over all of that to where it ends, the dark beyond; then, as the
    // rest of the hall's lights race away to the far wall, looking after
    // them; out over the empty racks.
    (35.6, vm.Vector3(70.0, _floor + 12.0, 22.0), vm.Vector3(68.0, _floor + 3.0, 62.0), 58),
    // (Back from the counter till it's done counting, and a moment on it.)
    (40.4, vm.Vector3(64.0, _floor + 11.8, 28.0), vm.Vector3(62.0, _floor + 2.5, 140.0), 60),
    (42.6, vm.Vector3(63.0, _floor + 11.8, 31.0), vm.Vector3(60.0, _floor + 1.5, 165.0), 62),
    (46.6, vm.Vector3(61.0, _floor + 11.8, 54.0), vm.Vector3(56.0, _floor + 1.5, 196.0), 62),
  ];

  @override
  Shot shot(double u) {
    // Straight from key to key, its corners rounded off by averaging over a
    // moment either side (a smooth way through: never past a key).
    const w = 0.75, n = 7;
    final eye = vm.Vector3.zero(), target = vm.Vector3.zero();
    var fov = 0.0;
    for (var i = 0; i < n; i++) {
      final (e, tg, f) = _along(u + w * (2 * i / (n - 1) - 1));
      eye.add(e);
      target.add(tg);
      fov += f;
    }
    return Shot(eye / n.toDouble(), target / n.toDouble(), fov: fov / n, settle: 0.5, drift: 0.25);
  }

  /// The way at [u], key to key in straight lines.
  static (vm.Vector3, vm.Vector3, double) _along(double u) {
    final ks = _keys;
    if (u <= ks.first.$1) return (ks.first.$2, ks.first.$3, ks.first.$4);
    var i = 0;
    while (i < ks.length - 2 && u >= ks[i + 1].$1) {
      i++;
    }
    final a = ks[i], b = ks[i + 1], f = seg(u, a.$1, b.$1);
    return (a.$2 + (b.$2 - a.$2) * f, a.$3 + (b.$3 - a.$3) * f, lerp(a.$4, b.$4, f));
  }

  // ── Down here (the sky asks) ──────────────────────────────────────────────

  late final _inverseFrame = vm.Matrix4.inverted(frame);
  final _q = vm.Vector3.zero();

  /// Whether the camera's below the street in here (as of last frame): the
  /// hall stays, and the camera may stay down, until it's out (the next
  /// beat's flight takes it up from where it was, through the ground).
  bool _down = false;

  /// How far [camera] (world) is underground in the hall (0 in the street
  /// … 1 down in it): the air goes dark as it goes down the stair. (Asked
  /// every frame.)
  double undergroundAt(vm.Vector3 camera) {
    final p = _inverseFrame.transform3(_q..setFrom(camera));
    final inside = p.x > _x0 - 1 && p.x < _x1 + 1 && p.z > _zFront - 12 && p.z < _zBack + 1;
    _down = (visited || _down) && inside && p.y < 0;
    if (!(visited || _down) || !inside) return 0;
    return smooth(0.6, -2.6, p.y);
  }

  /// Whether the camera at [eye] (world) may be below the ground: while the
  /// talk's down here (or the camera still is), within the hall (and the
  /// stair down to it).
  bool mayGoUnder(vm.Vector3 eye) {
    if (!(visited || _down)) return false;
    final p = _inverseFrame.transform3(_q..setFrom(eye));
    return p.x > _x0 && p.x < _x1 && p.z > _zFront && p.z < _zBack && p.y > _floor;
  }

  /// Where the opening in the street is (world: x0, z0, x1, z1): the city
  /// leaves its ground out there.
  static (double, double, double, double) get opening => Plan.archiveHole;
}
