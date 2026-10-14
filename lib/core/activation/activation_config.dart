import 'dart:convert';

class ConnectionConfig {
  final String url, publicKey, store;
  const ConnectionConfig(this.url, this.publicKey, this.store);
  void validate() {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException(
        'Informe a URL HTTPS do projeto, sem caminhos.',
      );
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(store.trim())) {
      throw const FormatException('Informe o UUID da loja.');
    }
    if (publicKey.trim().isEmpty || publicKey.trim().startsWith('sb_secret_')) {
      throw const FormatException('Use somente a chave pública do Supabase.');
    }
    if (publicKey.split('.').length == 3) {
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(publicKey.split('.')[1])),
        ),
      );
      if (payload is! Map || payload['role'] != 'anon') {
        throw const FormatException(
          'Use a chave pública anon, nunca service_role.',
        );
      }
    }
  }
}

class ConnectionDefaults {
  static const url = String.fromEnvironment('DEFAULT_SUPABASE_URL');
  static const publicKey = String.fromEnvironment(
    'DEFAULT_SUPABASE_PUBLIC_KEY',
  );
  static const store = String.fromEnvironment('DEFAULT_STORE_ID');
}

class ActivationConfig {
  final ConnectionConfig connection;
  final String code, slot;
  const ActivationConfig(this.connection, this.code, this.slot);
  void validate() {
    connection.validate();
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(code) ||
        !['admin', 'hortifruti', 'cozinha', 'padaria'].contains(slot)) {
      throw const FormatException('Código de ativação ou setor inválido.');
    }
  }

  String encode() {
    validate();
    final text = jsonEncode({
      'type': 'consumo-interno-activation',
      'v': 1,
      'url': connection.url.trim().replaceFirst(RegExp(r'/$'), ''),
      'key': connection.publicKey.trim(),
      'store': connection.store.trim(),
      'code': code,
      'slot': slot,
    });
    if (utf8.encode(text).length > 2000) {
      throw const FormatException(
        'Dados de conexão grandes demais para o QR Code.',
      );
    }
    return text;
  }

  factory ActivationConfig.decode(String text) {
    if (utf8.encode(text).length > 2000) {
      throw const FormatException('QR Code inválido.');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data['type'] != 'consumo-interno-activation' ||
        data['v'] != 1 ||
        [
          'url',
          'key',
          'store',
          'code',
          'slot',
        ].any((key) => data[key] is! String)) {
      throw const FormatException(
        'Este QR Code não pertence ao Consumo Interno.',
      );
    }
    final result = ActivationConfig(
      ConnectionConfig(data['url'], data['key'], data['store']),
      data['code'],
      data['slot'],
    );
    result.validate();
    return result;
  }
}
