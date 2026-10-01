import 'package:flutter/foundation.dart';

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

  /// Where the names are kept, for the operator (null: memory only).
  String? get location => null;
}

/// The default store; [path] overrides the file (tests).
BoothStore createStore({String? path}) => impl.createStore(path: path);

/// Every name built at this booth, oldest first, persisted in a [BoothStore].
/// "Today" is by the local calendar date, so the count starts again at
/// midnight without a restart.
class BoothHistory extends ChangeNotifier {
  BoothHistory(this.store);

  final BoothStore store;
  final _names = <BuiltName>[];
  Future<List<BuiltName>>? _load;
  Future<void> _chain = Future.value();

  /// Keep the file bounded: a conference never builds this many.
  static const keep = 5000;

  List<BuiltName> get all => List.unmodifiable(_names);

  /// Reads the saved names (once) and puts them before any added since.
  Future<List<BuiltName>> load() => _load ??= store
      .load()
      .catchError((Object _) => <BuiltName>[])
      .then((saved) {
        _names.insertAll(0, saved);
        notifyListeners();
        return saved;
      });

  /// Records a freshly built name and saves.
  void add(String name, {DateTime? at}) {
    _names.add(BuiltName(name, at ?? DateTime.now()));
    notifyListeners();
    _save();
  }

  /// Names built on [day]'s date (default: today), oldest first.
  List<BuiltName> on([DateTime? day]) {
    final d = day ?? DateTime.now();
    return [
      for (final b in _names)
        if (sameDay(b.at, d)) b,
    ];
  }

  /// Forgets the names built on [day]'s date (default: today) and saves.
  /// Returns the names removed, oldest first.
  Future<List<BuiltName>> clearDay([DateTime? day]) async {
    await load();
    final d = day ?? DateTime.now();
    final gone = on(d);
    _names.removeWhere((b) => sameDay(b.at, d));
    notifyListeners();
    _save();
    return gone;
  }

  /// Completes when everything recorded so far is saved.
  Future<void> get saved => _chain;

  void _save() {
    _chain = _chain
        .then((_) async {
          // Never write before the file has been read: that would drop history.
          await load();
          final n = _names.length;
          await store.save(_names.sublist(n > keep ? n - keep : 0));
        })
        .catchError((Object _) {});
  }

  static bool sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }
}
