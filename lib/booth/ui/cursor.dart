import 'dart:async';

import 'package:flutter/widgets.dart';

/// Hides the mouse pointer after [after] without movement (nobody at the
/// stall needs it on the TV) and shows it again as soon as the mouse moves.
class CursorHider extends StatefulWidget {
  const CursorHider({super.key, required this.child, this.after = const Duration(seconds: 3)});

  final Widget child;
  final Duration after;

  @override
  State<CursorHider> createState() => _CursorHiderState();
}

class _CursorHiderState extends State<CursorHider> {
  var _hidden = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _wake() {
    _timer?.cancel();
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _hidden = true);
    });
    if (_hidden) setState(() => _hidden = false);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _hidden ? SystemMouseCursors.none : MouseCursor.defer,
    onHover: (_) => _wake(),
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      onPointerMove: (_) => _wake(),
      onPointerSignal: (_) => _wake(),
      // While hidden, nothing underneath may show its own pointer (the text
      // field's I-beam would win over "none").
      child: IgnorePointer(ignoring: _hidden, child: widget.child),
    ),
  );
}
