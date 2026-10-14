import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/infrastructure/cloud/cloud_service.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Revogação confirmada invalida a permissão local em vez de manter acesso offline',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = LocalDatabase(NativeDatabase.memory());
      var revoked = false;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(
            jsonEncode({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {'id': '22222222-2222-4222-8222-222222222222'},
            }),
            200,
          );
        }
        return http.Response(
          revoked ? '[]' : '[{"role":"operator","sector":"cozinha"}]',
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
        await cloud.login('ana@example.com', 'password');
        expect(await db.setting('sector'), 'cozinha');
        revoked = true;
        await expectLater(cloud.refresh(), throwsA(isA<CloudException>()));
        expect(await db.setting('role'), 'unconfigured');
        expect(await db.setting('sector'), '');
        expect(await db.setting('access_verified'), '0');
      } finally {
        await db.close();
        client.close();
      }
    },
  );
  test(
    'Reenvio usa o mesmo ID quando o servidor grava mas a resposta se perde',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = LocalDatabase(NativeDatabase.memory());
      const store = '11111111-1111-4111-8111-111111111111';
      const user = '22222222-2222-4222-8222-222222222222';
      final ids = <String>[];
      var first = true;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(
            jsonEncode({
              'access_token': 'test',
              'refresh_token': 'refresh',
              'user': {'id': user},
            }),
            200,
          );
        }
        if (request.url.path.contains('memberships')) {
          return http.Response('[{"role":"admin"}]', 200);
        }
        if (request.url.path.contains('apply_operation')) {
          ids.add(jsonDecode(request.body)['p_operation']);
          if (first) {
            first = false;
            throw const CloudException('Resposta perdida');
          }
          return http.Response('{"ok":true,"duplicate":true}', 200);
        }
        return http.Response('[]', 200);
      });
      final cloud = CloudService(db, client: client);
      try {
        await cloud.configure(
          'https://example.supabase.co',
          'public-key',
          store,
        );
        await cloud.login('ana@example.com', 'password');
        await db.saveProduct(
          const Product(
            id: '33333333-3333-4333-8333-333333333333',
            code: '01',
            description: 'Café',
            unit: 'UN',
          ),
        );
        await expectLater(cloud.sync(), throwsA(isA<CloudException>()));
        expect((await db.pending()).length, 1);
        await cloud.sync();
        expect(await db.pending(), isEmpty);
        expect(ids.length, 2);
        expect(ids[0], ids[1]);
      } finally {
        await db.close();
        client.close();
      }
    },
  );
  test(
    'Lote por setor repete UUID após resposta perdida e inclui perfil versionado',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = LocalDatabase(NativeDatabase.memory());
      final ids = <String>[];
      var lost = true;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(
            jsonEncode({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {'id': '22222222-2222-4222-8222-222222222222'},
            }),
            200,
          );
        }
        if (request.url.path.contains('memberships')) {
          return http.Response('[{"role":"admin"}]', 200);
        }
        final body = jsonDecode(request.body);
        ids.add(body['p_id']);
        expect(request.url.path, contains('create_export_batch_v3'));
        expect(body['p_sector'], 'padaria');
        expect(body['p_profile']['validated'], true);
        expect(body['p_profile']['version'], 1);
        if (lost) {
          lost = false;
          throw const CloudException('Resposta perdida');
        }
        return http.Response(
          jsonEncode({
            'id': body['p_id'],
            'version': 1,
            'status': 'prepared',
            'rows': [],
          }),
          200,
        );
      });
      final cloud = CloudService(db, client: client);
      try {
        await cloud.configure(
          'https://example.supabase.co',
          'public-key',
          '11111111-1111-4111-8111-111111111111',
        );
        await cloud.login('ana@example.com', 'password');
        final item = ConsumptionItem(
          id: uuid.v4(),
          productId: uuid.v4(),
          code: '0001',
          description: 'Produto',
          unit: 'UN',
          amount: 1000,
          totalCents: 200,
        );
        final c = Consumption(
          id: uuid.v4(),
          date: '2026-10-02',
          createdAt: '2026-10-02T12:00:00Z',
          operatorName: 'Ana',
          sector: 'padaria',
          note: '',
          items: [item],
        );
        final rows = [ReportRow(c, item)];
        await expectLater(
          cloud.createBatch(rows, const ExportProfile(validated: true), {
            'sector': 'padaria',
          }),
          throwsA(isA<CloudException>()),
        );
        await cloud.createBatch(rows, const ExportProfile(validated: true), {
          'sector': 'padaria',
        });
        expect(ids.length, 2);
        expect(ids.first, ids.last);
      } finally {
        await db.close();
        client.close();
      }
    },
  );
  test(
    'Confirmação de salvamento fica pendente e repete o mesmo evento',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = LocalDatabase(NativeDatabase.memory());
      final events = <String>[];
      var lost = true;
      final client = MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(
            jsonEncode({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {'id': '22222222-2222-4222-8222-222222222222'},
            }),
            200,
          );
        }
        if (request.url.path.contains('memberships')) {
          return http.Response('[{"role":"admin"}]', 200);
        }
        if (request.url.path.contains('update_export_batch_v2')) {
          final body = jsonDecode(request.body);
          events.add(body['p_event']);
          if (lost) {
            lost = false;
            throw const CloudException('Resposta perdida');
          }
          return http.Response(
            jsonEncode({
              'id': body['p_id'],
              'status': 'downloaded',
              'version': 3,
              'rows': [],
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });
      final cloud = CloudService(db, client: client);
      try {
        await cloud.configure(
          'https://example.supabase.co',
          'public-key',
          '11111111-1111-4111-8111-111111111111',
        );
        await cloud.login('ana@example.com', 'password');
        await db.acceptRemote('export_receipt', {
          'id': uuid.v4(),
          'batch_id': uuid.v4(),
          'version': 2,
        });
        await expectLater(cloud.sync(), throwsA(isA<CloudException>()));
        expect((await db.records('export_receipt')).length, 1);
        await cloud.sync();
        expect(await db.records('export_receipt'), isEmpty);
        expect(events.length, 2);
        expect(events.first, events.last);
      } finally {
        await db.close();
        client.close();
      }
    },
  );
}
