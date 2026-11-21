import 'dart:io';

import 'package:flutter/services.dart';

class NativeService {
  static const _channel = MethodChannel('dev.hilva/native');
  static void Function(String)? _capture;
  static void Function(List<String>)? _images;
  static void _listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'capture') _capture?.call(call.arguments as String);
      if (call.method == 'images') {
        _images?.call(List<String>.from(call.arguments as List));
      }
    });
  }

  static void onCapture(void Function(String) callback) {
    _capture = callback;
    _listen();
  }

  static void onImages(void Function(List<String>) callback) {
    _images = callback;
    _listen();
  }

  static Future<String?> initialText() async {
    if (!Platform.isAndroid && !Platform.isWindows) return null;
    return _channel.invokeMethod<String>('initialText');
  }

  static Future<List<String>> initialImages() async {
    if (!Platform.isAndroid) return [];
    return await _channel.invokeListMethod<String>('initialImages') ?? [];
  }

  static Future<void> installApk(String path) =>
      _channel.invokeMethod('installApk', path);
  static Future<void> setAutoStart(bool enabled) =>
      _channel.invokeMethod('setAutoStart', enabled);
}
