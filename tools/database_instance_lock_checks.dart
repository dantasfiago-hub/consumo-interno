// Run with: dart run tools/database_instance_lock_checks.dart
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';

import '../lib/infrastructure/local/database_instance_lock.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    try {
      final lock = await DatabaseInstanceLock.acquire(File(args[0]));
      stdout.writeln('locked');
      if (args.length > 1 && args[1] == 'hold') {
        await stdin.transform(utf8.decoder).first;
      }
      await lock.release();
    } on DatabaseAlreadyOpenException {
      stdout.writeln('blocked');
      exitCode = 23;
    }
    return;
  }
  final dir = await Directory.systemTemp.createTemp('consumo_instance_');
  final file = File('${dir.path}/app.lock');
  final command = [Platform.script.toFilePath(), file.path];
  DatabaseInstanceLock? owner;
  Process? child;
  try {
    owner = await DatabaseInstanceLock.acquire(file);
    final rejected = await Process.run(Platform.resolvedExecutable, command);
    if (rejected.exitCode != 23 ||
        !rejected.stdout.toString().contains('blocked')) {
      throw StateError('Second process was not blocked: ${rejected.stderr}');
    }
    await owner.release();
    await owner.release();
    owner = null;
    final reopened = await Process.run(Platform.resolvedExecutable, command);
    if (reopened.exitCode != 0 ||
        !reopened.stdout.toString().contains('locked')) {
      throw StateError(
        'Could not reopen after releasing lock: ${reopened.stderr}',
      );
    }
    child = await Process.start(Platform.resolvedExecutable, [
      ...command,
      'hold',
    ]);
    final ready = await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    if (ready != 'locked') {
      throw StateError('Child failed to acquire lock');
    }
    child.kill();
    await child.exitCode;
    child = null;
    owner = await DatabaseInstanceLock.acquire(file);
    await owner.release();
    owner = null;
    if (!await file.exists()) {
      throw StateError('Lock file must not be deleted');
    }
    print(
      'PASS: second process rejected, release/reopen, process exit recovery, idempotent close.',
    );
  } finally {
    child?.kill();
    await owner?.release();
    await dir.delete(recursive: true);
  }
}
