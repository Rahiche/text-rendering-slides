import 'dart:async';

import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../model.dart';
import '../names.dart';

/// "Type your name ↵": always focused, so a keyboard at the stall just works
/// (Japanese via the macOS input method).
class NameInput extends StatefulWidget {
  const NameInput({super.key, required this.model});

  final BoothModel model;

  @override
  State<NameInput> createState() => _NameInputState();
}

class _NameInputState extends State<NameInput> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  String? _msg;
  String? _msgJa;
  bool _ok = false;
  Timer? _clear;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_keepFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _keepFocus() {
    if (!_focus.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _clear?.cancel();
    _focus.removeListener(_keepFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final m = widget.model;
    final r = m.submit(value);
    setState(() {
      switch (r) {
        case NameOk(:final name):
          _ok = true;
          final pos = m.queue.length;
          final mins = (m.estimatedWait / 60).ceil();
          _msg = '“$name” is #$pos in line · ≈ $mins min';
          _msgJa = '$pos番目 · 約$mins分';
          _text.clear();
        case NameRejected(:final en, :final ja):
          _ok = false;
          _msg = en;
          _msgJa = ja;
      }
    });
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 7), () => mounted ? setState(() => _msg = null) : null);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 430,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: BP.panel,
              border: Border.all(color: BP.amber, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _text,
                focusNode: _focus,
                autofocus: true,
                maxLength: maxNameLength + 4,
                onSubmitted: _submit,
                cursorColor: BP.amber,
                style: BT.sample(34, weight: 500).copyWith(locale: const Locale('ja')),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: 'Your name · お名前',
                  hintStyle: BT.sample(30, color: BP.inkFaint),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _msg == null
              ? Text('↵ Enter', style: BT.mono(22, color: BP.inkDim))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_msg!, style: BT.display(22, color: _ok ? BP.green : BP.coral)),
                    Text(_msgJa!, style: BT.sample(20, color: _ok ? BP.green : BP.coral)),
                  ],
                ),
        ),
      ],
    );
  }
}
