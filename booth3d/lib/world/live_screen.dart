import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';

/// A screen in the city showing a live Flutter widget: [child] laid out at
/// [width]×[height] (logical px) and captured into a texture
/// (flutter_scene's WidgetTexture) each time [capture] is called, for a
/// material to show. The widgets are hosted, unseen, beside the scene's
/// view ([LiveScreens]).
class LiveScreen {
  LiveScreen(this.width, this.height, this.child, {this.pixelRatio = 1});

  final double width, height, pixelRatio;
  final Widget child;
  final _controller = WidgetTextureController();

  /// The screens hosted now.
  static final hosted = ValueNotifier<List<LiveScreen>>(const []);

  /// Hosts it, and shows each capture on [mat] (as its colour and its glow:
  /// a screen lights itself).
  void show(PhysicallyBasedMaterial mat) {
    _controller.addListener(() {
      final t = _controller.texture;
      if (t == null) return;
      final source = GpuTextureSource(t);
      mat
        ..baseColorTexture = source
        ..emissiveTexture = source;
    });
    hosted.value = [...hosted.value, this];
  }

  /// Takes the widget as it paints this frame (call it only while it's
  /// changing and seen: a capture rasterizes it whole).
  void capture() => _controller.requestCapture();
}

/// Hosts the [LiveScreen]s' widgets for their captures (they take no room
/// and never reach the window).
class LiveScreens extends StatelessWidget {
  const LiveScreens({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<LiveScreen>>(
    valueListenable: LiveScreen.hosted,
    builder: (context, screens, _) => Stack(
      children: [
        for (final s in screens)
          WidgetTexture(
            controller: s._controller,
            width: s.width,
            height: s.height,
            pixelRatio: s.pixelRatio,
            update: WidgetUpdatePolicy.manual,
            child: s.child,
          ),
      ],
    ),
  );
}
