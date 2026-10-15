import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/app_state.dart';
import 'infrastructure/local/database.dart';
import 'infrastructure/local/database_instance_lock.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final LocalDatabase database;
  try {
    database = await LocalDatabase.open();
  } on DatabaseAlreadyOpenException catch (error) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error.toString(), textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final state = AppState(database);
  await state.load();
  state.startSyncTimer();
  runApp(ConsumptionApp(state: state));
}
