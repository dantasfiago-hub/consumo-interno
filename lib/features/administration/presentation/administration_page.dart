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
  String deviceSector = '';
  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      await widget.state.admin.cached();
      if (!mounted) return;
      setState(() {});
      if (widget.state.cloudConfigured && widget.state.canManage) {
        await run(widget.state.admin.refresh);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
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
    final deviceMembers = c.members
        .where(
          (m) =>
              deviceSector.isEmpty ||
              (deviceSector == 'admin'
                  ? m['role'] == 'admin'
                  : m['sector'] == deviceSector),
        )
        .toList();
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
                          'Consulte os aparelhos autorizados desta loja por setor. Excluir acesso remove somente o vínculo do aparelho, preservando produtos, consumos e backups. A revogação é feita na nuvem; um aparelho offline perceberá a mudança quando voltar a conectar.',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: busy ? null : provision,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Gerar código de ativação'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: deviceSector,
                        decoration: const InputDecoration(
                          labelText: 'Setor dos aparelhos',
                        ),
                        items:
                            {
                                  '': 'Todos os setores',
                                  'admin': 'Administração',
                                  ...sectors,
                                }.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) =>
                            setState(() => deviceSector = value!),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${deviceMembers.length} aparelho(s) autorizado(s) · ${c.members.length} no total',
                        ),
                      ),
                      if (deviceMembers.isEmpty)
                        const ListTile(
                          title: Text('Nenhum aparelho encontrado'),
                          subtitle: Text(
                            'Atualize a lista para consultar os vínculos na nuvem.',
                          ),
                        ),
                      for (final m in deviceMembers)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              m['role'] == 'admin'
                                  ? Icons.admin_panel_settings_outlined
                                  : Icons.devices_outlined,
                            ),
                            title: Text(
                              m['role'] == 'admin'
                                  ? 'Administração'
                                  : sectorLabel(m['sector'] ?? ''),
                            ),
                            subtitle: Text(
                              'Aparelho: ${m['device_id'] ?? 'Vínculo legado, sem identificador'}\n'
                              'Ativação: ${m['activated_at'] ?? 'Não informada'}\n'
                              'Identidade: ${m['user_id']}${m['user_id'] == s.cloud.userId ? '\nEste aparelho' : ''}',
                            ),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'Editar acesso',
                                  onPressed: busy ? null : () => member(m),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: m['user_id'] == s.cloud.userId
                                      ? 'Use Sair ou trocar de setor neste aparelho'
                                      : 'Excluir acesso do aparelho',
                                  onPressed:
                                      busy || m['user_id'] == s.cloud.userId
                                      ? null
                                      : () => removeDevice(m),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
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
                                  const JsonEncoder.withIndent('  ')
                                      .convert(issue['snapshot']),
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
                                      const JsonEncoder.withIndent('  ')
                                          .convert(a['detail']),
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
                          'São mantidas até 2 cópias por conta/aparelho na nuvem e até 4 cópias locais por vínculo. A recuperação automática só usa backups da conta autenticada.',
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

  Future<void> removeDevice(Json existing) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir acesso do aparelho?'),
        content: Text(
          'Setor: ${existing['role'] == 'admin' ? 'Administração' : sectorLabel(existing['sector'] ?? '')}\n'
          'Aparelho: ${existing['device_id'] ?? existing['user_id']}\n\n'
          'O aparelho perderá o acesso à nuvem. Produtos, consumos e backups serão preservados. '
          'Sincronize ou guarde um backup das pendências locais antes de remover. '
          'Para reconectar, gere um novo código de ativação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir acesso'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || !widget.state.canManage) return;
    await run(
      () => widget.state.admin.member(
        existing['user_id'],
        existing['role'],
        existing['sector'],
        false,
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
