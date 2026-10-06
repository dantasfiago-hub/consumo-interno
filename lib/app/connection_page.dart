import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/activation/activation_config.dart';
import '../core/activation/qr_image_decoder.dart';
import '../core/access/sectors.dart';
import '../features/activation/presentation/activation_qr_page.dart';

/// First provisioning only. No local administrator fallback is offered.
class ConnectionPage extends StatefulWidget {
  final AppState state;
  const ConnectionPage({super.key, required this.state});
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final url = TextEditingController(),
      key = TextEditingController(),
      store = TextEditingController(),
      password = TextEditingController();
  bool busy = false, restoreBackup = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait(
      ['cloud_url', 'cloud_key', 'store'].map(widget.state.db.setting),
    );
    if (!mounted) return;
    url.text = values[0] ?? ConnectionDefaults.url;
    key.text = values[1] ?? ConnectionDefaults.publicKey;
    store.text = values[2] ?? ConnectionDefaults.store;
    setState(() {});
  }

  Future<void> _readQr(Future<String?> Function() read) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final raw = await read();
      if (raw == null || !mounted) return;
      final data = ActivationConfig.decode(raw);
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Usar esta ativação?'),
          content: Text(
            'Projeto: ${Uri.parse(data.connection.url).host}\nLoja: ${data.connection.store}\nAcesso: ${data.slot == 'admin' ? 'Administração' : sectorLabel(data.slot)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Preencher'),
            ),
          ],
        ),
      );
      if (yes == true && mounted) {
        url.text = data.connection.url;
        key.text = data.connection.publicKey;
        store.text = data.connection.store;
        password.text = data.code;
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Não foi possível ler a ativação: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _readQrFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > 15 * 1024 * 1024) {
      throw const FormatException('Imagem acima de 15 MB.');
    }
    return compute(
      decodeActivationQrImage,
      file.bytes ?? await File(file.path!).readAsBytes(),
    );
  }

  @override
  void dispose() {
    for (final c in [url, key, store, password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Configuração do aparelho')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            const Text(
              'Leia o QR Code ou informe o código fornecido pelo administrador. A conexão padrão pode ser alterada abaixo. O setor é autorizado pelo código. A ativação exige internet; os lançamentos funcionam offline.',
            ),
            if (widget.state.verified)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Conta sem setor autorizado. Peça ao administrador para vincular a conta a Horti Fruti, Cozinha ou Padaria.',
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (Platform.isAndroid)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _readQr(
                            () => Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ActivationQrPage(),
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Ler QR Code'),
                  ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _readQr(_readQrFile),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Abrir imagem do QR Code'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _readQr(
                          () async =>
                              (await Clipboard.getData(Clipboard.kTextPlain))
                                  ?.text,
                        ),
                  child: const Text('Colar ativação'),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Configuração inicial da loja'),
              children: [
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'URL do projeto',
                  ),
                ),
                TextField(
                  controller: key,
                  decoration: const InputDecoration(labelText: 'Chave pública'),
                ),
                TextField(
                  controller: store,
                  decoration: const InputDecoration(
                    labelText: 'ID da loja (UUID)',
                  ),
                ),
              ],
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Código de ativação',
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: restoreBackup,
              onChanged: busy
                  ? null
                  : (value) => setState(() => restoreBackup = value ?? false),
              title: const Text('Restaurar backup no primeiro acesso'),
              subtitle: const Text(
                'Exclusivo do administrador, em instalação sem registros. A conta será validada antes de abrir o arquivo.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (error.isNotEmpty)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        await widget.state.activateDevice(
                          url.text,
                          key.text,
                          store.text,
                          password.text,
                          restoreBackup: restoreBackup
                              ? () async {
                                  final selected = await FilePicker.platform
                                      .pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: ['json'],
                                        withData: true,
                                      );
                                  if (selected == null) return null;
                                  final file = selected.files.single;
                                  return utf8.decode(
                                    file.bytes ??
                                        await File(file.path!).readAsBytes(),
                                  );
                                }
                              : null,
                        );
                        if (mounted) {
                          password.clear();
                          if (context.mounted && Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                        }
                      } catch (e) {
                        if (mounted) setState(() => error = '$e');
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'Ativando...' : 'Ativar aparelho'),
            ),
          ],
        ),
      ),
    ),
  );
}
