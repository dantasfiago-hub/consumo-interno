import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:consumo_interno/infrastructure/local/database.dart';
import 'package:consumo_interno/domain/models.dart';

void main() {
  late LocalDatabase db;
  const p = Product(id: 'p', code: '0001', description: 'Arroz', unit: 'UN');
  Consumption sample() => Consumption(
    id: 'c',
    date: '2026-09-30',
    createdAt: '2026-09-30T00:00:00Z',
    operatorName: 'Ana',
    sector: 'Padaria',
    note: '',
    items: [
      const ConsumptionItem(
        id: 'i',
        productId: 'p',
        code: '0001',
        description: 'Arroz',
        unit: 'UN',
        amount: 3000,
        totalCents: 1350,
      ),
    ],
  );
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  test(
    'Produto e fila são gravados atomicamente; código não duplica',
    () async {
      await db.saveProduct(p);
      expect((await db.pending()).length, 1);
      await expectLater(
        db.saveProduct(
          const Product(
            id: 'p2',
            code: '0001',
            description: 'Outro',
            unit: 'KG',
          ),
        ),
        throwsA(anything),
      );
      expect((await db.products()).length, 1);
      expect((await db.pending()).length, 1);
    },
  );
  test('Consumo preserva total e o cancelamento mantém os itens', () async {
    await db.saveProduct(p);
    await db.saveConsumption(sample());
    await db.cancelConsumption(sample(), 'Registro incorreto');
    final c = (await db.consumptions()).single;
    expect(c.status, 'cancelled');
    expect(c.totalCents, 1350);
    expect(c.version, 2);
    expect((await db.pending()).length, 3);
    await expectLater(
      db.cancelConsumption(sample(), 'Outra justificativa'),
      throwsStateError,
    );
  });
  test('Recebimento remoto não sobrescreve alteração pendente', () async {
    await db.saveProduct(p);
    await db.acceptRemote('product', p.toJson()..['description'] = 'Mudou');
    expect((await db.products()).single.description, 'Arroz');
    await db.acknowledge((await db.pending()).single['op_id']);
    await db.acceptRemote('product', p.toJson()..['description'] = 'Mudou');
    expect((await db.products()).single.description, 'Mudou');
  });
  test(
    'Backup restaura fotos, totais e IDs de operações sem duplicação',
    () async {
      await db.saveProduct(p);
      await db.saveConsumption(sample());
      final backup = await db.backup();
      final other = LocalDatabase(NativeDatabase.memory());
      try {
        await other.restore(backup);
        expect((await other.consumptions()).single.totalCents, 1350);
        expect(
          (await other.pending()).map((o) => o['op_id']).toList(),
          (await db.pending()).map((o) => o['op_id']).toList(),
        );
        await expectLater(other.restore(backup), throwsStateError);
        expect(jsonDecode(backup)['format'], 1);
      } finally {
        await other.close();
      }
    },
  );
  test('Falha em um item impede lançamento e operação parcial', () async {
    await db.saveProduct(p);
    final bad = Consumption.fromJson(
      sample().toJson()
        ..['items'] = [sample().items.single.toJson()..['amount'] = 1500],
    );
    await expectLater(db.saveConsumption(bad), throwsFormatException);
    expect(await db.consumptions(), isEmpty);
    expect((await db.pending()).length, 1);
  });
  test('Arquivo SQLite mantém foto e pendência após reiniciar', () async {
    final directory = await Directory.systemTemp.createTemp('consumo_test_');
    final file = File('${directory.path}/dados.sqlite');
    final photo = base64Encode([255, 216, 255, 217]);
    final first = LocalDatabase(NativeDatabase(file));
    await first.saveProduct(
      Product(
        id: 'photo',
        code: '002',
        description: 'Com foto',
        unit: 'KG',
        photo: photo,
      ),
    );
    final operation = (await first.pending()).single['op_id'];
    await first.close();
    final second = LocalDatabase(NativeDatabase(file));
    try {
      expect((await second.products()).single.photo, photo);
      expect((await second.pending()).single['op_id'], operation);
    } finally {
      await second.close();
      await directory.delete(recursive: true);
    }
  });
  test('Resolução arquiva conteúdo local antes de adotar a nuvem', () async {
    await db.setSetting('role', 'admin');
    await db.saveProduct(p);
    final remote = p.toJson()..['description'] = 'Arroz atualizado';
    await db.resolveWithRemote('product', 'p', remote);
    expect(await db.pending(), isEmpty);
    expect((await db.products()).single.description, 'Arroz atualizado');
    final backup = jsonDecode(await db.backup());
    final archive = jsonDecode(backup['archives'].single['body']);
    expect(archive['local']['description'], 'Arroz');
    expect(archive['operations'].length, 1);
  });
  test(
    'Sincronização aplica troca de códigos de várias páginas atomicamente',
    () async {
      await db.saveProduct(p);
      const other = Product(
        id: 'p2',
        code: '0002',
        description: 'Café',
        unit: 'UN',
      );
      await db.saveProduct(other);
      for (final op in await db.pending()) {
        await db.acknowledge(op['op_id']);
      }
      await db.stageRemote([
        {
          'kind': 'product',
          'id': 'p2',
          'created_by': 'admin',
          'body': other.toJson()
            ..['code'] = '0001'
            ..['version'] = 2,
        },
      ]);
      await db.stageRemote([
        {
          'kind': 'product',
          'id': 'p',
          'created_by': 'admin',
          'body': p.toJson()
            ..['code'] = '0002'
            ..['version'] = 2,
        },
      ]);
      await db.commitIncoming('12');
      expect((await db.products()).firstWhere((p) => p.id == 'p').code, '0002');
      expect(
        (await db.products()).firstWhere((p) => p.id == 'p2').code,
        '0001',
      );
      expect(await db.setting('entity_cursor'), '12');
    },
  );
  test('Falha no merge mantém registros e cursor sem avançar', () async {
    await db.saveProduct(p);
    const other = Product(
      id: 'p2',
      code: '0002',
      description: 'Café',
      unit: 'UN',
    );
    await db.saveProduct(other);
    await db.acknowledge((await db.pending()).last['op_id']);
    await db.setSetting('entity_cursor', '4');
    await db.stageRemote([
      {
        'kind': 'product',
        'id': 'p2',
        'created_by': 'admin',
        'body': other.toJson()
          ..['code'] = '0001'
          ..['version'] = 2,
      },
    ]);
    await expectLater(db.commitIncoming('5'), throwsA(anything));
    expect((await db.products()).firstWhere((p) => p.id == 'p2').code, '0002');
    expect(await db.setting('entity_cursor'), '4');
  });
}
