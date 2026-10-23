import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'devices.dart';
import 'engine_pages.dart';
import 'kit.dart';
import 'shot.dart';
import 'vignette.dart';

/// Flutter's trade-off: the web page from Chrome's room in Engine Town
/// (v_town.dart), set by Flutter's Text() this time — the headline not
/// balanced, no hyphens, the Japanese across with its readings in brackets,
/// each a red tag — on a screen hung over the east side street, only while
/// the talk calls on it.
class TalkEngines extends Vignette {
  TalkEngines(super.kit);

  @override
  String get name => 'engines';
  @override
  String get kick => "FLUTTER'S TEXT()";
  @override
  String get line => "Chrome's page, set by Flutter";
  @override
  String get note => "what it doesn't do for you: balance, hyphens, vertical, ruby";

  @override
  bool get talkOnly => true;

  /// A navy wall behind the screen: it reads against it, not against the
  /// street's buildings.
  @override
  ({vm.Vector3 at, double w, double h})? get backdrop => (at: vm.Vector3(0, 6.6, 1.6), w: 8.6, h: 9.2);

  @override
  double get loop => 12;
  @override
  double get visit => 10;

  /// Over the east side street by the avenue, facing the plaza (its −z:
  /// west).
  @override
  final frame = trs(vm.Vector3(21.5, 0, -7.5), rotY: math.pi / 2);

  /// The screen's height, its size (m).
  static const _y = 11.0, _ww = 5.6, _wh = 3.5;

  late final Window3D _flutter;
  bool _ready = false;

  @override
  List<(String, TextStyle)> get fontRuns => EnginePages.fontRuns;

  @override
  Future<void> init() async {
    _flutter = Window3D(detail, w: _ww, h: _wh, page: await EnginePages.flutterText(), name: 'engines flutter');
    _ready = true;
  }

  final _m = vm.Matrix4.identity();

  @override
  void pose(double u, double t, double night) {
    if (!_ready) return;
    if (!visited || u >= visit) {
      _flutter.hide();
      return;
    }
    // In as the camera comes, bobbing a little.
    final s = eio(seg(u, 0.0, 0.9));
    if (s <= 0.001) {
      _flutter.hide();
      return;
    }
    _m.setFromTranslationRotationScale(vm.Vector3(0, _y + 0.05 * math.sin(t * 1.2), 0), vm.Quaternion.identity(), vm.Vector3.all(s));
    _flutter.place(frame * _m);
  }

  /// Head on, close enough to read.
  @override
  Shot shot(double u) => Shot(vm.Vector3(-0.3, _y + 0.15, -7.8), vm.Vector3(0, _y, 0), fov: 40, settle: 1.0, drift: 0.3);
}
