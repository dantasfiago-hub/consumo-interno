import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Separate integer fields; persistence still uses thousandths of a unit/kg.
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
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      final number = int.tryParse(value.text) ?? 0;
      void step(int delta) {
        final next = (number + delta).clamp(0, maximum).toString();
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }

      return Row(
        children: [
          IconButton(
            key: ValueKey('$id-minus'),
            tooltip: 'Diminuir $label',
            onPressed: number <= 0 ? null : () => step(-1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: TextField(
              key: ValueKey(id),
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: maximum.toString().length,
              decoration: InputDecoration(labelText: label, counterText: ''),
            ),
          ),
          IconButton(
            key: ValueKey('$id-plus'),
            tooltip: 'Aumentar $label',
            onPressed: number >= maximum ? null : () => step(1),
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
      ),
      if (unit == 'KG') ...[
        const SizedBox(height: 12),
        _field(grams, 'Gramas (g)', 'quantity-grams', 999),
        const SizedBox(height: 8),
        const Text(
          'Ex.: 2 kg e 350 g. Gramas: de 0 a 999. Cada botão altera 1.',
        ),
      ],
    ],
  );
}
