import 'package:flutter_test/flutter_test.dart';

import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/consumption/label/application/scale_label_service.dart';

void main() {
  const service = ScaleLabelService();
  const product = Product(
    id: 'bacon',
    code: '39900',
    description: 'BACON AURORA F 250G',
    unit: 'KG',
    sectorIds: ['padaria', 'hortifruti'],
  );
  const barcode = '2039900017991';

  test('matches product codes after removing leading zeroes', () {
    final result = service.resolve(
      barcode: barcode,
      products: [product],
      sector: 'padaria',
      printedText: 'PESO 0,250kg (L)',
    );

    expect(result.product.id, 'bacon');
    expect(result.suggestedWeightMilli, 250);
    expect(result.weightSource, 'lido da etiqueta');
  });

  test('reports inactive, other-sector, and missing products clearly', () {
    expect(
      () => service.resolve(
        barcode: barcode,
        products: [
          const Product(
            id: 'bacon',
            code: '39900',
            description: 'BACON AURORA F 250G',
            unit: 'KG',
            active: false,
            sectorIds: ['padaria', 'hortifruti'],
          ),
        ],
        sector: 'padaria',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('inativo'),
        ),
      ),
    );
    expect(
      () => service.resolve(
        barcode: barcode,
        products: [
          const Product(
            id: 'bacon',
            code: '39900',
            description: 'BACON AURORA F 250G',
            unit: 'KG',
            sectorIds: ['cozinha'],
          ),
        ],
        sector: 'padaria',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('não está cadastrado neste setor'),
        ),
      ),
    );
    expect(
      () => service.resolve(barcode: barcode, products: [], sector: 'padaria'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('não está cadastrado neste setor'),
        ),
      ),
    );
  });

  test('builds quantity-only and priced consumption items', () {
    final resolution = service.resolve(
      barcode: barcode,
      products: [product],
      sector: 'padaria',
      printedText: '0,250 kg (L)',
    );
    final bakeryItem = service.createItem(
      resolution: resolution,
      whole: '0',
      grams: '250',
      total: '',
      requiresPrice: false,
    );
    final produceItem = service.createItem(
      resolution: resolution,
      whole: '0',
      grams: '250',
      total: '17,99',
      requiresPrice: true,
    );

    expect(bakeryItem.amount, 250);
    expect(bakeryItem.totalCents, 0);
    expect(produceItem.amount, 250);
    expect(produceItem.totalCents, 1799);
  });

  test(
    'calculates quantity from total and unit price when OCR misses weight',
    () {
      final result = service.resolve(
        barcode: barcode,
        products: [product],
        sector: 'padaria',
        printedText: r'PRECO/kg R$: 71,96',
      );

      expect(result.suggestedWeightMilli, 250);
      expect(result.weightSource, 'calculado');
    },
  );

  test('does not use a printed weight for products sold by unit', () {
    const unitProduct = Product(
      id: 'egg',
      code: '39900',
      description: 'Ovo',
      unit: 'UN',
      sectorIds: ['padaria'],
    );
    final result = service.resolve(
      barcode: barcode,
      products: [unitProduct],
      sector: 'padaria',
      printedText: 'PESO 0,250kg (L)',
    );

    expect(result.suggestedWeightMilli, isNull);
    final item = service.createItem(
      resolution: result,
      whole: '2',
      grams: '250',
      total: '',
      requiresPrice: false,
    );
    expect(item.amount, 2000);
  });
}
