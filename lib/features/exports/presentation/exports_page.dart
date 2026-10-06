import 'package:flutter/material.dart';
import '../../../core/access/sectors.dart';
import '../../../app/app_state.dart';
import '../../../domain/models.dart';
import '../../../core/files/file_service.dart';
import '../../../core/widgets/common.dart';
import '../domain/export.dart';
import '../application/prepare_export.dart';
import '../application/save_export_artifact.dart';

class ExportsPage extends StatefulWidget {
  final AppState state;
  const ExportsPage({super.key, required this.state});
  @override
  State<ExportsPage> createState() => _ExportsPageState();
}

class _ExportsPageState extends State<ExportsPage> {
  final filter = ReportFilter();
  String selectedSector = '';
  final excluded = <String>{};
  final errors = <String, String>{};
  bool busy = false;
  Json get filtersJson => {
    'from': filter.from?.toIso8601String(),
    'to': filter.to?.toIso8601String(),
    'query': filter.query,
    'sector': selectedSector,
    'operator': filter.operatorName,
    'unit': filter.unit,
    'min_cents': filter.minCents,
    'max_cents': filter.maxCents,
    'excluded_codes': excluded.toList()..sort(),
  };
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (!s.canManage) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Exportações e perfis são gerenciados pelo administrador. Consulte seus consumos em Histórico e Relatórios.',
        ),
      );
    }
    final eligible = eligibleExportRows(
      reportRows(
        s.consumptions.where((c) => c.sectorId == selectedSector).toList(),
        filter,
      ),
      s.batches,
    );
    List<ExportRow> grouped = [];
    String error = errors.values.join(' ');
    if (filter.minCents != null &&
        filter.maxCents != null &&
        filter.minCents! > filter.maxCents!) {
      error = 'O mínimo deve ser menor ou igual ao máximo.';
    }
    try {
      grouped = groupForExport(eligible);
    } catch (e) {
      error = '$e';
    }
    final selected = eligible
        .where((r) => !excluded.contains(r.item.code))
        .toList();
    final profile = s.exports.profile.forSector(selectedSector);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            'Exportações',
            'Agrupe os consumos por produto e acompanhe os arquivos do VR Master.',
          ),
          const Text(
            'Prévia dos dados locais. Confirme que os outros dispositivos sincronizaram antes de reservar. O lote definitivo exige conexão.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('export-sector'),
            initialValue: selectedSector,
            decoration: const InputDecoration(labelText: 'Setor do arquivo *'),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Selecione o setor'),
              ),
              ...sectors.entries.map(
                (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
              ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    selectedSector = v!;
                    excluded.clear();
                  }),
          ),
          const SizedBox(height: 12),
          if (selectedSector.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Disponíveis: ${eligible.length}')),
                Chip(
                  label: Text(
                    'Protegidos: ${reportRows(s.consumptions.where((c) => c.sectorId == selectedSector).toList(), ReportFilter()).length - eligibleExportRows(reportRows(s.consumptions.where((c) => c.sectorId == selectedSector).toList(), ReportFilter()), s.batches).length}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Pendentes: ${s.pending.where((op) => op['kind'] == 'consumption' && sectorKey(decodeObject(op['body'])['sector'] ?? '') == selectedSector).length}',
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              title: const Text('Filtros da exportação'),
              maintainState: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          filter.from == null
                              ? 'Selecionar período de exportação'
                              : '${filter.from!.toIso8601String().substring(0, 10)} a ${filter.to!.toIso8601String().substring(0, 10)}',
                        ),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDateRange: filter.from == null
                                ? null
                                : DateTimeRange(
                                    start: filter.from!,
                                    end: filter.to!,
                                  ),
                          );
                          if (range != null && mounted) {
                            setState(() {
                              filter.from = range.start;
                              filter.to = range.end;
                            });
                          }
                        },
                      ),
                      if (filter.from != null)
                        TextButton(
                          onPressed: () => setState(() {
                            filter.from = null;
                            filter.to = null;
                          }),
                          child: const Text('Todo o período'),
                        ),
                      _field(
                        'Produto para exportação',
                        (v) => filter.query = v,
                      ),

                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: filter.unit,
                          decoration: const InputDecoration(
                            labelText: 'Unidade de medida',
                          ),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('Todas')),
                            DropdownMenuItem(value: 'UN', child: Text('UN')),
                            DropdownMenuItem(value: 'KG', child: Text('KG')),
                          ],
                          onChanged: (v) => setState(() => filter.unit = v!),
                        ),
                      ),
                      _field(
                        'Total mínimo por item',
                        (v) => filter.minCents = v.trim().isEmpty
                            ? null
                            : parseScaled(v, 2, allowZero: true),
                      ),
                      _field(
                        'Total máximo por item',
                        (v) => filter.maxCents = v.trim().isEmpty
                            ? null
                            : parseScaled(v, 2, allowZero: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${selected.length} item(ns) disponível(is) selecionado(s) · ${grouped.where((r) => !excluded.contains(r.code)).length} produto(s) · Perfil v${profile.version}',
          ),
          Text(
            profile.quantityOnly
                ? 'Saída: somente código interno e quantidade acumulada. Peso em kg; UN/KG aparece somente para conferência.'
                : 'Saída: código interno, quantidade acumulada, unidade fixa 1 e valor unitário. UN/KG aparece somente para conferência.',
          ),
          if (!profile.validated)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Configure e confira o perfil em Configurações antes de reservar.',
              ),
            ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final r in grouped)
            Card(
              child: CheckboxListTile(
                value: !excluded.contains(r.code),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        if (v!) {
                          excluded.remove(r.code);
                        } else {
                          excluded.add(r.code);
                        }
                      }),
                title: Text('${r.code} · ${r.description}'),
                subtitle: Text(
                  profile.quantityOnly
                      ? '${scaledText(r.quantityMilli, 3)} ${r.measure}'
                      : '${scaledText(r.quantityMilli, 3)} ${r.measure} · Total R\$ ${scaledText(r.totalCents, 2, fixed: true)}\nValor unitário: ${scaledText(r.price4, 4, fixed: profile.fixedPrice)} · Unidade exportada: 1${r.difference7 == BigInt.zero ? '' : '\nDiferença por arredondamento: R\$ ${scaledText(r.difference7, 7)}'}',
                ),
              ),
            ),
          if (grouped.isEmpty && error.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Nenhum consumo disponível nestes filtros. Itens reservados ou cancelados não entram em outro lote.',
              ),
            ),
          FilledButton.icon(
            icon: const Icon(Icons.inventory_outlined),
            label: Text(busy ? 'Processando...' : 'Reservar lote selecionado'),
            onPressed:
                busy ||
                    s.syncing ||
                    !s.canManage ||
                    !s.cloudConfigured ||
                    !profile.validated ||
                    selected.isEmpty ||
                    selected.length > 2000 ||
                    error.isNotEmpty
                ? null
                : () => _reserve(selected),
          ),
          if (selected.length > 2000)
            const Text(
              'O lote aceita até 2000 itens. Reduza o período ou os filtros.',
            ),
          const SizedBox(height: 24),
          Text(
            'Histórico de exportações',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (s.exportReceipts.isNotEmpty)
            Text(
              '${s.exportReceipts.length} confirmação(ões) de arquivo salvo aguardando sincronização.',
            ),
          for (final batch in s.batches) _batchTile(batch),
        ],
      ),
    );
  }

  Widget _field(String label, void Function(String) update) => SizedBox(
    width: 220,
    child: TextField(
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => setState(() {
        try {
          update(v);
          errors.remove(label);
        } catch (e) {
          errors[label] = '$e';
        }
      }),
    ),
  );
  Widget _batchTile(Json b) {
    final modern = b['format_version'] == 2;
    final receipts = widget.state.exportReceipts.where(
      (r) => r['batch_id'] == b['id'],
    );
    return Card(
      child: ExpansionTile(
        title: Text(
          'Lote ${b['id'].toString().substring(0, 8)} · ${batchStatusLabel(b)}',
        ),
        subtitle: Text(
          '${sectorLabel(b['sector'] ?? 'Setor não definido (legado)')} · ${b['created_at'].toString().substring(0, 10)} · ${(b['rows'] as List).length} itens${modern ? ' · ${(b['grouped_rows'] as List).length} produtos' : ' · Histórico anterior'}',
        ),
        children: [
          if (!modern)
            const ListTile(
              title: Text(
                'Lote da versão anterior preservado. Não há confirmação de importação no VR Master.',
              ),
            ),
          if (b['reference'] != null)
            ListTile(title: Text('Referência histórica: ${b['reference']}')),
          if (modern)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Autor: ${b['created_by']} · Perfil v${b['profile']['version']}',
                  ),
                  if (receipts.isNotEmpty)
                    const Text(
                      'Arquivo salvo neste dispositivo; confirmação pendente na nuvem.',
                    ),
                  if (b['status'] == 'ready')
                    const Text(
                      'A gravação foi autorizada. Confira o destino; os itens seguem protegidos mesmo se a gravação for cancelada ou interrompida.',
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Salvar arquivo do lote'),
                        onPressed:
                            busy ||
                                !widget.state.canManage ||
                                b['status'] == 'cancelled'
                            ? null
                            : () => _run(() => _download(b)),
                      ),
                      if (b['status'] == 'downloaded')
                        TextButton(
                          onPressed: busy || widget.state.syncing
                              ? null
                              : () => _change(b, 'imported'),
                          child: const Text(
                            'Confirmar importação no VR Master',
                          ),
                        ),
                      if (b['status'] == 'prepared')
                        TextButton(
                          onPressed: busy || widget.state.syncing
                              ? null
                              : () => _change(b, 'cancelled'),
                          child: const Text('Cancelar reserva'),
                        ),
                    ],
                  ),
                  for (final e in b['events'] ?? [])
                    Text(
                      '${e['at'].toString().substring(0, 19)} · ${_eventLabel(e['action'])}${(e['reference'] ?? '').isEmpty ? '' : ' · ${e['reference']}'}',
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _eventLabel(dynamic action) => switch (action) {
    'reserved' => 'Reservado',
    'authorize_save' => 'Gravação autorizada',
    'saved' => 'Arquivo salvo',
    'imported' => 'Importação confirmada',
    'cancelled' => 'Cancelado',
    _ => '$action',
  };
  Future<void> _reserve(List<ReportRow> selection) async {
    if (busy) return;
    setState(() => busy = true);
    bool? yes;
    try {
      yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar exportação para o VR'),
          content: Text(
            'Setor: ${sectorLabel(selectedSector)}. ${widget.state.exports.profile.forSector(selectedSector).quantityOnly ? 'Arquivo com código interno e quantidade.' : 'Arquivo com código, quantidade, unidade 1 e valor unitário.'} Reservar ${selection.length} itens? Eles ficarão protegidos contra exportação em outro lote. Confirme que todos os dispositivos sincronizaram.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar exportação'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (yes != true || !mounted) return;
    // Keep the exact preflight selection/version; server rejects changes after this preview.
    final filters = filtersJson;
    await _run(() async {
      await widget.state.sync();
      if (widget.state.syncError.isNotEmpty) {
        throw StateError(widget.state.syncError);
      }
      final selectedIds = selection
          .map((r) => '${r.consumption.id}/${r.item.id}')
          .toSet();
      final refreshed =
          eligibleExportRows(
                reportRows(
                  widget.state.consumptions
                      .where((c) => c.sectorId == selectedSector)
                      .toList(),
                  filter,
                ),
                widget.state.batches,
              )
              .where(
                (r) => selectedIds.contains('${r.consumption.id}/${r.item.id}'),
              )
              .toList();
      if (refreshed.isEmpty) {
        throw StateError(
          'Não há itens novos: os consumos selecionados já estão reservados, exportados ou cancelados.',
        );
      }
      groupForExport(refreshed);
      final batch = await widget.state.prepareBatch(refreshed, filters);
      final ignored =
          selection.length -
          refreshed.length +
          (batch['skipped_count'] as int? ?? 0);
      if (mounted) {
        message(
          context,
          'Lote reservado para ${sectorLabel(selectedSector)}. ${ignored > 0 ? '$ignored item(ns) ignorado(s) por já estarem protegidos ou cancelados. ' : ''}Confira o histórico e salve o arquivo.',
        );
      }
    });
  }

  Future<void> _download(Json batch) async {
    final profile = ExportProfile.fromJson(
      Map<String, dynamic>.from(batch['profile']),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar arquivo para o VR'),
        content: Text(
          'Salvar o arquivo de ${sectorLabel(batch['sector'] ?? '')}, com ${(batch['grouped_rows'] as List).length} produtos?\nCampos: ${profile.order.map((f) => {'code': 'código interno', 'quantity': 'quantidade', 'unit': 'unidade 1', 'unit_price': 'valor unitário'}[f]).join(', ')}.\nApós a autorização de gravação, os itens continuam protegidos contra nova exportação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar e salvar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await saveExportArtifact(
      batch,
      authorize: (b) => widget.state.updateBatch(b, 'authorize_save', ''),
      write: (artifact) => saveBytes(artifact.name, artifact.bytes),
      recordSaved: widget.state.recordExportSaved,
    );
    if (result == ExportSaveResult.cancelled) return;
    if (mounted) {
      message(
        context,
        widget.state.exportReceipts.isEmpty
            ? 'Arquivo salvo. Confirme a importação após conferir no VR Master.'
            : 'Arquivo salvo. A confirmação será sincronizada quando houver conexão.',
      );
    }
  }

  Future<void> _change(Json batch, String action) async {
    final reference = await showTextPrompt(
      context,
      title: action == 'imported'
          ? 'Confirmar importação realizada'
          : 'Cancelar reserva',
      description: action == 'imported'
          ? 'Confirme somente após verificar a importação no VR Master. O aplicativo registra sua confirmação; não verifica o outro sistema.'
          : 'A reserva será liberada. O lote permanece no histórico.',
      label: action == 'imported'
          ? 'Referência da importação'
          : 'Justificativa',
    );
    if (reference == null || !mounted) return;
    await _run(() async {
      await widget.state.updateBatch(batch, action, reference);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
