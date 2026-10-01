import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../deck/scripts.dart';
import '../../deck/theme.dart';
import '../../worlds/factory/factory_kit.dart';
import '../layout.dart';
import '../model.dart';
import '../raster.dart';
import 'factory_pallet.dart';
import 'factory_plan.dart';
import 'factory_text.dart';

part 'factory_crew.dart';
part 'factory_frame.dart';
part 'factory_screen.dart';
part 'factory_static.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Styles & colours
// ─────────────────────────────────────────────────────────────────────────────

const _hallFill = Color(0xFF0B1E33);
const _glass = Color(0xFF071526);
const _screenFill = Color(0xFF06101C);

abstract final class FS {
  static const ja = Locale('ja');
  static final m16 = BT.mono(16, color: BP.ink, weight: 500);
  static final m16dim = BT.mono(16, color: BP.inkDim, weight: 500);
  static final m16amber = BT.mono(16, color: BP.amber, weight: 600);
  static final plate = BT.mono(16, color: BP.ink, weight: 600);
  static final plateHot = BT.mono(16, color: BP.amber, weight: 700);
  static final sign = BT.sample(18, color: BP.amber, weight: 600).copyWith(locale: ja);
  static final small = BT.sample(12, color: BP.inkDim, weight: 500).copyWith(locale: ja);
  static TextStyle name(double size, Color color) => NameRaster.nameStyle(size, color: color);
}

// ─────────────────────────────────────────────────────────────────────────────
// The scene: caches that live as long as the layer.
// ─────────────────────────────────────────────────────────────────────────────

class FactoryScene {
  FactoryScene(this.sys);

  final FactorySystem sys;
  final texts = FactoryTexts();

  ui.Picture? _back, _front;
  int _gen = -1;

  JobData? _data, _old;

  /// Per-name data for [j]: the current job (pass [current]) or the one just
  /// before it. Anything older gets a throwaway copy.
  JobData? data(Job? j, {bool current = false}) {
    if (j == null) return null;
    if (_data?.job == j) return _data;
    if (_old?.job == j) return _old;
    if (!current) return JobData(j);
    _old = _data;
    return _data = JobData(j);
  }

  void paint(Canvas canvas, BoothModel m) {
    if (_back == null || _gen != texts.generation) {
      _back?.dispose();
      _front?.dispose();
      _back = _record((c) => _Static(c, this).back());
      _front = _record((c) => _Static(c, this).front());
      _gen = texts.generation;
    }
    canvas.save();
    // Never paint outside the factory and its belt.
    canvas.clipRect(const Rect.fromLTRB(FG.left, 380, BL.beltEnd + 2, FG.floor + 0.5));
    _Frame(canvas, m, this).draw();
    canvas.restore();
  }

  ui.Picture _record(void Function(Canvas c) draw) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording();
  }

  void dispose() {
    _back?.dispose();
    _front?.dispose();
    texts.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shapes shared by the static and the live drawing
// ─────────────────────────────────────────────────────────────────────────────

final _funnel = Path()
  ..moveTo(60, FG.funnelTop)
  ..lineTo(144, FG.funnelTop)
  ..lineTo(132, FG.hopperBody.top)
  ..lineTo(72, FG.hopperBody.top)
  ..close();

const _sortScreen = Rect.fromLTRB(154, 541, 210, 565);
const _fontGlass = Rect.fromLTRB(232, 531, 292, 567);
const _fontStrip = Rect.fromLTRB(232, 569, 292, 579);
Rect _fontCellRect(int i) => Rect.fromLTWH(232 + (i % 2) * 30.0, 531 + (i ~/ 2) * 18.0, 30, 18);

/// What the fonts machine's strip calls each font (the screen has the full
/// name).
String _fontShort(String font) => switch (font) {
  'Hiragino · system' => 'Hiragino',
  'Apple SD Gothic · system' => 'SD Gothic',
  'Noto Kufi Arabic' => 'Noto Kufi',
  'system fallback' => 'fallback',
  _ => font,
};
const _fontCellGlyphs = ['Aa', 'あ', '字', '한'];

const _clock = Offset(505, 530);
const _flywheel = Offset(383, 541);
const _pressGauge = Offset(322, 542);
const _kilnGauge = Offset(406, 603);
const _firebox = Rect.fromLTRB(400, 652, 444, 694);

const _bin = [Offset(32, FG.binTop), Offset(142, FG.binTop), Offset(126, 698), Offset(32, 698)];

/// The pneumatic tube that brings each name in: along the roof from the
/// left edge, then down into the hopper.
const _tubeX = 136.0;
final _tube = Path()
  ..moveTo(FG.left, 392)
  ..lineTo(_tubeX - 14, 392)
  ..quadraticBezierTo(_tubeX, 392, _tubeX, 406)
  ..lineTo(_tubeX, 524);
final _tubeMetric = _tube.computeMetrics().first;

/// Soft edges for text scrolling across the screen.
final _screenFades = [
  for (final (x0, x1) in [(FG.screen.left + 6, FG.screen.left + 26), (FG.screen.right - 6, FG.screen.right - 26)])
    (
      Rect.fromLTRB(math.min(x0, x1), FG.screen.top + 6, math.max(x0, x1), FG.screen.bottom - 6),
      Paint()..shader = ui.Gradient.linear(Offset(x0, 0), Offset(x1, 0), [_screenFill, _screenFill.withValues(alpha: 0)]),
    ),
];

/// Machine plate rects (laid out with the plate style).
List<Rect> _plates(FactoryTexts tx) => [
  for (var k = 0; k < 5; k++)
    () {
      final p = tx.get(FG.machineNames[k], FS.plate, key: 'plate');
      return Rect.fromCenter(center: Offset(FG.machineX[k], FG.plateY), width: p.width + 14, height: 22);
    }(),
];

/// Three chasing arrows in a triangle (recycling).
void recycleMark(FactoryInk k, Offset o, double r, Color col) {
  for (var i = 0; i < 3; i++) {
    final a0 = -math.pi / 2 + i * 2 * math.pi / 3 + 0.35;
    final a1 = a0 + 2 * math.pi / 3 - 0.7;
    final p0 = o + Offset(math.cos(a0), math.sin(a0)) * r;
    final p1 = o + Offset(math.cos(a1), math.sin(a1)) * r;
    k.c.drawLine(p0, p1, k.st(col, 1.3));
    final d = (p1 - p0) / (p1 - p0).distance;
    final n = Offset(-d.dy, d.dx);
    k.c.drawLine(p1, p1 - d * 3 + n * 2, k.st(col, 1.3));
    k.c.drawLine(p1, p1 - d * 3 - n * 2, k.st(col, 1.3));
  }
}
