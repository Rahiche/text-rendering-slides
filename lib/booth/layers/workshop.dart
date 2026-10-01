import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../craft/method.dart';
import '../craft/plan.dart';
import '../craft/stage.dart';
import '../craft/workshop_layout.dart';
import '../layer.dart';
import '../layout.dart';
import '../model.dart';

/// The Name Workshop (craft mode): characters are made one at a time on the
/// dais, each in a different craft, then the gantry hangs them on the name
/// sign. When the name is complete the sign lights up, then it's lowered
/// onto a truck and delivered.
class WorkshopLayer extends BoothLayer {
  final _text = TextCache();

  @override
  CustomPainter painter(BoothModel m) => _WorkshopPainter(m, _text);

  @override
  void dispose() => _text.dispose();
}

// Parts of one character's window (fractions of it).
const _setupEnd = CraftPlan.setup;
const _makeEnd = 1 - CraftPlan.finish - CraftPlan.transfer;
const _finishEnd = 1 - CraftPlan.transfer;

class _WorkshopPainter extends CustomPainter {
  _WorkshopPainter(this.m, this.text) : super(repaint: m);

  final BoothModel m;
  final TextCache text;

  late Canvas c;
  late FactoryInk ink;
  late double t;

  TextPainter _label(
    String s,
    double size, {
    Color color = BP.ink,
    double weight = 500,
    bool mono = false,
  }) => text.get(
    s,
    mono
        ? BT.mono(size, color: color, weight: weight)
        : BT.sample(size, color: color, weight: weight).copyWith(locale: jaLocale),
  );

  CraftContext _ctx(CraftChar ch) =>
      CraftContext(c: c, ink: ink, text: text, s: ch.stage, t: t, seed: ch.seed, char: ch.char);

  @override
  void paint(Canvas canvas, Size size) {
    c = canvas;
    t = m.t;
    ink = FactoryInk(c);
    final j = m.job;
    final plan = j == null || j.mode != BuildMode.craft ? null : j.plan;
    final f = j?.buildProgress(t) ?? 0;

    _hall();
    _office(j, plan, f);

    // Delivery: the sign is lowered onto a truck and driven away.
    var signOffset = Offset.zero;
    var newSign = 1.0; // the next, empty sign coming down (cleanup)
    var truckX = double.nan;
    if (j != null && (j.phase == Phase.demolish || j.phase == Phase.cleanup)) {
      final u = j.progress(t);
      const bed = 756.0;
      final drop = bed - BW.sign.bottom;
      if (j.phase == Phase.demolish) {
        truckX = lerp(1780, BW.sign.center.dx + 30, eo(seg(u, 0, 0.3)));
        signOffset = Offset(0, drop * eio(seg(u, 0.3, 0.85)));
        newSign = 0;
      } else {
        truckX = BW.sign.center.dx + 30 + 900 * ei(seg(u, 0.05, 0.7));
        signOffset = Offset(truckX - (BW.sign.center.dx + 30), drop);
        newSign = eo(seg(u, 0.45, 1));
      }
    }
    final delivering = !truckX.isNaN;
    if (!delivering) _sign(j, plan, f, Offset.zero);
    if (delivering && newSign > 0) _emptySign(Offset(0, -260 * (1 - newSign)));
    _dais();
    _stage(j, plan, f);
    if (delivering) {
      if (j!.phase == Phase.demolish) _hoists(signOffset);
      _sign(j, plan, 1, signOffset);
      _truck(truckX);
    }
    if (j != null && j.phase == Phase.celebrate) _celebrate(j, plan);
  }

  // ── The hall ──────────────────────────────────────────────────────────────

  void _hall() {
    final h = BW.hall;
    final col = ink.st(BP.lineDim, 2);
    for (final x in [h.left + 12, h.right - 12]) {
      c.drawRect(Rect.fromLTRB(x - 9, h.top, x + 9, h.bottom), ink.fl(BP.paper));
      c.drawRect(Rect.fromLTRB(x - 9, h.top, x + 9, h.bottom), col);
      final braces = Path();
      for (var y = h.top + 20; y < h.bottom - 20; y += 36) {
        braces
          ..moveTo(x - 9, y)
          ..lineTo(x + 9, y + 18)
          ..moveTo(x + 9, y + 18)
          ..lineTo(x - 9, y + 36);
      }
      c.drawPath(braces, ink.st(BP.lineFaint, 1));
    }
    // Roof truss.
    final truss = Path()
      ..moveTo(h.left, h.top)
      ..lineTo(h.right, h.top)
      ..moveTo(h.left, h.top + 18)
      ..lineTo(h.right, h.top + 18);
    for (var x = h.left; x < h.right; x += 36) {
      truss
        ..moveTo(x, h.top + 18)
        ..lineTo(x + 18, h.top)
        ..lineTo(x + 36, h.top + 18);
    }
    c.drawPath(truss, ink.st(BP.lineDim, 1.4));
    // Gantry beam.
    c.drawRect(
      Rect.fromLTRB(h.left + 12, BW.beamY - 5, h.right - 12, BW.beamY + 5),
      ink.fl(BP.panel),
    );
    c.drawRect(
      Rect.fromLTRB(h.left + 12, BW.beamY - 5, h.right - 12, BW.beamY + 5),
      ink.st(BP.amber.withValues(alpha: 0.7), 1.3),
    );
    // Workshop sign on the truss.
    final title = _label('名前工房 · Name Workshop', 22, color: BP.amber, weight: 600);
    final r = Rect.fromCenter(
      center: Offset(h.center.dx, h.top - 18),
      width: title.width + 34,
      height: 34,
    );
    ink.box(r, col: BP.amber);
    title.paint(c, r.center - Offset(title.width / 2, title.height / 2));
  }

  void _dais() {
    final d = BW.dais;
    c.drawRect(d, ink.fl(BP.panel));
    c.drawRect(d, ink.st(BP.line, 1.4));
    final stripes = Path();
    for (var x = d.left + 6; x < d.right - 12; x += 22) {
      stripes
        ..moveTo(x, d.bottom - 2)
        ..lineTo(x + 10, d.top + 2);
    }
    c.drawPath(stripes, ink.st(BP.amber.withValues(alpha: 0.35), 2));
  }

  // ── The drafting office (left) ────────────────────────────────────────────

  void _office(Job? j, CraftPlan? plan, double f) {
    final o = BW.office;
    // Room outline with a little roof.
    final room = Path()
      ..moveTo(o.left, o.bottom)
      ..lineTo(o.left, o.top + 26)
      ..lineTo(o.left + 40, o.top)
      ..lineTo(o.right - 40, o.top)
      ..lineTo(o.right, o.top + 26)
      ..lineTo(o.right, o.bottom);
    c.drawPath(room, ink.st(BP.lineDim, 1.6));
    final tag = _label('設計室 · Drafting', 18, color: BP.inkDim);
    tag.paint(c, Offset(o.left + 48, o.top + 4));

    // Blueprint board.
    final board = Rect.fromLTWH(o.left + 22, o.top + 40, 250, 220);
    c.drawRect(board, ink.fl(const Color(0xFF0E3A66)));
    c.drawRect(board, ink.st(BP.line, 1.4));
    final grid = Path();
    for (var x = board.left + 12.5; x < board.right; x += 12.5) {
      grid
        ..moveTo(x, board.top)
        ..lineTo(x, board.bottom);
    }
    for (var y = board.top + 12.5; y < board.bottom; y += 12.5) {
      grid
        ..moveTo(board.left, y)
        ..lineTo(board.right, y);
    }
    c.drawPath(grid, ink.st(BP.line.withValues(alpha: 0.12), 0.8));
    // Table legs.
    c.drawLine(
      Offset(board.left + 30, board.bottom),
      Offset(board.left + 20, o.bottom),
      ink.st(BP.lineDim, 2),
    );
    c.drawLine(
      Offset(board.right - 30, board.bottom),
      Offset(board.right - 20, o.bottom),
      ink.st(BP.lineDim, 2),
    );

    // Which character is on the board.
    CraftChar? ch;
    var draw = 1.0;
    if (plan != null && plan.chars.isNotEmpty) {
      if (j!.phase == Phase.intake) {
        ch = plan.chars.first;
        draw = j.progress(t);
      } else {
        final k = plan.current(f) ?? plan.chars.length - 1;
        ch = plan.chars[k];
        draw = j.phase == Phase.build ? (seg((f - ch.start) / (ch.end - ch.start), 0, 0.25)) : 1;
      }
    }
    if (ch != null) _blueprint(ch, board.deflate(18), draw);

    // Draftsperson at the board.
    final pose = Pose()
      ..sit(46, 26)
      ..upA = 1.6 + 0.25 * math.sin(t * 3.1)
      ..foA = 2.0 + 0.2 * math.sin(t * 4.3);
    final feet = Offset(board.right + 34, o.bottom);
    c.drawRect(Rect.fromLTWH(feet.dx - 12, o.bottom - 26, 24, 4), ink.fl(BP.lineDim));
    ink.worker(feet, 46, -1, pose, hat: BP.inkDim, helmet: false);

    // Plan board (right).
    final pb = Rect.fromLTRB(o.left + 330, o.top + 40, o.right - 14, o.bottom - 14);
    ink.box(pb, col: BP.lineDim);
    _label('制作計画 · Plan', 18, color: BP.inkDim).paint(c, Offset(pb.left + 10, pb.top + 6));
    if (plan == null) return;
    final n = plan.chars.length;
    final cols = n > 8 ? 2 : 1;
    final rows = (n / cols).ceil();
    final rowH = math.min(34.0, (pb.height - 40) / math.max(rows, 1));
    final colW = (pb.width - 12) / cols;
    final shown = j!.phase == Phase.intake ? (j.progress(t) * 1.4 * n).floor() : n;
    final cur = j.phase == Phase.build ? plan.current(f) : null;
    for (var k = 0; k < math.min(shown, n); k++) {
      final ch = plan.chars[k];
      final cx = pb.left + 8 + (k ~/ rows) * colW;
      final cy = pb.top + 34 + (k % rows) * rowH;
      final done = f >= ch.end || j.phase.index > Phase.build.index;
      final now = cur == k;
      if (now) {
        c.drawRect(
          Rect.fromLTWH(cx - 4, cy, colW - 4, rowH - 2),
          ink.fl(BP.amber.withValues(alpha: 0.16)),
        );
      }
      final g = _label(
        ch.char,
        math.min(22, rowH * 0.7),
        color: now ? BP.amber : BP.ink,
        weight: 600,
      );
      g.paint(c, Offset(cx, cy + (rowH - g.height) / 2));
      final m = _label(
        ch.method.ja,
        math.min(18, rowH * 0.55),
        color: done ? BP.green : (now ? BP.amber : BP.inkDim),
      );
      m.paint(c, Offset(cx + 30, cy + (rowH - m.height) / 2));
      if (done) {
        final ok = _label('✓', 16, color: BP.green, mono: true);
        ok.paint(c, Offset(cx + colW - 26, cy + (rowH - ok.height) / 2));
      }
    }
  }

  /// The character as the workshop reads it: outline traced (marching
  /// squares) and the centre-line strokes, numbered in writing order.
  void _blueprint(CraftChar ch, Rect box, double draw) {
    final g = ch.geo;
    if (g.isEmpty) return;
    final k = math.min(box.width / g.inkWidth, box.height / g.inkHeight);
    final o = Offset(
      box.center.dx - (g.inkLeft + g.inkWidth / 2) * k,
      box.center.dy - (g.inkTop + g.inkHeight / 2) * k,
    );
    final s = ch.stage;
    c.save();
    c.translate(o.dx, o.dy);
    c.scale(k / s.k);
    c.translate(-s.origin.dx, -s.origin.dy);
    final w = s.k / k;
    c.drawPath(
      s.outlineUpTo(seg(draw, 0, 0.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = BP.ink
        ..strokeWidth = 1.4 * w,
    );
    final strokes = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = BP.amber
      ..strokeWidth = 2.2 * w;
    final sp = seg(draw, 0.45, 1);
    c.drawPath(_strokesPath(s, sp), strokes);
    c.restore();
    // Stroke numbers (first 12).
    if (sp <= 0) return;
    for (var i = 0; i < math.min(12, s.strokes.length); i++) {
      final st = s.strokes[i];
      if (st.start > sp * s.strokeLength) break;
      final p0 = st.pts.first;
      final at = o + (p0 - s.origin) * (k / s.k);
      c.drawCircle(at, 9, ink.fl(BP.amber));
      final n = _label('${i + 1}', 13, color: BP.paper, weight: 700, mono: true);
      n.paint(c, at - Offset(n.width / 2, n.height / 2));
    }
  }

  Path _strokesPath(GlyphStage s, double p) {
    final out = Path();
    final d = p * s.strokeLength;
    for (final st in s.strokes) {
      if (d <= st.start) break;
      final m = st.path.computeMetrics().firstOrNull;
      if (m == null) continue;
      out.addPath(m.extractPath(0, math.min(m.length, d - st.start)), Offset.zero);
    }
    return out;
  }

  // ── The name sign ─────────────────────────────────────────────────────────

  void _signFrame(Rect r, double lights) {
    // Cables up to the truss.
    for (final x in [r.left + 40, r.right - 40]) {
      c.drawLine(Offset(x, BW.hall.top + 18), Offset(x, r.top), ink.st(BP.lineDim, 1.2));
    }
    c.drawRect(r, ink.fl(BP.panel));
    c.drawRect(r, ink.st(BP.line, 2));
    // Bulbs around the frame.
    final per = (r.width / 26).floor();
    for (var i = 0; i <= per; i++) {
      for (final y in [r.top + 7, r.bottom - 7]) {
        final p = Offset(r.left + 6 + (r.width - 12) * i / per, y);
        final on = lights > 0 && (lights >= 1 ? ((t * 6).floor() + i) % 3 != 0 : i / per < lights);
        c.drawCircle(p, 3.2, ink.fl(on ? BP.amber : BP.lineFaint));
        if (on) c.drawCircle(p, 7, Paint()..color = BP.amber.withValues(alpha: 0.18));
      }
    }
  }

  void _emptySign(Offset o) => _signFrame(BW.sign.shift(o), 0);

  void _sign(Job? j, CraftPlan? plan, double f, Offset o) {
    var lights = 0.0;
    if (j != null && plan != null) {
      if (j.phase == Phase.reveal) lights = j.progress(t);
      if (j.phase == Phase.celebrate || j.phase == Phase.demolish) lights = 1;
    }
    _signFrame(BW.sign.shift(o), lights);
    if (plan == null) return;
    for (var k = 0; k < plan.chars.length; k++) {
      final ch = plan.chars[k];
      final dst = ch.signInk.shift(o);
      final hung =
          f >= ch.end || (j != null && j.phase.index > Phase.build.index && j.cutFrac == null);
      if (hung) {
        _drawFinishedAt(ch, dst);
        if (j!.phase == Phase.reveal) {
          // A glint sweeping across each letter as the lights come on.
          final g = seg(
            j.progress(t),
            k / plan.chars.length * 0.8,
            k / plan.chars.length * 0.8 + 0.25,
          );
          if (g > 0 && g < 1) {
            final x = lerp(dst.left - 20, dst.right + 20, g);
            c.drawLine(
              Offset(x, dst.top),
              Offset(x - 16, dst.bottom),
              ink.st(BP.ink.withValues(alpha: 0.8), 3),
            );
          }
        }
      } else {
        // What's coming: a faint outline in its slot.
        c.save();
        _toRect(ch, dst);
        c.drawPath(
          ch.stage.outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = BP.lineFaint
            ..strokeWidth = 1.2 * ch.stage.ink.height / dst.height,
        );
        c.restore();
      }
    }
  }

  /// Maps the character's dais ink rect onto [dst] (uniform scale).
  void _toRect(CraftChar ch, Rect dst) {
    final src = ch.stage.ink;
    final s = dst.height / math.max(1, src.height);
    c.translate(dst.left, dst.top);
    c.scale(s);
    c.translate(-src.left, -src.top);
  }

  void _drawFinishedAt(CraftChar ch, Rect dst) {
    c.save();
    _toRect(ch, dst);
    ch.method.paintFinished(_ctx(ch));
    c.restore();
  }

  // ── The dais ──────────────────────────────────────────────────────────────

  void _stage(Job? j, CraftPlan? plan, double f) {
    if (j == null || plan == null || j.phase != Phase.build) {
      _idleCrew(j);
      _trolley(BW.hall.right - 90, null);
      return;
    }
    final k = plan.current(f);
    if (k == null) {
      _trolley(BW.hall.right - 90, null);
      return;
    }
    final ch = plan.chars[k];
    final u = (f - ch.start) / (ch.end - ch.start);
    final x = _ctx(ch);
    _craftSign(ch);
    if (u < _setupEnd) {
      final p = u / _setupEnd;
      // Marking out: a chalk outline traced on the dais while the material arrives.
      c.drawPath(ch.stage.outlineUpTo(p), ink.st(BP.lineFaint, 1.2));
      _cart(ch, p);
      _trolley(BW.hall.right - 90, null);
    } else if (u < _makeEnd) {
      ch.method.paintMaking(x, (u - _setupEnd) / (_makeEnd - _setupEnd));
      _trolley(BW.hall.right - 90, null);
    } else if (u < _finishEnd) {
      ch.method.paintFinished(x);
      _inspect(ch, (u - _makeEnd) / (_finishEnd - _makeEnd));
      _trolley(
        lerp(
          BW.hall.right - 90,
          ch.stage.ink.center.dx,
          eio((u - _makeEnd) / (_finishEnd - _makeEnd)),
        ),
        null,
      );
    } else {
      _transfer(ch, (u - _finishEnd) / (1 - _finishEnd));
    }
  }

  void _craftSign(CraftChar ch) {
    final r = Rect.fromLTWH(BW.dais.left - 104, BW.floorY - 112, 96, 104);
    c.drawLine(
      Offset(r.left + 14, r.bottom),
      Offset(r.left + 14, BW.floorY),
      ink.st(BP.lineDim, 2),
    );
    c.drawLine(
      Offset(r.right - 14, r.bottom),
      Offset(r.right - 14, BW.floorY),
      ink.st(BP.lineDim, 2),
    );
    ink.box(r, col: ch.method.color);
    final ja = _label(
      ch.method.ja,
      ch.method.ja.length > 4 ? 18 : 24,
      color: ch.method.color,
      weight: 600,
    );
    ja.paint(c, Offset(r.center.dx - ja.width / 2, r.top + 8));
    final en = _label(ch.method.en, 13, color: BP.inkDim, mono: true);
    en.paint(c, Offset(r.center.dx - en.width / 2, r.top + 40));
    final g = _label('${ch.char}  ${ch.hex}', 14, color: BP.ink, mono: true);
    g.paint(c, Offset(r.center.dx - g.width / 2, r.bottom - g.height - 10));
  }

  void _cart(CraftChar ch, double p) {
    final x = lerp(BW.hall.left + 30, BW.dais.left + 60, eo(p));
    final cart = Rect.fromLTWH(x, BW.floorY - 30, 70, 22);
    ink.box(cart, col: ch.method.color);
    c.drawCircle(Offset(cart.left + 12, BW.floorY - 5), 5, ink.fl(BP.paper));
    c.drawCircle(Offset(cart.left + 12, BW.floorY - 5), 5, ink.st(BP.lineDim, 1.2));
    c.drawCircle(Offset(cart.right - 12, BW.floorY - 5), 5, ink.fl(BP.paper));
    c.drawCircle(Offset(cart.right - 12, BW.floorY - 5), 5, ink.st(BP.lineDim, 1.2));
    c.drawRect(
      Rect.fromLTWH(cart.left + 10, cart.top - 22, 50, 22),
      ink.fl(ch.method.color.withValues(alpha: 0.35)),
    );
    c.drawRect(Rect.fromLTWH(cart.left + 10, cart.top - 22, 50, 22), ink.st(ch.method.color, 1.2));
    final pose = Pose()
      ..walk(t * 8)
      ..lean = 0.25
      ..upA = 1.3
      ..foA = 1.5;
    ink.worker(Offset(x - 22, BW.floorY), 48, 1, pose);
  }

  void _inspect(CraftChar ch, double p) {
    final s = ch.stage;
    final feet = Offset(s.ink.right + 40, BW.dais.top);
    final pose = Pose();
    final limbs = ink.worker(feet, 48, -1, pose, hat: BP.green);
    ink.clipboard(limbs.handA, done: p > 0.5);
    if (p > 0.4) {
      final pop = eo(seg(p, 0.4, 0.7));
      final at = Offset(s.ink.right - 6, s.ink.top + 10);
      c.drawCircle(at, 22 * pop, ink.fl(BP.green));
      final ok = _label('✓', 26, color: BP.paper, weight: 700, mono: true);
      if (pop > 0.6) ok.paint(c, at - Offset(ok.width / 2, ok.height / 2));
    }
  }

  void _trolley(double x, Offset? hook) {
    final r = Rect.fromCenter(center: Offset(x, BW.beamY), width: 46, height: 20);
    ink.box(r, col: BP.amber);
    c.drawRect(Rect.fromLTWH(r.left + 6, r.bottom, 16, 14), ink.fl(BP.panel));
    c.drawRect(Rect.fromLTWH(r.left + 6, r.bottom, 16, 14), ink.st(BP.amber, 1.2));
    final h = hook ?? Offset(x, BW.beamY + 46);
    c.drawLine(Offset(x + 8, r.bottom), Offset(h.dx + 8, h.dy - 8), ink.st(BP.inkDim, 1.2));
    final hp = Path()
      ..moveTo(h.dx + 8, h.dy - 8)
      ..lineTo(h.dx + 8, h.dy)
      ..arcToPoint(Offset(h.dx + 2, h.dy + 2), radius: const Radius.circular(4));
    c.drawPath(hp, ink.st(BP.amber, 2));
  }

  void _transfer(CraftChar ch, double p) {
    final src = ch.stage.ink, dst = ch.signInk;
    final s = dst.height / src.height;
    final up = Rect.fromCenter(
      center: Offset(src.center.dx, dst.center.dy),
      width: src.width * s,
      height: dst.height,
    );
    Rect r;
    if (p < 0.45) {
      final q = eio(p / 0.45);
      r = Rect.lerp(src, up, q)!;
    } else {
      r = Rect.lerp(up, dst, eio((p - 0.45) / 0.55))!;
    }
    _trolley(r.center.dx, Offset(r.center.dx, r.top - 6));
    c.drawLine(Offset(r.center.dx + 8, r.top - 6), Offset(r.left + 4, r.top), ink.st(BP.inkDim, 1));
    c.drawLine(
      Offset(r.center.dx + 8, r.top - 6),
      Offset(r.right - 4, r.top),
      ink.st(BP.inkDim, 1),
    );
    _drawFinishedAt(ch, r);
    _idleCrew(null, waving: true);
  }

  void _idleCrew(Job? j, {bool waving = false}) {
    // Two workers by the dais: one sweeping, one with coffee (or waving the
    // finished letter off).
    final y = BW.floorY;
    final a = Pose();
    if (waving) {
      a.wave(t);
    } else {
      a.wipe(t);
    }
    final la = ink.worker(Offset(BW.dais.left + 80, y), 48, 1, a, hat: BP.amber);
    if (!waving) ink.broom(la.handA, la.elbowA, y, math.sin(t * 5));
    final b = Pose()..upA = 1.5;
    final lb = ink.worker(Offset(BW.dais.right - 70, y), 48, -1, b, hat: BP.coral);
    ink.coffee(lb.handA, t);
  }

  // ── Celebration & delivery ────────────────────────────────────────────────

  void _celebrate(Job j, CraftPlan? plan) {
    final u = j.progress(t);
    // Confetti from the truss.
    const colors = [BP.amber, BP.green, BP.pink, BP.line, BP.violet, BP.coral];
    for (var i = 0; i < 90; i++) {
      final x0 = BW.hall.left + rnd(i, 1) * BW.hall.width;
      final speed = 60 + 90 * rnd(i, 2);
      final y = BW.hall.top + 20 + ((t * speed + rnd(i, 3) * 600) % 560);
      final x = x0 + 18 * math.sin(t * 2 + i);
      c.save();
      c.translate(x, y);
      c.rotate(t * 3 + i);
      c.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), ink.fl(colors[i % colors.length]));
      c.restore();
    }
    // Banner over the dais.
    final banner = _label('完成！ Done!', 40, color: BP.amber, weight: 700);
    final stats = plan == null
        ? null
        : _label(
            '${plan.chars.length} characters · ${plan.chars.map((c) => c.method.id).toSet().length} crafts · ${_mmss(j.buildLen)}',
            20,
            color: BP.ink,
          );
    final pop = eo(seg(u, 0, 0.15));
    final r = Rect.fromCenter(
      center: Offset(BW.dais.center.dx, 420),
      width: 520 * pop,
      height: 104 * pop,
    );
    if (pop > 0.05) {
      ink.box(r, col: BP.amber);
      if (pop > 0.9) {
        banner.paint(c, Offset(r.center.dx - banner.width / 2, r.top + 12));
        stats?.paint(c, Offset(r.center.dx - stats.width / 2, r.bottom - stats.height - 12));
      }
    }
    // Crew cheering on the dais.
    for (var i = 0; i < 4; i++) {
      final pose = Pose()..cheer(t, i);
      ink.worker(
        Offset(BW.dais.left + 90 + i * 130, BW.dais.top),
        50,
        i.isEven ? 1 : -1,
        pose,
        hat: [BP.amber, BP.green, BP.coral, BP.line][i],
      );
    }
  }

  String _mmss(double s) => '${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, '0')}';

  void _hoists(Offset o) {
    for (final x in [BW.sign.left + 40, BW.sign.right - 40]) {
      c.drawLine(
        Offset(x, BW.hall.top + 18),
        Offset(x + o.dx, BW.sign.top + o.dy),
        ink.st(BP.lineDim, 1.2),
      );
    }
  }

  void _truck(double x) {
    if (x > 1800) return;
    final y = BL.road.top + 52;
    final bed = Rect.fromLTRB(x - 430, y - 30, x + 330, y - 12);
    ink.box(bed, col: BP.line);
    final cab = Rect.fromLTRB(x + 330, y - 80, x + 430, y - 12);
    ink.box(cab, col: BP.amber);
    c.drawRect(
      Rect.fromLTRB(cab.left + 50, cab.top + 10, cab.right - 12, cab.top + 36),
      ink.fl(BP.lineFaint),
    );
    final door = _label('配送 Delivery', 13, color: BP.amber, mono: true);
    door.paint(c, Offset(cab.left + 8, cab.bottom - door.height - 6));
    for (final wx in [bed.left + 50, bed.left + 140, bed.right - 90, cab.center.dx]) {
      final w = Offset(wx, y - 4);
      c.drawCircle(w, 14, ink.fl(BP.paper));
      c.drawCircle(w, 14, ink.st(BP.line, 1.6));
      final a = -x / 14;
      c.drawLine(w, w + Offset(math.cos(a), math.sin(a)) * 12, ink.st(BP.lineDim, 1.4));
    }
  }

  @override
  bool shouldRepaint(_WorkshopPainter old) => false;
}
