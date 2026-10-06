import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/app_state.dart';
import 'infrastructure/local/database.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await LocalDatabase.open());
  await state.load();
  state.startSyncTimer();
  runApp(ConsumptionApp(state: state));
}
