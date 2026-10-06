import 'dart:convert';
import 'package:crypto/crypto.dart';

String verifyBackupEnvelope(String envelope) {
  final data = jsonDecode(envelope);
  if (data is Map && data['envelope_version'] == 1) {
    final text = data['backup'];
    if (text is! String ||
        sha256.convert(utf8.encode(text)).toString() != data['sha256']) {
      throw const FormatException(
        'Backup corrompido: a assinatura de integridade não confere.',
      );
    }
    return text;
  }
  return envelope;
}
