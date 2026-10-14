import 'package:flutter/material.dart';

import '../../../core/formatting/sum_expression.dart';

/// Text keyboard deliberately exposes + on Android; result is never stored as text.
class SumNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label, helper;
  final int decimals, maximum;
  final String Function(int) format;
  const SumNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.format,
    this.helper = 'Você pode somar: 10+20+5, sem colocar =.',
    this.decimals = 0,
    this.maximum = 999999999999,
  });

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      String? result, error;
      if (value.text.trim().isNotEmpty) {
        try {
          result =
              'Resultado: ${format(parseSumScaled(value.text, decimals, allowZero: true, maximum: maximum))}';
        } on FormatException catch (e) {
          error = e.message;
        }
      }
      return TextField(
        controller: controller,
        keyboardType: TextInputType.text,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          helperText: result ?? helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
        ),
      );
    },
  );
}
