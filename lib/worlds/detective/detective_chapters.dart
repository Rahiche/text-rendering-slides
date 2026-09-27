import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../deck/theme.dart';
import '../../deck/widgets.dart';
import '../world.dart';
import 'chapter_scenes_a.dart';
import 'chapter_scenes_b.dart';
import 'noir_kit.dart';

/// Noir chapter names and the Japanese subtitles, per section.
const chapterNames = ['the scene', 'the suspects', 'other precincts', 'the motive', 'the reconstruction'];
const chapterSubtitles = [
  '「コードポイントからピクセルへ」',
  '「文字体系ごとに増えるルール」',
  '「他のエンジンはどうしている？」',
  '「Flutterのトレードオフ」',
  '「ひとつの単語の旅」',
];

/// What a scene gets every frame.
class SceneCtx {
  SceneCtx({required this.t, required this.dt, required this.pointer, required this.labels, required this.info});

  /// Seconds since the slide appeared, and since the last frame.
  final double t;
  final double dt;

  /// Pointer in canvas coordinates (null when outside).
  final Offset? pointer;
  final LabelCache labels;
  final SectionInfo info;

  double get clock => noirSeconds;
}

/// One chapter's scene: paints into the right part of the canvas
/// (x 600–1540, y 40–580) and reacts to the pointer.
abstract class ChapterScene {
  void paint(Canvas canvas, SceneCtx c);
  void tap(Offset p, SceneCtx c) {}
  void drag(Offset delta, SceneCtx c) {}
  void dispose() {}
}

ChapterScene _sceneFor(int i) => switch (i) {
  0 => CrimeScene(),
  1 => SuspectsScene(),
  2 => PrecinctsScene(),
  3 => InterrogationScene(),
  _ => BoardScene(),
};

/// A section divider as a case chapter: big number + title, the noir
/// chapter name, the Japanese subtitle, and a scene that moves the story on.
class DetectiveChapter extends StatefulWidget {
  const DetectiveChapter({super.key, required this.info});

  final SectionInfo info;

  @override
  State<DetectiveChapter> createState() => _DetectiveChapterState();
}

class _DetectiveChapterState extends State<DetectiveChapter> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);
  final _labels = LabelCache();
  late ChapterScene _scene = _sceneFor(widget.info.index);
  Offset? _pointer;
  double _last = 0;
  double _dt = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      final t = d.inMicroseconds / 1e6;
      _dt = (t - _last).clamp(0.0, 0.1);
      _last = t;
      _time.value = t;
    })..start();
  }

  @override
  void didUpdateWidget(DetectiveChapter old) {
    super.didUpdateWidget(old);
    if (old.info.index != widget.info.index) {
      _scene.dispose();
      _scene = _sceneFor(widget.info.index);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _labels.dispose();
    _scene.dispose();
    super.dispose();
  }

  SceneCtx _ctx() => SceneCtx(t: _time.value, dt: _dt, pointer: _pointer, labels: _labels, info: widget.info);

  @override
  Widget build(BuildContext context) {
    final s = widget.info;
    return MouseRegion(
      onHover: (e) => _pointer = e.localPosition,
      onExit: (_) => _pointer = null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (e) => _scene.tap(e.localPosition, _ctx()),
        onPanUpdate: (e) {
          _pointer = e.localPosition;
          _scene.drag(e.delta, _ctx());
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _ChapterPainter(this, _time)),
              ),
            ),
            Positioned(
              left: 96,
              top: 64,
              child: Reveal(
                visible: true,
                offset: const Offset(-30, 0),
                child: Text(
                  s.number,
                  style: BT.display(250, weight: 700, height: 1).copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 2.5
                      ..color = BP.line,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 108,
              top: 340,
              child: Reveal(
                visible: true,
                delay: const Duration(milliseconds: 300),
                offset: const Offset(-30, 0),
                child: Row(
                  children: [
                    Text('CHAPTER ${s.number}', style: BT.mono(16, color: BP.inkDim)),
                    const SizedBox(width: 16),
                    Transform.rotate(
                      angle: -0.03,
                      child: EvidenceTag(chapterNames[s.index], size: 22, filled: true),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 96,
              top: 598,
              child: Reveal(
                visible: true,
                delay: const Duration(milliseconds: 450),
                child: Text(s.title, style: BT.display(78, letterSpacing: -1.5, height: 1)),
              ),
            ),
            Positioned(
              left: 100,
              top: 700,
              child: Reveal(
                visible: true,
                delay: const Duration(milliseconds: 650),
                child: Row(
                  children: [
                    Container(width: 36, height: 1.5, color: BP.amber),
                    const SizedBox(width: 14),
                    Text(chapterSubtitles[s.index], style: NT.jp(30, color: BP.inkDim)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterPainter extends CustomPainter {
  _ChapterPainter(this.s, this.time) : super(repaint: time);

  final _DetectiveChapterState s;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final c = s._ctx();
    // Scene area: fade + slide in.
    final a = segOut(c.t, 0.2, 1.1);
    if (a <= 0) return;
    canvas.saveLayer(const Rect.fromLTWH(560, 0, 1040, 600), Paint()..color = Colors.white.withValues(alpha: a));
    canvas.translate(40 * (1 - a), 0);
    s._scene.paint(canvas, c);
    canvas.restore();
    // A thin rule under the scene, like a case-file divider.
    final w = 1440 * segOut(c.t, 0.3, 1.2);
    canvas.drawLine(const Offset(96, 584), Offset(96 + w, 584), Paint()
      ..color = BP.lineDim
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ChapterPainter old) => old.s != s;
}

/// Shared: a detective's floor-shadow ellipse.
void paintShadow(Canvas canvas, Offset feet, double w) {
  canvas.drawOval(
    Rect.fromCenter(center: feet + const Offset(0, 2), width: w, height: w * 0.16),
    Paint()..color = Colors.black.withValues(alpha: 0.25),
  );
}

/// Shared: an easing ping-pong in 0..1 with holds at both ends.
double pingPong(double t, double period) {
  final u = (t % period) / period;
  return u < 0.5 ? seg(u, 0.05, 0.45) : 1 - seg(u, 0.55, 0.95);
}

/// Shared: evidence tent marker with a number.
void paintMarker(Canvas canvas, Offset base, String n, LabelCache labels, {double s = 1}) {
  final w = 26 * s, h = 30 * s;
  final p = Path()
    ..moveTo(base.dx - w / 2, base.dy)
    ..lineTo(base.dx - w * 0.3, base.dy - h)
    ..lineTo(base.dx + w * 0.3, base.dy - h)
    ..lineTo(base.dx + w / 2, base.dy)
    ..close();
  canvas.drawPath(p, Paint()..color = BP.amber);
  canvas.drawPath(p, Paint()
    ..color = BP.paper
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1);
  final tp = labels.get(n, BT.mono(15 * s, color: BP.paper, weight: 700));
  tp.paint(canvas, Offset(base.dx - tp.width / 2, base.dy - h / 2 - tp.height / 2 - 2));
}

/// Shared: a wobbly angle for idle life.
double idle(double t, int salt, [double amp = 1]) => noise1(t * 0.7, salt) * amp + math.sin(t * 0.9 + salt) * 0.2 * amp;
