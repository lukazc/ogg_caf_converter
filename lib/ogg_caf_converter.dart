import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'models/caf_models.dart';
import 'models/ogg_models.dart';
import 'src/opus_decode_stub.dart'
    if (dart.library.ui) 'src/opus_decode_channel.dart';
import 'utils/logger.dart';

/// A class for converting OPUS audio data to and from OGG and CAF container formats.
class OggCafConverter {
  /// Converts OPUS audio data from OGG to CAF container format and saves it to the specified output path.
  ///
  /// [inputFile] is the path to the OPUS audio file in OGG container to be converted.
  /// Must have read access to this file path.
  ///
  /// [outputPath] is the path where the resulting OPUS audio file in CAF container will be saved.
  /// Must have write access to this file path.
  ///
  /// [deleteInput] specifies whether the input file should be deleted after conversion.
  /// Must have write access to the input file path.
  Future<void> convertOggToCaf({
    required String input,
    required String output,
    bool deleteInput = false,
  }) async {
    try {
      await _convertOggToCaf(input, output, deleteInput);
    } catch (e) {
      throw Exception(e);
    }
  }

  Future<void> _convertOggToCaf(
      String inputFile, String outputPath, bool deleteInput) async {
    final Uint8List encodedData = await _readOggToCafMemory(inputFile);

    // Atomic write: write to a temp file first, then rename.
    // This prevents data loss or corruption if the write is interrupted.
    final File outputFile = File(outputPath);
    final File tempFile =
        File('$outputPath.tmp.${DateTime.now().microsecondsSinceEpoch}');

    try {
      await tempFile.writeAsBytes(encodedData, flush: true);

      // If the target already exists, renameSync handles the
      // replacement atomically (on the same filesystem).
      if (outputFile.existsSync()) {
        tempFile.renameSync(outputPath);
      } else {
        await tempFile.rename(outputPath);
      }

      if (deleteInput) {
        await File(inputFile).delete();
      }
    } catch (e, stackTrace) {
      // Clean up temp file on failure — never leave junk behind.
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      log('Error converting OGG to CAF: $e');
      log(stackTrace.toString());

      throw Exception(e);
    }
  }

  Future<Uint8List> _readOggToCafMemory(String inputFile) async {
    late final OggReader ogg;
    try {
      ogg = OggReader(inputFile);
      final OggHeader header = await ogg.readHeaders();
      final OpusData opusData =
          await ogg.readOpusData(sampleRate: header.sampleRate);

      log('frameSize: ${opusData.frameSize}');

      final CafFile cf = _buildCafFile(
        header: header,
        audioData: opusData.audioData,
        trailingData: opusData.trailingData,
        frameSize: opusData.frameSize,
        opusHead: header.opusHead.isNotEmpty ? header.opusHead : null,
      );

      return cf.encode();
    } catch (e, stackTrace) {
      log('Error converting OGG to CAF: $e');
      log(stackTrace.toString());

      throw Exception(e);
    } finally {
      // Close input file
      await ogg.close();
    }
  }

  /// Converts OPUS audio data from OGG to CAF container format and returns the bytes in memory as a Uint8List.
  ///
  /// [inputFile] is the path to the OPUS audio file in OGG container to be converted.
  Future<Uint8List> convertOggToCafInMemory({
    required String input,
  }) async {
    try {
      return await _readOggToCafMemory(input);
    } catch (e) {
      throw Exception(e);
    }
  }

  /// Converts OPUS audio data from CAF to OGG container format and saves it to the specified output path.
  ///
  /// [inputFile] is the path to the OPUS audio file in CAF container to be converted.
  /// Must have read access to this file path.
  ///
  /// [outputPath] is the path where the resulting OPUS audio file in OGG container will be saved.
  /// Must have write access to this file path.
  ///
  /// [deleteInput] specifies whether the input file should be deleted after conversion.
  /// Must have write access to the input file path.
  Future<void> convertCafToOgg({
    required String input,
    required String output,
    bool deleteInput = false,
  }) async {
    try {
      await _convertCafToOgg(input, output, deleteInput);
    } catch (e) {
      throw Exception(e);
    }
  }

  Future<void> _convertCafToOgg(
      String inputFile, String outputPath, bool deleteInput) async {
    final Uint8List encodedData = await _convertCafToOggInMemory(inputFile);

    // Atomic write: write to temp file first, then rename.
    final File outputFile = File(outputPath);
    final File tempFile =
        File('$outputPath.tmp.${DateTime.now().microsecondsSinceEpoch}');

    try {
      await tempFile.writeAsBytes(encodedData, flush: true);

      if (outputFile.existsSync()) {
        tempFile.renameSync(outputPath);
      } else {
        await tempFile.rename(outputPath);
      }

      if (deleteInput) {
        await File(inputFile).delete();
      }
    } catch (e, stackTrace) {
      // Clean up temp file on failure.
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      log('Error converting CAF to OGG: $e');
      log(stackTrace.toString());
      throw Exception(e);
    }
  }

  Future<Uint8List> _convertCafToOggInMemory(String inputFile) async {
    try {
      final CafReader caf = CafReader(inputFile);
      final Uint8List bytes = await File(inputFile).readAsBytes();
      final Uint8List audioData = caf.readAudioData(bytes);
      final PacketTable packetTable = caf.readPacketTable(bytes);
      final AudioFormat audioFormat = caf.readAudioFormat(bytes);

      // Log lengths for debugging
      log('Audio data length: ${audioData.length}');
      log('Packet table length: ${packetTable.entries.length}');

      final OggFile ogg = buildOggFile(
        audioData: audioData,
        packetTable: packetTable.entries,
        channels: audioFormat.channelsPerPacket,
        preSkip: audioFormat.framesPerPacket,
        sampleRate: audioFormat.sampleRate.toInt(),
        version: 1,
        frameSize: audioFormat.framesPerPacket,
        repackage: false,
      );

      return ogg.encode();
    } catch (e, stackTrace) {
      log('Error converting CAF to OGG: $e');
      log(stackTrace.toString());
      throw Exception(e);
    }
  }

  /// Converts OPUS audio data from CAF to OGG container format and returns the bytes in memory as a Uint8List.
  ///
  /// [inputFile] is the path to the OPUS audio file in CAF container to be converted.
  Future<Uint8List> convertCafToOggInMemory({
    required String input,
  }) async {
    try {
      return await _convertCafToOggInMemory(input);
    } catch (e) {
      throw Exception(e);
    }
  }

  /// [decodeBatch] is the decode verification callback.  In a Flutter
  /// app, pass a closure wrapping `OpusDecodeChannel.decodePackets`.
  /// In tests, pass an `OpusFfiDecoder.decodeBatch` closure.
  Future<int> repairCaf({
    required String input,
    String? output,
  }) async {
    final bytes = await File(input).readAsBytes();
    final cafReader = CafReader(input);

    // Extract audio format and raw audio, ignoring the broken pakt.
    final audioFormat = cafReader.readAudioFormat(bytes);
    final audioData = cafReader.readAudioData(bytes);

    if (audioData.isEmpty) {
      throw Exception('No audio data found in CAF file');
    }

    log('Repair: audio=${audioData.length}B, '
        'sr=${audioFormat.sampleRate}, '
        'ch=${audioFormat.channelsPerPacket}, '
        'fpp=${audioFormat.framesPerPacket}');

    // Decode-verified boundary walk via iOS AVAudioConverter.
    final packetSizes = await _repairWalk(
      audioData,
      channels: audioFormat.channelsPerPacket,
      sampleRate: audioFormat.sampleRate,
      framesPerPacket: audioFormat.framesPerPacket,
    );

    if (packetSizes.isEmpty) {
      throw Exception('Could not find any Opus packet boundaries in audio data');
    }

    final int sum = packetSizes.reduce((a, b) => a + b);
    log('Repair: found ${packetSizes.length} packets, sum=$sum/${audioData.length}, '
        'avg=${(sum/packetSizes.length).toStringAsFixed(0)}B, '
        'min=${packetSizes.reduce((a,b)=>a<b?a:b)}, '
        'max=${packetSizes.reduce((a,b)=>a>b?a:b)}');

    // Build a new CAF with the repaired packet table.
    final cafFile = _buildRepairedCaf(
      audioFormat: audioFormat,
      audioData: audioData,
      packetSizes: packetSizes,
      originalBytes: bytes,
    );

    final outputPath = output ?? input;
    final outputFile = File(outputPath);
    final tempFile =
        File('$outputPath.tmp.${DateTime.now().microsecondsSinceEpoch}');

    try {
      await tempFile.writeAsBytes(cafFile.encode(), flush: true);
      if (outputFile.existsSync()) {
        tempFile.renameSync(outputPath);
      } else {
        await tempFile.rename(outputPath);
      }
      log('Repair: wrote ${cafFile.encode().length}B to $outputPath');
    } catch (e) {
      if (tempFile.existsSync()) {
        try { await tempFile.delete(); } catch (_) {}
      }
      rethrow;
    }

    return packetSizes.length;
  }

  /// Decode-verified boundary walk.
  ///
  /// Starts at byte 0 (guaranteed real packet start in a CAF data chunk).
  /// At each step, generates TOC-valid candidates, verifies each via
  /// [decodeBatch] + short lookahead, and commits the first verified
  /// boundary.  Candidates matching the dominant TOC byte pattern in the
  /// stream are preferred as tie-breakers.
  Future<List<int>> _repairWalk(
    Uint8List data, {
    required int channels,
    required double sampleRate,
    required int framesPerPacket,
  }) async {
    if (data.isEmpty) return [];

    const int minPacketSize = 10;
    const int maxPacketSize = 2000;
    const int lookahead = 2;
    final bool expectMono = channels == 1;

    // Pre-scan: identify dominant TOC byte values for tie-breaking.
    final tocHistogram = List<int>.filled(256, 0);
    for (int i = 0; i < data.length; i++) {
      if (_isValidOpusToc(data[i], expectMono: expectMono)) {
        tocHistogram[data[i]]++;
      }
    }
    final dominantToc = <int>{};
    for (int round = 0; round < 3; round++) {
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
    log('Repair walk: dominant TOC values: $dominantToc');

    // Helper: attempt decode via platform channel.
    Future<bool> tryDecode(List<Uint8List> packets) async {
      try {
        final results = await OpusDecodeChannel.decodePackets(
          packets: packets,
          sampleRate: sampleRate,
          channels: channels,
          framesPerPacket: framesPerPacket,
        );
        return results.isNotEmpty && results.every((r) => r);
      } catch (e) {
        log('Repair walk: decode error: $e');
        return false;
      }
    }

    final sizes = <int>[];
    int offset = 0;
    int step = 0;

    while (offset < data.length) {
      step++;
      int bestPos = -1;
      bool bestHasDominantToc = false;

      for (int pos = offset + minPacketSize;
          pos <= offset + maxPacketSize && pos < data.length;
          pos++) {
        if (!_isValidOpusToc(data[pos], expectMono: expectMono)) continue;

        final bool hasDominantToc = dominantToc.contains(data[pos]);

        // Build candidate + lookahead packets.
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
            if (_isValidOpusToc(data[p], expectMono: expectMono)) {
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

        // Decode-verify.
        final ok = await tryDecode(candidatePackets);
        if (ok) {
          if (bestPos < 0 || (hasDominantToc && !bestHasDominantToc)) {
            bestPos = pos;
            bestHasDominantToc = hasDominantToc;
          }
        }
      }

      if (bestPos > 0) {
        final int size = bestPos - offset;
        sizes.add(size);
        if (step <= 5 || step % 50 == 0) {
          log('Repair walk: step $step offset=$offset size=$size '
              'dominantToc=$bestHasDominantToc');
        }
        offset = bestPos;
      } else {
        // No valid continuation found.
        throw Exception(
            'Repair walk failed at offset $offset: no decode-verified '
            'candidate found in next $maxPacketSize bytes of '
            '${data.length}-byte audio stream.  The decode callback '
            'may be failing or the audio data is irrecoverably corrupted.');
      }
    }

    log('Repair walk: complete — ${sizes.length} packets in $step steps');
    return sizes;
  }

  /// Returns `true` if [byte] could be a valid Opus TOC byte.
  ///
  /// Validates per RFC 6716 §3.1:
  ///   - Frame count code c ≠ 3 (4 frames per packet is invalid)
  ///   - If [expectMono] is true, stereo flag s must be 0
  ///
  /// Note: we intentionally do NOT reject config values 20-31
  /// (RFC "reserved") because AVAudioRecorder's Opus encoder can use
  /// them in practice.
  static bool _isValidOpusToc(int byte, {bool expectMono = false}) {
    // c field (bits 1-0): frame count minus 1; 3 is invalid (RFC 6716 §3.1)
    if ((byte & 0x03) == 0x03) return false;

    // s field (bit 2): must be 0 for mono streams
    if (expectMono && ((byte >> 2) & 1) != 0) return false;

    return true;
  }

  /// Builds a repaired CAF file preserving the original `desc` and `kuki`
  /// chunks from [originalBytes], but replacing the `pakt` chunk with a new
  /// one built from the scanned [packetSizes], and adjusting the `data`
  /// chunk to match.
  CafFile _buildRepairedCaf({
    required AudioFormat audioFormat,
    required Uint8List audioData,
    required List<int> packetSizes,
    required Uint8List originalBytes,
  }) {
    final int totalFrames = packetSizes.length * audioFormat.framesPerPacket;
    final int packetTableLength = _calculatePacketTableLength(packetSizes);

    final CafFile cf = CafFile(
      fileHeader: FileHeader(
          fileType: FourByteString('caff'), fileVersion: 1, fileFlags: 0),
      chunks: <Chunk>[],
    );

    // Preserve the original desc chunk.
    cf.chunks.add(Chunk(
      header: ChunkHeader(
          chunkType: ChunkTypes.audioDescription, chunkSize: 32),
      contents: audioFormat,
    ));

    // Preserve the original kuki chunk if present; otherwise build one
    // from the audio format description (crashed CAF files lack a kuki
    // because AVAudioRecorder writes it only on stop()).
    final originalKuki = _extractChunk(originalBytes, 'kuki');
    final Uint8List kuki = originalKuki ??
        _buildAppleOpusKuki(
          sampleRate: audioFormat.sampleRate.toInt(),
          framesPerPacket: audioFormat.framesPerPacket,
        );
    cf.chunks.add(Chunk(
      header: ChunkHeader(
          chunkType: ChunkTypes.magicCookie, chunkSize: kuki.length),
      contents: MagicCookie(data: kuki),
    ));

    // Build new pakt.
    cf.chunks.add(Chunk(
      header: ChunkHeader(
          chunkType: ChunkTypes.packetTable, chunkSize: packetTableLength),
      contents: PacketTable(
        header: PacketTableHeader(
          numberPackets: packetSizes.length,
          numberValidFrames: totalFrames,
          primingFrames: 0,
          remainderFrames: 0,
        ),
        entries: packetSizes,
      ),
    ));

    // Calculate free padding to align audio data to 4096.
    final int offsetBeforeData =
        8 + 44 + 12 + kuki.length + 12 + packetTableLength;
    const int alignment = 4096;
    final int audioStartTarget =
        ((offsetBeforeData + 28 + alignment - 1) ~/ alignment) * alignment;
    final int freePayload = audioStartTarget - offsetBeforeData - 28;
    if (freePayload > 0) {
      cf.chunks.add(Chunk(
        header: ChunkHeader(
            chunkType: FourByteString('free'), chunkSize: freePayload),
        contents: UnknownContents(Uint8List(freePayload)),
      ));
    }

    // Data chunk.
    cf.chunks.add(Chunk(
      header: ChunkHeader(
          chunkType: ChunkTypes.audioData, chunkSize: audioData.length + 4),
      contents: AudioData(editCount: 1, data: audioData),
    ));

    return cf;
  }

  /// Extracts the payload of a named chunk from raw CAF bytes, or null if
  /// not found. Stops searching when it encounters the 'data' chunk since
  /// nothing follows it in a well-formed CAF.
  static Uint8List? _extractChunk(Uint8List bytes, String fourCc) {
    int offset = 8; // skip file header
    while (offset + 12 <= bytes.length) {
      final String chunkType = utf8.decode(bytes.sublist(offset, offset + 4));
      final int chunkSize =
          ByteData.sublistView(bytes, offset + 4, offset + 12).getInt64(0);
      if (chunkType == fourCc) {
        final int payloadLen =
            (chunkSize > 0 && offset + 12 + chunkSize <= bytes.length)
                ? chunkSize
                : (bytes.length - offset - 12).clamp(0, bytes.length);
        return bytes.sublist(offset + 12, offset + 12 + payloadLen);
      }
      // Stop at the data chunk — audio data bytes are not valid chunk headers
      // and trying to parse them as FourCC will throw FormatException.
      if (chunkType == 'data') break;
      offset += 12 + chunkSize;
    }
    return null;
  }

  /// Builds an OGG file from provided data.
  OggFile buildOggFile({
    required Uint8List audioData,
    required List<int> packetTable,
    required int channels,
    required int preSkip,
    required int sampleRate,
    required int version,
    required int frameSize,
    required bool repackage,
  }) {
    final OggFile oggFile = OggFile(pages: <OggPage>[]);

    int granulePosition = 0;
    int pageSequenceNumber = 0;
    final int serialNumber = DateTime.now().millisecondsSinceEpoch &
        0xFFFFFFFF; // Unique serial number
    int headerType = 0x02; // Begin of stream

    // Helper function to create a page header
    Uint8List createPageHeader({
      required int granulePosition,
      required int serialNumber,
      required int pageSequenceNumber,
      required Uint8List segments,
      required int headerType,
    }) {
      final List<int> header = <int>[];
      header.addAll(utf8.encode('OggS')); // Capture pattern
      header.add(0); // Stream structure version
      header.add(headerType); // Header type flag
      header.addAll(_encodeUint64(granulePosition)); // Granule position
      header.addAll(_encodeUint32(serialNumber)); // Stream serial number
      header.addAll(_encodeUint32(pageSequenceNumber)); // Page sequence number
      header.addAll(_encodeUint32(0)); // Placeholder for checksum
      header.add(segments.length); // Number of segments
      header.addAll(segments); // Segment table
      return Uint8List.fromList(header);
    }

    // Helper function to calculate the checksum
    int calculateChecksum(Uint8List header, Uint8List body) {
      final Uint8List page = Uint8List.fromList(header + body);
      int crc = 0;
      for (final int byte in page) {
        crc = (crc << 8) ^ _crcLookupTable[((crc >> 24) & 0xFF) ^ byte];
      }
      return crc & 0xFFFFFFFF;
    }

    // Create OPUS Head Packet
    Uint8List createOpusHeadPacket() {
      final List<int> packet = <int>[];
      packet.addAll(utf8.encode('OpusHead')); // Signature
      packet.add(1); // Version
      packet.add(channels); // Channels
      packet.addAll(_encodeUint16(preSkip)); // Pre-skip
      packet.addAll(_encodeUint32(sampleRate)); // Sample rate
      packet.addAll(_encodeUint16(0)); // Output gain
      packet.add(0); // Channel mapping family
      return Uint8List.fromList(packet);
    }

    // Create OPUS Tags Packet
    Uint8List createOpusTagsPacket() {
      final List<int> packet = <int>[];
      packet.addAll(utf8.encode('OpusTags')); // Signature
      packet.addAll(_encodeUint32(
          utf8.encode('Revival Apps').length)); // Vendor string length
      packet.addAll(utf8.encode('Revival Apps')); // Vendor string
      packet.addAll(_encodeUint32(0)); // User comment list length
      return Uint8List.fromList(packet);
    }

    // Split audio data into packets using the packetTable
    final List<Uint8List> packets = <Uint8List>[];
    int packetIndex = 0;
    for (final int packetSize in packetTable) {
      packets.add(audioData.sublist(packetIndex, packetIndex + packetSize));
      packetIndex += packetSize;
    }

    // Insert OPUS Head as the first page
    final Uint8List opusHeadPacket = createOpusHeadPacket();
    Uint8List header = createPageHeader(
      granulePosition: 0,
      serialNumber: serialNumber,
      pageSequenceNumber: pageSequenceNumber,
      segments: Uint8List.fromList(<int>[opusHeadPacket.length]),
      headerType: 0x02, // Begin of stream
    );
    int crc = calculateChecksum(header, opusHeadPacket);
    header.setRange(22, 26, _encodeUint32(crc));
    oggFile.pages.add(OggPage(header: header, body: opusHeadPacket));
    pageSequenceNumber++;

    // Insert OPUS Tags as the second page
    final Uint8List opusTagsPacket = createOpusTagsPacket();
    header = createPageHeader(
      granulePosition: 0,
      serialNumber: serialNumber,
      pageSequenceNumber: pageSequenceNumber,
      segments: Uint8List.fromList(<int>[opusTagsPacket.length]),
      headerType: 0x00, // Normal page, no continuation
    );
    crc = calculateChecksum(header, opusTagsPacket);
    header.setRange(22, 26, _encodeUint32(crc));
    oggFile.pages.add(OggPage(header: header, body: opusTagsPacket));
    pageSequenceNumber++;

    // Create pages from the audio packets
    // Ogg segments must be <= 255 bytes each
    const int maxOggSegmentSize = 255;
    List<int> currentSegment = <int>[];
    List<int> currentSegmentsTable = <int>[];
    headerType = 0x01; // continuation flag set for the first audio page

    for (final Uint8List packet in packets) {
      final int packetSize = packet.length;
      final int segmentCount =
          (packetSize + maxOggSegmentSize - 1) ~/ maxOggSegmentSize;

      for (int i = 0; i < segmentCount; i++) {
        final int start = i * maxOggSegmentSize;
        final int end = min(start + maxOggSegmentSize, packetSize);
        final int segmentSize = end - start;

        // If adding this segment would exceed 255 segments on the current page,
        // or the total segment data would exceed the page limit, flush the page.
        // (Optional boundary check — you may handle partial flush if needed.)
        if (currentSegmentsTable.length == 255 ||
            currentSegment.length + segmentSize > 65025) {
          // Create and finalize the current page
          header = createPageHeader(
            granulePosition: granulePosition,
            serialNumber: serialNumber,
            pageSequenceNumber: pageSequenceNumber,
            segments: Uint8List.fromList(currentSegmentsTable),
            headerType: headerType,
          );
          crc = calculateChecksum(header, Uint8List.fromList(currentSegment));
          header.setRange(22, 26, _encodeUint32(crc));
          oggFile.pages.add(OggPage(
              header: header, body: Uint8List.fromList(currentSegment)));
          pageSequenceNumber++;

          // Reset for the next page
          currentSegment = <int>[];
          currentSegmentsTable = <int>[];
          // After the first audio page, normal pages won't have the "fresh" (0x02) bit
          headerType = 0x00;
        }

        // Append this segment of data
        currentSegment.addAll(packet.sublist(start, end));
        currentSegmentsTable.add(segmentSize);
      }

      // Update granule position (this is a simplistic approach)
      if (repackage) {
        granulePosition += frameSize;
      } else {
        // For example, if sampleRate=48000, frameSize is typically the number
        // of samples in an Opus frame at 48 kHz, so we scale if needed.
        granulePosition += frameSize * (48000 ~/ sampleRate);
      }
    }

    // Flush the last page (end of stream)
    if (currentSegment.isNotEmpty) {
      header = createPageHeader(
        granulePosition: granulePosition,
        serialNumber: serialNumber,
        pageSequenceNumber: pageSequenceNumber,
        segments: Uint8List.fromList(currentSegmentsTable),
        headerType: 0x04, // End of stream
      );
      crc = calculateChecksum(header, Uint8List.fromList(currentSegment));
      header.setRange(22, 26, _encodeUint32(crc));
      oggFile.pages.add(
          OggPage(header: header, body: Uint8List.fromList(currentSegment)));
    }

    return oggFile;
  }

  Uint8List _encodeUint64(int value) {
    return Uint8List.fromList(<int>[
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
      (value >> 32) & 0xFF,
      (value >> 40) & 0xFF,
      (value >> 48) & 0xFF,
      (value >> 56) & 0xFF,
    ]);
  }

  Uint8List _encodeUint32(int value) {
    return Uint8List.fromList(<int>[
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  Uint8List _encodeUint16(int value) {
    return Uint8List.fromList(<int>[
      value & 0xFF,
      (value >> 8) & 0xFF,
    ]);
  }

  final Uint8List _crcLookupTable =
      Uint8List.fromList(List<int>.generate(256, (int i) {
    int r = i << 24;
    for (int j = 0; j < 8; j++) {
      if (r & 0x80000000 != 0) {
        r = ((r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
      } else {
        r = (r << 1) & 0xFFFFFFFF;
      }
    }
    return r;
  }));

  /// Calculates the length of the packet table based on trailing data.
  int _calculatePacketTableLength(List<int> trailingData) {
    int packetTableLength = 24;

    for (final int value in trailingData) {
      int numBytes = 0;
      if ((value & 0x7f) == value) {
        numBytes = 1;
      } else if ((value & 0x3fff) == value) {
        numBytes = 2;
      } else if ((value & 0x1fffff) == value) {
        numBytes = 3;
      } else if ((value & 0x0fffffff) == value) {
        numBytes = 4;
      } else {
        numBytes = 5;
      }
      packetTableLength += numBytes;
    }
    return packetTableLength;
  }

  /// Builds the 28-byte Apple-native Opus magic cookie for the 'kuki' chunk.
  ///
  /// CAF files (and their chunk contents written by Apple's own encoders)
  /// are big-endian. This layout was reverse-engineered from a real CAF
  /// produced by iOS's AVAudioRecorder (see test_resources/test.caf) and
  /// confirmed byte-for-byte (see
  /// "kuki bytes match the real native iOS CAF fixture" test) to match what
  /// a real iOS device writes for the same sample rate / frames-per-packet.
  ///
  /// Note: [outputGain] is intentionally NOT taken from the source OGG
  /// stream's OpusHead. Empirically, the native fixture's OpusHead has
  /// outputGain=0 while its CAF kuki has -1000 (~-3.9 dB) — this appears to
  /// be a fixed compensation constant that AVAudioRecorder's Opus encoder
  /// always writes, unrelated to the source stream's own gain field. We
  /// replicate that fixed constant rather than deriving it, since deriving
  /// it from the wrong source previously produced an undecodable cookie.
  Uint8List _buildAppleOpusKuki({
    required int sampleRate,
    required int framesPerPacket,
  }) {
    const int fixedOutputGain = -1000;

    // ByteData defaults to big-endian, which is what CAF requires — but we
    // set it explicitly below since getting this wrong is exactly what
    // caused this cookie format to be rejected by AVFoundation previously.
    final ByteData data = ByteData(28);
    data.setUint32(0, 0x00000800); // Endian.big (default)
    data.setUint32(4, sampleRate); // Endian.big (default)
    data.setUint32(8, framesPerPacket); // Endian.big (default)
    data.setInt32(12, fixedOutputGain); // Endian.big (default)
    data.setUint32(16, 0x00000001); // Endian.big (default)
    data.setUint32(20, 0x00000000); // Endian.big (default)
    data.setUint32(24, 0x00000000); // Endian.big (default)
    return data.buffer.asUint8List();
  }

  /// Builds a CAF file from provided data.
  ///
  /// A 'kuki' (magic cookie) chunk is always inserted immediately after
  /// 'desc', built from [header]'s sample rate / gain and [frameSize]. This
  /// is **required** for Core Audio playback on iOS/macOS. See
  /// [_buildAppleOpusKuki] for the exact byte layout.
  ///
  /// [opusHead] (the raw 19-byte RFC 7845 OpusHead packet) is retained on
  /// [OggHeader] for diagnostic/round-trip purposes but is not used to build
  /// the CAF kuki chunk — Apple's Core Audio expects its own cookie format,
  /// not the raw Ogg identification header.
  CafFile _buildCafFile({
    required OggHeader header,
    required Uint8List audioData,
    required List<int> trailingData,
    required int frameSize,
    Uint8List? opusHead,
  }) {
    final int lenAudio = audioData.length;
    final int packets = trailingData.length;
    final int frames = frameSize * packets;

    final int packetTableLength = _calculatePacketTableLength(trailingData);

    log('frameSize: $frameSize packetTableLength: $packetTableLength frames: $frames packets: $packets lenAudio: $lenAudio');

    final CafFile cf = CafFile(
        fileHeader: FileHeader(
            fileType: FourByteString('caff'), fileVersion: 1, fileFlags: 0),
        chunks: <Chunk>[]);

    final Chunk c = Chunk(
      header:
          ChunkHeader(chunkType: ChunkTypes.audioDescription, chunkSize: 32),
      contents: AudioFormat(
        sampleRate: header.sampleRate.toDouble(),
        formatID: FourByteString('opus'),
        formatFlags: 0x00000000,
        bytesPerPacket: 0,
        framesPerPacket: frameSize,
        channelsPerPacket: header.channels,
        bitsPerChannel: 0,
      ),
    );

    cf.chunks.add(c);

    // kuki (magic cookie) must come immediately after 'desc'.
    // Core Audio on iOS/macOS requires this to initialize the Opus decoder.
    //
    // This is NOT the RFC 7845 OpusHead packet. It is Apple's own 28-byte
    // big-endian cookie format, verified byte-for-byte against a native CAF
    // recorded by AVAudioRecorder (test_resources/test.caf) which is known
    // to play correctly via just_audio/AVPlayer on iOS:
    //
    //   offset  0 (u32 BE): 0x00000800           - fixed marker/flags
    //   offset  4 (u32 BE): sample rate           (matches desc.sampleRate)
    //   offset  8 (u32 BE): frames per packet     (matches desc.framesPerPacket)
    //   offset 12 (i32 BE): -1000                 - fixed (see _buildAppleOpusKuki)
    //   offset 16 (u32 BE): 0x00000001            - fixed
    //   offset 20 (u32 BE): 0x00000000            - fixed
    //   offset 24 (u32 BE): 0x00000000            - fixed
    final Uint8List kuki = _buildAppleOpusKuki(
      sampleRate: header.sampleRate,
      framesPerPacket: frameSize,
    );
    cf.chunks.add(Chunk(
      header: ChunkHeader(
          chunkType: ChunkTypes.magicCookie, chunkSize: kuki.length),
      contents: MagicCookie(data: kuki),
    ));
    log('added kuki chunk (${kuki.length} bytes)');

    // pakt (packet table). iOS native CAF files have primingFrames=0 —
    // the Opus pre-skip is handled by the decoder's own bitstream
    // parsing. This matches the structure produced by AVAudioRecorder.
    final Chunk paktChunk = Chunk(
      header: ChunkHeader(
          chunkType: ChunkTypes.packetTable, chunkSize: packetTableLength),
      contents: PacketTable(
        header: PacketTableHeader(
          numberPackets: packets,
          numberValidFrames: frames,
          primingFrames: 0,
          remainderFrames: 0,
        ),
        entries: trailingData,
      ),
    );

    cf.chunks.add(paktChunk);

    // Pad with a 'free' chunk so that the actual audio data bytes
    // (data chunk header + editCount + audio) land on a 4096-byte
    // boundary. This mirrors what iOS's AVAudioRecorder produces.
    //
    // Current offset = 8 (file header) + 44 (desc) + 40 (kuki)
    //                 + 12 (pakt header) + packetTableLength (pakt payload)
    final int offsetBeforeData = 8 + 44 + 40 + 12 + packetTableLength;
    // data chunk header = 12 bytes, editCount = 4 bytes
    // We want offsetBeforeData + freeHdr(12) + freePayload + dataHdr(12) + 4
    // to be the next multiple of 4096.
    // Simplifying: audio start = offsetBeforeData + freePayload + 28
    // Target: (offsetBeforeData + freePayload + 28) % 4096 == 0
    const int alignment = 4096;
    final int audioStartTarget =
        ((offsetBeforeData + 28 + alignment - 1) ~/ alignment) * alignment;
    final int freePayload = audioStartTarget - offsetBeforeData - 28;
    if (freePayload > 0) {
      cf.chunks.add(Chunk(
        header: ChunkHeader(
            chunkType: FourByteString('free'), chunkSize: freePayload),
        contents: UnknownContents(Uint8List(freePayload)),
      ));
    }

    // 'data' chunk comes last. editCount=1 matches iOS native output.
    final Chunk dataChunk = Chunk(
      header:
          ChunkHeader(chunkType: ChunkTypes.audioData, chunkSize: lenAudio + 4),
      contents: AudioData(editCount: 1, data: audioData),
    );

    cf.chunks.add(dataChunk);

    return cf;
  }
}

/// A class for reading CAF files.
class CafReader {
  CafReader(this.filePath);

  /// The path to the CAF file.
  final String filePath;

  /// Reads the audio data from the CAF file.
  Uint8List readAudioData(Uint8List bytes) {
    int offset = 0;

    // Read the CAF file header
    final String fileType = utf8.decode(bytes.sublist(offset, offset + 4));
    offset += 4;
    final int fileVersion =
        ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 2)
            .getUint16(0);
    offset += 2;
    final int fileFlags =
        ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 2)
            .getUint16(0);
    offset += 2;

    log('File type: $fileType, File version: $fileVersion, File flags: $fileFlags');

    while (offset < bytes.length) {
      // Read chunk header
      final String chunkType = utf8.decode(bytes.sublist(offset, offset + 4));
      final int chunkSize = ByteData.sublistView(
              Uint8List.fromList(bytes), offset + 4, offset + 12)
          .getUint64(0);
      offset += 12; // Move past the chunk header

      log('Chunk type: $chunkType, Chunk size: $chunkSize');

      if (chunkType == 'data') {
        // We found the audio data chunk.
        // When AVAudioRecorder crashes mid-recording, the data chunk size
        // may be 0 or -1 (a placeholder never finalized by stop()). In that
        // case, read all remaining bytes as audio.
        final int effectiveSize = (chunkSize > 0 && offset + chunkSize <= bytes.length)
            ? chunkSize
            : (bytes.length - offset);

        final int editCount = (effectiveSize >= 4)
            ? ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 4)
                .getUint32(0)
            : 0;
        if (effectiveSize >= 4) offset += 4;

        final Uint8List audioData = bytes.sublist(offset,
            offset + effectiveSize - 4);
        log('Audio data chunk found at offset $offset with size $chunkSize (effective: $effectiveSize), edit count: $editCount');
        return audioData;
      }

      // Move to the next chunk
      offset += chunkSize;
    }

    throw Exception('Audio data chunk not found');
  }

  /// Reads the packet table from the CAF file.
  PacketTable readPacketTable(Uint8List bytes) {
    int offset = 8;

    while (offset < bytes.length) {
      // Read chunk header
      final String chunkType = utf8.decode(bytes.sublist(offset, offset + 4));
      final int chunkSize = ByteData.sublistView(
              Uint8List.fromList(bytes), offset + 4, offset + 12)
          .getUint64(0);
      offset += 12; // Move past the chunk header

      if (chunkType == 'pakt') {
        // We found the packet table chunk
        final Uint8List packetTableBytes =
            bytes.sublist(offset, offset + chunkSize);

        final int numberPackets =
            ByteData.sublistView(Uint8List.fromList(packetTableBytes), 0, 8)
                .getUint64(0);
        final int numberValidFrames =
            ByteData.sublistView(Uint8List.fromList(packetTableBytes), 8, 16)
                .getUint64(0);
        final int primingFrames =
            ByteData.sublistView(Uint8List.fromList(packetTableBytes), 16, 20)
                .getUint32(0);
        final int remainderFrames =
            ByteData.sublistView(Uint8List.fromList(packetTableBytes), 20, 24)
                .getUint32(0);
        final Uint8List entries = packetTableBytes.sublist(24);

        log('Pakt numberPackets: $numberPackets numberValidFrames: $numberValidFrames primingFrames: $primingFrames remainderFrames: $remainderFrames');

        final PacketTableHeader header = PacketTableHeader(
          numberPackets: numberPackets,
          numberValidFrames: numberValidFrames,
          primingFrames: primingFrames,
          remainderFrames: remainderFrames,
        );

        log('Packet table chunk found at offset $offset with size $chunkSize');

        // Decode varint-encoded packet sizes.
        final List<int> decodedEntries = decodeVarintEntries(entries);

        if (decodedEntries.length != numberPackets) {
          log('Warning: Number of packets in header does not match the length of packet table entries (${decodedEntries.length} / $numberPackets)');
        }

        return PacketTable(header: header, entries: decodedEntries);
      }

      // Move to the next chunk
      offset += chunkSize;
    }

    throw Exception('Packet table chunk not found');
  }

  /// Reads the audio format from the CAF file.
  AudioFormat readAudioFormat(Uint8List bytes) {
    int offset = 8;

    while (offset < bytes.length) {
      // Read chunk header
      final String chunkType = utf8.decode(bytes.sublist(offset, offset + 4));
      final int chunkSize = ByteData.sublistView(
              Uint8List.fromList(bytes), offset + 4, offset + 12)
          .getUint64(0);
      offset += 12; // Move past the chunk header

      log('Chunk type: $chunkType, Chunk size: $chunkSize');

      if (chunkType == 'desc') {
        // We found the audio format chunk
        final Uint8List formatBytes = bytes.sublist(offset, offset + chunkSize);

        final double sampleRate =
            ByteData.sublistView(Uint8List.fromList(formatBytes), 0, 8)
                .getFloat64(0);
        final FourByteString formatID =
            FourByteString(utf8.decode(formatBytes.sublist(8, 12)));
        final int formatFlags =
            ByteData.sublistView(Uint8List.fromList(formatBytes), 12, 16)
                .getUint32(0);
        final int bytesPerPacket =
            ByteData.sublistView(Uint8List.fromList(formatBytes), 16, 20)
                .getUint32(0);
        final int framesPerPacket =
            ByteData.sublistView(Uint8List.fromList(formatBytes), 20, 24)
                .getUint32(0);
        final int channelsPerFrame =
            ByteData.sublistView(Uint8List.fromList(formatBytes), 24, 28)
                .getUint32(0);
        final int bitsPerChannel =
            ByteData.sublistView(Uint8List.fromList(formatBytes), 28, 32)
                .getUint32(0);

        log('Audio format chunk found at offset $offset with size $chunkSize');
        log('sampleRate: $sampleRate formatID: $formatID formatFlags: $formatFlags bytesPerPacket: $bytesPerPacket framesPerPacket: $framesPerPacket channelsPerFrame: $channelsPerFrame bitsPerChannel: $bitsPerChannel');

        return AudioFormat(
          sampleRate: sampleRate,
          formatID: formatID,
          formatFlags: formatFlags,
          bytesPerPacket: bytesPerPacket,
          framesPerPacket: framesPerPacket,
          channelsPerPacket: channelsPerFrame,
          bitsPerChannel: bitsPerChannel,
        );
      }

      // Move to the next chunk
      offset += chunkSize;
    }

    throw Exception('Audio format chunk not found');
  }
}

/// A class representing an OGG file.
class OggFile {
  OggFile({required this.pages});

  /// The pages in the OGG file.
  List<OggPage> pages;

  /// Encodes the OGG file to a list of bytes.
  Uint8List encode() {
    final int totalLength = pages.fold(0,
        (int sum, OggPage page) => sum + page.header.length + page.body.length);
    final Uint8List fileData = Uint8List(totalLength);
    int offset = 0;

    for (final OggPage page in pages) {
      fileData.setRange(offset, offset + page.header.length, page.header);
      offset += page.header.length;
      fileData.setRange(offset, offset + page.body.length, page.body);
      offset += page.body.length;
    }

    return fileData;
  }
}

/// A class representing an OGG page.
class OggPage {
  OggPage({required this.header, required this.body});

  /// The header of the OGG page.
  Uint8List header;

  /// The body of the OGG page.
  Uint8List body;
}
