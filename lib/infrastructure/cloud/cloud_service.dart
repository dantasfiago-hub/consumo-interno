import '../../core/activation/activation_config.dart';

import 'dart:convert';
import 'dart:io';

import '../../core/backup/compressed_backup.dart';

import 'package:crypto/crypto.dart';

import '../../core/access/sectors.dart';
import '../../features/exports/domain/export.dart';
import '../../features/exports/data/export_repository.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../domain/models.dart';
import '../local/database.dart';

class CloudException implements Exception {
  final String message;
  final int? statusCode;
  const CloudException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class CloudService implements ExportRepository {
  final LocalDatabase db;
  final http.Client client;
  final FlutterSecureStorage storage;
  String? _token;
  String? userId;
  String role = 'operator', sectorId = '';
  int featuresVersion = 3;
  CloudService(this.db, {http.Client? client, FlutterSecureStorage? storage})
    : client = client ?? http.Client(),
      storage = storage ?? const FlutterSecureStorage();
  Future<String> _refreshKey() async =>
      'refresh_token:${sha256.convert(utf8.encode('${await db.setting('cloud_url')}|${await db.setting('store')}'))}';
  Future<String?> _readRefreshToken() async {
    final scoped = await storage.read(key: await _refreshKey());
    if (scoped != null) return scoped;
    final binding = await db.setting('binding');
    final prefix =
        '${await db.setting('cloud_url')}|${await db.setting('store')}|';
    return binding?.startsWith(prefix) == true
        ? storage.read(key: 'refresh_token')
        : null;
  }

  Future<void> _writeRefreshToken(String token) async {
    await storage.write(key: await _refreshKey(), value: token);
    await storage.delete(key: 'refresh_token');
  }

  Future<bool> get configured async =>
      (await db.setting('cloud_url'))?.isNotEmpty == true;
  Future<dynamic> _request(String path, {Json? body, bool auth = true}) async {
    final url = await db.setting('cloud_url');
    final key = await db.setting('cloud_key');
    if (url == null || key == null) {
      throw const CloudException('Configure a conexão com a nuvem.');
    }
    final uri = Uri.parse('$url$path');
    final headers = {
      'apikey': key,
      'Content-Type': 'application/json',
      if (auth && _token != null) 'Authorization': 'Bearer $_token',
    };
    final response =
        await (body == null
                ? client.get(uri, headers: headers)
                : client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 30));
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (response.statusCode == 404 && path.contains('activate_sector_device')) {
      throw const CloudException(
        'Atualize o Supabase executando supabase/migrations/009_activation_and_scope_changes.sql após 008.',
      );
    }
    if (response.statusCode == 404 &&
        (path.contains('export_batch_v2') ||
            path.contains('export_batch_v3'))) {
      throw const CloudException(
        'Atualize o banco da nuvem executando supabase/migrations/002_exports_v2.sql e 003_sector_access.sql.',
      );
    }
    if (response.statusCode >= 400) {
      final message = data is Map
          ? (data['message'] ??
                data['msg'] ??
                data['error_description'] ??
                data['error'])
          : null;
      throw CloudException(
        'Falha ${response.statusCode}: ${message ?? 'servidor indisponível'}',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<void> configure(String url, String key, String store) async {
    try {
      ConnectionConfig(url, key, store).validate();
    } on FormatException catch (e) {
      throw CloudException(e.message.toString());
    }
    if (key.trim().startsWith('sb_secret_')) {
      throw const CloudException(
        'Use uma chave pública, nunca uma chave secreta.',
      );
    }
    if (key.split('.').length == 3) {
      try {
        final payload = decodeObject(
          utf8.decode(base64Url.decode(base64Url.normalize(key.split('.')[1]))),
        );
        if (payload['role'] == 'service_role') {
          throw const CloudException(
            'A chave service_role não pode ser usada no aplicativo.',
          );
        }
      } on FormatException {
        throw const CloudException('Chave inválida.');
      }
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty && uri.path != '/') {
      throw const CloudException(
        'Informe a URL HTTPS do projeto Supabase, sem caminhos.',
      );
    }
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(store.trim()) ||
        key.trim().isEmpty) {
      throw const CloudException('Informe o ID da loja e a chave pública.');
    }
    final old = await db.setting('cloud_url');
    final oldStore = await db.setting('store');
    if (await db.setting('binding') != null &&
        (old != null && old != url.trim().replaceFirst(RegExp(r'/$'), '') ||
            oldStore != null && oldStore != store.trim())) {
      if (await db.setting('device_setup_mode') != '1') {
        throw const CloudException(
          'Use Sair ou trocar de setor antes de alterar a loja.',
        );
      }
      final token = await _readRefreshToken();
      if (token != null) await _writeRefreshToken(token);
      await db.clearDeviceScope();
      await db.removeSetting('binding');
    }
    if (old != null && oldStore != null) {
      final oldToken =
          await storage.read(key: await _refreshKey()) ??
          await storage.read(key: 'refresh_token');
      if (oldToken != null) await _writeRefreshToken(oldToken);
    }
    await db.setSetting(
      'cloud_url',
      url.trim().replaceFirst(RegExp(r'/$'), ''),
    );
    await db.setSetting('cloud_key', key.trim());
    await db.setSetting('store', store.trim());
    _token = null;
  }

  Future<void> login(String email, String password) async {
    final data = await _request(
      '/auth/v1/token?grant_type=password',
      body: {'email': email.trim(), 'password': password},
      auth: false,
    );
    await _acceptSession(Map<String, dynamic>.from(data));
  }

  /// Creates a technical Auth identity, never a staff account or email login.
  Future<bool> activateDevice(String code) async {
    if (!RegExp(
      r'^[0-9A-F]{32}$',
    ).hasMatch(code.trim().replaceAll('-', '').toUpperCase())) {
      throw const CloudException(
        'Informe o código de ativação de 32 caracteres.',
      );
    }
    final refreshToken = await _readRefreshToken();
    if (refreshToken == null && await db.setting('binding') != null) {
      throw const CloudException(
        'Credencial do aparelho perdida. Preserve os dados e solicite recuperação ao administrador.',
      );
    }
    final data = Map<String, dynamic>.from(
      await _request(
        refreshToken == null
            ? '/auth/v1/signup'
            : '/auth/v1/token?grant_type=refresh_token',
        body: refreshToken == null
            ? <String, dynamic>{}
            : {'refresh_token': refreshToken},
        auth: false,
      ),
    );
    final id = data['user']['id'] as String;
    final binding =
        '${await db.setting('cloud_url')}|${await db.setting('store')}|$id';
    final previous = await db.setting('binding');
    if (previous != null && previous != binding) {
      throw const CloudException(
        'A credencial não corresponde a este aparelho.',
      );
    }
    _token = data['access_token'];
    // Keep the identity even when the activation response is lost or the code is mistyped.
    await _writeRefreshToken(data['refresh_token'] as String);
    var device = await db.setting('device');
    device ??= uuid.v4();
    await db.setSetting('device', device);
    final result = await _request(
      '/rest/v1/rpc/activate_sector_device',
      body: {
        'p_store': await db.setting('store'),
        'p_device': device,
        'p_code': code.trim(),
        'p_allow_scope_change': await db.setting('device_setup_mode') == '1',
      },
    );
    if (result is! Map || result['activated'] != true) {
      throw const CloudException('Ativação não confirmada.');
    }
    await _acceptSession(data);
    await db.setSetting('device_mode', '1');
    if (role == 'admin') await db.setSetting('admin_password_required', '1');
    return result['duplicate'] != true;
  }

  Future<Json> provisionSector(
    String sector,
    bool replace,
    String reason,
  ) async {
    await refresh();
    return Map<String, dynamic>.from(
      await _request(
        '/rest/v1/rpc/admin_provision_sector',
        body: {
          'p_store': await db.setting('store'),
          'p_slot': sector,
          'p_replace': replace,
          'p_reason': reason,
        },
      ),
    );
  }

  Future<void> refresh() async {
    final token = await _readRefreshToken();
    if (token == null) {
      throw const CloudException(
        'Ative ou recupere a credencial do aparelho para sincronizar. O uso local continua disponível.',
      );
    }
    final data = await _request(
      '/auth/v1/token?grant_type=refresh_token',
      body: {'refresh_token': token},
      auth: false,
    );
    await _acceptSession(Map<String, dynamic>.from(data));
  }

  Future<void> _acceptSession(Json data) async {
    _token = data['access_token'];
    final id = data['user']['id'] as String;
    final store = await db.setting('store');
    final url = await db.setting('cloud_url');
    final binding = '$url|$store|$id';
    final existing = await db.setting('binding');
    if (existing != null && existing != binding) {
      _token = null;
      throw const CloudException(
        'Conta ou loja diferente da instalação original.',
      );
    }
    // Refresh tokens rotate. Persist the newly issued one before another network request.
    await _writeRefreshToken(data['refresh_token'] as String);
    final memberships = await _request(
      '/rest/v1/memberships?store_id=eq.$store&user_id=eq.$id&select=role,sector,features_version',
    );
    if (memberships is! List || memberships.isEmpty) {
      _token = null;
      role = 'unconfigured';
      sectorId = '';
      await db.setSetting('role', role);
      await db.setSetting('sector', sectorId);
      await db.setSetting('access_verified', '0');
      throw const CloudException('Usuário sem acesso a esta loja.');
    }
    final nextRole = memberships.first['role'] as String;
    final nextSector = memberships.first['sector'] as String? ?? '';
    if (await db.setting('role') != 'unconfigured' &&
        await db.setting('device_mode') == '1' &&
        existing != null &&
        (await db.setting('role') != nextRole ||
            await db.setting('sector') != nextSector)) {
      if (await db.setting('device_setup_mode') != '1') {
        await db.setSetting('access_verified', '0');
        throw const CloudException(
          'O acesso mudou. Entre em Sair ou trocar de setor para reativar com segurança.',
        );
      }
      await db.clearDeviceScope();
    }
    featuresVersion = memberships.first['features_version'] ?? 3;
    await db.setSetting('features_version', featuresVersion.toString());
    role = memberships.first['role'];
    sectorId = memberships.first['sector'] ?? '';
    if (!['admin', 'operator'].contains(role)) {
      await db.setSetting('role', 'unconfigured');
      await db.setSetting('sector', '');
      await db.setSetting('access_verified', '0');
      throw const CloudException('Perfil não autorizado.');
    }
    userId = id;
    if (await db.setting('role') != role ||
        await db.setting('sector') != sectorId) {
      await db.setSetting('entity_cursor', '0');
    }
    await db.setSetting('binding', binding);
    await db.setSetting('role', role);
    await db.setSetting('sector', sectorId);
    await db.setSetting(
      'access_verified',
      await db.setting('device_setup_mode') == '1' ? '0' : '1',
    );
  }

  Future<void> logout() async {
    if (await db.setting('device_mode') == '1') {
      throw const CloudException(
        'A credencial do aparelho deve ser preservada. Use Bloquear administração.',
      );
    }
    // Local database stays bound to its original user. Never mix accounts.
    _token = null;
    await storage.delete(key: 'refresh_token');
  }

  Future<void> sync() async {
    await refresh();
    if (role == 'operator' && !sectors.containsKey(sectorId)) {
      throw const CloudException(
        'Conta sem setor. Peça ao administrador para vincular a conta.',
      );
    }
    final store = await db.setting('store');
    var device = await db.setting('device');
    device ??= uuid.v4();
    await db.setSetting('device', device);
    if (featuresVersion >= 4) await _applyReviews(store!);
    String? failure;
    for (final op in await db.pending()) {
      try {
        final body = decodeObject(op['body']);
        // Do not rewrite a durable operation: earlier versions may already have committed it.
        await _request(
          '/rest/v1/rpc/apply_operation',
          body: {
            'p_store': store,
            'p_operation': op['op_id'],
            'p_device': device,
            'p_kind': op['kind'],
            'p_expected': op['expected_version'],
            'p_body': body,
          },
        );
        await db.acknowledge(op['op_id']);
      } catch (e) {
        await db.fail(op['op_id'], e.toString());
        failure = e.toString();
        if (featuresVersion >= 4 &&
            e is CloudException &&
            e.statusCode != null &&
            e.statusCode! >= 400 &&
            e.statusCode! < 500 &&
            e.statusCode != 429) {
          try {
            await _request(
              '/rest/v1/rpc/report_sync_issue',
              body: {
                'p_store': store,
                'p_operation': op['op_id'],
                'p_device': device,
                'p_kind': op['kind'],
                'p_entity': op['entity_id'],
                'p_expected': op['expected_version'],
                'p_body': decodeObject(op['body']),
                'p_error': e.toString(),
              },
            );
          } catch (_) {
            /* Keep the original operation durable when review submission fails. */
          }
        }
        break; // Preserve dependencies. Never silently discard failed operations.
      }
    }
    var cursor = await db.setting('entity_cursor') ?? '0';
    await db.clearIncoming();
    while (true) {
      final page =
          await _request(
                '/rest/v1/entities?store_id=eq.$store&select=id,kind,body,created_by,revision,sector_id,export_locked&order=revision.asc&revision=gt.$cursor&limit=20',
              )
              as List;
      if (featuresVersion >= 4) await _hydrateImages(page, store!);
      await db.stageRemote(page);
      if (page.isNotEmpty) cursor = page.last['revision'].toString();
      if (page.length < 20) break;
    }
    await db.commitIncoming(cursor, operatorId: null);
    if (role == 'operator') await _reconcileSectorScope();
    if (featuresVersion >= 4) {
      final missing = <Json>[];
      for (final product in await db.records('product')) {
        final hash = product['photo_hash'];
        if (hash != null && await db.record('image', hash) == null) {
          missing.add({'kind': 'product', 'body': product});
        }
      }
      for (var i = 0; i < missing.length; i += 20) {
        await _hydrateImages(
          missing.sublist(i, (i + 20).clamp(0, missing.length)),
          store!,
        );
      }
    }
    for (final receipt in await db.records('export_receipt')) {
      try {
        await updateBatch(
          {'id': receipt['batch_id'], 'version': receipt['version']},
          'saved',
          '',
          eventId: receipt['id'],
          refreshSession: false,
        );
        await db.removeExportReceipt(receipt['id']);
      } catch (e) {
        failure ??= 'Confirmação de arquivo salvo pendente: $e';
      }
    }
    await fetchBatches();
    await db.setSetting('last_sync', DateTime.now().toIso8601String());
    if (featuresVersion >= 4 &&
        await db.setting('auto_cloud_backup') != 'false') {
      try {
        await _backupDevice(store!, device);
      } catch (e) {
        await db.setSetting('cloud_backup_error', e.toString());
      }
    }
    if (failure != null) {
      throw CloudException('Há uma pendência que precisa de revisão: $failure');
    }
  }

  Future<void> _hydrateImages(List<dynamic> rows, String store) async {
    final cached = <String, Json>{}, missing = <String>{};
    for (final row in rows) {
      if (row['kind'] != 'product' || row['body']['photo_hash'] == null) {
        continue;
      }
      final hash = row['body']['photo_hash'] as String;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw const CloudException('Referência de imagem inválida.');
      }
      final image = await db.record('image', hash);
      if (image == null) {
        missing.add(hash);
      } else {
        cached[hash] = image;
      }
    }
    if (missing.isNotEmpty) {
      final images =
          await _request(
                '/rest/v1/product_images?store_id=eq.$store&hash=in.(${missing.join(',')})&select=hash,data_base64',
              )
              as List;
      for (final image in images) {
        final hash = image['hash'] as String;
        if (!missing.contains(hash) ||
            sha256.convert(base64Decode(image['data_base64'])).toString() !=
                hash) {
          throw const CloudException('Integridade da foto inválida.');
        }
        cached[hash] = {'id': hash, 'data_base64': image['data_base64']};
        await db.acceptRemote('image', cached[hash]!);
      }
    }
    for (final row in rows) {
      final hash = row['body']['photo_hash'];
      if (row['kind'] == 'product' && cached.containsKey(hash)) {
        row['body'] = {
          ...Map<String, dynamic>.from(row['body']),
          'photo': cached[hash]!['data_base64'],
        };
      }
    }
  }

  Future<void> _applyReviews(String store) async {
    final reviews =
        await _request(
              '/rest/v1/sync_issues?store_id=eq.$store&actor=eq.$userId&status=in.(accept_remote,applied)&select=operation_id,kind,entity_id,review_reason,status',
            )
            as List;
    for (final review in reviews) {
      if (!(await db.pending()).any(
        (op) => op['op_id'] == review['operation_id'],
      )) {
        continue;
      }
      final rows =
          await _request(
                '/rest/v1/entities?store_id=eq.$store&kind=eq.${review['kind']}&id=eq.${review['entity_id']}&select=body,sector_id,export_locked',
              )
              as List;
      await db.resolveWithRemote(
        review['kind'],
        review['entity_id'],
        rows.isEmpty
            ? null
            : {
                ...Map<String, dynamic>.from(rows.first['body']),
                '_sector_id': rows.first['sector_id'],
                '_export_locked': rows.first['export_locked'] == true,
              },
        reason: 'Decisão administrativa: ${review['review_reason']}',
      );
    }
  }

  Future<void> _backupDevice(String store, String device) async {
    final snapshot = decodeObject(await db.backup())..remove('exported_at');
    final bytes = zlib.encode(utf8.encode(jsonEncode(snapshot)));
    final hash = sha256.convert(bytes).toString();
    if (await db.setting('cloud_backup_hash') == hash) {
      await db.setSetting('cloud_backup_error', '');
      return;
    }
    if (bytes.length > 20 * 1024 * 1024) {
      throw const CloudException('Backup remoto acima de 20 MB comprimidos.');
    }
    await _request(
      '/rest/v1/rpc/upload_device_backup',
      body: {
        'p_store': store,
        'p_device': device,
        'p_hash': hash,
        'p_payload': base64Encode(bytes),
      },
    );
    await db.setSetting('cloud_backup_hash', hash);
    await db.setSetting('cloud_backup_error', '');
    await db.setSetting(
      'cloud_backup_last',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> restoreOwnCloudBackup() async {
    if (featuresVersion < 4 ||
        (await db.products()).isNotEmpty ||
        (await db.consumptions()).isNotEmpty ||
        (await db.records('batch')).isNotEmpty ||
        (await db.records('export_receipt')).isNotEmpty ||
        (await db.pending()).isNotEmpty) {
      return;
    }
    final rows =
        await _request(
              '/rest/v1/device_backups?store_id=eq.${await db.setting('store')}&actor=eq.$userId&select=payload,hash&order=revision.desc&limit=1',
            )
            as List;
    if (rows.isEmpty) return;
    final bytes = base64Decode(rows.first['payload']);
    if (sha256.convert(bytes).toString() != rows.first['hash']) {
      throw const CloudException('Backup remoto corrompido.');
    }
    await db.restore(decodeCompressedBackup(bytes));
    await db.setSetting('entity_cursor', '0');
  }

  Future<List<Json>> adminList(
    String table, {
    String? sector,
    String? action,
    String? afterId,
  }) async {
    await refresh();
    if (role != 'admin') {
      throw const CloudException('Acesso administrativo obrigatório.');
    }
    final store = await db.setting('store');
    if (table == 'memberships') {
      final rows =
          await _request('/rest/v1/rpc/admin_members', body: {'p_store': store})
              as List;
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }
    if (!['audit_log', 'sync_issues', 'device_backups'].contains(table)) {
      throw const CloudException('Consulta administrativa inválida.');
    }
    final columns = table == 'device_backups'
        ? 'actor,device_id,scope_role,sector,hash,created_at,revision'
        : '*';
    final result = <Json>[];
    var offset = 0;
    do {
      final order = table == 'audit_log'
          ? 'id.desc'
          : table == 'sync_issues'
          ? 'updated_at.desc,operation_id.asc'
          : 'revision.desc';
      final rows =
          await _request(
                '/rest/v1/$table?store_id=eq.$store&select=$columns&order=$order&limit=100&offset=$offset${sector == null || sector.isEmpty ? '' : '&sector=eq.${Uri.encodeComponent(sector)}'}${action == null || action.isEmpty ? '' : '&action=eq.${Uri.encodeComponent(action)}'}${afterId == null ? '' : '&id=lt.${Uri.encodeComponent(afterId)}'}',
              )
              as List;
      result.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
      if (table == 'audit_log' || rows.length < 100) break;
      offset += rows.length;
    } while (true);
    return result;
  }

  Future<void> adminMember(
    String id,
    String role,
    String? sector,
    bool active,
  ) async {
    await refresh();
    await _request(
      '/rest/v1/rpc/admin_set_member',
      body: {
        'p_store': await db.setting('store'),
        'p_user': id,
        'p_role': role,
        'p_sector': sector,
        'p_active': active,
      },
    );
  }

  Future<void> reviewIssue(String id, String action, String reason) async {
    await refresh();
    await _request(
      '/rest/v1/rpc/admin_review_issue',
      body: {
        'p_store': await db.setting('store'),
        'p_operation': id,
        'p_action': action,
        'p_reason': reason,
      },
    );
  }

  Future<String> downloadDeviceBackup(
    String actor,
    String device,
    String hash,
  ) async {
    await refresh();
    if (role != 'admin') {
      throw const CloudException('Acesso administrativo obrigatório.');
    }
    final rows =
        await _request(
              '/rest/v1/device_backups?store_id=eq.${await db.setting('store')}&actor=eq.$actor&device_id=eq.$device&hash=eq.$hash&select=payload',
            )
            as List;
    if (rows.isEmpty) throw const CloudException('Backup não encontrado.');
    final bytes = base64Decode(rows.first['payload']);
    if (sha256.convert(bytes).toString() != hash) {
      throw const CloudException('Backup corrompido.');
    }
    return decodeCompressedBackup(bytes);
  }

  Future<void> _reconcileSectorScope() async {
    final allowed = <String>{};
    final store = await db.setting('store');
    for (final kind in ['product', 'consumption']) {
      String? cursor;
      while (true) {
        final page =
            await _request(
                  '/rest/v1/entities?store_id=eq.$store&kind=eq.$kind&select=id&order=id.asc&limit=200${cursor == null ? '' : '&id=gt.$cursor'}',
                )
                as List;
        for (final row in page) {
          allowed.add('$kind/${row['id']}');
        }
        if (page.length < 200) break;
        cursor = page.last['id'];
      }
    }
    await db.pruneSectorScope(allowed, sectorId);
  }

  Future<void> assignLegacySector(
    String id,
    String sector,
    String reason,
  ) async {
    await refresh();
    await _request(
      '/rest/v1/rpc/assign_legacy_sector',
      body: {
        'p_store': await db.setting('store'),
        'p_id': id,
        'p_sector': sector,
        'p_reason': reason,
      },
    );
    await sync();
  }

  Future<void> fetchBatches() async {
    final store = await db.setting('store');
    String? cursor;
    while (true) {
      final page =
          await _request(
                '/rest/v1/export_batches?store_id=eq.$store&select=id,body&order=id.asc&limit=20${cursor == null ? '' : '&id=gt.$cursor'}',
              )
              as List;
      for (final r in page) {
        await db.acceptRemote('batch', Map<String, dynamic>.from(r['body']));
      }
      if (page.length < 20) break;
      cursor = page.last['id'];
    }
  }

  Future<void> resolveWithRemote(String kind, String id) async {
    await refresh();
    final store = await db.setting('store');
    final rows =
        await _request(
              '/rest/v1/entities?store_id=eq.$store&kind=eq.$kind&id=eq.$id&select=body,sector_id,export_locked',
            )
            as List;
    await db.resolveWithRemote(
      kind,
      id,
      rows.isEmpty
          ? null
          : <String, dynamic>{
              ...Map<String, dynamic>.from(rows.first['body']),
              '_sector_id': rows.first['sector_id'],
              '_export_locked': rows.first['export_locked'] == true,
            },
    );
  }

  @override
  Future<Json> createBatch(
    List<ReportRow> rows,
    ExportProfile profile,
    Json filters,
  ) async {
    profile = profile.forSector(filters['sector'] as String? ?? '');
    profile.validate();
    if (!sectors.containsKey(filters['sector'])) {
      throw const CloudException('Selecione um único setor para exportar.');
    }
    if (!profile.validated) {
      throw const CloudException(
        'Confira o perfil na instalação do VR Master e confirme em Configurações.',
      );
    }
    await refresh();
    if ((await db.pending()).isNotEmpty) {
      throw const CloudException(
        'Sincronize todas as pendências antes de preparar o lote.',
      );
    }
    final requests = rows
        .map(
          (r) => {
            'consumption_id': r.consumption.id,
            'item_id': r.item.id,
            'version': r.consumption.version,
          },
        )
        .toList();
    requests.sort(
      (a, b) => '${a['consumption_id']}/${a['item_id']}'.compareTo(
        '${b['consumption_id']}/${b['item_id']}',
      ),
    );
    final fingerprint = jsonEncode({
      'items': requests,
      'profile': profile.toJson(),
      'filters': filters,
    });
    var id = await db.setting('batch_retry_id');
    if (await db.setting('batch_retry_body') != fingerprint || id == null) {
      id = uuid.v4();
      await db.setSetting('batch_retry_id', id);
      await db.setSetting('batch_retry_body', fingerprint);
    }
    final result = Map<String, dynamic>.from(
      await _request(
        '/rest/v1/rpc/create_export_batch_v3',
        body: {
          'p_store': await db.setting('store'),
          'p_id': id,
          'p_items': requests,
          'p_profile': profile.toJson(),
          'p_filters': filters,
          'p_sector': filters['sector'],
        },
      ),
    );
    await db.acceptRemote('batch', result);
    await db.setSetting('batch_retry_body', '');
    return result;
  }

  @override
  Future<Json> updateBatch(
    Json batch,
    String action,
    String reference, {
    String? eventId,
    bool refreshSession = true,
  }) async {
    if (refreshSession) await refresh();
    final result = Map<String, dynamic>.from(
      await _request(
        '/rest/v1/rpc/update_export_batch_v2',
        body: {
          'p_store': await db.setting('store'),
          'p_id': batch['id'],
          'p_version': batch['version'] ?? 1,
          'p_action': action,
          'p_reference': reference.trim(),
          'p_event': eventId ?? uuid.v4(),
        },
      ),
    );
    await db.acceptRemote('batch', result);
    return result;
  }
}
