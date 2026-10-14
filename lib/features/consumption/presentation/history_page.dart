import 'package:flutter/material.dart';
import '../../../core/access/sectors.dart';
import '../../../app/app_state.dart';
import '../../../domain/models.dart';
import '../../../core/widgets/common.dart';

class HistoryPage extends StatefulWidget {
  final AppState state;
  const HistoryPage({super.key, required this.state});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final records = widget.state.consumptions
        .where(
          (c) =>
              '${c.date} ${c.operatorName} ${sectorLabel(c.assignedSector ?? c.sector)} ${c.items.map((i) => i.description).join(' ')}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            'Consumos e cancelamento',
            'Confira os lançamentos e acompanhe o envio.',
          ),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar data, responsável, setor ou produto',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: records.isEmpty
                ? const EmptyState(
                    'Nenhum lançamento',
                    'Os consumos registrados aparecerão aqui.',
                  )
                : ListView.builder(
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final c = records[index];
                      final pending = widget.state.pending.any(
                        (op) => op['entity_id'] == c.id,
                      );
                      return Card(
                        child: ExpansionTile(
                          leading: Icon(
                            c.status == 'cancelled'
                                ? Icons.cancel_outlined
                                : Icons.receipt_long_outlined,
                          ),
                          title: Text(
                            '${c.date.split('-').reversed.join('/')} · ${money(c.totalCents)}',
                          ),
                          subtitle: Text(
                            '${c.operatorName}${c.sector.isEmpty ? '' : ' · ${sectorLabel(c.assignedSector ?? c.sector)}'}\n${c.status == 'cancelled' ? 'Cancelado · ' : ''}${pending ? 'Envio pendente' : 'Sincronizado'}',
                          ),
                          children: [
                            for (final i in c.items)
                              ListTile(
                                title: Text('${i.code} · ${i.description}'),
                                subtitle: Text(
                                  '${quantity(i.amount, i.unit)} ${i.unit}',
                                ),
                                trailing: Text(money(i.totalCents)),
                              ),
                            if (c.note.isNotEmpty)
                              ListTile(
                                title: Text('Observação'),
                                subtitle: Text(c.note),
                              ),
                            if (c.cancellationReason != null)
                              ListTile(
                                title: Text('Motivo do cancelamento'),
                                subtitle: Text(c.cancellationReason!),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                'ID: ${c.id}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (widget.state.canManage &&
                                c.sectorId == null &&
                                !c.exportLocked)
                              TextButton(
                                onPressed: () => _classify(context, c),
                                child: const Text(
                                  'Definir setor do consumo antigo',
                                ),
                              ),
                            if (c.exportLocked)
                              const ListTile(
                                title: Text(
                                  'Consumo protegido por exportação. Procure o administrador para correções.',
                                ),
                              ),
                            if (widget.state.canCancel(c))
                              TextButton.icon(
                                icon: Icon(Icons.block),
                                label: Text('Cancelar lançamento'),
                                onPressed: () async {
                                  final reason = await reasonDialog(context);
                                  if (reason != null && context.mounted) {
                                    await guarded(
                                      context,
                                      () => widget.state.cancel(c, reason),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _classify(BuildContext context, Consumption c) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Setor do consumo antigo'),
        children: sectors.entries
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, e.key),
                child: Text(e.value),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || !context.mounted) return;
    final reason = await reasonDialog(context);
    if (reason != null && context.mounted) {
      await guarded(
        context,
        () => widget.state.assignLegacySector(c.id, selected, reason),
      );
    }
  }
}
