import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:consumo_interno/infrastructure/cloud/cloud_service.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Trocar projeto não envia a credencial antiga ao projeto novo', () async {
    FlutterSecureStorage.setMockInitialValues({'refresh_token':'old-private-token'});
    final db = LocalDatabase(NativeDatabase.memory());
    const oldStore='11111111-1111-4111-8111-111111111111';
    const newStore='33333333-3333-4333-8333-333333333333';
    await db.setSetting('cloud_url','https://old.supabase.co');
    await db.setSetting('cloud_key','public');
    await db.setSetting('store',oldStore);
    await db.setSetting('binding','https://old.supabase.co|$oldStore|actor');
    await db.setSetting('device_setup_mode','1');
    await db.setSetting('device','22222222-2222-4222-8222-222222222222');
    await db.acceptRemote('product',{'id':'old','code':'old','photo':null});
    var signup=false;
    final client=MockClient((request) async {
      expect(request.url.host,'new.supabase.co');
      expect(request.body.contains('old-private-token'),isFalse);
      if(request.url.path.endsWith('/signup')) {
        signup=true;
        return http.Response(jsonEncode({'access_token':'new-token','refresh_token':'new-private-token','user':{'id':'44444444-4444-4444-8444-444444444444'}}),200);
      }
      if(request.url.path.endsWith('/activate_sector_device')) return http.Response('{"activated":true,"slot":"cozinha"}',200);
      return http.Response('[{"role":"operator","sector":"cozinha","features_version":7}]',200);
    });
    final cloud=CloudService(db,client:client);
    addTearDown(() async {client.close();await db.close();});
    await cloud.configure('https://new.supabase.co','public',newStore);
    await cloud.activateDevice('A'*32);
    expect(signup,isTrue);
    expect(await db.records('product'),isEmpty);
    expect(await db.setting('store'),newStore);
    expect(await db.setting('access_verified'),'0');
  });
}
