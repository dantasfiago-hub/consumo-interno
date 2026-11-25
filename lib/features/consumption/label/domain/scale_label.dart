import 'dart:convert';

enum ScaleLabelNumericField { totalCents, weightGrams }

class ScaleLabelFormat {
  final String prefix;
  final int internalCodeLength;
  final int numericFieldLength;
  final ScaleLabelNumericField numericField;

  const ScaleLabelFormat({
    this.prefix = '2',
    this.internalCodeLength = 6,
    this.numericFieldLength = 5,
    this.numericField = ScaleLabelNumericField.totalCents,
  });

  void validate() {
    if (!RegExp(r'^\d{1,4}$').hasMatch(prefix) ||
        internalCodeLength < 1 ||
        numericFieldLength < 1 ||
        prefix.length + internalCodeLength + numericFieldLength != 12) {
      throw const FormatException(
        'O layout deve ocupar os 12 dígitos de dados do EAN-13.',
      );
    }
  }

  Map<String, Object> toJson() => {
    'prefix': prefix,
    'internal_code_length': internalCodeLength,
    'numeric_field_length': numericFieldLength,
    'numeric_field': numericField.name,
  };

  String encode() => jsonEncode(toJson());

  factory ScaleLabelFormat.decode(String value) {
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Configuração do layout inválida.');
    }
    final field = ScaleLabelNumericField.values
        .where((candidate) => candidate.name == json['numeric_field'])
        .firstOrNull;
    if (field == null) {
      throw const FormatException('Campo numérico do layout inválido.');
    }
    final format = ScaleLabelFormat(
      prefix: json['prefix'] as String,
      internalCodeLength: json['internal_code_length'] as int,
      numericFieldLength: json['numeric_field_length'] as int,
      numericField: field,
    );
    format.validate();
    return format;
  }
}

class ScaleLabel {
  final String rawBarcode;
  final String internalCode;
  final int? totalCents;
  final int? weightMilli;
  final bool checkDigitOk;

  const ScaleLabel({
    required this.rawBarcode,
    required this.internalCode,
    required this.totalCents,
    required this.weightMilli,
    required this.checkDigitOk,
  });
}

class ScaleLabelParser {
  final ScaleLabelFormat format;

  const ScaleLabelParser({this.format = const ScaleLabelFormat()});

  ScaleLabel parse(String input) {
    format.validate();
    final barcode = input.trim();
    if (barcode.length != 13) {
      throw const FormatException('O código da etiqueta deve ter 13 dígitos.');
    }
    if (!RegExp(r'^\d{13}$').hasMatch(barcode)) {
      throw const FormatException('O código da etiqueta deve conter números.');
    }
    if (!barcode.startsWith(format.prefix)) {
      throw FormatException(
        'A etiqueta deve começar com o prefixo ${format.prefix}.',
      );
    }
    final expectedDigit = _checkDigit(barcode.substring(0, 12));
    if (int.parse(barcode[12]) != expectedDigit) {
      throw const FormatException(
        'O dígito verificador da etiqueta não confere.',
      );
    }
    final codeStart = format.prefix.length;
    final codeEnd = codeStart + format.internalCodeLength;
    final field = int.parse(barcode.substring(codeEnd, 12));
    return ScaleLabel(
      rawBarcode: barcode,
      internalCode: barcode.substring(codeStart, codeEnd),
      totalCents: format.numericField == ScaleLabelNumericField.totalCents
          ? field
          : null,
      weightMilli: format.numericField == ScaleLabelNumericField.weightGrams
          ? field
          : null,
      checkDigitOk: true,
    );
  }

  static int _checkDigit(String firstTwelve) {
    var sum = 0;
    for (var index = 0; index < firstTwelve.length; index++) {
      final digit = int.parse(firstTwelve[index]);
      sum += digit * (index.isOdd ? 3 : 1);
    }
    return (10 - sum % 10) % 10;
  }
}
