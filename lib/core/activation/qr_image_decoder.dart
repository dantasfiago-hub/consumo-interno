import 'package:qr/qr.dart';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

String decodeActivationQrImage(Uint8List bytes) {
  try {
    return _decodeActivationQrImage(bytes);
  } on RangeError {
    throw const FormatException('Imagem truncada ou inválida.');
  }
}

String _decodeActivationQrImage(Uint8List bytes) {
  if (bytes.length > 15 * 1024 * 1024) {
    throw const FormatException('Imagem acima de 15 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 8000000) {
    throw const FormatException(
      'Use uma imagem do QR Code com até 8 milhões de pixels.',
    );
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Imagem inválida.');
  var image = img.bakeOrientation(decoded);
  for (var turn = 0; turn < 4; turn++) {
    final pixels = Int32List(image.width * image.height);
    for (final p in image) {
      pixels[p.y * image.width + p.x] =
          (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();
    }
    try {
      return QRCodeReader()
          .decode(
            BinaryBitmap(
              HybridBinarizer(
                RGBLuminanceSource(image.width, image.height, pixels),
              ),
            ),
          )
          .text;
    } on ReaderException {
      image = img.copyRotate(image, angle: 90);
    }
  }
  throw const FormatException('Nenhum QR Code legível encontrado na imagem.');
}

Uint8List encodeActivationQrImage(String text) {
  final matrix = QrImage(
    QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
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
  return img.encodePng(image);
}
