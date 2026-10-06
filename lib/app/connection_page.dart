import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';

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
    url.text = values[0] ?? '';
    key.text = values[1] ?? '';
    store.text = values[2] ?? '';
    setState(() {});
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
              'O administrador configura a loja e informa o código de ativação. O setor vem desse código e fica fixo. Ative uma vez com internet; depois, abra diretamente os lançamentos, inclusive offline.',
            ),
            if (widget.state.verified)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Conta sem setor autorizado. Peça ao administrador para vincular a conta a Horti Fruti, Cozinha ou Padaria.',
                ),
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
