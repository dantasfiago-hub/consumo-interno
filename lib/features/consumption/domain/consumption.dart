import 'package:intl/intl.dart';
import '../../../core/access/sectors.dart';
import '../../../core/types/json.dart';

class ConsumptionItem {
  final String id, productId, code, description, unit;
  final int amount, totalCents;
  const ConsumptionItem({
    required this.id,
    required this.productId,
    required this.code,
    required this.description,
    required this.unit,
    required this.amount,
    required this.totalCents,
  });
  factory ConsumptionItem.fromJson(Json j) => ConsumptionItem(
    id: j['id'],
    productId: j['product_id'],
    code: j['code'],
    description: j['description'],
    unit: j['unit'],
    amount: j['amount'],
    totalCents: j['total_cents'],
  );
  Json toJson() => {
    'id': id,
    'product_id': productId,
    'code': code,
    'description': description,
    'unit': unit,
    'amount': amount,
    'total_cents': totalCents,
  };
}

class Consumption {
  final String id, date, createdAt, operatorName, sector, note, status;
  final String? cancellationReason;
  final List<ConsumptionItem> items;
  final int version;
  final bool exportLocked;
  final String? assignedSector;
  String? get sectorId => assignedSector ?? sectorKey(sector);
  const Consumption({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.operatorName,
    required this.sector,
    required this.note,
    required this.items,
    this.status = 'confirmed',
    this.cancellationReason,
    this.version = 1,
    this.exportLocked = false,
    this.assignedSector,
  });
  int get totalCents => items.fold(0, (a, b) => a + b.totalCents);
  factory Consumption.fromJson(Json j) => Consumption(
    id: j['id'],
    date: j['date'],
    createdAt: j['created_at'],
    operatorName: j['operator'],
    sector: j['sector'],
    note: j['note'],
    status: j['status'] ?? 'confirmed',
    version: j['version'] ?? 1,
    exportLocked: j['_export_locked'] ?? false,
    assignedSector: j['_sector_id'],
    cancellationReason: j['cancellation_reason'],
    items: (j['items'] as List)
        .map((i) => ConsumptionItem.fromJson(Map<String, dynamic>.from(i)))
        .toList(),
  );
  Json toJson() => {
    'id': id,
    'date': date,
    'created_at': createdAt,
    'operator': operatorName,
    'sector': sector,
    'note': note,
    'status': status,
    'cancellation_reason': cancellationReason,
    'version': version,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

void validateConsumption(Consumption c) {
  final parsed = DateTime.tryParse(c.date);
  if (c.id.isEmpty ||
      c.version < 1 ||
      parsed == null ||
      DateFormat('yyyy-MM-dd').format(parsed) != c.date ||
      DateTime.tryParse(c.createdAt) == null ||
      c.operatorName.trim().isEmpty ||
      c.operatorName.length > 100 ||
      c.sector.length > 100 ||
      c.note.length > 500 ||
      !['confirmed', 'cancelled'].contains(c.status) ||
      c.items.isEmpty ||
      c.items.length > 200) {
    throw const FormatException('Lançamento inválido.');
  }
  if (c.status == 'cancelled' &&
      ((c.cancellationReason?.trim().length ?? 0) < 3 ||
          c.cancellationReason!.length > 300)) {
    throw const FormatException('Cancelamento sem justificativa válida.');
  }
  if (c.items.map((i) => i.id).toSet().length != c.items.length ||
      c.items.map((i) => i.productId).toSet().length != c.items.length) {
    throw const FormatException('Itens repetidos.');
  }
  for (final i in c.items) {
    if (i.id.isEmpty ||
        i.productId.isEmpty ||
        i.code.trim().isEmpty ||
        i.code.length > 40 ||
        i.description.trim().isEmpty ||
        i.description.length > 150 ||
        i.amount <= 0 ||
        i.totalCents <= 0 ||
        i.amount > 999999999999 ||
        i.totalCents > 999999999999 ||
        !['UN', 'KG'].contains(i.unit) ||
        (i.unit == 'UN' && i.amount % 1000 != 0)) {
      throw const FormatException(
        'Quantidade, valor ou identificação do item inválida.',
      );
    }
  }
}
