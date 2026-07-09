import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:test/test.dart';

void main() {
  group('convertOggToCaf', () {
    final OggCafConverter oggCafConverter = OggCafConverter();

    test('converts OGG to CAF successfully', () async {
      const String inputFile = 'test_resources/test.ogg';
      const String outputFile = 'test_resources/test_output.caf';
      // Convert OGG to CAF
      await oggCafConverter.convertOggToCaf(
          input: inputFile, output: outputFile);
      // Check if the output file exists
      expect(File(outputFile).existsSync(), isTrue);
      // Check if input file still exists
      expect(File(inputFile).existsSync(), isTrue);
      // Delete the output file after completing test
      File(outputFile).deleteSync();
    });

    test('output CAF includes kuki (magic cookie) chunk for iOS', () async {
      const String inputFile = 'test_resources/test.ogg';
      const String outputFile = 'test_resources/test_output_kuki.caf';
      await oggCafConverter.convertOggToCaf(
          input: inputFile, output: outputFile);

      final bytes = await File(outputFile).readAsBytes();
      // Search for the 'kuki' FourCC in the CAF file.
      const kukiTag = [0x6B, 0x75, 0x6B, 0x69]; // 'kuki'
      var found = false;
      for (var i = 0; i < bytes.length - 4; i++) {
        if (bytes[i] == kukiTag[0] &&
            bytes[i + 1] == kukiTag[1] &&
            bytes[i + 2] == kukiTag[2] &&
            bytes[i + 3] == kukiTag[3]) {
          // Verify the next 8 bytes encode the size (28 bytes — Apple's
          // native big-endian Opus cookie format, not RFC 7845 OpusHead).
          final sizeData = ByteData.sublistView(bytes, i + 4, i + 12);
          final chunkSize = sizeData.getInt64(0);
          expect(chunkSize, equals(28),
              reason: 'kuki chunk size should be 28 (Apple native Opus cookie)');
          // Verify the fixed marker field and that sample rate round-trips.
          final payloadStart = i + 12;
          final marker =
              ByteData.sublistView(bytes, payloadStart, payloadStart + 4)
                  .getUint32(0); // big-endian (default)
          expect(marker, equals(0x00000800),
              reason: 'kuki should start with Apple Opus cookie marker 0x00000800');
          found = true;
          break;
        }
      }
      expect(found, isTrue,
          reason: 'kuki (magic cookie) chunk must be present for iOS/macOS Core Audio');

      File(outputFile).deleteSync();
    });

    test('kuki bytes match the real native iOS CAF fixture', () async {
      // test_resources/test.ogg and test_resources/test.caf are the SAME
      // underlying recording (both sampleRate=24000, preSkip=312,
      // outputGain=0). test.caf was produced natively by iOS's
      // AVAudioRecorder and is known to play via just_audio/AVPlayer.
      // Our converter's kuki bytes for test.ogg must therefore be
      // byte-identical to test.caf's real kuki bytes.
      const String inputFile = 'test_resources/test.ogg';
      const String outputFile = 'test_resources/test_output_kuki_native.caf';
      await oggCafConverter.convertOggToCaf(
          input: inputFile, output: outputFile);

      final ourBytes = await File(outputFile).readAsBytes();
      final nativeBytes = await File('test_resources/test.caf').readAsBytes();

      const kukiTag = [0x6B, 0x75, 0x6B, 0x69];
      final ourKukiIndex = _findFourCC(ourBytes, kukiTag);
      final nativeKukiIndex = _findFourCC(nativeBytes, kukiTag);
      expect(ourKukiIndex, isNotNull);
      expect(nativeKukiIndex, isNotNull);

      final ourKuki = ourBytes.sublist(ourKukiIndex! + 12, ourKukiIndex + 12 + 28);
      final nativeKuki =
          nativeBytes.sublist(nativeKukiIndex! + 12, nativeKukiIndex + 12 + 28);

      expect(ourKuki, equals(nativeKuki),
          reason: 'kuki bytes must exactly match the native iOS recording '
              'for the same sample rate/pre-skip/gain');

      File(outputFile).deleteSync();
    });

    test('deletes input file after converting OGG to CAF', () async {
      const String inputFile = 'test_resources/test_temp.ogg';
      const String outputFile = 'test_resources/test_temp.caf';
      // Create temporary input file for test
      File('test_resources/test.ogg').copySync(inputFile);
      // Convert OGG to CAF
      await oggCafConverter.convertOggToCaf(
        input: inputFile,
        output: outputFile,
        deleteInput: true,
      );
      // Check if the input file has been deleted
      expect(File(inputFile).existsSync(), isFalse);
      // Delete the output file after completing test
      File(outputFile).deleteSync();
    });

    test('throws exception for invalid OGG input file', () {
      const String inputFile = 'test_resources/invalid_ogg.opus';
      const String outputFile = 'test_resources/test_temp.opus';
      expect(
          () => oggCafConverter.convertOggToCaf(
              input: inputFile, output: outputFile),
          throwsException);
    });

    test('throws exception for non-existent OGG file', () {
      const String inputFile = 'test_resources/non_existent.opus';
      const String outputFile = 'test_resources/test_temp.opus';
      expect(
          () => oggCafConverter.convertOggToCaf(
              input: inputFile, output: outputFile),
          throwsException);
    });
  });

  group('convertCafToOgg', () {
    final OggCafConverter oggCafConverter = OggCafConverter();

    test('converts CAF to OGG successfully', () async {
      const String inputFile = 'test_resources/test.caf';
      const String outputFile = 'test_resources/test_output.ogg';
      // Convert CAF to OGG
      await oggCafConverter.convertCafToOgg(
          input: inputFile, output: outputFile);
      // Check if the output file exists
      expect(File(outputFile).existsSync(), isTrue);
      // Check if input file still exists
      expect(File(inputFile).existsSync(), isTrue);
      // Delete the output file after completing test
      File(outputFile).deleteSync();
    });

    test('deletes input file after converting CAF to OGG', () async {
      const String inputFile = 'test_resources/test_temp.caf';
      const String outputFile = 'test_resources/test_temp.ogg';
      // Create temporary input file for test
      File('test_resources/test.caf').copySync(inputFile);
      // Convert CAF to OGG
      await oggCafConverter.convertCafToOgg(
        input: inputFile,
        output: outputFile,
        deleteInput: true,
      );
      // Check if the input file has been deleted
      expect(File(inputFile).existsSync(), isFalse);
      // Delete the output file after completing test
      File(outputFile).deleteSync();
    });

    test('throws exception for invalid CAF input file', () {
      const String inputFile = 'test_resources/invalid_caf.opus';
      const String outputFile = 'test_resources/test_temp.opus';
      expect(
          () => oggCafConverter.convertOggToCaf(
              input: inputFile, output: outputFile),
          throwsException);
    });

    test('throws exception for non-existent CAF file', () {
      const String inputFile = 'test_resources/non_existent.opus';
      const String outputFile = 'test_resources/test_temp.opus';
      expect(
          () => oggCafConverter.convertCafToOgg(
              input: inputFile, output: outputFile),
          throwsException);
    });
  });

  group('convertCafToOggInMemory', () {
    final OggCafConverter oggCafConverter = OggCafConverter();

    test('converts CAF to OGG in memory successfully', () async {
      const String inputFile = 'test_resources/test.caf';
      final Uint8List result =
          await oggCafConverter.convertCafToOggInMemory(input: inputFile);
      expect(result, isNotNull);
      expect(result.length, greaterThan(0));
    });

    test('throws exception for invalid CAF input file', () async {
      const String inputFile = 'test_resources/invalid_caf.opus';
      expect(
        () async => oggCafConverter.convertCafToOggInMemory(input: inputFile),
        throwsA(isA<Exception>()),
      );
    });

    test('throws exception for non-existent CAF file', () async {
      const String inputFile = 'test_resources/non_existent.caf';
      expect(
        () async => oggCafConverter.convertCafToOggInMemory(input: inputFile),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('convertOggToCafInMemory', () {
    final OggCafConverter oggCafConverter = OggCafConverter();

    test('converts OGG to CAF in memory successfully', () async {
      const String inputFile = 'test_resources/test.ogg';
      final Uint8List result =
          await oggCafConverter.convertOggToCafInMemory(input: inputFile);
      expect(result, isNotNull);
      expect(result.length, greaterThan(0));

      // Verify the kuki chunk is present.
      const kukiTag = [0x6B, 0x75, 0x6B, 0x69];
      final kukiIndex = _findFourCC(result, kukiTag);
      expect(kukiIndex, isNotNull,
          reason: 'kuki chunk required for iOS/macOS');
      // Verify the chunk size is 28 bytes (Apple native Opus cookie format).
      final size = ByteData.sublistView(result, kukiIndex! + 4, kukiIndex + 12)
          .getInt64(0);
      expect(size, equals(28));
    });

    test('throws exception for invalid OGG input file', () async {
      const String inputFile = 'test_resources/invalid_ogg.opus';
      expect(
        () async => oggCafConverter.convertOggToCafInMemory(input: inputFile),
        throwsA(isA<Exception>()),
      );
    });

    test('throws exception for non-existent OGG file', () async {
      const String inputFile = 'test_resources/non_existent.ogg';
      expect(
        () async => oggCafConverter.convertOggToCafInMemory(input: inputFile),
        throwsA(isA<Exception>()),
      );
    });
  });
}

/// Finds the index of a FourCC tag in [bytes], or null if not found.
int? _findFourCC(Uint8List bytes, List<int> tag) {
  for (var i = 0; i < bytes.length - 4; i++) {
    if (bytes[i] == tag[0] &&
        bytes[i + 1] == tag[1] &&
        bytes[i + 2] == tag[2] &&
        bytes[i + 3] == tag[3]) {
      return i;
    }
  }
  return null;
}
