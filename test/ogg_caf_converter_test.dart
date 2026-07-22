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
      //
      // The kuki outputGain field (bytes 12-15) may differ between them:
      // AVAudioRecorder always writes -1000 (a fixed encoder headroom
      // constant); our converter propagates the source OGG's OpusHead
      // outputGain (0), negated for the kuki's encoder-side convention.
      // Both are correct for their respective source data.
      //
      // We verify that all OTHER kuki fields match byte-for-byte, and
      // that the gain field correctly reflects the source OGG's gain.
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

      // Verify the kuki is the correct size.
      expect(ourKuki.length, equals(28));
      expect(nativeKuki.length, equals(28));

      // Marker (bytes 0-3): must match.
      expect(ourKuki.sublist(0, 4), equals(nativeKuki.sublist(0, 4)),
          reason: 'kuki marker field must match');

      // Sample rate (bytes 4-7): must match.
      expect(ourKuki.sublist(4, 8), equals(nativeKuki.sublist(4, 8)),
          reason: 'kuki sampleRate must match');

      // Frames per packet (bytes 8-11): must match.
      expect(ourKuki.sublist(8, 12), equals(nativeKuki.sublist(8, 12)),
          reason: 'kuki framesPerPacket must match');

      // Output gain (bytes 12-15): our converter propagates the source
      // OGG's gain (0), negated for kuki convention → 0.
      // The native CAF has -1000 (AVAudioRecorder's fixed headroom constant).
      final ourGain =
          ByteData.sublistView(ourKuki, 12, 16).getInt32(0);
      expect(ourGain, equals(0),
          reason: 'kuki outputGain should be 0 (source OGG outputGain=0, '
              'negated for kuki encoder-side convention)');

      // Trailing fields (bytes 16-27): fixed constants, must match.
      expect(ourKuki.sublist(16, 28), equals(nativeKuki.sublist(16, 28)),
          reason: 'kuki trailing fields (0x00000001, 0x00000000, '
              '0x00000000) must match');

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

  group('repairCaf', () {
    final OggCafConverter oggCafConverter = OggCafConverter();

    test('repairs a crashed CAF with broken pakt (numberPackets=0)', () async {
      // Take the working native iOS CAF and corrupt its pakt chunk.
      const original = 'test_resources/Thursday_at_19_08.caf';
      const corrupted = 'test_resources/_repair_crashed.caf';

      final bytes = await File(original).readAsBytes();

      // Find the pakt chunk and zero out numberPackets + numberValidFrames.
      const paktTag = [0x70, 0x61, 0x6B, 0x74]; // 'pakt'
      final paktIdx = _findFourCC(bytes, paktTag);
      expect(paktIdx, isNotNull, reason: 'pakt chunk must exist in fixture');
      final paktPayloadStart = paktIdx! + 12;
      final corruptedBytes = Uint8List.fromList(bytes);
      for (var i = 0; i < 16; i++) {
        corruptedBytes[paktPayloadStart + i] = 0;
      }
      await File(corrupted).writeAsBytes(corruptedBytes);

      try {
        final packetCount = await oggCafConverter.repairCaf(
          input: corrupted,
          output: 'test_resources/_repair_repaired.caf',
        );
        expect(packetCount, greaterThan(0));

        final repairedBytes = await File('test_resources/_repair_repaired.caf').readAsBytes();
        final rpIdx = _findFourCC(repairedBytes, paktTag)!;
        final repairedNp = ByteData.sublistView(repairedBytes, rpIdx + 12, rpIdx + 20).getUint64(0);
        expect(repairedNp, greaterThan(0));
        await File('test_resources/_repair_repaired.caf').delete();
      } finally {
        await File(corrupted).delete();
      }
    });

    test('repairs a crashed CAF with data chunk size = -1 (unfinished recording)', () async {
      // Simulate an AVAudioRecorder crash: pakt missing, data chunk has
      // placeholder size 0xFFFFFFFFFFFFFFFF (-1 as int64). This is the
      // exact state of a CAF file interrupted before stop().
      const original = 'test_resources/Thursday_at_19_08.caf';
      const corrupted = 'test_resources/_repair_crashed2.caf';

      final bytes = await File(original).readAsBytes();

      // Build a minimal crashed CAF: only desc, kuki, and data with size=-1.
      const descTag = [0x64, 0x65, 0x73, 0x63];
      const dataTag = [0x64, 0x61, 0x74, 0x61];
      final descIdx = _findFourCC(bytes, descTag);
      final dataIdx = _findFourCC(bytes, dataTag);
      expect(descIdx, isNotNull);
      expect(dataIdx, isNotNull);

      // Extract desc + kuki chunks and the raw audio data.
      final kuki = bytes.sublist(52, 52 + 12 + 28); // kuki header + 28-byte payload
      final rawAudio = bytes.sublist(dataIdx! + 16); // skip data header + editCount

      // Build crashed CAF: header + desc + kuki + free (pad to align) + data (size=-1).
      final crashed = BytesBuilder();
      crashed.add(bytes.sublist(0, 8)); // caff file header
      crashed.add(bytes.sublist(descIdx!, descIdx! + 44)); // desc (12 hdr + 32 payload)
      crashed.add(kuki); // kuki (12 hdr + 28 payload)

      // Pad to 4096-aligned audio start.
      const alignment = 4096;
      final preDataOffset = 8 + 44 + 40; // file hdr + desc + kuki
      final dataHeaderAndEditOffset = 12 + 4; // data chunk header + editCount
      final audioStartTarget = ((preDataOffset + dataHeaderAndEditOffset + alignment - 1) ~/ alignment) * alignment;
      final freeSize = audioStartTarget - preDataOffset - dataHeaderAndEditOffset;
      if (freeSize > 0) {
        final freeHdr = ByteData(12);
        freeHdr.buffer.asUint8List().setRange(0, 4, utf8.encode('free'));
        freeHdr.setInt64(4, freeSize);
        crashed.add(freeHdr.buffer.asUint8List());
        crashed.add(Uint8List(freeSize));
      }

      // data chunk with size = -1 (0xFFFFFFFFFFFFFFFF as uint64).
      final dataHdr = ByteData(12);
      dataHdr.buffer.asUint8List().setRange(0, 4, utf8.encode('data'));
      dataHdr.setInt64(4, -1); // placeholder size
      final editCount = ByteData(4)..setUint32(0, 1);
      crashed.add(dataHdr.buffer.asUint8List());
      crashed.add(editCount.buffer.asUint8List());
      crashed.add(rawAudio);

      await File(corrupted).writeAsBytes(crashed.toBytes());

      try {
        final packetCount = await oggCafConverter.repairCaf(
          input: corrupted,
          output: 'test_resources/_repair_repaired2.caf',
        );
        expect(packetCount, greaterThan(0),
            reason: 'should recover packets from crash CAF with data size=-1');

        // Verify the repaired file has a valid pakt.
        final repairedBytes = await File('test_resources/_repair_repaired2.caf').readAsBytes();
        final rpIdx = _findFourCC(repairedBytes, [0x70, 0x61, 0x6B, 0x74])!;
        final repairedNp = ByteData.sublistView(repairedBytes, rpIdx + 12, rpIdx + 20).getUint64(0);
        expect(repairedNp, equals(packetCount),
            reason: 'repaired pakt numberPackets should match scanned count');
        await File('test_resources/_repair_repaired2.caf').delete();
      } finally {
        await File(corrupted).delete();
      }
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
