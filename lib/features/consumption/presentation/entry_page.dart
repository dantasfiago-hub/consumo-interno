import 'package:flutter/material.dart';

import 'quantity_fields.dart';
import 'sum_number_field.dart';
import '../../../core/formatting/sum_expression.dart';
import '../../../core/access/sectors.dart';

import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../infrastructure/local/database.dart';
import '../../../domain/models.dart';
import '../../../core/widgets/common.dart';

class EntryPage extends StatefulWidget {
  final AppState state;
  const EntryPage({super.key, required this.state});
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  final sector = TextEditingController(), note = TextEditingController();
  final List<ConsumptionItem> items = [];
  DateTime date = DateUtils.dateOnly(DateTime.now());
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (!widget.state.canManage) sector.text = widget.state.sectorId;
  }

  @override
  void dispose() {
    sector.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, i) => s + i.totalCents);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle(
            'Novo lançamento',
            'Informe a quantidade e o valor total de cada produto.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.calendar_month),
                          label: Text(DateFormat('dd/MM/yyyy').format(date)),
                          onPressed: busy
                              ? null
                              : () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (d != null && mounted) {
                                    setState(() => date = d);
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: widget.state.canManage
                            ? DropdownButtonFormField<String>(
                                initialValue: sectorKey(sector.text),
                                decoration: const InputDecoration(
                                  labelText: 'Setor *',
                                ),
                                items: sectors.entries
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() {
                                        sector.text = v!;
                                        items.clear();
                                      }),
                              )
                            : InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Setor',
                                ),
                                child: Text(sectorLabel(widget.state.sectorId)),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Observação (opcional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Produtos (${items.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Adicionar produto',
                        onPressed: busy ? null : _addItem,
                        icon: Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  if (items.isEmpty)
                    EmptyState(
                      'Adicione os produtos consumidos',
                      'Pesquise por código, descrição ou foto.',
                      action: FilledButton.icon(
                        onPressed: busy ? null : _addItem,
                        icon: Icon(Icons.add),
                        label: Text('Selecionar produto'),
                      ),
                    ),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Photo(
                            widget.state.products
                                .where((p) => p.id == item.productId)
                                .firstOrNull,
                            size: 52,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.description,
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${item.code} · ${quantity(item.amount, item.unit)} ${item.unit}',
                                ),
                              ],
                            ),
                          ),
                          Text(
                            money(item.totalCents),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            tooltip: 'Remover item',
                            onPressed: busy
                                ? null
                                : () => setState(() => items.remove(item)),
                            icon: Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  if (items.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: busy ? null : _addItem,
                      icon: Icon(Icons.add),
                      label: Text('Adicionar produto'),
                    ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total do lançamento',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Text(
                          money(total),
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: busy || items.isEmpty ? null : _save,
                        icon: Icon(Icons.save_outlined),
                        label: Text(busy ? 'Salvando...' : 'Salvar lançamento'),
                      ),
                      Text(
                        'Salvo no dispositivo. Enviado quando houver conexão.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addItem() async {
    final selectedSector = widget.state.canManage
        ? sectorKey(sector.text)
        : widget.state.sectorId;
    if (selectedSector == null || selectedSector.isEmpty) {
      message(context, 'Selecione o setor antes dos produtos.');
      return;
    }
    final item = await showDialog<ConsumptionItem>(
      context: context,
      builder: (_) => ItemPicker(
        products: widget.state.products
            .where((p) => p.active && p.sectorIds.contains(selectedSector))
            .toList(),
        favorites: widget.state.favorites,
        recent: widget.state.recentProducts,
      ),
    );
    if (item != null && mounted) {
      if (items.any((i) => i.productId == item.productId)) {
        message(
          context,
          'Produto já adicionado. Remova o item para alterar a quantidade e o total.',
        );
        return;
      }
      setState(() => items.add(item));
    }
  }

  Future<void> _save() async {
    if (busy || items.isEmpty) return;
    setState(() => busy = true);
    try {
      final c = Consumption(
        id: uuid.v4(),
        date: DateFormat('yyyy-MM-dd').format(date),
        createdAt: DateTime.now().toUtc().toIso8601String(),
        operatorName: sectorLabel(
          widget.state.canManage
              ? sectorKey(sector.text)!
              : widget.state.sectorId,
        ),
        sector: widget.state.canManage
            ? sectorKey(sector.text)!
            : widget.state.sectorId,
        note: note.text.trim(),
        items: List.of(items),
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar lançamento'),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sectorLabel(c.sector)} · ${DateFormat('dd/MM/yyyy').format(date)}',
              ),
              const SizedBox(height: 12),
              for (final item in c.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${item.code} · ${item.description}\n${quantity(item.amount, item.unit)} ${item.unit} · ${money(item.totalCents)}',
                  ),
                ),
              Text('Total: ${money(c.totalCents)}'),
              const SizedBox(height: 12),
              const Text('Confirma o lançamento deste consumo?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar lançamento'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.state.saveConsumption(c);
      if (mounted) {
        setState(() {
          items.clear();
          note.clear();
        });
        message(context, 'Lançamento salvo no dispositivo.');
      }
    } catch (e) {
      if (mounted) message(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ItemPicker extends StatefulWidget {
  final List<Product> products;
  final Set<String> favorites;
  final List<String> recent;
  const ItemPicker({
    super.key,
    required this.products,
    this.favorites = const {},
    this.recent = const [],
  });
  @override
  State<ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<ItemPicker> {
  String search = '', error = '';
  bool onlyFavorites = false, onlyRecent = false;
  Product? selected;
  final amount = TextEditingController(),
      grams = TextEditingController(),
      total = TextEditingController();
  @override
  void dispose() {
    amount.dispose();
    grams.dispose();
    total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        widget.products
            .where(
              (p) =>
                  (!onlyFavorites || widget.favorites.contains(p.id)) &&
                  (!onlyRecent || widget.recent.contains(p.id)) &&
                  '${p.code} ${p.description}'.toLowerCase().contains(
                    search.toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) {
            final favorite =
                (widget.favorites.contains(b.id) ? 1 : 0) -
                (widget.favorites.contains(a.id) ? 1 : 0);
            if (favorite != 0) return favorite;
            final ar = widget.recent.indexOf(a.id),
                br = widget.recent.indexOf(b.id);
            final recent = (ar < 0 ? 999 : ar).compareTo(br < 0 ? 999 : br);
            return recent != 0
                ? recent
                : a.description.compareTo(b.description);
          });
    return AlertDialog(
      title: Text(
        selected == null ? 'Selecionar produto' : 'Quantidade e valor',
      ),
      content: SizedBox(
        width: 540,
        height: 420,
        child: selected == null
            ? Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => search = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Código ou descrição',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Favoritos'),
                        selected: onlyFavorites,
                        onSelected: (v) => setState(() => onlyFavorites = v),
                      ),
                      FilterChip(
                        label: const Text('Recentes'),
                        selected: onlyRecent,
                        onSelected: (v) => setState(() => onlyRecent = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('Nenhum produto ativo encontrado.'),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                  horizontal: 4,
                                ),
                                leading: Photo(p, size: 52),
                                title: Text(p.description),
                                subtitle: Text(p.code),
                                trailing: UnitBadge(p.unit),
                                onTap: () => setState(() {
                                  selected = p;
                                  amount.text = '0';
                                  grams.text = '0';
                                  total.clear();
                                  error = '';
                                }),
                              );
                            },
                          ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Photo(selected, size: 110)),
                    const SizedBox(height: 12),
                    Text(
                      selected!.description,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('${selected!.code} · ${selected!.unit}'),
                    const SizedBox(height: 18),
                    QuantityFields(
                      unit: selected!.unit,
                      whole: amount,
                      grams: grams,
                    ),
                    const SizedBox(height: 16),
                    SumNumberField(
                      controller: total,
                      label: 'Valor total (R\$)',
                      decimals: 2,
                      format: money,
                      helper: 'Total do produto. Você pode somar: 10,50+20+5.',
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (selected != null) {
              setState(() => selected = null);
            } else {
              Navigator.pop(context);
            }
          },
          child: Text('Voltar'),
        ),
        if (selected != null)
          FilledButton(
            onPressed: () {
              try {
                final p = selected!;
                final q = p.unit == 'KG'
                    ? parseSumWeightParts(amount.text, grams.text)
                    : parseSumQuantity(amount.text, p.unit);
                final cents = parseSumScaled(total.text, 2);
                Navigator.pop(
                  context,
                  ConsumptionItem(
                    id: uuid.v4(),
                    productId: p.id,
                    code: p.code,
                    description: p.description,
                    unit: p.unit,
                    amount: q,
                    totalCents: cents,
                  ),
                );
              } catch (e) {
                setState(
                  () => error = e.toString().replaceFirst(
                    'FormatException: ',
                    '',
                  ),
                );
              }
            },
            child: Text('Adicionar'),
          ),
      ],
    );
  }
}
