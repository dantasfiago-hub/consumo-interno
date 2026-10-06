import 'package:flutter/material.dart';

/// Device preference only; appearance never creates a cloud operation.
class ThemeController extends ChangeNotifier {
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  ThemeController({required this.read, required this.write});
  ThemeMode _mode = ThemeMode.system;
  bool _loaded = false, _disposed = false;
  bool saving = false;
  ThemeMode get mode => _mode;

  Future<void> load({bool force = false}) async {
    if (_disposed || _loaded && !force) return;
    final stored = await read();
    if (_disposed) return;
    _mode = ThemeMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => ThemeMode.system,
    );
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    if (_disposed || saving || value == _mode) return;
    saving = true;
    if (!_disposed) notifyListeners();
    try {
      await write(value.name);
      _mode = value;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
