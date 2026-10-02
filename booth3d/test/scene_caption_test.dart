import 'package:booth3d/world/scene_caption.dart';
import 'package:flutter_test/flutter_test.dart';

/// Steps [c] at 20 fps from [from] to [to] on [topic].
double run(SceneCaption c, double from, double to, String? topic, String kick) {
  var t = from;
  for (; t < to - 1e-9; t += 0.05) {
    c.update(t, topic, kick: kick);
  }
  return t;
}

void main() {
  test('comes in half a second after its topic starts, and goes after a few seconds', () {
    final c = SceneCaption();
    run(c, 0, 0.5, 'delivery 0', 'DELIVERY');
    expect(c.show, 0);
    run(c, 0.5, 1.5, 'delivery 0', 'DELIVERY');
    expect(c.show, 1);
    expect(c.kick, 'DELIVERY');
    run(c, 1.5, 6.5, 'delivery 0', 'DELIVERY');
    expect(c.show, 0);
  });

  test('goes at once when its topic is over', () {
    final c = SceneCaption();
    final t = run(c, 0, 2, 'cleanup', 'CLEANUP');
    expect(c.show, 1);
    run(c, t, t + 0.3, null, '');
    expect(c.show, 0);
  });

  test("a new topic's words wait until the last one's have gone", () {
    final c = SceneCaption();
    var t = run(c, 0, 2, 'verdict', 'NEXT BUILD');
    c.update(t, 'demolish', kick: 'DEMOLITION');
    expect(c.kick, 'NEXT BUILD');
    expect(c.show, lessThan(1));
    t = run(c, t + 0.05, t + 0.3, 'demolish', 'DEMOLITION');
    expect(c.kick, 'DEMOLITION');
    run(c, t, t + 1.0, 'demolish', 'DEMOLITION');
    expect(c.show, 1);
  });
}
