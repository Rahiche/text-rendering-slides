import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/names.dart';

/// Knocks the name being built down at once and starts the next.
void _next(BoothModel m) {
  m.skip();
  m.update(0.01); // (cut short with nothing laid: no demolition)
  m.update(0.01); // (nor cleanup)
}

void main() {
  test('a showcase takes over from the samples, at once when asked, and is built over and over', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final m = BoothModel()..update(0.1);
    expect(m.job!.sample, isTrue);
    expect(sampleNames, contains(m.job!.name));

    m.setShowcase('ありがとう', now: true);
    final first = m.job!;
    expect(first.name, 'ありがとう');
    expect(first.sample, isTrue);
    expect(first.phase, Phase.intake);
    expect(m.upcoming, 'ありがとう');

    // Set again: it carries on.
    m.setShowcase('ありがとう', now: true);
    expect(m.job, same(first));

    _next(m);
    expect(m.job!.name, 'ありがとう');
    expect(m.job, isNot(same(first)));
    expect(m.built, isEmpty);

    // Off again: the samples carry on after it.
    m.setShowcase(null);
    expect(m.job!.name, 'ありがとう');
    _next(m);
    expect(sampleNames, contains(m.job!.name));
  });

  test("a visitor's name goes before the showcase", () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final m = BoothModel()..update(0.1);
    m.setShowcase('ありがとう', now: true);
    expect(m.submit('Ana'), isA<NameOk>());
    // (The showcase, a sample, makes way.)
    expect(m.job!.phase, Phase.demolish);
    m
      ..update(0.01)
      ..update(0.01);
    expect(m.job!.name, 'Ana');
    expect(m.job!.sample, isFalse);
    expect(m.upcoming, 'ありがとう');
  });
}
