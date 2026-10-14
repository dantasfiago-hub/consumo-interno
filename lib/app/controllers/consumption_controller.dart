import '../../domain/models.dart';
import '../../infrastructure/local/database.dart';
import 'session_controller.dart';

class ConsumptionController {
  final LocalDatabase db;
  final SessionController session;
  ConsumptionController(this.db, this.session);
  Future<List<Consumption>> load() async =>
      (await db.consumptions())
          .where(
            (c) =>
                session.canManage ||
                session.accessReady && c.sectorId == session.sectorId,
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  bool canCancel(Consumption c) =>
      session.accessReady &&
      c.status == 'confirmed' &&
      !c.exportLocked &&
      (session.canManage || c.sectorId == session.sectorId);
  Future<void> save(Consumption c, List<Product> products) async {
    if (!session.accessReady ||
        c.sectorId == null ||
        !session.canManage && c.sectorId != session.sectorId) {
      throw StateError('Você só pode lançar consumos do setor autorizado.');
    }
    final allowed = products
        .where((p) => p.active && p.sectorIds.contains(c.sectorId))
        .map((p) => p.id)
        .toSet();
    if (!c.items.every((i) => allowed.contains(i.productId))) {
      throw StateError('Produto não autorizado para este setor.');
    }
    await db.saveConsumption(c);
  }

  Future<void> cancel(Consumption c, String reason, List<Json> batches) async {
    if (!canCancel(c)) {
      throw StateError(
        'Cancelamento não autorizado ou consumo protegido por exportação.',
      );
    }
    if (batches.any(
      (b) =>
          b['status'] != 'cancelled' &&
          (b['rows'] as List).any((r) => r['consumption']['id'] == c.id),
    )) {
      throw StateError(
        'Consumo já incluído em lote de exportação. Consulte o administrador.',
      );
    }
    await db.cancelConsumption(c, reason);
  }
}
