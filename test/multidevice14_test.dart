import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/features/exports/domain/export.dart';
import 'package:consumo_interno/infrastructure/cloud/cloud_service.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

class DeviceStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dois dispositivos: exportação concorrente ao cancelamento offline, revisão e cache incremental',
    () async {
      final phoneDb = LocalDatabase(NativeDatabase.memory());
      final pcDb = LocalDatabase(NativeDatabase.memory());
      final photo = base64Encode(utf8.encode('foto compartilhada'));
      final hash = sha256.convert(base64Decode(photo)).toString();
      final product = Product(
        id: uuid.v4(),
        code: '001',
        description: 'Farinha',
        unit: 'KG',
        sectorIds: const ['cozinha'],
        photoHash: hash,
      );
      final second = Product(
        id: uuid.v4(),
        code: '002',
        description: 'Açúcar',
        unit: 'KG',
        sectorIds: const ['cozinha'],
        photoHash: hash,
      );
      final item = ConsumptionItem(
        id: uuid.v4(),
        productId: product.id,
        code: product.code,
        description: product.description,
        unit: 'KG',
        amount: 2350,
        totalCents: 7050,
      );
      final consumption = Consumption(
        id: uuid.v4(),
        date: '2026-10-04',
        createdAt: '2026-10-04T12:00:00Z',
        operatorName: 'Ana',
        sector: 'cozinha',
        note: '',
        items: [item],
      );
      final entities = <Map<String, dynamic>>[
        {
          'id': product.id,
          'kind': 'product',
          'body': product.toJson(),
          'revision': 1,
          'sector_id': null,
          'export_locked': false,
        },
        {
          'id': second.id,
          'kind': 'product',
          'body': second.toJson(),
          'revision': 2,
          'sector_id': null,
          'export_locked': false,
        },
        {
          'id': consumption.id,
          'kind': 'consumption',
          'body': consumption.toJson(),
          'revision': 3,
          'sector_id': 'cozinha',
          'export_locked': false,
        },
      ];
      final issues = <Map<String, dynamic>>[];
      final photoDownloads = <String, int>{};
      final applyDevices = <String>[];
      Map<String, dynamic>? batch;
      var cancellationAttempts = 0;
      final client = MockClient((request) async {
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        final path = request.url.path;
        final actor =
            request.headers['Authorization']?.replaceFirst('Bearer ', '') ?? '';
        http.Response reply(dynamic v, [int status = 200]) =>
            http.Response(jsonEncode(v), status);
        if (path.contains('/auth/')) {
          final user =
              body['email'] == 'pc@loja.test' || body['refresh_token'] == 'pc'
              ? 'pc'
              : 'phone';
          return reply({
            'access_token': user,
            'refresh_token': user,
            'user': {'id': user},
          });
        }
        if (path.endsWith('memberships')) {
          return reply([
            {
              'role': actor == 'pc' ? 'admin' : 'operator',
              'sector': actor == 'pc' ? null : 'cozinha',
              'features_version': 4,
            },
          ]);
        }
        if (path.endsWith('product_images')) {
          photoDownloads[actor] = (photoDownloads[actor] ?? 0) + 1;
          return reply([
            {'hash': hash, 'data_base64': photo},
          ]);
        }
        if (path.endsWith('entities')) {
          var rows = entities.where(
            (e) =>
                request.url.queryParameters['kind'] == null ||
                request.url.queryParameters['kind'] == 'eq.${e['kind']}',
          );
          final id = request.url.queryParameters['id'];
          if (id?.startsWith('eq.') == true) {
            rows = rows.where((e) => 'eq.${e['id']}' == id);
          }
          final rev = request.url.queryParameters['revision'];
          if (rev != null) {
            rows = rows.where(
              (e) => e['revision'] > int.parse(rev.substring(3)),
            );
          }
          return reply(rows.toList());
        }
        if (path.endsWith('sync_issues')) {
          return reply(
            issues
                .where(
                  (i) =>
                      request.url.queryParameters['actor'] == null ||
                      (i['status'] == 'accept_remote' && i['actor'] == actor),
                )
                .toList(),
          );
        }
        if (path.endsWith('create_export_batch_v3')) {
          expect(actor, 'pc');
          expect(body['p_sector'], 'cozinha');
          entities.last['export_locked'] = true;
          entities.last['revision'] = 4;
          batch = {
            'id': body['p_id'],
            'version': 1,
            'status': 'prepared',
            'sector': 'cozinha',
            'rows': [],
          };
          return reply(batch);
        }
        if (path.endsWith('apply_operation')) {
          cancellationAttempts++;
          applyDevices.add(body['p_device']);
          expect(actor, 'phone');
          expect(body['p_body']['status'], 'cancelled');
          return reply({'message': 'Consumo protegido pela exportação'}, 400);
        }
        if (path.endsWith('report_sync_issue')) {
          issues.add({
            'operation_id': body['p_operation'],
            'kind': body['p_kind'],
            'entity_id': body['p_entity'],
            'actor': actor,
            'status': 'pending',
            'snapshot': body['p_body'],
            'device_id': body['p_device'],
          });
          return reply(null);
        }
        if (path.endsWith('admin_review_issue')) {
          expect(actor, 'pc');
          expect(body['p_action'], 'accept_remote');
          final issue = issues.singleWhere(
            (i) => i['operation_id'] == body['p_operation'],
          );
          issue['status'] = 'accept_remote';
          issue['review_reason'] = body['p_reason'];
          return reply(null);
        }
        if (path.endsWith('export_batches')) {
          return reply(
            batch == null
                ? []
                : [
                    {'body': batch},
                  ],
          );
        }
        if (path.endsWith('upload_device_backup')) {
          final compressed = base64Decode(body['p_payload']);
          expect(sha256.convert(compressed).toString(), body['p_hash']);
          return reply(null);
        }
        throw StateError('Requisição inesperada: ${request.url}');
      });
      final phone = CloudService(
        phoneDb,
        client: client,
        storage: DeviceStorage(),
      );
      final pc = CloudService(pcDb, client: client, storage: DeviceStorage());
      try {
        for (final cloud in [phone, pc]) {
          await cloud.configure(
            'https://example.supabase.co',
            'public',
            '11111111-1111-4111-8111-111111111111',
          );
        }
        await phone.login('phone@loja.test', 'password');
        await pc.login('pc@loja.test', 'password');
        await phone.sync();
        await pc.sync();
        expect((await phoneDb.products()).length, 2);
        expect(photoDownloads, {'phone': 1, 'pc': 1});
        await pc.createBatch(
          [ReportRow(consumption, item)],
          const ExportProfile(validated: true),
          {'sector': 'cozinha'},
        );
        // The phone is still offline and has not received the export reservation.
        await phoneDb.cancelConsumption(
          (await phoneDb.consumptions()).single,
          'Quantidade incorreta',
        );
        await expectLater(phone.sync(), throwsA(isA<CloudException>()));
        expect((await phoneDb.pending()).length, 1);
        expect(issues.single['status'], 'pending');
        await pc.reviewIssue(
          issues.single['operation_id'],
          'accept_remote',
          'Preservar consumo reservado',
        );
        await phone.sync();
        expect(await phoneDb.pending(), isEmpty);
        final restored = (await phoneDb.consumptions()).single;
        expect(restored.status, 'confirmed');
        expect(restored.exportLocked, true);
        expect(cancellationAttempts, 1);
        expect(photoDownloads, {'phone': 1, 'pc': 1});
        expect(applyDevices.single, isNot(await pcDb.setting('device')));
        final archives = await phoneDb
            .customSelect('SELECT body FROM archives')
            .get();
        expect(
          archives.single.data['body'],
          contains('Preservar consumo reservado'),
        );
        expect(archives.single.data['body'], contains('Quantidade incorreta'));
      } finally {
        await phoneDb.close();
        await pcDb.close();
        client.close();
      }
    },
  );
}
