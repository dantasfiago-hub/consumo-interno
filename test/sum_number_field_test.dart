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
}
