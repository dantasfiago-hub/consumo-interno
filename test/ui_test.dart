import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/main.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> renderPreview(
  WidgetTester tester,
  GlobalKey key,
  String file,
) async {
  if (Platform.environment['RENDER_PREVIEWS'] != 'true') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dark =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
        ThemeMode.dark;
    final target = File(
      'docs/screenshots/${dark ? file.replaceFirst(".png", "-escuro.png") : file}',
    );
    await target.parent.create(recursive: true);
    await target.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in [const Size(1280, 900), const Size(390, 844)]) {
      testWidgets(
        'Fluxo offline e layout em ${size.width.toInt()} pixels em ${mode.name}',
        (tester) async {
          final db = LocalDatabase(NativeDatabase.memory());
          final state = AppState(db);
          await tester.binding.setSurfaceSize(size);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(() async {
            state.dispose();
            await db.close();
            await tester.binding.setSurfaceSize(null);
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await db.setSetting('role', 'admin');
          await db.setSetting('access_verified', '1');
          await db.setSetting(
            'auto_backup',
            'false',
          ); // Disk backup is covered separately with a real temporary directory.
          await state.load();
          await state.appearance.setMode(mode);
          final root = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: root,
              child: ConsumptionApp(state: state),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cadastrar produto'));
          await tester.pumpAndSettle();
          await tester.enterText(field('Código interno'), '000125');
          await tester.enterText(field('Descrição'), 'Açúcar 1 kg');
          await tester.ensureVisible(find.text('Padaria'));
          await tester.tap(find.text('Padaria'));
          await tester.tap(find.text('Salvar produto'));
          await tester.pumpAndSettle();
          expect(state.products.single.code, '000125');
          await state.saveProduct(
            Product(
              id: uuid.v4(),
              code: '00210',
              description: 'Carne bovina',
              unit: 'KG',
              sectorIds: ['padaria'],
            ),
          );
          await state.saveProduct(
            Product(
              id: uuid.v4(),
              code: '00840',
              description: 'Café 250 g',
              unit: 'UN',
              sectorIds: ['padaria'],
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await renderPreview(
            tester,
            root,
            size.width > 900 ? 'windows-produtos.png' : 'android-produtos.png',
          );
          await tester.tap(
            find.text(size.width > 900 ? 'Lançar consumo' : 'Lançar'),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (w) =>
                  w is DropdownButtonFormField<String> &&
                  w.decoration.labelText == 'Setor *',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Padaria').last);
          await tester.pumpAndSettle();
          debugPrint('UI: selecionar produto');
          await tester.ensureVisible(find.text('Selecionar produto'));
          await tester.tap(find.text('Selecionar produto'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Carne bovina'));
          await tester.pumpAndSettle();
          await tester.enterText(field('Quilogramas (kg)'), '2');
          await tester.enterText(field('Gramas (g)'), '350');
          await tester.enterText(field('Valor total (R\$)'), '70,50');
          await tester.pumpAndSettle();
          await renderPreview(
            tester,
            root,
            size.width > 900 ? 'windows-peso.png' : 'android-peso.png',
          );
          debugPrint('UI: adicionar item');
          await tester.tap(find.text('Adicionar'));
          await tester.pumpAndSettle();
          await renderPreview(
            tester,
            root,
            size.width > 900
                ? 'windows-lancamento.png'
                : 'android-lancamento.png',
          );
          debugPrint('UI: salvar lançamento');
          await tester.ensureVisible(find.text('Salvar lançamento'));
          await tester.tap(find.text('Salvar lançamento'));
          await tester.pumpAndSettle();
          await renderPreview(
            tester,
            root,
            size.width > 900
                ? 'windows-confirmacao-lancamento.png'
                : 'android-confirmacao-lancamento.png',
          );
          expect(state.consumptions, isEmpty);
          await tester.tap(find.text('Voltar'));
          await tester.pumpAndSettle();
          expect(state.consumptions, isEmpty);
          await tester.ensureVisible(find.text('Salvar lançamento'));
          await tester.tap(find.text('Salvar lançamento'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Confirmar lançamento'),
          );
          await tester.pumpAndSettle();
          expect(state.consumptions.single.totalCents, 7050);
          expect(state.consumptions.single.items.single.amount, 2350);
          expect(state.pending.length, 4);
          await tester.tap(find.text('Histórico'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Envio pendente'), findsOneWidget);
          await tester.tap(find.text('Relatórios'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(field('Total mínimo (R\$)'));
          await tester.enterText(field('Total mínimo (R\$)'), 'errado');
          await tester.enterText(field('Setor'), '');
          await tester.pumpAndSettle();
          final exportFinder = find.ancestor(
            of: find.text('Exportar CSV detalhado'),
            matching: find.byWidgetPredicate((w) => w is OutlinedButton),
          );
          final export = tester.widget<OutlinedButton>(exportFinder);
          expect(export.onPressed, isNull);
          await tester.enterText(field('Total mínimo (R\$)'), '0');
          await tester.pumpAndSettle();
          expect(
            tester.widget<OutlinedButton>(exportFinder).onPressed,
            isNotNull,
          );
          await renderPreview(
            tester,
            root,
            size.width > 900
                ? 'windows-relatorios.png'
                : 'android-relatorios.png',
          );
          await tester.tap(
            find.text(size.width > 900 ? 'Exportações' : 'Exportar'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('export-sector')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Padaria').last);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Saída: somente código interno'),
            findsOneWidget,
          );
          expect(find.textContaining('Valor unitário:'), findsNothing);
          expect(find.text('Reservar lote selecionado'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await renderPreview(
            tester,
            root,
            size.width > 900
                ? 'windows-exportacoes.png'
                : 'android-exportacoes.png',
          );
          await tester.tap(
            find.text(size.width > 900 ? 'Configurações' : 'Ajustes'),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Perfil de exportação VR Master'), findsOneWidget);
          final before = state.consumptions.single.id;
          await renderPreview(
            tester,
            root,
            size.width > 900
                ? 'windows-configuracoes.png'
                : 'android-configuracoes.png',
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('theme-selector')),
          );
          await tester.tap(find.byKey(const ValueKey('theme-selector')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(mode == ThemeMode.dark ? 'Claro' : 'Escuro').last,
          );
          await tester.pumpAndSettle();
          expect(
            state.appearance.mode,
            mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
          );
          expect(state.consumptions.single.id, before);
          expect(state.pending.length, 4);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
