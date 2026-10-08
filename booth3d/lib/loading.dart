import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/ui/ink.dart' show UT;
import 'package:text_slides/deck/theme.dart';

import 'loading_stub.dart' if (dart.library.js_interop) 'loading_web.dart';

/// The loading screen, over the canvas until the city is ready, then fading
/// away:
///
///   名前の街 · Name City
///   ■ ■ ■ ■ □ □ □ …   (bricks being laid, over and over)
///   Building the city · 街を建設中
///
/// On the web the page shows the same screen itself (web/index.html) from
/// the first moment, in the browser's fonts (the app's Japanese fallback font
/// is one of the things still downloading); this keeps its line up to date
/// and lifts it when the city is ready.
class LoadingCurtain extends StatefulWidget {
  const LoadingCurtain({super.key, required this.stage, required this.ready});

  /// What's being got ready ('fonts', 'city', 'people').
  final ValueListenable<String> stage;
  final bool ready;

  static String label(String stage) => switch (stage) {
    'fonts' => 'Fetching fonts',
    'city' => 'Building the city',
    'people' => 'Calling the crew',
    _ => 'Loading',
  };

  @override
  State<LoadingCurtain> createState() => _LoadingCurtainState();
}

class _LoadingCurtainState extends State<LoadingCurtain> with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    widget.stage.addListener(_stage);
    _stage();
  }

  void _stage() => pageLoadingStage(LoadingCurtain.label(widget.stage.value));

  @override
  void didUpdateWidget(LoadingCurtain old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) pageLoadingDone();
  }

  @override
  void dispose() {
    widget.stage.removeListener(_stage);
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.ready ? 0 : 1,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        onEnd: () {
          if (!widget.ready) return;
          _wave.stop();
          setState(() => _gone = true);
        },
        child: ColoredBox(
          color: BP.bg,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Name City', style: UT.name(48, color: BP.ink, weight: 700)),
                const SizedBox(height: 28),
                CustomPaint(size: const Size(_Bricks.width, _Bricks.side), painter: _Bricks(_wave)),
                const SizedBox(height: 24),
                ValueListenableBuilder<String>(
                  valueListenable: widget.stage,
                  builder: (context, stage, _) => Text(LoadingCurtain.label(stage), style: UT.mono(16, color: BP.inkDim, ls: 0.6)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of bricks laid one after another, then lifted, as in index.html.
class _Bricks extends CustomPainter {
  _Bricks(this.wave) : super(repaint: wave);

  final Animation<double> wave;
  static const n = 12, side = 14.0, gap = 8.0, width = n * (side + gap) - gap;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < n; i++) {
      // Each brick 0.1 s after the last; laid from 10% to 70% of its cycle.
      final p = (wave.value - i * 0.0625) % 1;
      final on = (p < 0.1 ? p / 0.1 : (p < 0.7 ? 1.0 : (p < 0.8 ? (0.8 - p) / 0.1 : 0.0))).clamp(0.0, 1.0);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(i * (side + gap), 0, side, side), const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = Color.lerp(BP.lineFaint, BP.amber, on)!);
    }
  }

  @override
  bool shouldRepaint(_Bricks old) => old.wave != wave;
}
