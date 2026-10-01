import 'package:flutter/widgets.dart';
import 'package:text_slides/booth/ui/ink.dart' show UT;
import 'package:text_slides/deck/theme.dart';

/// The event the booth is at, top right on every frame, opposite the board:
///
///   WELCOME TO · ようこそ
///   FlutterKaigi
///
/// `--dart-define=BOOTH_EVENT=…` names another event; empty hides it.
class EventBadge extends StatelessWidget {
  const EventBadge({super.key});

  static const name = String.fromEnvironment('BOOTH_EVENT', defaultValue: 'FlutterKaigi');

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 30,
      right: 36,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          decoration: BoxDecoration(
            color: BP.panel.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BP.amber, width: 1.6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('WELCOME TO · ようこそ', style: UT.mono(13, color: BP.amber, weight: 600, ls: 1.2)),
              const SizedBox(height: 2),
              Text(name, style: UT.name(34, color: BP.ink, weight: 700, height: 1.05)),
            ],
          ),
        ),
      ),
    );
  }
}
