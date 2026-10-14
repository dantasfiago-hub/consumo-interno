import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/app/app.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/core/access/sectors.dart';
import 'package:consumo_interno/features/consumption/presentation/entry_page.dart';
import 'package:consumo_interno/features/consumption/presentation/history_page.dart';
import 'package:consumo_interno/features/settings/presentation/settings_page.dart';
import 'package:consumo_interno/features/products/presentation/products_page.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

Product product(String sector) => Product(
  id: sector,
  code: sector,
  description: 'Produto $sector',
  unit: 'UN',
  sectorIds: [sector],
);
Consumption consumption(String sector, {String? id, bool locked = false}) =>
    Consumption(
      id: id ?? 'c-$sector',
      date: '2026-10-04',
      createdAt: '2026-10-04T12:00:00Z',
      operatorName: 'Ana',
      sector: sector,
      note: '',
      exportLocked: locked,
      items: [
        ConsumptionItem(
          id: 'item-${id ?? sector}',
          productId: sector,
          code: sector,
          description: 'Produto $sector',
          unit: 'UN',
          amount: 1000,
          totalCents: 200,
        ),
      ],
    );
Future<void> provision(LocalDatabase db, String sector) async {
  await db.setSetting('role', 'operator');
  await db.setSetting('sector', sector);
  await db.setSetting('access_verified', '1');
  for (final key in sectors.keys) {
    await db.acceptRemote('product', product(key).toJson());
    await db.acceptRemote('consumption', consumption(key).toJson());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Backup respeita a conta atual e não substitui permissões verificadas',
    () async {
      final original = LocalDatabase(NativeDatabase.memory());
      final same = LocalDatabase(NativeDatabase.memory());
      final other = LocalDatabase(NativeDatabase.memory());
      try {
        await original.setSetting('binding', 'loja/ana');
        await original.setSetting('role', 'admin');
        await original.setSetting('access_verified', '1');
        await original.acceptRemote('product', product('cozinha').toJson());
        final backup = await original.backup();
        await same.setSetting('binding', 'loja/ana');
        await same.setSetting('role', 'operator');
        await same.setSetting('sector', 'cozinha');
        await same.restore(backup);
        expect(await same.setting('role'), 'operator');
        expect(await same.setting('sector'), 'cozinha');
        await other.setSetting('binding', 'loja/bruno');
        await expectLater(other.restore(backup), throwsStateError);
        expect(await other.products(), isEmpty);
        expect(jsonDecode(await other.backup())['binding'], 'loja/bruno');
      } finally {
        await original.close();
        await same.close();
        await other.close();
      }
    },
  );
  test(
    'Relatórios aceitam nome do setor e classificação de consumo legado',
    () {
      final horti = consumption('hortifruti');
      expect(
        reportRows([horti], ReportFilter()..sector = 'Horti Fruti'),
        hasLength(1),
      );
      final legacy = Consumption.fromJson({
        ...consumption('cozinha').toJson(),
        'sector': 'Depósito antigo',
        '_sector_id': 'cozinha',
      });
      final rows = reportRows([legacy], ReportFilter()..sector = 'Cozinha');
      expect(rows, hasLength(1));
      expect(reportRows([legacy], ReportFilter()..sector = 'Padaria'), isEmpty);
      expect(reportCsv(rows), contains('Cozinha'));
    },
  );
  for (final sector in sectors.keys) {
    test(
      'Permissões locais e cancelamento offline somente em $sector',
      () async {
        final db = LocalDatabase(NativeDatabase.memory());
        final state = AppState(db);
        try {
          await provision(db, sector);
          await state.load();
          expect(state.products.single.id, sector);
          expect(state.consumptions.single.sectorId, sector);
          expect(state.canManage, false);
          await expectLater(
            state.saveProduct(product(sector)),
            throwsStateError,
          );
          expect(
            () => state.prepareBatch([], {'sector': sector}),
            throwsStateError,
          );
          final other = sector == 'cozinha' ? 'padaria' : 'cozinha';
          await expectLater(
            state.saveConsumption(consumption(other, id: 'invalid')),
            throwsStateError,
          );
          await expectLater(
            state.cancel(consumption(other), 'Erro'),
            throwsStateError,
          );
          await state.cancel(state.consumptions.single, 'Erro no consumo');
          expect(state.consumptions.single.status, 'cancelled');
          await state.saveConsumption(consumption(sector, id: 'new'));
          expect(state.consumptions.length, 2);
        } finally {
          state.dispose();
          await db.close();
        }
      },
    );
    for (final size in [const Size(390, 844), const Size(1280, 900)]) {
      testWidgets('Tela $sector ${size.width} só mostra lançar e cancelar', (
        tester,
      ) async {
        final db = LocalDatabase(NativeDatabase.memory());
        final state = AppState(db);
        await provision(db, sector);
        await state.load();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.binding.setSurfaceSize(size);
        addTearDown(() async {
          state.dispose();
          await db.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await tester.binding.setSurfaceSize(null);
        });
        await tester.pumpWidget(ConsumptionApp(state: state));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(EntryPage), findsOneWidget);
        expect(find.byType(SettingsPage), findsNothing);
        expect(find.byType(ProductsPage), findsNothing);
        expect(find.text('Relatórios'), findsNothing);
        expect(find.text('Exportações'), findsNothing);
        expect(find.text('Configurações'), findsNothing);
        expect(find.text(sectorLabel(sector)), findsWidgets);
        await tester.tap(
          find.text(size.width > 900 ? 'Cancelar consumo' : 'Cancelar'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HistoryPage), findsOneWidget);
        expect(
          find.textContaining(
            'Produto ${sector == 'cozinha' ? 'padaria' : 'cozinha'}',
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets('Instalação nova não abre administrador sem autenticação', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final state = AppState(db);
    await state.load();
    await tester.pumpWidget(ConsumptionApp(state: state));
    await tester.pumpAndSettle();
    expect(state.accessReady, false);
    expect(find.text('Ativar aparelho'), findsOneWidget);
    expect(find.text('Cadastrar produto'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    await db.close();
  });
  test('Consumo exportado não pode ser cancelado pelo setor', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final state = AppState(db);
    try {
      await provision(db, 'cozinha');
      await db.acceptRemote('consumption', {
        ...consumption('cozinha').toJson(),
        '_export_locked': true,
      });
      await state.load();
      expect(state.consumptions.single.exportLocked, true);
      await expectLater(
        state.cancel(state.consumptions.single, 'Erro'),
        throwsStateError,
      );
    } finally {
      state.dispose();
      await db.close();
    }
  });
  test(
    'Mudança de acesso remove catálogo fora do setor e arquiva pendências',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      try {
        await db.saveProduct(product('padaria'));
        await db.acceptRemote('product', product('cozinha').toJson());
        await db.setSetting('role', 'operator');
        await db.setSetting('sector', 'cozinha');
        await db.pruneSectorScope({'product/cozinha'}, 'cozinha');
        expect((await db.products()).single.id, 'cozinha');
        expect(await db.pending(), isEmpty);
        final backup = await db.backup();
        expect(
          (await db.customSelect('SELECT body FROM archives').get())
              .single
              .data['body'],
          contains('Registro fora do setor'),
        );
        expect(backup, isNot(contains('Registro fora do setor')));
      } finally {
        await db.close();
      }
    },
  );
}
