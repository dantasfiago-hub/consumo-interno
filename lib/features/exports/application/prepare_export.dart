import '../domain/export.dart';
import '../../reports/domain/report.dart';
import '../../../core/types/json.dart';

List<ReportRow> eligibleExportRows(List<ReportRow> rows, List<Json> batches) {
  final reserved = {
    for (final b in batches)
      if (b['status'] != 'cancelled')
        for (final r in b['rows'] as List)
          '${r['consumption']['id']}/${r['item']['id']}',
  };
  final unique = <String, ReportRow>{};
  for (final r in rows) {
    final key = '${r.consumption.id}/${r.item.id}';
    if (r.consumption.status == 'confirmed' && !reserved.contains(key)) {
      unique[key] = r;
    }
  }
  return unique.values.toList();
}

List<ExportRow> groupForExport(List<ReportRow> rows) {
  final groups = <String, ExportRow>{};
  final seen = <String>{};
  for (final r in rows) {
    if (r.consumption.status != 'confirmed') continue;
    if (!seen.add('${r.consumption.id}/${r.item.id}')) continue;
    final i = r.item;
    if (i.amount <= 0 ||
        i.totalCents <= 0 ||
        !['UN', 'KG'].contains(i.unit) ||
        (i.unit == 'UN' && i.amount % 1000 != 0)) {
      throw const FormatException(
        'Quantidade ou valor inválido para exportação.',
      );
    }
    final previous = groups[i.code];
    if (previous != null &&
        (previous.productId != i.productId || previous.measure != i.unit)) {
      throw FormatException(
        'Código ${i.code} representa produtos ou unidades diferentes. Revise o cadastro antes de exportar.',
      );
    }
    groups[i.code] = ExportRow(
      code: i.code,
      description: i.description,
      productId: i.productId,
      measure: i.unit,
      quantityMilli:
          (previous?.quantityMilli ?? BigInt.zero) + BigInt.from(i.amount),
      totalCents:
          (previous?.totalCents ?? BigInt.zero) + BigInt.from(i.totalCents),
    );
  }
  return groups.values.toList()..sort((a, b) => a.code.compareTo(b.code));
}
