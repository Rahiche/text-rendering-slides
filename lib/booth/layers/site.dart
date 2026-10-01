import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart' show FactoryInk, Pose, TextCache;
import '../layer.dart';
import '../layout.dart';
import '../model.dart';
import 'site_crane.dart';
import 'site_crew.dart';
import 'site_fx.dart';
import 'site_plan.dart';
import 'site_rubble.dart';
import 'site_sim.dart';
import 'site_wall.dart';

/// The construction site: crane, scaffold, builders laying the name brick by
/// brick, the reveal, fireworks, the wrecking ball and the cleanup.
class SiteLayer extends BoothLayer {
  final _sim = SiteSim();
  final _art = SiteArt();

  @override
  BoothSystem get system => _sim;

  @override
  CustomPainter painter(BoothModel m) => _SitePainter(m, _sim, _art);

  @override
  CustomPainter foreground(BoothModel m) => _SiteFront(m, _sim, _art);

  @override
  void dispose() => _art.dispose();
}

/// Cached drawing resources (text, meshes, atlases), reset per name.
class SiteArt {
  SiteArt() {
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  final text = TextCache();
  TextCache jobText = TextCache();
  final crane = CraneArt();
  final pieces = PieceBatch();
  final sprites = SpriteBatch();
  final nameSprites = SpriteBatch();
  GlyphAtlas? _glyphs;
  GlyphAtlas? _names;
  WallMesh? mesh;
  CrispName? crisp;
  Banner? banner;
  Int32List? pieceColors;
  Rubble? _colorsFor;
  Job? _job;
  SitePlan? _site;

  void _fontsChanged() {
    _glyphs?.dispose();
    _glyphs = null;
    _glyphsFor++;
    _names?.dispose();
    _names = null;
    _namesFor = null;
    crisp?.dispose();
    crisp = null;
    banner = null;
  }

  int _glyphsFor = 0;
  int _glyphsAsked = -1;
  Job? _namesFor;
  bool _disposed = false;

  void sync(SiteSim sim) {
    if (sim.job != _job) {
      _job = sim.job;
      _names?.dispose();
      _names = null;
      _namesFor = null;
      crisp?.dispose();
      crisp = null;
      banner = null;
      jobText.dispose();
      jobText = TextCache();
    }
    if (sim.site != _site) {
      _site = sim.site;
      mesh?.dispose();
      mesh = sim.site == null ? null : WallMesh(sim.site!);
      pieceColors = null;
      _colorsFor = null;
    }
    // Glyph sprites for the fireworks are rendered off the frame, well
    // before they are needed.
    if (_glyphs == null && _glyphsAsked != _glyphsFor) {
      final gen = _glyphsAsked = _glyphsFor;
      commonGlyphs().then(_gotGlyphs(gen));
    }
    final j = sim.job;
    if (j != null && j.raster != null && _namesFor != j) {
      _namesFor = j;
      nameGlyphs(j.name).then(_gotNames(j));
    }
  }

  void Function(GlyphAtlas) _gotGlyphs(int gen) => (a) {
    if (_disposed || gen != _glyphsFor) {
      a.dispose();
      return;
    }
    _glyphs = a;
  };

  void Function(GlyphAtlas) _gotNames(Job j) => (a) {
    if (_disposed || _job != j || _namesFor != j) {
      a.dispose();
      return;
    }
    _names?.dispose();
    _names = a;
  };

  GlyphAtlas? get glyphs => _glyphs;

  GlyphAtlas? get names => _names;

  Int32List colorsFor(Rubble r) {
    if (_colorsFor != r || pieceColors == null) {
      _colorsFor = r;
      pieceColors = Int32List(r.count);
      for (var i = 0; i < r.count; i++) {
        pieceColors![i] = pieceColor(r.site.r.bricks[i]);
      }
    }
    return pieceColors!;
  }

  void dispose() {
    _disposed = true;
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    text.dispose();
    jobText.dispose();
    _glyphs?.dispose();
    _names?.dispose();
    mesh?.dispose();
    crisp?.dispose();
  }
}

Paint _st(Color c, [double w = 1.2]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = c;

Paint _fl(Color c) => Paint()..color = c;

/// A brick in a builder's hands on its way into the wall.
class _Flight {
  _Flight(this.n, this.pos, this.f);
  final int n;
  final Offset pos;
  final double f;
}

class _SitePainter extends CustomPainter {
  _SitePainter(this.m, this.sim, this.art) : super(repaint: m);

  final BoothModel m;
  final SiteSim sim;
  final SiteArt art;

  @override
  void paint(Canvas c, Size size) {
    final j = m.job;
    if (j == null) return;
    art.sync(sim);
    final t = m.t;
    final ink = FactoryInk(c);
    final s = sim.site;
    final bp = sim.build;

    _fireworks(c, j, t);
    final cheering = j.phase == Phase.celebrate;
    art.crane.structure(c, t, cheer: cheering ? 1 : 0);
    _mastSign(c);
    _banner(c, j, t);
    if (s != null) _scaffold(c, s, bp, j, t);
    if (bp != null) _pallets(c, s!, bp, t);
    _hook(c, bp, t);

    // Builders work from the scaffold behind the wall.
    final flights = <int, List<_Flight>>{};
    for (var z = 0; z < zoneCount; z++) {
      _builder(ink, z, j, s, bp, t, flights);
    }
    if (s != null) _wall(c, ink, s, bp, j, t, flights);
    if (s != null) _reveal(c, s, j, t);
    _ball(c, t);
    if (sim.rubble != null) _rubble(c, sim.rubble!, t);
    sim.dust.draw(c, t);
    _props(ink, j, s, bp, t);
    sim.loader.draw(ink, t);
  }

  // ── Sky ───────────────────────────────────────────────────────────────────

  void _fireworks(Canvas c, Job j, double t) {
    if (!sim.celebrateAt.isFinite || t < sim.celebrateAt) return;
    final len = sim.demolishAt.isFinite ? sim.demolishAt - sim.celebrateAt : sim.celebrateLen;
    final common = art.glyphs;
    if (common == null) return;
    final fw = Fireworks(j.serial * 7 + 3, sim.celebrateAt, len);
    final box = sim.site == null ? null : _bannerRect(j);
    fw.draw(c, t, common, art.names, box, art.sprites, art.nameSprites);
  }

  Rect? _bannerRect(Job j) {
    final s = sim.site;
    if (s == null || j.raster == null) return null;
    final b = art.banner ??= Banner(j, art.jobText);
    return b.rect(s.wall.center.dx);
  }

  void _banner(Canvas c, Job j, double t) {
    final open = _bannerOpen(t);
    if (open <= 0 || j.raster == null || sim.site == null) return;
    final b = art.banner ??= Banner(j, art.jobText);
    b.draw(c, b.rect(sim.site!.wall.center.dx), open, t);
  }

  double _bannerOpen(double t) {
    if (!sim.celebrateAt.isFinite || t < sim.celebrateAt) return 0;
    final u = t - sim.celebrateAt;
    var open = eo(seg(u, 0.25, 1.3)) * (1 - eio(seg(u, sim.celebrateLen - 1.1, sim.celebrateLen - 0.3)));
    if (sim.demolishAt.isFinite && t >= sim.demolishAt) {
      final at = sim.demolishAt - sim.celebrateAt;
      final was = eo(seg(at, 0.25, 1.3)) * (1 - eio(seg(at, sim.celebrateLen - 1.1, sim.celebrateLen - 0.3)));
      open = was * (1 - eio(seg(t, sim.demolishAt, sim.demolishAt + 0.5)));
    }
    return open;
  }

  void _mastSign(Canvas c) {
    const r = Rect.fromLTRB(mastL - 30, 548, mastR + 30, 590);
    c.drawRect(r, _fl(BP.panel));
    c.drawRect(r, _st(BP.green, 1.4));
    // Green cross: the Japanese site safety mark.
    final cx = r.left + 13, cy = r.center.dy;
    c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 12, height: 4), _fl(BP.green));
    c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 4, height: 12), _fl(BP.green));
    final ja = art.text.get('安全第一', jaStyle(15, color: BP.ink, weight: 600));
    ja.paint(c, Offset(r.left + 23, r.top + 3));
    final en = art.text.get('SAFETY FIRST', BT.mono(8.5, color: BP.green, weight: 500));
    en.paint(c, Offset(r.left + 23, r.bottom - en.height - 3));
  }

  // ── Scaffold ──────────────────────────────────────────────────────────────

  void _scaffold(Canvas c, SitePlan s, BuildPlan? bp, Job j, double t) {
    var alpha = 1.0;
    var sink = 0.0;
    if (sim.demolishAt.isFinite && t >= sim.demolishAt) {
      final f = seg(t, sim.demolishAt, sim.scaffoldGone);
      alpha = 1 - f;
      sink = 30 * ei(f);
      if (alpha <= 0) return;
    }
    // Erected decks: up to [top], the newest growing.
    var top = 0;
    var grow = 1.0;
    if (bp != null) {
      for (var k = 1; k < bp.erectAt.length; k++) {
        if (t >= bp.erectAt[k]) {
          top = k;
          grow = seg(t, bp.erectAt[k], bp.erectAt[k] + 1.0);
        }
      }
    }
    // During intake the base goes up first.
    final base = eo(seg(t - j.startedAt, 0.6, 2.4));
    final pole = _st(BP.lineDim.withValues(alpha: 0.9 * alpha), 1.1);
    final faint = _st(BP.lineFaint.withValues(alpha: alpha), 1);
    final board = _st(BP.lineDim.withValues(alpha: alpha), 2.6);
    final rail = _st(BP.inkFaint.withValues(alpha: alpha), 1.1);
    c.save();
    c.translate(0, sink);
    final lastY = top == 0 ? BL.groundY : s.deckY(top);
    final prevY = top <= 1 ? BL.groundY : s.deckY(top - 1);
    final railTop = (top == 0 ? BL.groundY - 18 * base : mix(prevY, lastY, eo(grow)) - 16);
    final p = Path();
    for (final x in s.standards) {
      p
        ..moveTo(x, BL.groundY)
        ..lineTo(x, railTop);
      // Base plates.
      p
        ..moveTo(x - 4, BL.groundY)
        ..lineTo(x + 4, BL.groundY);
    }
    c.drawPath(p, pole);
    final braces = Path();
    final ladders = Path();
    final boards = Path();
    for (var k = 1; k <= top; k++) {
      final y = s.deckY(k);
      final y0 = s.deckY(k - 1);
      final a = k == top ? grow : 1.0;
      final x1 = mix(s.sL, s.sR, eio(a));
      boards
        ..moveTo(s.sL - 3, y - 1.3)
        ..lineTo(x1 + (a >= 1 ? 3 : 0), y - 1.3);
      for (var i = 0; i < s.standards.length - 1; i++) {
        if ((i + k).isEven) continue;
        final xa = s.standards[i], xb = s.standards[i + 1];
        if (xb > x1 + 1) continue;
        braces
          ..moveTo(xa, y0)
          ..lineTo(xb, y);
      }
      // Ladders at both ends, lift by lift.
      for (final lx in [s.sL + 9, s.sR - 9]) {
        if (lx > x1 + 1) continue;
        ladders
          ..moveTo(lx - 4, y0)
          ..lineTo(lx - 4, y - 10)
          ..moveTo(lx + 4, y0)
          ..lineTo(lx + 4, y - 10);
        for (var ry = y0 - 6; ry > y - 8; ry -= 6) {
          ladders
            ..moveTo(lx - 4, ry)
            ..lineTo(lx + 4, ry);
        }
      }
    }
    c.drawPath(braces, faint);
    c.drawPath(ladders, _st(BP.inkFaint.withValues(alpha: 0.9 * alpha), 1));
    c.drawPath(boards, board);
    if (top > 0 && grow > 0.6) {
      final y = s.deckY(top);
      final ra = seg(grow, 0.6, 1);
      c.drawLine(Offset(s.sL, y - 12), Offset(s.sR, y - 12), rail..color = rail.color.withValues(alpha: alpha * ra));
      c.drawLine(Offset(s.sL, y - 6), Offset(s.sR, y - 6), _st(BP.lineFaint.withValues(alpha: alpha * ra), 1));
    }
    c.restore();
  }

  // ── Pallets ───────────────────────────────────────────────────────────────

  static const _wood = Color(0xFFB98E5F);

  void _pallet(Canvas c, Offset bottom, BuildPlan bp, int i, int remaining, double alpha) {
    if (alpha <= 0) return;
    final r = bp.site.r;
    final first = i * palletSize;
    final size = math.min(palletSize, bp.total - first);
    final base = Rect.fromLTWH(bottom.dx - palletW / 2, bottom.dy - 4, palletW, 4);
    c.drawRect(base, _fl(BP.panel.withValues(alpha: alpha)));
    c.drawRect(base, _st(_wood.withValues(alpha: alpha), 1));
    for (final bx in [base.left + 3, base.center.dx, base.right - 3]) {
      c.drawLine(Offset(bx, base.top + 1), Offset(bx, base.bottom), _st(_wood.withValues(alpha: alpha * 0.8), 1));
    }
    final n = math.min(remaining, size);
    final paint = Paint();
    final faces = art.mesh?.col;
    for (var q = 0; q < n; q++) {
      final col = q % 6, row = q ~/ 6;
      final cell = Rect.fromLTWH(base.left + col * 4 + 0.3, base.top - (row + 1) * 3.5 + 0.3, 3.4, 3.0);
      final face = Color(faces == null ? pieceColor(r.bricks[first + q]) : faces[(first + q) * 8 + 4]);
      paint.color = alpha >= 1 ? face : face.withValues(alpha: face.a * alpha);
      c.drawRect(cell, paint);
    }
  }

  /// Fade for pallets once a build is cut short.
  double _cutFade(double t) => sim.cutAt.isFinite ? 1 - seg(t, sim.cutAt, sim.cutAt + 0.45) : 1;

  void _pallets(Canvas c, SitePlan s, BuildPlan bp, double t) {
    final fade = _cutFade(t);
    if (fade <= 0) return;
    final picked = bp.pickedAt(t);
    for (final trip in bp.trips) {
      // On the landing, waiting for the crane (or sliding onto the stack).
      if (t < trip.departAt) {
        for (var q = 0; q < trip.count; q++) {
          final i = trip.first + q;
          final at = bp.palletAt(i);
          if (t < at) continue;
          final f = eio(seg(t, at, at + hopTime));
          final to = Offset(stageX, palletFloor - q * palletH);
          final pos = Offset.lerp(Offset(BL.pickup.dx, palletFloor), to, f)! - Offset(0, 10 * bump(f));
          _pallet(c, pos, bp, i, palletSize, fade);
        }
        continue;
      }
      if (t < trip.landAt) continue; // on the hook (drawn with it)
      // On the deck, emptying as builders take bricks (from the top).
      final out = 1 - seg(t, trip.emptyAt + 0.3, trip.emptyAt + 1.3);
      if (out <= 0) continue;
      final bottom = s.deckY(trip.deck) - 1.5;
      final int gone = math.max(trip.brickFrom, math.min(trip.brickTo, picked));
      int left = trip.brickTo - gone;
      for (var q = 0; q < trip.count; q++) {
        final i = trip.first + q;
        final int size = math.min(palletSize, bp.total - i * palletSize);
        final int here = math.min(size, left);
        left -= here;
        _pallet(c, Offset(trip.bayX, bottom - q * palletH), bp, i, here, fade * out);
      }
    }
  }

  // ── Crane hook and its load ───────────────────────────────────────────────

  void _hook(Canvas c, BuildPlan? bp, double t) {
    final (tx, hook) = sim.hookAt(t);
    art.crane.trolley(c, tx);
    if (sim.ballHung) return; // the ball and its line are drawn in front
    art.crane.hook(c, tx, hook);
    if (bp == null) return;
    final fade = _cutFade(t);
    final slung = bp.slung(t);
    if (slung != null && fade > 0) {
      final top = hook.dy + slingH;
      art.crane.slings(c, hook, top, palletW);
    }
    final trip = bp.hooked(t);
    if (trip != null && fade > 0) {
      for (var q = 0; q < trip.count; q++) {
        final bottom = Offset(hook.dx, hook.dy + slingH + trip.height - q * palletH);
        _pallet(c, bottom, bp, trip.first + q, palletSize, fade);
      }
    }
  }

  void _ball(Canvas c, double t) {
    if (!sim.ballHung) {
      art.crane.ball(c, Offset.zero, Offset.zero, sim.ballPos, cable: false);
      return;
    }
    final p = sim.crane.at(t);
    final top = Offset(p.dx, trolleyY);
    final d = sim.ballPos - top;
    final n = d.distance;
    final block = n < 1 ? top : top + d / n * (p.dy - trolleyY - 6);
    art.crane.ball(c, top, block, sim.ballPos);
  }

  // ── Crew ──────────────────────────────────────────────────────────────────

  /// Index of the first brick of [list] still to land at [t].
  int _next(Int32List list, BuildPlan bp, double t) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (bp.landTime(list[mid]) <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _builder(FactoryInk ink, int z, Job j, SitePlan? s, BuildPlan? bp, double t, Map<int, List<_Flight>> flights) {
    final b = sim.builders[z];
    final pose = Pose();
    final dir = b.face >= 0 ? 1 : -1;
    final feet = Offset(b.x, b.y);
    final seed = z * 1.7;
    if (b.falling) {
      pose
        ..upA = 2.7
        ..foA = 3.0
        ..upB = 2.5
        ..foB = 2.8
        ..thA = 0.6
        ..shA = 0.1
        ..thB = -0.3
        ..shB = -0.5;
    } else if (b.climbing) {
      climbPose(pose, b.climbPh);
      if (s != null) ladder(ink.c, b.climbX, math.min(b.climbFrom, s.deckY(b.climbTo)), math.max(b.climbFrom, s.deckY(b.climbTo)));
    } else if (b.speed > 4) {
      pose.walk(b.walkPh, amp: 0.5);
    }
    final still = !b.falling && !b.climbing && b.speed <= 4;
    Offset? brickInHand;
    var hammer = false;
    Offset? strike;
    var shovel = false;
    var plank = false;
    var cup = false;

    switch (b.act) {
      case Act.work:
      case Act.hammer:
        if (s != null && bp != null && j.phase == Phase.build && j.cutAt == null) {
          final list = s.zoneBricks[z];
          final k = _next(list, bp, t);
          // Crouch for low courses.
          if (k < list.length) {
            final low = s.cy[list[k]] > b.y - crewH * 0.36;
            if (low && !b.climbing) {
              pose
                ..drop = 0.14
                ..lean = 0.32;
            }
          }
          final sh = shoulderOf(feet, crewH, dir.toDouble(), pose);
          final holdPt = sh + Offset(dir * 7.0, 6);
          final fl = <_Flight>[];
          for (var q = k; q < list.length; q++) {
            final n = list[q];
            final land = bp.landTime(n);
            if (land - flightTime > t) break;
            final f = (t - (land - flightTime)) / flightTime;
            final cell = Offset(s.cx[n], s.cy[n]);
            final dist = (cell - holdPt).distance;
            final pos = Offset.lerp(holdPt, cell, eio(f))! - Offset(0, (5 + 0.12 * dist) * bump(f));
            fl.add(_Flight(n, pos, f));
          }
          flights[z] = fl;
          if (fl.isNotEmpty) {
            final (up, fo) = reach(sh, fl.first.pos, crewH, dir.toDouble());
            pose
              ..upA = up
              ..foA = fo;
          } else if (k < list.length && bp.landTime(list[k]) - flightTime - 0.22 <= t) {
            // Picking the next brick up off the deck.
            final grab = feet + Offset(dir * 6.0, -3);
            final (up, fo) = reach(sh, grab, crewH, dir.toDouble());
            pose
              ..upA = up
              ..foA = fo
              ..lean = math.max(pose.lean, 0.35);
            brickInHand = grab;
          }
          // Hammer taps on the last brick set.
          if (k > 0 && t - bp.landTime(list[k - 1]) < 0.16) {
            final n = list[k - 1];
            strike = Offset(s.cx[n], s.cy[n] - s.b * 0.5);
            final (up, fo) = reach(sh, strike, crewH, dir.toDouble(), bend: -1);
            pose
              ..upB = up
              ..foB = fo;
          } else if (k < list.length && bp.landTime(list[k]) - t < 0.25) {
            pose
              ..upB = 2.4
              ..foB = 2.9;
          } else if (b.act == Act.hammer && still) {
            // Waiting: tap the scaffold, look around.
            final ph = (t * 1.6 + seed) % 1.0;
            pose
              ..upB = ph < 0.7 ? mix(1.0, 2.6, eo(ph / 0.7)) : mix(2.6, 1.0, (ph - 0.7) / 0.3)
              ..foB = pose.upB + 0.4
              ..head = 0.15 * math.sin(t * 0.7 + seed);
          }
          hammer = true;
        } else if (b.act == Act.hammer) {
          hammer = true;
          if (still) {
            final ph = (t * 1.8 + seed) % 1.0;
            pose
              ..lean = 0.35
              ..drop = 0.12
              ..upB = ph < 0.7 ? mix(1.1, 2.7, eo(ph / 0.7)) : mix(2.7, 0.9, (ph - 0.7) / 0.3)
              ..foB = pose.upB + 0.5;
          }
        }
      case Act.watch:
        if (still) {
          final react = sim.impacts.isNotEmpty && t - sim.impacts.last < 1.1 && j.phase == Phase.demolish;
          if (react) {
            pose.overwhelmed(t);
          } else if (j.phase == Phase.reveal) {
            pose
              ..point(2.0 + 0.1 * math.sin(t + seed))
              ..head = -0.15;
          } else {
            pose
              ..upA = 0.7
              ..foA = 2.1
              ..upB = 0.6
              ..foB = 2.0
              ..head = -0.1;
          }
        }
      case Act.cheer:
        if (still) cheerPose(pose, t, z * 1.3);
      case Act.shovel:
        if (still) {
          shovel = true;
          final ph = (t * 0.9 + seed) % 1.0;
          final lift = ph < 0.55 ? 0.0 : bump((ph - 0.55) / 0.45);
          pose
            ..lean = 0.3 - 0.25 * lift
            ..drop = 0.1
            ..upA = 1.2 + 0.9 * lift
            ..foA = 1.5 + 1.0 * lift
            ..upB = 0.9 + 0.7 * lift
            ..foB = 1.3 + 0.9 * lift;
        }
      case Act.stretch:
        if (still) {
          final ph = math.sin(t * 1.4 + seed);
          pose
            ..upA = 2.9 + 0.1 * ph
            ..foA = 3.1
            ..upB = 2.9 - 0.1 * ph
            ..foB = 3.1
            ..lean = 0.1 * ph;
        }
      case Act.plank:
        plank = true;
        pose.carry();
        pose
          ..upA = 2.6
          ..foA = 3.0
          ..upB = 2.5
          ..foB = 3.0;
      case Act.coffee:
        if (still) {
          cup = true;
          final sip = ((t + seed * 3) % 6.0) < 1.4;
          pose
            ..upA = sip ? 1.6 : 0.9
            ..foA = sip ? 3.0 : 2.2
            ..head = sip ? -0.2 : 0;
        }
      case Act.react:
      case Act.idle:
        if (still && j.phase == Phase.intake && (t * 0.3 + seed) % 4.0 < 1.0) {
          pose.wipe(t);
        }
    }

    final hat = zoneHats[z];
    final limbs = ink.worker(feet, crewH, dir, pose, hat: hat);
    if (hammer) ink.hammer(limbs.elbowB, limbs.handB);
    if (strike != null) ink.sparks(strike, 0.3, z * 13 + (t * 10).floor());
    if (brickInHand != null && s != null) heldBrick(ink.c, limbs.handA, math.max(3.0, s.b * 0.6), BP.ink);
    if (shovel) ink.shovel(limbs.handB, limbs.handA, 7);
    if (cup) ink.coffee(limbs.handA, t);
    if (plank) {
      ink.c.drawLine(limbs.head + Offset(-dir * 20.0, -6), limbs.head + Offset(dir * 20.0, -8), _st(_wood, 2.6));
    }
  }

  // ── The wall ──────────────────────────────────────────────────────────────

  void _wall(Canvas c, FactoryInk ink, SitePlan s, BuildPlan? bp, Job j, double t, Map<int, List<_Flight>> flights) {
    final mesh = art.mesh;
    if (mesh == null) return;
    final rb = sim.rubble;
    if (rb != null && (j.phase == Phase.demolish || j.phase == Phase.cleanup)) {
      mesh.drawStanding(c, rb);
      return;
    }
    final laid = j.laid(t);
    mesh.drawPrefix(c, laid);
    if (bp == null || j.phase != Phase.build) return;
    // Bricks on their way from hands to cells, and the tap as they land.
    final paint = Paint();
    final edge = _st(BP.paper.withValues(alpha: 0.8), 0.8);
    final sz = s.b * 0.86;
    for (var z = 0; z < zoneCount; z++) {
      for (final f in flights[z] ?? const <_Flight>[]) {
        if (f.n < laid) continue;
        final k = s.r.bricks[f.n];
        paint.color = Color(brickColors(k).$1);
        c.save();
        c.translate(f.pos.dx, f.pos.dy);
        c.rotate((1 - f.f) * 0.7 * (z.isEven ? 1 : -1));
        final r = Rect.fromCenter(center: Offset.zero, width: sz, height: sz);
        c.drawRect(r, paint);
        c.drawRect(r, edge);
        c.restore();
      }
      final list = s.zoneBricks[z];
      final k = _next(list, bp, t);
      for (var q = k - 1; q >= 0 && q >= k - 3; q--) {
        final n = list[q];
        final age = t - bp.landTime(n);
        if (age > 0.22) break;
        final p = Offset(s.cx[n], s.cy[n]);
        final a = 1 - age / 0.22;
        c.drawRect(
          Rect.fromCenter(center: p, width: s.b, height: s.b),
          _st(zoneHats[z].withValues(alpha: 0.9 * a), 1.4),
        );
      }
    }
  }

  // ── Reveal: pixels → outlines ─────────────────────────────────────────────

  void _reveal(Canvas c, SitePlan s, Job j, double t) {
    if (!sim.revealAt.isFinite || t < sim.revealAt) return;
    var alpha = 1.0;
    if (sim.demolishAt.isFinite && t >= sim.demolishAt) {
      alpha = 1 - seg(t, sim.demolishAt, sim.demolishAt + 0.5);
      if (alpha <= 0) return;
    }
    final r = j.raster;
    final mesh = art.mesh;
    if (r == null || mesh == null) return;
    final crisp = art.crisp ??= CrispName(r);
    final u = t - sim.revealAt;
    final w = s.wall;
    final scan = mix(w.bottom + 4, w.top - 6, eio(seg(u, 0.4, 3.9)));
    // Bricks fully below the scan line are "developed".
    var k = 0;
    while (k < s.total && s.cy[k] - s.b / 2 >= scan - 0.5) {
      k++;
    }
    if (alpha < 1) c.saveLayer(w.inflate(40), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    mesh.drawPrefixFlat(c, k, _fl(BP.paper.withValues(alpha: 0.5)));
    c.save();
    c.clipRect(Rect.fromLTRB(w.left - 40, scan, w.right + 40, w.bottom + 20));
    // While scanning, the fill is see-through: the outline lies over the
    // staircase of whole and partial bricks. Then it develops fully.
    final solid = mix(0.5, 0.94, eio(seg(u, 4.0, 5.6)));
    c.saveLayer(w.inflate(40), Paint()..color = Color.fromRGBO(0, 0, 0, solid));
    crisp.fill.paint(c, crisp.origin);
    c.restore();
    crisp.outline.paint(c, crisp.origin);
    c.restore();
    if (alpha < 1) c.restore();
    // The scan line.
    final on = (1 - seg(u, 3.9, 4.4)) * alpha;
    if (on > 0) {
      final x0 = w.left - 26, x1 = w.right + 26;
      final glow = Rect.fromLTRB(x0, scan, x1, scan + 28);
      c.drawRect(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BP.amber.withValues(alpha: 0.28 * on), BP.amber.withValues(alpha: 0)],
          ).createShader(glow),
      );
      c.drawLine(Offset(x0, scan), Offset(x1, scan), _st(BP.amber.withValues(alpha: on), 2));
      for (final (x, d) in [(x0, -1.0), (x1, 1.0)]) {
        c.drawPath(
          Path()
            ..moveTo(x, scan - 6)
            ..lineTo(x + d * 8, scan)
            ..lineTo(x, scan + 6)
            ..close(),
          _fl(BP.amber.withValues(alpha: on)),
        );
      }
    }
    // Caption: what just happened.
    final cap = seg(u, 1.0, 1.8) * alpha * (1 - seg(u, 5.6, 6.4));
    if (cap > 0) {
      final tp = art.text.get('pixels → outlines · ピクセル → アウトライン', jaStyle(14, color: BP.amber));
      final heads = s.deckY(s.lifts) - crewH - 10;
      final at = Offset(w.left, math.min(w.top, heads) - tp.height - 12);
      c.drawRect(
        Rect.fromLTWH(at.dx - 6, at.dy - 3, tp.width + 12, tp.height + 6),
        _fl(BP.paper.withValues(alpha: 0.85 * cap)),
      );
      c.saveLayer(Rect.fromLTWH(at.dx - 8, at.dy - 5, tp.width + 16, tp.height + 10), Paint()..color = Color.fromRGBO(0, 0, 0, cap));
      tp.paint(c, at);
      c.restore();
    }
  }

  // ── Rubble ────────────────────────────────────────────────────────────────

  void _rubble(Canvas c, Rubble rb, double t) {
    final colors = art.colorsFor(rb);
    final batch = art.pieces..begin(rb.count);
    for (var i = 0; i < rb.count; i++) {
      final st = rb.state[i];
      if (st == Piece.flying.index || st == Piece.resting.index) {
        batch.add(rb.x[i], rb.y[i], rb.size, rb.ang[i], colors[i]);
      } else if (st == Piece.pushed.index) {
        batch.add(rb.x[i], rb.y[i], rb.size * 0.8, rb.ang[i] + i * 0.3, colors[i]);
      } else if (st == Piece.bucket.index) {
        batch.add(rb.x[i], rb.y[i], rb.size * 0.7, rb.ang[i] + i * 0.3, colors[i]);
      }
    }
    batch.draw(c);
  }

  // ── Ground props and people ───────────────────────────────────────────────

  void _props(FactoryInk ink, Job j, SitePlan? s, BuildPlan? bp, double t) {
    mixer(ink, const Offset(mixerX, BL.groundY), t * 0.8);
    _surveyor(ink, j, s, t);
    _foreman(ink, j, t);
    _rigger(ink, j, bp, t);
  }

  void _surveyor(FactoryInk ink, Job j, SitePlan? s, double t) {
    final u = t - j.startedAt;
    if (u > 11 || (j.phase != Phase.intake && j.phase != Phase.build)) return;
    final c = ink.c;
    const tripod = 1446.0;
    double x;
    var fold = 0.0;
    var carrying = false;
    if (u < 1.8) {
      x = mix(1660, tripod + 13, eo(u / 1.8));
      carrying = true;
      fold = 1;
    } else if (u < 7.2) {
      x = tripod + 13;
      fold = 1 - eo(seg(u, 1.8, 2.3));
    } else {
      fold = eo(seg(u, 7.2, 7.7));
      x = mix(tripod + 13, 1680, ei(seg(u, 7.7, 10.8)));
      carrying = u > 7.7;
    }
    final working = u >= 2.3 && u < 7.2;
    if (!carrying) theodolite(ink, const Offset(tripod, BL.groundY), fold: fold);
    final pose = Pose();
    if (!working && (u < 1.8 || u > 7.7)) pose.walk(u * 9, amp: 0.45);
    if (working) {
      pose
        ..lean = 0.28
        ..upA = 1.5
        ..foA = 1.9
        ..upB = 0.6
        ..foB = 1.2;
    }
    final limbs = ink.worker(Offset(x, BL.groundY), crewH, u < 7.7 ? -1 : 1, pose, hat: BP.line);
    if (carrying) {
      c.drawLine(limbs.handA, limbs.handA + const Offset(-6, 18), _st(BP.lineDim, 1.4));
    }
    if (s == null) return;
    // Setting out: the baseline, then the raster's bounds on the ground.
    final w = s.wall;
    final eye = const Offset(tripod - 6, BL.groundY - 29);
    final out = 1 - seg(u, 9.2, 10.2);
    final line = seg(u, 2.4, 3.6) * out;
    if (line > 0) {
      final x1 = mix(eye.dx, w.left, eio(line));
      _dashed(c, eye, Offset(x1, BL.groundY - 2), BP.amber.withValues(alpha: 0.75 * out));
      staff(c, w.left - 6, BL.groundY, 34 * seg(u, 3.4, 3.8));
    }
    final box = seg(u, 3.4, 6.0) * out;
    if (box > 0) {
      final path = Path()
        ..moveTo(w.left, w.bottom)
        ..lineTo(w.left, w.top)
        ..lineTo(w.right, w.top)
        ..lineTo(w.right, w.bottom);
      final metric = path.computeMetrics().first;
      final part = metric.extractPath(0, metric.length * eio(box));
      _dashedPath(c, part, BP.amber.withValues(alpha: 0.6 * out));
      final lab = seg(u, 5.2, 5.8) * out;
      if (lab > 0) {
        final tp = art.jobText.get(
          'bounds ${s.cols}×${s.rows} px → ${s.total} bricks · レンガ',
          jaStyle(13, color: BP.amber),
        );
        c.saveLayer(Rect.fromLTWH(w.left - 2, w.top - 24, tp.width + 4, tp.height + 4), Paint()..color = Color.fromRGBO(0, 0, 0, lab));
        tp.paint(c, Offset(w.left, w.top - 22));
        c.restore();
      }
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Color col) {
    final d = b - a;
    final n = d.distance;
    if (n < 1) return;
    final u = d / n;
    final p = Path();
    for (var s = 0.0; s < n; s += 10) {
      final e = math.min(n, s + 6);
      p
        ..moveTo(a.dx + u.dx * s, a.dy + u.dy * s)
        ..lineTo(a.dx + u.dx * e, a.dy + u.dy * e);
    }
    c.drawPath(p, _st(col, 1.2));
  }

  void _dashedPath(Canvas c, Path src, Color col) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      for (var s = 0.0; s < m.length; s += 10) {
        out.addPath(m.extractPath(s, math.min(m.length, s + 6)), Offset.zero);
      }
    }
    c.drawPath(out, _st(col, 1.2));
  }

  void _foreman(FactoryInk ink, Job j, double t) {
    final pose = Pose();
    final u = j.since(t);
    var board = true;
    var flag = false;
    switch (j.phase) {
      case Phase.intake:
        if ((u % 4.0) > 2.6) pose.point(1.9);
        pose.head = 0.25;
      case Phase.build:
        final ph = (t / 5.0) % 1.0;
        if (ph < 0.18) {
          pose.point(2.2);
          pose.head = -0.4;
        } else {
          pose.head = 0.3;
        }
      case Phase.reveal:
        pose.point(2.05);
        pose.head = -0.2;
      case Phase.celebrate:
        board = false;
        flag = true;
        cheerPose(pose, t, 5);
      case Phase.demolish:
        flag = true;
        pose
          ..upB = 2.8
          ..foB = 3.0;
      case Phase.cleanup:
        flag = true;
        pose
          ..upB = 2.0 + 0.5 * math.sin(t * 5)
          ..foB = 2.6 + 0.5 * math.sin(t * 5);
    }
    if (board && j.phase != Phase.celebrate) {
      if (pose.upA == Pose().upA) {
        pose
          ..upA = 0.9
          ..foA = 2.0;
      }
    }
    final limbs = ink.worker(const Offset(foremanX, BL.groundY), crewH, -1, pose, hat: BP.ink);
    if (board) ink.clipboard(limbs.handA, done: j.phase.index >= Phase.reveal.index);
    if (flag) ink.flag(limbs.handB, t, color: BP.green);
    // What the foreman calls out.
    String? say;
    var show = 0.0;
    switch (j.phase) {
      case Phase.build when j.cutAt == null:
        final p = j.progress(t);
        show = seg(p, 0.86, 0.88) * (1 - seg(p, 0.96, 0.98));
        say = 'あと少し！ Almost!';
      case Phase.reveal:
        show = seg(u, 0.6, 0.9) * (1 - seg(u, 3.6, 3.9));
        say = '見て！ Look!';
      case Phase.demolish when j.phaseLen > 0:
        show = seg(u, 0.1, 0.35) * (1 - seg(u, 2.2, 2.5));
        say = '下がって！ Stand back!';
      default:
        break;
    }
    if (say != null && show > 0) _bubble(ink.c, limbs.head + const Offset(-4, -14), say, show, right: false);
  }

  /// A speech bubble whose tail points at [at] (the bubble sits up-left of
  /// it, or up-right when [right]).
  void _bubble(Canvas c, Offset at, String text, double alpha, {bool right = true}) {
    final tp = art.text.get(text, jaStyle(12, color: BP.ink, weight: 500));
    final w = tp.width + 14, h = tp.height + 8;
    final box = Rect.fromLTWH(right ? at.dx - 6 : at.dx - w + 6, at.dy - h - 7, w, h);
    c.saveLayer(box.inflate(8), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    final rr = RRect.fromRectAndRadius(box, const Radius.circular(7));
    final tail = Path()
      ..moveTo(at.dx + (right ? 2 : -2), box.bottom - 1)
      ..lineTo(at.dx, at.dy)
      ..lineTo(at.dx + (right ? 9 : -9), box.bottom - 1)
      ..close();
    final fill = _fl(BP.paper);
    final edge = _st(BP.amber, 1.2);
    c.drawRRect(rr, fill);
    c.drawPath(tail, fill);
    c.drawRRect(rr, edge);
    c.drawLine(Offset(at.dx + (right ? 2 : -2), box.bottom), at, edge);
    c.drawLine(at, Offset(at.dx + (right ? 9 : -9), box.bottom), edge);
    tp.paint(c, Offset(box.left + 7, box.top + 4));
    c.restore();
  }

  void _rigger(FactoryInk ink, Job j, BuildPlan? bp, double t) {
    final pose = Pose();
    var sign = false;
    if (bp != null && j.cutAt == null) {
      // Steering a pallet onto the stack, hooking up, signalling the lift.
      final feet = const Offset(riggerX, BL.groundY);
      final sh = shoulderOf(feet, crewH, 1, pose);
      Offset? target;
      for (final trip in bp.trips) {
        if (trip.attachAt > t + 1) break;
        if (t >= trip.attachAt - 0.05 && t < trip.departAt + 0.1) {
          final (_, hook) = sim.hookAt(t);
          target = hook + const Offset(0, 4);
        } else if (t >= trip.departAt + 0.1 && t < trip.departAt + 1.1) {
          sign = true;
        }
        for (var q = 0; q < trip.count; q++) {
          final at = bp.palletAt(trip.first + q);
          if (t >= at - 0.1 && t < at + hopTime) {
            final f = eio(seg(t, at, at + hopTime));
            target = Offset.lerp(Offset(BL.pickup.dx, palletFloor - 8), Offset(stageX, palletFloor - q * palletH - 8), f);
          }
        }
      }
      if (target != null) {
        final (up, fo) = reach(sh, target, crewH, 1);
        pose
          ..upA = up
          ..foA = fo
          ..lean = 0.1;
      }
      if (sign) {
        pose
          ..upB = 2.9
          ..foB = 3.0 + 0.4 * math.sin(t * 12);
      }
    }
    if (j.phase == Phase.celebrate) cheerPose(pose, t, 2);
    ink.worker(const Offset(riggerX, BL.groundY), crewH, 1, pose, hat: BP.coral);
  }

  @override
  bool shouldRepaint(_SitePainter old) => false;
}

/// In front of everything: the truck on the road (and its load), confetti.
class _SiteFront extends CustomPainter {
  _SiteFront(this.m, this.sim, this.art) : super(repaint: m);

  final BoothModel m;
  final SiteSim sim;
  final SiteArt art;

  @override
  void paint(Canvas c, Size size) {
    final j = m.job;
    if (j == null) return;
    final t = m.t;
    final ink = FactoryInk(c);
    final truck = sim.truck;
    final rb = sim.rubble;
    if (truck.visible(t)) {
      truck.body(ink, t, art.text);
      truck.bed(ink, t, art.text, () {
        if (rb == null) return;
        final colors = art.colorsFor(rb);
        final batch = art.pieces..begin(rb.count);
        final a = truck.angle(t);
        for (var i = 0; i < rb.count; i++) {
          if (rb.state[i] != Piece.truck.index) continue;
          final p = truck.world(t, rb.bedX(i), rb.bedY(i));
          batch.add(p.dx, p.dy, rb.size * 0.7, -a + i * 0.4, colors[i]);
        }
        batch.draw(c);
      });
    }
    if (truck.visible(t)) truck.beeper(ink, t, art.text);
    _guide(c, t);
    if (rb != null) {
      final colors = art.colorsFor(rb);
      final batch = art.pieces..begin(rb.count);
      for (var i = 0; i < rb.count; i++) {
        final st = rb.state[i];
        if (st == Piece.dropping.index) {
          batch.add(rb.x[i], rb.y[i], rb.size * 0.7, rb.ang[i], colors[i]);
        } else if (st == Piece.pouring.index) {
          final a = 1 - seg(rb.y[i], 772, 792);
          if (a > 0) batch.add(rb.x[i], rb.y[i], rb.size * 0.7, rb.ang[i], colors[i], alpha: a);
        }
      }
      batch.draw(c);
    }
    if (sim.celebrateAt.isFinite) {
      final len = sim.demolishAt.isFinite ? sim.demolishAt - sim.celebrateAt : sim.celebrateLen;
      confetti(c, t, sim.celebrateAt, len, j.serial);
    }
  }

  /// While the truck backs up past them, the crew guides it: 「オーライ！」
  void _guide(Canvas c, double t) {
    final tr = sim.truck;
    if (t < tr.reverseFrom || t > tr.reverseTo) return;
    final b = sim.builders[1];
    final a = seg(t, tr.reverseFrom, tr.reverseFrom + 0.3) * (1 - seg(t, tr.reverseTo - 0.3, tr.reverseTo));
    if (a <= 0) return;
    final tp = art.text.get('オーライ！ オーライ！', jaStyle(12, color: BP.ink, weight: 500));
    final at = Offset(b.x + 2, b.y - crewH - 6);
    final box = Rect.fromLTWH(at.dx - 6, at.dy - tp.height - 15, tp.width + 14, tp.height + 8);
    c.saveLayer(box.inflate(8), Paint()..color = Color.fromRGBO(0, 0, 0, a));
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(7)), _fl(BP.paper));
    c.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(7)), _st(BP.amber, 1.2));
    c.drawLine(Offset(at.dx + 2, box.bottom), at, _st(BP.amber, 1.2));
    tp.paint(c, Offset(box.left + 7, box.top + 4));
    c.restore();
  }

  @override
  bool shouldRepaint(_SiteFront old) => false;
}
