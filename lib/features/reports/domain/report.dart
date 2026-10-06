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
            : sectorLabel(
                c.assignedSector ?? c.sector,
              ).toLowerCase().contains(sector.toLowerCase())) &&
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
