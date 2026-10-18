import 'package:flutter/services.dart';

import 'narration_audio.dart';

/// The Mac app's player (MainFlutterWindow.swift: AVAudioPlayer).
NarrationAudio platformNarrationAudio() => _Native();

class _Native implements NarrationAudio {
  static const _channel = MethodChannel('narration');

  Future<void> _call(String method, [Object? arg]) async {
    try {
      await _channel.invokeMethod<void>(method, arg);
    } on MissingPluginException {
      // (Not on the Mac: silent.)
    } on PlatformException {
      // (A clip it couldn't play: the talk carries on without it.)
    }
  }

  @override
  Future<void> play(Uint8List mp3) => _call('play', mp3);
  @override
  void pause() => _call('pause');
  @override
  void resume() => _call('resume');
  @override
  void stop() => _call('stop');
}
