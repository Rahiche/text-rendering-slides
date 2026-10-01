import 'package:flutter/widgets.dart';

import 'booth/booth_app.dart';

/// The conference-stall loop: attendees type their name, the glyph factory
/// and a construction crew build it, then knock it down for the next one.
///
///     flutter run -d macos -t lib/main_booth.dart
///     tool/build_booth_macos.sh       # → ~/Applications/Name Factory.app
void main() => runApp(const BoothApp());
