import 'package:flutter/services.dart';
import 'package:consumo_interno/core/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/consumption/presentation/history_page.dart';
import 'package:consumo_interno/features/reports/presentation/reports_page.dart';
import 'package:consumo_interno/features/exports/presentation/exports_page.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();
  });
  Future<AppState> fixture(WidgetTester tester) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final state = AppState(db);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      state.dispose();
      await db.close();
      await tester.binding.setSurfaceSize(null);
    });
    await db.setSetting('role', 'admin');
    await db.setSetting('access_verified', '1');
    await db.transaction(() async {
      for (var i = 0; i < 55; i++) {
        final c = Consumption(
          id: 'c${i.toString().padLeft(3, '0')}',
          date: '2026-10-01',
          createdAt: '2026-10-01T12:00:00Z',
          operatorName: i == 0 ? 'Responsável antigo' : 'Ana',
          sector: 'cozinha',
          note: '',
          items: [
            ConsumptionItem(
              id: 'i$i',
              productId: 'p',
              code: '0001',
              description: 'Arroz',
              unit: 'UN',
              amount: 1000,
              totalCents: 100,
            ),
          ],
        );
        await db.acceptRemote('consumption', c.toJson());
      }
    });
    await state.load();
    expect(state.accessReady, isTrue);
    expect(state.consumptions, hasLength(50));
    expect(state.consumptions.any((c) => c.id == 'c000'), isFalse);
    return state;
  }

  testWidgets(
    'Histórico carrega mais e pesquisa registros fora da primeira página',
    (tester) async {
      final state = await fixture(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: HistoryPage(state: state)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Falha ao consultar'), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Carregar mais'),
        600,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
      await tester.tap(find.text('Carregar mais'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Responsável antigo'),
        600,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
      expect(find.textContaining('Responsável antigo'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Responsável antigo');
      await tester.pumpAndSettle();
      expect(find.textContaining('Responsável antigo'), findsWidgets);
      expect(find.text('Carregar mais'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Relatório completo inclui consumos além da primeira página', (
    tester,
  ) async {
    final state = await fixture(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ReportsPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0001 · Arroz'), findsNothing);
    await tester.tap(find.text('Exibir histórico completo'));
    await tester.pumpAndSettle();
    expect(find.text('0001 · Arroz'), findsNWidgets(55));
    expect(find.textContaining('Responsável antigo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Exportação consulta todos os consumos do setor selecionado', (
    tester,
  ) async {
    final state = await fixture(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ExportsPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-sector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cozinha').last);
    await tester.pumpAndSettle();
    // The preview's quantity must include all 55 records, including the five
    // intentionally absent from AppState's recent-consumption list.
    expect(find.text('55 UN'), findsOneWidget);
    expect(find.textContaining('55 item(ns) disponível(is)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
