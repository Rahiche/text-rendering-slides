import 'package:vector_math/vector_math.dart' as vm;

/// One framing: where the camera is, what it looks at, its field of view
/// (degrees), how quickly the camera settles into it, and how much it
/// drifts like a hand-held camera.
class Shot {
  Shot(this.eye, this.target, {this.fov = 40, this.settle = 2.2, this.drift = 1});
  final vm.Vector3 eye, target;
  final double fov, settle, drift;
}

/// The world asking the camera to look at something for a while: the
/// kerning close-up, a builder on a coffee break, the delivery driver.
///
/// Requests are made afresh every frame (into [Site3D.focus]); the
/// director frames the most important one over its own rotation of shots.
/// Someone typing at the booth still wins over all of them.
class Focus {
  Focus(this.id, this.shot, {this.priority = 1, this.weight = 1, this.cut = false});

  /// Who or what is followed ('kern 2', 'break 4', 'delivery'): a new id
  /// starts a new request (for [cut]).
  final String id;
  final Shot shot;

  /// Higher wins: 3 the kerning close-up, 2 a delivery, 1 a break.
  final int priority;

  /// 0..1: how much of the frame is this request's (ease it in and out;
  /// ignored when [cut]).
  final double weight;

  /// Cut to it when it starts (and back when it ends) instead of gliding:
  /// for a subject across the city from the wall.
  final bool cut;
}
