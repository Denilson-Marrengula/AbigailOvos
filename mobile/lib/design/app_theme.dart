import 'package:flutter/material.dart';

abstract final class AppColors {
  static const forest = Color.fromARGB(255, 19, 73, 55);
  static const gold = Color(0xFFD9B956);
  static const cream = Color(0xFFFAF9F2);
}

abstract final class AppSpacing {
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const extraLarge = 32.0;
  static const radius = 24.0;
}

abstract final class AppTheme {
  static ThemeData create(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      brightness: brightness,
      secondary: AppColors.gold,
      surface: brightness == Brightness.light ? AppColors.cream : null,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: Typography.material2021(platform: TargetPlatform.android).black
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    );
  }
}
