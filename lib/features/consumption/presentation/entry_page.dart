import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'quantity_fields.dart';
import 'sum_number_field.dart';
import '../../../core/formatting/sum_expression.dart';
import '../../../core/formatting/search.dart';
import '../../../core/access/sectors.dart';

import 'package:intl/intl.dart';

import '../../../app/app_state.dart';
import '../../../infrastructure/local/database.dart';
import '../../../domain/models.dart';
import '../../../core/widgets/common.dart';
import '../label/application/scale_label_service.dart';
import '../label/domain/scale_label.dart';
import '../label/presentation/label_review_dialog.dart';
import '../label/presentation/label_scanner.dart';
import '../label/presentation/label_text_recognizer.dart';

class EntryPage extends StatefulWidget {
  final AppState state;
  final LabelScanner? labelScanner;
  final LabelTextRecognizer? labelTextRecognizer;
  const EntryPage({
    super.key,
    required this.state,
    this.labelScanner,
    this.labelTextRecognizer,
  });
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> with WidgetsBindingObserver {
  final sector = TextEditingController(), note = TextEditingController();
  final List<ConsumptionItem> items = [];
  final Set<String> scannedBarcodes = {};
  DateTime date = DateUtils.dateOnly(DateTime.now());
  bool dateChosen = false;
  int sectorRevision = 0;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.state.canManage) sector.text = widget.state.sectorId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _followToday();
  }

  // A tablet left open overnight must not keep launching on yesterday's date
  // unless someone chose that date on purpose or a launch is in progress.
  void _followToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (mounted && !dateChosen && items.isEmpty && date != today) {
      setState(() => date = today);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sector.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, i) => s + i.totalCents);
    final selectedSector = widget.state.canManage
        ? sectorKey(sector.text)
        : widget.state.sectorId;
    final requiresPrice = sectorRequiresPrice(selectedSector);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTitle(
            'Novo lançamento',
            requiresPrice
                ? 'Informe a quantidade e o valor total de cada produto.'
                : 'Informe a quantidade de cada produto.',
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
                                    setState(() {
                                      date = d;
                                      dateChosen = true;
                                    });
                                  }
                                },
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: widget.state.canManage
                            ? DropdownButtonFormField<String>(
                                key: ValueKey('${sector.text}-$sectorRevision'),
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
                                onChanged: busy ? null : _changeSector,
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
                          if (requiresPrice)
                            Text(
                              money(item.totalCents),
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          IconButton(
                            tooltip: requiresPrice
                                ? 'Editar quantidade e valor'
                                : 'Editar quantidade',
                            onPressed: busy ? null : () => _editItem(item),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Remover item',
                            onPressed: busy
                                ? null
                                : () => setState(() => items.remove(item)),
                            icon: const Icon(Icons.delete_outline),
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
                  if (requiresPrice) ...[
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
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

  Future<void> _addItem() => _pickItem();

  Future<void> _editItem(ConsumptionItem current) =>
      _pickItem(existing: current);

  Future<void> _pickItem({ConsumptionItem? existing}) async {
    final selectedSector = widget.state.canManage
        ? sectorKey(sector.text)
        : widget.state.sectorId;
    if (selectedSector == null || selectedSector.isEmpty) {
      message(context, 'Selecione o setor antes dos produtos.');
      return;
    }
    ScaleLabelFormat labelFormat;
    try {
      final savedFormat = await widget.state.db.setting('scale_label_format');
      labelFormat = savedFormat == null
          ? const ScaleLabelFormat()
          : ScaleLabelFormat.decode(savedFormat);
    } catch (exception) {
      if (mounted) message(context, friendlyError(exception));
      return;
    }
    if (!mounted) return;
    final result = await showDialog<ItemPickerResult>(
      context: context,
      builder: (_) => ItemPicker(
        products: widget.state.products
            .where((p) => p.active && p.sectorIds.contains(selectedSector))
            .toList(),
        allProducts: widget.state.products,
        sectorId: selectedSector,
        labelFormat: labelFormat,
        scannedBarcodes: scannedBarcodes,
        labelScanner: widget.labelScanner,
        labelTextRecognizer: widget.labelTextRecognizer,
        favorites: widget.state.favorites,
        recent: widget.state.recentProducts,
        initialItem: existing,
        requiresPrice: sectorRequiresPrice(selectedSector),
      ),
    );
    if (result != null && mounted) {
      var item = result.item;
      final duplicateIndex = items.indexWhere(
        (i) => i.productId == item.productId && i.id != existing?.id,
      );
      if (duplicateIndex >= 0) {
        if (result.scannedBarcode == null) {
          message(context, 'Esse produto já está no lançamento.');
          return;
        }
        final sum = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Produto já adicionado'),
            content: const Text(
              'Deseja somar à quantidade existente ou cancelar esta etiqueta?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Somar à quantidade existente'),
              ),
            ],
          ),
        );
        if (sum != true || !mounted) return;
        try {
          item = const ScaleLabelService().combine(items[duplicateIndex], item);
        } catch (exception) {
          message(context, friendlyError(exception));
          return;
        }
      }
      setState(() {
        if (existing == null) {
          if (duplicateIndex >= 0) {
            items[duplicateIndex] = item;
          } else {
            items.add(item);
          }
        } else {
          final index = items.indexWhere((i) => i.id == existing.id);
          if (index >= 0) items[index] = item;
        }
      });
    }
  }

  Future<void> _changeSector(String? value) async {
    if (value == null || value == sectorKey(sector.text)) return;
    if (items.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Trocar de setor?'),
          content: const Text(
            'Os itens já adicionados serão removidos, porque cada setor tem os próprios produtos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Trocar setor'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        // Rebuild the dropdown so it shows the sector that is still selected.
        setState(() => sectorRevision++);
        return;
      }
    }
    setState(() {
      sector.text = value;
      items.clear();
      scannedBarcodes.clear();
    });
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
      final requiresPrice = sectorRequiresPrice(c.sectorId ?? c.sector);
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
              if (date != DateUtils.dateOnly(DateTime.now()))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Atenção: a data do lançamento não é a de hoje.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 12),
              for (final item in c.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${item.code} · ${item.description}\n${quantity(item.amount, item.unit)} ${item.unit}${requiresPrice ? ' · ${money(item.totalCents)}' : ''}',
                  ),
                ),
              if (requiresPrice) Text('Total: ${money(c.totalCents)}'),
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
          scannedBarcodes.clear();
          note.clear();
          dateChosen = false;
          date = DateUtils.dateOnly(DateTime.now());
        });
        message(context, 'Lançamento salvo no dispositivo.');
      }
    } catch (e) {
      if (mounted) message(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ItemPickerResult {
  final ConsumptionItem item;
  final String? scannedBarcode;

  const ItemPickerResult({required this.item, this.scannedBarcode});
}

class ItemPicker extends StatefulWidget {
  final List<Product> products;
  final List<Product> allProducts;
  final String sectorId;
  final ScaleLabelFormat labelFormat;
  final Set<String> scannedBarcodes;
  final LabelScanner? labelScanner;
  final LabelTextRecognizer? labelTextRecognizer;
  final Set<String> favorites;
  final List<String> recent;
  final ConsumptionItem? initialItem;
  // False for sectors that record quantity only (Cozinha and Padaria).
  final bool requiresPrice;
  const ItemPicker({
    super.key,
    required this.products,
    required this.allProducts,
    required this.sectorId,
    required this.labelFormat,
    required this.scannedBarcodes,
    this.labelScanner,
    this.labelTextRecognizer,
    this.favorites = const {},
    this.recent = const [],
    this.initialItem,
    this.requiresPrice = true,
  });
  @override
  State<ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<ItemPicker> {
  String search = '', error = '';
  bool onlyFavorites = false, onlyRecent = false;
  Product? selected;
  final barcodeInput = TextEditingController();
  final amount = TextEditingController(),
      grams = TextEditingController(),
      total = TextEditingController();

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    if (item != null) {
      selected = widget.products
          .where((p) => p.id == item.productId)
          .firstOrNull;
      if (selected != null) {
        if (item.unit == 'KG') {
          amount.text = (item.amount ~/ 1000).toString();
          grams.text = (item.amount % 1000).toString();
        } else {
          amount.text = (item.amount ~/ 1000).toString();
          grams.text = '0';
        }
        total.text = (item.totalCents / 100)
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      }
    }
  }

  @override
  void dispose() {
    barcodeInput.dispose();
    amount.dispose();
    grams.dispose();
    total.dispose();
    super.dispose();
  }

  Future<void> _scanLabel() async {
    try {
      final capture = await (widget.labelScanner ?? MobileLabelScanner()).scan(
        context,
      );
      if (capture != null && mounted) {
        await _processBarcode(capture.barcode, imageBytes: capture.image);
      }
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    }
  }

  Future<void> _readBarcodeInput() =>
      _processBarcode(barcodeInput.text, imageBytes: null);

  Future<bool> _confirmReadAgain() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Etiqueta já lida'),
          content: const Text(
            'Este mesmo código já foi lido nesta sessão. Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _processBarcode(
    String barcode, {
    required Uint8List? imageBytes,
  }) async {
    try {
      final service = ScaleLabelService(
        parser: ScaleLabelParser(format: widget.labelFormat),
      );
      final parsed = service.parseBarcode(barcode);
      if (widget.scannedBarcodes.contains(parsed.rawBarcode) &&
          !await _confirmReadAgain()) {
        return;
      }
      widget.scannedBarcodes.add(parsed.rawBarcode);

      String? recognizedText;
      String? ocrFailure;
      if (imageBytes != null) {
        try {
          recognizedText =
              await (widget.labelTextRecognizer ?? createLabelTextRecognizer())
                  .recognize(imageBytes);
          if (recognizedText == null || recognizedText.trim().isEmpty) {
            ocrFailure =
                'Não foi possível ler o texto da etiqueta. Informe a quantidade manualmente.';
          }
        } catch (exception) {
          ocrFailure =
              'Falha no OCR: ${friendlyError(exception)} Informe a quantidade manualmente.';
        }
      } else {
        ocrFailure =
            'Sem imagem para leitura do peso. Informe a quantidade manualmente.';
      }

      final resolution = service.resolveLabel(
        label: parsed,
        products: widget.allProducts,
        sector: widget.sectorId,
        printedText: recognizedText,
      );
      if (!mounted) return;
      final item = await showDialog<ConsumptionItem>(
        context: context,
        builder: (_) => ScaleLabelReviewDialog(
          resolution: resolution,
          requiresPrice: widget.requiresPrice,
          ocrFailure: ocrFailure,
        ),
      );
      if (item != null && mounted) {
        Navigator.pop(
          context,
          ItemPickerResult(item: item, scannedBarcode: parsed.rawBarcode),
        );
      }
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        widget.products
            .where(
              (p) =>
                  (!onlyFavorites || widget.favorites.contains(p.id)) &&
                  (!onlyRecent || widget.recent.contains(p.id)) &&
                  normalizeSearch(
                    '${p.code} ${p.description}',
                  ).contains(normalizeSearch(search)),
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
      title: selected == null
          ? Row(
              children: [
                const Expanded(child: Text('Selecionar produto')),
                OutlinedButton.icon(
                  onPressed: _scanLabel,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Ler etiqueta'),
                ),
              ],
            )
          : Text(
              widget.initialItem == null
                  ? 'Quantidade e valor'
                  : 'Editar quantidade e valor',
            ),
      content: SizedBox(
        width: 540,
        height: 420,
        child: selected == null
            ? Column(
                children: [
                  TextField(
                    key: const ValueKey('barcode-input'),
                    controller: barcodeInput,
                    autofocus: true,
                    onSubmitted: (_) => _readBarcodeInput(),
                    decoration: const InputDecoration(
                      labelText: 'Código da etiqueta',
                      hintText: 'Leia, digite ou cole os 13 dígitos',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _readBarcodeInput,
                      icon: const Icon(Icons.check),
                      label: const Text('Usar código'),
                    ),
                  ),
                  TextField(
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
                    if (widget.requiresPrice)
                      SumNumberField(
                        controller: total,
                        label: 'Valor total (R\$)',
                        decimals: 2,
                        format: money,
                        helper:
                            'Total do produto. Você pode somar: 10,50+20+5.',
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
                // Preserve totals on legacy items when editing a quantity-only
                // sector; newly added items still receive a zero total.
                final cents = widget.requiresPrice
                    ? parseSumScaled(total.text, 2)
                    : (widget.initialItem?.totalCents ?? 0);
                Navigator.pop(
                  context,
                  ItemPickerResult(
                    item: ConsumptionItem(
                      id: widget.initialItem?.id ?? uuid.v4(),
                      productId: p.id,
                      code: p.code,
                      description: p.description,
                      unit: p.unit,
                      amount: q,
                      totalCents: cents,
                    ),
                  ),
                );
              } catch (e) {
                setState(() => error = friendlyError(e));
              }
            },
            child: Text(
              widget.initialItem == null ? 'Adicionar' : 'Salvar alterações',
            ),
          ),
      ],
    );
  }
}
