import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/domain/models.dart';

void main() {
  test('KG é exato, UN exige inteiro e dinheiro é centavos', () {
    expect(parseQuantity('2,350', 'KG'), 2350);
    expect(parseQuantity('0,001', 'KG'), 1);
    expect(parseQuantity('3', 'UN'), 3000);
    expect(parseScaled('70,50', 2), 7050);
    expect(() => parseQuantity('1,5', 'UN'), throwsFormatException);
    expect(() => parseQuantity('1,0001', 'KG'), throwsFormatException);
    for (final s in ['0', '-1', 'NaN', '1e3', '1.000,00', '']) {
      expect(() => parseScaled(s, 2), throwsFormatException);
    }
    expect(() => parseScaled('10,001', 2), throwsFormatException);
  });
  test('CSV escapa aspas, delimitadores e fórmulas', () {
    expect(csvCell('Arroz; "especial"'), '"Arroz; ""especial"""');
    expect(csvCell('=HYPERLINK("a")'), '"\'=HYPERLINK(""a"")"');
  });
  test('Filtros de data são inclusivos e o total é por item', () {
    const i = ConsumptionItem(
      id: 'i',
      productId: 'p',
      code: '001',
      description: 'Carne',
      unit: 'KG',
      amount: 2350,
      totalCents: 7050,
    );
    final c = Consumption(
      id: 'c',
      date: '2026-09-30',
      createdAt: '2026-09-30T12:00:00Z',
      operatorName: 'Ana',
      sector: 'Padaria',
      note: '',
      items: [i],
    );
    final f = ReportFilter()
      ..from = DateTime(2026, 9, 30)
      ..to = DateTime(2026, 9, 30)
      ..query = '001'
      ..unit = 'KG'
      ..minCents = 7000;
    expect(reportRows([c], f).length, 1);
    expect(c.totalCents, 7050);
    f.maxCents = 7000;
    expect(reportRows([c], f), isEmpty);
    f.maxCents = null;
    f.status = 'cancelled';
    expect(reportRows([c], f), isEmpty);
  });
}
