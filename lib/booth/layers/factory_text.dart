import 'package:flutter/painting.dart';

/// Laid-out text for the glyph factory: lay out once, paint every frame.
///
/// Least-recently-used and bounded, because the booth runs for hours and
/// every name brings new strings (its code points, runs, fonts…). Dropped
/// when the platform's fonts change (layouts would be stale).
class FactoryTexts {
  FactoryTexts() {
    PaintingBinding.instance.systemFonts.addListener(clear);
  }

  static const _max = 480;

  final _map = <Object, TextPainter>{};

  /// Bumped whenever cached layouts are dropped, so pictures recorded with
  /// them can be re-recorded.
  int generation = 0;

  /// [text] in [style]. Pass a cheap [key] (e.g. a style id) to avoid hashing
  /// the whole style on every lookup.
  TextPainter get(String text, TextStyle style, {Object? key}) {
    final k = (text, key ?? style);
    final hit = _map.remove(k);
    if (hit != null) return _map[k] = hit;
    return _put(
      k,
      TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  /// An arbitrary [span] (mixed styles), cached under [key].
  TextPainter span(Object key, InlineSpan Function() span) {
    final k = ('span', key);
    final hit = _map.remove(k);
    if (hit != null) return _map[k] = hit;
    return _put(k, TextPainter(text: span(), textDirection: TextDirection.ltr)..layout());
  }

  TextPainter _put(Object k, TextPainter p) {
    _map[k] = p;
    while (_map.length > _max) {
      _map.remove(_map.keys.first)!.dispose();
    }
    return p;
  }

  void clear() {
    for (final p in _map.values) {
      p.dispose();
    }
    _map.clear();
    generation++;
  }

  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(clear);
    clear();
  }
}
