import 'package:flutter/material.dart';

import '../deck/theme.dart';
import 'model.dart';
import 'platform.dart';
import 'scene.dart';
import 'store.dart';

/// The booth app: an endless "Name Factory" for the conference stall.
class BoothApp extends StatefulWidget {
  const BoothApp({super.key});

  @override
  State<BoothApp> createState() => _BoothAppState();
}

class _BoothAppState extends State<BoothApp> {
  final _model = BoothModel();
  final _store = createStore();
  final _history = <BuiltName>[];

  @override
  void initState() {
    super.initState();
    BoothPlatform.keepAwake();
    _store.load().then((h) {
      _history.addAll(h);
      _model.built.addAll(h.map((b) => b.name));
    });
    _model.onBuilt = (m) {
      _history.add(BuiltName(m.built.last, DateTime.now()));
      _store.save(_history);
    };
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => boothMaterialApp(BoothScene(model: _model));
}

/// MaterialApp shell shared by the app and capture mode.
Widget boothMaterialApp(Widget home) => MaterialApp(
  title: 'Name Factory · 名前工場',
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
