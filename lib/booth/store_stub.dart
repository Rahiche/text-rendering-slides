import 'store.dart';

BoothStore createStore() => _MemoryStore();

class _MemoryStore implements BoothStore {
  @override
  Future<List<BuiltName>> load() async => [];

  @override
  Future<void> save(List<BuiltName> names) async {}
}
