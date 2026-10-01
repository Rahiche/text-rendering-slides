import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../deck/theme.dart';
import '../model.dart';
import '../names.dart';
import 'booth_ui.dart';
import 'ink.dart';

/// "Type your name · お名前を入力 ↵": a big input that always has the
/// keyboard, so typing at the stall just works, Japanese included.
///
/// With the macOS input method, Enter while converting confirms the
/// conversion (確定) and never submits; the next Enter submits. The platform
/// usually keeps that Enter to itself, but when it reports it anyway (with
/// the conversion still marked, or in the same moment it ends) it's treated
/// as the confirmation.
class NameInput extends StatefulWidget {
  const NameInput({super.key, required this.model});

  final BoothModel model;

  @override
  State<NameInput> createState() => _NameInputState();
}

class _NameInputState extends State<NameInput> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'booth name');
  late final BoothUi _ui = BoothUi.of(widget.model);
  var _last = TextEditingValue.empty;
  var _justCommitted = false;
  var _quiet = false;
  var _inviting = false;
  var _focusCheck = 0.0;

  static final _style = UT.name(40, color: BP.ink, weight: 500, height: 1.2);
  static const _strut = StrutStyle(fontFamily: BP.display, fontSize: 40, height: 1.2, forceStrutHeight: true);
  static const _empty = TextEditingValue(selection: TextSelection.collapsed(offset: 0));

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _focus.addListener(_keepFocus);
    widget.model.addListener(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.model.removeListener(_tick);
    _focus.removeListener(_keepFocus);
    _text.removeListener(_changed);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  static bool _composing(TextEditingValue v) => v.composing.isValid && !v.composing.isCollapsed;

  void _changed() {
    final v = _text.value;
    if (_composing(_last) && !_composing(v)) {
      // A conversion was just confirmed (確定). If Enter did that, the same
      // key press must not also submit (see [_submitted]); a later one may.
      _justCommitted = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _justCommitted = false);
      SchedulerBinding.instance.ensureVisualUpdate();
    }
    if (!_quiet && (v.text != _last.text || v.composing != _last.composing)) _ui.typed();
    _last = v;
  }

  /// Enter ([TextInputAction.done]).
  void _submitted(String _) {
    final v = _text.value;
    if (_composing(v)) {
      // Enter confirmed the input method's conversion, which the platform
      // has committed: keep the (now plain) text, the next Enter submits.
      _text.value = v.copyWith(composing: TextRange.empty);
      return;
    }
    if (_justCommitted) return;
    if (_ui.submit(v.text) is NameOk) _set(_empty);
    _focus.requestFocus();
  }

  /// Changes the text without counting it as typing.
  void _set(TextEditingValue v) {
    _quiet = true;
    _text.value = v;
    _quiet = false;
  }

  void _keepFocus() {
    if (_focus.hasFocus) return;
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  void _tick() {
    final t = widget.model.t;
    // The scene moved on: any later Enter is a new key press.
    _justCommitted = false;
    final inviting = _text.text.isEmpty && _ui.idleFor(t) >= BoothUi.idleAfter;
    if (inviting != _inviting) setState(() => _inviting = inviting);
    // Typed and walked away: tidy up for the next visitor.
    if (_text.text.isNotEmpty && _ui.idleFor(t) >= BoothUi.clearAfter) _set(_empty);
    // Belt and braces: a click or a window change may have taken the focus.
    if (!_focus.hasFocus && t - _focusCheck > 1) {
      _focusCheck = t;
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final field = TextField(
      controller: _text,
      focusNode: _focus,
      autofocus: true,
      decoration: null,
      style: _style,
      strutStyle: _strut,
      cursorColor: BP.amber,
      cursorWidth: 3,
      cursorHeight: 40,
      cursorRadius: const Radius.circular(1.5),
      showCursor: !_inviting,
      maxLength: maxNameLength + 8,
      maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onSubmitted: _submitted,
      // Keeps the focus and the composition: [_submitted] decides.
      onEditingComplete: () {},
      // A stray click must not take the keyboard away.
      onTapOutside: (_) {},
      contextMenuBuilder: null,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: CustomPaint(painter: _InputPainter(m, _ui, _text))),
        Positioned.fromRect(
          rect: UG.field,
          child: ListenableBuilder(
            listenable: m,
            builder: (context, child) => Transform.translate(offset: Offset(_ui.shakeDx(m.t), 0), child: child),
            child: field,
          ),
        ),
      ],
    );
  }
}

const _invitation = ['Your name could be next!', '次はあなたの名前！'];

/// The invitation typed out, held, and erased, line after line: what shows
/// [s] seconds in, and whether the caret is moving.
(String, bool) typewriter(List<String> lines, double s) {
  final spans = [for (final l in lines) _Typed(l)];
  final cycle = spans.fold<double>(0, (a, b) => a + b.total);
  var x = s % cycle;
  for (final sp in spans) {
    if (x < sp.total) return sp.at(x);
    x -= sp.total;
  }
  return ('', false);
}

class _Typed {
  _Typed(this.line) : g = line.characters.toList() {
    // Japanese is typed slower (it reads in fewer, denser characters).
    final wide = RegExp(r'[　-鿿]').hasMatch(line);
    type = g.length / (wide ? 6.5 : 15);
  }

  final String line;
  final List<String> g;
  late final double type;
  static const hold = 2.8;
  static const gap = 0.45;
  double get erase => g.length / 40;
  double get total => type + hold + erase + gap;

  (String, bool) at(double x) {
    if (x < type) return (g.take((x / type * g.length).floor() + 1).join(), true);
    x -= type;
    if (x < hold) return (line, false);
    x -= hold;
    if (x < erase) return (g.take(((1 - x / erase) * g.length).ceil()).join(), true);
    return ('', false);
  }
}

class _InputPainter extends CustomPainter {
  _InputPainter(this.m, this.ui, this.text) : super(repaint: Listenable.merge([m, ui, text]));

  final BoothModel m;
  final BoothUi ui;
  final TextEditingController text;

  @override
  void paint(Canvas canvas, Size size) {
    final t = m.t;
    ui.text.frame(t);
    final k = UiInk(canvas, ui.text);
    final v = text.value;
    final empty = v.text.isEmpty;
    final composing = v.composing.isValid && !v.composing.isCollapsed;
    final idle = ui.idleFor(t);
    final inviting = empty && idle >= BoothUi.idleAfter;
    final s = idle - BoothUi.idleAfter;
    final pulse = inviting ? 0.5 + 0.5 * math.sin(s * 3.4) : 0.0;

    canvas.save();
    canvas.translate(ui.shakeDx(t), 0);
    const r = UG.input;
    if (inviting) {
      canvas.drawRect(r.inflate(4 + 4 * pulse), k.st(BP.amber.withValues(alpha: 0.10 + 0.30 * pulse), 4));
    }
    canvas.drawRect(r, k.fl(BP.panel));
    canvas.drawRect(r, k.st(BP.amber, 2.2));
    if (empty) {
      if (inviting) {
        _invite(k, s);
      } else {
        _hint(k);
      }
    } else {
      _meter(k, v.text);
    }

    // The ↵ key: lit while there is something to send, pressed on Enter.
    final since = t - ui.pressedAt;
    final down = since >= 0 && since < 0.28 ? 1 - since / 0.28 : 0.0;
    k.keyCap(
      UG.key,
      lit: !empty || inviting,
      glow: empty ? pulse : 0.55 + 0.45 * math.sin(t * 4.4),
      down: down,
      icon: (f, col) {
        k.returnArrow(Rect.fromCenter(center: f.center.translate(0, -6), width: 26, height: 16), col, 2.6);
        final p = k.tp(composing ? '確定' : 'Enter', UT.mono(12, color: col, weight: 600));
        p.paint(canvas, Offset(f.center.dx - p.width / 2, f.bottom - p.height - 2));
      },
    );
    canvas.restore();
  }

  /// The resting hint.
  void _hint(UiInk k) {
    final ps = [
      k.tp('Type your name', UT.label(34, color: BP.inkDim, weight: 500)),
      k.tp('·', UT.label(34, color: BP.inkFaint)),
      k.tp('お名前を入力', UT.label(30, color: BP.inkDim, weight: 500)),
    ];
    var x = UG.field.left + 10; // clear of the caret
    for (final p in ps) {
      p.paint(k.c, Offset(x, UG.field.center.dy - p.height / 2));
      x += p.width + 12;
    }
  }

  /// Nobody has typed for a while: the invitation types itself.
  void _invite(UiInk k, double s) {
    final (line, moving) = typewriter(_invitation, s);
    final p = k.tp(line, UT.label(36, color: BP.amber, weight: 600));
    final x = UG.field.left + 4;
    final cy = UG.field.center.dy;
    if (line.isNotEmpty) p.paint(k.c, Offset(x, cy - p.height / 2));
    if (moving || (s * 2.2) % 1 < 0.6) {
      k.c.drawRect(Rect.fromLTWH(x + (line.isEmpty ? 0 : p.width + 5), cy - 19, 16, 38), k.fl(BP.amber));
    }
  }

  /// Letters used, once it gets close to the limit.
  void _meter(UiInk k, String s) {
    final n = s.characters.length;
    if (n < 12) return;
    final p = k.tp('$n/$maxNameLength', UT.mono(14, color: n > maxNameLength ? BP.coral : BP.inkFaint, weight: 600));
    p.paint(k.c, Offset(UG.key.left - 10 - p.width, UG.input.center.dy - p.height / 2));
  }

  @override
  bool shouldRepaint(_InputPainter old) => old.m != m || old.ui != ui || old.text != text;
}
