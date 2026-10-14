import '../../core/access/sectors.dart';
import '../../infrastructure/local/database.dart';

class SessionController {
  final LocalDatabase db;
  String role = 'unconfigured', sectorId = '';
  bool verified = false;
  SessionController(this.db);
  bool get canManage => verified && role == 'admin';
  bool get accessReady =>
      verified &&
      (role == 'admin' || role == 'operator' && sectors.containsKey(sectorId));
  Future<void> load() async {
    role = await db.setting('role') ?? 'unconfigured';
    sectorId = await db.setting('sector') ?? '';
    final marker = await db.setting('access_verified');
    // A historical binding is a fallback only when no explicit marker exists.
    verified =
        marker == '1' || marker == null && await db.setting('binding') != null;
  }
}
