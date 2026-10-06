import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/infrastructure/cloud/cloud_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Foto atrasada é recuperada sem nova revisão dos metadados', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = LocalDatabase(NativeDatabase.memory());
    final photo = base64Encode(utf8.encode('foto atrasada'));
    final hash = sha256.convert(base64Decode(photo)).toString();
    var available = false;
    final client = MockClient((r) async {
      dynamic response = [];
      if (r.url.path.contains('/auth/')) {
        response = {
          'access_token': 'token',
          'refresh_token': 'refresh',
          'user': {'id': 'ana'},
        };
      }
      if (r.url.path.endsWith('memberships')) {
        response = [
          {'role': 'admin', 'features_version': 4},
        ];
      }
      if (r.url.path.endsWith('entities') &&
          r.url.queryParameters['revision'] == 'gt.0') {
        response = [
          {
            'id': 'p',
            'kind': 'product',
            'revision': 1,
            'body': {
              'id': 'p',
              'code': '01',
              'description': 'Produto',
              'unit': 'UN',
              'active': true,
              'version': 1,
              'sectors': ['cozinha'],
              'photo': null,
              'photo_hash': hash,
            },
          },
        ];
      }
      if (r.url.path.endsWith('product_images') && available) {
        response = [
          {'hash': hash, 'data_base64': photo},
        ];
      }
      return http.Response(jsonEncode(response), 200);
    });
    final cloud = CloudService(db, client: client);
    try {
      await cloud.configure(
        'https://example.supabase.co',
        'public',
        '11111111-1111-4111-8111-111111111111',
      );
      await cloud.login('ana@test', 'password');
      await cloud.sync();
      expect((await db.products()).single.photo, isNull);
      available = true;
      await cloud.sync();
      expect((await db.products()).single.photo, photo);
      expect(await db.setting('entity_cursor'), '1');
    } finally {
      await db.close();
      client.close();
    }
  });
  test('Administração carrega registros além da primeira página', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = LocalDatabase(NativeDatabase.memory());
    final offsets = <int>[];
    final client = MockClient((r) async {
      dynamic response = [];
      if (r.url.path.contains('/auth/')) {
        response = {
          'access_token': 'token',
          'refresh_token': 'refresh',
          'user': {'id': 'ana'},
        };
      }
      if (r.url.path.endsWith('memberships')) {
        response = [
          {'role': 'admin', 'features_version': 4},
        ];
      }
      if (r.url.path.endsWith('sync_issues')) {
        final offset = int.parse(r.url.queryParameters['offset'] ?? '0');
        offsets.add(offset);
        response = List.generate(
          offset == 0 ? 100 : 1,
          (i) => {'operation_id': 'op-${offset + i}'},
        );
      }
      return http.Response(jsonEncode(response), 200);
    });
    final cloud = CloudService(db, client: client);
    try {
      await cloud.configure(
        'https://example.supabase.co',
        'public',
        '11111111-1111-4111-8111-111111111111',
      );
      await cloud.login('ana@test', 'password');
      final rows = await cloud.adminList('sync_issues');
      expect(rows.length, 101);
      expect(offsets, [0, 100]);
    } finally {
      await db.close();
      client.close();
    }
  });
}
