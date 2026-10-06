import 'dart:async';

import 'package:crypto/crypto.dart';

import '../core/access/admin_guard.dart';

import 'dart:convert';

import '../features/administration/application/administration_controller.dart';
import 'controllers/session_controller.dart';
import 'controllers/catalog_controller.dart';
import 'controllers/consumption_controller.dart';
import 'controllers/synchronization_controller.dart';
import '../features/backup/application/backup_controller.dart';
import '../features/exports/application/export_controller.dart';

import 'package:flutter/foundation.dart';

import '../infrastructure/local/database.dart';
import '../domain/models.dart';
import '../infrastructure/cloud/cloud_service.dart';
import '../core/theme/theme_controller.dart';

class AppState extends ChangeNotifier {
  final LocalDatabase db;
  final ThemeController appearance;
  final ExportController exports;
  Set<String> favorites = {};
  List<String> recentProducts = [];
  List<Json> exportReceipts = [];
  late final CloudService cloud = CloudService(db);
  List<Product> products = [];
  List<Consumption> consumptions = [];
  List<Json> pending = [];
  List<Json> batches = [];
  bool _disposed = false;
  final adminGuard = AdminGuard();
  bool adminProtected = false;
  String operatorName = '', lastSync = '';
  bool cloudConfigured = false;
  late final admin = AdministrationController(db, cloud, session);
  Future<void> runAdministration(Future<void> Function() action) {
    if (!canManage) throw StateError('Acesso administrativo obrigatório.');
    return _onlineAction(action);
  }

  late final session = SessionController(db);
  late final catalog = CatalogController(db, session);
  late final consumption = ConsumptionController(db, session);
  late final backups = BackupController(db);
  late final synchronization = SynchronizationController(
    synchronize: () async {
      try {
        if (cloudConfigured && await db.setting('device_setup_mode') != '1') {
          await cloud.sync();
        }
      } finally {
        if (session.accessReady) await backups.snapshot();
      }
    },
    reload: load,
    changed: () {
      if (!_disposed) notifyListeners();
    },
  );
  String get role => session.role;
  String get sectorId => session.sectorId;
  bool get verified => session.verified;
  bool get accessReady =>
      session.accessReady && (!adminProtected || adminGuard.unlocked);
  bool get syncing => synchronization.syncing;
  String get syncError => synchronization.error;
  AppState(this.db)
    : appearance = ThemeController(
        read: () => db.setting('theme_mode'),
        write: (value) => db.setSetting('theme_mode', value),
      ),
      exports = ExportController(
        read: () => db.setting('export_profile'),
        write: (value) => db.setSetting('export_profile', value),
      );
  bool get canManage =>
      session.canManage && (!adminProtected || adminGuard.unlocked);
  bool canCancel(Consumption c) => accessReady && consumption.canCancel(c);
  Future<void> load() async {
    if (_disposed) return;
    await appearance.load();
    await exports.load();
    favorites = Set<String>.from(
      jsonDecode(await db.setting('favorites') ?? '[]'),
    );
    recentProducts = List<String>.from(
      jsonDecode(await db.setting('recent_products') ?? '[]'),
    );
    exportReceipts = await db.records('export_receipt');
    await session.load();
    adminProtected =
        session.role == 'admin' &&
        (await db.setting('binding') != null ||
            await db.setting('admin_password_required') == '1');
    if (adminProtected) await adminGuard.load((await db.setting('binding'))!);
    products = await catalog.load();
    consumptions = await consumption.load();
    pending = await db.pending();
    batches = canManage ? await db.records('batch') : [];
    if (!canManage) exportReceipts = [];
    batches.sort(
      (a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String),
    );
    operatorName = await db.setting('operator') ?? '';
    lastSync = await db.setting('last_sync') ?? '';

    cloudConfigured = await cloud.configured;
    if (!_disposed) notifyListeners();
  }

  void startSyncTimer() => synchronization.start();
  Future<void> sync({bool silent = false}) => cloudConfigured
      ? synchronization.sync(automatic: silent && synchronization.failures > 0)
      : Future.value();
  Future<T> _onlineAction<T>(Future<T> Function() action) =>
      synchronization.action(action);
  bool _leaving = false;
  final Set<Future<void>> _localWrites = {};
  Future<void> _trackLocalWrite(Future<void> Function() action) {
    if (_leaving) return Future.error(StateError('Aguarde a saída do setor.'));
    late final Future<void> task;
    task = action().whenComplete(() => _localWrites.remove(task));
    _localWrites.add(task);
    return task;
  }

  Future<void> leaveForSetup() async {
    if (_leaving) throw StateError('A saída já está em andamento.');
    _leaving = true;
    try {
      await _onlineAction(() async {
        await Future.wait(_localWrites.toList());
        final previous = await db.setting('access_verified');
        await db.setSetting('access_verified', '0');
        await session.load();
        if (!_disposed) notifyListeners();
        try {
          await cloud.sync();
          if ((await db.pending()).isNotEmpty ||
              (await db.records('export_receipt')).isNotEmpty) {
            throw StateError(
              'Resolva as pendências antes de sair ou trocar de setor.',
            );
          }
          await backups.snapshot(force: true, required: true);
          await db.setSetting('device_setup_mode', '1');
          await db.setSetting('access_verified', '0');
          lockAdministration();
        } catch (_) {
          await db.setSetting('access_verified', previous ?? '0');
          rethrow;
        }
      });
    } finally {
      _leaving = false;
    }
  }

  Future<void> activateDevice(
    String url,
    String key,
    String store,
    String activationCode, {
    Future<String?> Function()? restoreBackup,
  }) => _onlineAction(() async {
    final changing = await db.setting('device_setup_mode') == '1';
    if (changing) {
      if ((await db.pending()).isNotEmpty ||
          (await db.records('export_receipt')).isNotEmpty) {
        throw StateError('Resolva as pendências antes de ativar outro setor.');
      }
      await backups.snapshot(force: true, required: true);
    }
    await cloud.configure(url, key, store);
    await cloud.activateDevice(activationCode);
    if (cloud.role == 'admin') {
      await adminGuard.load((await db.setting('binding'))!);
      await adminGuard.resetAfterActivation(
        sha256
            .convert(
              utf8.encode(
                activationCode.trim().replaceAll('-', '').toUpperCase(),
              ),
            )
            .toString(),
      );
    }
    if (restoreBackup != null) {
      if (cloud.role != 'admin') {
        throw StateError('Somente administradores restauram backups.');
      }
      final backup = await restoreBackup();
      if (backup != null) await db.restore(backup);
    }
    if (restoreBackup == null) await cloud.restoreOwnCloudBackup();
    await cloud.sync();
    await db.removeSetting('device_setup_mode');
    await db.setSetting('access_verified', '1');
    await appearance.load(force: true);
    await backups.snapshot(force: true);
  });
  Future<void> assignLegacySector(String id, String sector, String reason) {
    if (!canManage) {
      throw StateError('Somente administradores classificam consumos antigos.');
    }
    return _onlineAction(() => cloud.assignLegacySector(id, sector, reason));
  }

  void lockAdministration() {
    adminGuard.lock();
    if (!_disposed) notifyListeners();
  }

  Future<void> logout() => _onlineAction(() => cloud.logout());
  Future<void> resolveConflict(String kind, String id) {
    if (!canManage) {
      throw StateError('Somente administradores resolvem conflitos.');
    }
    return _onlineAction(() => cloud.resolveWithRemote(kind, id));
  }

  Future<Json> prepareBatch(List<ReportRow> rows, Json filters) {
    if (!canManage) throw StateError('Somente administradores exportam.');
    return _onlineAction(
      () => cloud.createBatch(rows, exports.profile, filters),
    );
  }

  Future<Json> updateBatch(Json batch, String action, String reference) {
    if (!canManage) throw StateError('Somente administradores alteram lotes.');
    return _onlineAction(() => cloud.updateBatch(batch, action, reference));
  }

  Future<void> recordExportSaved(Json batch) async {
    if (!canManage) throw StateError('Somente administradores exportam.');
    final receipt = {
      'id': uuid.v4(),
      'batch_id': batch['id'],
      'version': batch['version'],
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await db.acceptRemote('export_receipt', receipt);
    await load();
    await sync(); // Receipt stays durable when the network is unavailable.
  }

  Future<void> toggleFavorite(String id) async {
    final next = {...favorites};
    if (!next.remove(id)) next.add(id);
    await db.setSetting('favorites', jsonEncode(next.toList()));
    favorites = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> saveProduct(Product p, {int expectedVersion = 0}) =>
      _trackLocalWrite(() async {
        if (!canManage) throw StateError('Desbloqueie a administração.');
        await catalog.save(p, expectedVersion: expectedVersion);
        await _afterLocalCommit(() async {
          await backups.snapshot(force: true);
          await load();
        });
      });

  Future<void> saveConsumption(Consumption c) => _trackLocalWrite(() async {
    if (!accessReady) throw StateError('Acesso bloqueado.');
    await consumption.save(c, products);
    await _afterLocalCommit(() async {
      final recent = <dynamic>{
        ...c.items.map((i) => i.productId),
        ...recentProducts,
      }.take(20).toList();
      await db.setSetting('recent_products', jsonEncode(recent));
      await backups.snapshot(force: true);
      await load();
    });
  });

  Future<void> cancel(Consumption c, String reason) =>
      _trackLocalWrite(() async {
        if (!accessReady) throw StateError('Acesso bloqueado.');
        await consumption.cancel(c, reason, batches);
        await _afterLocalCommit(() async {
          await backups.snapshot(force: true);
          await load();
        });
      });

  Future<void> _afterLocalCommit(Future<void> Function() refresh) async {
    // A committed record must never be reported as a failed save: retrying the
    // UI action would create a different UUID and duplicate the consumption.
    try {
      await refresh();
    } catch (e) {
      synchronization.error =
          'Registro salvo no dispositivo. Falha na atualização da tela ou backup: $e';
      if (!_disposed) notifyListeners();
    }
    if (!_disposed) unawaited(sync(silent: true));
  }

  @override
  void dispose() {
    _disposed = true;
    synchronization.dispose();
    appearance.dispose();
    exports.dispose();
    cloud.client.close();
    super.dispose();
  }
}
