import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:consumo_interno/features/products/data/photo_service.dart';

void main() {
  test('WebP estático com zero quadros de animação é aceito', () {
    final bytes = base64Decode(
      File('test/fixtures/static_product.webp.b64').readAsStringSync().trim(),
    );
    final info = img.WebPDecoder().startDecode(bytes)!;
    expect(info.hasAnimation, isFalse);
    expect(info.numFrames, 0);
    final photo = img.decodeJpg(base64Decode(optimizePhoto(bytes)))!;
    expect(photo.width, 194);
    expect(photo.height, 259);
  });

  test('Foto pequena preserva proporção sem ampliação artificial', () {
    final input = img.encodePng(img.Image(width: 2, height: 3));
    final photo = img.decodeJpg(base64Decode(optimizePhoto(input)))!;
    expect(photo.width, 2);
    expect(photo.height, 3);
  });
  test(
    'Arquivo inválido ou com pixels excessivos é recusado antes de decodificar',
    () {
      expect(
        () => optimizePhoto(Uint8List.fromList([0, 1, 2])),
        throwsFormatException,
      );
      // A valid BMP header with extreme dimensions must be refused before pixel allocation.
      final data = ByteData(54);
      data.setUint8(0, 66);
      data.setUint8(1, 77);
      data.setUint32(2, 54, Endian.little);
      data.setUint32(10, 54, Endian.little);
      data.setUint32(14, 40, Endian.little);
      data.setInt32(18, 100000, Endian.little);
      data.setInt32(22, 100000, Endian.little);
      data.setUint16(26, 1, Endian.little);
      data.setUint16(28, 24, Endian.little);
      expect(
        () => optimizePhoto(data.buffer.asUint8List()),
        throwsFormatException,
      );
    },
  );
}
