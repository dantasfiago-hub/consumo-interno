import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';

/// Apply per-connection settings in the worker isolate before migrations or SQL.
QueryExecutor openLocalSqlite(File file) => NativeDatabase.createInBackground(
  file,
  setup: (database) {
    database.execute('PRAGMA busy_timeout = 5000');
    database.execute('PRAGMA journal_mode = WAL');
  },
);
