import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/craft/extrude.dart' show GlyphMesh;
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// 文字の挨拶 · The talk's bookends: "Text" in eight scripts round its
/// title, and "Thank you" in the same eight round its last words. Solid
/// words hung in the air in front of the camera, each its own colour, set
/// round the middle of the frame (where the title is) and turned to face
/// it; they come in one by one as the camera arrives (down out of the sky
/// for the title; over the avenue for the thanks, the fireworks behind),
/// drift while the presenter talks, and fly off as the talk moves on.
/// Only in a talk.
class TalkScripts extends Vignette {
  TalkScripts(super.kit);

  @override
  String get name => 'scripts';
  @override
  String get kick => '文字 · ONE WORD, EIGHT SCRIPTS';
  @override
  String get line => _text.join(' · ');
  @override
  String get note => 'and thank you, in the same eight';

  @override
  bool get talkOnly => true;

  /// (The talk holds its camera within a visit: both turns.)
  @override
  double get loop => 200;
  @override
  double get visit => 200;

  /// Set in the world itself (the words are placed for the cameras).
  @override
  final frame = vm.Matrix4.identity();

  static const _text = ['Text', 'نص', 'टेक्स्ट', '文字', 'טקסט', 'ข้อความ', '텍스트', 'Текст'];
  static const _thanks = ['Thank you', 'شكرًا', 'धन्यवाद', 'ありがとう', 'תודה', 'ขอบคุณ', '감사합니다', 'Спасибо'];
  static const _langs = [null, null, null, 'ja', null, null, 'ko', null];

  /// Each script's colour (the same in both sets).
  static const _colors = [0x2F6BFF, 0x10B981, 0xF59E0B, 0xEC4899, 0x8B5CF6, 0x06B6D4, 0xEF4444, 0xF97316];

  /// The turns: the title's from 0, held at [_hold1]; the thanks' from
  /// [_from2], held at [_hold2]; each gone a little after its hold.
  static const _hold1 = 10.0, _end1 = 12.5, _from2 = 100.0, _hold2 = 110.0, _end2 = 112.5;

  /// The framings the words are set for (the talk's title and thanks
  /// shots), and where each word stands in its frame: across and up (−1…1
  /// of the half frame), how far (m), and how tall its em is (of the
  /// frame's height). Round the middle, where the title is; the thanks'
  /// above the street.
  static final _titleShot = Shot(vm.Vector3(0, 26, -50), vm.Vector3(0, 12, 55), fov: 52, settle: 1.0, drift: 0.6);
  static final _thanksShot = Shot(vm.Vector3(0, 7, -30), vm.Vector3(0, 14, 6), fov: 56, settle: 1.0, drift: 0.5);
  static const _titleSlots = [
    (-0.62, 0.55, 22.0, 0.13),
    (0.64, 0.58, 26.0, 0.14),
    (-0.78, 0.0, 20.0, 0.11),
    (0.78, 0.06, 18.0, 0.13),
    (-0.58, -0.55, 18.0, 0.12),
    (0.58, -0.52, 20.0, 0.11),
    (-0.08, 0.8, 30.0, 0.1),
    (0.14, -0.8, 16.0, 0.1),
  ];
  static const _thanksSlots = [
    (-0.6, 0.6, 18.0, 0.09),
    (0.62, 0.62, 17.0, 0.11),
    (-0.72, 0.2, 15.0, 0.085),
    (0.68, 0.24, 15.0, 0.08),
    (-0.6, -0.12, 14.0, 0.1),
    (0.6, -0.1, 14.0, 0.09),
    (-0.22, 0.84, 26.0, 0.075),
    (0.26, 0.86, 24.0, 0.075),
  ];

  static const _px = 160.0, _depth = 0.18;

  final _title = <_Word>[], _thank = <_Word>[];
  int _act = 0;
  bool _ready = false;

  static TextStyle _style(String? lang) => TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: const [BP.arabic],
    fontSize: _px,
    locale: lang == null ? null : Locale(lang),
    fontWeight: FontWeight.w700,
    fontVariations: const [FontVariation('wght', 700)],
  );

  @override
  List<(String, TextStyle)> get fontRuns => [
    for (var i = 0; i < _text.length; i++) ('${_text[i]} ${_thanks[i]}', _style(_langs[i]).copyWith(fontSize: 40)),
  ];

  @override
  Future<void> init() async {
    final metal = pbr(Vignette.c(0xC9D1DC), metallic: 0.85, roughness: 0.3);
    final faces = [
      for (final c in _colors) pbr(Vignette.c(c), roughness: 0.36, metallic: 0.05, emissive: Vignette.c(c), emissiveStrength: 0.16),
    ];
    final solids = await extrudeTextsAt([
      for (final set in [_text, _thanks])
        for (var i = 0; i < set.length; i++) (set[i], _style(_langs[i])),
    ], unitsPerPx: 1 / _px, depth: _depth);
    for (var i = 0; i < _text.length; i++) {
      _title.add(_Word(_node(solids[i].mesh, faces[i], metal), solids[i].mesh, _titleShot, _titleSlots[i]));
      _thank.add(_Word(_node(solids[_text.length + i].mesh, faces[i], metal), solids[_text.length + i].mesh, _thanksShot, _thanksSlots[i]));
    }
    _ready = true;
  }

  /// A word's node: its faces in its colour, its sides in metal.
  Node _node(GlyphMesh m, Material face, Material side) {
    final f = <int>[], s = <int>[];
    for (var t = 0; t + 2 < m.indices.length; t += 3) {
      final v = m.indices[t];
      (m.normals[v * 3 + 2].abs() > 0.5 ? f : s).addAll([m.indices[t], m.indices[t + 1], m.indices[t + 2]]);
    }
    MeshGeometry geometry(List<int> idx) => MeshGeometry.fromArrays(positions: m.positions, normals: m.normals, texCoords: m.uvs, indices: idx);
    final n = Node(
      name: 'talk script word',
      mesh: Mesh.primitives(primitives: [MeshPrimitive(geometry(f), face), MeshPrimitive(geometry(s), side)]),
    )..visible = false;
    detail.add(n);
    return n;
  }

  // ── Posing ────────────────────────────────────────────────────────────────

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    if (visited) _act = u < 50 ? 1 : 2;
    final title = _act == 1 && u < _end1, thanks = _act == 2 && u >= _from2 && u < _end2;
    _turn(_title, u, t, 0, _hold1, title);
    _turn(_thank, u, t, _from2, _hold2, thanks);
  }

  final _m = vm.Matrix4.identity(), _spin = vm.Matrix4.identity();

  void _turn(List<_Word> words, double u, double t, double from, double hold, bool on) {
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final a = from + 0.5 + 0.32 * i;
      final k = seg(u, a, a + 1.9), out = seg(u, hold + 0.06 * i, hold + 0.06 * i + 1.1);
      if (!on || k <= 0 || out >= 1) {
        w.node.visible = false;
        continue;
      }
      // In from far behind it, turned and small; out, up and away; a slow
      // drift between.
      final e = eo(k), o = eio(out);
      final bob = 0.05 * w.em * math.sin(t * 0.9 + i * 1.3);
      final p = w.at + w.back * (18 * (1 - e) + 12 * o) + vm.Vector3(0, 4 * (1 - e) + 10 * o + bob, 0);
      final s = w.em * (0.55 + 0.45 * e) * (1 - 0.6 * o);
      _spin.setRotationY(0.9 * (1 - e) + 0.07 * math.sin(t * 0.6 + i * 2.1));
      _m
        ..setFrom(w.facing)
        ..setTranslation(p);
      w.node
        ..visible = true
        ..localTransform = _m * _spin * vm.Matrix4.diagonal3Values(s, s, s) * vm.Matrix4.translation(vm.Vector3(0, -w.height / 2, 0));
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  @override
  Shot shot(double u) {
    // Easing in to the framing the words are set for.
    final s = u < 50 ? _titleShot : _thanksShot;
    final k = eo(seg(u, u < 50 ? 0 : _from2, (u < 50 ? 0 : _from2) + 14));
    final back = (s.eye - s.target).normalized();
    return Shot(s.eye + back * (u < 50 ? 12 : 4) * (1 - k) + vm.Vector3(0, (u < 50 ? 5 : 1) * (1 - k), 0), s.target, fov: s.fov, settle: s.settle, drift: s.drift);
  }
}

/// A word, where it stands (the middle of its ink) and how it's turned to
/// face its camera; away from it ([back]); its em (m) and ink height (em).
class _Word {
  _Word(this.node, GlyphMesh mesh, Shot shot, (double, double, double, double) slot) : height = mesh.height {
    final (x, y, d, size) = slot;
    final f = (shot.target - shot.eye).normalized();
    final right = vm.Vector3(0, 1, 0).cross(f).normalized(), up = f.cross(right);
    final ty = math.tan(shot.fov * math.pi / 360), tx = ty * 16 / 9;
    at = shot.eye + f * d + right * (x * d * tx) + up * (y * d * ty);
    em = size * 2 * d * ty;
    // Its back (local +z) away from the camera, upright.
    back = (at - shot.eye).normalized();
    final across = vm.Vector3(0, 1, 0).cross(back).normalized(), upright = back.cross(across);
    facing = vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(across.x, across.y, across.z, 0))
      ..setColumn(1, vm.Vector4(upright.x, upright.y, upright.z, 0))
      ..setColumn(2, vm.Vector4(back.x, back.y, back.z, 0));
  }

  final Node node;
  final double height;
  late final vm.Vector3 at, back;
  late final double em;
  late final vm.Matrix4 facing;
}
