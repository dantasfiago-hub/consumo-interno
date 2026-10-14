import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';
import 'package:consumo_interno/features/exports/application/prepare_export.dart';
import 'package:consumo_interno/features/exports/data/vr_master_serializer.dart';

ReportRow row(
  String id,
  int amount,
  int cents, {
  String code = '000125',
  String unit = 'UN',
  String product = 'p',
  String status = 'confirmed',
}) {
  final item = ConsumptionItem(
    id: 'i$id',
    productId: product,
    code: code,
    description: 'Produto',
    unit: unit,
    amount: amount,
    totalCents: cents,
  );
  return ReportRow(
    Consumption(
      id: id,
      date: '2026-10-02',
      createdAt: '2026-10-02T12:00:00Z',
      operatorName: 'Ana',
      sector: '',
      note: '',
      items: [item],
      status: status,
    ),
    item,
  );
}

void main() {
  test('Agrupa com média ponderada, preserva código e deduplica origens', () {
    final a = row('a', 2000, 6101), b = row('b', 3000, 9256);
    final result = groupForExport([
      a,
      b,
      a,
      row('c', 1000, 100, status: 'cancelled'),
    ]);
    expect(result.single.quantityMilli, BigInt.from(5000));
    expect(result.single.totalCents, BigInt.from(15357));
    expect(result.single.price4, BigInt.from(307140));
    expect(result.single.difference7, BigInt.zero);
    expect(
      utf8.decode(serializeExport(result, const ExportProfile())),
      '000125;5;1;30,714\r\n',
    );
  });
  test('Preço arredondado até quatro casas com quantidade KG mínima', () {
    expect(unitPrice4(BigInt.from(200), BigInt.from(3000)), BigInt.from(6667));
    expect(unitPrice4(BigInt.from(1), BigInt.from(1)), BigInt.from(100000));
    // Half-up: 0.01 / 32 = 0.0003125 -> 0.0003; exact half at 0.01 / 8 = 0.00125 -> 0.0013.
    expect(unitPrice4(BigInt.from(1), BigInt.from(8000)), BigInt.from(13));
    final result = groupForExport([row('a', 3, 2, unit: 'KG')]);
    expect(
      utf8.decode(serializeExport(result, const ExportProfile())),
      '000125;0,003;1;6,6667\r\n',
    );
    expect(result.single.difference7, BigInt.from(1));
  });
  test('Inteiros grandes não estouram na multiplicação para o preço', () {
    final total = BigInt.parse('999999999999999999999999');
    expect(unitPrice4(total, BigInt.from(1000)), total * BigInt.from(100));
    expect(scaledText(BigInt.from(100000), 4), '10');
  });
  test('Bloqueia mistura de produtos, unidades, zero e UN fracionada', () {
    expect(
      () => groupForExport([
        row('a', 1000, 100),
        row('b', 1000, 100, product: 'outro'),
      ]),
      throwsFormatException,
    );
    expect(
      () => groupForExport([
        row('a', 1000, 100),
        row('b', 1000, 100, unit: 'KG'),
      ]),
      throwsFormatException,
    );
    expect(() => groupForExport([row('a', 1500, 100)]), throwsFormatException);
    expect(() => unitPrice4(BigInt.one, BigInt.zero), throwsFormatException);
  });
  test('Perfil determina bytes, ordem, cabeçalho, decimal e fim de linha', () {
    final rows = groupForExport([row('a', 2000, 6000)]);
    const profile = ExportProfile(
      separator: '|',
      decimal: '.',
      encoding: 'LATIN1',
      lineEnding: 'LF',
      header: true,
      fixedPrice: true,
      order: ['unit_price', 'code', 'unit', 'quantity'],
    );
    expect(
      latin1.decode(serializeExport(rows, profile)),
      'unit_price|code|unit|quantity\n30.0000|000125|1|2\n',
    );
    expect(serializeExport(rows, const ExportProfile(bom: true)).take(3), [
      239,
      187,
      191,
    ]);
    expect(
      () => const ExportProfile(
        order: ['code', 'code', 'unit', 'quantity'],
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => serializeExport(
        groupForExport([row('x', 1000, 100, code: '12;34')]),
        const ExportProfile(),
      ),
      throwsFormatException,
    );
    expect(
      () => serializeExport(
        groupForExport([row('x', 1000, 100, code: '12\n34')]),
        const ExportProfile(),
      ),
      throwsFormatException,
    );
  });
  test('Elegibilidade protege reserva; cancelado libera itens', () {
    final a = row('a', 1000, 100), b = row('b', 1000, 100);
    final batch = {
      'id': 'b',
      'status': 'downloaded',
      'rows': [
        {'consumption': a.consumption.toJson(), 'item': a.item.toJson()},
      ],
    };
    expect(eligibleExportRows([a, a, b], [batch]).length, 1);
    expect(
      eligibleExportRows(
        [a, b],
        [
          {...batch, 'status': 'cancelled'},
        ],
      ).length,
      2,
    );
    expect(
      batchStatusLabel({'status': 'issued'}),
      'Concluído na versão anterior',
    );
  });
}
