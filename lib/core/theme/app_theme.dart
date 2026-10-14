import 'package:flutter/material.dart';

/// Matching Material color roles for surfaces, fields, text and dialogs.
abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff00865d),
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final scheme = isDark
        ? generatedScheme.copyWith(
            // Medium greys keep the dark theme softer without losing contrast.
            surface: const Color(0xff505853),
            surfaceContainerLowest: const Color(0xff454b48),
            surfaceContainerLow: const Color(0xff5a625d),
            surfaceContainer: const Color(0xff555d58),
            surfaceContainerHigh: const Color(0xff606863),
            surfaceContainerHighest: const Color(0xff68716b),
            surfaceDim: const Color(0xff404843),
            surfaceBright: const Color(0xff68716b),
            onSurface: const Color(0xffffffff),
            onSurfaceVariant: const Color(0xffe4e9e5),
            outline: const Color(0xffb0beb5),
            outlineVariant: const Color(0xff7a847d),
            // Text actions and focus indicators need a lighter green on grey.
            primary: const Color(0xffd2f7de),
            onPrimary: const Color(0xff123d25),
            primaryContainer: const Color(0xff165b36),
            onPrimaryContainer: const Color(0xffffffff),
            secondary: const Color(0xffc0dcc9),
            onSecondary: const Color(0xff203b2b),
            secondaryContainer: const Color(0xff345342),
            onSecondaryContainer: const Color(0xffffffff),
            tertiary: const Color(0xffbce0db),
            onTertiary: const Color(0xff173c38),
            tertiaryContainer: const Color(0xff315b55),
            onTertiaryContainer: const Color(0xffffffff),
            inverseSurface: const Color(0xffe4e9e5),
            onInverseSurface: const Color(0xff202a25),
            inversePrimary: const Color(0xff165b36),
            error: const Color(0xffffd2ce),
            onError: const Color(0xff5f1412),
            errorContainer: const Color(0xff782622),
            onErrorContainer: const Color(0xffffffff),
            surfaceTint: Colors.transparent,
          )
        : generatedScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceDim : scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? scheme.primaryContainer : null,
          foregroundColor: isDark ? scheme.onPrimaryContainer : null,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        ),
      ),
    );
  }
}
