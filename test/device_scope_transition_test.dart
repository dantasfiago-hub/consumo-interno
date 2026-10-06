import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  test(
    'Limpeza de escopo recusa operações pendentes sem apagar registros',
    () async {
      final db = LocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.acceptRemote('product', {'id': 'p', 'code': '1', 'photo': null});
      await db.customStatement(
        "INSERT INTO outbox(op_id,kind,entity_id,expected_version,body) VALUES('op','product','p',0,'{}')",
      );
      await expectLater(db.clearDeviceScope(), throwsStateError);
      expect(await db.record('product', 'p'), isNotNull);
    },
  );
  test('Limpeza de escopo recusa recibos e mantém o aparelho', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.setSetting('device', 'installation');
    await db.acceptRemote('export_receipt', {'id': 'receipt'});
    await expectLater(db.clearDeviceScope(), throwsStateError);
    await db.removeExportReceipt('receipt');
    await db.acceptRemote('product', {'id': 'p', 'code': '1', 'photo': null});
    await db.setSetting('binding', 'original');
    await db.clearDeviceScope();
    expect(await db.records('product'), isEmpty);
    expect(await db.setting('device'), 'installation');
    expect(await db.setting('binding'), 'original');
    expect(await db.setting('access_verified'), '0');
  });
}
