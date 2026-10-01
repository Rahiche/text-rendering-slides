import 'dart:convert';
import 'dart:io';

import 'store.dart';

BoothStore createStore() => _FileStore();

class _FileStore implements BoothStore {
  // Sandboxed on macOS: HOME is the app's container.
  File get _file =>
      File('${Platform.environment['HOME'] ?? Directory.systemTemp.path}/booth_history.json');

  @override
  Future<List<BuiltName>> load() async {
    try {
      final list = jsonDecode(await _file.readAsString());
      if (list is! List) return [];
      return [for (final j in list) ?BuiltName.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<BuiltName> names) async {
    try {
      await _file.writeAsString(jsonEncode([for (final n in names) n.toJson()]));
    } catch (_) {}
  }
}
