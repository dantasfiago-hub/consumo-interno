import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class _LimitedBytes extends ByteConversionSinkBase {
  final int limit;
  final builder = BytesBuilder(copy: false);
  int length = 0;
  _LimitedBytes(this.limit);
  @override
  void add(List<int> bytes) {
    length += bytes.length;
    if (length > limit) {
      throw const FormatException('Backup descomprimido acima de 64 MB.');
    }
    builder.add(bytes);
  }

  @override
  void close() {}
}

String decodeCompressedBackup(
  List<int> bytes, {
  int maxDecodedBytes = 64 * 1024 * 1024,
}) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Backup comprimido acima de 20 MB.');
  }
  final output = _LimitedBytes(maxDecodedBytes.clamp(1, 64 * 1024 * 1024));
  final input = zlib.decoder.startChunkedConversion(output);
  for (var i = 0; i < bytes.length; i += 4096) {
    input.add(bytes.sublist(i, (i + 4096).clamp(0, bytes.length)));
  }
  input.close();
  return utf8.decode(output.builder.takeBytes());
}
