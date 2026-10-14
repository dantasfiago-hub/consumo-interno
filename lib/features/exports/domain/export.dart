import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../core/types/json.dart';
import '../../consumption/domain/consumption.dart';
import '../../reports/domain/report.dart';

const exportFields = ['code', 'quantity', 'unit', 'unit_price'];
const quantityExportFields = ['code', 'quantity'];

class ExportProfile {
  final int version;
  final String separator, decimal, encoding, lineEnding;
  final bool header, bom, fixedPrice, validated;
  final List<String> order;
  const ExportProfile({
    this.version = 1,
    this.separator = ';',
    this.decimal = ',',
    this.encoding = 'UTF8',
    this.lineEnding = 'CRLF',
    this.header = false,
    this.bom = false,
    this.fixedPrice = false,
    this.validated = false,
    this.order = exportFields,
  });
  factory ExportProfile.fromJson(Json j) => ExportProfile(
    version: j['version'] ?? 1,
    separator: j['separator'] ?? ';',
    decimal: j['decimal'] ?? ',',
    encoding: j['encoding'] ?? 'UTF8',
    lineEnding: j['line_ending'] ?? 'CRLF',
    header: j['header'] ?? false,
    bom: j['bom'] ?? false,
    fixedPrice: j['fixed_price'] ?? false,
    validated: j['validated'] ?? false,
    order: List<String>.from(j['order'] ?? exportFields),
  );
  Json toJson() => {
    'version': version,
    'separator': separator,
    'decimal': decimal,
    'encoding': encoding,
    'line_ending': lineEnding,
    'header': header,
    'bom': bom,
    'fixed_price': fixedPrice,
    'validated': validated,
    'order': order,
  };
  bool get quantityOnly => order.length == 2;
  ExportProfile forSector(String sector) => ExportProfile.fromJson({
    ...toJson(),
    'order': ['cozinha', 'padaria'].contains(sector)
        ? quantityExportFields
        : quantityOnly
        ? exportFields
        : order,
  });
  void validate() {
    if (version < 1 ||
        ![';', '|', '\t'].contains(separator) ||
        ![',', '.'].contains(decimal) ||
        !['UTF8', 'LATIN1'].contains(encoding) ||
        !['CRLF', 'LF'].contains(lineEnding) ||
        (bom && encoding != 'UTF8') ||
        !((order.length == 4 &&
                order.toSet().length == 4 &&
                order.every(exportFields.contains)) ||
            (order.length == 2 &&
                order[0] == 'code' &&
                order[1] == 'quantity'))) {
      throw const FormatException(
        'Perfil de exportação inválido. Use quatro campos ou código e quantidade.',
      );
    }
  }
}

String scaledText(
  BigInt value,
  int scale, {
  String decimal = ',',
  bool fixed = false,
}) {
  final negative = value.isNegative;
  final digits = value.abs().toString().padLeft(scale + 1, '0');
  if (scale == 0) return '${negative ? '-' : ''}$digits';
  var fraction = digits.substring(digits.length - scale);
  if (!fixed) fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}${digits.substring(0, digits.length - scale)}${fraction.isEmpty ? '' : '$decimal$fraction'}';
}

BigInt unitPrice4(BigInt totalCents, BigInt quantityMilli) {
  if (totalCents <= BigInt.zero || quantityMilli <= BigInt.zero) {
    throw const FormatException('Quantidade e valor devem ser positivos.');
  }
  final numerator = totalCents * BigInt.from(100000);
  final remainder = numerator % quantityMilli;
  return numerator ~/ quantityMilli +
      (remainder * BigInt.two >= quantityMilli ? BigInt.one : BigInt.zero);
}

class ExportRow {
  final String code, description, productId, measure;
  final BigInt quantityMilli, totalCents;
  const ExportRow({
    required this.code,
    required this.description,
    required this.productId,
    required this.measure,
    required this.quantityMilli,
    required this.totalCents,
  });
  BigInt get price4 => unitPrice4(totalCents, quantityMilli);
  // Difference in ten-millionths of a real, exactly computed.
  BigInt get difference7 =>
      price4 * quantityMilli - totalCents * BigInt.from(100000);
}

List<ReportRow> batchSourceRows(Json batch) => (batch['rows'] as List)
    .map(
      (r) => ReportRow(
        Consumption.fromJson(Map<String, dynamic>.from(r['consumption'])),
        ConsumptionItem.fromJson(Map<String, dynamic>.from(r['item'])),
      ),
    )
    .toList();

String batchStatusLabel(Json batch) => switch (batch['status']) {
  'issued' => 'Concluído na versão anterior',
  'cancelled' => 'Cancelado',
  'ready' => 'Gravação autorizada',
  'downloaded' => 'Arquivo salvo',
  'imported' => 'Importação confirmada pelo usuário',
  _ => 'Reservado',
};

class ExportArtifact {
  final String name, hash;
  final List<int> bytes;
  ExportArtifact._(this.name, this.hash, this.bytes);
  factory ExportArtifact.fromJson(Json json) {
    final bytes = base64Decode(json['base64'] as String);
    final hash = sha256.convert(bytes).toString();
    if (hash != json['sha256'] || bytes.length != json['size']) {
      throw const FormatException(
        'Arquivo do lote inválido. Sincronize e tente novamente.',
      );
    }
    final name = json['name'] as String;
    if (!RegExp(
      r'^consumo_(?:(?:hortifruti|cozinha|padaria)_)?[0-9a-fA-F-]+\.txt$',
    ).hasMatch(name)) {
      throw const FormatException('Nome de arquivo do lote inválido.');
    }
    return ExportArtifact._(name, hash, List.unmodifiable(bytes));
  }
}
