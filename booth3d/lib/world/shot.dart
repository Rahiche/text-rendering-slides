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
/// director cuts to the most important one (and back after it), holding
/// every shot a moment at least. Someone typing at the booth still wins
/// over all of them.
class Focus {
  Focus(this.id, this.shot, {this.priority = 1});

  /// Who or what is followed ('kern 2', 'break 4', 'delivery'): a new id
  /// is a new shot (a cut, unless it's framed much as the last).
  final String id;
  final Shot shot;

  /// Higher wins: 3 the kerning close-up, 2 a delivery, 1 a break.
  final int priority;
}
