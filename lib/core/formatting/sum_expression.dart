/// Addition only, without evaluation of code or floating-point arithmetic.
/// The result uses cents, grams or integer units according to [decimals].
int parseSumScaled(
  String text,
  int decimals, {
  bool allowZero = false,
  int maximum = 999999999999,
}) {
  if (decimals < 0 || decimals > 3 || maximum < 0) {
    throw ArgumentError('Escala ou limite inválido.');
  }
  final input = text.trim();
  if (input.isEmpty || input.length > 200) {
    throw const FormatException(
      'Informe um número ou uma soma de até 200 caracteres.',
    );
  }
  final terms = input.split('+');
  var sum = BigInt.zero;
  final limit = BigInt.from(maximum);
  for (final term in terms) {
    final value = term.trim();
    if (value.isEmpty) {
      throw const FormatException(
        'Complete a soma: informe um número entre os sinais +.',
      );
    }
    if (!RegExp(r'^\d+([,.]\d+)?$').hasMatch(value)) {
      throw const FormatException(
        'Use números e +, sem separador de milhar. Ex.: 10+20+5.',
      );
    }
    final parts = value.replaceAll(',', '.').split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > decimals) {
      throw FormatException(
        decimals == 0
            ? 'Este campo aceita apenas números inteiros.'
            : 'Use no máximo $decimals casas decimais por parcela.',
      );
    }
    sum += BigInt.parse(parts[0] + fraction.padRight(decimals, '0'));
    if (sum > limit) {
      throw const FormatException('A soma ultrapassa o limite permitido.');
    }
  }
  if (!allowZero && sum == BigInt.zero) {
    throw const FormatException('O resultado deve ser maior que zero.');
  }
  return sum.toInt();
}

int parseSumQuantity(String text, String unit) {
  if (unit == 'UN') {
    return parseSumScaled(text, 0, maximum: 999999999) * 1000;
  }
  if (unit == 'KG') return parseSumScaled(text, 3);
  throw const FormatException('Unidade inválida.');
}

/// Normalize complete expressions without changing the stored gram precision.
/// Zero is allowed here so empty editing fields and decrement buttons can work.
({int kilograms, int grams}) normalizeSumWeightParts(
  String kilograms,
  String grams,
) {
  final kg = parseSumScaled(
    kilograms.trim().isEmpty ? '0' : kilograms,
    0,
    allowZero: true,
    maximum: 999999999,
  );
  final g = parseSumScaled(
    grams.trim().isEmpty ? '0' : grams,
    0,
    allowZero: true,
  );
  final total = kg * 1000 + g;
  if (total > 999999999999) {
    throw const FormatException('O peso ultrapassa o limite permitido.');
  }
  return (kilograms: total ~/ 1000, grams: total % 1000);
}

int parseSumWeightParts(String kilograms, String grams) {
  final parts = normalizeSumWeightParts(kilograms, grams);
  final result = parts.kilograms * 1000 + parts.grams;
  if (result == 0) {
    throw const FormatException('Informe um peso maior que zero.');
  }
  return result;
}
