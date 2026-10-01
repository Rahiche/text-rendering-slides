import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_slides/booth/booth_app.dart';
import 'package:text_slides/booth/layout.dart';
import 'package:text_slides/booth/model.dart';
import 'package:text_slides/booth/names.dart';
import 'package:text_slides/booth/scene.dart';
import 'package:text_slides/booth/store_stub.dart';
import 'package:text_slides/booth/ui/booth_ui.dart';
import 'package:text_slides/booth/ui/input.dart';

TextEditingValue _value(String s, {bool composing = false}) => TextEditingValue(
  text: s,
  selection: TextSelection.collapsed(offset: s.length),
  composing: composing ? TextRange(start: 0, end: s.length) : TextRange.empty,
);

Future<BoothModel> _pumpInput(WidgetTester tester) async {
  tester.view.physicalSize = BL.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final m = BoothModel();
  BoothUi.attach(m, MemoryStore());
  await tester.pumpWidget(boothMaterialApp(SizedBox.fromSize(size: BL.size, child: NameInput(model: m))));
  await tester.pump();
  await tester.showKeyboard(find.byType(EditableText));
  return m;
}

String _text(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).controller.text;

void main() {
  testWidgets('Enter while composing confirms (確定); the next Enter submits', (tester) async {
    final m = await _pumpInput(tester);
    tester.testTextInput.updateEditingValue(_value('たなか', composing: true));
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(m.queue, isEmpty, reason: 'the Enter only confirmed the conversion');
    expect(_text(tester), 'たなか');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(m.queue.single.name, 'たなか');
    expect(_text(tester), isEmpty);
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
  });

  testWidgets('a commit and Enter in the same moment is one key press', (tester) async {
    final m = await _pumpInput(tester);
    tester.testTextInput.updateEditingValue(_value('さくら', composing: true));
    await tester.pump();
    // The platform reports the commit and then the Enter, no frame between.
    tester.testTextInput.updateEditingValue(_value('さくら'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(m.queue, isEmpty);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(m.queue.single.name, 'さくら');
  });

  testWidgets('plain typing submits on Enter; rejections keep the text', (tester) async {
    final m = await _pumpInput(tester);
    tester.testTextInput.updateEditingValue(_value('Ana'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(m.queue.single.name, 'Ana');
    final ui = BoothUi.of(m);
    expect(ui.toast?.ok, isTrue);
    expect(ui.flights.single.name, 'Ana');

    // Already in line.
    tester.testTextInput.updateEditingValue(_value('ana'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(m.queue, hasLength(1));
    expect(ui.toast?.ok, isFalse);
    expect(_text(tester), 'ana');

    // Not letters.
    tester.testTextInput.updateEditingValue(_value('😀'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(m.queue, hasLength(1));
    expect(_text(tester), '😀');
  });

  test('the line has a limit and a kind message', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final m = BoothModel();
    final ui = BoothUi.attach(m, MemoryStore());
    for (var i = 0; i < BoothUi.maxQueue; i++) {
      expect(ui.submit('Guest ${String.fromCharCode(65 + i)}'), isA<NameOk>());
    }
    expect(ui.submit('One More'), isA<NameRejected>());
    expect(m.queue, hasLength(BoothUi.maxQueue));
  });

  testWidgets(
    'operator keys take only Ctrl+Shift combinations',
    (tester) async {
      final m = BoothModel();
      final ui = BoothUi.attach(m, MemoryStore());
      await tester.pumpWidget(boothMaterialApp(BoothScene(model: m, live: false)));
      await tester.pump();

      // Plain typing keys are left alone (they go on to the input method).
      for (final k in [LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyR, LogicalKeyboardKey.backspace]) {
        expect(await tester.sendKeyEvent(k), isFalse, reason: '$k');
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyH), isFalse); // Shift+H types "H"
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(ui.help, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH), isTrue);
      expect(ui.help, isTrue);
      // Held down: the repeats are swallowed, without toggling again.
      expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyH), isTrue);
      expect(ui.help, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      // Not one of ours: passes through.
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyJ), isFalse);

      // Reset takes two presses.
      ui.history.add('Ana');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(ui.history.on(), hasLength(1));
      expect(ui.armed, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(ui.history.on(), isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('the invitation types, holds and erases', () {
    expect(typewriter(['Hi!'], 0), ('H', true));
    expect(typewriter(['Hi!'], 1.0), ('Hi!', false)); // held
    expect(typewriter(['Hi!'], 3.06).$1, 'H'); // being erased
    expect(typewriter(['Hi!', '次'], 3.6).$1, '次'); // then the next line
  });
}
