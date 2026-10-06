import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// PBKDF2-HMAC-SHA256; CPU work is isolated from the interface.
String deriveAdminPassword(Map<String, String> data) {
  final hmac = Hmac(sha256, utf8.encode(data['password']!));
  var block = hmac.convert([...base64Decode(data['salt']!), 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var iteration = 1; iteration < 120000; iteration++) {
    block = hmac.convert(block).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return base64Encode(result);
}

class AdminGuard {
  final FlutterSecureStorage storage;
  bool unlocked = false;
  int failures = 0;
  DateTime? retryAfter;
  String? _binding;
  String? _record;
  String? _activation;
  AdminGuard({this.storage = const FlutterSecureStorage()});
  String get _key => 'admin_guard_${sha256.convert(utf8.encode(_binding!))}';
  bool get configured => _record != null;
  Future<void> load(String binding) async {
    if (_binding == binding) return;
    _binding = binding;
    unlocked = false;
    _record = await storage.read(key: _key);
    _activation = _record == null
        ? null
        : (jsonDecode(_record!) as Map)['activation'] as String?;
  }

  Future<void> resetAfterActivation(String activationHash) async {
    _activation = activationHash;
    // A replay of the already used code cannot erase an established password.
    if (_record != null &&
        (jsonDecode(_record!) as Map)['activation'] == activationHash) {
      return;
    }
    await storage.delete(key: _key);
    _record = null;
    unlocked = false;
  }

  Future<void> create(String password) async {
    if (_binding == null) throw StateError('Ative o aparelho primeiro.');
    if (configured && !unlocked) {
      throw StateError('Desbloqueie antes de alterar a senha.');
    }
    if (password.length < 8 || password.length > 128) {
      throw const FormatException('Use uma senha de 8 a 128 caracteres.');
    }
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    final hash = await compute(deriveAdminPassword, {
      'password': password,
      'salt': salt,
    });
    final record = jsonEncode({
      'salt': salt,
      'hash': hash,
      'iterations': 120000,
      'activation': _activation,
    });
    await storage.write(key: _key, value: record);
    _record = record;
    unlocked = true;
    failures = 0;
    retryAfter = null;
  }

  Future<void> unlock(String password) async {
    if (!configured) throw StateError('Defina a senha administrativa.');
    if (password.length > 128) {
      throw StateError('Senha administrativa incorreta.');
    }
    if (retryAfter != null && DateTime.now().isBefore(retryAfter!)) {
      throw StateError('Aguarde antes de tentar novamente.');
    }
    final record = jsonDecode(_record!) as Map<String, dynamic>;
    final actual = base64Decode(
      await compute(deriveAdminPassword, {
        'password': password,
        'salt': record['salt'] as String,
      }),
    );
    final expected = base64Decode(record['hash'] as String);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    if (difference != 0) {
      failures++;
      if (failures >= 5) {
        retryAfter = DateTime.now().add(const Duration(seconds: 30));
      }
      throw StateError('Senha administrativa incorreta.');
    }
    unlocked = true;
    failures = 0;
    retryAfter = null;
  }

  void lock() => unlocked = false;
}
