import 'store.dart';

BoothStore createStore({String? path}) => MemoryStore();

/// Keeps the names for this run only (web).
class MemoryStore extends BoothStore {
  var _names = <BuiltName>[];

  @override
  Future<List<BuiltName>> load() async => List.of(_names);

  @override
  Future<void> save(List<BuiltName> names) async => _names = List.of(names);
}
