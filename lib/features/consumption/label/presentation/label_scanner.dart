import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class LabelCameraCapture {
  final String barcode;
  final Uint8List? image;

  const LabelCameraCapture({required this.barcode, this.image});
}

abstract interface class LabelScanner {
  Future<LabelCameraCapture?> scan(BuildContext context);
}

class NoLabelScanner implements LabelScanner {
  @override
  Future<LabelCameraCapture?> scan(BuildContext context) async {
    throw const FormatException(
      'A câmera está disponível somente no Android. Digite o código da etiqueta.',
    );
  }
}

class MobileLabelScanner implements LabelScanner {
  @override
  Future<LabelCameraCapture?> scan(BuildContext context) {
    if (!Platform.isAndroid) return NoLabelScanner().scan(context);
    return showDialog<LabelCameraCapture>(
      context: context,
      builder: (_) => const _LabelCameraDialog(),
    );
  }
}

class _LabelCameraDialog extends StatefulWidget {
  const _LabelCameraDialog();

  @override
  State<_LabelCameraDialog> createState() => _LabelCameraDialogState();
}

class _LabelCameraDialogState extends State<_LabelCameraDialog> {
  final controller = MobileScannerController(
    formats: [BarcodeFormat.ean13],
    returnImage: true,
  );
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ler etiqueta de balança'),
    content: SizedBox(
      width: 520,
      height: 360,
      child: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (handled || !mounted) return;
          final barcode = capture.barcodes
              .map((item) => item.rawValue)
              .whereType<String>()
              .firstOrNull;
          if (barcode == null) return;
          handled = true;
          Navigator.pop(
            context,
            LabelCameraCapture(barcode: barcode, image: capture.image),
          );
        },
        errorBuilder: (context, _) => const Center(
          child: Text(
            'Não foi possível acessar a câmera. Verifique a permissão e tente novamente.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
    ],
  );
}
