import 'dart:math' as math;
import 'dart:ui' show Color;

/// The lower third for the shots without a caption of their own: the bricks
/// arriving, the finish (the plaster as anti-aliasing, then the paint), the
/// new manager's plans, the demolition and the cleanup.
///
/// The site says what's on every frame (a topic and its words, from the
/// shot on screen). The caption comes in half a second after a topic
/// starts and goes after a few seconds, or as soon as the topic's over; a
/// new topic's words wait until the last one's are gone.
class SceneCaption {
  /// 0 hidden … 1 fully in.
  double show = 0;

  /// The kicker ('資材搬入 · DELIVERY'), the line under it and a note; a
  /// colour swatch before the line (the paint going on), if any.
  String kick = '', line = '', note = '';
  Color? swatch;

  String? _topic;
  double _since = 0, _t = 0;
  ({String kick, String line, String note, Color? swatch})? _next;

  /// What's on at [t]: [topic] (null: nothing to say) and its words.
  void update(double t, String? topic, {String kick = '', String line = '', String note = '', Color? swatch}) {
    if (topic != _topic) {
      _topic = topic;
      _since = t;
      _next = topic == null ? null : (kick: kick, line: line, note: note, swatch: swatch);
    }
    final dt = (t - _t).clamp(0.0, 0.5);
    _t = t;
    final on = _next == null && _topic != null && t >= _since + 0.5 && t < _since + 5.6;
    show = on ? math.min(1, show + dt / 0.35) : math.max(0, show - dt / 0.25);
    final next = _next;
    if (next != null && show < 1e-6) {
      show = 0;
      this.kick = next.kick;
      this.line = next.line;
      this.note = next.note;
      this.swatch = next.swatch;
      _next = null;
    }
  }
}
