import 'package:intl/intl.dart';

final brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String money(int cents) => brl.format(cents / 100);
String quantity(int value, String unit) => unit == 'UN'
    ? '${value ~/ 1000}'
    : '${value ~/ 1000},${(value % 1000).toString().padLeft(3, '0')}';

/// Integers throughout persistence. Quantity is thousandths, money is cents.
int parseScaled(String text, int decimals, {bool allowZero = false}) {
  final s = text.trim();
  if (!RegExp(r'^\d+([,.]\d+)?$').hasMatch(s)) {
    throw const FormatException(
      'Informe um número positivo, sem separador de milhar.',
    );
  }
  final parts = s.replaceAll(',', '.').split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) {
    throw FormatException('Use no máximo $decimals casas decimais.');
  }
  final result = int.parse(parts[0] + fraction.padRight(decimals, '0'));
  if (result < 0 || (!allowZero && result == 0) || result > 999999999999) {
    throw const FormatException(
      'Valor deve ser positivo e menor que o limite permitido.',
    );
  }
  return result;
}

int parseQuantity(String text, String unit) {
  if (unit != 'UN' && unit != 'KG') {
    throw const FormatException('Unidade inválida.');
  }
  final value = parseScaled(text, 3);
  if (unit == 'UN' && value % 1000 != 0) {
    throw const FormatException(
      'Produtos em UN aceitam apenas quantidades inteiras.',
    );
  }
  return value;
}

/// Weight parts are integers, with grams strictly between 0 and 999.
int parseWeightParts(String kilograms, String grams) {
  final kg = parseScaled(
    kilograms.trim().isEmpty ? '0' : kilograms,
    0,
    allowZero: true,
  );
  final g = parseScaled(grams.trim().isEmpty ? '0' : grams, 0, allowZero: true);
  if (g > 999) throw const FormatException('Informe de 0 a 999 gramas.');
  final milli = kg * 1000 + g;
  if (milli <= 0 || milli > 999999999999) {
    throw const FormatException(
      'Informe um peso positivo dentro do limite permitido.',
    );
  }
  return milli;
}
