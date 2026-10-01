import 'dart:io';
import 'dart:typed_data';

/// Where capture mode writes its frames (native: the app's temp folder).
class CaptureSink {
  CaptureSink(String tag) : _dir = Directory('${Directory.systemTemp.path}/booth3d_capture/$tag') {
    _dir.createSync(recursive: true);
    for (final f in _dir.listSync()) {
      if (f.path.endsWith('.png')) f.deleteSync();
    }
  }

  final Directory _dir;

  void save(String name, Uint8List png) => File('${_dir.path}/$name').writeAsBytesSync(png);

  void log(String line) => stdout.writeln(line);

  Never finish() {
    stdout.writeln('CAPTURE_DONE ${_dir.path}');
    exit(0);
  }
}
