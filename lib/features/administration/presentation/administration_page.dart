import 'package:flutter/foundation.dart';
import '../../../core/activation/qr_image_decoder.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';

import '../../../core/activation/activation_config.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../../../core/access/sectors.dart';
import '../../../core/types/json.dart';
import '../../../core/widgets/common.dart';
import '../../../core/files/file_service.dart';

class AdministrationPage extends StatefulWidget {
  final AppState state;
  const AdministrationPage({super.key, required this.state});
  @override
  State<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends State<AdministrationPage> {
  bool busy = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    widget.state.admin
        .cached()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {});
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.state.runAdministration(action);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (!s.canManage) {
      return const Center(child: Text('Acesso administrativo obrigatório.'));
    }
    final c = s.admin;
    return DefaultTabController(
      length: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTitle(
              'Administração',
              'Aparelhos, pendências, auditoria e recuperação.',
              action: OutlinedButton.icon(
                onPressed: busy ? null : () => run(c.refresh),
                icon: const Icon(Icons.sync),
                label: const Text('Atualizar'),
              ),
            ),
            if (error.isNotEmpty)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (busy) const LinearProgressIndicator(),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Aparelhos'),
                Tab(text: 'Pendências'),
                Tab(text: 'Auditoria'),
                Tab(text: 'Backups'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Gere um código para cada máquina do setor. Os aparelhos compartilham os dados após sincronizar. Para substituir uma máquina, revogue somente o acesso dela abaixo e gere outro código.',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: busy ? null : provision,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Gerar código de ativação'),
                      ),
                      for (final m in c.members)
                        Card(
                          child: ListTile(
                            title: Text(
                              m['role'] == 'admin'
                                  ? 'Aparelho administrativo'
                                  : sectorLabel(m['sector'] ?? ''),
                            ),
                            subtitle: Text(
                              '${m['role'] == 'admin' ? 'Administrador' : sectorLabel(m['sector'] ?? '')}\n${m['user_id']}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: 'Editar acesso',
                              onPressed: busy ? null : () => member(m),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                        ),
                    ],
                  ),
                  ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Nenhum registro é descartado automaticamente. A decisão será aplicada no aparelho de origem quando ele sincronizar.',
                        ),
                      ),
                      if (c.issues.isEmpty)
                        const ListTile(
                          title: Text('Nenhuma pendência recebida'),
                        ),
                      for (final issue in c.issues)
                        Card(
                          child: ExpansionTile(
                            title: Text(
                              '${sectorLabel(issue['sector'] ?? '')} · ${issue['status']}',
                            ),
                            subtitle: Text(issue['error']),
                            children: [
                              ListTile(
                                title: Text('Conta: ${issue['actor']}'),
                                subtitle: Text(
                                  'Aparelho: ${issue['device_id']}\nOperação: ${issue['operation_id']}',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  const JsonEncoder.withIndent(
                                    '  ',
                                  ).convert(issue['snapshot']),
                                ),
                              ),
                              if (![
                                'accept_remote',
                                'applied',
                              ].contains(issue['status']))
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final decision in {
                                      'retry': 'Tentar novamente',
                                      'accept_remote': 'Manter versão da nuvem',
                                      'apply_local': 'Aplicar consumo pendente',
                                    }.entries)
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => review(issue, decision.key),
                                        child: Text(decision.value),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Column(
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: c.sector,
                              decoration: const InputDecoration(
                                labelText: 'Setor da auditoria',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('Todos os setores'),
                                ),
                                ...sectors.entries.map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => c.sector = v!),
                            ),
                          ),
                          SizedBox(
                            width: 240,
                            child: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Ação (opcional)',
                              ),
                              onChanged: (v) => c.action = v.trim(),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : () => run(c.refresh),
                            child: const Text('Filtrar'),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: c.audit.length + 1,
                          itemBuilder: (context, i) {
                            if (i == c.audit.length) {
                              return TextButton(
                                onPressed: busy || c.audit.isEmpty
                                    ? null
                                    : () => run(c.olderAudit),
                                child: const Text(
                                  'Carregar registros anteriores',
                                ),
                              );
                            }
                            final a = c.audit[i];
                            return Card(
                              child: ExpansionTile(
                                title: Text(a['action']),
                                subtitle: Text(
                                  '${a['occurred_at']} · ${sectorLabel(a['sector'] ?? '')}',
                                ),
                                children: [
                                  ListTile(
                                    title: Text(
                                      'Identidade técnica: ${a['actor'] ?? 'Registro legado'}',
                                    ),
                                    subtitle: Text(
                                      'Aparelho: ${a['device_id'] ?? 'Servidor'}',
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: SelectableText(
                                      const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(a['detail']),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'São mantidas até 7 cópias por conta/aparelho na nuvem. O aparelho também mantém 14 cópias locais. A recuperação automática só usa backups da conta autenticada.',
                        ),
                      ),
                      if (c.backups.isEmpty)
                        const ListTile(
                          title: Text('Nenhum backup sincronizado'),
                        ),
                      for (final b in c.backups)
                        Card(
                          child: ListTile(
                            title: Text(b['created_at']),
                            subtitle: Text(
                              'Conta: ${b['actor']}\nAparelho: ${b['device_id']}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: 'Salvar backup',
                              onPressed: busy
                                  ? null
                                  : () => run(() async {
                                      final text = await s.cloud
                                          .downloadDeviceBackup(
                                            b['actor'],
                                            b['device_id'],
                                            b['hash'],
                                          );
                                      await saveBytes(
                                        'backup_${b['device_id']}.json',
                                        utf8.encode(text),
                                      );
                                    }),
                              icon: const Icon(Icons.download_outlined),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> review(Json issue, String decision) async {
    final reason = await reasonDialog(context);
    if (reason != null && mounted) {
      await run(
        () =>
            widget.state.admin.review(issue['operation_id'], decision, reason),
      );
    }
  }

  Future<void> provision() async {
    String selectedSector = 'cozinha';
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Ativar aparelho do setor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedSector,
                  decoration: const InputDecoration(labelText: 'Setor'),
                  items: {'admin': 'Administração', ...sectors}.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => set(() => selectedSector = value!),
                ),
                TextField(
                  controller: reason,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Justificativa'),
                ),
                const Text(
                  'Este código adiciona uma máquina sem desconectar as existentes.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Gerar código'),
            ),
          ],
        ),
      ),
    );
    final justification = reason.text.trim();
    reason.dispose();
    if (yes != true || !mounted) return;
    Json? result;
    await run(() async {
      result = await widget.state.cloud.provisionSector(
        selectedSector,
        false,
        justification,
      );
    });
    if (result == null || !mounted || !widget.state.canManage) return;
    final activation = ActivationConfig(
      ConnectionConfig(
        (await widget.state.db.setting('cloud_url'))!,
        (await widget.state.db.setting('cloud_key'))!,
        (await widget.state.db.setting('store'))!,
      ),
      result!['code'],
      selectedSector,
    ).encode();
    if (!mounted || !widget.state.canManage) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Ativação: ${selectedSector == 'admin' ? 'Administração' : sectorLabel(selectedSector)}',
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: activation,
                  size: 320,
                  backgroundColor: Colors.white,
                ),
                SelectableText(
                  'Código: ${result!['code']}\nValidade: 24 horas. Uso único. O QR Code inclui a configuração da loja.',
                ),
                const Text(
                  'Compartilhe apenas com o responsável pelo aparelho autorizado.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: activation));
            },
            child: const Text('Copiar ativação'),
          ),
          TextButton(
            onPressed: () => guarded(context, () async {
              final bytes = await compute(encodeActivationQrImage, activation);
              await saveBytes('ativacao_$selectedSector.png', bytes);
            }),
            child: const Text('Salvar QR Code'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> member([Json? existing]) async {
    final user = TextEditingController(text: existing?['user_id'] ?? '');
    String role = existing?['role'] ?? 'operator';
    String sector = existing?['sector'] ?? 'cozinha';
    bool active = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(existing == null ? 'Vincular conta' : 'Editar acesso'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: user,
                  enabled: existing == null,
                  decoration: const InputDecoration(
                    labelText: 'UUID da conta existente',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Papel'),
                  items: const [
                    DropdownMenuItem(
                      value: 'operator',
                      child: Text('Aparelho do setor'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrador'),
                    ),
                  ],
                  onChanged: (v) => set(() => role = v!),
                ),
                if (role == 'operator')
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: sector,
                    decoration: const InputDecoration(labelText: 'Setor'),
                    items: sectors.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => set(() => sector = v!),
                  ),
                SwitchListTile(
                  value: active,
                  onChanged: (v) => set(() => active = v),
                  title: const Text('Acesso ativo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    final id = user.text.trim();
    user.dispose();
    if (yes == true && mounted) {
      await run(
        () => widget.state.admin.member(
          id,
          role,
          role == 'operator' ? sector : null,
          active,
        ),
      );
    }
  }
}
