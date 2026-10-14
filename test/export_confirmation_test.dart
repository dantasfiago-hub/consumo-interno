import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';
import 'package:consumo_interno/features/exports/presentation/exports_page.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  testWidgets('Voltar nas confirmações não reserva nem autoriza o arquivo', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final state = AppState(db);
    addTearDown(() async {
      state.dispose();
      await db.close();
    });
    await db.setSetting('role', 'admin');
    await db.setSetting('access_verified', '1');
    await db.setSetting('auto_backup', 'false');
    await state.load();
    await state.exports.save(const ExportProfile(validated: true));
    final product = Product(
      id: uuid.v4(),
      code: '0001',
      description: 'Produto',
      unit: 'KG',
      sectorIds: ['cozinha'],
    );
    await state.saveProduct(product);
    final item = ConsumptionItem(
      id: uuid.v4(),
      productId: product.id,
      code: product.code,
      description: product.description,
      unit: product.unit,
      amount: 2350,
      totalCents: 100,
    );
    await state.saveConsumption(
      Consumption(
        id: uuid.v4(),
        date: '2026-10-05',
        createdAt: '2026-10-05T12:00:00Z',
        operatorName: 'Ana',
        sector: 'cozinha',
        note: '',
        items: [item],
      ),
    );
    state.cloudConfigured = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExportsPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-sector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cozinha').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reservar lote selecionado'));
    await tester.tap(find.text('Reservar lote selecionado'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar exportação para o VR'), findsOneWidget);
    expect(
      find.textContaining('Arquivo com código interno e quantidade.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(await db.records('batch'), isEmpty);
    expect(await db.setting('batch_retry_id'), isNull);
    final batch = {
      'id': uuid.v4(),
      'status': 'prepared',
      'format_version': 2,
      'version': 1,
      'sector': 'cozinha',
      'created_at': '2026-10-05T12:00:00Z',
      'created_by': 'admin',
      'profile': const ExportProfile().forSector('cozinha').toJson(),
      'rows': <Json>[],
      'grouped_rows': [
        <String, dynamic>{'code': '0001'},
      ],
    };
    state.batches = [batch];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportsPage(key: const ValueKey('with-batch'), state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.textContaining(
      'Lote ${batch['id'].toString().substring(0, 8)}',
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Salvar arquivo do lote'));
    await tester.tap(find.text('Salvar arquivo do lote'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar arquivo para o VR'), findsOneWidget);
    expect(
      find.textContaining('Campos: código interno, quantidade.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(batch['status'], 'prepared');
    expect(state.exportReceipts, isEmpty);
    expect(state.syncError, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
