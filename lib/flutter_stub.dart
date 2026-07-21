// Stub: used when Flutter is NOT available (dart test).
// The real implementation is in package:flutter/services.dart.

class MethodChannel {
  final String name;
  final dynamic binaryMessenger;
  const MethodChannel(this.name, {this.binaryMessenger});

  Future<dynamic> invokeMethod(String method, [dynamic arguments]) async {
    throw UnsupportedError(
        'MethodChannel requires Flutter. Use flutter test.');
  }
}

class MissingPluginException implements Exception {
  final String message;
  MissingPluginException(this.message);
  @override
  String toString() => 'MissingPluginException: $message';
}
