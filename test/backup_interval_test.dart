import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/features/backup/application/backup_controller.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabase db;
  late DateTime now;
  late BackupController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-interval');
    db = LocalDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 14);
    controller = BackupController(
      db,
      directory: () async => directory,
      clock: () => now,
    );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<List<File>> copies() async => directory
      .list(recursive: true)
      .where((f) => f is File && f.path.endsWith('.json'))
      .cast<File>()
      .toList();

  test('Seven day boundary persists across controller restart', () async {
    await controller.snapshot();
    expect(await copies(), hasLength(1));
    now = now.add(const Duration(days: 7) - const Duration(microseconds: 1));
    controller = BackupController(
      db,
      directory: () async => directory,
      clock: () => now,
    );
    await controller.snapshot();
    expect(await copies(), hasLength(1));
    now = now.add(const Duration(microseconds: 1));
    await controller.snapshot();
    expect(await copies(), hasLength(2));
    expect(await db.setting('backup_last'), now.toIso8601String());
  });

  test('Forced/manual backup bypasses opt out and resets interval', () async {
    await db.setSetting('auto_backup', 'false');
    await controller.snapshot();
    expect(await copies(), isEmpty);
    await controller.snapshot(force: true);
    expect(await copies(), hasLength(1));
    await db.setSetting('auto_backup', 'true');
    now = now.add(const Duration(days: 6));
    await controller.snapshot();
    expect(await copies(), hasLength(1));
    await controller.snapshot(force: true);
    now = now.add(const Duration(days: 1));
    await controller.snapshot();
    expect(await copies(), hasLength(2));
  });

  test('Invalid/future date never indefinitely suppresses backup', () async {
    for (final date in [
      'invalid',
      now.add(const Duration(days: 30)).toIso8601String(),
    ]) {
      await db.setSetting('backup_last', date);
      await controller.snapshot();
    }
    expect(await copies(), hasLength(2));
  });

  test(
    'New binding and folder receive a snapshot without waiting a week',
    () async {
      await db.setSetting('binding', 'store/actor1');
      await controller.snapshot();
      await db.setSetting('binding', 'store/actor2');
      await controller.snapshot();
      expect(await copies(), hasLength(2));
      await db.setSetting('backup_directory', '${directory.path}/custom');
      await controller.snapshot();
      expect(await copies(), hasLength(3));
    },
  );

  test(
    'Failure preserves timestamp; required snapshot throws and can retry',
    () async {
      final blocked = File('${directory.path}/blocked');
      await blocked.writeAsString('not a directory');
      await db.setSetting('backup_directory', blocked.path);
      await db.setSetting('backup_last', 'invalid');
      await controller.snapshot();
      expect(controller.error, isNotEmpty);
      expect(await db.setting('backup_last'), 'invalid');
      await expectLater(
        controller.snapshot(required: true),
        throwsA(isA<FileSystemException>()),
      );
      await db.setSetting('auto_backup', 'false');
      await db.removeSetting('backup_directory');
      await controller.snapshot(required: true);
      expect(await copies(), hasLength(1));
      expect(controller.error, isEmpty);
    },
  );

  test('Restoring data starts a new backup interval', () async {
    await db.setSetting('favorites', '["original"]');
    final saved = await db.backup();
    await controller.snapshot();
    await db.setSetting('favorites', '["changed"]');
    await db.restore(saved);
    expect(await db.setting('backup_last'), isNull);
    await controller.snapshot();
    expect(await copies(), hasLength(2));
    expect(await db.setting('favorites'), '["original"]');
  });

  test(
    'Clock rollback retains the new snapshot rather than deleting it',
    () async {
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(days: 7));
        await controller.snapshot();
      }
      now = DateTime.utc(2026, 10, 14);
      await db.setSetting('favorites', '["after-rollback"]');
      await controller.snapshot();
      final files = await copies();
      files.sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(4));
      final data = jsonDecode(
        BackupController.verify(await files.last.readAsString()),
      );
      expect(data['preferences']['favorites'], '["after-rollback"]');
    },
  );

  test(
    'Concurrent forced copies do not overwrite; retain latest four only',
    () async {
      final root = Directory('${directory.path}/backups');
      await root.create();
      final unrelated = File('${root.path}/consumo_manual.json');
      await unrelated.writeAsString('keep');
      final temporary = File('${root.path}/consumo_1.json.tmp');
      await temporary.writeAsString('keep');
      for (var i = 0; i < 6; i++) {
        await db.setSetting('favorites', jsonEncode(['f$i']));
        await Future.wait([
          controller.snapshot(force: true),
          controller.snapshot(force: true),
        ]);
      }
      final files =
          (await copies()).where((f) => f.path != unrelated.path).toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(4));
      expect(
        jsonDecode(
          BackupController.verify(await files.last.readAsString()),
        )['preferences']['favorites'],
        '["f5"]',
      );
      expect(await unrelated.readAsString(), 'keep');
      expect(await temporary.exists(), isTrue);
    },
  );
}
