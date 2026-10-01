import 'package:flutter/widgets.dart';

import 'booth/booth_app.dart';

/// The conference-stall loop: attendees type their name, the glyph factory
/// and a construction crew build it, then knock it down for the next one.
///
///     flutter run -d macos -t lib/main_booth.dart [--dart-define=BOOTH_WINDOWED=true]
///     tool/build_booth_macos.sh       # → ~/Applications/Name Factory.app
///
/// Operator keys: Ctrl+Shift+H shows them all (skip, drop the last queued
/// name, full screen, fast-forward, reset today's count).
void main() => runApp(const BoothApp());
