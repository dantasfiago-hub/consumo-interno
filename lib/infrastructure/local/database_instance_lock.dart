import 'dart:io';

class DatabaseAlreadyOpenException implements Exception {
  const DatabaseAlreadyOpenException();
  @override
  String toString() =>
      'Não foi possível obter acesso exclusivo aos dados locais. '
      'O Consumo Interno pode estar aberto em outra janela. '
      'Feche a outra janela e abra novamente.';
}

/// Holds an OS lock for the lifetime of the production database.
/// Keep the lock file: deleting it could allow competing processes on Unix.
class DatabaseInstanceLock {
  final RandomAccessFile _handle;
  bool _released = false;
  DatabaseInstanceLock._(this._handle);

  static Future<DatabaseInstanceLock> acquire(File file) async {
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      throw const DatabaseAlreadyOpenException();
    }
    return DatabaseInstanceLock._(handle);
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    // Closing releases the exact region/handle on Windows and on Unix.
    await _handle.close();
  }
}
