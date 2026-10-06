import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/app/app.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/app/controllers/synchronization_controller.dart';
import 'package:consumo_interno/core/backup/compressed_backup.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/administration/presentation/administration_page.dart';
import 'package:consumo_interno/features/backup/application/backup_controller.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Backup automático retém 14 cópias e restaura com verificação de integridade',
    () async {
      final dir = await Directory.systemTemp.createTemp('backup14');
      final db = LocalDatabase(NativeDatabase.memory()),
          restored = LocalDatabase(NativeDatabase.memory());
      final c = BackupController(db, directory: () async => dir);
      try {
        for (var i = 0; i < 16; i++) {
          await db.setSetting('favorites', jsonEncode(['f$i']));
          await c.snapshot(force: true);
        }
        final files = await Directory(
          '${dir.path}/backups',
        ).list().where((f) => f.path.endsWith('.json')).cast<File>().toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        expect(files.length, 14);
        final text = await files.last.readAsString();
        await restored.restore(text);
        expect(await restored.setting('favorites'), '["f15"]');
        final tampered = jsonDecode(text)..['backup'] = '{}';
        expect(
          () => BackupController.verify(jsonEncode(tampered)),
          throwsFormatException,
        );
        expect(c.error, isEmpty);
      } finally {
        await db.close();
        await restored.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'Backups simultâneos são serializados e a cópia final contém a última alteração',
    () async {
      final dir = await Directory.systemTemp.createTemp('backup-concurrent');
      final db = LocalDatabase(NativeDatabase.memory());
      final c = BackupController(db, directory: () async => dir);
      try {
        await db.setSetting('favorites', '["a"]');
        final first = c.snapshot(force: true);
        await db.setSetting('favorites', '["b"]');
        await Future.wait([first, c.snapshot(force: true)]);
        final files = await Directory(
          '${dir.path}/backups',
        ).list().cast<File>().toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        final data = jsonDecode(
          BackupController.verify(await files.last.readAsString()),
        );
        expect(data['preferences']['favorites'], '["b"]');
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('Backup comprimido tem limite de expansão e mantém UTF-8', () {
    const original = '{"descrição":"Maçã"}';
    expect(
      decodeCompressedBackup(zlib.encode(utf8.encode(original))),
      original,
    );
    expect(
      () => decodeCompressedBackup(
        zlib.encode(List.filled(2000, 65)),
        maxDecodedBytes: 1000,
      ),
      throwsFormatException,
    );
    expect(() => decodeCompressedBackup([1, 2, 3]), throwsA(isA<Exception>()));
  });
  test(
    'Fotos iguais usam um só registro e sobrevivem ao backup sem duplicar o catálogo',
    () async {
      final db = LocalDatabase(NativeDatabase.memory()),
          other = LocalDatabase(NativeDatabase.memory());
      final photo = base64Encode([1, 2, 3, 4]);
      try {
        for (var i = 0; i < 2; i++) {
          await db.saveProduct(
            Product(
              id: 'p$i',
              code: '00$i',
              description: 'Produto',
              unit: 'UN',
              photo: photo,
              sectorIds: const ['cozinha'],
            ),
          );
        }
        expect((await db.records('image')).length, 1);
        expect(
          (await db.records('product')).every((p) => p['photo'] == null),
          true,
        );
        final text = await db.backup();
        await other.restore(text);
        expect((await other.products()).every((p) => p.photo == photo), true);
        expect((await other.records('image')).length, 1);
      } finally {
        await db.close();
        await other.close();
      }
    },
  );
  test(
    'Sincronização aplica intervalo progressivo, ignora tentativa antecipada e permite tentativa manual',
    () async {
      var calls = 0, reloads = 0;
      final c = SynchronizationController(
        synchronize: () async {
          calls++;
          if (calls < 3) throw StateError('Rede indisponível');
        },
        reload: () async {
          reloads++;
        },
        changed: () {},
      );
      await c.sync();
      expect(c.retryDelay, const Duration(seconds: 120));
      await c.sync(automatic: true);
      expect(calls, 1);
      await c.sync();
      expect(c.retryDelay, const Duration(seconds: 240));
      await c.sync();
      expect(c.error, isEmpty);
      expect(c.failures, 0);
      expect(reloads, 3);
      c.dispose();
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'Administração possui quatro áreas e layout correto em $width',
      (tester) async {
        final db = LocalDatabase(NativeDatabase.memory());
        final s = AppState(db);
        await db.setSetting('role', 'admin');
        await db.setSetting('access_verified', '1');
        await db.setSetting('auto_backup', 'false');
        await s.load();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.binding.setSurfaceSize(Size(width, 900));
        try {
          await tester.pumpWidget(ConsumptionApp(state: s));
          await tester.pumpAndSettle();
          await tester.tap(find.text(width > 900 ? 'Administração' : 'Admin'));
          await tester.pumpAndSettle();
          for (final label in [
            'Aparelhos',
            'Pendências',
            'Auditoria',
            'Backups',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.tap(find.text('Gerar código de ativação'));
          await tester.pumpAndSettle();
          expect(find.text('Ativar aparelho do setor'), findsOneWidget);
          await tester.tap(find.text('Voltar'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          s.dispose();
          await db.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  }
  testWidgets('Conta de setor não abre administração por acesso direto', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final s = AppState(db);
    await db.setSetting('role', 'operator');
    await db.setSetting('sector', 'cozinha');
    await db.setSetting('access_verified', '1');
    await s.load();
    await tester.pumpWidget(MaterialApp(home: AdministrationPage(state: s)));
    await tester.pumpAndSettle();
    expect(find.text('Acesso administrativo obrigatório.'), findsOneWidget);
    expect(find.text('Gerar código de ativação'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
    await db.close();
  });
}
