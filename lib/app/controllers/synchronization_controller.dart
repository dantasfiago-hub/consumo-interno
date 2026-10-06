import 'dart:async';

class SynchronizationController {
  final Future<void> Function() synchronize, reload;
  final void Function() changed;
  bool syncing = false, disposed = false;
  String error = '';
  int failures = 0;
  DateTime? nextAttempt;
  Future<void>? _task;
  Timer? _timer;
  SynchronizationController({
    required this.synchronize,
    required this.reload,
    required this.changed,
  });
  Duration get retryDelay =>
      Duration(seconds: (60 * (1 << failures.clamp(0, 4))).clamp(60, 900));
  void start() {
    if (disposed) return;
    _timer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => sync(automatic: true),
    );
  }

  Future<void> sync({bool automatic = false}) {
    if (disposed) return Future.value();
    if (_task != null) return _task!;
    if (syncing ||
        automatic &&
            nextAttempt != null &&
            DateTime.now().isBefore(nextAttempt!)) {
      return Future.value();
    }
    return _task = _perform().whenComplete(() => _task = null);
  }

  Future<void> _perform() async {
    syncing = true;
    changed();
    try {
      await synchronize();
      error = '';
      failures = 0;
    } catch (e) {
      error = e.toString();
      failures++;
    } finally {
      await _finish();
    }
  }

  Future<T> action<T>(Future<T> Function() run) async {
    if (_task != null) await _task;
    if (disposed) throw StateError('Controlador encerrado.');
    if (syncing) throw StateError('Outra operação de nuvem está em andamento.');
    syncing = true;
    changed();
    try {
      final result = await run();
      error = '';
      return result;
    } finally {
      await _finish();
    }
  }

  Future<void> _finish() async {
    try {
      if (!disposed) await reload();
    } catch (e) {
      error =
          '${error.isEmpty ? '' : '$error\n'}Falha ao atualizar dados locais: $e';
      if (failures == 0) failures = 1;
    } finally {
      nextAttempt = DateTime.now().add(retryDelay);
      syncing = false;
      if (!disposed) changed();
    }
  }

  void dispose() {
    disposed = true;
    _timer?.cancel();
  }
}
