import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../../../core/files/file_service.dart';
import '../../../core/widgets/common.dart';
import 'appearance_card.dart';
import '../../exports/presentation/profile_card.dart';

class SettingsPage extends StatefulWidget {
  final AppState state;
  const SettingsPage({super.key, required this.state});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final url = TextEditingController(),
      key = TextEditingController(),
      store = TextEditingController(),
      password = TextEditingController();
  bool busy = false;
  String feedback = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = widget.state.db;
    final values = await Future.wait([
      d.setting('cloud_url'),
      d.setting('cloud_key'),
      d.setting('store'),
    ]);
    if (mounted) {
      url.text = values[0] ?? '';
      key.text = values[1] ?? '';
      store.text = values[2] ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [url, key, store, password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.state.canManage
      ? const Center(child: Text('Acesso exclusivo do administrador.'))
      : SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageTitle(
                'Configurações',
                'Aparência, nuvem e cópias de segurança.',
              ),
              AppearanceCard(controller: widget.state.appearance),
              const SizedBox(height: 16),
              ExportProfileCard(state: widget.state),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conectar à nuvem',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Informe os dados fornecidos pelo responsável pela instalação e entre na conta desta loja. Os lançamentos continuam disponíveis sem internet.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: url,
                        decoration: const InputDecoration(
                          labelText: 'URL do projeto',
                          hintText: 'https://seu-projeto.supabase.co',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: key,
                        decoration: const InputDecoration(
                          labelText: 'Chave pública',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: store,
                        decoration: const InputDecoration(
                          labelText: 'ID da loja (UUID)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Código de ativação',
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: busy || widget.state.syncing
                                ? null
                                : () => _run(() async {
                                    await widget.state.activateDevice(
                                      url.text,
                                      key.text,
                                      store.text,
                                      password.text,
                                    );
                                    if (mounted) password.clear();
                                  }, 'Aparelho ativado e sincronizado.'),
                            icon: Icon(Icons.cloud_outlined),
                            label: Text('Conectar e sincronizar'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                busy ||
                                    widget.state.syncing ||
                                    !widget.state.cloudConfigured
                                ? null
                                : () => _run(() async {
                                    await widget.state.sync();
                                    if (widget.state.syncError.isNotEmpty) {
                                      throw StateError(widget.state.syncError);
                                    }
                                  }, 'Sincronização concluída.'),
                            icon: Icon(Icons.sync),
                            label: Text('Sincronizar agora'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : widget.state.lockAdministration,
                            child: const Text('Bloquear administração'),
                          ),
                        ],
                      ),
                      if (busy)
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: LinearProgressIndicator(),
                        ),
                      if (feedback.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SelectableText(feedback),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup e recuperação',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Inclui produtos, fotos, consumos, lotes, perfil, favoritos e operações pendentes. Não inclui senhas. Guarde o arquivo em um local protegido. A restauração exige uma instalação sem registros.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Backup automático: 14 cópias locais, criadas após alterações e diariamente enquanto o app está aberto. Até 7 cópias por aparelho na nuvem após sincronizar.',
                      ),
                      FutureBuilder<List<String?>>(
                        future: Future.wait(
                          [
                            'backup_last',
                            'backup_error',
                            'cloud_backup_last',
                            'cloud_backup_error',
                            'backup_directory',
                          ].map(widget.state.db.setting),
                        ),
                        builder: (context, snapshot) {
                          final values = snapshot.data;
                          if (values == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Último local: ${values[0] ?? 'Ainda não criado'}',
                              ),
                              Text(
                                'Último na nuvem: ${values[2] ?? 'Ainda não enviado'}',
                              ),
                              if ((values[1] ?? '').isNotEmpty)
                                Text(values[1]!),
                              if ((values[3] ?? '').isNotEmpty)
                                Text(values[3]!),
                              Text(
                                'Pasta adicional/configurada: ${values[4] ?? 'Pasta privada do aplicativo'}',
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,

                        children: [
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _run(() async {
                                    await widget.state.backups.snapshot(
                                      force: true,
                                    );
                                    await widget.state.load();
                                    if (widget.state.backups.error.isNotEmpty) {
                                      throw StateError(
                                        widget.state.backups.error,
                                      );
                                    }
                                  }, 'Backup automático criado.'),
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('Criar cópia agora'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _run(() async {
                                    final dir = await FilePicker.platform
                                        .getDirectoryPath(
                                          dialogTitle:
                                              'Pasta de backups automáticos',
                                        );
                                    if (dir == null) return;
                                    await widget.state.db.setSetting(
                                      'backup_directory',
                                      dir,
                                    );
                                    await widget.state.backups.snapshot(
                                      force: true,
                                    );
                                    if (widget.state.backups.error.isNotEmpty) {
                                      throw StateError(
                                        widget.state.backups.error,
                                      );
                                    }
                                  }, 'Pasta de backup configurada.'),
                            icon: const Icon(Icons.folder_outlined),
                            label: const Text('Escolher pasta'),
                          ),

                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _run(() async {
                                    final data = await widget.state.db.backup();
                                    await saveBytes(
                                      'backup_consumo_${DateTime.now().millisecondsSinceEpoch}.json',
                                      utf8.encode(data),
                                    );
                                  }, 'Operação de backup finalizada.'),
                            icon: Icon(Icons.download_outlined),
                            label: Text('Exportar backup'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _run(() async {
                                    final result = await FilePicker.platform
                                        .pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: ['json'],
                                          withData: true,
                                        );
                                    if (result == null) return;
                                    final file = result.files.single;
                                    final bytes =
                                        file.bytes ??
                                        await File(file.path!).readAsBytes();
                                    await widget.state.db.restore(
                                      utf8.decode(bytes),
                                    );
                                    await widget.state.appearance.load(
                                      force: true,
                                    );
                                    await widget.state.load();
                                  }, 'Operação de restauração finalizada.'),
                            icon: Icon(Icons.upload_outlined),
                            label: Text('Restaurar backup'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Fila de sincronização (${widget.state.pending.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Falhas são mantidas na fila. Conflitos não sobrescrevem dados da nuvem automaticamente.',
              ),
              for (final op in widget.state.pending)
                Card(
                  child: ListTile(
                    leading: Icon(
                      op['error'] == null
                          ? Icons.schedule
                          : Icons.error_outline,
                    ),
                    title: Text(
                      '${op['kind'] == 'product' ? 'Produto' : 'Consumo'} · ${op['entity_id']}',
                    ),
                    subtitle: Text(op['error'] ?? 'Aguardando envio'),
                    trailing: IconButton(
                      tooltip: 'Resolver com a versão da nuvem',
                      icon: Icon(Icons.rule),
                      onPressed:
                          busy ||
                              widget.state.syncing ||
                              !widget.state.cloudConfigured
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Usar a versão da nuvem?'),
                                  content: Text(
                                    'As alterações locais deste registro serão retiradas da fila e arquivadas no backup. O registro será substituído pela versão da nuvem, ou removido da lista se ainda não existir lá. Você poderá consultar o conteúdo arquivado no backup JSON.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text('Voltar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text('Arquivar e resolver'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                await _run(
                                  () async {
                                    await widget.state.resolveConflict(
                                      op['kind'],
                                      op['entity_id'],
                                    );
                                  },
                                  'Pendências locais arquivadas. Versão da nuvem aplicada.',
                                );
                              }
                            },
                    ),
                    isThreeLine: op['error'] != null,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Versão 1.6.1 · Consumo interno e exportação para outro aplicativo.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      busy = true;
      feedback = '';
    });
    try {
      await action();
      if (mounted) setState(() => feedback = success);
    } catch (e) {
      if (mounted) setState(() => feedback = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
