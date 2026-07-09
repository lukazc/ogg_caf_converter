import 'dart:io';
import 'dart:typed_data';

/// Diagnostic: reads a CAF file and dumps its chunk structure.
/// Usage: dart run test/dump_caf.dart <path-to-caf-file>
void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run test/dump_caf.dart <path-to-caf-file>');
    return;
  }

  final bytes = File(args[0]).readAsBytesSync();
  print('File: ${args[0]}');
  print('Size: ${bytes.length} bytes\n');

  final fileType = String.fromCharCodes(bytes.sublist(0, 4));
  final fileVersion = ByteData.sublistView(bytes, 4, 6).getUint16(0);
  final fileFlags = ByteData.sublistView(bytes, 6, 8).getUint16(0);
  print('CAF Header: "$fileType" v$fileVersion flags=$fileFlags\n');

  int offset = 8;
  int chunkNum = 0;
  while (offset + 12 <= bytes.length) {
    final chunkType = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = ByteData.sublistView(bytes, offset + 4, offset + 12).getInt64(0);
    print('Chunk $chunkNum: "$chunkType" size=$chunkSize (offset $offset)');

    if (chunkType == 'kuki') {
      final data = bytes.sublist(offset + 12, offset + 12 + chunkSize);
      print('  kuki data (${data.length} bytes):');
      _hexdump(data, '  ');
      if (data.length >= 8) {
        final sig = String.fromCharCodes(data.sublist(0, 8));
        print('  First 8 bytes: "$sig" ${sig == 'OpusHead' ? '✅ matches OpusHead' : '❌ NOT OpusHead'}');
      }
    }

    if (chunkType == 'desc') {
      final data = bytes.sublist(offset + 12, offset + 12 + chunkSize);
      final sr = ByteData.sublistView(data, 0, 8).getFloat64(0);
      final fmt = String.fromCharCodes(data.sublist(8, 12));
      final fpp = ByteData.sublistView(data, 20, 24).getUint32(0);
      final ch = ByteData.sublistView(data, 24, 28).getUint32(0);
      print('  desc: sr=$sr fmt="$fmt" framesPerPacket=$fpp channels=$ch');
    }

    offset += 12 + chunkSize;
    chunkNum++;
  }
}

void _hexdump(Uint8List data, String indent) {
  for (var i = 0; i < data.length; i += 16) {
    final end = (i + 16 > data.length) ? data.length : i + 16;
    final hex = data.sublist(i, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final ascii = data.sublist(i, end).map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.').join('');
    print('$indent${i.toString().padLeft(4, '0')}: $hex  $ascii');
  }
}
