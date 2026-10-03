import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart' show Crew3D;
import 'figure.dart';
import 'kit.dart';
import 'prop_pool.dart';
import 'shot.dart';
import 'site_fx.dart';
import 'site_plan.dart' show BuildPlan;

/// A small scene of its own somewhere in the city: one idea from the talk
/// acted out over and over (a code point asking font after font for its
/// glyph, a tram that breaks lines, letters welded into ligatures…). Built
/// once; posed every frame from the scene's clock, [loop] seconds a turn;
/// its people drawn with everyone else's. The camera comes by now and then
/// ([Vignettes]), from the start of a turn, for [visit] seconds.
///
/// It's built in its own frame ([frame]: x across, y up, −z towards where
/// it's seen from), with the helpers here: static parts into a [Batch],
/// moving ones each frame into its [pool], signs painted with the real text
/// stack, letters extruded from it, people.
abstract class Vignette {
  Vignette(this.kit);

  final VignetteKit kit;
  Scene get scene => kit.scene;

  /// One word: the camera's requests and the capture log use it.
  String get name;

  /// The caption: a kicker (Japanese · ENGLISH), the line, a note.
  String get kick;
  String get line;
  String get note;

  /// A turn's length (seconds), and how long the camera stays.
  double get loop;
  double get visit;

  /// Where it stands (local to world).
  vm.Matrix4 get frame;

  /// Whether the camera's visiting it now (set every frame).
  bool visited = false;

  Future<void> init();

  /// Poses it [u] seconds into a turn (scene time [t], [night] 0 day … 1).
  void pose(double u, double t, double night);

  /// The camera [u] seconds into a visit, in its own frame.
  Shot shot(double u);

  /// The runs of text it shapes (the web fetches the fonts first).
  List<(String, TextStyle)> get fontRuns => const [];

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Its nodes: what's only seen up close (shown while the camera's here
  /// or near), and what reads from afar too (a building's walls, a
  /// landmark).
  late final detail = Node(name: name), shell = Node(name: '$name shell');

  /// Small moving props (made by [makePool], centred on the scene).
  late final PropPool pool;

  void makePool({int boxes = 64, int cyls = 16, int glows = 32}) {
    pool = PropPool(scene, '$name props', home: frame.transform3(vm.Vector3(0, 0.5, 0)), maxBoxes: boxes, maxCyls: cyls, maxGlows: glows, parent: detail)
      ..init();
  }

  /// A point of its own frame in the world.
  vm.Vector3 world(double x, double y, double z) => frame.transform3(vm.Vector3(x, y, z));

  late final _inverse = vm.Matrix4.inverted(frame);

  /// A world point in its own frame (into [out]).
  vm.Vector3 local(vm.Vector3 w, vm.Vector3 out) => _inverse.transform3(out..setFrom(w));

  /// A building's shell with its ground floor open to the front (−z, its
  /// face on z = 0): the floor, back and side walls, the upper floors with
  /// rows of windows, a band over the opening, the roof — [w] wide, [d]
  /// deep, [h] tall, the opening [open] high (into [b]).
  void storefront(Batch b, {double w = 12, double d = 9.6, double h = 10, double open = 3.85, int wall = 0xD8D2C4, int trim = 0x2E6DA8}) {
    final m = pbr(rgb(1, 1, 1), roughness: 0.75);
    final glass = pbr(rgb(1, 1, 1), roughness: 0.15, metallic: 0.4);
    final wc = Vignette.c(wall);
    box(b, m, w, 0.2, d, 0, 0.1, d / 2, Vignette.c(0x9A968E));
    box(b, m, w, h, 0.3, 0, h / 2, d - 0.15, wc);
    for (final x in [-w / 2 + 0.15, w / 2 - 0.15]) {
      box(b, m, 0.3, h, d, x, h / 2, d / 2, wc);
    }
    box(b, m, w, h - open, 0.3, 0, (h + open) / 2, 0.15, wc);
    box(b, m, w + 0.2, 0.25, 0.4, 0, open, 0.1, Vignette.c(trim));
    for (var y = open + 1.0; y + 1.4 < h; y += 2.6) {
      for (var k = -((w / 2 - 1.2) / 1.3).floor(); k <= ((w / 2 - 1.2) / 1.3).floor(); k++) {
        box(b, glass, 0.95, 1.3, 0.05, k * 1.3, y + 0.65, -0.02, Vignette.c(0x9CC4E0));
      }
    }
    box(b, m, w + 0.4, 0.3, d + 0.4, 0, h + 0.1, d / 2, Vignette.c(0x5A6470));
  }

  /// [m] (its own frame) in the world.
  vm.Matrix4 place(vm.Matrix4 m) => frame * m;

  /// A box [w]×[h]×[d] at (x, y, z) of its frame into [b].
  void box(
    Batch b,
    Material mat,
    double w,
    double h,
    double d,
    double x,
    double y,
    double z,
    vm.Vector4 color, {
    double yaw = 0,
    double rotX = 0,
    double rotZ = 0,
  }) => b.add(mat, part(CuboidGeometry(vm.Vector3(w, h, d)), place(trs(vm.Vector3(x, y, z), rotY: yaw, rotX: rotX, rotZ: rotZ)), color));

  /// An upright cylinder of radius [r], [h] tall, centred at (x, y, z).
  void cylinder(
    Batch b,
    Material mat,
    double r,
    double h,
    double x,
    double y,
    double z,
    vm.Vector4 color, {
    int sides = 14,
    double rotX = 0,
    double rotZ = 0,
  }) => b.add(
    mat,
    part(CylinderGeometry(bottomRadius: r, topRadius: r, height: h, radialSegments: sides), place(trs(vm.Vector3(x, y, z), rotX: rotX, rotZ: rotZ)), color),
  );

  /// The prop pool's box, in its frame (turned by its frame's yaw too).
  void pbox(double x, double y, double z, double sx, double sy, double sz, vm.Vector4 c, {double yaw = 0, double pitch = 0, double roll = 0}) {
    final p = frame.transform3(_v..setValues(x, y, z));
    pool.box(p.x, p.y, p.z, sx, sy, sz, c, yaw: yaw + kit.yawOf(frame), pitch: pitch, roll: roll);
  }

  /// The prop pool's glowing box, in its frame.
  void pglow(double x, double y, double z, double sx, double sy, double sz, vm.Vector4 c, {double yaw = 0, double pitch = 0, double roll = 0}) {
    final p = frame.transform3(_v..setValues(x, y, z));
    pool.glow(p.x, p.y, p.z, sx, sy, sz, c, yaw: yaw + kit.yawOf(frame), pitch: pitch, roll: roll);
  }

  /// The prop pool's upright cylinder, in its frame.
  void pcyl(double x, double y, double z, double r, double h, vm.Vector4 c, {double pitch = 0, double roll = 0}) {
    final p = frame.transform3(_v..setValues(x, y, z));
    pool.cyl(p.x, p.y, p.z, r, h, c, yaw: kit.yawOf(frame), pitch: pitch, roll: roll);
  }

  final _v = vm.Vector3.zero();

  /// [s] (digits, spaces) as a lit seven-segment display centred at
  /// (x, y), at depth z, [size] high; a comma before digit [comma].
  void digits(String s, double x, double y, double z, {double size = 0.42, int? comma, vm.Vector4? color}) {
    const segs = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F];
    final h = size, dw = size * 0.95, th = size * 0.12, on = color ?? vm.Vector4(2.6, 1.3, 0.35, 1);
    final n = s.length;
    for (var i = 0; i < n; i++) {
      final d = int.tryParse(s[i]);
      final cx = x + (i - (n - 1) / 2) * (dw + size * 0.2) + (comma != null && i >= comma ? size * 0.14 : 0);
      if (comma != null && i == comma) pglow(cx - dw / 2 - size * 0.17, y - h * 0.56, z, th, size * 0.2, 0.02, on);
      if (d == null) continue;
      final bits = segs[d];
      void bar(int b, double ox, double oy, bool across) {
        if (bits & (1 << b) == 0) return;
        pglow(cx + ox, y + oy, z, across ? dw * 0.8 : th, across ? th : h * 0.45, 0.02, on);
      }

      bar(0, 0, h / 2, true);
      bar(1, dw / 2 - th / 2, h / 4, false);
      bar(2, dw / 2 - th / 2, -h / 4, false);
      bar(3, 0, -h / 2, true);
      bar(4, -dw / 2 + th / 2, -h / 4, false);
      bar(5, -dw / 2 + th / 2, h / 4, false);
      bar(6, 0, 0, true);
    }
  }

  /// A painted sign [w]×[h] m at [at] (its frame), [paint]ed on a canvas
  /// [px] wide, lit a little from inside ([glow]); with the [shell] if it
  /// reads from afar.
  Future<Node> sign(
    double w,
    double h,
    vm.Matrix4 at,
    void Function(Canvas c, Size s) paint, {
    int px = 640,
    double glow = 0.25,
    double thick = 0.04,
    bool shell = false,
  }) async {
    final tex = await paintedTexture(px, math.max(8, (px * h / w).round()), paint);
    final mat = PhysicallyBasedMaterial()
      ..baseColorTexture = tex
      ..metallicFactor = 0
      ..roughnessFactor = 0.7
      ..emissiveTexture = tex
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = glow;
    kit.signs.add(mat);
    final n = Node(
      name: '$name sign',
      mesh: Mesh(boardGeometry(w, h, thick: thick), mat),
      localTransform: place(at),
    )..castsShadows = false;
    (shell ? this.shell : detail).add(n);
    return n;
  }

  /// Letters, extruded with the real text stack ([unitsPerPx] metres a
  /// pixel of [style]), each its own node under the scene, hidden until
  /// placed with [put].
  Future<List<Glyph3D>> letters(List<(String, TextStyle)> texts, Material mat, {double unitsPerPx = 0.6 / 160, double depth = 0.1}) async {
    final solids = await extrudeTextsAt(texts, unitsPerPx: unitsPerPx, depth: depth);
    return [
      for (final s in solids)
        () {
          final n = Node(name: '$name letter', mesh: Mesh(glyphGeometry(s.mesh), mat))
            ..castsShadows = false
            ..visible = false;
          detail.add(n);
          return Glyph3D(s, n);
        }(),
    ];
  }

  final _m = vm.Matrix4.identity();

  /// Shows [g] with its middle at (x, y, z) of the frame, turned and
  /// scaled ([s] 0 hides it).
  void put(Glyph3D g, double x, double y, double z, {double s = 1, double yaw = 0, double pitch = 0, double roll = 0}) {
    if (s <= 0.001) {
      g.node.visible = false;
      return;
    }
    g.node.visible = true;
    // (Its ink's middle is what's placed: the mesh stands on its ink's
    // bottom.)
    final q = vm.Quaternion.euler(yaw, pitch, roll);
    final off = q.rotated(vm.Vector3(0, -g.height * s / 2, 0));
    _m.setFromTranslationRotationScale(vm.Vector3(x + off.x, y + off.y, z + off.z), q, vm.Vector3.all(s));
    g.node.localTransform = frame * _m;
  }

  /// Shows [g] set like text: its pen at x, its baseline at y (z: its
  /// middle), scaled [s] (0 hides it).
  void pen(Glyph3D g, double x, double y, double z, {double s = 1, double yaw = 0}) =>
      put(g, x + s * g.solid.ox, y + s * (g.solid.oy + g.height / 2), z, s: s, yaw: yaw);

  /// A person who looks like [look] (their number among the figures).
  int person(FigureLook look) => kit.figures.add(look);

  /// [p]'s place and facing (posed in the frame) turned into the world's:
  /// then [Crew3D.aim] can reach for world points, and [Figures.draw] draw
  /// it.
  void worldPose(FigurePose p) {
    frame.transform3(p.pos);
    p.yaw += kit.yawOf(frame);
  }

  /// Draws person [slot] as [p] posed in the frame.
  void draw(int slot, FigurePose p) {
    worldPose(p);
    kit.figures.draw(slot, p);
  }

  /// A plain sRGB colour as a linear one.
  static vm.Vector4 c(int rgb) => v4(hex3(rgb));

  /// Text painted centred in [box] on [canvas], shrunk to fit.
  static void text(Canvas canvas, String s, Rect box, double size, Color color, {String? lang, String? family, FontWeight weight = FontWeight.w800}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: family ?? BP.display,
          fontFamilyFallback: const [BP.arabic],
          fontSize: size,
          color: color,
          locale: lang == null ? null : Locale(lang),
          fontWeight: weight,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final k = tp.width > box.width * 0.94 ? box.width * 0.94 / tp.width : 1.0;
    canvas
      ..save()
      ..translate(box.center.dx, box.center.dy)
      ..scale(k);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    tp.dispose();
  }
}

/// An extruded glyph (or run) and its node.
class Glyph3D {
  Glyph3D(this.solid, this.node);
  final PlacedSolid solid;
  final Node node;

  /// Its ink's size (metres, at scale 1).
  double get width => solid.mesh.width;
  double get height => solid.mesh.height;
}

/// What the vignettes share: the scene, the effects, the people (and the
/// crew, for its arm-aiming), their signs' materials (lit at night).
class VignetteKit {
  VignetteKit(this.scene, this.fx, this.crew) : figures = Figures.of(scene);
  final Scene scene;
  final Fx3D fx;
  final Crew3D crew;
  final Figures figures;
  final signs = <PhysicallyBasedMaterial>[];

  /// Where the vignettes' people are this frame (world), for the crowd to
  /// walk round.
  final walkers = <vm.Vector3>[];

  /// The yaw of a frame (its −z's heading).
  double yawOf(vm.Matrix4 m) => math.atan2(m.storage[8], m.storage[10]);
}

class _Visit {
  _Visit(this.scene, this.a, this.e);
  final int scene;
  final double a, e;
}

/// The vignettes, and the camera's visits to them during a build (in free
/// stretches: clear of the kerning close-ups and the other scenes'
/// visits): one or two in a visitor's build; while the booth builds its
/// sample words with no one waiting, every other one is a tour of them
/// (three visits); the scenes take turns from one build to the next.
class Vignettes {
  Vignettes(Scene scene, Fx3D fx, Crew3D crew, List<Vignette> Function(VignetteKit kit) make) : kit = VignetteKit(scene, fx, crew) {
    all = make(kit);
  }

  final VignetteKit kit;
  late final List<Vignette> all;

  /// When the camera's on one during this build (for the other planners).
  final camWindows = <(double, double)>[];
  final _visits = <_Visit>[];
  bool _ready = false;

  Future<void> init() async {
    for (final v in all) {
      kit.scene
        ..add(v.detail)
        ..add(v.shell);
    }
    await Future.wait([for (final v in all) v.init()]);
    _ready = true;
  }

  /// The texts they shape, for the web's font warm-up.
  List<(String, TextStyle)> get fontRuns => [for (final v in all) ...v.fontRuns];

  /// Each scene's clock, unvisited: its own turn of its loop; after a
  /// visit, carrying on from where the visit left it (nobody jumps as the
  /// camera leaves).
  late final _phase = [for (var i = 0; i < all.length; i++) 7.3 * i];

  _Visit? _visitAt(double t) {
    for (final v in _visits) {
      if (t >= v.a && t < v.e) return v;
    }
    return null;
  }

  /// Poses them at [t] (each on its own turn; the one the camera's on,
  /// from the start of one); those far from the [camera] keep their last
  /// pose (a few pixels from there).
  void update(double t, double night, {vm.Vector3? camera}) {
    if (!_ready) return;
    kit.walkers.clear();
    final v = _visitAt(t), on = v == null ? null : (v.scene, v.a);
    for (final m in kit.signs) {
      m.emissiveStrength = 0.25 + 0.9 * smooth(0.2, 0.7, night);
    }
    for (final (i, v) in all.indexed) {
      final visited = on != null && on.$1 == i;
      if (visited) _phase[i] = -on.$2;
      // Its details only near the camera (each node is drawn in every
      // pass: a whole scene of them seen from across the city costs more
      // than it shows); posed a little further out.
      var d2 = 0.0;
      if (camera != null) {
        final o = v.frame.storage, dx = o[12] - camera.x, dz = o[14] - camera.z;
        d2 = dx * dx + dz * dz;
      }
      v
        ..visited = visited
        ..detail.visible = visited || d2 < 40 * 40;
      if (!visited && d2 > 75 * 75) continue;
      final u = visited ? t - on.$2 : (t + _phase[i]) % v.loop;
      v.pose(u, t, night);
    }
  }

  /// Plans this build's visits, in stretches the camera's free (clear of
  /// the filmed kerning steps and [busyCam]): one (two in a long build)
  /// half a minute apart for a visitor's name; on a tour (a [sample] word,
  /// no one waiting), as many as fit (three at most), a dozen seconds
  /// apart. The scenes take turns from one build to the next.
  void planFor(BuildPlan plan, {required List<(double, double)> busyCam, bool sample = false}) {
    _visits.clear();
    camWindows.clear();
    if (all.isEmpty) return;
    // Capture aid: --dart-define=BOOTH3D_VISIT=tofu@20,tram@40 visits those
    // scenes then, whatever else is on.
    const pinned = String.fromEnvironment('BOOTH3D_VISIT');
    if (pinned.isNotEmpty) {
      for (final v in pinned.split(',')) {
        final [n, at] = v.split('@');
        final k = all.indexWhere((s) => s.name == n), a = double.parse(at);
        if (k < 0) continue;
        _visits.add(_Visit(k, a, a + all[k].visit));
        camWindows.add((a, a + all[k].visit));
      }
      return;
    }
    final busy = [
      for (final st in plan.steps)
        if (st != null && st.filmed) (st.a - 2.0, st.e + 1.5),
      // (Back on the build a few seconds between visits: a shot, not a
      // glimpse.)
      for (final (a, e) in busyCam) (a - 3.5, e + 3.5),
    ];
    final want = sample ? 3 : (plan.len > 80 ? 2 : 1), end = plan.t0 + plan.len - 2.0;
    var from = plan.t0 + (sample ? 12.0 : 22.0);
    for (var n = 0; n < want; n++) {
      final k = (plan.job.serial * 3 + n) % all.length, len = all[k].visit;
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
      _visits.add(_Visit(k, a, a + len));
      camWindows.add((a, a + len));
      from = a + len + (sample ? 12 : 30);
    }
  }

  /// The visits, for the capture log.
  String describe() => '\nPLAN vignettes ${[for (final v in _visits) '${all[v.scene].name} ${v.a.toStringAsFixed(1)}–${v.e.toStringAsFixed(1)}'].join(', ')}';

  /// The camera's request at [t] (priority 2): the scene visited, from the
  /// start of its turn.
  void focus(List<Focus> out, double t) {
    if (!_ready || out.any((f) => f.priority >= 2)) return;
    final on = _visitAt(t);
    if (on == null) return;
    final v = all[on.scene];
    final s = v.shot(t - on.a);
    out.add(
      Focus(
        'vignette ${v.name} ${on.a.toStringAsFixed(1)}',
        Shot(v.frame.transform3(s.eye.clone()), v.frame.transform3(s.target.clone()), fov: s.fov, settle: s.settle, drift: s.drift),
        priority: 2,
      ),
    );
  }

  /// The caption for [shot] (a vignette's request), or null.
  ({String kick, String line, String note, String topic})? captionFor(String shot) {
    if (!shot.startsWith('vignette ')) return null;
    final parts = shot.split(' ');
    for (final v in all) {
      if (v.name == parts[1]) return (kick: v.kick, line: v.line, note: v.note, topic: 'vignette ${v.name} ${parts.last}');
    }
    return null;
  }
}
