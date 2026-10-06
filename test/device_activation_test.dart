import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/app/app.dart';
import 'package:consumo_interno/core/access/admin_guard.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/infrastructure/cloud/cloud_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Ativação sem e-mail reutiliza identidade e aparelho após perder a resposta',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      var signups = 0, claims = 0;
      final devices = <String>[];
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          if (request.url.path.endsWith('/signup')) {
            signups++;
            expect(jsonDecode(request.body), isEmpty);
          } else {
            expect(jsonDecode(request.body)['refresh_token'], 'refresh');
          }
          return http.Response(
            jsonEncode({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {'id': '22222222-2222-4222-8222-222222222222'},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/activate_sector_device')) {
          final body = jsonDecode(request.body);
          expect(body.containsKey('email'), false);
          expect(body.containsKey('p_sector'), false);
          devices.add(body['p_device']);
          claims++;
          if (claims == 1) throw const CloudException('Resposta perdida');
          return http.Response(
            '{"activated":true,"slot":"cozinha","duplicate":true}',
            200,
          );
        }
        return http.Response(
          '[{"role":"operator","sector":"cozinha","features_version":7}]',
          200,
        );
      });
      final cloud = CloudService(db, client: client);
      try {
        await cloud.configure(
          'https://example.supabase.co',
          'public',
          '11111111-1111-4111-8111-111111111111',
        );
        await expectLater(
          cloud.activateDevice('A'.padRight(32, 'A')),
          throwsA(isA<CloudException>()),
        );
        expect(await db.setting('access_verified'), isNull);
        await cloud.activateDevice('A'.padRight(32, 'A'));
        expect(signups, 1);
        expect(devices.toSet().length, 1);
        expect(await db.setting('sector'), 'cozinha');
        expect(await db.setting('device_mode'), '1');
        await expectLater(cloud.logout(), throwsA(isA<CloudException>()));
      } finally {
        await db.close();
        client.close();
      }
    },
  );
  test('PBKDF2 coincide com vetor independente de SHA-256', () {
    expect(
      deriveAdminPassword({
        'password': 'a',
        'salt': base64Encode(List.generate(16, (i) => i)),
      }),
      'gNQMfiwu11bDbW/6lJnBR/CP2ZKdylDo67RFaA/ovhs=',
    );
  });
  test(
    'Credencial perdida em banco vinculado não cria outra identidade',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      final client = MockClient(
        (_) async => throw StateError('Não deve chamar a rede'),
      );
      try {
        await db.setSetting('binding', 'vinculo');
        await expectLater(
          CloudService(
            db,
            client: client,
          ).activateDevice('A'.padRight(32, 'A')),
          throwsA(isA<CloudException>()),
        );
      } finally {
        await db.close();
        client.close();
      }
    },
  );
  test(
    'Senha administrativa persiste, bloqueia ao reiniciar e código antigo não a apaga',
    () async {
      final guard = AdminGuard();
      await guard.load('loja|admin');
      await guard.resetAfterActivation('generation1');
      await expectLater(guard.create('123'), throwsFormatException);
      await guard.create('senha-de-teste-segura');
      expect(guard.unlocked, true);
      final reopened = AdminGuard();
      await reopened.load('loja|admin');
      expect(reopened.unlocked, false);
      expect(reopened.configured, true);
      await expectLater(reopened.unlock('incorreta'), throwsStateError);
      await reopened.resetAfterActivation('generation1');
      expect(reopened.configured, true);
      await reopened.unlock('senha-de-teste-segura');
      expect(reopened.unlocked, true);
      reopened.lock();
      expect(reopened.unlocked, false);
      await reopened.resetAfterActivation('generation2');
      expect(reopened.configured, false);
    },
  );
  testWidgets(
    'Aparelho de setor abre lançamento offline sem login ou responsável',
    (tester) async {
      final db = LocalDatabase(NativeDatabase.memory());
      final state = AppState(db);
      addTearDown(() async {
        state.dispose();
        await db.close();
      });
      await db.setSetting('role', 'operator');
      await db.setSetting('sector', 'cozinha');
      await db.setSetting('access_verified', '1');
      await db.setSetting('device_mode', '1');
      await db.setSetting('auto_backup', 'false');
      await state.load();
      await tester.pumpWidget(ConsumptionApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Novo lançamento'), findsOneWidget);
      expect(find.text('Cozinha'), findsWidgets);
      expect(find.text('E-mail'), findsNothing);
      expect(find.text('Responsável *'), findsNothing);
      expect(find.text('Administração'), findsNothing);
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .length,
        2,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Administração vinculada exige senha e bloqueia ações antes de desbloquear',
    (tester) async {
      final db = LocalDatabase(NativeDatabase.memory());
      final state = AppState(db);
      addTearDown(() async {
        state.dispose();
        await db.close();
      });
      await db.setSetting('role', 'admin');
      await db.setSetting('access_verified', '1');
      await db.setSetting('binding', 'loja|admin');
      await db.setSetting('auto_backup', 'false');
      await state.load();
      expect(state.canManage, false);
      expect(state.accessReady, false);
      expect(() => state.runAdministration(() async {}), throwsStateError);
      await tester.pumpWidget(ConsumptionApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Definir senha'), findsOneWidget);
      expect(find.text('E-mail'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
