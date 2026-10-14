import '../../../core/access/sectors.dart';
import '../../consumption/domain/consumption.dart';
import '../../../core/formatting/numbers.dart';

class ReportFilter {
  String query = '',
      sector = '',
      operatorName = '',
      status = 'confirmed',
      unit = '';
  DateTime? from, to;
  int? minCents, maxCents;
  bool accepts(Consumption c, ConsumptionItem i) {
    final d = DateTime.parse(c.date);
    return (from == null || !d.isBefore(from!)) &&
        (to == null || !d.isAfter(to!)) &&
        (status.isEmpty || c.status == status) &&
        (sectorKey(sector) != null
            ? c.sectorId == sectorKey(sector)
            : sectorLabel(c.assignedSector ?? c.sector)
                  .toLowerCase()
                  .contains(sector.toLowerCase())) &&
        c.operatorName.toLowerCase().contains(operatorName.toLowerCase()) &&
        '${i.code} ${i.description}'.toLowerCase().contains(
          query.toLowerCase(),
        ) &&
        (unit.isEmpty || i.unit == unit) &&
        (minCents == null || i.totalCents >= minCents!) &&
        (maxCents == null || i.totalCents <= maxCents!);
  }
}

class ReportRow {
  final Consumption consumption;
  final ConsumptionItem item;
  const ReportRow(this.consumption, this.item);
}

List<ReportRow> reportRows(List<Consumption> records, ReportFilter f) => [
  for (final c in records)
    for (final i in c.items)
      if (f.accepts(c, i)) ReportRow(c, i),
];

String csvCell(Object? value) {
  var s = value?.toString() ?? '';
  // Prevent spreadsheet formula execution in descriptive fields.
  if (RegExp(r'^[\s]*[=+@\-\t\r]').hasMatch(s)) s = "'$s";
  return '"${s.replaceAll('"', '""')}"';
}

String reportCsv(List<ReportRow> rows) =>
    '\uFEFF${[
      ['ID lançamento', 'ID item', 'Data', 'Código', 'Descrição', 'Unidade', 'Quantidade', 'Valor total (R\$)', 'Setor', 'Responsável', 'Situação'],
      ...rows.map((r) => [r.consumption.id, r.item.id, r.consumption.date, r.item.code, r.item.description, r.item.unit, quantity(r.item.amount, r.item.unit), (r.item.totalCents / 100).toStringAsFixed(2).replaceAll('.', ','), sectorLabel(r.consumption.assignedSector ?? r.consumption.sector), r.consumption.operatorName, r.consumption.status == 'confirmed' ? 'Confirmado' : 'Cancelado']),
    ].map((r) => r.map(csvCell).join(';')).join('\r\n')}';

/// A product's historical totals; units and cancellation states never mix.
class ReportProductSummary {
  final String productId, code, description, unit, status;
  final int amount, totalCents, consumptionCount;
  const ReportProductSummary({
    required this.productId,
    required this.code,
    required this.description,
    required this.unit,
    required this.status,
    required this.amount,
    required this.totalCents,
    required this.consumptionCount,
  });
}

List<ReportProductSummary> groupReportProducts(List<ReportRow> rows) {
  final groups = <(String, String, String), List<ReportRow>>{};
  for (final row in rows) {
    final key = (row.item.productId, row.item.unit, row.consumption.status);
    groups.putIfAbsent(key, () => []).add(row);
  }
  final result = <ReportProductSummary>[];
  for (final group in groups.values) {
    // Use the latest matching snapshot when a product was renamed.
    group.sort((a, b) {
      var order = b.consumption.date.compareTo(a.consumption.date);
      if (order == 0) {
        order = b.consumption.createdAt.compareTo(a.consumption.createdAt);
      }
      if (order == 0) {
        order = b.consumption.id.compareTo(a.consumption.id);
      }
      return order;
    });
    final latest = group.first;
    result.add(
      ReportProductSummary(
        productId: latest.item.productId,
        code: latest.item.code,
        description: latest.item.description,
        unit: latest.item.unit,
        status: latest.consumption.status,
        amount: group.fold<int>(0, (sum, row) => sum + row.item.amount),
        totalCents: group.fold<int>(0, (sum, row) => sum + row.item.totalCents),
        consumptionCount: group.map((row) => row.consumption.id).toSet().length,
      ),
    );
  }
  result.sort((a, b) {
    var order = a.code.compareTo(b.code);
    if (order == 0) order = a.productId.compareTo(b.productId);
    if (order == 0) order = a.unit.compareTo(b.unit);
    if (order == 0) order = a.status.compareTo(b.status);
    return order;
  });
  return result;
}

String reportProductsCsv(List<ReportProductSummary> summaries) =>
    '\uFEFF${[
      ['Código', 'Descrição', 'Unidade', 'Quantidade total', 'Valor total (R\$)', 'Lançamentos', 'Situação'],
      ...summaries.map((s) => [s.code, s.description, s.unit, quantity(s.amount, s.unit), (s.totalCents / 100).toStringAsFixed(2).replaceAll('.', ','), s.consumptionCount, s.status == 'confirmed' ? 'Confirmado' : 'Cancelado']),
    ].map((r) => r.map(csvCell).join(';')).join('\r\n')}';
