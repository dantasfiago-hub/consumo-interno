import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/consumption/label/presentation/label_scanner.dart';
import 'package:consumo_interno/features/consumption/label/presentation/label_text_recognizer.dart';
import 'package:consumo_interno/features/consumption/presentation/entry_page.dart';
import 'package:consumo_interno/features/consumption/presentation/sum_number_field.dart';
import 'package:consumo_interno/features/consumption/label/domain/scale_label.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

const scaleProduct = Product(
  id: 'bacon',
  code: '39900',
  description: 'BACON AURORA F 250G',
  unit: 'KG',
  sectorIds: ['padaria', 'hortifruti'],
);

const exampleText = r'''
TARA: 0,014kg (T)
PESO: 0,250kg (L)
PREÇO/kg R$: 71,96
TOTAL R$: 17,99
''';

class FakeLabelScanner implements LabelScanner {
  final String barcode;

  FakeLabelScanner(this.barcode);

  @override
  Future<LabelCameraCapture?> scan(BuildContext context) async =>
      LabelCameraCapture(barcode: barcode, image: Uint8List.fromList([1]));
}

class FakeLabelTextRecognizer implements LabelTextRecognizer {
  final String? text;

  FakeLabelTextRecognizer(this.text);

  @override
  Future<String?> recognize(Uint8List imageBytes) async => text;
}

void main() {
  Future<Future<ItemPickerResult?>> openLabelPicker(
    WidgetTester tester, {
    required String sector,
    required bool requiresPrice,
    required LabelTextRecognizer recognizer,
  }) async {
    final result = Completer<ItemPickerResult?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showDialog<ItemPickerResult>(
                  context: context,
                  builder: (_) => ItemPicker(
                    products: [scaleProduct],
                    allProducts: [scaleProduct],
                    sectorId: sector,
                    labelFormat: const ScaleLabelFormat(),
                    scannedBarcodes: <String>{},
                    labelScanner: FakeLabelScanner('2039900017991'),
                    labelTextRecognizer: recognizer,
                    requiresPrice: requiresPrice,
                  ),
                ).then(result.complete);
              },
              child: const Text('Abrir seletor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir seletor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ler etiqueta'));
    await tester.pumpAndSettle();
    return result.future;
  }

  testWidgets('Padaria adds OCR weight without a value field', (tester) async {
    final pending = await openLabelPicker(
      tester,
      sector: 'padaria',
      requiresPrice: false,
      recognizer: FakeLabelTextRecognizer(exampleText),
    );
    expect(find.text('Confirmar etiqueta'), findsOneWidget);
    expect(find.text('Valor total (R\$)'), findsNothing);
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    final result = await pending;
    expect(result!.item.amount, 250);
    expect(result.item.totalCents, 0);
    expect(result.scannedBarcode, '2039900017991');
  });

  testWidgets('Horti Fruti adds OCR weight and barcode value', (tester) async {
    final pending = await openLabelPicker(
      tester,
      sector: 'hortifruti',
      requiresPrice: true,
      recognizer: FakeLabelTextRecognizer(exampleText),
    );
    final valueTextFields = tester.widgetList<EditableText>(
      find.byType(EditableText),
    );
    expect(
      valueTextFields.any((field) => field.controller.text == '17,99'),
      isTrue,
    );
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    final result = await pending;
    expect(result!.item.amount, 250);
    expect(result.item.totalCents, 1799);
  });

  testWidgets('inconsistent OCR values require explicit review', (
    tester,
  ) async {
    final pending = await openLabelPicker(
      tester,
      sector: 'hortifruti',
      requiresPrice: true,
      recognizer: FakeLabelTextRecognizer(r'''
PESO 0,250kg (L)
PRECO/kg R$: 71,96
TOTAL R$: 18,99
'''),
    );

    expect(
      find.textContaining('não confere. Revise os valores'),
      findsOneWidget,
    );
    final addButton = find.widgetWithText(FilledButton, 'Adicionar');
    expect(tester.widget<FilledButton>(addButton).onPressed, isNull);
    final acknowledgement = find.text('Revisei a quantidade e o valor');
    await tester.ensureVisible(acknowledgement);
    await tester.pumpAndSettle();
    await tester.tap(acknowledgement);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final result = await pending;
    expect(result!.item.amount, 250);
    expect(result.item.totalCents, 1799);
  });

  testWidgets('OCR failure leaves a focused manual quantity field', (
    tester,
  ) async {
    final pending = await openLabelPicker(
      tester,
      sector: 'padaria',
      requiresPrice: false,
      recognizer: FakeLabelTextRecognizer(null),
    );
    expect(
      find.textContaining('Não foi possível ler o texto da etiqueta'),
      findsOneWidget,
    );
    final quantityField = tester.widget<SumNumberField>(
      find.byKey(const ValueKey('quantity-kg')),
    );
    expect(quantityField.focusNode!.hasFocus, isTrue);
    final gramsField = find.descendant(
      of: find.byKey(const ValueKey('quantity-grams')),
      matching: find.byType(TextField),
    );
    await tester.enterText(gramsField, '250');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    final result = await pending;
    expect(result!.item.amount, 250);
  });

  testWidgets('typed or USB barcode enters the same review flow', (
    tester,
  ) async {
    final result = Completer<ItemPickerResult?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () {
                showDialog<ItemPickerResult>(
                  context: context,
                  builder: (_) => ItemPicker(
                    products: [scaleProduct],
                    allProducts: [scaleProduct],
                    sectorId: 'padaria',
                    labelFormat: const ScaleLabelFormat(),
                    scannedBarcodes: <String>{},
                    labelTextRecognizer: FakeLabelTextRecognizer(null),
                    requiresPrice: false,
                  ),
                ).then(result.complete);
              },
              child: const Text('Abrir seletor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir seletor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('barcode-input')),
      '2039900017991',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Confirmar etiqueta'), findsOneWidget);
    expect(
      find.textContaining('Sem imagem para leitura do peso'),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('quantity-grams')),
        matching: find.byType(TextField),
      ),
      '250',
    );
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    final selected = await result.future;
    expect(selected!.item.amount, 250);
    expect(selected.item.totalCents, 0);
  });

  testWidgets('repeated label can be summed into the existing item', (
    tester,
  ) async {
    final database = LocalDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    final state = AppState(database);
    state.session.role = 'operator';
    state.session.sectorId = 'hortifruti';
    state.session.verified = true;
    state.products = [scaleProduct];
    addTearDown(() async {
      state.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EntryPage(
          state: state,
          labelScanner: FakeLabelScanner('2039900017991'),
          labelTextRecognizer: FakeLabelTextRecognizer(exampleText),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Selecionar produto'));
    await tester.tap(find.text('Selecionar produto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ler etiqueta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Adicionar produto'));
    await tester.tap(find.text('Adicionar produto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ler etiqueta'));
    await tester.pumpAndSettle();
    expect(find.text('Etiqueta já lida'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Somar à quantidade existente'), findsOneWidget);
    await tester.tap(find.text('Somar à quantidade existente'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0,500 KG'), findsOneWidget);
    expect(find.textContaining('35,98'), findsNWidgets(2));
  });
}
