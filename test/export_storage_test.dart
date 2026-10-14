import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';
import 'package:consumo_interno/features/exports/application/save_export_artifact.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> batch() {
    final bytes = utf8.encode('0001;3;1;0,6667\r\n');
    return {
      'id': 'b',
      'version': 1,
      'status': 'prepared',
      'artifact': {
        'name': 'consumo_abc123.txt',
        'base64': base64Encode(bytes),
        'sha256': sha256.convert(bytes).toString(),
        'size': bytes.length,
      },
    };
  }

  test(
    'Gravação cancelada protege reserva sem confirmar arquivo salvo',
    () async {
      final actions = <String>[];
      final result = await saveExportArtifact(
        batch(),
        authorize: (b) async {
          actions.add('authorize');
          return {...b, 'status': 'ready'};
        },
        write: (a) async {
          actions.add('write');
          return null;
        },
        recordSaved: (b) async {
          actions.add('saved');
        },
      );
      expect(result, ExportSaveResult.cancelled);
      expect(actions, ['authorize', 'write']);
    },
  );
  test(
    'Confirma arquivo somente depois da gravação e mantém bytes originais',
    () async {
      final actions = <String>[];
      final b = batch();
      final result = await saveExportArtifact(
        b,
        authorize: (b) async {
          actions.add('authorize');
          return {...b, 'status': 'ready'};
        },
        write: (a) async {
          actions.add('write');
          expect(utf8.decode(a.bytes), '0001;3;1;0,6667\r\n');
          return '/example/file.txt';
        },
        recordSaved: (b) async {
          actions.add('saved');
        },
      );
      expect(result, ExportSaveResult.saved);
      expect(actions, ['authorize', 'write', 'saved']);
      final restored = ExportArtifact.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(b['artifact']))),
      );
      expect(restored.hash, b['artifact']['sha256']);
    },
  );
  test('Hash inválido e lote cancelado impedem gravação', () async {
    final b = batch();
    b['artifact']['sha256'] = 'invalid';
    await expectLater(
      saveExportArtifact(
        b,
        authorize: (_) async => throw StateError('não deve autorizar'),
        write: (_) async => throw StateError('não deve escrever'),
        recordSaved: (_) async {},
      ),
      throwsFormatException,
    );
    final c = batch()..['status'] = 'cancelled';
    await expectLater(
      saveExportArtifact(
        c,
        authorize: (_) async => c,
        write: (_) async => throw StateError('não deve escrever'),
        recordSaved: (_) async {},
      ),
      throwsStateError,
    );
  });
  test(
    'Backup conserva perfil, favoritos e confirmação offline pendente',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      final other = LocalDatabase(NativeDatabase.memory());
      final state = AppState(db);
      try {
        await db.setSetting('role', 'admin');
        await db.setSetting('access_verified', '1');
        await state.load();
        await state.toggleFavorite('produto');
        await state.exports.save(
          const ExportProfile(decimal: '.', validated: true),
        );
        await state.recordExportSaved({'id': 'batch-id', 'version': 2});
        expect(state.exportReceipts.length, 1);
        await other.restore(await db.backup());
        expect(jsonDecode((await other.setting('favorites'))!), ['produto']);
        expect(
          jsonDecode((await other.setting('export_profile'))!)['decimal'],
          '.',
        );
        expect(
          (await other.records('export_receipt')).single['batch_id'],
          'batch-id',
        );
        await state.load();
        expect(state.favorites, {'produto'});
        expect(state.exports.profile.version, 2);
      } finally {
        state.dispose();
        await db.close();
        await other.close();
      }
    },
  );
  test('Perfil inválido no backup não deixa restauração parcial', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    try {
      final backup = jsonDecode(await db.backup());
      backup['preferences']['export_profile'] = jsonEncode({'separator': '#'});
      await expectLater(db.restore(jsonEncode(backup)), throwsFormatException);
      expect(await db.records('product'), isEmpty);
      expect(await db.setting('export_profile'), isNull);
    } finally {
      await db.close();
    }
  });
}
