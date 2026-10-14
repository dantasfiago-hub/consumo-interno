import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ActivationQrPage extends StatefulWidget {
  const ActivationQrPage({super.key});
  @override
  State<ActivationQrPage> createState() => _ActivationQrPageState();
}

class _ActivationQrPageState extends State<ActivationQrPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool handled = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ler QR Code de ativação')),
    body: !Platform.isAndroid
        ? const Center(
            child: Text('Neste aparelho, use Abrir imagem do QR Code.'),
          )
        : MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (handled || !mounted) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null) {
                  handled = true;
                  Navigator.pop(context, value);
                  break;
                }
              }
            },
            errorBuilder: (context, error) => const Center(
              child: Text(
                'Não foi possível acessar a câmera. Verifique a permissão ou abra uma imagem do QR Code.',
              ),
            ),
          ),
  );
}
