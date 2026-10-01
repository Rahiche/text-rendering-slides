import 'dart:typed_data';

/// Capture mode is native-only; on the web this does nothing.
class CaptureSink {
  CaptureSink(String tag);

  void save(String name, Uint8List png) {}

  void log(String line) {}

  void finish() {}
}
