import 'dart:convert';

import '../../../core/backup/backup_envelope.dart';

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/local/database.dart';

class BackupController {
  final LocalDatabase db;
  final Future<Directory> Function() defaultDirectory;
  Future<void>? _running;
  String error = '', lastBackup = '';
  BackupController(this.db, {Future<Directory> Function()? directory})
    : defaultDirectory = directory ?? getApplicationSupportDirectory;
  Future<void> snapshot({bool force = false, bool required = false}) async {
    if (_running != null) {
      await _running;
      if (force) await snapshot(force: true, required: required);
      return;
    }
    await (_running = _snapshot(
      force,
      required,
    ).whenComplete(() => _running = null));
  }

  Future<void> _snapshot(bool force, bool required) async {
    if (!required && await db.setting('auto_backup') == 'false') return;
    try {
      final previous = DateTime.tryParse(await db.setting('backup_last') ?? '');
      if (!force &&
          previous != null &&
          DateTime.now().difference(previous) < const Duration(days: 7)) {
        return;
      }
      final custom = await db.setting('backup_directory');
      var root = custom != null && custom.isNotEmpty
          ? Directory(custom)
          : Directory(p.join((await defaultDirectory()).path, 'backups'));
      final binding = await db.setting('binding');
      if (binding != null) {
        root = Directory(
          p.join(
            root.path,
            sha256.convert(utf8.encode(binding)).toString().substring(0, 16),
          ),
        );
      }
      await root.create(recursive: true);
      final text = await db.backup();
      final envelope = jsonEncode({
        'envelope_version': 1,
        'sha256': sha256.convert(utf8.encode(text)).toString(),
        'backup': text,
      });
      final name =
          'consumo_${DateTime.now().toUtc().microsecondsSinceEpoch}.json';
      final temp = File(p.join(root.path, '$name.tmp'));
      await temp.writeAsString(envelope, flush: true);
      await temp.rename(p.join(root.path, name));
      final files = await root
          .list()
          .where(
            (f) =>
                f is File &&
                p.basename(f.path).startsWith('consumo_') &&
                f.path.endsWith('.json'),
          )
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(14)) {
        await f.delete();
      }
      lastBackup = DateTime.now().toUtc().toIso8601String();
      error = '';
      await db.setSetting('backup_last', lastBackup);
      await db.setSetting('backup_error', '');
    } catch (e) {
      error = 'Falha no backup automático: $e';
      await db.setSetting('backup_error', error);
      if (required) rethrow;
    }
  }

  static String verify(String envelope) => verifyBackupEnvelope(envelope);
}
