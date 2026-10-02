import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show PictureRecorder;
import 'dart:ui' show Color, FontWeight, FontVariation, Locale, Paint, PaintingStyle, RRect, Radius, Rect;

import 'package:flutter/painting.dart' show Canvas, Offset, TextAlign, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/raster.dart';
import 'package:text_slides/booth/web_fonts.dart';
import 'package:text_slides/deck/font_data.dart';
import 'package:text_slides/deck/theme.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'crew.dart';
import 'crew_breaks.dart' show OffDuty;
import 'kit.dart';
import 'prop_pool.dart';
import 'shot.dart';
import 'site_fx.dart';
import 'site_geo.dart';
import 'site_plan.dart';
import 'walk.dart';
import 'works_name.dart';

/// Where the Glyph Works stands (world units): the plaza's left-rear corner,
/// behind the smoking corner, open to the front (−z, the sun's side).
/// Inside, the text pipeline runs along a belt at the back, left to right
/// as the name reads from the front; the pixel board stands at the front
/// right.
abstract final class WorksLayout {
  static const x0 = -16.65, x1 = -8.45, z0 = 4.6, z1 = 7.75;
  static const cx = (x0 + x1) / 2;

  /// The roof, and the top of the open front (the sign board above it).
  static const roof = 3.0, open = 2.45;

  /// The belt: its ends, its middle line, its top and its width.
  static const beltX0 = -16.4, beltX1 = -10.2, beltZ = 6.25, beltY = 0.6, beltW = 0.46;

  /// Where each step of the pipeline works on a letter, along the belt:
  /// the feeder (UTF-8), the decoder, the font cases, the composing stick
  /// (shaping), the wire bender (outline), the rasterizer.
  static const stepX = [-16.05, -15.15, -14.15, -12.94, -11.8, -10.8];

  /// Where a maker stands to work each step (behind the belt, facing out;
  /// beside the bender and the rasterizer, at their crank and controls),
  /// and the lane behind for walking back.
  static const workX = [-16.05, -15.15, -14.15, -12.94, -11.3, -10.3];
  static const workZ = 6.8, laneZ = 7.3;

  /// The walkway past the belt's right end, from the back to the front.
  static const walkX = -9.7;

  /// The pixel board on its stand at the front right: the middle of its
  /// bottom edge, and how far it leans back (radians). A maker sets pixels
  /// on it from behind it ([placeZ]).
  static const boardX = -9.85, boardY = 0.62, boardZ = 5.12, boardTilt = 0.5, placeZ = 5.8;

  /// Where the makers wait for their next letter (behind the feeder).
  static final homes = [vm.Vector3(-16.2, 0, 7.12), vm.Vector3(-15.62, 0, 7.32), vm.Vector3(-15.05, 0, 7.12)];

  /// The way out of the front, past the board's left (for whoever leaves
  /// on foot).
  static final exit = [vm.Vector3(-10.7, 0, placeZ), vm.Vector3(-10.7, 0, z0 - 0.35)];

  /// A way through the works from [from] to [to], both on the floor: along
  /// the lane behind the belt and the walkway past its end, never through
  /// the line.
  static List<vm.Vector3> route(vm.Vector3 from, vm.Vector3 to) {
    bool back(vm.Vector3 v) => v.z > beltZ + 0.3 && v.x < beltX1 + 0.2;
    final pts = [from.clone()];
    if (back(from) && back(to)) {
      pts.addAll([vm.Vector3(from.x, 0, laneZ), vm.Vector3(to.x, 0, laneZ)]);
    } else if (back(from)) {
      pts.addAll([vm.Vector3(from.x, 0, laneZ), vm.Vector3(walkX, 0, laneZ), vm.Vector3(walkX, 0, placeZ), vm.Vector3(to.x, 0, placeZ)]);
    } else if (back(to)) {
      pts.addAll([vm.Vector3(from.x, 0, placeZ), vm.Vector3(walkX, 0, placeZ), vm.Vector3(walkX, 0, laneZ), vm.Vector3(to.x, 0, laneZ)]);
    } else {
      pts.addAll([vm.Vector3(from.x, 0, placeZ), vm.Vector3(to.x, 0, placeZ)]);
    }
    pts.add(to.clone());
    final out = <vm.Vector3>[];
    for (final p in pts) {
      if (out.isEmpty || out.last.distanceTo(p) > 1e-3) out.add(p);
    }
    return out;
  }
}

/// What the works needs of one of the name's smooth letters (made by the site
/// for the reveal). The site still hands them over every frame; the
/// pipeline makes its own glyphs from the text stack ([WorksName]), so they
/// go unused.
class LetterShape {
  LetterShape({
    required this.glyph,
    required this.geometry,
    required this.bands,
    required this.bandTops,
    required this.at,
    required this.width,
    required this.height,
    required this.depth,
  });
  final int glyph;
  final Geometry geometry;
  final List<Geometry> bands;
  final List<double> bandTops;
  final vm.Vector3 at;
  final double width, height, depth;
}

/// The pipeline's steps as the signs and the caption name them.
const worksSteps = [
  ('文字列', 'UTF-8 BYTES'),
  ('デコード', 'DECODE'),
  ('フォント', 'FONT · CMAP'),
  ('シェーピング', 'SHAPING'),
  ('アウトライン', 'OUTLINE'),
  ('ラスタライズ', 'RASTERIZE'),
  ('画面', 'PIXELS'),
];

/// What the works' caption (the 2D overlay's lower third, during a camera
/// visit) shows, refreshed every frame: the step being looked at and its
/// real values for the letter going through it.
class WorksCaption {
  /// 0 hidden … 1 fully in.
  double show = 0;

  /// The step (0 the bytes … 6 the pixels), the letter, its values (e.g.
  /// 'E3 82 88  →  U+3088') and a note under them.
  int step = -1;
  String letter = '', value = '', note = '';

  /// At the font step: the fonts looked in so far, and whether each had it.
  List<(String, bool)> fonts = const [];

  /// Whether the camera's following this letter all the way down the line.
  bool journey = false;
}

/// 文字工場 · Glyph Works: while the crew build the name in bricks, the works
/// runs it through the text pipeline, letter by letter in step with the
/// wall, onto a pixel board. Each letter goes down the line on the belt, a
/// maker with it, and changes form at every step:
///
/// 1. 文字列 · UTF-8: its bytes come out of the feeder as crates, one per
///    byte (`utf8.encode`: K is 4B, よ is E3 82 88); the whole string's
///    bytes are on the board above, the letter's lit up.
/// 2. デコード · decode: the crates go into the decoder (a lamp per byte read)
///    and the code point comes out as a tile, U+3088 (a grapheme of several
///    code points comes out as a cluster of tiles).
/// 3. フォント · font: the tile is looked up in the font cases in the name
///    style's order, Space Grotesk, Noto Kufi Arabic, then the system's
///    fallback, by their real cmaps: a red ✕ where there's no glyph, a
///    green ✓ where there is, and the glyph comes out of that case as a
///    type sort, its body as wide as its advance.
/// 4. シェーピング · shaping: the sort is set in the composing stick after
///    the letter before, at the pen; the advance lights up on the ruler and
///    the kerning nudges it (both measured with the text stack, as the wall's
///    kerning step). The stick keeps the line shaped so far.
/// 5. アウトライン · outline: the wire bender bends the glyph's outline in
///    wire, traced from the glyph as the text stack draws it, at the size
///    the works renders (16 px, smaller for a long name).
/// 6. ラスタライズ · rasterize: the wire is laid on a pixel grid and the
///    print head runs it scanline by scanline; each pixel takes the glyph's
///    real coverage there (painted alone at its place in the line by the
///    text stack): solid inside, grey on the anti-aliased edges.
/// 7. 画面 · pixels: the maker carries the pixels to the board — the
///    framebuffer — and sets them in at the letter's shaped place; letter by
///    letter the name appears, pixel for pixel as the text stack draws it.
///
/// Letters overlap on the line (one being shaped while the next is
/// decoded); each step takes one letter at a time. The board is done as the
/// wall is, and the finale (photo_op.dart) carries it to the site ([held]).
/// Now and then the camera cuts over, a step at a time in pipeline order
/// across the build, and a caption gives the step's real values ([caption]).
///
/// The building and its machines are two merged meshes over one painted
/// atlas; each name's labels, glyph faces and string are painted once into
/// an atlas of its own; the pixels are instanced tiles; the moving parts
/// come from the site's [PropPool]. Everything is a pure function of scene
/// time, planned once per build.
class GlyphWorks {
  GlyphWorks(this.scene, this.crew, this.fx, this.props);

  final Scene scene;
  final Crew3D crew;
  final Fx3D fx;
  final PropPool props;

  PhysicallyBasedMaterial? _mat;
  late final PhysicallyBasedMaterial _wireMat;
  late final UnlitMaterial _pixelMat;
  FontData? _latin, _arabic;

  /// What the 2D caption shows this frame (set by [focus]).
  final caption = WorksCaption();

  /// Where the pixel board is this frame when it's not on its stand (the
  /// finale carries it): the middle of its bottom edge, its turn (yaw, as a
  /// figure's) and how far it leans back. Set before [update]; cleared by it.
  ({vm.Vector3 at, double yaw, double tilt})? held;

  /// Makers the finale poses this frame (bit i: maker i); [update] leaves them.
  int finaleMakers = 0;

  /// When the camera cuts over to the works (the breaks keep clear).
  final camWindows = <(double, double)>[];

  /// The name's data and its atlas being prepared (capture waits on it).
  Future<void>? pending;

  // The pixels: the plate the rasterizer fills (one letter at a time) and
  // the board they're set in (the whole name).
  late final InstancedMesh _platePixels, _boardPixels;
  final _plateNode = Node(name: 'works plate pixels'), _boardNode = Node(name: 'works board pixels');
  final _boardRoot = Node(name: 'works board'), _boardFrame = Node(name: 'works board frame');
  final _stick = Node(name: 'works stick'), _strip = Node(name: 'works string'), _display = Node(name: 'works decoder display');

  void init() {
    _wireMat = pbr(lin(const Color(0xFFE8A04A)), metallic: 0.75, roughness: 0.32, emissive: lin(const Color(0xFFFFB347)), emissiveStrength: 0.35);
    _pixelMat = UnlitMaterial();
    _platePixels = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: _pixelMat);
    _boardPixels = InstancedMesh(geometry: CuboidGeometry(vm.Vector3.all(1)), material: _pixelMat);
    _plateNode
      ..addComponent(InstancedMeshComponent(_platePixels))
      ..castsShadows = false
      ..visible = false;
    _boardNode
      ..addComponent(InstancedMeshComponent(_boardPixels))
      ..castsShadows = false;
    _boardRoot
      ..add(_boardFrame..castsShadows = false)
      ..add(_boardNode)
      ..visible = false;
    for (final n in [_stick, _strip, _display]) {
      n
        ..castsShadows = false
        ..visible = false;
    }
    _display.localTransform = trs(vm.Vector3(-15.15, WorksLayout.beltY + 0.19, WorksLayout.beltZ - 0.282));
    scene
      ..add(_plateNode)
      ..add(_boardRoot)
      ..add(_stick)
      ..add(_strip)
      ..add(_display);
    FontData.spaceGrotesk().then((f) => _latin = f);
    FontData.notoKufiArabic().then((f) => _arabic = f);
    _build();
  }

  // ── Per build ─────────────────────────────────────────────────────────────

  BuildPlan? _plan;
  WorksName? _name;
  _Job? _job;
  final _steps = <_Steps>[];
  final _cuts = <_Cut>[];

  /// The one letter the camera follows through all seven steps (see
  /// [_planJourney]), or null.
  _Journey? _journey;

  /// When the last letter's pixels are on the board (null before a plan).
  double? get boardDone => _steps.isEmpty ? null : _steps.last.at[7];

  /// The board's width and height (the finale's carriers hold its sides).
  double get boardWidth => _job?.boardW ?? 1.2;
  double get boardHeight => _job?.boardH ?? 0.4;

  /// When maker [i] is free after their last letter, and where they are
  /// then (at home, or behind the board if theirs was the last letter).
  double freeAt(int i) => _freeOf(i).t;
  vm.Vector3 freeSpot(int i) => _freeOf(i).at;

  ({double t, vm.Vector3 at}) _freeOf(int i) {
    _Steps? last;
    for (final s in _steps) {
      if (s.maker == i) last = s;
    }
    if (last == null) return (t: double.negativeInfinity, at: WorksLayout.homes[i]);
    if (identical(last, _steps.last)) return (t: last.at[7] + 0.3, at: vm.Vector3(_slotX(last.k), 0, WorksLayout.placeZ));
    return (t: last.homeAt, at: WorksLayout.homes[i]);
  }

  /// Each step's share of a letter's way down the line.
  static const _share = [0.08, 0.12, 0.18, 0.14, 0.13, 0.16, 0.19];

  /// From home to the feeder, and (about) from the board back home.
  static const _walkIn = 1.0, _walkHome = 6.2;

  /// Plans the build's letters down the line and the camera's visits (once,
  /// when its plan is ready), keeping clear of [busyCam] (the deliveries'
  /// shots) and the kerning close-ups.
  void planFor(BuildPlan plan, {List<(double, double)> busyCam = const []}) {
    _clear();
    _plan = plan;
    final name = _name = WorksName.measure(plan.job.name, plan.letters, latin: _latin, arabic: _arabic);
    _planJourney(plan, busyCam, name);
    _schedule(plan, const {});
    _planCuts(plan, busyCam, name);
    final job = _job = _Job(name);
    pending = _prepare(plan, name, job);
    if (const String.fromEnvironment('BOOTH3D_TIMES') == '') return;
    String f(double v) => v.toStringAsFixed(1);
    for (final s in _steps) {
      final l = name.letters[s.k];
      // ignore: avoid_print
      print(
        'PLAN works ${l.text} maker ${s.maker}: ${[for (var i = 0; i < 7; i++) '${worksSteps[i].$2.split(' ').first.toLowerCase()} ${f(s.at[i])}'].join(', ')}, on the board ${f(s.at[7])}',
      );
    }
    for (final c in _cuts) {
      // ignore: avoid_print
      print('PLAN works cut ${f(c.from)}-${f(c.to)} ${worksSteps[c.step].$2} ${name.letters[c.k].text}');
    }
    if (_journey case final jn?) {
      // ignore: avoid_print
      print('PLAN works journey ${name.letters[jn.k].text}: ${[for (final (a, e, _) in jn.stretches) '${f(a)}-${f(e)}'].join(', ')}');
    }
  }

  /// The name's atlas, its letters' pixels and outlines; then their meshes.
  Future<void> _prepare(BuildPlan plan, WorksName name, _Job job) async {
    await awaitFallbackFonts(name.name, style: NameRaster.nameStyle(40));
    if (_latin == null || _arabic == null) {
      _latin ??= await FontData.spaceGrotesk();
      _arabic ??= await FontData.notoKufiArabic();
    }
    name.lookUp(_latin, _arabic);
    final atlas = job.atlas = _Atlas(name);
    final tex = await _texture(_Atlas.size, _Atlas.size, atlas.paint);
    if (!identical(_job, job)) return;
    job.mat = PhysicallyBasedMaterial()
      ..baseColorTexture = tex
      ..emissiveTexture = tex
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.1
      ..metallicFactor = 0.1
      ..roughnessFactor = 0.55;
    await name.render();
    if (!identical(_job, job)) return;
    pending = null;
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      // ignore: avoid_print
      print('PLAN ${name.describe()}');
    }
  }

  void _clear() {
    _job?.dispose();
    _job = null;
    _name = null;
    _plan = null;
    _steps.clear();
    _cuts.clear();
    _journey = null;
    camWindows.clear();
    pending = null;
    _plateK = -1;
    _plateShown = 0;
    _plateHome = false;
    _boardPlaced = false;
    _boardWas = null;
    _boardLanded = -1;
    _stickSet = -1;
    _displayK = -1;
    _platePixels.clearInstances();
    _boardPixels.clearInstances();
    _boardFrame.mesh = null;
    _stick.mesh = null;
    _strip.mesh = null;
    _display.mesh = null;
  }

  /// Each letter down the line: its way from the feeder to the board takes
  /// a little under twice its big letter's turn (laying and kerning), and
  /// ends as the big letter's does, so the mini letter lands as the wall's
  /// is kerned into place, and the next letter is on the line before it
  /// lands. A step takes one letter at a time (and the plate one letter
  /// from the rasterizer to the board), and a maker one letter: a letter
  /// waits for whichever is busy, at the step it's done. A letter [pins]
  /// for the camera (its step, when) sets off early enough and waits for
  /// it. All of it a little faster when the last letter would land after
  /// the build.
  void _schedule(BuildPlan plan, Map<int, (int, double)> pins) {
    final sc = plan.sched, n = plan.letterCount;
    final deadline = plan.t0 + plan.len - 0.25, first = plan.job.startedAt + 1.5;
    var squeeze = 1.0;
    for (var tries = 0; tries < 14; tries++) {
      _steps.clear();
      final free = List.filled(7, -1e9);
      final makers = List.filled(3, -1e9);
      var plate = -1e9;
      for (var k = 0; k < n; k++) {
        final s = _Steps(k, k % 3);
        if (_journey case final jn? when jn.k == k) {
          // Followed all the way: its own times, the others behind it.
          for (var i = 0; i < 7; i++) {
            s
              ..at[i] = jn.at[i]
              ..end[i] = jn.end[i];
            if (i > 0) free[i - 1] = jn.at[i] + 0.3;
          }
          s.at[7] = jn.at[7];
          free[6] = jn.at[7] + 0.3;
          plate = jn.at[7];
          s
            ..walkIn = s.at[0] - _walkIn
            ..homeAt = jn.at[7] + 0.3 + _walkHome;
          makers[s.maker] = s.homeAt;
          _steps.add(s);
          continue;
        }
        final a = plan.at(sc.layA[k]), d = plan.at(sc.downB[k]);
        final len = (1.8 * (d - a)).clamp(12.0, 32.0) * squeeze;
        final ready = math.max(first, makers[s.maker] + _walkIn + 0.3);
        var t = math.max(d - len, ready);
        final pin = pins[k];
        if (pin != null) {
          var lead = 0.0;
          for (var i = 0; i < pin.$1; i++) {
            lead += _share[i] * len;
          }
          t = math.max(ready, math.min(t, pin.$2 - lead));
        }
        for (var i = 0; i < 7; i++) {
          t = math.max(t, free[i]);
          if (i == 5) t = math.max(t, plate);
          if (pin != null && i == pin.$1) t = math.max(t, pin.$2);
          s.at[i] = t;
          if (i > 0) free[i - 1] = t + 0.3;
          t += _share[i] * len;
          s.end[i] = t;
        }
        s.at[7] = t;
        free[6] = t + 0.3;
        plate = t;
        s
          ..walkIn = s.at[0] - _walkIn
          ..homeAt = t + 0.3 + _walkHome;
        makers[s.maker] = s.homeAt;
        _steps.add(s);
      }
      if (_steps.isEmpty || _steps.last.at[7] <= deadline) break;
      squeeze *= 0.9;
    }
  }

  // ── The camera's visits ───────────────────────────────────────────────────

  /// Picks the moments to cut over: 7.5 s (at least 5.5) at a time, every
  /// half a minute or so, never near a kerning close-up or the deliveries'
  /// shots; each comes for a step, in pipeline order across the build (a
  /// short build: decoding, shaping, rasterizing; a long one every step),
  /// so the visits follow the whole journey. The letter whose step comes
  /// nearest is pinned to the visit (it waits for the camera, or sets off a
  /// little sooner) and the line planned again. A visit opens on the whole
  /// works (the board shows how far the name has come), then moves in on
  /// the step and follows the letter.
  void _planCuts(BuildPlan plan, List<(double, double)> busyCam, WorksName name) {
    _cuts.clear();
    camWindows.clear();
    final s = plan.job.serial;
    // (A kerning close-up eases in from 0.7–1.1 s before its step and out
    // by 0.6 s after.)
    final journey = _journey;
    final busy = [
      for (final st in plan.steps)
        if (st != null && st.filmed) (st.a - 1.5, st.e + 1.0),
      for (final (a, e) in busyCam) (a - 2.0, e + 2.0),
      if (journey != null)
        for (final (a, e, _) in journey.stretches) (a - 2.0, e + 2.0),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    // (After a journey, the next visit only half a minute after it.)
    final first = journey == null ? plan.t0 + 12 : math.max(plan.t0 + 12, journey.at[7] + 25), last = plan.t0 + plan.len - 1.0;
    // The gaps between them.
    final gaps = <(double, double)>[];
    var from = first;
    for (final (a, e) in busy) {
      if (a > from) gaps.add((from, math.min(a, last)));
      from = math.max(from, e);
    }
    if (last > from) gaps.add((from, last));
    if (const String.fromEnvironment('BOOTH3D_TIMES') != '') {
      // ignore: avoid_print
      print('PLAN works free for visits: ${gaps.map((g) => '${g.$1.toStringAsFixed(1)}–${g.$2.toStringAsFixed(1)}').join(', ')}');
    }
    // The steps to show, in order, for about as many visits as there's time
    // for: the rasterizer always; with two, the shaping (the kerning) for a
    // name in the name's own font, the fallback for one in a script it
    // hasn't (Japanese: nothing kerns there); with three, the decoder
    // first. (Before the fonts' cmaps are in, anything past Latin is taken
    // to fall back.)
    final fallback = name.letters.any((l) => l.fonts.isEmpty ? l.codePoints.any((c) => c > 0x2FF) : l.font > 0);
    // (After the journey, one or two more at most.)
    final room = math.min(((last - first) / 38).floor() + 1, journey == null ? 99 : 2);
    final want = switch (room) {
      <= 1 => const [5],
      2 => fallback ? const [2, 5] : const [3, 5],
      3 => fallback ? const [1, 2, 5] : const [1, 3, 5],
      4 => const [1, 2, 3, 5],
      5 => const [1, 2, 3, 4, 5],
      _ => const [1, 2, 3, 4, 5, 6],
    };
    final natural = [for (final st in _steps) Float64List.fromList(st.at)];
    final pins = <int, (int, double)>{};
    final picks = <(_Cut, (double, double))>[];
    // The letter whose step [x] comes nearest [at]: a little early (it
    // waits, up to a third of its way down the line, if it still lands
    // before the build ends), else a little late (it sets off sooner). A
    // visit for the decoder comes as the bytes leave the feeder, to see
    // both.
    final deadline = plan.t0 + plan.len - 0.5;
    int? letterFor(int x, double at) {
      int? best;
      var cost = double.infinity;
      for (var k = 0; k < natural.length; k++) {
        if (pins.containsKey(k) || k == journey?.k) continue;
        final turn = natural[k][7] - natural[k][0], dt = at - natural[k][x == 1 ? 0 : x];
        if (natural[k][7] + math.max(0.0, dt) > deadline) continue;
        final c = dt >= 0 ? (dt <= 0.35 * turn ? dt : double.infinity) : (-dt <= 0.3 * turn ? -1.6 * dt : double.infinity);
        if (c < cost) {
          cost = c;
          best = k;
        }
      }
      return best;
    }

    // A visit about [next] (somewhere between half a minute and
    // three-quarters of one after the last began), [earliest] at the
    // soonest: the step wanted next (after the rasterizer, from the start
    // again) in the first gap that has it, up to 20 s past [next]; else
    // the nearest step further down the line, in the first gap that has
    // one.
    var next = first + 6 * rnd(s, 61), earliest = first;
    var done = 0;
    // Long enough to see the step through (the bytes out and decoded; the
    // lookups up to the case that has the glyph; the scan…): 6–9 s.
    (int, int, double, double, (double, double))? find(List<int> steps, double until) {
      for (final g in gaps) {
        final a0 = math.max(earliest, g.$1);
        final starts = [for (var a = a0; a + 5.5 <= g.$2 + 1e-6 && a <= until; a += 0.5) a]..sort((x, y) => (x - next).abs().compareTo((y - next).abs()));
        for (final x in steps) {
          for (final a in starts) {
            final k = letterFor(x, a + _lead);
            if (k == null) continue;
            final n = natural[k];
            final need = switch (x) {
              1 => 0.75 * (n[2] - n[0]),
              // (To the case that has the glyph, and the glyph out of it.)
              2 => _catchAt(n[3] - n[2], name.letters[k].font) + 0.4,
              _ => 0.85 * (n[x + 1] - n[x]),
            };
            final e = math.min(a + (_lead + need + 1.0).clamp(6.0, 9.0), g.$2);
            if (e - a - _lead >= need - 1e-6) return (x, k, a, e, g);
          }
        }
      }
      return null;
    }

    var raster = false;
    while (true) {
      // (The last visit there's time for comes for the rasterizer, if none
      // has yet.)
      final goal = next + 27 > last - 6 && !raster ? 5 : want.firstWhere((w) => w > done, orElse: () => want.first);
      final from = goal == want.first ? 0 : done;
      final pick = find([goal], next + 20) ?? find([for (var x = from + 1; x <= 6; x++) x], double.infinity);
      if (pick == null) break;
      final (x, k, a, e, g) = pick;
      final step = x == 1 ? 0 : x;
      pins[k] = (step, a + _lead);
      picks.add((_Cut(a, e, step, k), g));
      done = x >= 5 ? 0 : x;
      raster |= x >= 5;
      earliest = a + 27;
      next = a + 30 + 14 * rnd(picks.length, s, 62);
    }
    _schedule(plan, pins);
    // Where a pinned step was held up (by the letter before), the visit
    // follows it, if it still fits its gap.
    for (final (c, g) in picks) {
      final at = _steps[c.k].at[c.step];
      var a = c.from, e = c.to;
      if ((at - (a + _lead)).abs() > 0.25) {
        a = at - _lead;
        e = math.min(a + (c.to - c.from), g.$2);
        if (a < g.$1 - 1e-6 || e - a < 5.5 - 1e-6) continue;
      }
      _cuts.add(_Cut(a, e, c.step, c.k));
      camWindows.add((a, e));
    }
    if (journey != null) {
      for (final (a, e, _) in journey.stretches) {
        camWindows.add((a, e));
      }
      camWindows.sort((x, y) => x.$1.compareTo(y.$1));
    }
  }

  /// Seconds on each step while the camera follows a letter all the way:
  /// the bytes out of the feeder, the decoder, the font cases (a second more
  /// to fall back), the stick, the bender, the rasterizer, the walk to the
  /// board.
  static const _dwell = [3.2, 3.6, 4.2, 4.0, 4.2, 4.6, 4.0];

  /// The longest the camera stays with the letter in one go, and how long
  /// it's away on the site in between.
  static const _stretch = 12.0, _away = 5.0;

  /// One letter's whole life in the works, followed by the camera: the
  /// first letter (its big one goes up first), from the moment the camera's
  /// free once the build is under way (after the delivery's shot), step by
  /// step at [_dwell] each. A kerning close-up (or another shot) takes the
  /// camera away, and so does the site every [_stretch] seconds or so: the
  /// letter waits at the end of its step, and the camera comes back for the
  /// next. Faster, down to 60 %, if it wouldn't land before the build ends;
  /// none if it still wouldn't.
  void _planJourney(BuildPlan plan, List<(double, double)> busyCam, WorksName name) {
    _journey = null;
    if (name.letters.isEmpty) return;
    const k = 0;
    final l = name.letters[k];
    // (Before the fonts' cmaps are in, anything past Latin is taken to fall
    // back.)
    final fallback = l.fonts.isEmpty ? l.codePoints.any((c) => c > 0x2FF) : l.font > 0;
    final busy = [
      for (final st in plan.steps)
        if (st != null && st.filmed) (st.a - 1.0, st.e + 0.6),
      for (final (a, e) in busyCam) (a - 0.3, e + 0.3),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    // The first moment ≥ [t] with [len] seconds free of them.
    double clear(double t, double len) {
      var x = t;
      for (var moved = true; moved;) {
        moved = false;
        for (final (a, e) in busy) {
          if (x < e && x + len > a) {
            x = e;
            moved = true;
          }
        }
      }
      return x;
    }

    final deadline = plan.t0 + plan.len - 1.0;
    for (var pace = 1.0; pace > 0.55; pace -= 0.1) {
      final jn = _Journey(k);
      // The whole works first (1.8 s), then the steps; back after a cut
      // away, 0.4 s before the next.
      var from = clear(plan.t0 + 3.0, 1.8 + _dwell[0] * pace);
      var t = from + 1.8;
      var opening = true;
      for (var i = 0; i < 7; i++) {
        final d = (_dwell[i] + (i == 2 && fallback ? 1.0 : 0)) * pace;
        // After a long look, back to the site for a few seconds (the two
        // stories cut together).
        final long = t - from > _stretch;
        if (long || clear(t, d) > t + 1e-6) {
          // Away: this stretch ends with the step before; the letter waits.
          jn.stretches.add((from, t + 0.5, opening));
          opening = false;
          from = clear(long ? t + 0.5 + _away : t, 0.4 + d);
          t = from + 0.4;
        }
        jn.at[i] = t;
        jn.end[i] = t + d;
        t += d + 0.15;
      }
      jn.at[7] = t;
      jn.stretches.add((from, t + 0.6, opening));
      if (t <= deadline) {
        _journey = jn;
        return;
      }
    }
  }

  /// How far into a visit the step it comes for starts (the works' front,
  /// then the move in).
  static const _lead = 2.4;

  /// The camera's request at [t] (priority 2, a cut): the whole works for a
  /// moment, then in on the step, following the letter down the line. Fills
  /// [caption] while it's on a step.
  void focus(List<Focus> out, double t) {
    final plan = _plan, name = _name;
    if (plan == null || name == null || plan.job.phase != Phase.build || plan.job.cutAt != null) return;
    if (out.any((f) => f.priority >= 2)) return;
    if (_journey case final jn?) {
      for (final (a, e, opening) in jn.stretches) {
        if (t < a || t >= e) continue;
        final u = t - a;
        final st = _steps[jn.k];
        final step = st.stepAt(t).clamp(0, 6);
        final Shot shot;
        if (opening && u < 1.8) {
          shot = _front;
        } else {
          shot = _stepShot(step, 0.2 * seg(t, jn.stretches.first.$1, jn.at[7]));
          _caption(name, jn.k, step, t, seg(u, opening ? 1.7 : 0.2, opening ? 2.3 : 0.6) * (1 - seg(t, e - 0.5, e)));
          caption.journey = true;
        }
        out.add(Focus('works journey ${a.toStringAsFixed(1)}', shot, priority: 2));
        return;
      }
    }
    for (final c in _cuts) {
      if (t < c.from || t >= c.to) continue;
      final u = t - c.from;
      final st = _steps[c.k];
      // (On to the letter's next step only with time left to see it there.)
      final step = st.stepAt(math.min(t, c.to - 1.5)).clamp(c.step, 6);
      final drift = 0.2 * seg(u, 1.5, c.to - c.from);
      final Shot shot;
      if (u < 1.8) {
        shot = _front;
      } else {
        shot = _stepShot(step, drift);
        _caption(name, c.k, step, t, seg(u, 1.7, 2.3) * (1 - seg(t, c.to - 0.5, c.to)));
        caption.journey = false;
      }
      out.add(Focus('works ${c.from.toStringAsFixed(1)}', shot, priority: 2));
      return;
    }
  }

  /// The works to begin a visit: from just inside its front right corner,
  /// under its sign, down the whole line (whoever's about in front of it,
  /// on a break or on the way to one, is behind the camera).
  static final _front = Shot(vm.Vector3(-9.2, 2.6, 3.4), vm.Vector3(-13.8, 0.9, 6.4), fov: 56, settle: 0.6, drift: 0.4);

  /// In on step [step] through the open front (clear of the smoking corner
  /// in front, past the board's left for the rasterizer).
  static Shot _stepShot(int step, double drift) {
    const z = WorksLayout.beltZ;
    return switch (step) {
      // The string's bytes on the wall, the feeder and the decoder.
      0 || 1 => Shot(vm.Vector3(-15.0 + drift, 1.6, 4.1), vm.Vector3(-15.35, 1.12, z + 0.55), fov: 48, settle: 1.3, drift: 0.3),
      2 => Shot(vm.Vector3(-13.95 - drift, 1.72, 4.15), vm.Vector3(-14.15, 0.95, z + 0.1), fov: 44, settle: 1.3, drift: 0.3),
      3 => Shot(vm.Vector3(-12.8 - drift, 1.72, 4.15), vm.Vector3(-12.95, 0.92, z + 0.1), fov: 44, settle: 1.3, drift: 0.3),
      4 => Shot(vm.Vector3(-11.65 - drift, 1.75, 4.2), vm.Vector3(-11.8, 0.85, z + 0.15), fov: 44, settle: 1.3, drift: 0.3),
      5 => Shot(vm.Vector3(-11.25 + drift, 1.75, 4.15), vm.Vector3(-10.8, 0.85, z + 0.1), fov: 44, settle: 1.3, drift: 0.3),
      // The board, the pixels set in (and the letter's tile, held up).
      _ => Shot(vm.Vector3(-10.3 + drift, 1.7, 2.85), vm.Vector3(-9.8, 1.05, WorksLayout.boardZ + 0.08), fov: 54, settle: 1.3, drift: 0.3),
    };
  }

  /// The caption for letter [k] at step [step].
  void _caption(WorksName name, int k, int step, double t, double show) {
    final l = name.letters[k];
    final st = _steps[k];
    caption
      ..show = show
      ..step = step
      ..letter = l.text
      ..fonts = const [];
    final bytes = l.bytes.map(WorksLetter.byte).join(' ');
    final cps = l.codePoints.map(WorksLetter.hex).join(' ');
    String em(double v) => '${v < -0.0049 ? '−' : (v > 0.0049 ? '+' : '±')}${v.abs().toStringAsFixed(2)} em';
    switch (step) {
      case 0:
        caption
          ..value = bytes
          ..note = l.bytes.length == 1 ? 'utf8.encode: 1 byte (ASCII)' : 'utf8.encode: ${l.bytes.length} bytes';
      case 1:
        caption
          ..value = '$bytes  →  $cps'
          ..note = l.codePoints.length == 1 ? 'UTF-8 decoded: 1 code point' : 'UTF-8 decoded: ${l.codePoints.length} code points, one grapheme cluster';
      case 2:
        final f = l.font, look = _lookup(st, t);
        caption
          ..value = l.codePoints.map(WorksLetter.hex).first
          ..fonts = [for (var i = 0; i <= math.min(f, look); i++) (worksFonts[i], i == f)]
          ..note = f == 0 ? 'cmap: found in the name\'s font' : (look < f ? 'cmap: no glyph here → fallback' : 'cmap: found by fallback');
      case 3:
        caption
          ..value = 'advance ${l.advance.toStringAsFixed(2)} em   kern ${k == 0 ? '—' : em(l.kern)}'
          ..note = k == 0
              ? 'the first letter: pen at 0'
              : (l.spaced
                    ? 'after a space: pen at ${l.pen.toStringAsFixed(2)} em'
                    : '${name.letters[k - 1].text} ${l.text}: pen at ${l.pen.toStringAsFixed(2)} em');
      case 4:
        final outer = l.outline.length - l.holes;
        caption
          ..value = l.rendered ? '$outer outline${outer == 1 ? '' : 's'}${l.holes > 0 ? ' + ${l.holes} hole${l.holes == 1 ? '' : 's'}' : ''}' : '…'
          ..note = 'the glyph\'s outline, scaled to ${name.size.toStringAsFixed(0)} px';
      case 5:
        caption
          ..value = l.rendered ? '${l.w} × ${l.h} px   ${l.full} full · ${l.edge} edge' : '…'
          ..note = 'coverage → grey: anti-aliasing, scanline by scanline';
      default:
        caption
          ..value = 'x ${l.penPx.toStringAsFixed(1)} px  →  column ${l.x - name.x0}'
          ..note = 'into the framebuffer at its shaped place';
    }
  }

  // ── Per frame ─────────────────────────────────────────────────────────────

  final _m = vm.Matrix4.identity(), _n = vm.Matrix4.identity();
  final _p = vm.Vector3.zero(), _q = vm.Vector3.zero();

  /// Poses the makers and the letters for [j] at [t] ([plan]: the build's
  /// plan, if ready). [shapes]: unused (see [LetterShape]).
  void update(Job j, BuildPlan? plan, double t, double night, List<LetterShape> shapes) {
    caption.show = 0;
    _mat?.emissiveStrength = 0.5 + 2.2 * smooth(0.1, 0.5, night);
    _wireMat.emissiveStrength = 0.35 + 1.2 * smooth(0.2, 0.6, night);
    final current = plan != null && identical(plan, _plan);
    if (!current && _plan != null) _clear();
    final job = _job, name = _name;
    if (job?.mat case final mat?) mat.emissiveStrength = 0.1 + 0.6 * smooth(0.2, 0.6, night);
    // A sample cut short: the works stops; what's on the board stays there,
    // the rest is put away and the makers stand about.
    final pl = _plan;
    final cutT = pl != null && j.cutAt != null && j.phase.index >= Phase.demolish.index ? math.min(t, pl.t0 + (j.cutFrac ?? 0) * pl.len) : null;
    final stopped = cutT != null;
    final tt = cutT ?? t;
    final ready = job != null && name != null && job.mat != null;
    if (ready) _meshes(job, name, tt);
    for (var i = 0; i < 3; i++) {
      if (finaleMakers & (1 << i) != 0) continue;
      final p = crew.poses[Crew3D.makers + i]..rest();
      final s = stopped || !ready ? null : _makerJob(i, tt);
      if (s == null) {
        p.pos.setFrom(WorksLayout.homes[i]);
        OffDuty.stand(p, t, 40 + i * 7);
        _idle(p, i, t);
      } else {
        _work(p, s, tt, t);
      }
    }
    if (ready) {
      _string(job, name, tt, stopped);
      _letters(job, name, tt, t, stopped);
      _stickAt(job, name, tt);
      _plateAt(job, name, tt, t, stopped);
      _boardAt(job, name, tt);
    }
    _machines(tt, t, stopped);
    held = null;
    finaleMakers = 0;
  }

  /// The letter maker [i] is with at [tt] (from setting off for the feeder
  /// to being back home), or null.
  _Steps? _makerJob(int i, double tt) {
    for (final s in _steps) {
      if (s.maker == i && tt >= s.walkIn && tt < s.homeAt) return s;
    }
    return null;
  }

  /// Builds what's missing of the letters' meshes: one letter a frame ahead
  /// of time, and whatever is needed now at once.
  void _meshes(_Job job, WorksName name, double tt) {
    var built = false;
    for (final s in _steps) {
      final piece = job.pieces[s.k];
      final soon = tt >= s.at[0] - 3;
      if (piece.crates == null && (soon || !built)) {
        _labels(job, name, s.k);
        built = true;
      }
      if (piece.wire == null && name.rendered && (tt >= s.at[4] - 2 || !built)) {
        _wireOf(job, name, s.k);
        built = true;
      }
    }
    if (job.stripMesh == null) {
      job.stripMesh = Mesh(merged([_region(_Atlas.size, _Atlas.strip, 1.76, 0.22, 0, 0, 0, 0.02)]), job.mat!);
      _strip
        ..mesh = job.stripMesh
        ..localTransform = trs(vm.Vector3(_stripX, _stripY, WorksLayout.z1 - 0.135))
        ..visible = true;
    }
    if (name.rendered && job.cell == 0) job.cell = _cellFor(name);
    if (name.rendered && job.boardW == null && _mat != null) _boardSetup(job, name);
  }

  // ── The string, and the letters down the line ─────────────────────────────

  /// The string board over the feeder: its middle.
  static const _stripX = -15.15, _stripY = 1.62;

  /// Lights up the letter being read on the string board.
  void _string(_Job job, WorksName name, double tt, bool stopped) {
    if (stopped) return;
    for (final s in _steps) {
      if (tt < s.at[0] - 0.2 || tt >= s.at[2]) continue;
      final r = job.atlas!.letterGroup[s.k];
      if (r == null) continue;
      final k = math.min(1.0, seg(tt, s.at[0] - 0.2, s.at[0] + 0.2)) * (1 - seg(tt, s.at[2] - 0.3, s.at[2]));
      final x = _stripX + (r.center.dx / _Atlas.size - 0.5) * 1.76, w = r.width / _Atlas.size * 1.76;
      final y = _stripY + (0.5 - r.bottom / _Atlas.stripH) * 0.22;
      props.glow(x, y + 0.004, WorksLayout.z1 - 0.15, w, 0.008, 0.01, _amberGlow * k);
    }
  }

  static final _amberGlow = vm.Vector4(5, 2.6, 0.6, 1), _greenGlow = vm.Vector4(0.6, 5, 2.2, 1), _redGlow = vm.Vector4(6, 0.5, 0.45, 1);

  /// The crates, the tile, the sort and the wire of every letter on the line.
  void _letters(_Job job, WorksName name, double tt, double t, bool stopped) {
    for (final s in _steps) {
      final piece = job.pieces[s.k];
      final step = stopped ? 7 : s.stepAt(tt);
      piece.hideAll();
      if (step < 0 || step >= 7 || piece.crates == null) continue;
      final l = name.letters[s.k];
      _cratesAt(piece, s, tt);
      _tileAt(piece, s, l, tt);
      _sortAt(piece, s, l, tt);
      _wireAt(piece, s, l, tt);
    }
  }

  /// The feeder's slot, the decoder's ends.
  static const _feedOut = -15.82, _decodeIn = -15.4, _decodeOut = -14.9;

  void _cratesAt(_Piece piece, _Steps s, double tt) {
    final node = piece.crates!;
    final half = piece.rowW / 2;
    double x;
    if (tt < s.at[1]) {
      // Out of the feeder's slot along the belt, to the decoder.
      x = lerp(_feedOut - half - 0.02, _decodeIn - half - 0.025, eio(seg(tt, s.at[0] + 0.25, s.end[0])));
    } else {
      // Into it, all the way.
      final f = seg(tt, s.at[1], s.at[1] + 0.55 * (s.end[1] - s.at[1]));
      if (f >= 1) return;
      x = lerp(_decodeIn - half - 0.025, _decodeIn + half + 0.02, f);
    }
    node
      ..visible = true
      ..place((m) => setTrs(m, x, WorksLayout.beltY, WorksLayout.beltZ));
  }

  /// The font cases (their middles), and the height a tile is held up to
  /// them at.
  static const _caseX = [-14.45, -14.15, -13.85], _caseY = 1.12, _lookY = 1.02;

  /// When (seconds into a font step [d] long) a glyph from font [f] comes
  /// out of its case: the tile moved over and lifted, a look in each case
  /// up to it.
  static double _catchAt(double d, int f) {
    final mv = math.min(0.6, 0.2 * d), per = (d - mv - 0.35 - 0.9) / (f + 1);
    return mv + 0.35 + (f + 0.8) * per;
  }

  /// How many cases the tile of [s] has been held up to at [tt] (−1: not
  /// yet).
  int _lookup(_Steps s, double tt) {
    final f = _name!.letters[s.k].font;
    final a = s.at[2], d = s.end[2] - a, mv = math.min(0.6, 0.2 * d);
    final per = (d - mv - 0.35 - 0.9) / (f + 1);
    var n = -1;
    for (var i = 0; i <= f; i++) {
      if (tt >= a + mv + 0.35 + i * per + 0.4 * per) n = i;
    }
    return n;
  }

  void _tileAt(_Piece piece, _Steps s, WorksLetter l, double tt) {
    final node = piece.tile!;
    final half = piece.tileW / 2;
    final y0 = WorksLayout.beltY, z = WorksLayout.beltZ;
    if (tt < s.at[1] + 0.45 * (s.end[1] - s.at[1])) return;
    if (tt < s.at[2]) {
      // Out of the decoder's far side.
      final f = eio(seg(tt, s.at[1] + 0.45 * (s.end[1] - s.at[1]), s.end[1]));
      _place(node, lerp(_decodeOut - half - 0.02, _decodeOut + half + 0.05, f), y0, z);
      return;
    }
    if (tt >= s.at[3]) return;
    // Along to the first case, up to each case in turn, and into the one
    // that has the glyph.
    final a = s.at[2], d = s.end[2] - a, mv = math.min(0.6, 0.2 * d);
    final f = l.font, per = (d - mv - 0.35 - 0.9) / (f + 1);
    final start = _decodeOut + half + 0.05;
    if (tt < a + mv) {
      _place(node, lerp(start, _caseX[0], eio(seg(tt, a, a + mv))), y0, z);
      return;
    }
    final up = eio(seg(tt, a + mv, a + mv + 0.35));
    var x = _caseX[0], y = lerp(y0, _lookY - 0.035, up);
    for (var i = 1; i <= f; i++) {
      x = lerp(x, _caseX[i], eio(seg(tt, a + mv + 0.35 + i * per, a + mv + 0.35 + i * per + 0.35 * per)));
    }
    final catchAt = a + mv + 0.35 + (f + 0.55) * per;
    final into = seg(tt, catchAt, catchAt + 0.25 * per);
    if (into >= 1) return;
    _place(node, x, y + 0.12 * into, z - 0.02 * up);
  }

  /// The composing stick: its left end (em 0, before scrolling), its rail's
  /// top, the sorts' middle line; and its em.
  static const _stickX0 = -13.44, _railY = 0.74, _sortZ = WorksLayout.beltZ + 0.07, _em = 0.2, _stickEm = 5.15;

  /// Where the stick's line starts (em) while letter [k] is set in it: far
  /// enough along that the letter fits.
  double _scroll(WorksName name, int k) {
    final l = name.letters[k];
    return math.max(0.0, l.pen + l.advance - _stickEm + 0.05);
  }

  double _stickXOf(WorksName name, int k, double em) => _stickX0 + (em - _scroll(name, k)) * _em;

  void _sortAt(_Piece piece, _Steps s, WorksLetter l, double tt) {
    final node = piece.sort!;
    final name = _name!;
    final w = l.advance * _em, h = 1.2 * _em;
    if (tt < s.at[2] || tt >= s.end[3]) return;
    if (tt < s.at[3]) {
      // Out of the case that has the glyph, down to the belt beside them.
      final a = s.at[2], d = s.end[2] - a, mv = math.min(0.6, 0.2 * d);
      final f = l.font, per = (d - mv - 0.35 - 0.9) / (f + 1);
      final out = a + mv + 0.35 + (f + 0.8) * per;
      if (tt < out) return;
      final drop = eio(seg(tt, out, out + 0.35));
      final down = eio(seg(tt, out + 0.45, s.end[2]));
      final x = lerp(_caseX[f], _caseX[2] + 0.36, down);
      final y = lerp(lerp(_caseY - 0.02 + h / 2 - h * 0.6, _caseY - h / 2 - 0.03, drop), WorksLayout.beltY + h / 2 + 0.005, down);
      _place(node, x, y, WorksLayout.beltZ);
      return;
    }
    // Up onto the stick after the letter before (the pen, unkerned), its
    // advance lit, then the kerning's nudge.
    final a = s.at[3], d = s.end[3] - a;
    final set = eio(seg(tt, a + 0.1, a + 0.4 * d));
    final nudge = eio(seg(tt, a + 0.6 * d, a + 0.85 * d));
    final xs = _stickXOf(name, s.k, lerp(l.unkerned, l.pen, nudge)) + w / 2;
    final x = lerp(_caseX[2] + 0.36, xs, set);
    final y = lerp(WorksLayout.beltY + h / 2 + 0.005, _railY + h / 2, set) + 0.08 * math.sin(math.pi * set);
    _place(node, x, y, lerp(WorksLayout.beltZ, _sortZ, set));
  }

  /// The bender's board and the rasterizer's plate lean back this much; a
  /// frame's origin is the middle of its bottom edge.
  static const _tilt = 0.95, _frameY = 0.66, _frameZ = WorksLayout.beltZ - 0.2;

  /// The leaning frame at [x] (the bender's or the plate's), into [out].
  static vm.Matrix4 _frame(double x, vm.Matrix4 out, {double lift = 0}) => setTrs(out, x, _frameY + lift, _frameZ - 0.6 * lift, pitch: _tilt);

  void _wireAt(_Piece piece, _Steps s, WorksLetter l, double tt) {
    final node = piece.wire;
    if (node == null || tt < s.at[4] || tt >= s.end[5] - 0.15) return;
    final w = piece.wireData!;
    if (tt < s.at[5]) {
      // Bent on the bender's board along its outline, the head tracing it.
      final p = _trace(s, tt);
      final chunks = piece.chunks!;
      final f = p * chunks.spare.length;
      if (p < 1) {
        for (var k = 0; k < chunks.spare.length; k++) {
          chunks.spare[k].visible = k < f;
        }
        chunks.show(node);
      } else if (!identical(node.mesh, piece.wireFull)) {
        node.mesh = piece.wireFull;
      }
      node
        ..visible = true
        ..place((m) => _frame(WorksLayout.stepX[4], m));
      if (p > 0 && p < 1) {
        w.at(p, _p);
        _frame(WorksLayout.stepX[4], _m).transform3(_p..z -= 0.03);
        props
          ..box(_p.x, _p.y + 0.02, _p.z - 0.015, 0.035, 0.05, 0.03, _steel, pitch: _tilt)
          ..glow(_p.x, _p.y, _p.z, 0.012, 0.012, 0.012, _amberGlow);
      }
      return;
    }
    // Lifted over to the plate and laid on its grid, for the scan.
    if (!identical(node.mesh, piece.wireFull)) node.mesh = piece.wireFull;
    final a = s.at[5], mv = math.min(0.7, 0.2 * (s.end[5] - a));
    final f = eio(seg(tt, a, a + mv));
    final lift = 0.1 * math.sin(math.pi * f);
    node
      ..visible = true
      ..place((m) => _frame(lerp(WorksLayout.stepX[4], WorksLayout.stepX[5], f), m, lift: lift));
  }

  /// How far the bender has traced [s]'s outline at [tt] (0..1).
  double _trace(_Steps s, double tt) => seg(tt, s.at[4] + 0.35, s.end[4] - 0.45);

  /// Places [node] at (x, y, z), shown.
  static void _place(Node node, double x, double y, double z) {
    node
      ..visible = true
      ..place((m) => setTrs(m, x, y, z));
  }

  // ── The composing stick ───────────────────────────────────────────────────

  int _stickSet = -1;
  double _stickScroll = 0;

  /// The sorts set so far, in one mesh, rebuilt as a letter is set (the
  /// line scrolls along for a long name).
  void _stickAt(_Job job, WorksName name, double tt) {
    var set = 0;
    for (final s in _steps) {
      if (tt >= s.end[3]) set = s.k + 1;
    }
    // The line starts where the letter being set needs it to.
    var at = set;
    for (final s in _steps) {
      if (tt >= s.at[3] && tt < s.end[3]) at = s.k;
    }
    final scroll = set == 0 && at == 0 ? 0.0 : _scroll(name, math.min(at, name.letters.length - 1));
    if (set != _stickSet || scroll != _stickScroll) {
      _stickSet = set;
      _stickScroll = scroll;
      final parts = <MeshData>[];
      for (var k = 0; k < set; k++) {
        final l = name.letters[k];
        final x0 = _stickX0 + (l.pen - scroll) * _em;
        // (Scrolled off the stick's left end: in the galley.)
        if (x0 < _stickX0 - 0.005) continue;
        parts.add(_sort(job, l).transformed(trs(vm.Vector3(x0 + l.advance * _em / 2, _railY + 0.6 * _em, _sortZ + (k.isEven ? 0 : 0.003)))));
      }
      _stick.mesh = parts.isEmpty ? null : Mesh(merged(parts), job.mat!);
    }
    _stick.visible = _stick.mesh != null;
  }

  // ── The plate and the board ───────────────────────────────────────────────

  int _plateK = -1, _plateShown = 0;

  /// The pixel tiles' colour for coverage [c]: the text's ink over the
  /// screen's ground, blended as the renderer does (in sRGB).
  static vm.Vector4 _pixel(double c) => lin(Color.lerp(_ground, _ink, c)!);
  static const _ground = Color(0xFF16293F), _ink = Color(0xFFE3F2FF);
  static final _groundLin = lin(_ground);

  /// The rasterizer's plate: a letter's grid laid out when it gets there,
  /// filled scanline by scanline, then carried to the board.
  void _plateAt(_Job job, WorksName name, double tt, double t, bool stopped) {
    _plateNode.visible = false;
    if (stopped || !name.rendered) return;
    _Steps? s;
    for (final x in _steps) {
      if (tt >= x.at[5] && tt < x.at[7]) s = x;
    }
    if (s == null) return;
    final l = name.letters[s.k];
    if (!l.rendered) return;
    final cell = job.cell;
    if (_plateK != s.k) {
      // This letter's grid.
      _plateK = s.k;
      _plateShown = 0;
      _plateHome = false;
      _platePixels.clearInstances();
      for (var j = 0; j < l.h; j++) {
        for (var i = 0; i < l.w; i++) {
          setTqs(_m, (i + 0.5 - l.w / 2) * cell, 0.04 + (l.h - j - 0.5) * cell, -0.012, _qi, cell * 0.9, cell * 0.9, 0.012);
          _platePixels.addInstance(_m, color: _groundLin);
        }
      }
    }
    // The scan: a pixel at a time, row by row from the top.
    final a = s.at[5], e = s.at[6], mv = math.min(0.7, 0.2 * (s.end[5] - a));
    final scanA = a + mv + 0.15, scanE = s.end[5] - 0.3;
    final n = l.w * l.h;
    final f = seg(tt, scanA, scanE);
    final shown = (f * n).floor().clamp(0, n);
    if (shown < _plateShown) {
      for (var c = 0; c < n; c++) {
        _platePixels.setInstanceColor(c, _groundLin);
      }
      _plateShown = 0;
    }
    for (var c = _plateShown; c < shown; c++) {
      _platePixels.setInstanceColor(c, _pixel(l.cover[c]));
    }
    _plateShown = shown;
    _plateNode.visible = true;
    if (tt < e) {
      if (!_plateHome) {
        _plateHome = true;
        _plateNode.place((m) => _frame(WorksLayout.stepX[5], m));
      }
      if (f > 0 && f < 1) {
        // The print head on its bar, over the pixel being done.
        final c = math.min(n - 1, shown);
        final j = c ~/ l.w, i = c % l.w;
        final m = _frame(WorksLayout.stepX[5], _m);
        _p.setValues(0, 0.04 + (l.h - j - 0.5) * cell, -0.05);
        m.transform3(_p);
        props.box(_p.x, _p.y, _p.z, l.w * cell + 0.08, 0.025, 0.025, _dark, pitch: _tilt);
        _q.setValues((i + 0.5 - l.w / 2) * cell, 0.04 + (l.h - j - 0.5) * cell, -0.07);
        m.transform3(_q);
        props
          ..box(_q.x, _q.y, _q.z, 0.05, 0.05, 0.05, _steel, pitch: _tilt)
          ..glow(_q.x, _q.y - 0.002, _q.z + 0.03, 0.02, 0.008, 0.008, _amberGlow * 0.6);
      }
      return;
    }
    // Carried to the board in the maker's hands, and set in at the letter's
    // place (shrinking to the board's pixels).
    final p = crew.poses[Crew3D.makers + s.maker];
    OffDuty.hand(p, 0, _p);
    OffDuty.hand(p, 1, _q);
    final hx = (_p.x + _q.x) / 2, hy = (_p.y + _q.y) / 2, hz = (_p.z + _q.z) / 2;
    final set = eio(seg(tt, s.at[7] - 0.55, s.at[7]));
    final lift = eio(seg(tt, e, e + 0.3));
    // Upright in the hands, facing where they go (rising off the stand).
    final carry = setTrs(_n, hx - math.sin(p.yaw) * 0.05, hy - 0.04, hz - math.cos(p.yaw) * 0.05, yaw: p.yaw, pitch: 0.25);
    final from = set > 0 ? _slotM(job, name, s.k, _m) : _frame(WorksLayout.stepX[5], _m);
    _plateHome = false;
    _plateNode.place((m) {
      if (set > 0) {
        _blendM(carry, from, set, m);
      } else if (lift < 1) {
        _blendM(from, carry, lift, m);
      } else {
        m.setFrom(carry);
      }
    });
  }

  /// [a] towards [b] by [f] (positions and axes; a quick stand-in for an
  /// interpolated rotation, fine for the small turns here), into [out].
  static vm.Matrix4 _blendM(vm.Matrix4 a, vm.Matrix4 b, double f, vm.Matrix4 out) {
    final sa = a.storage, sb = b.storage, so = out.storage;
    for (var i = 0; i < 16; i++) {
      so[i] = sa[i] + (sb[i] - sa[i]) * f;
    }
    return out;
  }

  /// Where letter [k]'s plate goes on the board (its pixels on the board's
  /// pixels), into [out].
  vm.Matrix4 _slotM(_Job job, WorksName name, int k, vm.Matrix4 out) {
    final l = name.letters[k];
    final px = job.px, s = px / job.cell;
    final ox = (l.x - name.x0 + l.w / 2 - name.cols / 2) * px;
    final oy = _boardMargin + (name.rows - (l.y - name.y0) - l.h) * px - 0.04 * s;
    _boardPose(out);
    return out..multiply(setTqs(_slot, ox, oy, -0.007 + 0.012 * s, _qi, s, s, s));
  }

  final _slot = vm.Matrix4.identity();
  bool _plateHome = false;

  /// Where letter [k]'s pixels go on the board, in the world (x).
  double _slotX(int k) {
    final name = _name, job = _job;
    final b = held?.at.x ?? WorksLayout.boardX;
    if (name == null || job == null || !name.rendered || job.boardW == null) return b;
    final l = name.letters[k];
    return b + (l.x - name.x0 + l.w / 2 - name.cols / 2) * job.px;
  }

  static const _boardMargin = 0.035, _boardThick = 0.03;

  /// The board's pose: on its stand, or wherever the finale has it.
  vm.Matrix4 _boardPose(vm.Matrix4 out) {
    final h = held;
    if (h == null) return setTrs(out, WorksLayout.boardX, WorksLayout.boardY, WorksLayout.boardZ, pitch: WorksLayout.boardTilt);
    return setTrs(out, h.at.x, h.at.y, h.at.z, yaw: h.yaw, pitch: h.tilt);
  }

  /// The board for this name: a pixel tile for every pixel of the
  /// framebuffer (the screen's ground), its frame.
  void _boardSetup(_Job job, WorksName name) {
    final px = job.px = math.min(0.024, 1.36 / name.cols);
    final w = job.boardW = name.cols * px + 2 * _boardMargin, h = job.boardH = name.rows * px + 2 * _boardMargin;
    _boardPixels.clearInstances();
    for (var j = 0; j < name.rows; j++) {
      for (var i = 0; i < name.cols; i++) {
        setTqs(_m, (i + 0.5 - name.cols / 2) * px, _boardMargin + (name.rows - j - 0.5) * px, -0.006, _qi, px * 0.88, px * 0.88, 0.012);
        _boardPixels.addInstance(_m, color: _groundLin);
      }
    }
    _boardLanded = 0;
    job.cover = Float32List(name.cols * name.rows);
    // The frame: a navy panel, a steel rim, a strut behind.
    final navy = v4(hex3(0x070E18)), rim = v4(hex3(0x8A96A6)), amber = v4(hex3(0xE9B949));
    MeshData box(double x, double y, double z, double sx, double sy, double sz, vm.Vector4 c) =>
        _solid(CuboidGeometry(vm.Vector3(sx, sy, sz)).extractMeshData(), vm.Matrix4.translationValues(x, y, z), c, _white);
    _boardFrame.mesh = Mesh(
      merged([
        box(0, h / 2, _boardThick / 2, w, h, _boardThick, navy),
        box(0, h - 0.008, -0.004, w + 0.02, 0.016, 0.016, rim),
        box(0, 0.008, -0.004, w + 0.02, 0.016, 0.016, rim),
        box(-w / 2 - 0.002, h / 2, -0.004, 0.016, h, 0.016, rim),
        box(w / 2 + 0.002, h / 2, -0.004, 0.016, h, 0.016, rim),
        box(-w / 2 + 0.06, h + 0.012, 0.0, 0.08, 0.018, 0.02, amber),
        box(w / 2 - 0.06, h + 0.012, 0.0, 0.08, 0.018, 0.02, amber),
      ]),
      _mat!,
    );
  }

  int _boardLanded = -1;

  /// The board: where it is, and the pixels of the letters landed by [tt]
  /// (each laid over what's there, as the renderer composites them).
  void _boardAt(_Job job, WorksName name, double tt) {
    _boardRoot.visible = job.boardW != null;
    if (job.boardW == null) return;
    var landed = 0;
    for (final s in _steps) {
      if (tt >= s.at[7]) landed = s.k + 1;
    }
    if (landed < _boardLanded) {
      job.cover!.fillRange(0, job.cover!.length, 0);
      for (var c = 0; c < job.cover!.length; c++) {
        _boardPixels.setInstanceColor(c, _groundLin);
      }
      _boardLanded = 0;
    }
    for (var k = _boardLanded; k < landed; k++) {
      final l = name.letters[k];
      for (var j = 0; j < l.h; j++) {
        for (var i = 0; i < l.w; i++) {
          final v = l.cover[j * l.w + i];
          if (v <= 0) continue;
          final c = (l.y - name.y0 + j) * name.cols + (l.x - name.x0 + i);
          final was = job.cover![c];
          job.cover![c] = 1 - (1 - was) * (1 - v);
          _boardPixels.setInstanceColor(c, _pixel(job.cover![c]));
        }
      }
    }
    _boardLanded = landed;
    // Moved only when it moves (moving it costs a pass over its pixels).
    final h = held;
    final pose = h == null ? null : (h.at.x, h.at.y, h.at.z, h.yaw, h.tilt);
    if (pose != _boardWas || !_boardPlaced) {
      _boardWas = pose;
      _boardPlaced = true;
      _boardRoot.place((m) => _boardPose(m));
    }
  }

  (double, double, double, double, double)? _boardWas;
  bool _boardPlaced = false;

  // ── The machines' moving parts ────────────────────────────────────────────

  static final _steel = v4(hex3(0x8A96A6)), _dark = v4(hex3(0x1B2233)), _brass = v4(hex3(0xB08A3E));
  static final _qi = vm.Quaternion.identity();

  void _machines(double tt, double t, bool stopped) {
    final name = _name;
    const z = WorksLayout.beltZ, by = WorksLayout.beltY;
    // The feeder's lever: pulled as a letter's bytes come out.
    var pull = 0.0;
    // The decoder's lamps (one per byte read) and its display.
    _display.visible = false;
    if (name != null && !stopped && _job?.mat != null) {
      for (final s in _steps) {
        pull = math.max(pull, math.sin(math.pi * seg(tt, s.at[0] - 0.1, s.at[0] + 0.6)));
        _lamps(s, name.letters[s.k], tt);
        _marks(s, name.letters[s.k], tt);
        _bracket(s, name, tt);
      }
      _decoderDisplay(tt);
    }
    final lx = _feedOut - 0.06, ly = by + 0.2, lz = z - 0.29;
    final a = -0.5 + 1.0 * pull;
    _p.setValues(lx, ly, lz);
    _q.setValues(lx + 0.02, ly + 0.16 * math.cos(a), lz - 0.16 * math.sin(a));
    props
      ..rod(_p, _q, 0.012, _dark)
      ..box(_q.x, _q.y, _q.z, 0.045, 0.045, 0.045, v4(hex3(0xE8505F)));
    // The bender's crank, turning while it bends.
    var crank = 0.0;
    if (!stopped) {
      for (final s in _steps) {
        final p = _trace(s, tt);
        if (p > 0 && p < 1) crank = t * 7;
      }
    }
    final cx = WorksLayout.stepX[4] + 0.42, cy = by + 0.32, cz = z + 0.16;
    props.cyl(cx + 0.02 * math.cos(crank), cy + 0.09 * math.sin(crank), cz - 0.09 * math.cos(crank), 0.012, 0.08, _brass, roll: math.pi / 2);
  }

  /// The decoder's lamps: one per byte as it goes in, the leading byte
  /// amber (it says how many follow), the rest green.
  void _lamps(_Steps s, WorksLetter l, double tt) {
    if (tt < s.at[1] || tt >= s.end[1] + 0.3) return;
    final piece = _job!.pieces[s.k];
    final f = seg(tt, s.at[1], s.at[1] + 0.55 * (s.end[1] - s.at[1]));
    final n = math.min(l.bytes.length, 6);
    for (var b = 0; b < n; b++) {
      // Lit once the crate is in.
      final at = (b + 0.5) * (piece.crate + 0.008) / (piece.rowW + 0.045);
      if (f < at) continue;
      final lead = l.bytes[b] & 0xC0 != 0x80;
      final x = -15.15 + (b - (n - 1) / 2) * 0.06;
      props.glow(x, WorksLayout.beltY + 0.075, WorksLayout.beltZ - 0.28, 0.03, 0.03, 0.008, lead ? _amberGlow : _greenGlow);
    }
  }

  int _displayK = -1;

  /// The decoder's display: the last letter decoded, bytes → code points
  /// (blank while the next one's bytes go in).
  void _decoderDisplay(double tt) {
    _Steps? last;
    for (final s in _steps) {
      if (tt >= s.at[1]) last = s;
    }
    if (last == null || tt < last.at[1] + 0.4 * (last.end[1] - last.at[1])) return;
    final k = last.k;
    final piece = _job!.pieces[k];
    if (piece.display == null) return;
    if (k != _displayK) {
      _displayK = k;
      _display.mesh = piece.display;
    }
    _display.visible = true;
  }

  /// ✕ on each font case that hasn't the glyph, ✓ on the one that has it.
  void _marks(_Steps s, WorksLetter l, double tt) {
    if (tt < s.at[2] || tt >= s.end[2] + 0.4) return;
    final n = _lookup(s, tt);
    final fade = 1 - seg(tt, s.end[2], s.end[2] + 0.4);
    // Stamped over the case's sample glyphs, under its name card.
    for (var i = 0; i <= n; i++) {
      final x = _caseX[i], y = _caseY + 0.09, z = WorksLayout.beltZ - 0.1 - 0.012;
      if (i < l.font) {
        props
          ..glow(x, y, z, 0.12, 0.016, 0.006, _redGlow * fade, roll: 0.6)
          ..glow(x, y, z, 0.12, 0.016, 0.006, _redGlow * fade, roll: -0.6);
      } else {
        props
          ..glow(x - 0.03, y - 0.012, z, 0.05, 0.016, 0.006, _greenGlow * fade, roll: -0.785)
          ..glow(x + 0.02, y + 0.008, z, 0.1, 0.016, 0.006, _greenGlow * fade, roll: 0.95);
      }
    }
  }

  /// On the stick: the letter's advance lit (a bar over its body, from pen
  /// to pen + advance) and, while it's nudged, where the pen was unkerned.
  void _bracket(_Steps s, WorksName name, double tt) {
    final a = s.at[3], d = s.end[3] - a;
    if (tt < a + 0.4 * d || tt >= s.end[3] + 0.2) return;
    final l = name.letters[s.k];
    final on = seg(tt, a + 0.4 * d, a + 0.5 * d) * (1 - seg(tt, s.end[3], s.end[3] + 0.2));
    final nudge = eio(seg(tt, a + 0.6 * d, a + 0.85 * d));
    final x0 = _stickXOf(name, s.k, lerp(l.unkerned, l.pen, nudge)), x1 = x0 + l.advance * _em;
    final y = _railY + 1.2 * _em + 0.025, z = _sortZ - 0.03;
    props
      ..glow((x0 + x1) / 2, y, z, x1 - x0, 0.008, 0.008, _amberGlow * on)
      ..glow(x0, y - 0.012, z, 0.006, 0.03, 0.008, _amberGlow * on)
      ..glow(x1, y - 0.012, z, 0.006, 0.03, 0.008, _amberGlow * on);
    if (s.k > 0 && (l.kern).abs() > 0.0005 && tt >= a + 0.55 * d) {
      final xu = _stickXOf(name, s.k, l.unkerned);
      props.glow(xu, _railY + 0.6 * _em, z - 0.004, 0.005, 1.2 * _em, 0.006, _redGlow * on);
    }
  }

  // ── The makers ────────────────────────────────────────────────────────────

  /// Maker [p] with letter [s] at [tt]: to the feeder, along the line with
  /// it, a step at a time, its pixels to the board, and home.
  void _work(FigurePose p, _Steps s, double tt, double t) {
    final seed = 40 + s.maker * 7;
    _walksOf(s);
    if (tt < s.at[0]) {
      s.toFeeder!.pose(p, tt, seed);
      if (tt >= s.walkIn + _walkIn - 0.05) p.yaw = 0;
      return;
    }
    final step = s.stepAt(tt);
    if (step >= 7) {
      s.toHome!.pose(p, tt, seed);
      return;
    }
    if (step == 6) {
      // The pixels to the board: round the belt's end, behind the board,
      // leaning over it to set them in.
      final there = s.at[7] - 0.6;
      if (tt < there) {
        s.toBoard!.pose(p, tt, seed);
        if (tt < s.toBoard!.start) p.yaw = 0;
        _holdOut(p);
        return;
      }
      p.pos.setValues(s.slotX, 0, WorksLayout.placeZ);
      p.yaw = 0;
      OffDuty.stand(p, t, seed);
      final k = math.sin(math.pi * seg(tt, there, s.at[7] + 0.3));
      p.lean = 0.45 * k;
      _holdOut(p);
      p.armPitch[0] = p.armPitch[1] = lerp(0.85, 1.25, k);
      return;
    }
    // At the step (walking along from the last one as it starts).
    final x = WorksLayout.workX[step];
    final a = s.at[step], d = s.end[step] - a;
    final prev = step == 0 ? x : WorksLayout.workX[step - 1];
    final mv = math.min(0.6, 0.2 * d);
    if (tt < a + mv && (x - prev).abs() > 0.05) {
      p.pos.setValues(lerp(prev, x, seg(tt, a, a + mv)), 0, WorksLayout.workZ);
      OffDuty.walk(p, t, (x - prev).abs() / mv, seed);
      p.yaw = x > prev ? -math.pi / 2 : math.pi / 2;
      return;
    }
    p.pos.setValues(x, 0, WorksLayout.workZ);
    OffDuty.stand(p, t, seed);
    p.yaw = 0;
    final pieces = _job!.pieces;
    final piece = pieces[s.k];
    switch (step) {
      case 0:
        // Pulling the feeder's lever.
        _p.setValues(_feedOut - 0.04, WorksLayout.beltY + 0.3, WorksLayout.beltZ - 0.22);
        _reach(p, 1, _p, math.sin(math.pi * seg(tt, a - 0.1, a + 0.7)));
        p.lean = 0.12;
      case 1:
        // A hand on the decoder, watching the bytes go in.
        _p.setValues(-15.1, WorksLayout.beltY + 0.36, WorksLayout.beltZ + 0.12);
        crew.aim(p, 1, _p, maxStoop: _bench);
        p.lean = 0.18;
      case 2 || 3:
        // The tile up to the cases, the sort out of one, onto the stick.
        final node = piece.sort?.visible == true ? piece.sort : (piece.tile?.visible == true ? piece.tile : null);
        p.lean = 0.25;
        if (node == null) {
          p.armRoll[0] = p.armRoll[1] = 0.85;
          p.armPitch[0] = p.armPitch[1] = -0.3;
          break;
        }
        final at = node.globalTransform.getTranslation();
        for (var h = 0; h < 2; h++) {
          _p.setValues(at.x + (h == 0 ? -0.06 : 0.06), at.y, at.z + 0.04);
          crew.aim(p, h, _p, maxStoop: _bench);
        }
        p.yaw = (-(at.x - p.pos.x) * 0.6).clamp(-0.5, 0.5);
      case 4:
        // Turning the bender's crank.
        final c = t * 7;
        _p.setValues(WorksLayout.stepX[4] + 0.44, WorksLayout.beltY + 0.32 + 0.09 * math.sin(c), WorksLayout.beltZ + 0.16 - 0.09 * math.cos(c));
        crew.aim(p, 1, _p, maxStoop: _bench);
        p.lean = 0.22;
        p.armRoll[0] = 0.85;
        p.armPitch[0] = -0.3;
      default:
        // Laying the wire on the plate, then a hand on the rasterizer's
        // controls while it runs.
        if (tt < a + math.min(0.7, 0.2 * d) + 0.1) {
          final m = _frame(WorksLayout.stepX[5], _m);
          for (var h = 0; h < 2; h++) {
            _p.setValues(h == 0 ? -0.18 : 0.18, 0.25, -0.05);
            m.transform3(_p);
            crew.aim(p, h, _p, maxStoop: _bench);
          }
          p.lean = 0.3;
        } else {
          _p.setValues(WorksLayout.stepX[5] + 0.42, WorksLayout.beltY + 0.2, WorksLayout.beltZ + 0.12);
          crew.aim(p, 1, _p, maxStoop: _bench);
          p.lean = 0.15;
          p.armRoll[0] = 0.85;
          p.armPitch[0] = -0.3;
        }
    }
  }

  /// [s]'s maker's walks (made once, and again if the letter's place on
  /// the board moves, once its pixels are in): from home to the feeder,
  /// with its pixels to the board, and home again.
  void _walksOf(_Steps s) {
    final x = _slotX(s.k);
    if (s.toBoard != null && s.slotX == x) return;
    s.slotX = x;
    final home = WorksLayout.homes[s.maker], slot = vm.Vector3(x, 0, WorksLayout.placeZ);
    s.toFeeder = Walk(WorksLayout.route(home, vm.Vector3(WorksLayout.workX[0], 0, WorksLayout.workZ)), s.walkIn, 1.2);
    final way = [
      vm.Vector3(WorksLayout.workX[5], 0, WorksLayout.workZ),
      vm.Vector3(WorksLayout.walkX, 0, WorksLayout.workZ),
      vm.Vector3(WorksLayout.walkX, 0, WorksLayout.placeZ),
      slot,
    ];
    final go = s.at[6] + 0.3, there = s.at[7] - 0.6;
    s.toBoard = Walk(way, go, Walk.lengthOf(way) / math.max(0.4, there - go));
    final back = WorksLayout.route(slot, home);
    s.toHome = Walk(back, s.at[7] + 0.3, Walk.lengthOf(back) / math.max(0.5, s.homeAt - s.at[7] - 0.3));
  }

  /// How low a maker crouches to reach along the belt (a little: they lean
  /// over it, rather than duck under the bench).
  static const _bench = 0.12;

  /// Arm [s] of [p] towards [at], by [k] (0: as it was).
  void _reach(FigurePose p, int s, vm.Vector3 at, double k) {
    final pitch = p.armPitch[s], roll = p.armRoll[s];
    crew.aim(p, s, at, maxStoop: _bench);
    p.armPitch[s] = lerp(pitch, p.armPitch[s], k);
    p.armRoll[s] = lerp(roll, p.armRoll[s], k);
  }

  void _idle(FigurePose p, int i, double t) {
    // A word with the neighbour now and then, else watching the line.
    final cycle = (t / 6.5).floor();
    if (rnd(cycle, i, 71) < 0.35) {
      p.yaw = i == 0 ? -0.9 : (i == 2 ? 0.9 : (cycle.isEven ? 0.9 : -0.9));
      if ((cycle + i).isEven) {
        OffDuty.talk(p, t, i * 5);
      } else {
        OffDuty.listen(p, t, i * 5);
      }
    } else {
      p.yaw = 0.15 * math.sin(t * 0.4 + i);
      p.lean = 0.06;
      p.armRoll[0] = p.armRoll[1] = 0.85;
      p.armPitch[0] = p.armPitch[1] = -0.3;
    }
  }

  /// Both hands out in front, holding something.
  void _holdOut(FigurePose p) {
    p.armPitch[0] = p.armPitch[1] = 0.85;
    p.armRoll[0] = p.armRoll[1] = -0.22;
  }

  // ── The letters' meshes ───────────────────────────────────────────────────

  /// The crates' wood, the tiles' navy, the sorts' steel (vertex colours
  /// round their printed faces).
  static final _wood = v4(hex3(0xB98B5E)), _navy = v4(hex3(0x1B2A44)), _type = v4(hex3(0x3A4558)), _white4 = vm.Vector4(1, 1, 1, 1);

  /// Letter [k]'s crates (a row of its bytes), code point tiles, sort and
  /// the decoder's display of it.
  void _labels(_Job job, WorksName name, int k) {
    final l = name.letters[k], atlas = job.atlas!, piece = job.pieces[k];
    final n = l.bytes.length;
    final c = piece.crate = math.min(0.085, 0.42 / n);
    const gap = 0.008;
    final rowW = piece.rowW = n * c + (n - 1) * gap;
    final crates = [for (var b = 0; b < n; b++) _labelBox(atlas.bytes[k][b], -rowW / 2 + c / 2 + b * (c + gap), c / 2, 0, c, c, c, _wood)];
    piece.crates = _node('crates ${l.text}', Mesh(merged(crates), job.mat!));
    const tw = 0.2, th = 0.07;
    final m = l.codePoints.length;
    final tileW = piece.tileW = m * tw + (m - 1) * 0.006;
    final tiles = [
      for (var i = 0; i < m; i++) _labelBox(atlas.codes[k][i], -tileW / 2 + tw / 2 + i * (tw + 0.006), th / 2, 0, tw, th, 0.025, _navy),
      // One grapheme, several code points: clamped together.
      if (m > 1) _labelBox(null, 0, th + 0.007, 0, tileW + 0.01, 0.014, 0.03, v4(hex3(0xE9B949))),
    ];
    piece.tile = _node('tile ${l.text}', Mesh(merged(tiles), job.mat!));
    piece.sort = _node('sort ${l.text}', Mesh(merged([_sort(job, l)]), job.mat!));
    piece.display = Mesh(merged([_region(_Atlas.size, atlas.displays[k], 0.36, 0.072, 0, 0, 0, 0.006)]), job.mat!);
  }

  /// Letter [l]'s sort: a body as wide as its advance and as tall as the
  /// line, its glyph on its face (centred on the origin).
  MeshData _sort(_Job job, WorksLetter l) => _labelBox(job.atlas!.faces[l.k], 0, 0, 0, math.max(0.01, l.advance * _em), 1.2 * _em, 0.05, _type);

  Node _node(String name, Mesh mesh) {
    final n = Node(name: 'works $name', mesh: mesh)
      ..castsShadows = false
      ..visible = false;
    scene.add(n);
    _job!.nodes.add(n);
    return n;
  }

  /// A box [w]×[h]×[d] centred at (x, y, z) whose front (−z) shows [face] of
  /// the name's atlas (null: plain), the rest [color].
  MeshData _labelBox(Rect? face, double x, double y, double z, double w, double h, double d, vm.Vector4 color) {
    final data = CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData();
    final uv = Float32List(data.vertexCount * 2), nr = data.normals!, p = data.positions;
    final colors = Float32List(data.vertexCount * 4);
    const plain = _Atlas.plain;
    for (var i = 0; i < data.vertexCount; i++) {
      final front = face != null && nr[i * 3 + 2] < -0.5;
      uv[i * 2] = front ? (face.left + (p[i * 3] / w + 0.5) * face.width) / _Atlas.size : (plain.center.dx / _Atlas.size);
      uv[i * 2 + 1] = front ? (face.top + (0.5 - p[i * 3 + 1] / h) * face.height) / _Atlas.size : (plain.center.dy / _Atlas.size);
      final c = front ? _white4 : color;
      colors
        ..[i * 4] = c.x
        ..[i * 4 + 1] = c.y
        ..[i * 4 + 2] = c.z
        ..[i * 4 + 3] = 1;
    }
    return MeshData(
      positions: p,
      vertexCount: data.vertexCount,
      normals: nr,
      texCoords: uv,
      colors: colors,
      indices: data.indices,
    ).transformed(vm.Matrix4.translationValues(x, y, z));
  }

  /// A thin board [w]×[h] (centred at (x, y, z), [thick]) showing [region]
  /// of an atlas [size] px square on its front, [edge] round the edges
  /// (the atlas's [plain] white under it).
  static MeshData _region(
    int size,
    Rect region,
    double w,
    double h,
    double x,
    double y,
    double z,
    double thick, {
    Rect plain = _Atlas.plain,
    int edge = 0x1B2233,
  }) {
    final d = CuboidGeometry(vm.Vector3(w, h, thick)).extractMeshData();
    final uv = Float32List(d.vertexCount * 2), nr = d.normals!, p = d.positions;
    final colors = Float32List(d.vertexCount * 4), side = v4(hex3(edge));
    for (var i = 0; i < d.vertexCount; i++) {
      final front = nr[i * 3 + 2] < -0.5;
      uv[i * 2] = front ? (region.left + (p[i * 3] / w + 0.5) * region.width) / size : plain.center.dx / size;
      uv[i * 2 + 1] = front ? (region.top + (0.5 - p[i * 3 + 1] / h) * region.height) / size : plain.center.dy / size;
      final c = front ? _white4 : side;
      colors
        ..[i * 4] = c.x
        ..[i * 4 + 1] = c.y
        ..[i * 4 + 2] = c.z
        ..[i * 4 + 3] = 1;
    }
    return MeshData(
      positions: p,
      vertexCount: d.vertexCount,
      normals: nr,
      texCoords: uv,
      colors: colors,
      indices: d.indices,
    ).transformed(vm.Matrix4.translationValues(x, y, z));
  }

  /// Letter [k]'s wire: its outline as a thin tube in the leaning frame's
  /// metres (one pixel of the works' raster a grid cell), in runs to trace
  /// it out, and whole.
  void _wireOf(_Job job, WorksName name, int k) {
    final l = name.letters[k], piece = job.pieces[k];
    final cell = job.cell = job.cell > 0 ? job.cell : _cellFor(name);
    final loops = [
      for (final o in l.outline)
        Float32List.fromList([
          for (var i = 0; i < o.length; i += 2) ...[(o[i] - l.w / 2) * cell, 0.04 + (l.h - o[i + 1]) * cell],
        ]),
    ];
    final wire = piece.wireData = _Wire(loops);
    const runs = 6;
    final parts = [for (var r = 0; r < runs; r++) wire.tube(r / runs, (r + 1) / runs, 0.0045, -0.026)];
    final geos = [
      for (final p in parts)
        if (p != null) MeshGeometry.fromMeshData(p),
    ];
    if (geos.isEmpty) {
      piece.wire = _node('wire ${l.text}', Mesh(CuboidGeometry(vm.Vector3.all(0.001)), _wireMat));
      piece.wireFull = piece.wire!.mesh;
      piece.chunks = _Flip([CuboidGeometry(vm.Vector3.all(0.001))], _wireMat);
      return;
    }
    piece.chunks = _Flip(geos, _wireMat);
    piece.wireFull = Mesh(merged([for (final p in parts) ?p]), _wireMat);
    piece.wire = _node('wire ${l.text}', piece.wireFull!);
  }

  /// The grid's cell (m): the biggest letter fits the plate (52 cm).
  static double _cellFor(WorksName name) {
    var most = 1;
    for (final l in name.letters) {
      most = math.max(most, math.max(l.w, l.h));
    }
    return math.min(0.034, 0.52 / most);
  }

  // ── The building ──────────────────────────────────────────────────────────

  static const _atlas = 1024;
  static const _sign = Rect.fromLTWH(8, 8, 1008, 150);
  static const _stepSigns = [
    Rect.fromLTWH(8, 166, 330, 84),
    Rect.fromLTWH(346, 166, 330, 84),
    Rect.fromLTWH(684, 166, 330, 84),
    Rect.fromLTWH(8, 258, 330, 84),
    Rect.fromLTWH(346, 258, 330, 84),
    Rect.fromLTWH(684, 258, 330, 84),
    Rect.fromLTWH(8, 350, 330, 84),
  ];
  static const _cases = [Rect.fromLTWH(346, 350, 220, 196), Rect.fromLTWH(574, 350, 220, 196), Rect.fromLTWH(802, 350, 220, 196)];
  static const _poster = Rect.fromLTWH(8, 556, 420, 300), _decoderPanel = Rect.fromLTWH(436, 556, 300, 42), _screen = Rect.fromLTWH(436, 648, 160, 100);
  static const _ruler = Rect.fromLTWH(8, 868, 1008, 48), _plateGrid = Rect.fromLTWH(744, 556, 272, 272);
  static const _white = Rect.fromLTWH(968, 968, 48, 48), _glowPatch = Rect.fromLTWH(908, 968, 48, 48), _lampPatch = Rect.fromLTWH(848, 968, 48, 48);

  Future<void> _build() async {
    await awaitFallbackFonts(
      '文字工場 文字列 デコード フォント シェーピング アウトライン ラスタライズ 画面 字あ한 テキストパイプライン',
      style: const TextStyle(fontFamily: BP.display, fontSize: 40, locale: Locale('ja')),
    );
    final base = await _texture(_atlas, _atlas, (c) => _paint(c, glow: false));
    final glow = await _texture(_atlas, _atlas, (c) => _paint(c, glow: true));
    final mat = PhysicallyBasedMaterial()
      ..baseColorTexture = base
      ..emissiveTexture = glow
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.6
      ..metallicFactor = 0.05
      ..roughnessFactor = 0.62;
    _mat = mat;
    scene.add(Node(name: 'glyph works', mesh: Mesh(merged(_walls()), mat)));
    // The roof (and its signs) casts no shadow: the sun reaches the line.
    scene.add(Node(name: 'glyph works roof', mesh: Mesh(merged(_roof()), mat))..castsShadows = false);
  }

  /// A texture painted with a canvas; its mip levels averaged as data (the
  /// colour-correct average is ~20× slower to build, a dropped frame for
  /// each name's atlas, and labels look the same).
  static Future<Texture2D> _texture(int w, int h, void Function(Canvas c) paint) async {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec));
    final image = await rec.endRecording().toImage(w, h);
    try {
      return await Texture2D.fromImage(image, content: TextureContent.data);
    } finally {
      image.dispose();
    }
  }

  static vm.Vector2 _uvOf(Rect r) => vm.Vector2((r.left + r.width / 2) / _atlas, (r.top + r.height / 2) / _atlas);

  /// A box sampling one patch of the atlas (white: plain colour).
  MeshData _box(double x, double y, double z, double w, double h, double d, int rgb, {Rect patch = _white, double yaw = 0, double pitch = 0}) =>
      _solid(CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData(), trs(vm.Vector3(x, y, z), rotY: yaw, rotX: pitch), v4(hex3(rgb)), patch);

  MeshData _cyl(
    double x,
    double y,
    double z,
    double r,
    double h,
    int rgb, {
    double? top,
    int segments = 14,
    Rect patch = _white,
    double pitch = 0,
    double roll = 0,
  }) => _solid(
    CylinderGeometry(bottomRadius: r, topRadius: top ?? r, height: h, radialSegments: segments).extractMeshData(),
    trs(vm.Vector3(x, y, z), rotX: pitch, rotZ: roll),
    v4(hex3(rgb)),
    patch,
  );

  static MeshData _solid(MeshData d, vm.Matrix4 at, vm.Vector4 color, Rect patch) {
    final uv = Float32List(d.vertexCount * 2), c = _uvOf(patch);
    for (var i = 0; i < d.vertexCount; i++) {
      uv
        ..[i * 2] = c.x
        ..[i * 2 + 1] = c.y;
    }
    return painted(d, color, uvs: uv).transformed(at);
  }

  /// A thin board whose front (local −z) shows [region] of the atlas.
  MeshData _board(
    double x,
    double y,
    double z,
    double w,
    double h,
    Rect region, {
    int edge = 0x1B2233,
    double thick = 0.03,
    double yaw = 0,
    double pitch = 0,
  }) => _region(_atlas, region, w, h, 0, 0, 0, thick, plain: _white, edge: edge).transformed(trs(vm.Vector3(x, y, z), rotY: yaw, rotX: pitch));

  List<MeshData> _walls() {
    const x0 = WorksLayout.x0, x1 = WorksLayout.x1, z0 = WorksLayout.z0, z1 = WorksLayout.z1, cx = WorksLayout.cx;
    const w = x1 - x0, d = z1 - z0, h = WorksLayout.roof, zc = (z0 + z1) / 2;
    const wall = 0xE6DED0, band = 0x2A3344, floor = 0x4B5566, steel = 0x3A4558;
    final parts = <MeshData>[
      // Floor, back wall, side walls (a navy band along their feet).
      _box(cx, 0.008, zc, w, 0.016, d, floor),
      _box(cx, h / 2, z1 - 0.06, w, h, 0.12, wall),
      _box(cx, 0.3, z1 - 0.125, w - 0.2, 0.6, 0.012, band),
      for (final x in [x0 + 0.06, x1 - 0.06]) ...[
        _box(x, h / 2, zc, 0.12, h, d, wall),
        _box(x + (x < cx ? 0.065 : -0.065), 0.3, zc, 0.012, 0.6, d - 0.2, band),
      ],
      // The front's corner posts.
      for (final x in [x0 + 0.1, x1 - 0.1]) _box(x, WorksLayout.open / 2, z0 + 0.1, 0.2, WorksLayout.open, 0.2, steel),
    ];
    // The belt: rubber on a steel frame, legs, a roller at each end.
    const bx0 = WorksLayout.beltX0, bx1 = WorksLayout.beltX1, bz = WorksLayout.beltZ, by = WorksLayout.beltY, bw = WorksLayout.beltW;
    const bm = (bx0 + bx1) / 2, bl = bx1 - bx0;
    parts
      ..add(_box(bm, by - 0.015, bz, bl, 0.03, bw - 0.04, 0x23272E))
      ..add(_box(bm, by - 0.06, bz - bw / 2 + 0.015, bl + 0.06, 0.1, 0.03, steel))
      ..add(_box(bm, by - 0.06, bz + bw / 2 - 0.015, bl + 0.06, 0.1, 0.03, steel));
    for (var x = bx0 + 0.15; x < bx1; x += 1.0) {
      for (final s in [-1.0, 1.0]) {
        parts.add(_box(x, (by - 0.1) / 2, bz + s * (bw / 2 - 0.03), 0.05, by - 0.1, 0.05, steel));
      }
    }
    for (final x in [bx0 + 0.02, bx1 - 0.02]) {
      parts.add(_cyl(x, by - 0.035, bz, 0.035, bw - 0.03, 0x8A96A6, pitch: math.pi / 2));
    }
    // 1 The feeder: a low hopper over the belt's start, the bytes come out
    // of its slot; the string's board on the wall above.
    parts
      ..add(_box(-16.12, by + 0.14, bz, 0.6, 0.28, 0.52, 0x2E6DA8))
      ..add(_box(-16.12, by + 0.3, bz, 0.66, 0.05, 0.58, 0x2A3344))
      ..add(_box(_feedOut + 0.002, by + 0.06, bz, 0.004, 0.11, 0.3, 0x0B0F16))
      ..add(_box(_feedOut - 0.06, by + 0.2, bz - 0.27, 0.05, 0.05, 0.03, 0x1B2233))
      ..add(_box(_stripX, _stripY, z1 - 0.125, 1.84, 0.3, 0.01, 0x2A3344));
    // 2 The decoder: low over the belt (the bytes go in one side, the code
    // point comes out of the other), its label, display and lamps in front.
    parts
      ..add(_box(-15.15, by + 0.16, bz, 0.5, 0.32, 0.54, 0x3A4558))
      ..add(_box(-15.15, by + 0.335, bz, 0.54, 0.03, 0.58, 0x2A3344))
      ..add(_board(-15.15, by + 0.285, bz - 0.278, 0.36, 0.05, _decoderPanel, thick: 0.006))
      ..add(_box(-15.15, by + 0.075, bz - 0.274, 0.4, 0.05, 0.006, 0x0B0F16))
      ..add(_box(-15.15, by + 0.19, bz - 0.274, 0.4, 0.09, 0.006, 0x0B0F16));
    // 3 The font cases on a gantry over the belt, in the order they're
    // looked in.
    for (final x in [-14.64, -13.66]) {
      parts.add(_box(x, (by + _caseY + 0.29) / 2, bz + 0.2, 0.04, _caseY + 0.29 - by + 0.02, 0.04, steel));
    }
    parts.add(_box(-14.15, _caseY + 0.3, bz + 0.2, 1.02, 0.04, 0.05, steel));
    for (var i = 0; i < 3; i++) {
      parts
        ..add(_box(_caseX[i], _caseY + 0.125, bz + 0.04, 0.28, 0.25, 0.28, 0x9C6B3C))
        ..add(_board(_caseX[i], _caseY + 0.125, bz - 0.1, 0.27, 0.24, _cases[i], thick: 0.006))
        ..add(_box(_caseX[i], _caseY + 0.005, bz - 0.04, 0.22, 0.012, 0.12, 0x0B0F16));
    }
    // 4 The composing stick: a rail with a ruler in em, a ledge behind.
    const sm = _stickX0 + _stickEm * _em / 2, sw = _stickEm * _em + 0.04;
    parts
      ..add(_box(sm, _railY - 0.02, _sortZ, sw, 0.04, 0.1, steel))
      ..add(_board(sm, _railY - 0.02, _sortZ - 0.052, sw, 0.04, _ruler, thick: 0.004))
      ..add(_box(sm, _railY + 0.05, _sortZ + 0.04, sw, 0.1, 0.012, 0x2A3344));
    for (final x in [_stickX0 - 0.03, _stickX0 + _stickEm * _em + 0.03]) {
      parts.add(_box(x, (by + _railY) / 2, _sortZ, 0.04, _railY - by, 0.04, steel));
    }
    // 5 The wire bender: its board leaning back, a spool, the crank's wheel.
    MeshData leaning(double x, double ly, double lz, double sx, double sy, double sz, int rgb, {Rect patch = _white}) {
      final m = _frame(x, vm.Matrix4.identity());
      final c = m.transform3(vm.Vector3(0, ly, lz));
      return _box(c.x, c.y, c.z, sx, sy, sz, rgb, pitch: _tilt, patch: patch);
    }

    final bx = WorksLayout.stepX[4], rx = WorksLayout.stepX[5];
    parts
      ..add(leaning(bx, 0.3, 0.015, 0.62, 0.62, 0.02, 0x9C6B3C))
      ..add(leaning(bx, 0.3, 0.03, 0.66, 0.66, 0.02, 0x2A3344))
      ..add(_cyl(bx - 0.36, by + 0.12, bz + 0.12, 0.08, 0.06, 0xE8A04A, pitch: math.pi / 2))
      ..add(_cyl(bx + 0.38, by + 0.32, bz + 0.16, 0.1, 0.03, 0x3A4558, roll: math.pi / 2));
    // 6 The rasterizer: the plate leaning back on its stand (a grid under
    // the pixels), its gantry's rails, the control box.
    parts
      ..add(leaning(rx, 0.3, 0.02, 0.62, 0.62, 0.02, 0x0E1A2B, patch: _plateGrid))
      ..add(leaning(rx, 0.3, 0.035, 0.68, 0.68, 0.02, 0x2A3344))
      ..add(leaning(rx - 0.33, 0.3, -0.03, 0.025, 0.66, 0.04, steel))
      ..add(leaning(rx + 0.33, 0.3, -0.03, 0.025, 0.66, 0.04, steel))
      ..add(_box(rx + 0.42, by + 0.09, bz + 0.12, 0.14, 0.18, 0.13, 0x2E6DA8))
      ..add(_board(rx + 0.42, by + 0.12, bz + 0.052, 0.1, 0.07, _screen, thick: 0.004));
    for (final x in [bx, rx]) {
      for (final s in [-0.25, 0.25]) {
        parts.add(_box(x + s, (by + _frameY) / 2, _frameZ + 0.1, 0.035, _frameY - by + 0.1, 0.035, steel));
      }
    }
    // 7 The pixel board's stand: a ledge for its bottom edge, legs, a strut
    // behind.
    const gx = WorksLayout.boardX, gy = WorksLayout.boardY, gz = WorksLayout.boardZ;
    parts.add(_box(gx, gy - 0.02, gz, 1.56, 0.03, 0.09, 0x9C6B3C));
    for (final s in [-0.7, 0.7]) {
      parts
        ..add(_box(gx + s, (gy - 0.035) / 2, gz - 0.02, 0.04, gy - 0.035, 0.04, steel))
        ..add(_box(gx + s, gy * 0.75, gz + 0.22, 0.035, gy * 1.4, 0.035, steel, pitch: -0.35));
    }
    // The back wall: a poster for the talk; shelves of font cases and wire
    // spools on the side walls; a fire extinguisher.
    parts.add(_board(-11.05, 1.72, z1 - 0.13, 0.84, 0.6, _poster, edge: 0xF4F1EA, thick: 0.01));
    for (final (x, dir) in [(x0 + 0.24, 1.0), (x1 - 0.24, -1.0)]) {
      for (final y in [1.0, 1.55]) {
        parts.add(_box(x, y, zc + 0.5, 0.3, 0.03, 1.5, 0x9C6B3C));
        for (var k = 0; k < 4; k++) {
          final c = const [0xE9B949, 0x5FB8FF, 0xE8505F, 0xF4F1EA, 0x6CE5B1][(k + (y > 1.2 ? 2 : 0)) % 5];
          if (dir > 0) {
            parts.add(_box(x, y + 0.07, zc - 0.05 + k * 0.36, 0.22, 0.11, 0.28, k.isEven ? 0x9C6B3C : 0x7A5230));
          } else {
            parts.add(_cyl(x, y + 0.075, zc - 0.05 + k * 0.36, 0.09, 0.06, c, roll: math.pi / 2));
          }
        }
      }
    }
    parts
      ..add(_cyl(x0 + 0.32, 0.27, z0 + 0.35, 0.08, 0.5, 0xD8343F))
      ..add(_cyl(x0 + 0.32, 0.56, z0 + 0.35, 0.03, 0.08, 0x1B2233));
    return parts;
  }

  List<MeshData> _roof() {
    const x0 = WorksLayout.x0, x1 = WorksLayout.x1, z0 = WorksLayout.z0, z1 = WorksLayout.z1, cx = WorksLayout.cx;
    const h = WorksLayout.roof, open = WorksLayout.open, zc = (z0 + z1) / 2;
    final parts = <MeshData>[
      _box(cx, h + 0.08, zc - 0.1, x1 - x0 + 0.3, 0.16, z1 - z0 + 0.4, 0x2A3344),
      _box(cx, h + 0.17, z0 - 0.28, x1 - x0 + 0.3, 0.04, 0.05, 0xFFC23D),
      // The fascia over the opening, and the sign on it.
      _box(cx, (open + h) / 2, z0 + 0.05, x1 - x0, h - open, 0.1, 0x1B2A44),
      _board(cx, (open + h) / 2 + 0.01, z0 - 0.02, 5.2, 0.52, _sign, edge: 0x1B2A44, thick: 0.04),
    ];
    // Each step's sign, hung over it; lamps over the line.
    final signs = [...WorksLayout.stepX, WorksLayout.boardX];
    for (var i = 0; i < 7; i++) {
      final x = signs[i], z = i < 6 ? WorksLayout.beltZ - 0.3 : WorksLayout.boardZ + 0.25, y = i < 6 ? 2.08 : 1.75;
      parts.add(_board(x, y, z, 0.86, 0.22, _stepSigns[i], thick: 0.02));
      for (final s in [-0.34, 0.34]) {
        parts.add(_box(x + s, (y + 0.11 + h) / 2, z, 0.012, h - y - 0.11, 0.012, 0x1B2233));
      }
    }
    for (final x in [-15.6, -14.15, -12.94, -11.3]) {
      parts
        ..add(_cyl(x, h - 0.2, WorksLayout.beltZ + 0.1, 0.012, 0.4, 0x1B2233))
        ..add(_cyl(x, h - 0.45, WorksLayout.beltZ + 0.1, 0.2, 0.12, 0x2E6DA8, top: 0.06))
        ..add(_cyl(x, h - 0.515, WorksLayout.beltZ + 0.1, 0.16, 0.012, 0xFFF1D6, patch: _lampPatch));
    }
    return parts;
  }

  // ── The atlas ─────────────────────────────────────────────────────────────

  void _paint(Canvas c, {required bool glow}) {
    const navy = Color(0xFF1B2A44), cream = Color(0xFFF4F1EA), black = Color(0xFF000000);
    c.drawRect(const Rect.fromLTWH(0, 0, _atlas + 0.0, _atlas + 0.0), Paint()..color = black);
    c.drawRect(_white, Paint()..color = glow ? black : const Color(0xFFFFFFFF));
    c.drawRect(_glowPatch, Paint()..color = const Color(0xFFFF8A3D));
    c.drawRect(_lampPatch, Paint()..color = glow ? const Color(0xFFFFE2B0) : const Color(0xFFFFF4DE));
    // The sign: 文字工場 · GLYPH WORKS on navy, an amber rule.
    final r = _sign;
    c.drawRect(r, Paint()..color = glow ? black : navy);
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(8), const Radius.circular(10)),
      Paint()
        ..color = glow ? const Color(0xFF7A5A10) : BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    final ink = glow ? const Color(0xFFFFC23D) : cream, amber = glow ? const Color(0xFFFFC23D) : BP.amber;
    _text(
      c,
      '',
      Rect.fromLTWH(r.left + 30, r.top + 22, r.width - 60, r.height - 44),
      96,
      ink,
      spans: [
        TextSpan(
          text: '文字工場',
          style: TextStyle(color: ink),
        ),
        TextSpan(
          text: '  ·  ',
          style: TextStyle(color: glow ? const Color(0xFF7A5A10) : amber),
        ),
        TextSpan(
          text: 'GLYPH WORKS',
          style: TextStyle(color: amber, fontSize: 80),
        ),
      ],
    );
    // The steps' signs: a number in a ring, the step in Japanese and English.
    for (var i = 0; i < 7; i++) {
      final b = _stepSigns[i];
      c.drawRect(b, Paint()..color = glow ? black : cream);
      if (glow) continue;
      c.drawRect(
        b.deflate(4),
        Paint()
          ..color = navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      final o = Offset(b.left + 44, b.center.dy);
      c.drawCircle(o, 28, Paint()..color = i == 6 ? const Color(0xFF2E6DA8) : navy);
      _text(c, '${i + 1}', Rect.fromCenter(center: o, width: 44, height: 44), 40, cream);
      _text(c, worksSteps[i].$1, Rect.fromLTWH(b.left + 84, b.top + 6, b.width - 92, 44), 40, navy);
      _text(c, worksSteps[i].$2, Rect.fromLTWH(b.left + 84, b.top + 50, b.width - 92, 28), 24, const Color(0xFF2E6DA8));
    }
    // The font cases' fronts: a drawer with a name card and a sample.
    const samples = ['Aa Éé', 'ب ت ع', '字 あ 한'];
    for (var i = 0; i < 3; i++) {
      final b = _cases[i];
      c.drawRect(b, Paint()..color = glow ? black : const Color(0xFFB07A44));
      if (glow) continue;
      c.drawRect(
        b.deflate(6),
        Paint()
          ..color = const Color(0xFF7A5230)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      final card = Rect.fromLTWH(b.left + 18, b.top + 18, b.width - 36, 64);
      c.drawRect(card, Paint()..color = cream);
      _text(c, worksFonts[i], card.deflate(6), 30, navy);
      _text(c, samples[i], Rect.fromLTWH(b.left + 14, b.top + 92, b.width - 28, 70), 54, const Color(0xFF2A1A0E), sample: true);
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(b.center.dx - 34, b.bottom - 26, 68, 12), const Radius.circular(6)),
        Paint()..color = const Color(0xFF3A2A1A),
      );
    }
    // A poster for the talk: the pipeline in seven boxes.
    final p = _poster;
    c.drawRect(p, Paint()..color = glow ? black : cream);
    if (!glow) {
      _text(c, 'Inside Flutter\'s Text Pipeline', Rect.fromLTWH(p.left + 14, p.top + 14, p.width - 28, 52), 40, navy);
      _text(c, 'テキストパイプラインの中', Rect.fromLTWH(p.left + 14, p.top + 66, p.width - 28, 36), 28, const Color(0xFFE8505F));
      for (var i = 0; i < 7; i++) {
        final x = p.left + 22 + i * 56.0, y = p.top + 130;
        c.drawRect(
          Rect.fromLTWH(x, y, 44, 44),
          Paint()
            ..color = navy
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        _text(c, '${i + 1}', Rect.fromLTWH(x, y, 44, 44), 26, navy);
        if (i < 6) {
          c.drawLine(
            Offset(x + 46, y + 22),
            Offset(x + 54, y + 22),
            Paint()
              ..color = navy
              ..strokeWidth = 3,
          );
        }
      }
      _text(c, 'UTF-8 → U+ → cmap → shape → outline → raster → pixels', Rect.fromLTWH(p.left + 14, p.top + 196, p.width - 28, 30), 20, const Color(0xFF2E6DA8));
      _text(c, '名前の街 · NAME CITY', Rect.fromLTWH(p.left + 14, p.top + 244, p.width - 28, 36), 24, navy);
    }
    // The decoder's panel.
    final dp = _decoderPanel;
    c.drawRect(dp, Paint()..color = glow ? black : const Color(0xFF0E1A2B));
    _text(c, 'UTF-8  →  U+', dp.deflate(10), 40, glow ? const Color(0xFF3A8F6A) : BP.green);
    // The rasterizer's screen.
    final s = _screen;
    c.drawRect(s, Paint()..color = const Color(0xFF0E1A2B));
    _text(c, 'SCAN', Rect.fromLTWH(s.left + 10, s.top + 10, s.width - 20, 40), 34, const Color(0xFF6CE5B1));
    c.drawRect(Rect.fromLTWH(s.left + 14, s.top + 62, s.width - 28, 16), Paint()..color = const Color(0xFF2A3A55));
    // The plate under the pixels: a fine grid.
    final g = _plateGrid;
    c.drawRect(g, Paint()..color = glow ? black : const Color(0xFF0E1A2B));
    if (!glow) {
      final line = Paint()
        ..color = const Color(0xFF2A3A55)
        ..strokeWidth = 2;
      for (var k = 0; k <= 16; k++) {
        final v = g.left + k * g.width / 16;
        c.drawLine(Offset(v, g.top), Offset(v, g.bottom), line);
        c.drawLine(Offset(g.left, g.top + k * g.height / 16), Offset(g.right, g.top + k * g.height / 16), line);
      }
    }
    // The stick's ruler: em in tenths, every half and whole em longer.
    final ru = _ruler;
    c.drawRect(ru, Paint()..color = glow ? black : const Color(0xFFE6DED0));
    if (!glow) {
      final tick = Paint()
        ..color = navy
        ..strokeWidth = 2;
      final perEm = ru.width / (_stickEm + 0.2);
      for (var k = 0; k <= (_stickEm * 10).floor(); k++) {
        final x = ru.left + perEm * 0.1 + k * perEm / 10;
        final len = k % 10 == 0 ? 30.0 : (k % 5 == 0 ? 20.0 : 11.0);
        c.drawLine(Offset(x, ru.top), Offset(x, ru.top + len), tick);
      }
    }
  }

  void _text(Canvas c, String s, Rect box, double size, Color color, {List<TextSpan>? spans, bool sample = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: spans == null ? s : null,
        children: spans,
        style: sample
            ? TextStyle(fontFamily: BP.display, fontFamilyFallback: const [BP.arabic], fontSize: size, color: color, locale: const Locale('ja'))
            : TextStyle(
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
    )..layout(maxWidth: box.width * 3);
    final k = math.min(1.0, math.min(box.width * 0.96 / tp.width, box.height / tp.height));
    c.save();
    c.translate(box.center.dx, box.center.dy);
    c.scale(k);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }
}

/// One letter's way down the line: when each step starts ([at] 0 the
/// bytes … 6 the board), when its work there is done ([end]; it waits
/// there until the next step's start) and when its pixels land ([at] 7);
/// its maker, when they set off for the feeder and when they're back home.
class _Steps {
  _Steps(this.k, this.maker);
  final int k, maker;
  final at = Float64List(8), end = Float64List(7);
  double walkIn = 0, homeAt = 0;

  /// Its maker's walks (see [GlyphWorks._walksOf]), and where on the board
  /// they were made for.
  Walk? toFeeder, toBoard, toHome;
  double slotX = double.nan;

  /// The step it's at, at [t]: −1 before, 7 once on the board.
  int stepAt(double t) {
    if (t < at[0]) return -1;
    for (var s = 0; s < 7; s++) {
      if (t < at[s + 1]) return s;
    }
    return 7;
  }
}

/// A letter followed all the way down the line: when it's at each step
/// (as [_Steps.at]/[_Steps.end]; [at] 7: on the board), and the camera's
/// stretches with it (from, to, and whether it opens on the works' front).
class _Journey {
  _Journey(this.k);
  final int k;
  final at = Float64List(8), end = Float64List(7);
  final stretches = <(double, double, bool)>[];
}

/// A camera visit: from, to, the step it comes for and the letter.
class _Cut {
  _Cut(this.from, this.to, this.step, this.k);
  final double from, to;
  final int step, k;
}

/// What the works makes for one name: its atlas and material, each letter's
/// pieces, the board's size, the grid's cell.
class _Job {
  _Job(WorksName name) : pieces = [for (var k = 0; k < name.letters.length; k++) _Piece()];

  _Atlas? atlas;
  PhysicallyBasedMaterial? mat;
  final List<_Piece> pieces;
  final nodes = <Node>[];
  Mesh? stripMesh;

  /// The plate's cell, the board's pixel and size (once rendered), and the
  /// board's coverage so far.
  double cell = 0, px = 0.02;
  double? boardW, boardH;
  Float32List? cover;

  void dispose() {
    for (final n in nodes) {
      n.parent?.remove(n);
    }
    nodes.clear();
  }
}

/// One letter's things on the line: its row of crates, its code point
/// tile(s), its sort, the decoder's display of it, its wire.
class _Piece {
  Node? crates, tile, sort, wire;
  Mesh? display, wireFull;
  _Flip? chunks;
  _Wire? wireData;
  double crate = 0.085, rowW = 0, tileW = 0;

  void hideAll() {
    for (final n in [crates, tile, sort, wire]) {
      n?.visible = false;
    }
  }
}

/// A letter's outline as wire, in a leaning frame's metres: closed loops,
/// their lengths.
class _Wire {
  _Wire(this.loops) {
    for (final p in loops) {
      var l = 0.0;
      final n = p.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        l += math.sqrt(math.pow(p[2 * j] - p[2 * i], 2) + math.pow(p[2 * j + 1] - p[2 * i + 1], 2));
      }
      lengths.add(l);
      total += l;
    }
  }

  final List<Float32List> loops;
  final lengths = <double>[];
  double total = 0;

  /// The point [f] (0..1) of the way along the wire, into [out] (z 0).
  vm.Vector3 at(double f, vm.Vector3 out) {
    var d = f * total;
    for (var k = 0; k < loops.length; k++) {
      if (d > lengths[k] && k + 1 < loops.length) {
        d -= lengths[k];
        continue;
      }
      final p = loops[k];
      final n = p.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final l = math.sqrt(math.pow(p[2 * j] - p[2 * i], 2) + math.pow(p[2 * j + 1] - p[2 * i + 1], 2));
        if (d <= l || i == n - 1) {
          final u = l > 0 ? c01(d / l) : 0.0;
          return out..setValues(lerp(p[2 * i], p[2 * j], u), lerp(p[2 * i + 1], p[2 * j + 1], u), 0);
        }
        d -= l;
      }
    }
    return out..setValues(0, 0, 0);
  }

  /// The wire from [f0] to [f1] of the way along as a four-sided tube of
  /// radius [r] at depth [z] (null if there's none of it).
  MeshData? tube(double f0, double f1, double r, double z) {
    final pos = <double>[], nor = <double>[], idx = <int>[];
    var from = f0 * total, to = f1 * total, at = 0.0;
    for (var k = 0; k < loops.length; k++) {
      final p = loops[k], n = p.length ~/ 2;
      // This loop's piece of [from, to): its points.
      final run = <double>[];
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final ax = p[2 * i], ay = p[2 * i + 1], bx = p[2 * j], by = p[2 * j + 1];
        final l = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
        final s0 = math.max(from, at), s1 = math.min(to, at + l);
        if (s1 > s0 && l > 0) {
          final u0 = (s0 - at) / l, u1 = (s1 - at) / l;
          if (run.isEmpty) run.addAll([lerp(ax, bx, u0), lerp(ay, by, u0)]);
          run.addAll([lerp(ax, bx, u1), lerp(ay, by, u1)]);
        }
        at += l;
      }
      if (run.length >= 4) _ring(run, r, z, pos, nor, idx);
    }
    if (pos.isEmpty) return null;
    final v = pos.length ~/ 3;
    return MeshData(
      positions: Float32List.fromList(pos),
      vertexCount: v,
      normals: Float32List.fromList(nor),
      texCoords: Float32List(v * 2),
      colors: Float32List(v * 4)..fillRange(0, v * 4, 1),
      indices: idx,
    );
  }

  /// A tube along the open polyline [run] (x, y pairs): four vertices
  /// round each point (in the plane and out of it), four quads between.
  static void _ring(List<double> run, double r, double z, List<double> pos, List<double> nor, List<int> idx) {
    final n = run.length ~/ 2;
    final base = pos.length ~/ 3;
    for (var i = 0; i < n; i++) {
      final a = math.max(0, i - 1), b = math.min(n - 1, i + 1);
      var tx = run[2 * b] - run[2 * a], ty = run[2 * b + 1] - run[2 * a + 1];
      final l = math.sqrt(tx * tx + ty * ty);
      if (l > 0) {
        tx /= l;
        ty /= l;
      }
      final nx = -ty, ny = tx;
      final x = run[2 * i], y = run[2 * i + 1];
      for (final (ox, oy, oz) in [(nx, ny, 0.0), (0.0, 0.0, -1.0), (-nx, -ny, 0.0), (0.0, 0.0, 1.0)]) {
        pos.addAll([x + ox * r, y + oy * r, z + oz * r]);
        nor.addAll([ox, oy, oz]);
      }
    }
    for (var i = 0; i + 1 < n; i++) {
      for (var s = 0; s < 4; s++) {
        final a = base + i * 4 + s, b = base + i * 4 + (s + 1) % 4, c = base + (i + 1) * 4 + (s + 1) % 4, d = base + (i + 1) * 4 + s;
        // Wound to face out (the side's normal).
        final ax = pos[a * 3], ay = pos[a * 3 + 1], az = pos[a * 3 + 2];
        final ux = pos[b * 3] - ax, uy = pos[b * 3 + 1] - ay, uz = pos[b * 3 + 2] - az;
        final vx = pos[c * 3] - ax, vy = pos[c * 3 + 1] - ay, vz = pos[c * 3 + 2] - az;
        final cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
        final mx = nor[a * 3] + nor[b * 3] + nor[c * 3] + nor[d * 3];
        final my = nor[a * 3 + 1] + nor[b * 3 + 1] + nor[c * 3 + 1] + nor[d * 3 + 1];
        final mz = nor[a * 3 + 2] + nor[b * 3 + 2] + nor[c * 3 + 2] + nor[d * 3 + 2];
        if (cx * mx + cy * my + cz * mz >= 0) {
          idx.addAll([a, b, c, a, c, d]);
        } else {
          idx.addAll([a, c, b, a, d, c]);
        }
      }
    }
  }
}

/// Where a name's things are painted in its atlas: the string (each
/// grapheme's characters over its bytes), the sorts' faces (each glyph in
/// its advance box), the crates' bytes, the tiles' code points, the
/// decoder's display of each letter.
class _Atlas {
  _Atlas(this.name) {
    // The faces: the glyph in its line box (advance × 1.2 em), packed in rows.
    var x = 4.0, y = _facesTop;
    for (final l in name.letters) {
      final w = math.max(4.0, l.advance * _faceEm);
      if (x + w > size - 4) {
        x = 4;
        y += _faceEm * 1.2 + 6;
      }
      faces.add(Rect.fromLTWH(x, y, w, _faceEm * 1.2));
      x += w + 6;
    }
    // (A name of more bytes or code points than there are cells shares the
    // last ones: labels go wrong rather than anything breaking.)
    var b = 0, cp = 0;
    for (final l in name.letters) {
      bytes.add([for (var i = 0; i < l.bytes.length; i++) _cell(_bytesTop, 60, 44, 16, math.min(b++, 63))]);
      codes.add([for (var i = 0; i < l.codePoints.length; i++) _cell(_codesTop, 164, 44, 6, math.min(cp++, 23))]);
      displays.add(_cell(_displaysTop, 164, 40, 6, math.min(l.k, 17)));
    }
    _layOutString();
  }

  final WorksName name;
  static const size = 1024, stripH = 128.0;
  static const _faceEm = 84.0, _facesTop = 136.0, _bytesTop = 470.0, _codesTop = 668.0, _displaysTop = 864.0;
  static const plain = Rect.fromLTWH(1004, 1004, 16, 16);

  final faces = <Rect>[], displays = <Rect>[];
  final bytes = <List<Rect>>[], codes = <List<Rect>>[];
  static const strip = Rect.fromLTWH(0, 0, 1024, stripH);

  /// Each grapheme's place on the string board, and each letter's.
  final _groups = <Rect>[];
  final letterGroup = <Rect?>[];
  double _scale = 1;

  static Rect _cell(double top, double w, double h, int perRow, int i) => Rect.fromLTWH(2 + (i % perRow) * (w + 4), top + (i ~/ perRow) * (h + 4), w, h);

  static TextStyle _mono(double size, Color color) =>
      TextStyle(fontFamily: BP.mono, fontSize: size, color: color, fontWeight: FontWeight.w700, fontVariations: const [FontVariation('wght', 700)]);

  /// The string's sizes for each grapheme's character and its bytes (before
  /// [_scale]), and the height they need together.
  static const _charPx = 34.0, _bytePx = 22.0, _groupH = 72.0;

  /// The string: each grapheme's character over its bytes, in as few rows
  /// as fit (three at most), as large as fit.
  void _layOutString() {
    final widths = [
      for (final g in name.string)
        () {
          final a = TextPainter(
            text: TextSpan(text: g.text, style: NameRaster.nameStyle(_charPx)),
            textDirection: TextDirection.ltr,
          )..layout();
          final b = TextPainter(
            text: TextSpan(text: g.bytes.map(WorksLetter.byte).join(' '), style: _mono(_bytePx, const Color(0xFFFFFFFF))),
            textDirection: TextDirection.ltr,
          )..layout();
          final w = math.max(a.width, b.width) + 18;
          a.dispose();
          b.dispose();
          return w;
        }(),
    ];
    final total = widths.fold(0.0, (a, b) => a + b);
    final rows = total <= 1000 ? 1 : (total <= 2100 ? 2 : 3);
    // Rows of about equal width.
    final target = total / rows;
    final rowOf = <int>[];
    var row = 0, acc = 0.0;
    for (final w in widths) {
      if (acc > 0 && acc + w / 2 > target && row + 1 < rows) {
        row++;
        acc = 0;
      }
      rowOf.add(row);
      acc += w;
    }
    final rowW = List.filled(rows, 0.0);
    for (var i = 0; i < widths.length; i++) {
      rowW[rowOf[i]] += widths[i];
    }
    final rowH = (stripH - 8) / rows;
    _scale = math.min(1000 / rowW.reduce(math.max), rowH / _groupH).clamp(0.2, 1.7);
    final x = [for (final w in rowW) (size - w * _scale) / 2];
    for (var i = 0; i < widths.length; i++) {
      final r = rowOf[i];
      _groups.add(Rect.fromLTWH(x[r], 4 + r * rowH, widths[i] * _scale, rowH));
      x[r] += widths[i] * _scale;
    }
    for (var k = 0; k < name.letters.length; k++) {
      Rect? r;
      for (var i = 0; i < name.string.length; i++) {
        if (name.string[i].letter == k) r = _groups[i];
      }
      letterGroup.add(r);
    }
  }

  void paint(Canvas c) {
    const ground = Color(0xFF0E1A2B), cream = Color(0xFFF4F1EA), amber = Color(0xFFFFC66D), dim = Color(0xFF5E7A99);
    c.drawRect(const Rect.fromLTWH(0, 0, size + 0.0, size + 0.0), Paint()..color = ground);
    c.drawRect(plain, Paint()..color = const Color(0xFFFFFFFF));
    // The string: each grapheme over its bytes (spaces dim: no glyph to
    // make), a rule between graphemes.
    final rule = Paint()
      ..color = const Color(0xFF2A3A55)
      ..strokeWidth = 2;
    for (var i = 0; i < name.string.length; i++) {
      final g = name.string[i], r = _groups[i];
      final ch = TextPainter(
        text: TextSpan(
          text: g.text,
          style: NameRaster.nameStyle(_charPx * _scale, color: g.letter == null ? dim : cream),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = r.top + (r.height - _groupH * _scale) / 2;
      ch.paint(c, Offset(r.center.dx - ch.width / 2, top));
      final b = TextPainter(
        text: TextSpan(text: g.bytes.map(WorksLetter.byte).join(' '), style: _mono(_bytePx * _scale, g.letter == null ? dim : amber)),
        textDirection: TextDirection.ltr,
      )..layout();
      b.paint(c, Offset(r.center.dx - b.width / 2, top + _groupH * _scale - b.height));
      ch.dispose();
      b.dispose();
      if (i > 0 && (r.left - _groups[i - 1].right).abs() < 1) c.drawLine(Offset(r.left, r.top + 10), Offset(r.left, r.bottom - 10), rule);
    }
    // The faces: each glyph in its advance box, as the text stack draws it.
    for (final l in name.letters) {
      final r = faces[l.k];
      c.drawRect(r, Paint()..color = const Color(0xFF3A4558));
      final tp = TextPainter(
        text: TextSpan(
          text: l.text,
          style: NameRaster.nameStyle(_faceEm, color: const Color(0xFFFFE9B0)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, r.topLeft);
      tp.dispose();
    }
    // The crates' bytes, the tiles' code points, the decoder's display.
    for (final l in name.letters) {
      for (var i = 0; i < l.bytes.length; i++) {
        _label(c, bytes[l.k][i], WorksLetter.byte(l.bytes[i]), const Color(0xFFD9B48A), const Color(0xFF1B2233), 30);
      }
      for (var i = 0; i < l.codePoints.length; i++) {
        _label(c, codes[l.k][i], WorksLetter.hex(l.codePoints[i]), const Color(0xFF1B2A44), amber, 28);
      }
      _label(
        c,
        displays[l.k],
        '${l.bytes.map(WorksLetter.byte).join(' ')} → ${l.codePoints.map(WorksLetter.hex).join(' ')}',
        ground,
        const Color(0xFF6CE5B1),
        22,
      );
    }
  }

  static void _label(Canvas c, Rect r, String s, Color ground, Color ink, double px) {
    c.drawRect(r, Paint()..color = ground);
    final tp = TextPainter(
      text: TextSpan(text: s, style: _mono(px, ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    final k = math.min(1.0, (r.width - 6) / tp.width);
    c.save();
    c.translate(r.center.dx, r.center.dy);
    c.scale(k);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    tp.dispose();
  }
}

/// Two meshes over the same geometry, so a change of which primitives show
/// takes effect: the engine keeps what a node's mesh had when it was
/// assigned, and only takes up changes when another mesh over the same
/// geometry is assigned. Set up [spare], then [show] it.
class _Flip {
  _Flip(List<Geometry> geos, Material m) : shown = _mesh(geos, m), _spare = _mesh(geos, m);

  Mesh shown, _spare;

  static Mesh _mesh(List<Geometry> geos, Material m) => Mesh.primitives(primitives: [for (final g in geos) MeshPrimitive(g, m)..castsShadow = false]);

  List<MeshPrimitive> get spare => _spare.primitives;

  void show(Node node) {
    node.mesh = _spare;
    final t = shown;
    shown = _spare;
    _spare = t;
  }
}
