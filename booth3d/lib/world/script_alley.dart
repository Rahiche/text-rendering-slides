import 'dart:math' as math;
import 'dart:ui' show Color, FontVariation, FontWeight, Locale, Paint, PaintingStyle, Rect;

import 'package:flutter/painting.dart' show Canvas, Offset, TextAlign, TextDirection, TextPainter, TextSelection, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'kit.dart';
import 'shot.dart';
import 'site_fx.dart';
import 'site_geo.dart';
import 'site_plan.dart';

/// One of the alley's stalls: the rule its script breaks (the talk's
/// "Every script breaks a rule"), on its sign in Japanese and English, the
/// script, its colour (the slides'), and what the caption says about it.
class AlleyRule {
  const AlleyRule(this.ja, this.en, this.script, this.color, this.note);
  final String ja, en, script;
  final Color color;
  final String note;
}

const alleyRules = [
  AlleyRule('右から左', 'Right-to-left', 'HEBREW', BP.coral, 'שלום — written from the right'),
  AlleyRule('つながる', 'Joining', 'ARABIC', BP.amber, 'ب ي ت → بيت — each letter takes a shape for its neighbours'),
  AlleyRule('並べ替え', 'Reordering', 'DEVANAGARI', BP.violet, 'क + ि → कि — typed after, drawn before'),
  AlleyRule('積み重ね', 'Stacking', 'THAI', BP.pink, 'ป + ั + ่ → ปั่ — marks stack on the letter'),
  AlleyRule('組み立て', 'Composition', 'HANGUL', Color(0xFF7FE0FF), 'ㅎ + ㅏ + ㄴ → 한 — one syllable, one block'),
  AlleyRule('縦書き', 'Vertical', 'JAPANESE', Color(0xFF9FF0D6), 'top to bottom — not built into Flutter'),
];

/// Where the alley is: the park's long path, past its cross path; three
/// stalls on each side, facing the path (local −z is a stall's front).
abstract final class AlleyLayout {
  static const rowX = 5.7;
  static const rowZ = [29.5, 34.5, 39.5];

  /// The gate over the path at the alley's start.
  static const gateZ = 26.2, gateX = 3.0;

  /// Stall [i]'s front middle, on the ground, and the turn that faces it
  /// to the path.
  static vm.Vector3 at(int i) => vm.Vector3(i < 3 ? -rowX : rowX, 0, rowZ[i % 3]);
  static double yaw(int i) => i < 3 ? -math.pi / 2 : math.pi / 2;

  /// Stall [i]'s frame (local to world).
  static vm.Matrix4 frame(int i) => trs(at(i), rotY: yaw(i));

  /// A point in stall [i]'s frame, in the world.
  static vm.Vector3 toWorld(int i, vm.Vector3 local) {
    final c = math.cos(yaw(i)), s = math.sin(yaw(i)), o = at(i);
    return vm.Vector3(o.x + c * local.x + s * local.z, o.y + local.y, o.z - s * local.x + c * local.z);
  }

  /// Where stall [i]'s keeper stands (behind the counter), and which way
  /// they face (heading: local +x towards the path, as the crowd's).
  static vm.Vector3 keeper(int i) => toWorld(i, vm.Vector3(0.15, 0, 0.72));
  static double keeperHeading(int i) => i < 3 ? 0 : math.pi;

  /// The counter's top, where the letters stand (stall frame).
  static const stageY = 0.98, stageZ = -0.1;
}

/// A text piece on a counter: its solid and its node.
class _Piece {
  _Piece(this.solid, this.node);
  final PlacedSolid solid;
  final Node node;

  double get advance => solid.advance;
  double get width => solid.mesh.width;
  double get height => solid.mesh.height;
}

/// One stall's letters and where they go.
class _Demo {
  final pieces = <_Piece>[];

  /// Pen positions (x, stage frame) worked out from the real layout.
  final x = <double>[];
  Node? frame;
}

class _Visit {
  _Visit(this.stall, this.a, this.e, this.gate);
  final int stall;
  final double a, e;

  /// Starting on the gate (the alley's first visit in a build).
  final bool gate;

  /// When the stall's loop starts (so the camera sees it from the start).
  double get start => a + (gate ? 2.2 : 0.3);
}

/// 文字横丁 · Script Alley: festival stalls (屋台) along the park's long path,
/// one for each rule from the talk's "Every script breaks a rule" —
/// right-to-left, joining, reordering, stacking, composition, vertical.
/// Each stall shows its rule with big letters on its counter, over and
/// over: they come, the rule happens to them (they slide, hop, drop, are
/// pressed together…), the result holds, they go. Lanterns light up at
/// dusk; a keeper minds each stall. Now and then during a build the camera
/// visits one (the gate first), from the start of its loop; the stalls
/// take turns from one name to the next.
class ScriptAlley {
  ScriptAlley(this.scene, this.fx);

  final Scene scene;
  final Fx3D fx;

  /// When the camera's here during this build (for the other planners).
  final camWindows = <(double, double)>[];
  final _visits = <_Visit>[];

  final _demos = List.generate(6, (_) => _Demo());
  final _glyphMats = <PhysicallyBasedMaterial>[];
  late final PhysicallyBasedMaterial _lanterns;
  bool _ready = false;

  /// A stall's loop (seconds), and when in it the letters go.
  static const _period = 8.4, _out = 7.7;

  /// The stalls' letters and signs per script, for the web's font warm-up
  /// (the world fetches every fallback font it draws with at once).
  static List<(String, TextStyle)> get fontRuns => [
    ('שלום ← بيت ب ي ت क ि कि ป น ั ่ ปั่น', _style(null)),
    ('ㅎ ㅏ ㄴ 한', _style('ko')),
    ('縦書き 文字横丁 右から左 つながる 並べ替え 積み重ね 組み立て', _style('ja')),
  ];

  Future<void> init() async {
    _lanterns = pbr(lin(const Color(0xFFFF5A3C)), roughness: 0.6, emissive: lin(const Color(0xFFFF7A45)), emissiveStrength: 0.6);
    _buildStalls();
    await Future.wait([_buildSigns(), _buildLetters()]);
    _ready = true;
  }

  // ── The stalls ────────────────────────────────────────────────────────────

  void _buildStalls() {
    final batch = Batch();
    final timber = pbr(rgb(1, 1, 1), roughness: 0.8);
    final wood = v4(hex3(0xB98A5A)), dark = v4(hex3(0x2E2A2A)), post = v4(hex3(0x5B3B2A)), white = v4(hex3(0xF4F1EA));
    final vermilion = v4(hex3(0xC8442F)), cord = v4(hex3(0x1C1F26));
    for (var i = 0; i < 6; i++) {
      final m = AlleyLayout.frame(i);
      final c = lin(alleyRules[i].color);
      void box(double w, double h, double d, double x, double y, double z, vm.Vector4 col, {double rotX = 0}) =>
          batch.add(timber, part(CuboidGeometry(vm.Vector3(w, h, d)), m * trs(vm.Vector3(x, y, z), rotX: rotX), col));
      // The counter, its top, a band of the stall's colour.
      box(2.4, 0.92, 0.62, 0, 0.46, 0, dark);
      box(2.56, 0.06, 0.8, 0, 0.95, -0.02, wood);
      box(2.42, 0.22, 0.02, 0, 0.72, -0.32, c);
      // Posts, the back wall, the sides.
      for (final x in [-1.22, 1.22]) {
        box(0.09, 2.5, 0.09, x, 1.25, -0.36, post);
        box(0.09, 2.5, 0.09, x, 1.25, 1.02, post);
        box(0.04, 0.9, 1.3, x, 0.45, 0.35, dark);
      }
      box(2.4, 1.6, 0.05, 0, 1.75, 1.06, v4(lin3(alleyRules[i].color, 0.32)));
      // The roof: stripes of the stall's colour and white, down to the front.
      for (var k = 0; k < 5; k++) {
        box(0.56, 0.07, 1.75, -1.12 + 0.56 * k, 2.5, 0.33, k.isEven ? c : white, rotX: -0.14);
      }
      // The lanterns' cords and caps (the lit paper is its own mesh).
      for (final x in [-0.98, 0.98]) {
        box(0.015, 0.2, 0.015, x, 2.3, -0.5, cord);
        box(0.2, 0.04, 0.2, x, 2.2, -0.5, cord);
        box(0.2, 0.04, 0.2, x, 1.82, -0.5, cord);
      }
      // The vertical stall's board, on its counter.
      if (i == 5) box(0.52, 1.36, 0.05, 0, AlleyLayout.stageY + 0.68, AlleyLayout.stageZ + 0.2, dark);
    }
    // The gate: two vermilion posts and a beam over the path.
    for (final x in [-AlleyLayout.gateX, AlleyLayout.gateX]) {
      batch.add(timber, part(CuboidGeometry(vm.Vector3(0.18, 3.7, 0.18)), trs(vm.Vector3(x, 1.85, AlleyLayout.gateZ)), vermilion));
    }
    batch.add(timber, part(CuboidGeometry(vm.Vector3(6.7, 0.2, 0.24)), trs(vm.Vector3(0, 3.62, AlleyLayout.gateZ)), vermilion));
    // Strings of lanterns across the path between the stalls.
    final paper = CylinderGeometry(bottomRadius: 0.16, topRadius: 0.16, height: 0.34, radialSegments: 12);
    final small = CylinderGeometry(bottomRadius: 0.11, topRadius: 0.11, height: 0.24, radialSegments: 10);
    for (var i = 0; i < 6; i++) {
      for (final x in [-0.98, 0.98]) {
        batch.add(_lanterns, part(paper, AlleyLayout.frame(i) * trs(vm.Vector3(x, 2.01, -0.5)), v4(lin3(const Color(0xFFFFFFFF)))));
      }
    }
    for (final z in [32.0, 37.0]) {
      batch.add(timber, part(CuboidGeometry(vm.Vector3(2 * AlleyLayout.rowX - 2.2, 0.02, 0.02)), trs(vm.Vector3(0, 3.0, z)), cord));
      for (var k = 0; k < 7; k++) {
        final x = -2.7 + 0.9 * k;
        batch.add(
          _lanterns,
          part(
            small,
            trs(vm.Vector3(x, 2.8 - 0.12 * math.cos((k - 3) / 3 * math.pi / 2), z)),
            v4(lin3(k.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFFFE3B0))),
          ),
        );
      }
    }
    batch.build(scene, 'script alley', castsShadows: false, lightChannelMask: 0x01);
  }

  /// The stalls' signs (their rule in Japanese and English, the script) and
  /// the gate's: 文字横丁 · SCRIPT ALLEY.
  Future<void> _buildSigns() async {
    Future<void> sign(String ja, String en, Color bg, Color ink, double w, double h, vm.Matrix4 at) async {
      final tex = await paintedTexture(640, (640 * h / w).round(), (c, s) {
        c.drawRect(Offset.zero & s, Paint()..color = bg);
        c.drawRect(
          (Offset.zero & s).deflate(8),
          Paint()
            ..color = ink.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
        _text(c, ja, Rect.fromLTWH(0, s.height * 0.08, s.width, s.height * 0.58), s.height * 0.44, ink, 'ja');
        _text(c, en, Rect.fromLTWH(0, s.height * 0.62, s.width, s.height * 0.3), s.height * 0.2, ink, null);
      });
      final mat = PhysicallyBasedMaterial()
        ..baseColorTexture = tex
        ..metallicFactor = 0
        ..roughnessFactor = 0.7
        ..emissiveTexture = tex
        ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
        ..emissiveStrength = 0.25;
      _signMats.add(mat);
      scene.add(Node(name: 'alley sign', mesh: Mesh(boardGeometry(w, h, thick: 0.04), mat), localTransform: at)..castsShadows = false);
    }

    await Future.wait([
      for (var i = 0; i < 6; i++)
        sign(
          alleyRules[i].ja,
          '${alleyRules[i].en.toUpperCase()} · ${alleyRules[i].script}',
          alleyRules[i].color,
          const Color(0xFF14203A),
          2.3,
          0.56,
          AlleyLayout.frame(i) * vm.Matrix4.translation(vm.Vector3(0, 2.86, -0.66)),
        ),
      sign(
        '文字横丁',
        'SCRIPT ALLEY · EVERY SCRIPT BREAKS A RULE',
        const Color(0xFFF4EBD8),
        const Color(0xFF8E2A1E),
        4.6,
        0.8,
        vm.Matrix4.translation(vm.Vector3(0, 3.05, AlleyLayout.gateZ - 0.14)),
      ),
    ]);
  }

  final _signMats = <PhysicallyBasedMaterial>[];

  void _text(Canvas c, String s, Rect box, double size, Color color, String? lang) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: BP.display,
          fontSize: size,
          color: color,
          locale: lang == null ? null : Locale(lang),
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 760)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final k = tp.width > box.width * 0.92 ? box.width * 0.92 / tp.width : 1.0;
    c
      ..save()
      ..translate(box.center.dx, box.center.dy)
      ..scale(k);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }

  // ── The letters ───────────────────────────────────────────────────────────

  static TextStyle _style(String? lang) => TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: const [BP.arabic],
    fontSize: 160,
    height: 1.15,
    locale: lang == null ? null : Locale(lang),
    fontWeight: FontWeight.w700,
    fontVariations: const [FontVariation('wght', 700)],
  );

  /// Each stall's pieces: the letters alone, and what they make.
  static const _texts = [
    ['ש', 'ל', 'ו', 'ם', '←'],
    ['ب', 'ي', 'ت', 'بيت'],
    ['क', 'ि', 'कि'],
    ['ป', 'น', 'ั', '่', 'ปั่น'],
    ['ㅎ', 'ㅏ', 'ㄴ', '한'],
    ['縦', '書', 'き'],
  ];
  static const _langs = [null, null, null, null, 'ko', 'ja'];

  Future<void> _buildLetters() async {
    const u = 0.62 / 160, uSmall = 0.34 / 160;
    final solids = await Future.wait([
      for (var i = 0; i < 6; i++) extrudeTextsAt([for (final s in _texts[i]) (s, _style(_langs[i]))], unitsPerPx: i == 5 ? uSmall : u, depth: 0.1),
    ]);
    for (var i = 0; i < 6; i++) {
      final mat = pbr(lin(alleyRules[i].color), roughness: 0.42, emissive: lin(alleyRules[i].color), emissiveStrength: 0.12);
      _glyphMats.add(mat);
      final root = Node(
        name: 'alley stall $i',
        localTransform: AlleyLayout.frame(i) * vm.Matrix4.translation(vm.Vector3(0, AlleyLayout.stageY, AlleyLayout.stageZ)),
      );
      scene.add(root);
      final d = _demos[i];
      for (final s in solids[i]) {
        final n = Node(name: 'alley letter', mesh: Mesh(glyphGeometry(s.mesh), mat))
          ..castsShadows = false
          ..visible = false;
        root.add(n);
        d.pieces.add(_Piece(s, n));
      }
      if (i == 4) {
        // The syllable's square, round where 한 stands.
        final h = d.pieces[3];
        final side = math.max(h.width, h.height) * 1.22, t = 0.035;
        final frame = merged([
          for (final (x, y, w, hh) in [(0.0, side, side + t, t), (0.0, 0.0, side + t, t), (-side / 2, side / 2, t, side), (side / 2, side / 2, t, side)])
            part(CuboidGeometry(vm.Vector3(w, hh, 0.05)), vm.Matrix4.translation(vm.Vector3(x, y, 0.04)), v4(lin3(alleyRules[i].color))),
        ]);
        root.add(
          d.frame = Node(name: 'alley block', mesh: Mesh(frame, mat))
            ..castsShadows = false
            ..visible = false,
        );
      }
    }
    // Where the letters stand in the words they make (the real layout).
    _layout(0, 'שלום', 4);
    _layout(1, 'بيت', 3);
    _layout(3, 'ปั่น', 4);
  }

  /// Pen positions (stage x, the word centred) of the first [n] characters
  /// of [word], as stall [i]'s pieces lay out in it.
  void _layout(int i, String word, int n) {
    const u = 0.62 / 160;
    final tp = TextPainter(
      text: TextSpan(text: word, style: _style(_langs[i])),
      textDirection: TextDirection.ltr,
    )..layout();
    final half = tp.width / 2;
    final d = _demos[i];
    for (var k = 0; k < word.length && d.x.length < n; k++) {
      final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: k, extentOffset: k + 1));
      d.x.add(boxes.isEmpty ? 0 : (boxes.first.left - half) * u);
    }
    tp.dispose();
  }

  // ── Every frame ───────────────────────────────────────────────────────────

  /// Poses every stall at [t]; lanterns and letters glow after dusk.
  void update(double t, double night) {
    final on = smooth(0.12, 0.5, night);
    _lanterns.emissiveStrength = 0.6 + 7 * on;
    for (final m in _signMats) {
      m.emissiveStrength = 0.25 + 0.6 * on;
    }
    if (!_ready) return;
    for (final m in _glyphMats) {
      m.emissiveStrength = 0.12 + 1.3 * on;
    }
    for (var i = 0; i < 6; i++) {
      _pose(i, _loopAt(i, t));
    }
  }

  /// Where stall [i] is in its loop at [t]: a talk's (from when it called
  /// on it, held once it's done), or from a visit's start while the
  /// camera's there, else on its own clock.
  double _loopAt(int i, double t) {
    if (_played case (final k, final at) when k == i) {
      _playedU = (t - at).clamp(0.0, _done);
      _playedT = t;
      return _playedU;
    }
    for (final v in _visits) {
      if (v.stall == i && t >= v.a - 1.0 && t < v.e + 0.5) return t - v.start;
    }
    return (t + _phase[i]) % _period;
  }

  /// Each stall's own clock (out of step with the others).
  final _phase = [for (var i = 0; i < 6; i++) 1.37 * i];

  /// Every stall's letters are done by now, and held until the loop's end.
  static const _done = 7.2;

  /// The stall a talk's on, and when it called on it; where it got to.
  (int, double)? _played;
  double _playedU = 0, _playedT = 0;

  /// Plays stall [i] from the start at [at] (scene time), its outcome held
  /// until [release]d (a talk's call, talk/).
  void play(int i, double at) => _played = (i, at);

  /// Lets the stall a talk had go on round from where it is.
  void release() {
    if (_played case (final k, _)) _phase[k] = _playedU - _playedT;
    _played = null;
  }

  static double _back(double x) {
    const c1 = 1.70158, c3 = c1 + 1;
    final y = x - 1;
    return 1 + c3 * y * y * y + c1 * y * y;
  }

  /// [p]'s mesh at (x, y) in the stage, scale [s]; hidden at 0.
  static void _put(_Piece p, double x, double y, double s, {double z = 0}) {
    p.node.visible = s > 0.002;
    if (!p.node.visible) return;
    p.node.place((m) => setTrs(m, x, y, z, s: s));
  }

  /// [p] with its pen at (x, baseline y).
  static void _pen(_Piece p, double x, double y, double s) => _put(p, x + s * p.solid.ox, y + s * p.solid.oy, s);

  /// [p] with its ink centred on (x, y).
  static (double, double) _inkAt(_Piece p, double x, double y, double s) => (x, y - s * p.height / 2);

  /// A puff where letters come together (stage point of stall [i]).
  void _puff(int i, double x, double y, double age, int seed) {
    final w = AlleyLayout.toWorld(i, vm.Vector3(x, AlleyLayout.stageY + y, AlleyLayout.stageZ - 0.1));
    fx.puff(w.x, w.y, w.z, age, 0.35, seed: seed, n: 3);
  }

  void _pose(int i, double u) {
    final d = _demos[i], ps = d.pieces;
    if (ps.isEmpty) return;
    final out = 1 - seg(u, _out, _out + 0.45);
    double pop(double at) => u < at ? 0 : _back(seg(u, at, at + 0.32)) * out;
    switch (i) {
      case 0:
        // שלום letter by letter, from the right; the pen's arrow going left.
        if (d.x.length < 4) return;
        for (var k = 0; k < 4; k++) {
          _pen(ps[k], d.x[k], 0, pop(0.6 + 0.55 * k));
        }
        final right = d.x[0] + ps[0].advance, left = d.x[3];
        final arrow = ps[4];
        final f = eio(seg(u, 0.35, 2.55));
        final as = 0.6 * seg(u, 0.25, 0.45) * (1 - seg(u, 2.8, 3.1)) * out;
        _pen(arrow, lerp(right + 0.08, left - 0.12 - arrow.advance * 0.6, f), 0.66, as);
      case 1:
        // ب ي ت alone and apart (right to left), sliding together; then
        // they're one word, each letter in the shape that joins it.
        if (d.x.length < 3) return;
        final joined = u >= 3.0;
        final slide = eio(seg(u, 1.7, 2.9));
        const apart = [0.62, 0.0, -0.62];
        for (var k = 0; k < 3; k++) {
          final x0 = apart[k] - ps[k].advance / 2;
          _pen(ps[k], lerp(x0, d.x[k], slide), 0, joined ? 0 : pop(0.4 + 0.4 * k));
        }
        final word = ps[3];
        _pen(word, -word.advance / 2, 0, joined ? _back(seg(u, 3.0, 3.35)) * out : 0);
        _puff(i, 0, 0.2, (u - 3.0) / 0.8, 11);
      case 2:
        // क, then ि typed after it — which hops over to be drawn before it;
        // then they're one cluster, कि.
        final ka = ps[0], ii = ps[1], word = ps[2];
        final merged = u >= 3.2;
        _pen(ka, -0.25 - ka.advance / 2, 0, merged ? 0 : pop(0.4));
        final hop = eio(seg(u, 1.9, 3.0));
        final x0 = 0.5 - ii.advance / 2, x1 = -0.25 - ka.advance / 2 - ii.advance * 0.8;
        _pen(ii, lerp(x0, x1, hop), 0.5 * math.sin(math.pi * hop), merged ? 0 : pop(1.0));
        _pen(word, -word.advance / 2, 0, merged ? _back(seg(u, 3.2, 3.55)) * out : 0);
        _puff(i, -0.2, 0.25, (u - 3.2) / 0.8, 12);
      case 3:
        // ป and น; the marks ั and ่ (each on its placeholder circle) come
        // down onto ป, one over the other; then the cluster as the font
        // stacks it.
        if (d.x.length < 4) return;
        final merged = u >= 3.3;
        final base = ps[0], last = ps[1], word = ps[4];
        _pen(base, d.x[0], 0, merged ? 0 : pop(0.4));
        _pen(last, d.x[3], 0, merged ? 0 : pop(0.7));
        double drop(double a) {
          final f = seg(u, a, a + 0.38);
          return f < 1 ? (1 - f * f) : 0.06 * math.sin(math.pi * seg(u, a + 0.38, a + 0.6));
        }

        _pen(ps[2], d.x[0], 0.8 * drop(1.9), merged ? 0 : pop(1.2));
        _pen(ps[3], d.x[0], 1.15 * drop(2.5), merged ? 0 : pop(1.5));
        _pen(word, -word.advance / 2, 0, merged ? _back(seg(u, 3.3, 3.65)) * out : 0);
        _puff(i, -0.15, 0.35, (u - 3.3) / 0.8, 13);
      case 4:
        // ㅎ ㅏ ㄴ in a row; drawn into one square, smaller; then 한.
        final h = ps[3];
        final merged = u >= 3.2;
        final f = eio(seg(u, 1.7, 2.9));
        final cx = 0.0, y0 = 0.02, w = h.width, hh = h.height;
        const row = [-0.62, 0.0, 0.62];
        final spots = [(cx - 0.22 * w, y0 + 0.74 * hh), (cx + 0.28 * w, y0 + 0.6 * hh), (cx - 0.04 * w, y0 + 0.2 * hh)];
        for (var k = 0; k < 3; k++) {
          final p = ps[k];
          final s = merged ? 0.0 : pop(0.4 + 0.3 * k) * lerp(1, 0.5, f);
          final (ax, ay) = _inkAt(p, row[k], p.height / 2 + 0.02, s);
          final (bx, by) = _inkAt(p, spots[k].$1, spots[k].$2, s);
          _put(p, lerp(ax, bx, f), lerp(ay, by, f), s);
        }
        _put(h, cx, y0, merged ? _back(seg(u, 3.2, 3.55)) * out : 0);
        final frame = d.frame;
        if (frame != null) {
          final s = (u < 1.6 ? 0 : _back(seg(u, 1.6, 1.95))) * out;
          frame.visible = s > 0.002;
          frame.place((m) => setTrs(m, cx, y0 - 0.1 * hh, 0, s: s));
        }
        _puff(i, 0, 0.3, (u - 3.2) / 0.8, 14);
      default:
        // 縦, 書, き dropping into the vertical board, top to bottom.
        const slots = [1.08, 0.68, 0.28];
        for (var k = 0; k < 3; k++) {
          final p = ps[k];
          final a = 0.5 + 0.6 * k;
          final fall = seg(u, a, a + 0.42);
          final y = slots[k] + (fall < 1 ? 1.3 * (1 - fall * fall) : 0.05 * math.sin(math.pi * seg(u, a + 0.42, a + 0.62)));
          final s = (u < a ? 0.0 : 1.0) * out;
          final (x, yy) = _inkAt(p, 0, y, s);
          _put(p, x, yy, s, z: -0.03);
        }
    }
  }

  // ── The camera ────────────────────────────────────────────────────────────

  /// Plans this build's visits: one (two in a long build), each in a
  /// stretch the camera's free (clear of the kerning close-ups and [busyCam],
  /// the delivery's and the works' shots), half a minute apart. The first
  /// starts on the gate; the stalls take turns from one name to the next.
  void planFor(BuildPlan plan, {required List<(double, double)> busyCam}) {
    _visits.clear();
    camWindows.clear();
    final busy = [
      for (final st in plan.steps)
        if (st != null && st.filmed) (st.a - 2.0, st.e + 1.5),
      for (final (a, e) in busyCam) (a - 3.5, e + 3.5),
    ];
    final want = plan.len > 90 ? 2 : 1, end = plan.t0 + plan.len - 2.0;
    var from = plan.t0 + 14.0;
    for (var n = 0; n < want; n++) {
      final gate = n == 0, len = gate ? 9.6 : 7.8;
      var a = from;
      for (var moved = true; moved;) {
        moved = false;
        for (final (x, y) in busy) {
          if (a < y && a + len > x) {
            a = y;
            moved = true;
          }
        }
      }
      if (a + len > end) break;
      _visits.add(_Visit((plan.job.serial * 2 + n) % 6, a, a + len, gate));
      camWindows.add((a, a + len));
      from = a + len + 30;
    }
  }

  /// The visits, for the capture log.
  String describe() => '\nPLAN alley ${[for (final v in _visits) '${alleyRules[v.stall].en} ${v.a.toStringAsFixed(1)}–${v.e.toStringAsFixed(1)}'].join(', ')}';

  /// The stall visited from [a] (as its focus names it), or null.
  int? stallAt(String a) {
    for (final v in _visits) {
      if (v.a.toStringAsFixed(1) == a) return v.stall;
    }
    return null;
  }

  /// The camera's request at [t] (priority 2): the gate and the stalls
  /// beyond it for a moment, then in on the stall, pushing in slowly as its
  /// letters do their thing.
  void focus(List<Focus> out, double t) {
    if (!_ready || out.any((f) => f.priority >= 2)) return;
    for (final v in _visits) {
      if (t < v.a || t >= v.e) continue;
      final u = t - v.a, id = v.a.toStringAsFixed(1);
      if (v.gate && u < 2.2) {
        out.add(
          Focus(
            'alley gate $id',
            Shot(vm.Vector3(0.9, 2.2, AlleyLayout.gateZ - 3.4), vm.Vector3(-0.3, 2.0, 35.5), fov: 52, settle: 0.8, drift: 0.6),
            priority: 2,
          ),
        );
        return;
      }
      final k = seg(u, v.gate ? 2.2 : 0, v.e - v.a);
      final eye = AlleyLayout.toWorld(v.stall, vm.Vector3(0.85, 1.72, lerp(-4.4, -3.7, k)));
      final tg = AlleyLayout.toWorld(v.stall, vm.Vector3(0.05, 1.42, -0.1));
      out.add(Focus('alley ${v.stall} $id', Shot(eye, tg, fov: 40, settle: 1.0, drift: 0.4), priority: 2));
      return;
    }
  }
}
