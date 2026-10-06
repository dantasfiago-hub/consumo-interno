import 'package:crypto/crypto.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:consumo_interno/core/theme/theme_controller.dart';
import 'package:consumo_interno/features/exports/application/export_controller.dart';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/app/controllers/session_controller.dart';
import 'package:consumo_interno/app/controllers/synchronization_controller.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/domain/models.dart';

class FailingReadDatabase extends LocalDatabase {
  bool failReads = false;
  FailingReadDatabase() : super(NativeDatabase.memory());
  @override
  Future<List<Map<String, dynamic>>> records(String kind) {
    if (failReads && kind == 'consumption') {
      throw StateError('Falha de leitura posterior ao commit');
    }
    return super.records(kind);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Controladores não notificam depois de descarte durante leitura',
    () async {
      final themeRead = Completer<String?>(), exportRead = Completer<String?>();
      final theme = ThemeController(
        read: () => themeRead.future,
        write: (_) async {},
      );
      final export = ExportController(
        read: () => exportRead.future,
        write: (_) async {},
      );
      final t = theme.load(), e = export.load();
      theme.dispose();
      export.dispose();
      themeRead.complete('dark');
      exportRead.complete(null);
      await Future.wait([t, e]);
    },
  );
  test('Tema restaurado pode atualizar a preferência já carregada', () async {
    var saved = 'light';
    final theme = ThemeController(read: () async => saved, write: (_) async {});
    await theme.load();
    expect(theme.mode, ThemeMode.light);
    saved = 'dark';
    await theme.load(force: true);
    expect(theme.mode, ThemeMode.dark);
    theme.dispose();
  });
  test(
    'Falha após commit não informa erro de gravação nem convida a duplicar lançamento',
    () async {
      final db = FailingReadDatabase();
      final app = AppState(db);
      try {
        await db.setSetting('role', 'admin');
        await db.setSetting('access_verified', '1');
        await db.setSetting('auto_backup', 'false');
        await db.acceptRemote(
          'product',
          const Product(
            id: 'p',
            code: '01',
            description: 'Produto',
            unit: 'UN',
            sectorIds: ['cozinha'],
          ).toJson(),
        );
        await app.load();
        db.failReads = true;
        final c = Consumption(
          id: 'c',
          date: '2026-10-04',
          createdAt: '2026-10-04T12:00:00Z',
          operatorName: 'Ana',
          sector: 'cozinha',
          note: '',
          items: const [
            ConsumptionItem(
              id: 'i',
              productId: 'p',
              code: '01',
              description: 'Produto',
              unit: 'UN',
              amount: 1000,
              totalCents: 100,
            ),
          ],
        );
        await app.saveConsumption(c);
        expect(app.syncError, contains('Registro salvo'));
        expect((await db.pending()).length, 1);
        db.failReads = false;
        expect((await db.consumptions()).single.id, 'c');
        expect(await db.setting('operator'), 'Ana');
      } finally {
        app.dispose();
        await db.close();
      }
    },
  );
  test('Fotos órfãs não aumentam o backup do catálogo atual', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final photo = base64Encode([1, 2, 3]),
        hash = sha256.convert([1, 2, 3]).toString();
    final orphan = base64Encode([4, 5, 6]),
        oldHash = sha256.convert([4, 5, 6]).toString();
    try {
      await db.setSetting('role', 'admin');
      await db.acceptRemote('image', {'id': oldHash, 'data_base64': orphan});
      await db.acceptRemote(
        'product',
        Product(
          id: 'p',
          code: '01',
          description: 'Produto',
          unit: 'UN',
          photo: photo,
        ).toJson(),
      );
      expect((await db.products()).single.photo, photo);
      final backup = jsonDecode(await db.backup());
      expect(backup['images'].length, 1);
      expect(backup['images'].single['id'], hash);
      // Cache cleanup is not destructive: the original cache entry remains on disk.
      expect(await db.record('image', oldHash), isNotNull);
    } finally {
      await db.close();
    }
  });
  test('Falha de reload não trava sincronização nem escapa do timer', () async {
    var reloadFails = true;
    var sends = 0;
    final c = SynchronizationController(
      synchronize: () async {
        sends++;
      },
      reload: () async {
        if (reloadFails) throw StateError('disco');
      },
      changed: () {},
    );
    await c.sync();
    expect(c.syncing, false);
    expect(c.error, contains('disco'));
    reloadFails = false;
    await c.sync();
    expect(sends, 2);
    expect(c.error, isEmpty);
    c.dispose();
  });
  test('Erro da ação é preservado quando reload também falha', () async {
    final c = SynchronizationController(
      synchronize: () async {},
      reload: () async {
        throw StateError('reload');
      },
      changed: () {},
    );
    await expectLater(
      c.action(() async {
        throw StateError('original');
      }),
      throwsA(predicate((e) => e.toString().contains('original'))),
    );
    expect(c.syncing, false);
    c.dispose();
    await expectLater(c.action(() async {}), throwsStateError);
  });
  test('Revogação explícita tem prioridade sobre binding histórico', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    try {
      await db.setSetting('binding', 'loja/ana');
      await db.setSetting('role', 'admin');
      await db.setSetting('access_verified', '0');
      final c = SessionController(db);
      await c.load();
      expect(c.canManage, false);
      expect(c.accessReady, false);
    } finally {
      await db.close();
    }
  });
  test('Backup sem binding é recusado por instalação vinculada', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    try {
      final text = await db.backup();
      await db.setSetting('binding', 'loja/ana');
      await expectLater(db.restore(text), throwsStateError);
      expect(await db.products(), isEmpty);
    } finally {
      await db.close();
    }
  });
  test(
    'Backup não concede privilégios em banco ainda não autenticado',
    () async {
      final db = LocalDatabase(NativeDatabase.memory()),
          copy = LocalDatabase(NativeDatabase.memory());
      try {
        await db.setSetting('role', 'admin');
        await db.setSetting('access_verified', '1');
        await copy.restore(await db.backup());
        final s = SessionController(copy);
        await s.load();
        expect(s.canManage, false);
        expect(s.accessReady, false);
      } finally {
        await db.close();
        await copy.close();
      }
    },
  );
  test(
    'Backup após mudança de setor omite cache e outbox de outro setor',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      try {
        await db.saveProduct(
          const Product(
            id: 'p',
            code: '01',
            description: 'Produto',
            unit: 'UN',
            sectorIds: ['padaria'],
          ),
        );
        await db.acceptRemote('batch', {'id': 'lote', 'rows': []});
        await db.setSetting('role', 'operator');
        await db.setSetting('sector', 'cozinha');
        final backup = jsonDecode(await db.backup());
        expect(backup['products'], isEmpty);
        expect(backup['outbox'], isEmpty);
        expect(backup['batches'], isEmpty);
        expect((await db.pending()).length, 1);
      } finally {
        await db.close();
      }
    },
  );
  test('Consumo rejeita código incompatível e cancelamento longo', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final product = const Product(
      id: 'p',
      code: '01',
      description: 'Produto',
      unit: 'UN',
    );
    Consumption make(String code) => Consumption(
      id: 'c',
      date: '2026-10-04',
      createdAt: '2026-10-04T12:00:00Z',
      operatorName: 'Ana',
      sector: 'cozinha',
      note: '',
      items: [
        ConsumptionItem(
          id: 'i',
          productId: 'p',
          code: code,
          description: 'Produto',
          unit: 'UN',
          amount: 1000,
          totalCents: 100,
        ),
      ],
    );
    try {
      await db.acceptRemote('product', product.toJson());
      await expectLater(db.saveConsumption(make('ERRADO')), throwsStateError);
      await db.saveConsumption(make('01'));
      await expectLater(
        db.cancelConsumption(make('01'), List.filled(301, 'x').join()),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });
  test(
    'Objeto antigo não cancela consumo já protegido no banco local',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      final c = Consumption(
        id: 'c',
        date: '2026-10-04',
        createdAt: '2026-10-04T12:00:00Z',
        operatorName: 'Ana',
        sector: 'cozinha',
        note: '',
        items: const [
          ConsumptionItem(
            id: 'i',
            productId: 'p',
            code: '01',
            description: 'Produto',
            unit: 'UN',
            amount: 1000,
            totalCents: 100,
          ),
        ],
      );
      try {
        await db.acceptRemote('consumption', {
          ...c.toJson(),
          '_export_locked': true,
        });
        await expectLater(
          db.cancelConsumption(c, 'Correção'),
          throwsStateError,
        );
        expect(await db.pending(), isEmpty);
      } finally {
        await db.close();
      }
    },
  );
  test('Restauração conserva instante de cancelamento', () async {
    final db = LocalDatabase(NativeDatabase.memory()),
        copy = LocalDatabase(NativeDatabase.memory());
    final c = Consumption(
      id: 'c',
      date: '2026-10-04',
      createdAt: '2026-10-04T12:00:00Z',
      operatorName: 'Ana',
      sector: 'cozinha',
      note: '',
      status: 'cancelled',
      cancellationReason: 'Erro no consumo',
      version: 2,
      items: const [
        ConsumptionItem(
          id: 'i',
          productId: 'p',
          code: '01',
          description: 'Produto',
          unit: 'UN',
          amount: 1000,
          totalCents: 100,
        ),
      ],
    );
    try {
      await db.acceptRemote('consumption', {
        ...c.toJson(),
        'cancelled_at': '2026-10-04T13:00:00Z',
      });
      await copy.restore(await db.backup());
      expect(
        (await copy.record('consumption', 'c'))!['cancelled_at'],
        '2026-10-04T13:00:00Z',
      );
    } finally {
      await db.close();
      await copy.close();
    }
  });
}
