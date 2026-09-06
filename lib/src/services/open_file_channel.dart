import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Receives files opened from Finder (double click, "Abrir com", drop on the
/// Dock icon) through the native side.
class OpenFileChannel {
  static const MethodChannel _channel = MethodChannel('csviewer/open_file');

  static void listen(void Function(String path) onOpen) {
    if (!Platform.isMacOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile' && call.arguments is String) {
        onOpen(call.arguments as String);
      }
      return null;
    });
  }

  /// Files that arrived before the Flutter engine was listening.
  static Future<List<String>> consumePending() async {
    if (!Platform.isMacOS) return const <String>[];
    try {
      final result = await _channel.invokeMethod<List<Object?>>('consumePending');
      return result?.whereType<String>().toList() ?? const <String>[];
    } on PlatformException {
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }
}
