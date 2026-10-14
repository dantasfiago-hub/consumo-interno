import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/core/formatting/numbers.dart';
import 'package:consumo_interno/features/consumption/presentation/quantity_fields.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';
import 'package:consumo_interno/features/exports/data/vr_master_serializer.dart';

void main() {
  test('Peso separado mantém a precisão e recusa partes inválidas', () {
    expect(parseWeightParts('2', '350'), 2350);
    expect(parseWeightParts('', '1'), 1);
    expect(parseWeightParts('1', ''), 1000);
    for (final parts in [
      ['0', '0'],
      ['1', '1000'],
      ['1,5', '0'],
      ['1', '-1'],
      ['999999999999', '0'],
    ]) {
      expect(() => parseWeightParts(parts[0], parts[1]), throwsFormatException);
    }
  });
  test('Cozinha e Padaria têm exatamente duas colunas; Horti Fruti quatro', () {
    final row = ExportRow(
      code: '000125',
      description: 'Produto',
      productId: 'p',
      measure: 'KG',
      quantityMilli: BigInt.from(2350),
      totalCents: BigInt.from(7050),
    );
    const base = ExportProfile(validated: true);
    for (final sector in ['cozinha', 'padaria']) {
      final profile = base.forSector(sector);
      expect(utf8.decode(serializeExport([row], profile)), '000125;2,35\r\n');
      expect(ExportProfile.fromJson(profile.toJson()).order, [
        'code',
        'quantity',
      ]);
      expect(profile.validated, true);
    }
    expect(
      utf8.decode(serializeExport([row], base.forSector('hortifruti'))),
      '000125;2,35;1;30\r\n',
    );
    expect(base.order, exportFields);
    expect(
      () => const ExportProfile(order: ['quantity', 'code']).validate(),
      throwsFormatException,
    );
  });
  test(
    'Duas colunas preservam codificação, decimal, cabeçalho e separador',
    () {
      final row = ExportRow(
        code: '0009',
        description: '',
        productId: 'p',
        measure: 'KG',
        quantityMilli: BigInt.from(1),
        totalCents: BigInt.from(1),
      );
      final profile = const ExportProfile(
        separator: '|',
        decimal: '.',
        encoding: 'LATIN1',
        lineEnding: 'LF',
        header: true,
      ).forSector('padaria');
      expect(
        latin1.decode(serializeExport([row], profile)),
        'code|quantity\n0009|0.001\n',
      );
    },
  );
  for (final unit in ['KG', 'UN']) {
    testWidgets(
      'Botões de quantidade $unit não produzem negativos e respeitam limites',
      (tester) async {
        final whole = TextEditingController(text: '0');
        final grams = TextEditingController(text: '999');
        addTearDown(whole.dispose);
        addTearDown(grams.dispose);
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuantityFields(unit: unit, whole: whole, grams: grams),
            ),
          ),
        );
        final id = unit == 'KG' ? 'quantity-kg' : 'quantity-units';
        expect(
          tester
              .widget<IconButton>(find.byKey(ValueKey('$id-minus')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(ValueKey('$id-plus')));
        await tester.pump();
        expect(whole.text, '1');
        await tester.tap(find.byKey(ValueKey('$id-minus')));
        await tester.pump();
        expect(whole.text, '0');
        if (unit == 'KG') {
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('quantity-grams-plus')),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const ValueKey('quantity-grams-minus')));
          await tester.pump();
          expect(grams.text, '998');
          await tester.tap(find.byKey(const ValueKey('quantity-grams-plus')));
          await tester.pump();
          expect(grams.text, '999');
        } else {
          expect(find.byKey(const ValueKey('quantity-grams')), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
