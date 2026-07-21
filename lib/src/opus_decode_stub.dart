// Stub: used when Flutter is NOT available (pure dart test, CLI).
// The real implementation (opus_decode_channel.dart) is used when the
// Flutter SDK is present, selected via conditional import.

import 'dart:typed_data';

class OpusDecodeChannel {
  static Future<List<bool>> decodePackets({
    required List<Uint8List> packets,
    required double sampleRate,
    required int channels,
    required int framesPerPacket,
  }) async {
    throw UnsupportedError(
        'OpusDecodeChannel requires a Flutter plugin context. '
        'Use the FFI test harness for local testing.');
  }
}
