import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// libopus C FFI bindings — used ONLY for local dart/flutter test runs.
// Not shipped with the plugin; the real iOS path uses AVAudioConverter
// via platform channel (see opus_decode_channel.dart).

typedef OpusDecoderCreateNative = Pointer<Void> Function(
  Int32 sampleRate,
  Int32 channels,
  Pointer<Int32> error,
);
typedef OpusDecoderCreateDart = Pointer<Void> Function(
  int sampleRate,
  int channels,
  Pointer<Int32> error,
);

typedef OpusDecodeNative = Int32 Function(
  Pointer<Void> decoder,
  Pointer<Uint8> data,
  Int32 len,
  Pointer<Int16> pcm,
  Int32 frameSize,
  Int32 decodeFec,
);
typedef OpusDecodeDart = int Function(
  Pointer<Void> decoder,
  Pointer<Uint8> data,
  int len,
  Pointer<Int16> pcm,
  int frameSize,
  int decodeFec,
);

typedef OpusDecoderDestroyNative = Void Function(Pointer<Void> decoder);
typedef OpusDecoderDestroyDart = void Function(Pointer<Void> decoder);

/// Opus decoder backed by system-installed libopus via dart:ffi.
///
/// Used for local dev/CI test runs (`dart test` / `flutter test`).
/// Requires `brew install opus` (macOS) or equivalent on Linux.
/// Not used in production — the real iOS plugin uses AVAudioConverter.
class OpusFfiDecoder {
  OpusFfiDecoder({
    required this.sampleRate,
    required this.channels,
    required this.framesPerPacket,
  }) {
    _library = _loadLibOpus();
    _decoder = _createDecoder();
  }

  final double sampleRate;
  final int channels;
  final int framesPerPacket;

  late final DynamicLibrary _library;
  late final Pointer<Void> _decoder;

  /// Decodes a batch of raw Opus packets sequentially.
  /// Returns a list of booleans — `true` for each successfully decoded packet.
  /// Maintains decoder state across the batch.
  List<bool> decodeBatch(List<Uint8List> packets) {
    final results = <bool>[];
    for (final packet in packets) {
      results.add(_decodeOne(packet));
    }
    return results;
  }

  bool _decodeOne(Uint8List packet) {
    final pcm = calloc<Int16>(framesPerPacket * channels);
    try {
      final result = _decode(
        _decoder,
        packet,
        packet.length,
        pcm,
        framesPerPacket,
        0, // decodeFec
      );
      return result >= 0;
    } finally {
      calloc.free(pcm);
    }
  }

  void dispose() {
    _destroy(_decoder);
    // Don't close the DynamicLibrary — it may be shared.
  }

  // --- Private helpers ---

  DynamicLibrary _loadLibOpus() {
    if (Platform.isMacOS) {
      for (final path in [
        '/opt/homebrew/lib/libopus.dylib',
        '/usr/local/lib/libopus.dylib',
        '/usr/lib/libopus.dylib',
      ]) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libopus.so.0');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('opus.dll');
    }
    throw UnsupportedError(
        'OpusFfiDecoder: unsupported platform ${Platform.operatingSystem}. '
        'Install libopus: brew install opus (macOS) or apt install libopus0 (Linux).');
  }

  Pointer<Void> _createDecoder() {
    final create = _library.lookupFunction<OpusDecoderCreateNative,
        OpusDecoderCreateDart>('opus_decoder_create');
    final error = calloc<Int32>();
    final decoder = create(sampleRate.toInt(), channels, error);
    if (error.value != 0) {
      calloc.free(error);
      throw Exception('opus_decoder_create failed: error ${error.value}');
    }
    calloc.free(error);
    return decoder;
  }

  int _decode(
    Pointer<Void> decoder,
    Uint8List data,
    int len,
    Pointer<Int16> pcm,
    int frameSize,
    int decodeFec,
  ) {
    final decode =
        _library.lookupFunction<OpusDecodeNative, OpusDecodeDart>('opus_decode');
    final dataPtr = calloc<Uint8>(len);
    try {
      for (int i = 0; i < len; i++) {
        dataPtr[i] = data[i];
      }
      return decode(decoder, dataPtr, len, pcm, frameSize, decodeFec);
    } finally {
      calloc.free(dataPtr);
    }
  }

  void _destroy(Pointer<Void> decoder) {
    final destroy = _library.lookupFunction<OpusDecoderDestroyNative,
        OpusDecoderDestroyDart>('opus_decoder_destroy');
    destroy(decoder);
  }
}
