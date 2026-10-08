import 'package:flutter/material.dart';

import '../deck/theme.dart';
import 'model.dart';
import 'platform.dart';
import 'scene.dart';
import 'ui/cursor.dart';

/// The booth app: an endless "Name Factory" for the conference stall.
///
/// Opens full screen (`--dart-define=BOOTH_WINDOWED=true` keeps a window),
/// keeps the display awake and hides the mouse pointer when it rests. The
/// history of built names lives with the UI (lib/booth/ui/booth_ui.dart).
class BoothApp extends StatefulWidget {
  const BoothApp({super.key});

  @override
  State<BoothApp> createState() => _BoothAppState();
}

class _BoothAppState extends State<BoothApp> {
  final _model = BoothModel()..mode = initialBuildMode();

  @override
  void initState() {
    super.initState();
    BoothPlatform.keepAwake();
    if (!const bool.fromEnvironment('BOOTH_WINDOWED')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => BoothPlatform.enterFullScreen());
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      boothMaterialApp(CursorHider(child: BoothScene(model: _model)));
}

/// MaterialApp shell shared by the app and capture mode.
Widget boothMaterialApp(Widget home) => MaterialApp(
  title: 'Name Factory',
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: BP.bg,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: BP.amber,
      selectionColor: BP.line.withValues(alpha: 0.35),
    ),
  ),
  home: Material(
    type: MaterialType.transparency,
    child: DefaultTextStyle(
      style: const TextStyle(fontFamily: BP.display, fontSize: 16, color: BP.ink),
      child: home,
    ),
  ),
);

/// `--dart-define=BOOTH_MODE=craft`, `?mode=craft` or a `/workshop/` URL
/// start in the Name Workshop; otherwise the Name Factory.
BuildMode initialBuildMode() {
  const define = String.fromEnvironment('BOOTH_MODE');
  final uri = Uri.base;
  final craft =
      define == 'craft' ||
      uri.queryParameters['mode'] == 'craft' ||
      uri.pathSegments.contains('workshop');
  return craft ? BuildMode.craft : BuildMode.bricks;
}
