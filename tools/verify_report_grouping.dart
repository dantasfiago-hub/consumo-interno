// Standalone Dart script; relative imports keep it runnable without Flutter.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/features/reports/domain/report.dart';
import '../lib/features/consumption/domain/consumption.dart';

void check(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

Consumption entry(
  String id,
  String date,
  String sector,
  int amount,
  int cents, {
  String unit = 'KG',
  String status = 'confirmed',
  String product = 'tomate',
  String description = 'Tomate',
}) => Consumption(
  id: id,
  date: date,
  createdAt: '${date}T12:00:00Z',
  operatorName: 'Aparelho',
  sector: sector,
  assignedSector: sector,
  note: '',
  status: status,
  items: [
    ConsumptionItem(
      id: 'item-$id',
      productId: product,
      code: '00123',
      description: description,
      unit: unit,
      amount: amount,
      totalCents: cents,
    ),
  ],
);

void main() {
  final records = [
    entry('a', '2026-10-01', 'hortifruti', 1250, 999),
    entry('b', '2026-10-02', 'cozinha', 2750, 1001, description: 'Tomate novo'),
    entry('c', '2026-10-03', 'hortifruti', 1000, 500, status: 'cancelled'),
    entry('d', '2026-10-04', 'hortifruti', 2000, 900, unit: 'UN'),
    entry('e', '2026-10-05', 'padaria', 1000, 400, product: 'outro'),
  ];
  final all = reportRows(records, ReportFilter()..status = '');
  final grouped = groupReportProducts(all);
  check(grouped.length == 4, 'Separate product identities, units and states');
  final tomato = grouped.singleWhere(
    (s) => s.productId == 'tomate' && s.unit == 'KG' && s.status == 'confirmed',
  );
  check(
    tomato.amount == 4000 && tomato.totalCents == 2000,
    'Exact integer sums',
  );
  check(tomato.consumptionCount == 2, 'Count distinct consumption records');
  check(tomato.description == 'Tomate novo', 'Latest historical label');
  final reversed = groupReportProducts(all.reversed.toList());
  check(
    reportProductsCsv(grouped) == reportProductsCsv(reversed),
    'Stable output regardless of input order',
  );
  final sector = groupReportProducts(
    reportRows(
      records,
      ReportFilter()
        ..sector = 'hortifruti'
        ..unit = 'KG',
    ),
  );
  check(
    sector.length == 1 && sector.single.amount == 1250,
    'Sector, unit and default confirmed filters before aggregation',
  );
  final period = groupReportProducts(
    reportRows(
      records,
      ReportFilter()
        ..from = DateTime(2026, 10, 2)
        ..to = DateTime(2026, 10, 2),
    ),
  );
  check(
    period.length == 1 && period.single.totalCents == 1001,
    'Inclusive period filter',
  );
  check(groupReportProducts([]).isEmpty, 'Empty result');
  final csv = reportProductsCsv(grouped);
  check(
    csv.startsWith('\uFEFF') &&
        csv.contains('"4,000"') &&
        csv.contains('"20,00"') &&
        csv.contains('"00123"'),
    'CSV preserves code and decimal formatting',
  );
  check(
    csv.contains('"Cancelado"') && csv.contains('"Confirmado"'),
    'CSV separates cancellation states',
  );
  check(
    csvCell('=SUM(A1)') == '"\'=SUM(A1)"',
    'Spreadsheet injection protection',
  );
  check(all.first.item.amount == 1250, 'No mutation of source entries');
  print('11 grouped-report checks passed.');
}
