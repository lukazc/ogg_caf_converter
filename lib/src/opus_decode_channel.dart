import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Platform channel interface for iOS Opus decode verification.
///
/// Sends raw Opus packets to AVAudioConverter via the
/// `ogg_caf_converter/opus_decode` method channel and returns
/// per-packet decode success/failure.
class OpusDecodeChannel {
  static const _channel = MethodChannel('ogg_caf_converter/opus_decode');

  /// Attempts to decode a batch of raw Opus packets sequentially.
  ///
  /// [packets] is a list of raw elementary-stream Opus packets (no CAF/OGG
  /// container). [sampleRate], [channels], and [framesPerPacket] must
  /// match the encoder configuration (available from the intact CAF
  /// `desc` chunk).
  ///
  /// Returns a list of booleans, one per packet — `true` if the packet
  /// decoded successfully, `false` if the decoder reported an error.
  /// Decoder state is maintained across packets in the batch, so
  /// a failure at position N means subsequent packets may also fail.
  static Future<List<bool>> decodePackets({
    required List<Uint8List> packets,
    required double sampleRate,
    required int channels,
    required int framesPerPacket,
  }) async {
    final result = await _channel.invokeMethod('decodePackets', {
      'packets': packets,
      'sampleRate': sampleRate,
      'channels': channels,
      'framesPerPacket': framesPerPacket,
    });
    return (result as List<dynamic>).cast<bool>();
  }
}
