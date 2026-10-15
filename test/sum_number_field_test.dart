import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/features/consumption/presentation/quantity_fields.dart';
import 'package:consumo_interno/features/consumption/presentation/sum_number_field.dart';

void main() {
  testWidgets(
    'Soma ao digitar; botões usam resultado e preservam soma incompleta',
    (tester) async {
      final whole = TextEditingController(), grams = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuantityFields(unit: 'UN', whole: whole, grams: grams),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '10+20+5');
      await tester.pump();
      expect(find.text('Resultado: 35 UN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quantity-units-plus')));
      await tester.pump();
      expect(whole.text, '36');
      await tester.tap(find.byKey(const ValueKey('quantity-units-minus')));
      await tester.pump();
      expect(whole.text, '35');
      await tester.enterText(find.byType(TextField), '10+');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('quantity-units-plus')),
            )
            .onPressed,
        isNull,
      );
      expect(whole.text, '10+');
      await tester.enterText(find.byType(TextField), '1,5+2');
      await tester.pump();
      expect(
        find.text('Este campo aceita apenas números inteiros.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      whole.dispose();
      grams.dispose();
    },
  );
  testWidgets('Valor aceita centavos e recalcula ao alterar uma parcela', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SumNumberField(
            controller: controller,
            label: 'Valor',
            decimals: 2,
            format: (cents) => '$cents centavos',
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '0,1+0,2');
    await tester.pump();
    expect(find.text('Resultado: 30 centavos'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '10+20');
    await tester.pump();
    expect(find.text('Resultado: 3000 centavos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('Gramas excedentes preservam a digitação e convertem ao sair', (
    tester,
  ) async {
    final whole = TextEditingController(text: '2+1');
    final grams = TextEditingController(text: '0');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuantityFields(unit: 'KG', whole: whole, grams: grams),
        ),
      ),
    );
    final gramField = find.descendant(
      of: find.byKey(const ValueKey('quantity-grams')),
      matching: find.byType(TextField),
    );
    final kgField = find.descendant(
      of: find.byKey(const ValueKey('quantity-kg')),
      matching: find.byType(TextField),
    );
    await tester.enterText(gramField, '800+700');
    await tester.pump();
    expect(grams.text, '800+700');
    expect(find.text('Resultado: 4 kg e 500 g'), findsOneWidget);
    await tester.tap(kgField);
    await tester.pump();
    expect(whole.text, '4');
    expect(grams.text, '500');
    await tester.enterText(gramField, '1500');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(whole.text, '5');
    expect(grams.text, '500');
    await tester.pumpWidget(const SizedBox());
    whole.dispose();
    grams.dispose();
  });

  testWidgets('Somas incompletas e excesso no limite não alteram os campos', (
    tester,
  ) async {
    final whole = TextEditingController(text: '1');
    final grams = TextEditingController(text: '0');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuantityFields(unit: 'KG', whole: whole, grams: grams),
        ),
      ),
    );
    final gramField = find.descendant(
      of: find.byKey(const ValueKey('quantity-grams')),
      matching: find.byType(TextField),
    );
    final kgField = find.descendant(
      of: find.byKey(const ValueKey('quantity-kg')),
      matching: find.byType(TextField),
    );
    await tester.enterText(gramField, '800+');
    await tester.pump();
    await tester.tap(kgField);
    await tester.pump();
    expect(whole.text, '1');
    expect(grams.text, '800+');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('quantity-grams-plus')))
          .onPressed,
      isNull,
    );
    whole.text = '999999999';
    grams.text = '999';
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('quantity-grams-plus')))
          .onPressed,
      isNull,
    );
    await tester.enterText(gramField, '1000');
    await tester.pump();
    await tester.tap(kgField);
    await tester.pump();
    expect(whole.text, '999999999');
    expect(grams.text, '1000');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    whole.dispose();
    grams.dispose();
  });
}
