import 'dart:convert';
import 'dart:io';

import 'store.dart';

BoothStore createStore({String? path}) => _FileStore(File(path ?? _defaultPath()));

/// Sandboxed on macOS, HOME is the app's container, e.g.
/// ~/Library/Containers/dev.slides.nameFactory/Data/booth_history.json.
String _defaultPath() =>
    '${Platform.environment['HOME'] ?? Directory.systemTemp.path}/booth_history.json';

class _FileStore extends BoothStore {
  _FileStore(this._file);

  final File _file;

  @override
  String get location => _file.path;

  @override
  Future<List<BuiltName>> load() async {
    try {
      if (!await _file.exists()) return [];
      final list = jsonDecode(await _file.readAsString());
      if (list is List) return [for (final j in list) ?BuiltName.fromJson(j)];
    } catch (_) {
      // Unreadable: fall through.
    }
    // Keep a damaged file aside rather than overwrite it on the next save.
    try {
      await _file.rename('${_file.path}.damaged-${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {}
    return [];
  }

  @override
  Future<void> save(List<BuiltName> names) async {
    try {
      await _file.parent.create(recursive: true);
      // Write a sibling and rename it over the file: a crash or power cut at
      // the stall never leaves half a file behind.
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent(' ').convert([for (final n in names) n.toJson()]),
        flush: true,
      );
      await tmp.rename(_file.path);
    } catch (_) {}
  }
}
