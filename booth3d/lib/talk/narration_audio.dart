import 'dart:typed_data';

import 'narration_audio_stub.dart' if (dart.library.io) 'narration_audio_io.dart' if (dart.library.js_interop) 'narration_audio_web.dart';

/// The presentation's voice (presentation.dart): one clip, an mp3, at a
/// time; on the Mac through the app's own player (MainFlutterWindow.swift),
/// on the web through the page's.
abstract class NarrationAudio {
  factory NarrationAudio() => platformNarrationAudio();

  /// Plays [mp3] from its start (the clip before stopped).
  Future<void> play(Uint8List mp3);

  void pause();
  void resume();
  void stop();
}
