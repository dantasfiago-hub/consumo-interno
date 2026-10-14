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
  final DateTime Function() now;
  Future<void>? _running;
  String error = '', lastBackup = '';
  BackupController(
    this.db, {
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : defaultDirectory = directory ?? getApplicationSupportDirectory,
       now = clock ?? DateTime.now;
  Future<void> snapshot({bool force = false, bool required = false}) async {
    if (_running != null) {
      await _running;
      if (force || required) await snapshot(force: true, required: required);
      return;
    }
    await (_running = _snapshot(
      force,
      required,
    ).whenComplete(() => _running = null));
  }

  Future<void> _snapshot(bool force, bool required) async {
    if (!force && !required && await db.setting('auto_backup') == 'false')
      return;
    try {
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
      final scope = p.normalize(root.absolute.path);
      final previousScope = await db.setting('backup_last_scope');
      final previous = DateTime.tryParse(await db.setting('backup_last') ?? '');
      final started = now().toUtc();
      final elapsed = previous == null ? null : started.difference(previous);
      if (!force &&
          !required &&
          (previousScope == null || previousScope == scope) &&
          elapsed != null &&
          !elapsed.isNegative &&
          elapsed < const Duration(days: 7)) {
        return;
      }
      await root.create(recursive: true);
      final text = await db.backup();
      final envelope = jsonEncode({
        'envelope_version': 1,
        'sha256': sha256.convert(utf8.encode(text)).toString(),
        'backup': text,
      });
      var stamp = started.microsecondsSinceEpoch;
      // Keep names monotonic even after the system clock moves backwards.
      await for (final file in root.list()) {
        if (file is! File) continue;
        final match = RegExp(r'^consumo_([0-9]+)\.json(?:\.tmp)?$')
            .firstMatch(p.basename(file.path));
        final existing = match == null ? null : int.tryParse(match.group(1)!);
        if (existing != null && existing >= stamp) stamp = existing + 1;
      }
      while (await File(p.join(root.path, 'consumo_$stamp.json')).exists() ||
          await File(p.join(root.path, 'consumo_$stamp.json.tmp')).exists()) {
        stamp++;
      }
      final name = 'consumo_$stamp.json';
      final temp = File(p.join(root.path, '$name.tmp'));
      await temp.writeAsString(envelope, flush: true);
      await temp.rename(p.join(root.path, name));
      final files = await root
          .list()
          .where(
            (f) =>
                f is File &&
                RegExp(r'^consumo_[0-9]+\.json$').hasMatch(p.basename(f.path)),
          )
          .cast<File>()
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(4)) {
        await f.delete();
      }
      lastBackup = now().toUtc().toIso8601String();
      error = '';
      await db.setSetting('backup_last', lastBackup);
      await db.setSetting('backup_last_scope', scope);
      await db.setSetting('backup_error', '');
    } catch (e) {
      error = 'Falha no backup automático: $e';
      await db.setSetting('backup_error', error);
      if (required) rethrow;
    }
  }

  static String verify(String envelope) => verifyBackupEnvelope(envelope);
}
