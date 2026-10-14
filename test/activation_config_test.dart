import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:consumo_interno/core/activation/activation_config.dart';
import 'package:consumo_interno/core/activation/qr_image_decoder.dart';

void main() {
  const connection = ConnectionConfig(
    'https://example.supabase.co',
    'sb_publishable_public',
    '11111111-1111-4111-8111-111111111111',
  );
  final activation = ActivationConfig(connection, 'A' * 32, 'cozinha');
  test('Ativação QR preserva dados públicos e setor', () {
    final read = ActivationConfig.decode(activation.encode());
    expect(read.connection.url, connection.url);
    expect(read.connection.publicKey, connection.publicKey);
    expect(read.connection.store, connection.store);
    expect(read.code, activation.code);
    expect(read.slot, 'cozinha');
  });
  test('Rejeita payload estranho, URL insegura e chave privilegiada', () {
    expect(() => ActivationConfig.decode('{}'), throwsFormatException);
    expect(
      () => ActivationConfig(
        ConnectionConfig(
          'http://example.com',
          connection.publicKey,
          connection.store,
        ),
        activation.code,
        'cozinha',
      ).encode(),
      throwsFormatException,
    );
    final token =
        'e30.${base64Url.encode(utf8.encode('{"role":"service_role"}'))}.signature';
    expect(
      () =>
          ConnectionConfig(connection.url, token, connection.store).validate(),
      throwsFormatException,
    );
    expect(
      () => ConnectionConfig(
        connection.url,
        'sb_secret_private',
        connection.store,
      ).validate(),
      throwsFormatException,
    );
  });
  test('Lê QR gerado, inclusive rotacionado, sem ampliar fotos', () {
    final qr = QrCode.fromData(
      data: activation.encode(),
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final matrix = QrImage(qr);
    const scale = 8, border = 4;
    final size = (matrix.moduleCount + border * 2) * scale;
    final image = img.Image(width: size, height: size);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.moduleCount; y++) {
      for (var x = 0; x < matrix.moduleCount; x++) {
        if (!matrix.isDark(y, x)) continue;
        img.fillRect(
          image,
          x1: (x + border) * scale,
          y1: (y + border) * scale,
          x2: (x + border + 1) * scale - 1,
          y2: (y + border + 1) * scale - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
    expect(decodeActivationQrImage(img.encodePng(image)), activation.encode());
    expect(
      decodeActivationQrImage(img.encodePng(img.copyRotate(image, angle: 90))),
      activation.encode(),
    );
    expect(
      () => decodeActivationQrImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
