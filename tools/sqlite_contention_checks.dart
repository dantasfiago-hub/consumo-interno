// Run with: dart run tools/sqlite_contention_checks.dart
// ignore_for_file: avoid_print, avoid_relative_lib_imports
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import '../lib/infrastructure/local/sqlite_connection.dart';

class _TestDatabase extends GeneratedDatabase {
  _TestDatabase(File file) : super(openLocalSqlite(file));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE incoming(id TEXT PRIMARY KEY, body TEXT NOT NULL)',
      );
    },
  );
}

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('consumo_sqlite_');
  final file = File('${directory.path}/database.sqlite');
  final first = _TestDatabase(file);
  final second = _TestDatabase(file);
  final entered = Completer<void>(), release = Completer<void>();
  Future<void>? writer;
  try {
    await first.customSelect('SELECT 1').get();
    await second.customSelect('SELECT 1').get();
    for (final db in [first, second]) {
      final timeout = (await db.customSelect('PRAGMA busy_timeout').getSingle())
          .read<int>('timeout');
      final mode = (await db.customSelect('PRAGMA journal_mode').getSingle())
          .read<String>('journal_mode');
      if (timeout != 5000 || mode.toLowerCase() != 'wal')
        throw StateError('Connection settings were not applied');
    }
    await first.customStatement(
      "INSERT INTO incoming VALUES('initial','preserved')",
    );
    writer = first.transaction(() async {
      await first.customStatement("INSERT INTO incoming VALUES('first','one')");
      entered.complete();
      await release.future;
    });
    await entered.future;
    // A reader in another isolate can still read the committed snapshot in WAL.
    final read = await second
        .customSelect('SELECT count(*) n FROM incoming')
        .getSingle();
    if (read.read<int>('n') != 1)
      throw StateError('Uncommitted row was exposed');
    var finished = false;
    final waiting = second
        .customStatement("INSERT INTO incoming VALUES('second','two')")
        .then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (finished)
      throw StateError('Second writer bypassed the held transaction');
    release.complete();
    await writer;
    await waiting;
    final rows = await first.customSelect('SELECT * FROM incoming').get();
    if (rows.length != 3) throw StateError('Concurrent write was lost');
    try {
      await second.transaction(() async {
        await second.customStatement(
          "INSERT INTO incoming VALUES('rollback','not committed')",
        );
        throw StateError('abort transaction');
      });
    } on StateError {
      // Expected rollback.
    }
    final failed = await first
        .customSelect("SELECT * FROM incoming WHERE id='rollback'")
        .get();
    if (failed.isNotEmpty)
      throw StateError('Failed transaction was partially committed');
    print(
      'PASS: WAL and timeout on both connections, concurrent reader/writer, writer waits then succeeds, rollback preserves data.',
    );
  } finally {
    if (!release.isCompleted) release.complete();
    await writer;
    await second.close();
    await first.close();
    await directory.delete(recursive: true);
  }
}
