import 'package:flutter/material.dart';

import 'brand.dart';

ThemeData buildWorkerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: WorkerBrand.accent,
        brightness: brightness,
        surface: dark ? const Color(0xFF0D1714) : WorkerBrand.lightSurface,
      ).copyWith(
        primary: dark ? WorkerBrand.accent : const Color(0xFF006B51),
        tertiary: dark ? WorkerBrand.signal : const Color(0xFF7A4B00),
      );
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: dark
        ? WorkerBrand.voidColor
        : WorkerBrand.lightSurface,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    textTheme: Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: colors.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      selectedIconTheme: IconThemeData(color: colors.onPrimaryContainer),
      selectedLabelTextStyle: TextStyle(
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
