import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/booth/store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('booth_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('saves to the file and reads it back after a restart', () async {
    final path = '${dir.path}/booth_history.json';
    final h = BoothHistory(createStore(path: path));
    await h.load();
    h.add('田中太郎');
    h.add('Ana');
    await h.saved;
    expect(File(path).existsSync(), isTrue);
    expect(File('$path.tmp').existsSync(), isFalse); // written atomically

    final again = BoothHistory(createStore(path: path));
    final names = await again.load();
    expect(names.map((b) => b.name), ['田中太郎', 'Ana']);
    expect(again.on().length, 2);
  });

  test('never overwrites the file before reading it', () async {
    final path = '${dir.path}/booth_history.json';
    final first = BoothHistory(createStore(path: path));
    first.add('Old');
    await first.saved;

    // Built before the history finished loading: kept after the old names.
    final h = BoothHistory(createStore(path: path));
    h.add('New');
    await h.saved;
    final names = await BoothHistory(createStore(path: path)).load();
    expect(names.map((b) => b.name), ['Old', 'New']);
  });

  test('a damaged file is kept aside, not lost', () async {
    final path = '${dir.path}/booth_history.json';
    File(path).writeAsStringSync('{not json');
    final h = BoothHistory(createStore(path: path));
    expect(await h.load(), isEmpty);
    expect(dir.listSync().any((f) => f.path.contains('.damaged-')), isTrue);
  });

  test('today is by calendar date; reset forgets only today', () async {
    final path = '${dir.path}/booth_history.json';
    final h = BoothHistory(createStore(path: path));
    await h.load();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    h.add('Before', at: yesterday);
    h.add('Ana', at: now);
    h.add('Bob', at: now);
    expect(h.on().map((b) => b.name), ['Ana', 'Bob']);
    expect(h.on(yesterday).map((b) => b.name), ['Before']);

    final gone = await h.clearDay();
    expect(gone.map((b) => b.name), ['Ana', 'Bob']);
    expect(h.on(), isEmpty);
    await h.saved;
    final names = await BoothHistory(createStore(path: path)).load();
    expect(names.map((b) => b.name), ['Before']);
  });
}
