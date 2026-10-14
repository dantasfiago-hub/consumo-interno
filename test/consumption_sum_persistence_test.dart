import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/app/app_state.dart';
import 'package:consumo_interno/core/formatting/sum_expression.dart';
import 'package:consumo_interno/domain/models.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Sums remain numeric and durable without forcing a weekly backup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sum-persistence',
      );
      final file = File('${directory.path}/data.sqlite');
      var db = LocalDatabase(NativeDatabase(file));
      var state = AppState(db);
      try {
        await db.setSetting('role', 'admin');
        await db.setSetting('access_verified', '1');
        await db.setSetting('backup_directory', '${directory.path}/backups');
        final previous = DateTime.now().toUtc().toIso8601String();
        await db.setSetting('backup_last', previous);
        await state.load();
        await state.saveProduct(
          const Product(
            id: 'p',
            code: '001',
            description: 'Produto',
            unit: 'UN',
            sectorIds: ['padaria'],
          ),
        );
        await state.saveConsumption(
          Consumption(
            id: 'c',
            date: '2026-10-14',
            createdAt: '2026-10-14T12:00:00Z',
            operatorName: 'Teste',
            sector: 'Padaria',
            note: '',
            items: [
              ConsumptionItem(
                id: 'i',
                productId: 'p',
                code: '001',
                description: 'Produto',
                unit: 'UN',
                amount: parseSumQuantity('10+20+5', 'UN'),
                totalCents: parseSumScaled('0,1+0,2', 2),
              ),
            ],
          ),
        );
        expect(await db.setting('backup_last'), previous);
        expect(await Directory('${directory.path}/backups').exists(), isFalse);
        final body = jsonDecode(
          (await db.pending()).singleWhere(
            (op) => op['kind'] == 'consumption',
          )['body'],
        );
        expect(body['items'].single['amount'], 35000);
        expect(body['items'].single['total_cents'], 30);
        final operations = (await db.pending()).map((o) => o['op_id']).toList();
        state.dispose();
        await db.close();
        db = LocalDatabase(NativeDatabase(file));
        state = AppState(db);
        await state.load();
        expect(state.consumptions, hasLength(1));
        expect(state.consumptions.single.items.single.amount, 35000);
        expect(state.consumptions.single.totalCents, 30);
        expect(
          (await db.pending()).map((o) => o['op_id']).toList(),
          operations,
        );
        await state.cancel(state.consumptions.single, 'Teste de cancelamento');
        expect(state.consumptions.single.status, 'cancelled');
        expect(state.consumptions.single.totalCents, 30);
        expect(await db.setting('backup_last'), previous);
        expect(await Directory('${directory.path}/backups').exists(), isFalse);
      } finally {
        state.dispose();
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
