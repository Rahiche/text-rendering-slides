import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import 'crew.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Outro: the crew group photo. Everyone who built the text stands on the
// bleachers under a name tag (the libraries doing the work), the Flutter
// crew in front, the Latin trio lounging at the front as always. The
// photographer counts down, the flash goes off, the photo frames the crew;
// then again. Tap to take the photo now; hover someone to make them wave.
// ─────────────────────────────────────────────────────────────────────────────

const _ground = 742.0;
const _period = 11.0;

/// (name, tier, centre x, crew size). Tier 0 = back row.
const _groups = [
  ('Impeller', 0, 520.0, 4),
  ('Skia', 0, 710.0, 4),
  ('HarfBuzz', 0, 900.0, 4),
  ('ICU', 0, 1090.0, 4),
  ('SkParagraph', 1, 480.0, 4),
  ('Dart', 1, 690.0, 4),
  ('FreeType', 1, 910.0, 4),
  ('Noto', 1, 1130.0, 4),
  ('Flutter', 2, 820.0, 7),
];

double _tierY(int tier) => switch (tier) {
  0 => 548.0,
  1 => 646.0,
  _ => _ground,
};

class WorkersOutro extends StatelessWidget {
  const WorkersOutro({super.key});

  @override
  Widget build(BuildContext context) => SceneHost(painter: (clock, labels) => _OutroPainter(clock, labels));
}

class _OutroPainter extends CustomPainter {
  _OutroPainter(this.clock, this.labels) : super(repaint: clock);

  final SceneClock clock;
  final LabelCache labels;

  @override
  bool shouldRepaint(_OutroPainter old) => old.labels != labels;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.t;
    final k = CrewPainter(canvas, t);
    // Photo clock: a tap jumps straight to the countdown.
    final tapped = clock.sinceTap < 6;
    final lt = tapped ? 3.2 + clock.sinceTap : (t + 1.0) % _period;
    const flashAt = 6.0;
    final counting = lt >= 3 && lt < flashAt;
    final flash = span(lt, flashAt, flashAt + 0.6);
    final posing = lt >= flashAt - 0.4 && lt < flashAt + 0.5;
    final after = lt >= flashAt + 0.5;

    // ── the words ──
    final intro = easeOut3(span(t, 0.2, 1.2));
    final jp = labels.sample('ありがとうございました', 80, BP.ink, ja: true);
    _alpha(canvas, intro, () => jp.paint(canvas, Offset(800 - jp.width / 2, 60 + 20 * (1 - intro))));
    final en = labels.display('thank you', 44, BP.line, weight: 400);
    final ea = easeOut3(span(t, 0.6, 1.5));
    _alpha(canvas, ea, () => en.paint(canvas, Offset(800 - en.width / 2, 176)));
    final q1 = labels.mono('questions?', 24, BP.amber);
    final dot = labels.mono('·', 24, BP.inkFaint);
    final q2 = labels.sample('ご質問は？', 24, BP.amber, ja: true);
    final qw = q1.width + dot.width + q2.width + 32;
    final qa = easeOut3(span(t, 1.0, 1.8));
    _alpha(canvas, qa, () {
      var x = 800 - qw / 2;
      q1.paint(canvas, Offset(x, 252));
      x += q1.width + 16;
      dot.paint(canvas, Offset(x, 252));
      x += dot.width + 16;
      q2.paint(canvas, Offset(x, 252 + (q1.height - q2.height) / 2));
    });

    // ── bleachers ──
    final ink = inkStroke(BP.lineDim, 1.4);
    canvas
      ..drawLine(const Offset(380, 548), const Offset(1230, 548), ink)
      ..drawLine(const Offset(350, 646), const Offset(1260, 646), ink)
      ..drawLine(const Offset(80, _ground), const Offset(1520, _ground), inkStroke(BP.line, 1.5));
    for (final x in [380.0, 1230.0]) {
      canvas.drawLine(Offset(x, 548), Offset(x + (x < 800 ? -30 : 30), 646), ink);
    }
    for (final x in [350.0, 1260.0]) {
      canvas.drawLine(Offset(x, 646), Offset(x + (x < 800 ? -30 : 30), _ground), ink);
    }

    final crew = <Worker>[];
    var id = 0;
    for (final (name, tier, cx, n) in _groups) {
      final y = _tierY(tier);
      for (var j = 0; j < n; j++) {
        final x = cx + (j - (n - 1) / 2) * 32;
        final seed = hash01(id, 3);
        Pose p;
        if (posing) {
          p = seed < 0.55 ? Pose.cheer : Pose.stand;
        } else if (counting) {
          p = Pose.stand;
        } else if (after) {
          p = [Pose.wipe, Pose.stand, Pose.sit, Pose.cheer][(seed * 4).floor()];
          if (lt > flashAt + 2.5 && p == Pose.cheer) p = Pose.stand;
        } else {
          p = seed < 0.3 ? Pose.clipboard : Pose.stand;
        }
        final g = Worker(x, seed < 0.5 || counting || posing ? 1 : -1, p, y: y, id: 100 + id, item: p == Pose.clipboard ? Tool.clipboard : Tool.none)
          ..scale = tier == 2 ? 1.6 : 1.45
          ..wave = counting && seed > 0.8;
        crew.add(g);
        id++;
      }
      // Name tag.
      final tag = labels.mono(name, 14, name == 'Flutter' ? BP.amber : BP.line);
      final ty = tier == 2 ? _ground + 12 : y + 8;
      final r = Rect.fromCenter(center: Offset(cx, ty + tag.height / 2 + 2), width: tag.width + 18, height: tag.height + 6);
      canvas
        ..drawRect(r, inkFill(BP.paper))
        ..drawRect(r, inkStroke(name == 'Flutter' ? BP.amber : BP.lineDim, 1.2));
      tag.paint(canvas, Offset(r.left + 9, r.top + 3));
    }
    // The Latin trio, front left, unimpressed (one wakes up for the flash).
    final wake = flash > 0 && flash < 1;
    crew
      ..add(Worker(520, 1, Pose.coffee, y: _ground, id: 1, item: Tool.cup)..scale = 1.6)
      ..add(Worker(470, 1, Pose.lean, y: _ground, id: 2, k: posing ? 0 : 1)..scale = 1.6)
      ..add(Worker(590, 1, wake ? Pose.stand : Pose.lie, y: _ground, id: 3)
        ..scale = 1.6
        ..alarm = wake);
    final lt3 = labels.mono('latin', 14, BP.inkDim);
    final r3 = Rect.fromCenter(center: const Offset(530, _ground + 22), width: lt3.width + 18, height: lt3.height + 6);
    canvas
      ..drawRect(r3, inkFill(BP.paper))
      ..drawRect(r3, inkStroke(BP.lineFaint, 1.2));
    lt3.paint(canvas, Offset(r3.left + 9, r3.top + 3));

    // ── photographer + camera ──
    const cam = Offset(1350, 640);
    canvas
      ..drawLine(cam + const Offset(0, 16), const Offset(1330, _ground), inkStroke(BP.inkDim, 1.6))
      ..drawLine(cam + const Offset(0, 16), const Offset(1372, _ground), inkStroke(BP.inkDim, 1.6))
      ..drawLine(cam + const Offset(0, 16), const Offset(1352, _ground), inkStroke(BP.inkDim, 1.6));
    final body = Rect.fromCenter(center: cam, width: 58, height: 34);
    canvas
      ..drawRect(body, inkFill(BP.panel))
      ..drawRect(body, inkStroke(BP.line, 1.6))
      ..drawRect(Rect.fromLTWH(body.left + 8, body.top - 8, 16, 8), inkStroke(BP.line, 1.4))
      ..drawCircle(body.centerLeft + const Offset(-6, 0), 11, inkFill(BP.paper))
      ..drawCircle(body.centerLeft + const Offset(-6, 0), 11, inkStroke(BP.line, 1.6))
      ..drawCircle(body.centerLeft + const Offset(-6, 0), 5, inkStroke(BP.amber, 1.2));
    crew.add(Worker(1410, -1, counting ? Pose.signal : (posing ? Pose.point : Pose.clipboard), y: _ground, id: 90, ph: t * 7,
        item: counting || posing ? Tool.none : Tool.clipboard)
      ..scale = 1.6
      ..aim = cam);
    if (counting) {
      final n = (flashAt - lt).ceil().clamp(1, 3);
      final c = labels.display('$n', 54, BP.amber, weight: 600);
      final pulse = 1 + 0.25 * (1 - ((flashAt - lt) % 1));
      canvas
        ..save()
        ..translate(cam.dx, cam.dy - 70)
        ..scale(pulse);
      c.paint(canvas, Offset(-c.width / 2, -c.height / 2));
      canvas.restore();
    }

    waveNearest(crew, clock.pointer);
    k.drawCrew(crew);
    for (final g in crew) {
      if (g.id == 3 && g.p == Pose.lie) k.zzz(g.head, t);
    }

    // ── the photo ──
    final frameA = span(lt, flashAt + 0.1, flashAt + 0.5) * (1 - span(lt, _period - 1.2, _period - 0.4));
    if (frameA > 0) {
      canvas
        ..save()
        ..translate(810, 650)
        ..rotate(-0.012 * frameA)
        ..translate(-810, -650);
      const outer = Rect.fromLTRB(320, 462, 1300, 786);
      final p = inkStroke(BP.ink, 3, frameA);
      canvas.drawRect(outer, p);
      canvas.drawRect(outer.deflate(8), inkStroke(BP.lineDim, 1, frameA));
      final cap = labels.mono('crew · 104', 13, BP.inkDim);
      _alpha(canvas, frameA, () => cap.paint(canvas, Offset(outer.right - cap.width - 14, outer.top + 12)));
      canvas.restore();
    }
    if (flash > 0 && flash < 1) {
      final a = math.pow(1 - flash, 2).toDouble();
      canvas.drawRect(Offset.zero & size, inkFill(BP.ink, 0.28 * a));
      final lens = body.centerLeft + const Offset(-6, 0);
      canvas.drawCircle(lens, 20 + 260 * flash, inkFill(BP.ink, 0.35 * a));
      for (var i = 0; i < 12; i++) {
        final an = i * math.pi / 6;
        canvas.drawLine(lens + Offset(math.cos(an), math.sin(an)) * 18, lens + Offset(math.cos(an), math.sin(an)) * (30 + 90 * flash),
            inkStroke(BP.amber, 2, a));
      }
    }
  }

  void _alpha(Canvas c, double a, void Function() draw) {
    if (a <= 0.01) return;
    if (a >= 0.99) {
      draw();
      return;
    }
    c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    draw();
    c.restore();
  }
}
