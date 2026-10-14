import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/theme/app_theme.dart';
import 'app_state.dart';
import 'shell.dart';

class ConsumptionApp extends StatelessWidget {
  final AppState state;
  const ConsumptionApp({super.key, required this.state});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.appearance,
    builder: (context, _) => MaterialApp(
      title: 'Consumo interno',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: state.appearance.mode,
      home: Shell(state: state),
    ),
  );
}
