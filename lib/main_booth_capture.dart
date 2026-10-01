import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'booth/booth_app.dart';
import 'booth/model.dart';
import 'booth/scene.dart';

/// Renders booth frames at given scene times without waiting in real time
/// (tool/booth_capture.sh). The model is stepped at 30 Hz up to each time.
///
///   --dart-define=BOOTH_TIMES=5,40,120     scene seconds to capture
///   --dart-define=BOOTH_NAMES=Ana,田中太郎   names typed at t=0 (else samples)
///   --dart-define=BOOTH_TAG=x               output folder name
void main() {
  final model = BoothModel();
  const names = String.fromEnvironment('BOOTH_NAMES');
  final key = GlobalKey();
  runApp(boothMaterialApp(BoothScene(model: model, canvasKey: key, live: false)));
  WidgetsBinding.instance.addPostFrameCallback((_) => _capture(model, key, names));
}

Future<void> _capture(BoothModel m, GlobalKey key, String names) async {
  const times = String.fromEnvironment('BOOTH_TIMES', defaultValue: '5,30,90');
  const tag = String.fromEnvironment('BOOTH_TAG', defaultValue: 'booth');
  final out = Directory('${Directory.systemTemp.path}/booth_capture/$tag')
    ..createSync(recursive: true);
  for (final f in out.listSync()) {
    if (f.path.endsWith('.png')) f.deleteSync();
  }
  await Future<void>.delayed(const Duration(milliseconds: 800)); // fonts
  m.update(1 / 30);
  for (final n in names.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    m.submit(n);
  }
  final targets = times.split(',').map((s) => double.parse(s.trim())).toList()..sort();
  var steps = 0;
  for (final target in targets) {
    while (m.t < target) {
      m.update(math.min(1 / 30, target - m.t + 1e-9));
      if (m.pending case final p?) await p;
      if (++steps % 120 == 0) await Future<void>.delayed(Duration.zero);
    }
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final j = m.job;
    final name = 't${target.toStringAsFixed(0).padLeft(4, '0')}_${j?.phase.name ?? 'none'}.png';
    File('${out.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
    stdout.writeln(
      'captured $name  (${j?.name} · ${j?.phase.name} ${(j?.progress(m.t) ?? 0).toStringAsFixed(2)})',
    );
  }
  stdout.writeln('CAPTURE_DONE ${out.path}');
  exit(0);
}
