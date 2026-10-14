import '../../../core/types/json.dart';
import '../../../infrastructure/local/database.dart';
import '../../../infrastructure/cloud/cloud_service.dart';
import '../../../app/controllers/session_controller.dart';

class AdministrationController {
  final LocalDatabase db;
  final CloudService cloud;
  final SessionController session;
  List<Json> members = [], issues = [], audit = [], backups = [];
  String sector = '', action = '';
  AdministrationController(this.db, this.cloud, this.session);
  void _authorize() {
    if (!session.canManage) {
      throw StateError('Acesso administrativo obrigatório.');
    }
  }

  Future<void> cached() async {
    _authorize();
    for (final table in [
      'memberships',
      'sync_issues',
      'audit_log',
      'device_backups',
    ]) {
      final cache = await db.record('admin_cache', table);
      _assign(
        table,
        List<Json>.from(
          (cache?['rows'] as List? ?? []).map(
            (r) => Map<String, dynamic>.from(r),
          ),
        ),
      );
    }
  }

  void _assign(String table, List<Json> rows) {
    switch (table) {
      case 'memberships':
        members = rows;
      case 'sync_issues':
        issues = rows;
      case 'audit_log':
        audit = rows;
      case 'device_backups':
        backups = rows;
    }
  }

  Future<void> refresh() async {
    _authorize();
    for (final table in [
      'memberships',
      'sync_issues',
      'audit_log',
      'device_backups',
    ]) {
      final rows = await cloud.adminList(
        table,
        sector: table == 'audit_log' ? sector : null,
        action: table == 'audit_log' ? action : null,
      );
      _assign(table, rows);
      await db.acceptRemote('admin_cache', {'id': table, 'rows': rows});
    }
  }

  Future<void> olderAudit() async {
    _authorize();
    if (audit.isEmpty) return;
    final older = await cloud.adminList(
      'audit_log',
      sector: sector,
      action: action,
      afterId: audit.last['id'].toString(),
    );
    final ids = audit.map((r) => r['id']).toSet();
    audit.addAll(older.where((r) => !ids.contains(r['id'])));
  }

  Future<void> member(
    String user,
    String role,
    String? sector,
    bool active,
  ) async {
    _authorize();
    await cloud.adminMember(user, role, sector, active);
    await refresh();
  }

  Future<void> review(String operation, String decision, String reason) async {
    _authorize();
    await cloud.reviewIssue(operation, decision, reason);
    await refresh();
  }
}
