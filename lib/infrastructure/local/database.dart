import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../core/backup/backup_envelope.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models.dart';
import '../../core/access/sectors.dart';
import '../../features/exports/domain/export.dart';

const uuid = Uuid();

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);
  static Future<LocalDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    return LocalDatabase(
      NativeDatabase.createInBackground(
        File(p.join(dir.path, 'consumo.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE records(kind TEXT NOT NULL, id TEXT NOT NULL, code TEXT, body TEXT NOT NULL, PRIMARY KEY(kind,id))',
      );
      await customStatement(
        "CREATE UNIQUE INDEX unique_product_code ON records(code) WHERE kind='product'",
      );
      await customStatement(
        'CREATE TABLE outbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, entity_id TEXT NOT NULL, expected_version INTEGER NOT NULL, body TEXT NOT NULL, error TEXT)',
      );
      await customStatement(
        'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE archives(id TEXT PRIMARY KEY, body TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE incoming(kind TEXT NOT NULL,id TEXT NOT NULL,code TEXT,body TEXT NOT NULL,PRIMARY KEY(kind,id))',
      );
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) {
        await customStatement(
          'CREATE TABLE IF NOT EXISTS archives(id TEXT PRIMARY KEY,body TEXT NOT NULL)',
        );
        await customStatement(
          'CREATE TABLE IF NOT EXISTS incoming(kind TEXT NOT NULL,id TEXT NOT NULL,code TEXT,body TEXT NOT NULL,PRIMARY KEY(kind,id))',
        );
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<String?> setting(String key) async {
    final r = await customSelect(
      'SELECT value FROM settings WHERE key=?',
      variables: [Variable.withString(key)],
    ).get();
    return r.isEmpty ? null : r.first.read<String>('value');
  }

  Future<void> setSetting(String key, String value) => customStatement(
    'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  Future<List<Json>> records(String kind) async => (await customSelect(
    'SELECT body FROM records WHERE kind=? ORDER BY rowid DESC',
    variables: [Variable.withString(kind)],
  ).get()).map((r) => decodeObject(r.read<String>('body'))).toList();
  Future<Json?> record(String kind, String id) async {
    final r = await customSelect(
      'SELECT body FROM records WHERE kind=? AND id=?',
      variables: [Variable.withString(kind), Variable.withString(id)],
    ).get();
    return r.isEmpty ? null : decodeObject(r.first.read<String>('body'));
  }

  Future<List<Product>> products() async {
    final products = await records('product');
    final hashes = products
        .map((p) => p['photo_hash'])
        .whereType<String>()
        .toSet();
    final images = {
      for (final image in await _imagesFor(hashes))
        image['id']: image['data_base64'],
    };
    return products
        .map(
          (p) => Product.fromJson({
            ...p,
            if (p['photo'] == null && images.containsKey(p['photo_hash']))
              'photo': images[p['photo_hash']],
          }),
        )
        .toList();
  }

  Future<List<Json>> _imagesFor(Set<String> hashes) async {
    final ids = hashes.toList();
    final images = <Json>[];
    for (var i = 0; i < ids.length; i += 100) {
      final part = ids.sublist(i, (i + 100).clamp(0, ids.length));
      final rows = await customSelect(
        "SELECT body FROM records WHERE kind='image' AND id IN (${List.filled(part.length, '?').join(',')})",
        variables: part.map(Variable.withString).toList(),
      ).get();
      images.addAll(rows.map((r) => decodeObject(r.read<String>('body'))));
    }
    return images;
  }

  Future<List<Consumption>> consumptions() async =>
      (await records('consumption')).map(Consumption.fromJson).toList();
  Future<void> _put(String kind, Json body) async {
    if (kind == 'product' && body['photo'] != null) {
      final hash = sha256.convert(base64Decode(body['photo'])).toString();
      await _put('image', {'id': hash, 'data_base64': body['photo']});
      body = {...body, 'photo': null, 'photo_hash': hash};
    }
    await customStatement(
      'INSERT INTO records(kind,id,code,body) VALUES(?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET code=excluded.code,body=excluded.body',
      [
        kind,
        body['id'],
        kind == 'product' ? body['code'] : null,
        jsonEncode(body),
      ],
    );
  }

  Future<void> saveProduct(Product product, {int expectedVersion = 0}) async {
    validateProduct(product);
    if (product.code.trim().isEmpty ||
        product.description.trim().isEmpty ||
        !['UN', 'KG'].contains(product.unit)) {
      throw StateError('Preencha código, descrição e unidade.');
    }
    if ((product.photo?.length ?? 0) > 180000) {
      throw StateError('Foto muito grande.');
    }
    await _save('product', product.toJson(), expectedVersion);
  }

  Future<void> saveConsumption(Consumption c) async {
    validateConsumption(c);
    if (c.status != 'confirmed' || c.version != 1) {
      throw StateError('Novo lançamento deve estar confirmado na versão 1.');
    }
    if (c.items.isEmpty || c.operatorName.trim().isEmpty) {
      throw StateError('Informe responsável e produtos.');
    }
    if (c.items.length > 200) {
      throw StateError('Limite de 200 itens por lançamento.');
    }
    if (c.items.map((i) => i.productId).toSet().length != c.items.length) {
      throw StateError('Produto repetido no lançamento.');
    }
    for (final i in c.items) {
      if (i.amount <= 0 ||
          i.totalCents <= 0 ||
          i.amount > 999999999999 ||
          i.totalCents > 999999999999 ||
          !['UN', 'KG'].contains(i.unit) ||
          (i.unit == 'UN' && i.amount % 1000 != 0)) {
        throw StateError('Quantidade ou valor inválido.');
      }
      final p = await record('product', i.productId);
      if (p == null ||
          p['active'] != true ||
          p['unit'] != i.unit ||
          p['code'] != i.code) {
        throw StateError('Produto indisponível ou unidade alterada.');
      }
    }
    await _save('consumption', c.toJson(), 0);
  }

  Future<void> cancelConsumption(Consumption c, String reason) async {
    if (c.exportLocked ||
        c.status != 'confirmed' ||
        reason.trim().length < 3 ||
        reason.trim().length > 300) {
      throw StateError('Informe uma justificativa.');
    }
    final body = c.toJson()
      ..['status'] = 'cancelled'
      ..['cancellation_reason'] = reason.trim()
      ..['version'] = c.version + 1
      ..['cancelled_at'] = DateTime.now().toUtc().toIso8601String()
      ..['_sector_id'] = c.sectorId
      ..['_export_locked'] = false;
    await _save('consumption', body, c.version);
  }

  Future<void> _save(
    String kind,
    Json body,
    int expected,
  ) => transaction(() async {
    final current = await record(kind, body['id']);
    if ((current?['version'] ?? 0) != expected) {
      throw StateError('Registro alterado. Reabra antes de salvar.');
    }
    if (kind == 'consumption' &&
        expected > 0 &&
        current?['_export_locked'] == true) {
      throw StateError('Consumo protegido por exportação.');
    }
    if (body['version'] != expected + 1) {
      throw StateError('Versão do registro inválida.');
    }
    await _put(kind, body);
    if (kind == 'consumption' && expected == 0) {
      await setSetting('operator', body['operator']);
    }
    await customStatement(
      'INSERT INTO outbox(op_id,kind,entity_id,expected_version,body) VALUES(?,?,?,?,?)',
      [uuid.v4(), kind, body['id'], expected, jsonEncode(body)],
    );
  });
  Future<List<Json>> pending() async => (await customSelect(
    'SELECT * FROM outbox ORDER BY seq',
  ).get()).map((r) => r.data).toList();
  Future<bool> hasPending(String kind, String id) async => (await customSelect(
    'SELECT seq FROM outbox WHERE kind=? AND entity_id=? LIMIT 1',
    variables: [Variable.withString(kind), Variable.withString(id)],
  ).get()).isNotEmpty;
  Future<void> acknowledge(String opId) =>
      customStatement('DELETE FROM outbox WHERE op_id=?', [opId]);
  Future<void> fail(String opId, String error) =>
      customStatement('UPDATE outbox SET error=? WHERE op_id=?', [error, opId]);
  Future<void> acceptRemote(String kind, Json body) => transaction(() async {
    if (!await hasPending(kind, body['id'])) await _put(kind, body);
  });
  Future<void> pruneSectorScope(
    Set<String> visible,
    String sector,
  ) => transaction(() async {
    for (final kind in ['product', 'consumption']) {
      for (final body in await records(kind)) {
        final pending = await hasPending(kind, body['id']);
        final inScope = kind == 'product'
            ? (body['sectors'] as List? ?? []).contains(sector)
            : (body['_sector_id'] ?? sectorKey(body['sector'] ?? '')) == sector;
        // Keep in-scope offline inserts not visible on the server yet.
        if (inScope && (visible.contains('$kind/${body['id']}') || pending)) {
          continue;
        }
        if (pending) {
          final ops = (await this.pending())
              .where((o) => o['kind'] == kind && o['entity_id'] == body['id'])
              .toList();
          await customStatement('INSERT INTO archives(id,body) VALUES(?,?)', [
            uuid.v4(),
            jsonEncode({
              'reason': 'Registro fora do setor após atualização de acesso',
              'local': body,
              'operations': ops,
            }),
          ]);
          await customStatement(
            'DELETE FROM outbox WHERE kind=? AND entity_id=?',
            [kind, body['id']],
          );
        }
        await customStatement('DELETE FROM records WHERE kind=? AND id=?', [
          kind,
          body['id'],
        ]);
      }
    }
    for (final receipt in await records('export_receipt')) {
      await customStatement('INSERT INTO archives(id,body) VALUES(?,?)', [
        uuid.v4(),
        jsonEncode({
          'reason':
              'Confirmação de exportação arquivada após mudança de acesso',
          'receipt': receipt,
        }),
      ]);
    }
    await customStatement(
      "DELETE FROM records WHERE kind IN ('batch','export_receipt','admin_cache')",
    );
  });
  Future<void> clearIncoming() => customStatement('DELETE FROM incoming');
  Future<void> stageRemote(List<dynamic> rows) => transaction(() async {
    for (final row in rows) {
      final kind = row['kind'] as String;
      final body = Map<String, dynamic>.from(row['body'])
        ..['_owner'] = row['created_by']
        ..['_sector_id'] = row['sector_id']
        ..['_export_locked'] = row['export_locked'] ?? false;
      if (kind == 'product' && body['photo'] != null) {
        final hash = sha256.convert(base64Decode(body['photo'])).toString();
        await _put('image', {'id': hash, 'data_base64': body['photo']});
        body['photo'] = null;
        body['photo_hash'] = hash;
      }
      await customStatement(
        'INSERT INTO incoming(kind,id,code,body) VALUES(?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET code=excluded.code,body=excluded.body',
        [
          kind,
          row['id'],
          kind == 'product' ? body['code'] : null,
          jsonEncode(body),
        ],
      );
    }
  });
  Future<void> commitIncoming(
    String cursor, {
    String? operatorId,
  }) => transaction(() async {
    // Remove stale code indexes together, then merge all incoming records atomically.
    // This also supports product code swaps whose changes arrived on different pages.
    await customStatement(
      'UPDATE records SET code=NULL WHERE kind=\'product\' AND EXISTS(SELECT 1 FROM incoming i WHERE i.kind=records.kind AND i.id=records.id) AND NOT EXISTS(SELECT 1 FROM outbox o WHERE o.kind=records.kind AND o.entity_id=records.id)',
    );
    await customStatement(
      'INSERT INTO records(kind,id,code,body) SELECT i.kind,i.id,i.code,i.body FROM incoming i WHERE NOT EXISTS(SELECT 1 FROM outbox o WHERE o.kind=i.kind AND o.entity_id=i.id) ON CONFLICT(kind,id) DO UPDATE SET code=excluded.code,body=excluded.body',
    );
    if (operatorId != null) {
      await customStatement('DELETE FROM records WHERE kind=\'batch\'');
      await customStatement(
        'DELETE FROM records WHERE kind=\'consumption\' AND json_extract(body,\'\$._owner\') IS NOT NULL AND json_extract(body,\'\$._owner\')<>? AND NOT EXISTS(SELECT 1 FROM outbox o WHERE o.kind=records.kind AND o.entity_id=records.id)',
        [operatorId],
      );
    }
    await setSetting('entity_cursor', cursor);
    await clearIncoming();
  });
  Future<void> resolveWithRemote(
    String kind,
    String id,
    Json? remote, {
    String reason = 'Usuário escolheu a versão da nuvem',
  }) => transaction(() async {
    final ops = (await pending())
        .where((op) => op['kind'] == kind && op['entity_id'] == id)
        .toList();
    if (ops.isEmpty) throw StateError('Não há pendência para resolver.');
    if (kind == 'product' &&
        remote == null &&
        (await consumptions()).any(
          (c) => c.items.any((i) => i.productId == id),
        )) {
      throw StateError(
        'Arquive primeiro os consumos que dependem deste produto.',
      );
    }
    final archive = {
      'kind': kind,
      'entity_id': id,
      'local': await record(kind, id),
      'operations': ops,
      'archived_at': DateTime.now().toUtc().toIso8601String(),
      'reason': reason,
    };
    await customStatement('INSERT INTO archives(id,body) VALUES(?,?)', [
      uuid.v4(),
      jsonEncode(archive),
    ]);
    await customStatement('DELETE FROM outbox WHERE kind=? AND entity_id=?', [
      kind,
      id,
    ]);
    if (remote == null) {
      await customStatement('DELETE FROM records WHERE kind=? AND id=?', [
        kind,
        id,
      ]);
    } else {
      await _put(kind, remote);
    }
  });
  Future<void> removeExportReceipt(String id) => customStatement(
    "DELETE FROM records WHERE kind='export_receipt' AND id=?",
    [id],
  );

  Future<List<Json>> _backupRecords(String kind) async {
    final role = await setting('role');
    final rows = await records(kind);
    if (role == null || role == 'admin') return rows;
    final sector = await setting('sector');
    if (role != 'operator' || !sectors.containsKey(sector)) return [];
    if (kind == 'product') {
      return rows
          .where((r) => (r['sectors'] as List? ?? []).contains(sector))
          .toList();
    }
    if (kind == 'consumption') {
      return rows
          .where(
            (r) => (r['_sector_id'] ?? sectorKey(r['sector'] ?? '')) == sector,
          )
          .toList();
    }
    return [];
  }

  Future<List<Json>> _backupPending() async {
    final role = await setting('role');
    final rows = await pending();
    if (role == null || role == 'admin') return rows;
    final sector = await setting('sector');
    if (role != 'operator' || !sectors.containsKey(sector)) return [];
    return rows
        .where(
          (r) =>
              r['kind'] == 'consumption' &&
              sectorKey(decodeObject(r['body'])['sector'] ?? '') == sector,
        )
        .toList();
  }

  Future<List<Json>> _backupArchives() async {
    final rows = (await customSelect(
      'SELECT id,body FROM archives',
    ).get()).map((r) => r.data).toList();
    if (await setting('role') == 'admin') return rows;
    final sector = await setting('sector');
    if (!sectors.containsKey(sector)) return [];
    return rows.where((r) {
      final body = decodeObject(r['body']);
      final local = body['local'];
      return local is Map &&
          (local['_sector_id'] ?? sectorKey(local['sector'] ?? '')) == sector;
    }).toList();
  }

  Future<List<Json>> _backupImages() async {
    final hashes = (await _backupRecords(
      'product',
    )).map((p) => p['photo_hash']).whereType<String>().toSet();
    for (final archive in await _backupArchives()) {
      final body = decodeObject(archive['body']);
      final local = body['local'];
      if (local is Map && local['photo_hash'] is String) {
        hashes.add(local['photo_hash']);
      }
    }
    for (final op in await _backupPending()) {
      final hash = decodeObject(op['body'])['photo_hash'];
      if (hash is String) hashes.add(hash);
    }
    // Old cached photos are not current data; do not let them inflate backups indefinitely.
    return _imagesFor(hashes);
  }

  Future<String> backup() => transaction(
    () async => jsonEncode({
      'format': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'products': await _backupRecords('product'),
      'images': await _backupImages(),
      'consumptions': await _backupRecords('consumption'),
      'batches': await _backupRecords('batch'),
      'export_receipts': await _backupRecords('export_receipt'),
      'preferences': {
        for (final key in [
          'export_profile',
          'favorites',
          'recent_products',
          'theme_mode',
        ])
          key: await setting(key),
      },
      'archives': await _backupArchives(),
      'outbox': await _backupPending(),
      'binding': await setting('binding'),
      'role': await setting('role'),
      'sector': await setting('sector'),
      'access_verified': await setting('access_verified'),
      'operator': await setting('operator'),
      'device': await setting('device'),
    }),
  );
  Future<void> restore(String text) async {
    final data = decodeObject(verifyBackupEnvelope(text));
    if (data['format'] != 1 ||
        data['products'] is! List ||
        data['consumptions'] is! List ||
        data['outbox'] is! List) {
      throw const FormatException('Backup inválido.');
    }
    // Force model decoding before any mutation. Restore is allowed only into an empty database.
    final products = (data['products'] as List)
        .map((x) => Product.fromJson(Map<String, dynamic>.from(x)))
        .toList();
    final consumptions = (data['consumptions'] as List)
        .map((x) => Consumption.fromJson(Map<String, dynamic>.from(x)))
        .toList();
    for (final p in products) {
      validateProduct(p);
    }
    for (final c in consumptions) {
      validateConsumption(c);
    }
    final preferences = data['preferences'] as Map? ?? {};
    for (final key in ['favorites', 'recent_products']) {
      if (preferences[key] != null) {
        List<String>.from(jsonDecode(preferences[key] as String));
      }
    }
    if (preferences['export_profile'] != null) {
      ExportProfile.fromJson(
        decodeObject(preferences['export_profile'] as String),
      ).validate();
    }
    for (final receipt in data['export_receipts'] ?? []) {
      if (receipt['id'] is! String ||
          receipt['batch_id'] is! String ||
          receipt['version'] is! int ||
          receipt['version'] < 1 ||
          DateTime.tryParse(receipt['created_at'] ?? '') == null) {
        throw const FormatException(
          'Confirmação de exportação inválida no backup.',
        );
      }
    }
    await transaction(() async {
      final currentBinding = await setting('binding');
      if (currentBinding != null && currentBinding != data['binding']) {
        throw StateError('O backup pertence a outra conta ou loja.');
      }
      if ((await records('product')).isNotEmpty ||
          (await records('consumption')).isNotEmpty ||
          (await records('batch')).isNotEmpty ||
          (await records('export_receipt')).isNotEmpty ||
          (await pending()).isNotEmpty) {
        throw StateError(
          'Restauração permitida apenas em uma instalação sem registros.',
        );
      }
      for (final image in data['images'] ?? []) {
        if (image['id'] is! String ||
            image['data_base64'] is! String ||
            sha256.convert(base64Decode(image['data_base64'])).toString() !=
                image['id']) {
          throw const FormatException('Imagem corrompida no backup.');
        }
        await _put('image', Map<String, dynamic>.from(image));
      }
      for (final p in products) {
        await _put('product', p.toJson());
      }
      for (final c in consumptions) {
        final raw = (data['consumptions'] as List).firstWhere(
          (r) => r['id'] == c.id,
        );
        await _put('consumption', {
          ...c.toJson(),
          if (raw['_sector_id'] != null) '_sector_id': raw['_sector_id'],
          if (raw['_owner'] != null) '_owner': raw['_owner'],
          '_export_locked': c.exportLocked,
          if (raw['cancelled_at'] != null) 'cancelled_at': raw['cancelled_at'],
        });
      }
      for (final b in data['batches'] ?? []) {
        await _put('batch', Map<String, dynamic>.from(b));
      }
      for (final r in data['export_receipts'] ?? []) {
        await _put('export_receipt', Map<String, dynamic>.from(r));
      }
      for (final key in [
        'export_profile',
        'favorites',
        'recent_products',
        'theme_mode',
      ]) {
        if (preferences[key] is String) await setSetting(key, preferences[key]);
      }
      for (final a in data['archives'] ?? []) {
        await customStatement('INSERT INTO archives(id,body) VALUES(?,?)', [
          a['id'],
          a['body'],
        ]);
      }
      for (final op in data['outbox']) {
        await customStatement(
          'INSERT INTO outbox(op_id,kind,entity_id,expected_version,body,error) VALUES(?,?,?,?,?,?)',
          [
            op['op_id'],
            op['kind'],
            op['entity_id'],
            op['expected_version'],
            op['body'],
            op['error'],
          ],
        );
      }
      if (data['binding'] != null) await setSetting('binding', data['binding']);
      if (currentBinding == null) {
        // Backup content is data, not an authentication authority.
        await setSetting('role', 'unconfigured');
        await setSetting('sector', '');
        await setSetting('access_verified', '0');
      }
      if (data['operator'] != null) {
        await setSetting('operator', data['operator']);
      }
      // New device ID: restored installation is a distinct device. Operation IDs remain unchanged.
    });
  }
}
