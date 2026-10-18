import 'dart:typed_data';

import 'narration_audio.dart';

/// No voice where there's no player.
NarrationAudio platformNarrationAudio() => _Silent();

class _Silent implements NarrationAudio {
  @override
  Future<void> play(Uint8List mp3) async {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void stop() {}
}
