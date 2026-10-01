import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, FontWeight, FontVariation, Locale, Paint, PaintingStyle, RRect, Radius, Rect;

import 'package:flutter/painting.dart' show Canvas, Offset, TextAlign, TextDirection, TextPainter, TextSpan, TextStyle;
import 'package:flutter_scene/scene.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/web_fonts.dart';
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

/// Where the Glyph Works stands (world units): the plaza's left-rear corner,
/// behind the smoking corner, open to the front (−z, the sun's side).
abstract final class WorksLayout {
  static const x0 = -16.75, x1 = -10.55, z0 = 4.6, z1 = 7.75;
  static const cx = (x0 + x1) / 2;

  /// The roof, and the top of the open front (the sign board above it).
  static const roof = 3.0, open = 2.45;

  /// The three benches (the printer, the casting bench, the mill), their
  /// tops, and where each station's maker stands: behind it, facing out.
  static const stationX = [cx - 2.1, cx, cx + 2.1];
  static const benchY = 0.55, benchZ = 6.6, benchW = 1.2, benchD = 0.6;
  static const makerZ = 7.3;

  /// The walkways between the benches, to the front.
  static const gaps = [cx - 1.05, cx + 1.05];

  /// The display table at the front, the tray on it, and where a maker
  /// stands to put a letter on the tray (behind the table).
  static const tableX = cx + 0.3, tableZ = 5.2, tableY = 0.5, tableW = 2.5, tableD = 0.45;
  static const trayY = tableY + 0.045, trayZ = tableZ + 0.04, placeZ = 5.8;

  /// Where the front's middle is (for the walk out with the tray).
  static final door = vm.Vector3(cx + 1.4, 0, z0 - 0.3);
}

/// What the works needs of one of the name's smooth letters (made by the site
/// for the reveal): its geometry (whole, and cut into bands bottom-up), the
/// top of each band above its foot, its foot on the wall (ink bottom-centre)
/// and its ink size. Full size; the works scales it down.
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

/// 文字工場 · Glyph Works: while the crew build the name in bricks, three
/// makers craft a mini name in gold, a letter for each letter, in step with
/// it — mini letter k is made while big letter k is laid, by each station in
/// turn: printed layer by layer, cast (the mold glows as the metal goes in,
/// opens, the letter cools from orange to gold), or milled out of a brass
/// block (chips flying). Each finished letter is carried to the display tray
/// at the front, where the name comes together at its real (kerned) places,
/// scaled down. Now and then the camera cuts over for a few seconds.
///
/// The building and its benches are one merged mesh (and the roof another),
/// the moving parts come from the site's [PropPool], the mini letters reuse
/// the job's smooth letter meshes (scaled nodes, gold). The finale
/// (photo_op.dart) carries the tray to the site ([held]). Everything is a
/// pure function of scene time, planned once per build.
class GlyphWorks {
  GlyphWorks(this.scene, this.crew, this.fx, this.props);

  final Scene scene;
  final Crew3D crew;
  final Fx3D fx;
  final PropPool props;

  PhysicallyBasedMaterial? _mat;
  late final PhysicallyBasedMaterial _gold, _fresh, _hot;

  /// Where the tray is this frame when it's not on the display table (the
  /// finale carries it): its top's middle and its turn (yaw, as a figure's).
  /// Set before [update]; cleared by it.
  ({vm.Vector3 at, double yaw})? held;

  /// Makers the finale poses this frame (bit i: maker i); [update] leaves them.
  int finaleMakers = 0;

  void init() {
    _gold = pbr(_goldBase, metallic: 0.6, roughness: 0.3, emissive: lin(const Color(0xFFE89B2E)), emissiveStrength: 0.2);
    _fresh = pbr(lin(const Color(0xFFFFE6A8)), metallic: 0.2, roughness: 0.45, emissive: lin(BP.amber), emissiveStrength: 2.6);
    _hot = pbr(rgb(1, 0.5, 0.18), metallic: 0.4, roughness: 0.5, emissive: rgb(1, 0.3, 0.05), emissiveStrength: 5);
    _build();
  }

  // ── Per build ─────────────────────────────────────────────────────────────

  BuildPlan? _plan;
  final _minis = <_Mini>[];
  final _cuts = <_Cut>[];

  /// The mini name's scale (of the wall), and the tray's length.
  double scale = 0.05, trayLen = 1.2;

  /// When the camera cuts over to the works (the breaks keep clear).
  final camWindows = <(double, double)>[];

  /// When the last mini letter is on the tray (null before a plan).
  double? get trayDone => _minis.isEmpty ? null : _minis.map((m) => m.place).reduce(math.max);

  /// The mini name's height and its foot on the tray: its letters stand at
  /// their places on the wall, scaled.
  double get nameHeight => (_plan?.height ?? 4) * scale;

  /// Seconds each station gets ready before its letter (closing the mold,
  /// setting the block…), and how long a letter cools before it's picked up.
  static const _setup = [1.0, 1.6, 1.3], _cool = [1.4, 2.4, 1.5];
  static const _carry = 1.1, _walk = 1.35;

  /// Plans the build's mini letters and the camera's visits (once, when its
  /// plan is ready), keeping clear of [busyCam] (the deliveries' shots) and
  /// the kerning close-ups.
  void planFor(BuildPlan plan, {List<(double, double)> busyCam = const []}) {
    _plan = plan;
    _clear();
    final sc = plan.sched;
    scale = math.min(0.3 / plan.height, 1.5 / plan.width);
    trayLen = math.max(0.9, plan.width * scale + 0.3);
    for (var k = 0; k < plan.letterCount; k++) {
      final l = plan.letters.letters[k];
      final m = _Mini(k, k % 3, l.glyph);
      final a = plan.at(sc.layA[k]), d = plan.at(sc.layB[k]) - a;
      m
        ..slotX = ((l.col0 + l.col1 + 1) / 2 - plan.r.cols / 2) * plan.b * scale
        ..a = a
        ..e = a + math.max(0.7 * d, math.min(3.2, d + 1.2))
        ..setup = a - _setup[m.method];
      m.pick = m.e + _cool[m.method];
      m.path = _carryPath(m);
      m.back = m.path.reversed.toList();
      m.place = m.pick + 0.4 + _length(m.path) / _carry;
      m.home = m.place + 0.5 + _length(m.path) / _walk;
      _minis.add(m);
    }
    _planCuts(plan, busyCam);
    if (const String.fromEnvironment('BOOTH3D_TIMES') == '') return;
    String f(double v) => v.toStringAsFixed(1);
    // ignore: avoid_print
    print(
      'PLAN works scale=${scale.toStringAsFixed(3)} tray=${trayLen.toStringAsFixed(2)} ${[
        for (final m in _minis) '${plan.letters.letters[m.k].text}:${const ['print', 'cast', 'mill'][m.method]} ${f(m.a)}-${f(m.e)} on tray ${f(m.place)}',
      ].join(', ')}',
    );
    for (final c in _cuts) {
      // ignore: avoid_print
      print('PLAN works cut ${f(c.from)}-${f(c.to)} ${c.kind.name} ${plan.letters.letters[c.k].text}');
    }
  }

  /// The maker's way from their station to the letter's place on the tray
  /// (on the display table): round the bench, through the gap, along the
  /// front.
  List<vm.Vector3> _carryPath(_Mini m) {
    final sx = WorksLayout.stationX[m.method], tx = WorksLayout.tableX + m.slotX;
    final gap = m.method == 0
        ? WorksLayout.gaps[0]
        : (m.method == 2 ? WorksLayout.gaps[1] : ((tx < WorksLayout.cx) ? WorksLayout.gaps[0] : WorksLayout.gaps[1]));
    return [
      vm.Vector3(sx, 0, WorksLayout.makerZ),
      vm.Vector3(gap, 0, WorksLayout.makerZ),
      vm.Vector3(gap, 0, WorksLayout.placeZ),
      vm.Vector3(tx, 0, WorksLayout.placeZ),
    ];
  }

  static double _length(List<vm.Vector3> pts) {
    var l = 0.0;
    for (var i = 0; i + 1 < pts.length; i++) {
      l += pts[i].distanceTo(pts[i + 1]);
    }
    return l;
  }

  // ── The camera's visits ───────────────────────────────────────────────────

  /// Picks the moments to cut over: 7.5 s (at least 5.5) at a time, every
  /// half a minute or so, never near a kerning close-up or the deliveries'
  /// shots, each on something happening — a letter finished (best), one
  /// set on the tray, one started — a different station each time when
  /// there's a choice. A visit opens on the whole works for a moment, then
  /// moves in, so the moment comes a few seconds in.
  void _planCuts(BuildPlan plan, List<(double, double)> busyCam) {
    _cuts.clear();
    camWindows.clear();
    final s = plan.job.serial;
    // (A kerning close-up eases in from 0.7–1.1 s before its step and out
    // by 0.6 s after.)
    final busy = [
      for (final st in plan.steps)
        if (st != null) (st.a - 1.5, st.e + 1.0),
      for (final (a, e) in busyCam) (a - 2.0, e + 2.0),
    ];
    final first = plan.t0 + 12, last = plan.t0 + plan.len - 1.0;
    bool clear(double a, double e) => busy.every((r) => e <= r.$1 + 1e-6 || a >= r.$2 - 1e-6);
    // Each candidate: the best window around one event.
    final cands = <_Cut>[];
    for (final m in _minis) {
      for (final (kind, at) in [(_Moment.finish, m.e), (_Moment.place, m.place), (_Moment.start, m.a)]) {
        final start = kind == _Moment.start;
        for (final lead in start ? const [3.0, 2.2, 4.0, 1.5] : const [4.6, 4.0, 5.2, 3.6]) {
          final a = at - lead;
          if (a < first) continue;
          var e = a + 7.5;
          for (final r in busy) {
            if (r.$1 >= a + 5.5 - 1e-6) e = math.min(e, r.$1);
          }
          e = math.min(e, last);
          if (e - a < 5.5 - 1e-6 || !clear(a, e) || at > e - (start ? 2.5 : 1.0)) continue;
          cands.add(_Cut(a, e, kind, m.k));
          break;
        }
      }
    }
    cands.sort((x, y) => x.from.compareTo(y.from));
    var next = plan.t0 + 12 + 6 * rnd(s, 61);
    var lastMethod = -1;
    while (true) {
      final open = cands.where((c) => c.from >= next).toList();
      if (open.isEmpty) break;
      // Of those starting soon, the best moment, not the station just seen.
      final soon = open.where((c) => c.from < open.first.from + 16).toList()
        ..sort((x, y) {
          double score(_Cut c) => c.kind.weight - (_minis[c.k].method == lastMethod ? 0.8 : 0);
          final d = score(y).compareTo(score(x));
          return d != 0 ? d : x.from.compareTo(y.from);
        });
      final pick = soon.first;
      _cuts.add(pick);
      camWindows.add((pick.from, pick.to));
      lastMethod = _minis[pick.k].method;
      next = pick.to + 24 + 14 * rnd(_cuts.length, s, 62);
    }
  }

  /// The camera's request at [t] (priority 2, a cut): the works' front for a
  /// moment, then in on the station (or the tray) where it happens.
  void focus(List<Focus> out, double t) {
    final plan = _plan;
    if (plan == null || plan.job.phase != Phase.build || plan.job.cutAt != null) return;
    if (out.any((f) => f.priority >= 2)) return;
    for (final c in _cuts) {
      if (t < c.from || t >= c.to) continue;
      final u = t - c.from;
      final m = _minis[c.k];
      final onTray = c.kind == _Moment.place;
      // Into the front, past the sign; then the station (or the tray).
      final sx = onTray ? WorksLayout.tableX + m.slotX : WorksLayout.stationX[m.method];
      final drift = 0.25 * seg(u, 1.5, c.to - c.from);
      // Looking in through the open front (not past its corner posts).
      final ex = math.min(sx + 1.25, WorksLayout.x1 - 0.55) - drift;
      final Shot shot;
      if (u < 1.8) {
        // The whole works, its sign over the open front.
        shot = Shot(vm.Vector3(WorksLayout.cx + 0.6, 1.9, WorksLayout.z0 - 5.2), vm.Vector3(WorksLayout.cx - 0.9, 2.1, 6.0), fov: 52, settle: 0.6, drift: 0.4);
      } else if (onTray) {
        shot = Shot(
          vm.Vector3(ex, 1.55, WorksLayout.trayZ - 2.5 + drift),
          vm.Vector3(sx - 0.1, 0.72, WorksLayout.trayZ + 0.6),
          fov: 36,
          settle: 1.4,
          drift: 0.35,
        );
      } else {
        final close = m.method == 2 ? 2.9 : 3.3;
        shot = Shot(
          vm.Vector3(ex, 1.75, WorksLayout.benchZ - close + drift),
          vm.Vector3(sx - 0.05, WorksLayout.benchY + 0.32, WorksLayout.benchZ + 0.05),
          fov: 36,
          settle: 1.4,
          drift: 0.35,
        );
      }
      out.add(Focus('works ${c.from.toStringAsFixed(1)}', shot, priority: 2, cut: true));
      return;
    }
  }

  // ── Per frame ─────────────────────────────────────────────────────────────

  /// When the works stopped (a sample cut short), or infinity.
  double _stop = double.infinity;
  final _p = vm.Vector3.zero(), _q = vm.Vector3.zero(), _r = vm.Vector3.zero();

  /// Poses the makers and the mini letters for [j] at [t] ([plan]: the
  /// build's plan, if ready; [shapes]: the job's smooth letters made so far).
  void update(Job j, BuildPlan? plan, double t, double night, List<LetterShape> shapes) {
    _mat?.emissiveStrength = 0.5 + 2.2 * smooth(0.1, 0.5, night);
    _gold.emissiveStrength = 0.2 + 0.5 * smooth(0.2, 0.6, night);
    final current = plan != null && identical(plan, _plan);
    if (!current && _plan != null) {
      _clear();
      _cuts.clear();
      camWindows.clear();
      _plan = null;
    }
    // Make the mini letters as their smooth letters appear.
    for (final m in _minis) {
      if (m.node != null) continue;
      for (final s in shapes) {
        if (s.glyph == m.glyph) _make(m, s);
      }
    }
    // A sample cut short: the works stops; what's on the tray stays there,
    // the rest is put away and the makers stand about.
    final pl = _plan;
    final cutT = pl != null && j.cutAt != null && j.phase.index >= Phase.demolish.index ? math.min(t, pl.t0 + (j.cutFrac ?? 0) * pl.len) : null;
    final stopped = cutT != null;
    final tt = cutT ?? t;
    _stop = cutT ?? double.infinity;
    for (var i = 0; i < 3; i++) {
      if (finaleMakers & (1 << i) != 0) continue;
      if (stopped) {
        final p = crew.poses[Crew3D.makers + i]..rest();
        p.pos.setValues(WorksLayout.stationX[i], 0, WorksLayout.makerZ);
        OffDuty.stand(p, t, 40 + i * 7);
        _idle(p, i, t);
      } else {
        _poseMaker(i, tt, t);
      }
    }
    _stations(tt, t);
    for (final m in _minis) {
      _place(m, tt, t, stopped);
    }
    _tray();
    held = null;
    finaleMakers = 0;
  }

  /// Drops the last name's mini letters.
  void _clear() {
    for (final m in _minis) {
      if (m.node case final n?) scene.remove(n);
    }
    _minis.clear();
  }

  void _make(_Mini m, LetterShape s) {
    m
      ..shape = s
      ..full = _Flip([s.geometry], _gold)
      ..bands = s.bands.isEmpty ? null : _Flip(s.bands, _gold);
    m.node = Node(name: 'mini ${m.k}', mesh: m.full!.shown)
      ..castsShadows = false
      ..visible = false;
    scene.add(m.node!);
  }

  /// The tray: on the display table, or wherever the finale has it.
  ({vm.Vector3 at, double yaw}) get _trayPose => held ?? _onTable;
  static final _onTable = (at: vm.Vector3(WorksLayout.tableX, WorksLayout.trayY, WorksLayout.trayZ), yaw: 0.0);

  /// Tray-local (x along it, y up, z across) into world [out].
  vm.Vector3 _onTray(double x, double y, double z, vm.Vector3 out) {
    final pose = _trayPose;
    final c = math.cos(pose.yaw), s = math.sin(pose.yaw);
    return out..setValues(pose.at.x + x * c + z * s, pose.at.y + y, pose.at.z - x * s + z * c);
  }

  static final _wood = v4(hex3(0x2A3344)), _trim = v4(hex3(0xE9B949)), _peg = v4(hex3(0x1B2233));

  void _tray() {
    if (_plan == null) return;
    final pose = _trayPose;
    _onTray(0, -0.022, 0, _p);
    props.box(_p.x, _p.y, _p.z, trayLen, 0.04, 0.3, _wood, yaw: pose.yaw);
    for (final side in const [-1.0, 1.0]) {
      _onTray(0, -0.005, side * 0.148, _p);
      props.box(_p.x, _p.y, _p.z, trayLen + 0.02, 0.018, 0.012, _trim, yaw: pose.yaw);
    }
  }

  // ── The mini letters ──────────────────────────────────────────────────────

  /// Where mini letter [m] is at [tt] (the works' clock, stopped by a cut):
  /// not started, at its station, in its maker's hands, or on the tray.
  void _place(_Mini m, double tt, double t, bool stopped) {
    final node = m.node, shape = m.shape;
    if (node == null || shape == null) return;
    final s = scale;
    final placed = tt >= m.place;
    if (stopped && !placed) {
      node.visible = false;
      return;
    }
    node.visible = tt >= m.setup;
    if (!node.visible) return;
    if (placed) {
      _wear(node, m.full!, _gold);
      final pose = _trayPose;
      final foot = shape.at.y * s;
      _onTray(m.slotX, foot, 0, _p);
      node.place((x) => setTrs(x, _p.x, _p.y, _p.z, yaw: pose.yaw, s: s));
      // A little skid under a letter that sits above the tray (a baseline
      // above a descender's foot).
      if (foot > 0.012) {
        _onTray(m.slotX, foot / 2, 0, _q);
        props.box(_q.x, _q.y, _q.z, math.max(0.02, shape.width * s * 0.5), foot, 0.03, _peg, yaw: pose.yaw);
      }
      return;
    }
    if (tt >= m.pick) {
      // In the maker's hands, upright, facing where they go.
      final p = crew.poses[Crew3D.makers + m.method];
      OffDuty.hand(p, 0, _p);
      OffDuty.hand(p, 1, _q);
      final dx = -math.sin(p.yaw), dz = -math.cos(p.yaw);
      final x = (_p.x + _q.x) / 2 + dx * 0.03, z = (_p.z + _q.z) / 2 + dz * 0.03;
      final y = (_p.y + _q.y) / 2 - shape.height * s * 0.4;
      _wear(node, m.full!, _gold);
      node.place((x0) => setTrs(x0, x, y, z, yaw: p.yaw, s: s));
      return;
    }
    // At its station.
    final at = _stationFoot(m.method, _r);
    node.place((x) => setTrs(x, at.x, at.y, at.z, s: s));
    switch (m.method) {
      case 0:
        // Printed: the bands appear bottom-up, the newest still glowing.
        final bands = m.bands;
        if (bands == null || tt >= m.e) {
          _wear(node, m.full!, _gold);
          break;
        }
        final spare = bands.spare;
        final f = seg(tt, m.a, m.e) * spare.length;
        for (var k = 0; k < spare.length; k++) {
          spare[k]
            ..visible = k < f
            ..material = k + 1 >= f ? _fresh : _gold;
        }
        bands.show(node);
      case 1:
        // Cast: hidden in the mold until it opens, then cooling.
        node.visible = tt >= m.e - 0.35;
        final cool = seg(tt, m.e - 0.2, m.e + 2.3);
        _wear(node, m.full!, cool < 1 ? _hot : _gold);
        if (cool < 1) {
          _hot
            ..emissiveStrength = 5.5 * math.pow(1 - cool, 1.4).toDouble()
            ..baseColorFactor = _hotBase + (_goldBase - _hotBase) * eio(cool)
            ..emissiveFactor = _hotGlow + (_hotEnd - _hotGlow) * cool;
        }
      default:
        // Milled out of its block (drawn by the station).
        _wear(node, m.full!, _gold);
    }
  }

  /// Shows [f]'s meshes on [node], all in [mat].
  static void _wear(Node node, _Flip f, Material mat) {
    if (identical(node.mesh, f.shown) && f.shown.primitives.every((p) => p.visible && identical(p.material, mat))) return;
    for (final p in f.spare) {
      p
        ..visible = true
        ..material = mat;
    }
    f.show(node);
  }

  static final _hotBase = rgb(1, 0.5, 0.18), _goldBase = lin(const Color(0xFFF0B03C));
  static final _hotGlow = rgb(1, 0.3, 0.05), _hotEnd = rgb(0.8, 0.12, 0.02);

  /// Where a letter made at [station] stands (its foot, world).
  vm.Vector3 _stationFoot(int station, vm.Vector3 out) {
    final x = WorksLayout.stationX[station];
    return switch (station) {
      0 => out..setValues(x, WorksLayout.benchY + 0.03, WorksLayout.benchZ),
      1 => out..setValues(x - 0.14, WorksLayout.benchY + 0.012, WorksLayout.benchZ),
      _ => out..setValues(x, WorksLayout.benchY + 0.035, WorksLayout.benchZ),
    };
  }

  // ── The stations' moving parts ────────────────────────────────────────────

  static final _steel = v4(hex3(0x8A96A6)), _dark = v4(hex3(0x1B2233)), _sand = v4(hex3(0x5E5A55)), _brass = v4(hex3(0xB08A3E));
  static final _accent = lin(BP.amber);
  static final _orange = vm.Vector4(6, 2.2, 0.5, 1), _ember = vm.Vector4(1, 0.5, 0.12, 1), _chip = vm.Vector4(1, 0.78, 0.35, 1);
  static final _steam = vm.Vector4(0.95, 0.96, 1, 0.3);

  /// The mini letter each station is busy with at [tt] (from its setup to
  /// its pick-up), or null; with [after], the last one it started.
  _Mini? _atStation(int station, double tt, {bool after = false}) {
    _Mini? last;
    for (final m in _minis) {
      if (m.method != station || tt < m.setup || m.place > _stop) continue;
      if (tt < m.pick) return m;
      if (after) last = m;
    }
    return last;
  }

  void _stations(double tt, double t) {
    final b = WorksLayout.benchY, z = WorksLayout.benchZ;
    final s = scale;
    // The printer: the gantry and its head, parked up top unless printing.
    final px = WorksLayout.stationX[0];
    final pm = _atStation(0, tt);
    var gantry = b + 0.74, head = px;
    var printing = false;
    if (pm != null && pm.shape != null && tt >= pm.a - 0.6 && tt < pm.e + 0.4) {
      final shape = pm.shape!;
      final bands = shape.bandTops;
      final f = seg(tt, pm.a, pm.e);
      // The layer being laid: the head rides just over it, back and forth.
      final layer = bands.isEmpty ? f * shape.height : bands[math.min(bands.length - 1, (f * bands.length).floor())];
      final down = tt < pm.a ? eio(seg(tt, pm.a - 0.6, pm.a)) : (tt < pm.e ? 1.0 : 1 - eio(seg(tt, pm.e, pm.e + 0.4)));
      gantry = lerp(b + 0.74, b + 0.03 + layer * s + 0.05, down);
      printing = tt >= pm.a && tt < pm.e;
      final half = shape.width * s / 2 + 0.01;
      head = px + (printing ? half * math.sin(t * 9.5) : 0);
    }
    props.box(px, gantry, z, 0.66, 0.035, 0.06, _dark);
    props.box(head, gantry - 0.04, z, 0.09, 0.08, 0.1, _steel);
    props.box(head, gantry - 0.04, z - 0.051, 0.06, 0.03, 0.004, _accent);
    if (printing) props.glow(head, gantry - 0.09, z, 0.014, 0.024, 0.014, _orange);

    // The casting bench: the mold's halves, the crucible (in the furnace or
    // in hand), the pour.
    final cxs = WorksLayout.stationX[1];
    // (The mold stays open on the bench until the next cast.)
    final cm = _atStation(1, tt, after: true);
    final foot = _stationFoot(1, _foot);
    final furnace = _furnace..setValues(cxs + 0.38, b + 0.34, z);
    if (cm != null && cm.shape != null) {
      final shape = cm.shape!;
      final w = shape.width * s + 0.08, h = shape.height * s + 0.06, d = shape.depth * s + 0.08;
      // Closed over the setup, open from just before the finish.
      final close = eio(seg(tt, cm.setup, cm.setup + 0.9));
      final open = eio(seg(tt, cm.e - 0.6, cm.e));
      final apart = (1 - close) * 0.1 + open * (w / 2 + 0.06);
      final poured = seg(tt, cm.a + 0.6, cm.a + 0.6 + _pour(cm));
      final heat = poured * (1 - seg(tt, cm.a + 0.6 + _pour(cm), cm.e + 0.5));
      final c = _sand + (vm.Vector4(0.55, 0.16, 0.08, 1) - _sand) * (0.7 * heat);
      for (final side in const [-1.0, 1.0]) {
        props.box(foot.x + side * (w / 4 + apart + 0.003), foot.y + h / 2, foot.z, w / 2 - 0.002, h, d, c);
      }
      // The seam glows as the metal rises inside, and dims as it sets.
      if (heat > 0.02 && open < 0.05) {
        final level = h * seg(tt, cm.a + 0.6, cm.a + 0.6 + _pour(cm));
        props.glow(foot.x, foot.y + level / 2, foot.z - d / 2 - 0.003, 0.009, level, 0.004, _orange * (0.25 + 0.75 * heat));
        props.glow(foot.x, foot.y + level / 2, foot.z + d / 2 + 0.003, 0.009, level, 0.004, _orange * (0.25 + 0.75 * heat));
      }
      // The sprue on top, glowing while the metal goes in.
      if (open < 0.05) {
        props.cyl(foot.x, foot.y + h + 0.02, foot.z, 0.025, 0.04, _dark);
        if (heat > 0.02) props.glow(foot.x, foot.y + h + 0.045, foot.z, 0.035, 0.006, 0.035, _orange * (0.3 + 0.7 * heat));
      }
      // The crucible: lifted out, tipped over the sprue, put back.
      final pour = _pour(cm);
      final out = seg(tt, cm.a - 0.2, cm.a + 0.5), back = seg(tt, cm.a + 0.6 + pour, cm.a + 1.3 + pour);
      if (out > 0 && back < 1) {
        final p = crew.poses[Crew3D.makers + 1];
        OffDuty.hand(p, 0, _p);
        OffDuty.hand(p, 1, _q);
        final hx = (_p.x + _q.x) / 2, hy = (_p.y + _q.y) / 2, hz = (_p.z + _q.z) / 2;
        final tip = math.sin(math.pi * seg(tt, cm.a + 0.5, cm.a + 0.8 + pour)) * 1.25;
        props.cyl(hx, hy + 0.02, hz, 0.06, 0.1, _dark, roll: tip);
        props.glow(hx - math.sin(tip) * 0.05, hy + 0.07 * math.cos(tip), hz, 0.08, 0.008, 0.08, _orange, roll: tip);
        if (tt >= cm.a + 0.6 && tt < cm.a + 0.6 + pour) {
          // The stream, from the lip to the sprue, and sparks where it lands.
          final lipX = hx - 0.07, lipY = hy + 0.04;
          final topY = foot.y + h + 0.05;
          props.glow((lipX + foot.x) / 2, (lipY + topY) / 2, foot.z, 0.014, math.max(0.01, lipY - topY), 0.014, _orange * 1.4);
          for (var k = 0; k < 4; k++) {
            final age = (t * 3 + k * 0.25) % 1.0;
            final a = k * 1.7 + (t * 3).floor();
            fx.spark(foot.x + math.cos(a) * 0.08 * age, topY + 0.1 * age * (1 - age) * 4, foot.z + math.sin(a) * 0.08 * age, 0.012 * (1 - age), _ember, 7);
          }
        }
      } else {
        props.cyl(furnace.x, furnace.y + 0.03, furnace.z, 0.06, 0.1, _dark);
      }
      // Steam as it cools.
      if (tt >= cm.e && tt < cm.e + 2.4) {
        for (var k = 0; k < 2; k++) {
          final age = ((tt - cm.e) * 0.9 + k * 0.5) % 1.0;
          fx.puff(foot.x + 0.04 * (k - 0.5), foot.y + shape.height * s + 0.05 + 0.25 * age, foot.z, age, 0.08, seed: cm.k * 5 + k, n: 1, tint: _steam);
        }
      }
    } else {
      props.cyl(furnace.x, furnace.y + 0.03, furnace.z, 0.06, 0.1, _dark);
    }
    // The furnace's mouth always glows.
    props.glow(furnace.x, furnace.y - 0.005, furnace.z, 0.16, 0.012, 0.16, _orange * (0.7 + 0.15 * math.sin(t * 7)));

    // The mill: the block coming down to the letter, the spindle over it.
    final mx = WorksLayout.stationX[2];
    final mm = _atStation(2, tt);
    var spindleY = b + 0.62, spindleX = mx;
    if (mm != null && mm.shape != null) {
      final shape = mm.shape!;
      final f = _stationFoot(2, _r);
      final top = shape.height * s + 0.03;
      final level = tt < mm.a ? top : top * (1 - seg(tt, mm.a, mm.e));
      final w = shape.width * s + 0.06, d = shape.depth * s + 0.06;
      // Set down on the vise over the setup (from the back of the bench).
      final slide = 1 - eio(seg(tt, mm.setup, mm.setup + 0.9));
      if (level > 0.004) props.box(f.x, f.y + level / 2, f.z + slide * 0.3, w, level, d, _brass);
      final milling = tt >= mm.a && tt < mm.e;
      if (tt >= mm.a - 0.5 && tt < mm.e + 0.5) {
        spindleY = f.y + level + 0.16 + 0.15 * (1 - (milling ? 1 : 0));
        spindleX = f.x + (milling ? (w / 2 - 0.01) * math.sin(t * 6.5) : 0);
      }
      if (milling) {
        // The bit at the cut, chips flying off it.
        props.cyl(spindleX, f.y + level + 0.06, f.z, 0.008, 0.1, _steel);
        for (var k = 0; k < 5; k++) {
          final age = (t * 2.4 + k * 0.2) % 1.0;
          final a = (k * 2.3 + (t * 2.4).floor() * 1.1) % (2 * math.pi);
          final r = 0.05 + 0.25 * age;
          fx.pixel(
            spindleX + math.cos(a) * r,
            f.y + level + 0.02 + 0.22 * age - 0.5 * age * age,
            f.z - 0.02 + math.sin(a) * r * 0.6,
            0.012 * (1 - 0.5 * age),
            _chip,
            glow: 1.6,
            spin: age * 9 + k,
          );
        }
      }
    }
    props.box(spindleX, spindleY + 0.08, z, 0.09, 0.16, 0.09, _steel);
  }

  final _foot = vm.Vector3.zero(), _furnace = vm.Vector3.zero();

  /// How long the pour of [m] takes.
  static double _pour(_Mini m) => math.min(2.2, math.max(0.9, 0.35 * (m.e - m.a)));

  // ── The makers ────────────────────────────────────────────────────────────

  /// Maker [i] at [tt] (the works' clock): at their station between jobs,
  /// at work on a letter, carrying it to the tray and back.
  void _poseMaker(int i, double tt, double t) {
    final p = crew.poses[Crew3D.makers + i]..rest();
    p.visible = true;
    final seed = 40 + i * 7;
    final home = vm.Vector3(WorksLayout.stationX[i], 0, WorksLayout.makerZ);
    p.pos.setFrom(home);
    OffDuty.stand(p, t, seed);
    p.yaw = 0.12 * math.sin(t * 0.4 + i);
    _Mini? m;
    for (final x in _minis) {
      if (x.method == i && tt >= x.setup - 0.2 && tt < x.home) m = x;
    }
    if (m == null) {
      _idle(p, i, t);
      return;
    }
    final path = m.path;
    if (tt >= m.place + 0.5) {
      // Walking back.
      _walkAlong(p, m.back, m.place + 0.5, m.home, t, _walk);
      return;
    }
    if (tt >= m.pick) {
      if (tt < m.place - 0.45) {
        _walkAlong(p, path, m.pick, m.place - 0.45, t, _carry);
      } else {
        // Setting it down on the tray.
        p.pos.setFrom(path.last);
        p.yaw = 0;
        final k = math.sin(math.pi * seg(tt, m.place - 0.45, m.place + 0.5));
        p.lean = 0.35 * k;
        p.bob = -0.04 * k;
      }
      _holdOut(p);
      return;
    }
    final foot = _stationFoot(i, _r);
    final top = (m.shape?.height ?? 1) * scale;
    // Bending to pick it up.
    if (tt >= m.pick - 0.5) {
      final k = eio(seg(tt, m.pick - 0.5, m.pick));
      p.lean = 0.3 * k;
      for (var s = 0; s < 2; s++) {
        _p.setValues(foot.x + (s == 0 ? -1 : 1) * ((m.shape?.width ?? 1) * scale / 2 + 0.02), foot.y + top * 0.5, foot.z);
        crew.aim(p, s, _p);
      }
      return;
    }
    switch (i) {
      case 0:
        _printer(p, m, tt, t, foot, top);
      case 1:
        _caster(p, m, tt, t, foot, top);
      default:
        _miller(p, m, tt, t, foot, top);
    }
  }

  void _idle(FigurePose p, int i, double t) {
    // A word with the neighbour now and then, else watching the bench.
    final cycle = (t / 6.5).floor();
    if (rnd(cycle, i, 71) < 0.3) {
      final n = i == 0 ? 1 : (i == 2 ? 1 : (cycle.isEven ? 0 : 2));
      p.yaw = n < i ? 0.9 : -0.9;
      if ((cycle + i).isEven) {
        OffDuty.talk(p, t, i * 5);
      } else {
        OffDuty.listen(p, t, i * 5);
      }
    } else {
      p.lean = 0.12;
      p.armRoll[0] = p.armRoll[1] = 0.85;
      p.armPitch[0] = p.armPitch[1] = -0.3;
    }
  }

  /// Both hands out in front, holding something small.
  void _holdOut(FigurePose p) {
    p.armPitch[0] = p.armPitch[1] = 0.85;
    p.armRoll[0] = p.armRoll[1] = -0.22;
  }

  void _printer(FigurePose p, _Mini m, double tt, double t, vm.Vector3 foot, double top) {
    if (tt < m.a) {
      // Pressing start on the control box.
      final k = math.sin(math.pi * seg(tt, m.setup, m.a));
      _p.setValues(WorksLayout.stationX[0] + 0.4, WorksLayout.benchY + 0.14, WorksLayout.benchZ - 0.15);
      final pitch = p.armPitch[1], roll = p.armRoll[1];
      crew.aim(p, 1, _p);
      p.armPitch[1] = lerp(pitch, p.armPitch[1], k);
      p.armRoll[1] = lerp(roll, p.armRoll[1], k);
      p.lean = 0.15 * k;
      return;
    }
    // Watching it print, leaning in, then a look at the finished letter.
    p.lean = 0.22 + 0.04 * math.sin(t * 1.3);
    p.yaw = 0.1 * math.sin(t * 0.8);
    p.armRoll[0] = p.armRoll[1] = 0.85;
    p.armPitch[0] = p.armPitch[1] = -0.3;
    if (tt >= m.e) p.yaw = -0.25;
  }

  void _caster(FigurePose p, _Mini m, double tt, double t, vm.Vector3 foot, double top) {
    final w = (m.shape?.width ?? 1) * scale + 0.08;
    final pour = _pour(m);
    if (tt < m.a - 0.2) {
      // Closing the mold: pushing the halves together.
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        _p.setValues(foot.x + side * (w / 2 + 0.1 * (1 - eio(seg(tt, m.setup, m.setup + 0.9)))), foot.y + top * 0.5, foot.z);
        crew.aim(p, s, _p);
      }
      p.lean = 0.25;
      return;
    }
    final furnace = vm.Vector3(WorksLayout.stationX[1] + 0.38, WorksLayout.benchY + 0.42, WorksLayout.benchZ);
    final sprue = vm.Vector3(foot.x + 0.08, foot.y + top + 0.16, foot.z);
    if (tt < m.a + 1.3 + pour) {
      // The crucible: out of the furnace, over the sprue, back.
      final f = tt < m.a + 0.5 ? 1 - eio(seg(tt, m.a - 0.2, m.a + 0.5)) : (tt < m.a + 0.6 + pour ? 0.0 : eio(seg(tt, m.a + 0.6 + pour, m.a + 1.3 + pour)));
      _q.setValues(lerp(sprue.x, furnace.x, f), lerp(sprue.y, furnace.y, f), lerp(sprue.z, furnace.z, f));
      for (var s = 0; s < 2; s++) {
        _p.setValues(_q.x + (s == 0 ? -0.07 : 0.07), _q.y, _q.z);
        crew.aim(p, s, _p);
      }
      p.lean = 0.28;
      return;
    }
    if (tt >= m.e - 0.7) {
      // Pulling the mold open.
      final k = eio(seg(tt, m.e - 0.6, m.e));
      for (var s = 0; s < 2; s++) {
        final side = s == 0 ? -1.0 : 1.0;
        _p.setValues(foot.x + side * (w / 2 + k * (w / 2 + 0.06)), foot.y + top * 0.5, foot.z);
        crew.aim(p, s, _p);
      }
      p.lean = 0.25;
      if (tt >= m.e) {
        // Then stepping back from the heat.
        p.lean = -0.05;
        p.armPitch[0] = p.armPitch[1] = 0.4;
      }
      return;
    }
    // Waiting for it to set: arms folded.
    p.armPitch[0] = p.armPitch[1] = 1.0;
    p.armRoll[0] = p.armRoll[1] = -0.75;
    p.lean = 0.05;
  }

  void _miller(FigurePose p, _Mini m, double tt, double t, vm.Vector3 foot, double top) {
    if (tt < m.a) {
      // Setting the block in the vise.
      final w = (m.shape?.width ?? 1) * scale + 0.06;
      for (var s = 0; s < 2; s++) {
        _p.setValues(foot.x + (s == 0 ? -1 : 1) * (w / 2 + 0.01), foot.y + top * 0.5, foot.z + 0.3 * (1 - eio(seg(tt, m.setup, m.setup + 0.9))));
        crew.aim(p, s, _p);
      }
      p.lean = 0.3;
      return;
    }
    if (tt < m.e) {
      // A hand on the controls, watching the cut.
      _p.setValues(WorksLayout.stationX[2] + 0.42, WorksLayout.benchY + 0.3, WorksLayout.benchZ + 0.12);
      crew.aim(p, 1, _p);
      p.armRoll[0] = 0.85;
      p.armPitch[0] = -0.3;
      p.lean = 0.18;
      return;
    }
    // Brushing off the chips.
    final sweep = math.sin((tt - m.e) * 9);
    _p.setValues(foot.x + 0.12 * sweep, foot.y + 0.02, foot.z - 0.08);
    crew.aim(p, 1, _p);
    p.lean = 0.3;
  }

  /// Walks [p] along [pts] from [t0] to [t1] at about [speed].
  void _walkAlong(FigurePose p, List<vm.Vector3> pts, double t0, double t1, double t, double speed) {
    final total = _length(pts);
    var d = total * c01((t - t0) / math.max(t1 - t0, 1e-3));
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final l = a.distanceTo(b);
      if (d <= l || i + 2 == pts.length) {
        final f = l > 0 ? c01(d / l) : 1.0;
        p.pos.setValues(lerp(a.x, b.x, f), 0, lerp(a.z, b.z, f));
        if (t < t1 && l > 0.01) {
          OffDuty.walk(p, t, speed, 7);
          p.yaw = math.atan2(-(b.x - a.x), -(b.z - a.z));
        } else {
          p.yaw = 0;
        }
        return;
      }
      d -= l;
    }
  }

  // ── The building ──────────────────────────────────────────────────────────

  static const _atlas = 1024;
  static const _sign = Rect.fromLTWH(8, 8, 1008, 150),
      _labels = [Rect.fromLTWH(8, 172, 330, 76), Rect.fromLTWH(346, 172, 330, 76), Rect.fromLTWH(684, 172, 330, 76)];
  static const _poster = Rect.fromLTWH(8, 262, 300, 240), _screen = Rect.fromLTWH(320, 262, 160, 100);
  static const _white = Rect.fromLTWH(968, 456, 48, 48), _glowPatch = Rect.fromLTWH(908, 456, 48, 48), _lampPatch = Rect.fromLTWH(848, 456, 48, 48);

  Future<void> _build() async {
    await awaitFallbackFonts(
      '文字工場 印刷 鋳造 切削 書体見本',
      style: const TextStyle(fontFamily: BP.display, fontSize: 40, locale: Locale('ja')),
    );
    final base = await paintedTexture(_atlas, _atlas ~/ 2, (c, s) => _paint(c, glow: false));
    final glow = await paintedTexture(_atlas, _atlas ~/ 2, (c, s) => _paint(c, glow: true));
    final mat = PhysicallyBasedMaterial()
      ..baseColorTexture = base
      ..emissiveTexture = glow
      ..emissiveFactor = vm.Vector4(1, 1, 1, 1)
      ..emissiveStrength = 0.6
      ..metallicFactor = 0.05
      ..roughnessFactor = 0.62;
    _mat = mat;
    scene.add(Node(name: 'glyph works', mesh: Mesh(merged(_walls()), mat)));
    // The roof (and its sign) casts no shadow: the sun reaches the benches.
    scene.add(Node(name: 'glyph works roof', mesh: Mesh(merged(_roof()), mat))..castsShadows = false);
  }

  static vm.Vector2 _uvOf(Rect r) => vm.Vector2((r.left + r.width / 2) / _atlas, (r.top + r.height / 2) / (_atlas / 2));

  /// A box sampling one patch of the atlas (white: plain colour).
  MeshData _box(double x, double y, double z, double w, double h, double d, int rgb, {Rect patch = _white, double yaw = 0, double pitch = 0}) =>
      _solid(CuboidGeometry(vm.Vector3(w, h, d)).extractMeshData(), trs(vm.Vector3(x, y, z), rotY: yaw, rotX: pitch), rgb, patch);

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
    rgb,
    patch,
  );

  MeshData _solid(MeshData d, vm.Matrix4 at, int rgb, Rect patch) {
    final uv = Float32List(d.vertexCount * 2), c = _uvOf(patch);
    for (var i = 0; i < d.vertexCount; i++) {
      uv
        ..[i * 2] = c.x
        ..[i * 2 + 1] = c.y;
    }
    return painted(d, v4(hex3(rgb)), uvs: uv).transformed(at);
  }

  /// A thin board whose front (local −z) shows [region] of the atlas.
  MeshData _board(double x, double y, double z, double w, double h, Rect region, {int edge = 0x1B2233, double thick = 0.03, double yaw = 0}) {
    final d = CuboidGeometry(vm.Vector3(w, h, thick)).extractMeshData();
    final uv = Float32List(d.vertexCount * 2), n = d.normals!, p = d.positions, white = _uvOf(_white);
    final colors = Float32List(d.vertexCount * 4), side = v4(hex3(edge));
    for (var i = 0; i < d.vertexCount; i++) {
      final front = n[i * 3 + 2] < -0.5;
      uv[i * 2] = front ? (region.left + (p[i * 3] / w + 0.5) * region.width) / _atlas : white.x;
      uv[i * 2 + 1] = front ? (region.top + (0.5 - p[i * 3 + 1] / h) * region.height) / (_atlas / 2) : white.y;
      final c = front ? vm.Vector4(1, 1, 1, 1) : side;
      colors
        ..[i * 4] = c.x
        ..[i * 4 + 1] = c.y
        ..[i * 4 + 2] = c.z
        ..[i * 4 + 3] = 1;
    }
    return MeshData(
      positions: p,
      vertexCount: d.vertexCount,
      normals: n,
      texCoords: uv,
      colors: colors,
      indices: d.indices,
    ).transformed(trs(vm.Vector3(x, y, z), rotY: yaw));
  }

  List<MeshData> _walls() {
    const x0 = WorksLayout.x0, x1 = WorksLayout.x1, z0 = WorksLayout.z0, z1 = WorksLayout.z1, cx = WorksLayout.cx;
    const w = x1 - x0, d = z1 - z0, h = WorksLayout.roof, zc = (z0 + z1) / 2;
    const wall = 0xE6DED0, band = 0x2A3344, floor = 0x4B5566;
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
      for (final x in [x0 + 0.1, x1 - 0.1]) _box(x, WorksLayout.open / 2, z0 + 0.1, 0.2, WorksLayout.open, 0.2, 0x3A4558),
    ];
    // The benches: a top on a navy cabinet, each with its label.
    for (var i = 0; i < 3; i++) {
      final x = WorksLayout.stationX[i], y = WorksLayout.benchY, z = WorksLayout.benchZ;
      parts
        ..add(_box(x, y - 0.025, z, WorksLayout.benchW, 0.05, WorksLayout.benchD, 0x9C6B3C))
        ..add(_box(x, (y - 0.05) / 2, z, WorksLayout.benchW - 0.06, y - 0.05, WorksLayout.benchD - 0.06, 0x2A3344))
        ..add(_board(x, (y - 0.05) * 0.55, z - WorksLayout.benchD / 2 + 0.02, 0.62, 0.15, _labels[i], thick: 0.01));
    }
    // The printer: a frame, its bed, the control box (a screen), a spool.
    final px = WorksLayout.stationX[0], by = WorksLayout.benchY, bz = WorksLayout.benchZ;
    for (final sx in [-0.33, 0.33]) {
      for (final sz in [-0.2, 0.2]) {
        parts.add(_box(px + sx, by + 0.4, bz + sz, 0.035, 0.8, 0.035, 0x3A4558));
      }
      parts.add(_box(px + sx, by + 0.79, bz, 0.035, 0.035, 0.4, 0x3A4558));
    }
    parts
      ..add(_box(px, by + 0.79, bz + 0.2, 0.7, 0.035, 0.035, 0x3A4558))
      ..add(_box(px, by + 0.012, bz, 0.5, 0.024, 0.34, 0x1B2233))
      ..add(_box(px + 0.42, by + 0.09, bz - 0.12, 0.13, 0.18, 0.12, 0x2E6DA8))
      ..add(_board(px + 0.42, by + 0.11, bz - 0.185, 0.1, 0.07, _screen, thick: 0.004))
      ..add(_cyl(px - 0.18, by + 0.88, bz + 0.12, 0.09, 0.05, 0xE9B949, pitch: math.pi / 2));
    // The casting bench: the furnace with its glowing mouth, tongs on a hook.
    final fx = WorksLayout.stationX[1] + 0.38;
    parts
      ..add(_box(fx, by + 0.15, bz, 0.28, 0.3, 0.28, 0x3A4558))
      ..add(_box(fx, by + 0.305, bz, 0.22, 0.012, 0.22, 0x1B2233))
      ..add(_cyl(fx, by + 0.31, bz, 0.075, 0.012, 0xFF8A3D, patch: _glowPatch));
    // The mill: its column at the back left, the arm over the vise.
    final mx = WorksLayout.stationX[2];
    parts
      ..add(_box(mx - 0.4, by + 0.47, bz + 0.12, 0.14, 0.94, 0.14, 0x2E6DA8))
      ..add(_box(mx - 0.12, by + 0.88, bz, 0.66, 0.1, 0.14, 0x2E6DA8))
      ..add(_box(mx, by + 0.015, bz, 0.42, 0.03, 0.28, 0x3A4558))
      ..add(_box(mx + 0.42, by + 0.25, bz + 0.12, 0.1, 0.5, 0.1, 0x1B2233))
      ..add(_box(mx + 0.42, by + 0.47, bz + 0.12, 0.04, 0.12, 0.04, 0xE8505F));
    // The display table at the front.
    parts.add(_box(WorksLayout.tableX, WorksLayout.tableY - 0.02, WorksLayout.tableZ, WorksLayout.tableW, 0.04, WorksLayout.tableD, 0xC9A27A));
    for (final sx in [-1.0, 1.0]) {
      for (final sz in [-1.0, 1.0]) {
        parts.add(
          _box(
            WorksLayout.tableX + sx * (WorksLayout.tableW / 2 - 0.06),
            (WorksLayout.tableY - 0.04) / 2,
            WorksLayout.tableZ + sz * (WorksLayout.tableD / 2 - 0.05),
            0.04,
            WorksLayout.tableY - 0.04,
            0.04,
            0x3A4558,
          ),
        );
      }
    }
    // The back wall: a type specimen poster, a pegboard with tools, shelves
    // of spools and blocks on the side walls; a fire extinguisher.
    parts.add(_board(cx + 1.05, 1.55, z1 - 0.13, 0.75, 0.6, _poster, edge: 0xF4F1EA, thick: 0.01, yaw: 0));
    parts.add(_box(cx - 1.05, 1.45, z1 - 0.13, 0.9, 0.6, 0.015, 0xC9A27A));
    for (var k = 0; k < 6; k++) {
      parts.add(_box(cx - 1.4 + k * 0.14, 1.45 + 0.08 * math.sin(k * 1.9), z1 - 0.145, 0.03, 0.26 + 0.06 * (k % 3), 0.02, k.isEven ? 0x8A96A6 : 0xE8505F));
    }
    for (final (x, dir) in [(x0 + 0.24, 1.0), (x1 - 0.24, -1.0)]) {
      for (final y in [0.9, 1.5]) {
        parts.add(_box(x, y, zc + 0.3, 0.3, 0.03, 1.6, 0x9C6B3C));
        for (var k = 0; k < 5; k++) {
          final c = const [0xE9B949, 0x5FB8FF, 0xE8505F, 0xF4F1EA, 0x6CE5B1][(k + (y > 1 ? 2 : 0)) % 5];
          if (dir > 0) {
            parts.add(_cyl(x, y + 0.075, zc - 0.35 + k * 0.32, 0.09, 0.06, c, roll: math.pi / 2));
          } else {
            parts.add(_box(x, y + 0.06, zc - 0.35 + k * 0.32, 0.18, 0.09, 0.16, k.isEven ? 0xB08A3E : 0x8A96A6));
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
      _board(cx, (open + h) / 2 + 0.01, z0 - 0.02, 4.4, 0.5, _sign, edge: 0x1B2A44, thick: 0.04),
      // A vent stack for the furnace.
      _cyl(WorksLayout.stationX[1] + 0.4, h + 0.55, z1 - 0.6, 0.14, 0.9, 0x8A96A6),
      _cyl(WorksLayout.stationX[1] + 0.4, h + 1.02, z1 - 0.6, 0.2, 0.06, 0x3A4558),
    ];
    // Lamps over the benches: shades with a warm glow under them.
    for (final x in WorksLayout.stationX) {
      parts
        ..add(_cyl(x, h - 0.2, WorksLayout.benchZ, 0.012, 0.4, 0x1B2233))
        ..add(_cyl(x, h - 0.45, WorksLayout.benchZ, 0.2, 0.12, 0x2E6DA8, top: 0.06))
        ..add(_cyl(x, h - 0.515, WorksLayout.benchZ, 0.16, 0.012, 0xFFF1D6, patch: _lampPatch));
    }
    return parts;
  }

  // ── The atlas ─────────────────────────────────────────────────────────────

  void _paint(Canvas c, {required bool glow}) {
    c.drawRect(const Rect.fromLTWH(0, 0, _atlas + 0.0, _atlas / 2), Paint()..color = const Color(0xFF000000));
    c.drawRect(_white, Paint()..color = glow ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    c.drawRect(_glowPatch, Paint()..color = const Color(0xFFFF8A3D));
    c.drawRect(_lampPatch, Paint()..color = glow ? const Color(0xFFFFE2B0) : const Color(0xFFFFF4DE));
    // The sign: 文字工場 · GLYPH WORKS on navy, an amber rule.
    final r = _sign;
    c.drawRect(r, Paint()..color = glow ? const Color(0xFF000000) : const Color(0xFF1B2A44));
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(8), const Radius.circular(10)),
      Paint()
        ..color = glow ? const Color(0xFF7A5A10) : BP.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    final ink = glow ? const Color(0xFFFFC23D) : const Color(0xFFF4F1EA), amber = glow ? const Color(0xFFFFC23D) : BP.amber;
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
    // The stations' labels.
    const labels = [('印刷', 'PRINT'), ('鋳造', 'CAST'), ('切削', 'MILL')];
    for (var i = 0; i < 3; i++) {
      final b = _labels[i];
      c.drawRect(b, Paint()..color = glow ? const Color(0xFF000000) : const Color(0xFFF4F1EA));
      _text(c, '${labels[i].$1} · ${labels[i].$2}', b.deflate(6), 44, glow ? const Color(0xFF000000) : const Color(0xFF1B2A44));
    }
    // A type specimen poster.
    final p = _poster;
    c.drawRect(p, Paint()..color = glow ? const Color(0xFF000000) : const Color(0xFFF4F1EA));
    if (!glow) {
      _text(c, 'Aa あ 字', Rect.fromLTWH(p.left + 10, p.top + 14, p.width - 20, 110), 92, const Color(0xFF1B2A44));
      _text(c, '書体見本', Rect.fromLTWH(p.left + 10, p.top + 128, p.width - 20, 40), 34, const Color(0xFFE8505F));
      for (var k = 0; k < 4; k++) {
        c.drawRect(Rect.fromLTWH(p.left + 24, p.top + 178 + k * 13.0, p.width - 48 - 30.0 * (k % 2), 5), Paint()..color = const Color(0xFF8DA3BC));
      }
    }
    // The printer's screen: a progress bar.
    final s = _screen;
    c.drawRect(s, Paint()..color = const Color(0xFF0E1A2B));
    c.drawRect(Rect.fromLTWH(s.left + 14, s.top + 58, s.width - 28, 16), Paint()..color = const Color(0xFF2A3A55));
    c.drawRect(Rect.fromLTWH(s.left + 14, s.top + 58, (s.width - 28) * 0.62, 16), Paint()..color = const Color(0xFF6CE5B1));
    _text(c, '62%', Rect.fromLTWH(s.left + 10, s.top + 10, s.width - 20, 40), 34, const Color(0xFF6CE5B1));
  }

  void _text(Canvas c, String s, Rect box, double size, Color color, {List<TextSpan>? spans}) {
    final tp = TextPainter(
      text: TextSpan(
        text: spans == null ? s : null,
        children: spans,
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

/// One mini letter: plan letter [k] (smooth letter [glyph]), made by
/// [method] (0 printed, 1 cast, 2 milled — also its station and maker).
/// Its station gets ready from [setup], it's made over [a, e), cools, is
/// picked up at [pick], set on the tray at [place] (at [slotX] along it),
/// and its maker is back at [home].
class _Mini {
  _Mini(this.k, this.method, this.glyph);
  final int k, method, glyph;
  double slotX = 0, setup = 0, a = 0, e = 0, pick = 0, place = 0, home = 0;

  /// The way to its place on the tray, and back.
  List<vm.Vector3> path = const [], back = const [];
  LetterShape? shape;
  Node? node;
  _Flip? full, bands;
}

/// Two meshes over the same geometry, so a change of materials (or of which
/// bands show) takes effect: the engine keeps the materials a node's mesh
/// had when it was assigned, and only takes up new ones when another mesh
/// over the same geometry is assigned. Set up [spare], then [show] it.
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

/// What a camera visit to the works shows.
enum _Moment {
  finish(2.0),
  place(1.5),
  start(1.0);

  const _Moment(this.weight);
  final double weight;
}

class _Cut {
  _Cut(this.from, this.to, this.kind, this.k);
  final double from, to;
  final _Moment kind;
  final int k;
}
