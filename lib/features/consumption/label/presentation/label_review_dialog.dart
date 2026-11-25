import 'package:flutter/material.dart';

import '../../../../core/formatting/numbers.dart';
import '../../../../core/widgets/common.dart';
import '../../presentation/quantity_fields.dart';
import '../../presentation/sum_number_field.dart';
import '../application/scale_label_service.dart';

class ScaleLabelReviewDialog extends StatefulWidget {
  final ScaleLabelResolution resolution;
  final bool requiresPrice;
  final String? ocrFailure;

  const ScaleLabelReviewDialog({
    super.key,
    required this.resolution,
    required this.requiresPrice,
    this.ocrFailure,
  });

  @override
  State<ScaleLabelReviewDialog> createState() => _ScaleLabelReviewDialogState();
}

class _ScaleLabelReviewDialogState extends State<ScaleLabelReviewDialog> {
  final whole = TextEditingController();
  final grams = TextEditingController();
  final total = TextEditingController();
  final wholeFocus = FocusNode();
  bool quantityEdited = false, totalEdited = false;
  bool confirmedInconsistentReading = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    final weight = widget.resolution.suggestedWeightMilli;
    if (weight != null) {
      whole.text = (weight ~/ 1000).toString();
      grams.text = (weight % 1000).toString();
    } else {
      whole.text = '';
      grams.text = '0';
    }
    final cents = widget.resolution.label.totalCents;
    if (widget.requiresPrice && cents != null) {
      total.text =
          '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
    }
    whole.addListener(_quantityChanged);
    grams.addListener(_quantityChanged);
    total.addListener(_totalChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.resolution.suggestedWeightMilli == null) {
        wholeFocus.requestFocus();
      }
    });
  }

  void _quantityChanged() => quantityEdited = true;
  void _totalChanged() => totalEdited = true;

  @override
  void dispose() {
    whole.removeListener(_quantityChanged);
    grams.removeListener(_quantityChanged);
    total.removeListener(_totalChanged);
    whole.dispose();
    grams.dispose();
    total.dispose();
    wholeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolution = widget.resolution;
    final reading = resolution.printedText;
    return AlertDialog(
      title: const Text('Confirmar etiqueta'),
      scrollable: true,
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${resolution.product.description} · ${resolution.product.code}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Produto identificado pelo código de barras'),
            const SizedBox(height: 12),
            QuantityFields(
              unit: resolution.product.unit,
              whole: whole,
              grams: grams,
              wholeFocusNode: wholeFocus,
            ),
            Text(
              'Quantidade: ${quantityEdited ? 'digitado' : resolution.weightSource ?? 'digitado'}',
            ),
            if (widget.requiresPrice) ...[
              const SizedBox(height: 12),
              SumNumberField(
                controller: total,
                label: 'Valor total (R\$)',
                decimals: 2,
                format: money,
                helper: 'Valor total impresso na etiqueta.',
              ),
              Text(
                'Valor: ${totalEdited || resolution.label.totalCents == null ? 'digitado' : 'código de barras'}',
              ),
            ],
            if (widget.ocrFailure != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(widget.ocrFailure!),
              ),
            if (reading?.isConsistent == false)
              Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'A leitura do peso, preço/kg e total impresso não confere. Revise os valores.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmedInconsistentReading,
                    onChanged: (value) => setState(
                      () => confirmedInconsistentReading = value ?? false,
                    ),
                    title: const Text('Revisei a quantidade e o valor'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            if (reading != null &&
                reading.weightMilli == null &&
                resolution.suggestedWeightMilli == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Não foi possível ler o peso. Informe a quantidade manualmente.',
                ),
              ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              reading?.isConsistent == false && !confirmedInconsistentReading
              ? null
              : _add,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }

  void _add() {
    try {
      final resolution = widget.resolution;
      final item = const ScaleLabelService().createItem(
        resolution: resolution,
        whole: whole.text,
        grams: grams.text,
        total: total.text,
        requiresPrice: widget.requiresPrice,
      );
      Navigator.pop(context, item);
    } catch (exception) {
      setState(() => error = friendlyError(exception));
    }
  }
}
