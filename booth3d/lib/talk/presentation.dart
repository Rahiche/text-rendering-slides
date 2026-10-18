import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart' show PerspectiveCamera;

import 'narration_audio.dart';
import 'talk.dart';

/// Presentation mode: the talk told by itself, in the presenter's own
/// voice. Each beat's narration (assets/narration, a clip a beat, made by
/// tool/narration) plays as the beat comes up; when it's done, after a
/// breath, the next beat comes on: the whole talk, the title to the
/// thanks, in 25 minutes (narration.json gives each beat its time). Then
/// the questions, as in the talk.
///
/// Space pauses it (the voice and its clock) and carries on; → and ← go a
/// beat either way (its narration from the start); Esc stops it.
class Presentation extends ChangeNotifier {
  Presentation(this.talk, {this.silent = false});

  final Talk talk;

  /// No voice (a capture: frames at scene times, the clock all the same).
  final bool silent;

  late final NarrationAudio _audio = NarrationAudio();
  List<_Clip>? _clips;
  final _mp3 = <int, Future<Uint8List>>{};

  bool get on => _on;
  bool _on = false;

  bool get paused => _paused;
  bool _paused = false;

  /// The beat on (counted through the whole talk), how long it's been on
  /// by the presentation's clock (held while paused), whether its voice
  /// has started.
  int _beat = -1;
  double _age = 0;
  bool _spoken = false;

  /// How long the whole presentation takes, and how far through it is.
  double get length => _clips?.fold<double>(0, (a, c) => a + c.dwell) ?? 0;
  double get elapsed {
    final clips = _clips;
    if (!_on || clips == null || _beat < 0) return 0;
    var s = _age;
    for (var i = 0; i < _beat && i < clips.length; i++) {
      s += clips[i].dwell;
    }
    return s;
  }

  /// Starts it from the title (the talk started afresh, the camera flown
  /// there from [from]).
  Future<void> start(PerspectiveCamera from) async {
    if (_on) return;
    final clips = _clips ??= await _load();
    if (clips.isEmpty) return;
    // (The first clip ready before the talk starts; none where the voice
    // isn't, as on the web: it plays silent.)
    await _clip(0).then<void>((_) {}, onError: (Object _) {});
    if (talk.on) talk.end();
    talk.start(from);
    _on = true;
    _paused = false;
    _beat = -1;
    notifyListeners();
  }

  /// Stops it (and the talk).
  void stop() {
    if (!_on) return;
    _on = false;
    _audio.stop();
    if (talk.on) talk.end();
    notifyListeners();
  }

  void togglePause() {
    if (!_on) return;
    _paused = !_paused;
    if (_paused) {
      _audio.pause();
    } else if (_spoken) {
      _audio.resume();
    }
    notifyListeners();
  }

  /// The next beat now, or the one before (its narration from the start).
  void next() {
    if (_on) talk.next();
  }

  void back() {
    if (!_on) return;
    talk.back();
    // (Back on the first beat: it isn't a new beat, so start it over.)
    _beat = -1;
  }

  /// Each frame, before the world's update, by the frame's real [dt].
  void update(double dt) {
    if (!_on) return;
    if (!talk.on) {
      // (The talk ended some other way.)
      _on = false;
      _audio.stop();
      notifyListeners();
      return;
    }
    final clips = _clips!, b = talk.beatNumber;
    if (b != _beat) {
      _beat = b;
      _age = 0;
      _spoken = false;
      _audio.stop();
      if (b + 1 < clips.length) _clip(b + 1).then<void>((_) {}, onError: (Object _) {});
    }
    if (_paused || b >= clips.length) return;
    _age += dt;
    final c = clips[b];
    if (!_spoken && _age >= c.start) {
      _spoken = true;
      _say(b);
    }
    if (_age >= c.dwell && b + 1 < clips.length) talk.next();
  }

  Future<void> _say(int b) async {
    if (silent) return;
    final Uint8List mp3;
    try {
      mp3 = await _clip(b);
    } catch (_) {
      return; // (No voice for it: silent.)
    }
    // (Still on it, not paused meanwhile.)
    if (_on && _beat == b && !_paused) await _audio.play(mp3);
  }

  Future<Uint8List> _clip(int b) => _mp3[b] ??= rootBundle.load('assets/narration/${_clips![b].file}').then((d) => d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));

  static Future<List<_Clip>> _load() async {
    final j = json.decode(await rootBundle.loadString('assets/narration/narration.json')) as Map<String, dynamic>;
    return [
      for (final c in (j['clips'] as List).cast<Map<String, dynamic>>())
        _Clip(c['file'] as String, (c['start'] as num).toDouble(), (c['dwell'] as num).toDouble()),
    ];
  }
}

/// A beat's narration: its file, when in the beat it starts, and how long
/// the beat stays on.
class _Clip {
  const _Clip(this.file, this.start, this.dwell);
  final String file;
  final double start, dwell;
}
