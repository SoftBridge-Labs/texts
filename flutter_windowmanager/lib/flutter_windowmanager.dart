import 'dart:async';

import 'package:flutter/services.dart';

class FlutterWindowManager {
  static const MethodChannel _channel = MethodChannel('flutter_windowmanager');

  static const int FLAG_SECURE = 0x00002000;

  static Future<bool?> addFlags(int flags) {
    return _channel.invokeMethod<bool>('addFlags', {'flags': flags});
  }

  static Future<bool?> clearFlags(int flags) {
    return _channel.invokeMethod<bool>('clearFlags', {'flags': flags});
  }
}
