import 'package:flutter/material.dart';

import '../../../core/formatting/sum_expression.dart';
import 'sum_number_field.dart';

/// Separate integer sums; persistence still uses thousandths of a unit/kg.
class QuantityFields extends StatefulWidget {
  final String unit;
  final TextEditingController whole, grams;
  const QuantityFields({
    super.key,
    required this.unit,
    required this.whole,
    required this.grams,
  });

  @override
  State<QuantityFields> createState() => _QuantityFieldsState();
}

class _QuantityFieldsState extends State<QuantityFields> {
  final _gramsFocus = FocusNode();
  String get unit => widget.unit;
  TextEditingController get whole => widget.whole;
  TextEditingController get grams => widget.grams;

  @override
  void initState() {
    super.initState();
    _gramsFocus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_gramsFocus.hasFocus) _normalizeGrams();
  }

  void _write(TextEditingController controller, int number) {
    final text = number.toString();
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setWeight(int total) {
    _write(whole, total ~/ 1000);
    _write(grams, total % 1000);
  }

  void _normalizeGrams() {
    if (unit != 'KG') return;
    try {
      final g = parseSumScaled(
        grams.text.trim().isEmpty ? '0' : grams.text,
        0,
        allowZero: true,
      );
      if (g < 1000) return;
      final parts = normalizeSumWeightParts(whole.text, grams.text);
      _setWeight(parts.kilograms * 1000 + parts.grams);
    } on FormatException {
      // Keep incomplete/invalid expressions for correction.
    }
  }

  int? _weight() {
    try {
      final parts = normalizeSumWeightParts(whole.text, grams.text);
      return parts.kilograms * 1000 + parts.grams;
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    _gramsFocus.removeListener(_onFocusChanged);
    _gramsFocus.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String id,
    int maximum,
    String suffix,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      int? number;
      try {
        number = parseSumScaled(
          value.text.trim().isEmpty ? '0' : value.text,
          0,
          allowZero: true,
          maximum: maximum,
        );
      } on FormatException {
        // Do not discard an unfinished/invalid expression when stepping.
      }
      final isGrams = id == 'quantity-grams';
      final weight = isGrams ? _weight() : null;
      void step(int delta) {
        if (isGrams) {
          // Read again: losing focus may already have normalized the fields.
          final current = _weight();
          if (current == null ||
              current + delta < 0 ||
              current + delta > 999999999999) {
            return;
          }
          _setWeight(current + delta);
          return;
        }
        if (number == null) return;
        final next = (number + delta).clamp(0, maximum).toString();
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            key: ValueKey('$id-minus'),
            tooltip: 'Diminuir $label',
            onPressed:
                (isGrams
                    ? weight == null || weight <= 0
                    : number == null || number <= 0)
                ? null
                : () => step(-1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: SumNumberField(
              key: ValueKey(id),
              controller: controller,
              label: label,
              maximum: maximum,
              focusNode: isGrams ? _gramsFocus : null,
              onSubmitted: isGrams ? (_) => _normalizeGrams() : null,
              format: (n) {
                if (!isGrams) return '$n $suffix';
                final parts = normalizeSumWeightParts(whole.text, grams.text);
                return '${parts.kilograms} kg e ${parts.grams} g';
              },
            ),
          ),
          IconButton(
            key: ValueKey('$id-plus'),
            tooltip: 'Aumentar $label',
            onPressed: isGrams
                ? (weight == null || weight >= 999999999999
                      ? null
                      : () => step(1))
                : number == null || number >= maximum
                ? null
                : () => step(1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([whole, grams]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          whole,
          unit == 'KG' ? 'Quilogramas (kg)' : 'Quantidade (UN)',
          unit == 'KG' ? 'quantity-kg' : 'quantity-units',
          999999999,
          unit == 'KG' ? 'kg' : 'UN',
        ),
        if (unit == 'KG') ...[
          const SizedBox(height: 12),
          _field(grams, 'Gramas (g)', 'quantity-grams', 999999999999, 'g'),
          const SizedBox(height: 8),
          const Text(
            'Ex.: kg 2+1 e gramas 200+150 = 3 kg e 350 g. '
            'Acima de 999 g, o excedente vira kg ao sair do campo ou confirmar. '
            'O resultado aparece enquanto você digita. Cada botão altera 1.',
          ),
        ],
      ],
    ),
  );
}
