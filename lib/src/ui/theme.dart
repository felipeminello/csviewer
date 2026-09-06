import 'package:flutter/material.dart';

/// A compact, macOS-flavoured theme: small type, hairline separators, and a
/// dense grid that fits as many records on screen as possible.
class AppTheme {
  static const Color accent = Color(0xFF0A66FF);

  static ThemeData light({String? fontFamily}) => _build(Brightness.light, fontFamily);
  static ThemeData dark({String? fontFamily}) => _build(Brightness.dark, fontFamily);

  static ThemeData _build(Brightness brightness, [String? fontFamily]) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      surface: isDark ? const Color(0xFF1E1F22) : const Color(0xFFF7F7F8),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: fontFamily);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.compact,
      // Desktop pointer targets: no 48px minimum padding around icon buttons.
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      // Dense widgets set their own sizes; only the styles Material picks for
      // dialogs and buttons are nudged down, and only where a size exists.
      textTheme: _scaled(base.textTheme, 0.94),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: isDark ? const Color(0xFF34363A) : const Color(0xFFDDDEE1),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2C30) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: isDark ? const Color(0xFF3C3F44) : const Color(0xFFD3D4D8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: isDark ? const Color(0xFF3C3F44) : const Color(0xFFD3D4D8)),
        ),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    );
  }
}

TextTheme _scaled(TextTheme theme, double factor) {
  TextStyle? scale(TextStyle? style) {
    final size = style?.fontSize;
    if (style == null || size == null) return style;
    return style.copyWith(fontSize: size * factor);
  }

  return TextTheme(
    displayLarge: scale(theme.displayLarge),
    displayMedium: scale(theme.displayMedium),
    displaySmall: scale(theme.displaySmall),
    headlineLarge: scale(theme.headlineLarge),
    headlineMedium: scale(theme.headlineMedium),
    headlineSmall: scale(theme.headlineSmall),
    titleLarge: scale(theme.titleLarge),
    titleMedium: scale(theme.titleMedium),
    titleSmall: scale(theme.titleSmall),
    bodyLarge: scale(theme.bodyLarge),
    bodyMedium: scale(theme.bodyMedium),
    bodySmall: scale(theme.bodySmall),
    labelLarge: scale(theme.labelLarge),
    labelMedium: scale(theme.labelMedium),
    labelSmall: scale(theme.labelSmall),
  );
}

/// Colours the grid needs that are not part of [ColorScheme].
class GridColors {
  const GridColors._(this.header, this.gridLine, this.stripe, this.hover, this.selection);

  final Color header;
  final Color gridLine;
  final Color stripe;
  final Color hover;
  final Color selection;

  factory GridColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const GridColors._(
        Color(0xFF2A2C30),
        Color(0xFF35373C),
        Color(0xFF232529),
        Color(0xFF2F3238),
        Color(0xFF15427F),
      );
    }
    return const GridColors._(
      Color(0xFFEFEFF1),
      Color(0xFFE2E3E6),
      Color(0xFFFAFAFB),
      Color(0xFFEDF3FF),
      Color(0xFFD3E3FF),
    );
  }
}

const double kRowHeight = 26;
const double kHeaderHeight = 30;
const double kRowNumberWidth = 62;
