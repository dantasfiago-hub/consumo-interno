import '../../../core/access/sectors.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../domain/models.dart';
import '../../../core/files/file_service.dart';
import '../data/pdf_service.dart';
import '../../../core/widgets/common.dart';

class ReportsPage extends StatefulWidget {
  final AppState state;
  const ReportsPage({super.key, required this.state});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final filter = ReportFilter();
  bool resultsVisible = false;
  bool fullHistory = false;
  bool grouped = false, busy = false;
  String amountError = '';
  final fieldErrors = <String, String>{};
  @override
  Widget build(BuildContext context) {
    if (!widget.state.canManage) {
      return const Center(child: Text('Acesso exclusivo do administrador.'));
    }
    final rows = resultsVisible
        ? reportRows(
            widget.state.consumptions,
            fullHistory ? (ReportFilter()..status = '') : filter,
          )
        : <ReportRow>[];
    final valid = rows.where((r) => r.consumption.status == 'confirmed');
    final total = valid.fold<int>(0, (n, r) => n + r.item.totalCents);
    final units = valid
        .where((r) => r.item.unit == 'UN')
        .fold<int>(0, (n, r) => n + r.item.amount);
    final kg = valid
        .where((r) => r.item.unit == 'KG')
        .fold<int>(0, (n, r) => n + r.item.amount);
    final sync = widget.state.lastSync.isEmpty
        ? 'Ainda não houve sincronização.'
        : 'Última sincronização: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(widget.state.lastSync))}';
    final summaries = groupReportProducts(rows);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            'Relatórios',
            'Combine filtros e exporte os resultados.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: Icon(Icons.date_range),
                    label: Text(
                      filter.from == null
                          ? 'Selecionar período'
                          : '${DateFormat('dd/MM/yy').format(filter.from!)} — ${DateFormat('dd/MM/yy').format(filter.to!)}',
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
                          resultsVisible = false;
                          fullHistory = false;
                          filter.from = range.start;
                          filter.to = range.end;
                        });
                      }
                    },
                  ),
                  if (filter.from != null)
                    TextButton(
                      onPressed: () => setState(() {
                        resultsVisible = false;
                        fullHistory = false;
                        filter.from = null;
                        filter.to = null;
                      }),
                      child: Text('Todo o período'),
                    ),
                  _field('Código ou descrição', (v) => filter.query = v),
                  _field('Setor', (v) => filter.sector = v),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: filter.status,
                      decoration: const InputDecoration(labelText: 'Situação'),
                      items: const [
                        DropdownMenuItem(
                          value: 'confirmed',
                          child: Text('Confirmados'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Cancelados'),
                        ),
                        DropdownMenuItem(value: '', child: Text('Todos')),
                      ],
                      onChanged: (v) => setState(() {
                        resultsVisible = false;
                        fullHistory = false;
                        filter.status = v!;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      initialValue: filter.unit,
                      decoration: const InputDecoration(labelText: 'Unidade'),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Todas')),
                        DropdownMenuItem(value: 'UN', child: Text('UN')),
                        DropdownMenuItem(value: 'KG', child: Text('KG')),
                      ],
                      onChanged: (v) => setState(() {
                        resultsVisible = false;
                        fullHistory = false;
                        filter.unit = v!;
                      }),
                    ),
                  ),
                  _field('Total mínimo (R\$)', (v) {
                    filter.minCents = v.trim().isEmpty
                        ? null
                        : parseScaled(v, 2, allowZero: true);
                  }),
                  _field('Total máximo (R\$)', (v) {
                    filter.maxCents = v.trim().isEmpty
                        ? null
                        : parseScaled(v, 2, allowZero: true);
                  }),
                ],
              ),
            ),
          ),
          if (amountError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                amountError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy || amountError.isNotEmpty
                    ? null
                    : () => setState(() {
                        fullHistory = false;
                        resultsVisible = true;
                      }),
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Aplicar filtros'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        fullHistory = true;
                        grouped = false;
                        resultsVisible = true;
                      }),
                icon: const Icon(Icons.history),
                label: const Text('Exibir histórico completo'),
              ),
            ],
          ),
          if (resultsVisible && fullHistory)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Histórico completo. Pressione Aplicar filtros para voltar aos filtros preenchidos.',
              ),
            ),
          if (!resultsVisible)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                'Aplique os filtros para consultar',
                'Selecione os filtros e pressione Aplicar filtros, ou escolha Exibir histórico completo.',
              ),
            ),
          if (resultsVisible) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Valor confirmado', money(total)),
                _metric('Unidades', quantity(units, 'UN')),
                _metric('Quilogramas', '${quantity(kg, 'KG')} kg'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$sync ${widget.state.pending.length} operação(ões) pendente(s).',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text('Agrupar por produto'),
                  selected: grouped,
                  onSelected: (v) => setState(() => grouped = v),
                ),
                OutlinedButton.icon(
                  onPressed:
                      busy ||
                          rows.isEmpty ||
                          (!fullHistory && amountError.isNotEmpty)
                      ? null
                      : () => _export(rows, false, sync),
                  icon: Icon(Icons.table_view_outlined),
                  label: Text(
                    grouped
                        ? 'Exportar CSV por produto'
                        : 'Exportar CSV detalhado',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      busy ||
                          rows.isEmpty ||
                          (!fullHistory && amountError.isNotEmpty)
                      ? null
                      : () => _export(rows, true, sync),
                  icon: Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    grouped
                        ? 'Exportar PDF por produto'
                        : 'Exportar PDF detalhado',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Arquivo para importação: abra Exportações.'),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const EmptyState(
                'Nenhum resultado',
                'Altere os filtros ou registre um consumo.',
              ),
            if (grouped)
              ...summaries.map(
                (s) => Card(
                  child: ListTile(
                    title: Text('${s.code} · ${s.description}'),
                    subtitle: Text(
                      '${quantity(s.amount, s.unit)} ${s.unit} · ${s.consumptionCount} lançamento(s) · ${s.status == 'confirmed' ? 'Confirmado' : 'Cancelado'}',
                    ),
                    trailing: Text(money(s.totalCents)),
                  ),
                ),
              )
            else
              ...rows.map(
                (r) => Card(
                  child: ListTile(
                    title: Text('${r.item.code} · ${r.item.description}'),
                    subtitle: Text(
                      '${r.consumption.date.split('-').reversed.join('/')} · ${quantity(r.item.amount, r.item.unit)} ${r.item.unit}\n${r.consumption.operatorName} · ${sectorLabel(r.consumption.assignedSector ?? r.consumption.sector)}${r.consumption.status == 'cancelled' ? ' · Cancelado' : ''}',
                    ),
                    trailing: Text(money(r.item.totalCents)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, void Function(String) update) => SizedBox(
    width: 210,
    child: TextField(
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        setState(() {
          resultsVisible = false;
          fullHistory = false;
          try {
            update(v);
            fieldErrors.remove(label);
            amountError = fieldErrors.values.join(' ');
            if (filter.minCents != null &&
                filter.maxCents != null &&
                filter.minCents! > filter.maxCents!) {
              amountError = 'O mínimo deve ser menor ou igual ao máximo.';
            }
          } catch (e) {
            fieldErrors[label] = e.toString().replaceFirst(
              'FormatException: ',
              '',
            );
            amountError = fieldErrors.values.join(' ');
          }
        });
      },
    ),
  );
  Widget _metric(String title, String value) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 25,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _export(List<ReportRow> rows, bool pdf, String sync) async {
    final exportGrouped = grouped;
    setState(() => busy = true);
    try {
      final bytes = pdf
          ? await reportPdf(
              rows,
              grouped: exportGrouped,
              synchronization:
                  '$sync Pendências: ${widget.state.pending.length}.',
            )
          : utf8.encode(
              exportGrouped
                  ? reportProductsCsv(groupReportProducts(rows))
                  : reportCsv(rows),
            );
      final path = await saveBytes(
        'consumos_${exportGrouped ? 'por_produto_' : ''}${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.${pdf ? 'pdf' : 'csv'}',
        bytes,
      );
      if (mounted && path != null) message(context, 'Arquivo exportado.');
    } catch (e) {
      if (mounted) message(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
