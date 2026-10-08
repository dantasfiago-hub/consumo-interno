import 'package:flutter/material.dart';

import '../../../core/formatting/sum_expression.dart';
import 'sum_number_field.dart';

/// Separate integer sums; persistence still uses thousandths of a unit/kg.
class QuantityFields extends StatelessWidget {
  final String unit;
  final TextEditingController whole, grams;
  const QuantityFields({
    super.key,
    required this.unit,
    required this.whole,
    required this.grams,
  });

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
      void step(int delta) {
        if (number == null) return;
        final next = (number! + delta).clamp(0, maximum).toString();
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
            onPressed: number == null || number <= 0 ? null : () => step(-1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: SumNumberField(
              key: ValueKey(id),
              controller: controller,
              label: label,
              maximum: maximum,
              format: (n) => '$n $suffix',
            ),
          ),
          IconButton(
            key: ValueKey('$id-plus'),
            tooltip: 'Aumentar $label',
            onPressed: number == null || number >= maximum
                ? null
                : () => step(1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Column(
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
        _field(grams, 'Gramas (g)', 'quantity-grams', 999, 'g'),
        const SizedBox(height: 8),
        const Text(
          'Ex.: kg 2+1 e gramas 200+150 = 3 kg e 350 g. '
          'A soma das gramas deve ficar de 0 a 999. Cada botão altera 1.',
        ),
      ],
    ],
  );
}
