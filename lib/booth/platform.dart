import 'package:flutter/services.dart';

/// Native helpers for the booth (macOS Runner, channel "booth"). No-ops
/// where the platform doesn't implement them (web).
abstract final class BoothPlatform {
  static const _ch = MethodChannel('booth');

  /// Keeps the display awake while the booth runs.
  static Future<void> keepAwake() => _call('keepAwake');

  static Future<void> toggleFullScreen() => _call('toggleFullScreen');

  static Future<void> _call(String method) async {
    try {
      await _ch.invokeMethod<void>(method);
    } on MissingPluginException {
      // web / not wired up
    } on PlatformException {
      // ignore
    }
  }
}
