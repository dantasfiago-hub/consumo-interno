import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

Future<String?> choosePhoto() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
  );
  if (result == null) return null;
  final file = result.files.single;
  if (file.size > 15 * 1024 * 1024) {
    throw const FormatException('Escolha uma foto de até 15 MB.');
  }
  final bytes = file.bytes ?? await File(file.path!).readAsBytes();
  return compute(optimizePhoto, bytes);
}

/// Runs outside the UI isolate. Inspect dimensions before allocating pixel buffers.
String optimizePhoto(Uint8List bytes) {
  try {
    return _optimizePhoto(bytes);
  } on RangeError {
    throw const FormatException('Imagem truncada ou inválida.');
  }
}

String _optimizePhoto(Uint8List bytes) {
  if (bytes.length > 15 * 1024 * 1024) {
    throw const FormatException('Escolha uma foto de até 15 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const FormatException('Não foi possível ler esta imagem.');
  }
  if (info.width * info.height > 16000000) {
    throw const FormatException(
      'Escolha uma foto de até 16 milhões de pixels.',
    );
  }
  // image 4.5.4 reports zero animation frames for static WebP files.
  // Check the animation flag instead of rejecting those valid photos.
  final isAnimated = info is img.WebPInfo
      ? info.hasAnimation
      : info.numFrames != 1;
  if (isAnimated) {
    throw const FormatException('Escolha uma foto estática, sem animação.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Imagem inválida.');
  final baked = img.bakeOrientation(decoded);
  final resized = baked.width <= 384 && baked.height <= 384
      ? baked
      : img.copyResize(
          baked,
          width: baked.width >= baked.height ? 384 : null,
          height: baked.height > baked.width ? 384 : null,
        );
  var output = img.encodeJpg(resized, quality: 78);
  if (output.length > 130000) output = img.encodeJpg(resized, quality: 50);
  if (output.length > 130000) {
    throw const FormatException('Não foi possível reduzir esta imagem.');
  }
  return base64Encode(output);
}
