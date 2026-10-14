import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:consumo_interno/app/app.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/core/theme/theme_controller.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/features/settings/presentation/appearance_card.dart';

void main() {
  test('Preferência persiste sem gerar pendência de sincronização', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    final state = AppState(db);
    await state.load();
    expect(state.appearance.mode, ThemeMode.system);
    await state.appearance.setMode(ThemeMode.dark);
    expect(await db.pending(), isEmpty);
    state.dispose();
    final reopened = AppState(db);
    await reopened.load();
    expect(reopened.appearance.mode, ThemeMode.dark);
    reopened.dispose();
    await db.close();
  });

  test(
    'Valor desconhecido usa automático; falha ao salvar mantém preferência',
    () async {
      final controller = ThemeController(
        read: () async => 'invalid',
        write: (_) async => throw StateError('disco indisponível'),
      );
      await controller.load();
      expect(controller.mode, ThemeMode.system);
      await expectLater(controller.setMode(ThemeMode.dark), throwsStateError);
      expect(controller.mode, ThemeMode.system);
      expect(controller.saving, isFalse);
      controller.dispose();
    },
  );

  testWidgets('Automático acompanha sistema; preferência explícita prevalece', (
    tester,
  ) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final state = AppState(db);
    await state.load();
    addTearDown(() async {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      state.dispose();
      await db.close();
    });
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(ConsumptionApp(state: state));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    await state.appearance.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Falha ao salvar não deixa seletor com tema incorreto', (
    tester,
  ) async {
    final controller = ThemeController(
      read: () async => null,
      write: (_) async => throw StateError('Falha ao salvar'),
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppearanceCard(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('theme-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escuro').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<ThemeMode>>(
            find.byKey(const ValueKey('theme-selector')),
          )
          .value,
      ThemeMode.system,
    );
    expect(find.text('Falha ao salvar'), findsOneWidget);
    expect(controller.saving, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
