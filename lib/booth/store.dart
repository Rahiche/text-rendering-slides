import 'store_stub.dart' if (dart.library.io) 'store_io.dart' as impl;

/// One name the factory built.
class BuiltName {
  const BuiltName(this.name, this.at);
  final String name;
  final DateTime at;

  Map<String, Object> toJson() => {'name': name, 'at': at.toIso8601String()};

  static BuiltName? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final at = DateTime.tryParse('${j['at']}');
    return name is String && at != null ? BuiltName(name, at) : null;
  }
}

/// Keeps the list of built names across restarts (a file in the app's
/// container on macOS; nothing on the web).
abstract class BoothStore {
  Future<List<BuiltName>> load();
  Future<void> save(List<BuiltName> names);
}

BoothStore createStore() => impl.createStore();
