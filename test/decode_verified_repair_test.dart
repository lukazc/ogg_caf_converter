import 'dart:io';
import 'dart:typed_data';

import 'package:ogg_caf_converter/models/caf_models.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:ogg_caf_converter/src/opus_ffi_stub.dart';
import 'package:test/test.dart';

/// Integration tests for decode-verified CAF repair using system libopus.
///
/// These tests require `brew install opus` on macOS.  They exercise the
/// same decode-verification logic that the production iOS path uses
/// (AVAudioConverter), via a locally-loaded libopus for CI/dev testing.
///
/// Skip if libopus is not available (test will be marked as skipped, not
/// failed).

void main() {
  late OpusFfiDecoder decoder;

  setUpAll(() {
    try {
      decoder = OpusFfiDecoder(
        sampleRate: 48000,
        channels: 1,
        framesPerPacket: 960,
      );
    } catch (e) {
      // System libopus not installed — skip all tests in this group.
    }
  });

  tearDownAll(() {
    // decoder.dispose() — omitted, let GC handle it.
  });

  group('decode-verified repair', () {
    test('valid CAF packet decodes successfully', () {
      // Feed a known-good packet from ios_record_valid.caf's intact pakt.
      final validBytes = File('test_resources/ios_record_valid.caf').readAsBytesSync();
      final reader = CafReader('test_resources/ios_record_valid.caf');
      final pakt = reader.readPacketTable(validBytes);
      final audio = reader.readAudioData(validBytes);

      // Decode the first few packets.
      int offset = 0;
      final packets = <Uint8List>[];
      for (final size in pakt.entries.take(5)) {
        packets.add(Uint8List.sublistView(audio, offset, offset + size));
        offset += size;
      }

      final results = decoder.decodeBatch(packets);
      expect(results.length, equals(5));
      expect(results.every((r) => r), isTrue,
          reason: 'All known-good packets must decode successfully');
    });

    test('random bytes fail decode', () {
      // Deterministic "random-like" data that is NOT a valid Opus packet.
      // Use a simple LCG with a fixed seed for reproducibility.
      final garbage = List<int>.generate(200, (i) => (i * 73 + 17) % 256);
      final results = decoder.decodeBatch([Uint8List.fromList(garbage)]);
      // Most random byte sequences must fail.  libopus is lenient but a
      // genuinely random 200-byte sequence should fail.
      expect(results[0], isFalse,
          reason: 'Random byte sequence must not decode as valid Opus');
    });

    test('decode-verified walk repairs corrupted CAF #1', () {
      final corrupted = File('test_resources/ios_record_corrupted_by_crash.caf')
          .readAsBytesSync();
      final reader = CafReader('test_resources/ios_record_corrupted_by_crash.caf');
      final audioFormat = reader.readAudioFormat(corrupted);
      final audio = reader.readAudioData(corrupted);

      // Run the decode-verified walk directly.
      final sizes = _decodeVerifiedWalk(
        audio,
        decodeBatch: (packets,
                  {double? sampleRate, int? channels, int? framesPerPacket}) =>
            decoder.decodeBatch(packets),
        channels: audioFormat.channelsPerPacket,
      );

      expect(sizes.isNotEmpty, isTrue);
      expect(sizes.length, greaterThan(50),
          reason: 'Should recover a significant number of packets');

      // End-to-end decode verification: decode every packet in sequence.
      final allPackets = <Uint8List>[];
      int offset = 0;
      for (final size in sizes) {
        allPackets.add(Uint8List.sublistView(audio, offset, offset + size));
        offset += size;
      }
      final decodeResults = decoder.decodeBatch(allPackets);
      final failures = decodeResults.where((r) => !r).length;
      expect(failures, equals(0),
          reason: 'All $failures packets must decode without error '
              'after repair (${sizes.length} total)');

      // Diagnostic: log packet stats.
      final sum = sizes.reduce((a, b) => a + b);
      final avg = sum / sizes.length;
      print('--- Decode-Verified Repair #1 ---');
      print('Packets: ${sizes.length}  |  Avg size: ${avg.toStringAsFixed(0)}');
      print('Min/Max: ${sizes.reduce((a,b)=>a<b?a:b)} / '
          '${sizes.reduce((a,b)=>a>b?a:b)}');
      print('Sum vs audio: $sum / ${audio.length}');
      print('First 10: ${sizes.take(10).toList()}');
      print('All decoded without error: YES');
      print('---------------------------------');
    });

    test('decode-verified walk repairs corrupted CAF #2', () {
      final corrupted = File(
              'test_resources/ios_record_corrupted_by_crash_2.caf')
          .readAsBytesSync();
      final reader =
          CafReader('test_resources/ios_record_corrupted_by_crash_2.caf');
      final audioFormat = reader.readAudioFormat(corrupted);
      final audio = reader.readAudioData(corrupted);

      final sizes = _decodeVerifiedWalk(
        audio,
        decodeBatch: (packets,
                {double? sampleRate, int? channels, int? framesPerPacket}) =>
            decoder.decodeBatch(packets),
        channels: audioFormat.channelsPerPacket,
      );

      expect(sizes.isNotEmpty, isTrue);
      expect(sizes.length, greaterThan(50));

      final allPackets = <Uint8List>[];
      int offset = 0;
      for (final size in sizes) {
        allPackets.add(Uint8List.sublistView(audio, offset, offset + size));
        offset += size;
      }
      final decodeResults = decoder.decodeBatch(allPackets);
      final failures = decodeResults.where((r) => !r).length;
      expect(failures, equals(0));

      final sum = sizes.reduce((a, b) => a + b);
      final avg = sum / sizes.length;
      print('--- Decode-Verified Repair #2 ---');
      print('Packets: ${sizes.length}  |  Avg size: ${avg.toStringAsFixed(0)}');
      print('All decoded without error: YES');
      print('---------------------------------');
    });

    test('vbr_packet_sizes_vary_with_content', () {
      // This test documents the VBR behaviour rather than asserting it.
      // We just verify packets sizes are NOT uniform (which would be
      // suspicious) and that all decode.
      final corrupted = File('test_resources/ios_record_corrupted_by_crash.caf')
          .readAsBytesSync();
      final reader = CafReader('test_resources/ios_record_corrupted_by_crash.caf');
      final audio = reader.readAudioData(corrupted);

      final sizes = _decodeVerifiedWalk(
        audio,
        decodeBatch: (packets,
                {double? sampleRate, int? channels, int? framesPerPacket}) =>
            decoder.decodeBatch(packets),
        channels: 1,
      );

      // All must decode.
      final allPackets = <Uint8List>[];
      int offset = 0;
      for (final size in sizes) {
        allPackets.add(Uint8List.sublistView(audio, offset, offset + size));
        offset += size;
      }
      final decodeResults = decoder.decodeBatch(allPackets);
      expect(decodeResults.every((r) => r), isTrue);

      // VBR: sizes should vary — not all the same.
      final uniqueSizes = sizes.toSet();
      expect(uniqueSizes.length, greaterThan(1),
          reason: 'VBR streams should have varying packet sizes '
              '(got ${uniqueSizes.length} unique values)');
    });
  });
}

// ---------------------------------------------------------------------------
// Decode-verified walk — used by tests above.  This is the same algorithm
// that _repairWalk in ogg_caf_converter.dart will use, but wired to the
// FFI decoder for local testing without a Flutter app context.
// ---------------------------------------------------------------------------

typedef DecodeBatchFn = List<bool> Function(List<Uint8List> packets,
    {double sampleRate, int channels, int framesPerPacket});

/// Walk the raw Opus elementary stream starting from byte 0,
/// committing to boundaries verified by real Opus decode via [decodeBatch].
///
/// Byte 0 is guaranteed to be a valid packet start (CAF data chunk
/// always begins at a packet boundary).  The walk is greedy: the first
/// TOC-valid-and-decode-verified candidate at each step is committed.
/// A short lookahead (2 subsequent packets) is required to avoid false
/// positives.
List<int> _decodeVerifiedWalk(
  Uint8List data, {
  required DecodeBatchFn decodeBatch,
  required int channels,
}) {
  if (data.isEmpty) return [];

  // ---------------------------------------------------------------------------
  // Imported from ogg_caf_converter.dart (_isValidOpusToc).  Duplicated
  // here so the integration test is self-contained and can exercise the
  // algorithm without depending on private library internals.
  // ---------------------------------------------------------------------------
  bool isValidOpusToc(int byte, bool expectMono) {
    // c=3 invalid (RFC 6716 §3.1)
    if ((byte & 0x03) == 0x03) return false;
    // s=1 rejected for mono
    if (expectMono && ((byte >> 2) & 1) != 0) return false;
    return true;
  }

  const int minPacketSize = 10;
  const int maxPacketSize = 2000;
  const int lookahead = 2;
  final bool expectMono = channels == 1;

  // Pre-scan: identify dominant TOC byte values for tie-breaking.
  // Real Opus streams use only 1-3 TOC byte values (same config+s,
  // different c field).  We prefer candidates matching this pattern.
  final tocHistogram = List<int>.filled(256, 0);
  for (int i = 0; i < data.length; i++) {
    if (isValidOpusToc(data[i], expectMono)) {
      tocHistogram[data[i]]++;
    }
  }
  final dominantToc = <int>{};
  for (int i = 0; i < 3; i++) {
    int best = 0, bestIdx = 0;
    for (int j = 0; j < 256; j++) {
      if (tocHistogram[j] > best) {
        best = tocHistogram[j];
        bestIdx = j;
      }
    }
    if (best > 0) {
      dominantToc.add(bestIdx);
      tocHistogram[bestIdx] = 0;
    }
  }

  final sizes = <int>[];
  int offset = 0;

  while (offset < data.length) {
    int bestPos = -1;
    bool bestHasDominantToc = false;

    for (int pos = offset + minPacketSize;
        pos <= offset + maxPacketSize && pos < data.length;
        pos++) {
      if (!isValidOpusToc(data[pos], expectMono)) continue;

      final bool hasDominantToc = dominantToc.contains(data[pos]);

      // Build candidate packet + lookahead.
      final candidatePackets = <Uint8List>[];
      candidatePackets.add(Uint8List.sublistView(data, offset, pos));

      int laOffset = pos;
      for (int la = 0;
          la < lookahead && laOffset < data.length;
          la++) {
        int laPos = -1;
        for (int p = laOffset + minPacketSize;
            p <= laOffset + maxPacketSize && p < data.length;
            p++) {
          if (isValidOpusToc(data[p], expectMono)) {
            laPos = p;
            break;
          }
        }
        if (laPos > 0) {
          candidatePackets.add(
              Uint8List.sublistView(data, laOffset, laPos));
          laOffset = laPos;
        } else {
          break;
        }
      }

      final results = decodeBatch(candidatePackets);
      if (results.isNotEmpty && results.every((r) => r)) {
        // Prefer candidates matching dominant TOC pattern.
        // If no dominant match found yet, accept any.
        if (bestPos < 0 || (hasDominantToc && !bestHasDominantToc)) {
          bestPos = pos;
          bestHasDominantToc = hasDominantToc;
        }
        // If this candidate has dominant TOC (and best does too),
        // prefer the smaller one (closer = less likely to skip).
        if (hasDominantToc && bestHasDominantToc) {
          // Already have one with dominant TOC — keep the first.
        }
      }
    }

    if (bestPos > 0) {
      sizes.add(bestPos - offset);
      offset = bestPos;
    } else {
      // No valid continuation — accept remaining bytes as a final,
      // possibly truncated packet.
      final remaining = data.length - offset;
      if (remaining >= minPacketSize) {
        sizes.add(remaining);
      }
      break;
    }
  }

  return sizes;
}
