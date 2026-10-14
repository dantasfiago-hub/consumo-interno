import 'dart:convert';
import '../domain/export.dart';

List<int> serializeExport(List<ExportRow> rows, ExportProfile profile) {
  profile.validate();
  final lines = <String>[];
  if (profile.header) lines.add(profile.order.join(profile.separator));
  for (final r in rows) {
    if (r.code.isEmpty ||
        r.code.contains(profile.separator) ||
        RegExp(r'[\r\n\x00-\x1f\x7f]').hasMatch(r.code)) {
      throw FormatException(
        'Código ${r.code} contém caracteres incompatíveis com o arquivo.',
      );
    }
    final fields = {
      'code': r.code,
      'quantity': scaledText(r.quantityMilli, 3, decimal: profile.decimal),
      'unit': '1',
      'unit_price': scaledText(
        r.price4,
        4,
        decimal: profile.decimal,
        fixed: profile.fixedPrice,
      ),
    };
    lines.add(profile.order.map((f) => fields[f]!).join(profile.separator));
  }
  final end = profile.lineEnding == 'CRLF' ? '\r\n' : '\n';
  final text = '${profile.bom ? '\uFEFF' : ''}${lines.join(end)}$end';
  return profile.encoding == 'UTF8' ? utf8.encode(text) : latin1.encode(text);
}
