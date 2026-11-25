import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

abstract interface class LabelTextRecognizer {
  Future<String?> recognize(Uint8List imageBytes);
}

class NoLabelTextRecognizer implements LabelTextRecognizer {
  @override
  Future<String?> recognize(Uint8List imageBytes) async => null;
}

LabelTextRecognizer createLabelTextRecognizer() => Platform.isAndroid
    ? GoogleMlKitLabelTextRecognizer()
    : NoLabelTextRecognizer();

class GoogleMlKitLabelTextRecognizer implements LabelTextRecognizer {
  @override
  Future<String?> recognize(Uint8List imageBytes) async {
    if (!Platform.isAndroid) return null;
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null ||
        decoded.width <= 0 ||
        decoded.height <= 0 ||
        decoded.width * decoded.height > 8000000) {
      throw const FormatException(
        'Não foi possível processar a imagem da etiqueta.',
      );
    }
    final input = InputImage.fromBitmap(
      bitmap: decoded.getBytes(order: img.ChannelOrder.rgba),
      width: decoded.width,
      height: decoded.height,
    );
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(input);
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}
