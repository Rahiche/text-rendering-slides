import 'dart:js_interop';
import 'dart:typed_data';

import 'narration_audio.dart';

/// The page's player: an Audio element on a blob of the clip. (A browser
/// plays sound only once the page has had a click or a key.)
NarrationAudio platformNarrationAudio() => _Page();

@JS('Audio')
extension type _Audio._(JSObject _) implements JSObject {
  external factory _Audio(String src);
  external JSPromise<JSAny?> play();
  external void pause();
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobType type);
}

extension type _BlobType._(JSObject _) implements JSObject {
  external factory _BlobType({String type});
}

@JS('URL.createObjectURL')
external String _urlOf(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revoke(String url);

class _Page implements NarrationAudio {
  _Audio? _audio;
  String? _url;

  @override
  Future<void> play(Uint8List mp3) async {
    stop();
    final url = _url = _urlOf(_Blob(<JSAny>[mp3.toJS].toJS, _BlobType(type: 'audio/mpeg')));
    final audio = _audio = _Audio(url);
    try {
      await audio.play().toDart;
    } catch (_) {
      // (Not allowed yet: the talk carries on without it.)
    }
  }

  @override
  void pause() => _audio?.pause();

  @override
  void resume() {
    final audio = _audio;
    if (audio != null) audio.play().toDart.catchError((_) => null);
  }

  @override
  void stop() {
    _audio?.pause();
    _audio = null;
    if (_url case final url?) _revoke(url);
    _url = null;
  }
}
