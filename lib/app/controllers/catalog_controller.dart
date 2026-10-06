import '../../domain/models.dart';
import '../../infrastructure/local/database.dart';
import 'session_controller.dart';

class CatalogController {
  final LocalDatabase db;
  final SessionController session;
  CatalogController(this.db, this.session);
  Future<List<Product>> load() async =>
      (await db.products())
          .where(
            (p) =>
                session.canManage ||
                session.accessReady && p.sectorIds.contains(session.sectorId),
          )
          .toList()
        ..sort((a, b) => a.description.compareTo(b.description));
  Future<void> save(Product p, {int expectedVersion = 0}) async {
    if (!session.canManage) {
      throw StateError('Somente administradores podem alterar produtos.');
    }
    await db.saveProduct(p, expectedVersion: expectedVersion);
  }
}
