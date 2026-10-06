import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/export.dart';

class ExportController extends ChangeNotifier {
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  bool _disposed = false;
  ExportProfile profile = const ExportProfile();
  ExportController({required this.read, required this.write});
  Future<void> load() async {
    if (_disposed) return;
    final saved = await read();
    if (_disposed) return;
    if (saved != null) {
      final next = ExportProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(saved)),
      );
      if (_disposed) throw StateError('Controlador encerrado.');
      next.validate();
      profile = next;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> save(ExportProfile next) async {
    if (_disposed) throw StateError('Controlador encerrado.');
    next.validate();
    final stored = ExportProfile.fromJson({
      ...next.toJson(),
      'version': profile.version + 1,
    });
    await write(jsonEncode(stored.toJson()));
    profile = stored;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
