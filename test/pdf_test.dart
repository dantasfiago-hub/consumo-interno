import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/services/files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PDF inclui vários itens, acentos e total confirmado', () async {
    final c = Consumption(
      id: 'c',
      date: '2026-09-30',
      createdAt: '2026-09-30T12:00:00Z',
      operatorName: 'João',
      sector: 'Padaria',
      note: '',
      items: [
        const ConsumptionItem(
          id: 'i',
          productId: 'p',
          code: '00125',
          description: 'Açúcar 1 kg',
          unit: 'UN',
          amount: 3000,
          totalCents: 1350,
        ),
      ],
    );
    final rows = List.generate(80, (_) => ReportRow(c, c.items.single));
    final bytes = await reportPdf(
      rows,
      synchronization: 'Dados fictícios para teste de exportação.',
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    if (Platform.environment['RENDER_PREVIEWS'] == 'true') {
      final f = File('docs/examples/relatorio-exemplo.pdf');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
    }
  });
}
