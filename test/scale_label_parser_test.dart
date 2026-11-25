import 'package:flutter_test/flutter_test.dart';

import 'package:consumo_interno/features/consumption/label/domain/scale_label.dart';
import 'package:consumo_interno/features/consumption/label/domain/scale_label_text.dart';

void main() {
  group('ScaleLabelParser', () {
    const parser = ScaleLabelParser();

    test('parses internal code and total cents from EAN-13', () {
      final label = parser.parse('2039900017991');

      expect(label.rawBarcode, '2039900017991');
      expect(label.internalCode, '039900');
      expect(label.totalCents, 1799);
      expect(label.weightMilli, isNull);
      expect(label.checkDigitOk, isTrue);
    });

    test('rejects invalid length, characters, prefix, and check digit', () {
      for (final barcode in [
        '12',
        '20399000179912',
        '20399000179A1',
        '0039900017991',
        '2039900017992',
      ]) {
        expect(() => parser.parse(barcode), throwsFormatException);
      }
    });

    test('supports a numeric field containing grams', () {
      const weightParser = ScaleLabelParser(
        format: ScaleLabelFormat(
          numericField: ScaleLabelNumericField.weightGrams,
        ),
      );
      final label = weightParser.parse('2039900002508');

      expect(label.internalCode, '039900');
      expect(label.totalCents, isNull);
      expect(label.weightMilli, 250);
      expect(label.checkDigitOk, isTrue);
    });

    test('validates and round-trips the configurable layout', () {
      const format = ScaleLabelFormat(
        prefix: '20',
        internalCodeLength: 5,
        numericFieldLength: 5,
        numericField: ScaleLabelNumericField.weightGrams,
      );

      expect(
        ScaleLabelFormat.decode(format.encode()).toJson(),
        format.toJson(),
      );
      expect(
        () => ScaleLabelParser(
          format: const ScaleLabelFormat(prefix: '2', internalCodeLength: 5),
        ).parse('2039900017991'),
        throwsFormatException,
      );
    });
  });

  group('ScaleLabelTextParser', () {
    const parser = ScaleLabelTextParser();

    test('extracts net weight, unit price, and total; ignores tare', () {
      final text = parser.parse(r'''
TARA: 0,014kg (T)
PESO: 0,250kg (L)
PREÇO/kg R$: 71,96
TOTAL R$: 17,99
''');

      expect(text.weightMilli, 250);
      expect(text.pricePerKgCents, 7196);
      expect(text.totalCents, 1799);
      expect(text.isConsistent, isTrue);

      expect(
        parser.parse(r'''
PESO 0,250kg (L)
PRECO/kg R$: 71,96
TOTAL R$: 18,00
''').isConsistent,
        isTrue,
      );
    });

    test('accepts OCR noise and flags inconsistent printed values', () {
      final text = parser.parse(r'''
0.014kg(T)
0.250 kg (1)
PRECO / kg R$ 71,96
TOTAL R$: 18,99
''');

      expect(text.weightMilli, 250);
      expect(text.pricePerKgCents, 7196);
      expect(text.totalCents, 1899);
      expect(text.isConsistent, isFalse);
    });
  });
}
