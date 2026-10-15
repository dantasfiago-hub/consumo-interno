import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/infrastructure/local/sqlite_connection.dart';
import '../tools/sqlite_contention_checks.dart' as contention;

void main() {
  test(
    'Duas conexões aguardam o bloqueio sem perder gravações',
    contention.main,
  );
  test(
    'Conexão de produção configura WAL e espera; mantém incoming e cursor',
    () async {
      final dir = await Directory.systemTemp.createTemp('consumo_busy_');
      final file = File('${dir.path}/consumo.sqlite');
      // Simulates an existing installation before enabling WAL.
      final old = LocalDatabase(NativeDatabase(file));
      await old.setSetting('entity_cursor', '41');
      await old.setSetting('operator', 'Preservado');
      await old.close();
      final db = LocalDatabase(openLocalSqlite(file));
      try {
        expect(
          (await db.customSelect('PRAGMA busy_timeout').getSingle()).read<int>(
            'timeout',
          ),
          5000,
        );
        expect(
          (await db.customSelect('PRAGMA journal_mode').getSingle())
              .read<String>('journal_mode'),
          'wal',
        );
        expect(await db.setting('operator'), 'Preservado');
        await db.stageRemote([
          {
            'kind': 'product',
            'id': 'p',
            'created_by': 'admin',
            'body': {
              'id': 'p',
              'code': '001',
              'description': 'Produto',
              'unit': 'UN',
              'active': true,
              'version': 1,
              'sectors': ['cozinha'],
            },
            'sector_id': null,
            'export_locked': false,
          },
        ]);
        expect(await db.setting('entity_cursor'), '41');
        await db.commitIncoming('42');
        expect(await db.setting('entity_cursor'), '42');
        expect((await db.record('product', 'p'))?['code'], '001');
        expect(await db.pending(), isEmpty);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
