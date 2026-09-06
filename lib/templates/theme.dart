import 'package:flutter/material.dart';

/// One accent, one radius scale, two modes.
///
/// The palette is derived from a single seed so light and dark stay in step;
/// the previous hand-written [ColorScheme] was dark only and half of its slots
/// used members that Flutter has since deprecated.
class AppTheme {
  AppTheme._();

  /// The blue the app has always used, kept so it still looks like itself.
  static const Color seed = Color(0xFF0B6FA4);

  /// Bundled with the app, not fetched at run time. See the fonts block in
  /// `pubspec.yaml` for why.
  static const String sansFamily = 'Mukta';
  static const String monoFamily = 'JetBrainsMono';

  /// Single corner radius for every surface: cards, fields, sheets, buttons.
  static const double radius = 14;
  static final BorderRadius borderRadius = BorderRadius.circular(radius);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final shape = RoundedRectangleBorder(borderRadius: borderRadius);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: sansFamily,
      // Mukta is subset to Latin, so anything outside that (a note pasted in
      // Bengali, say) falls through to the platform font rather than to
      // rectangles.
      fontFamilyFallback: const ['Roboto', 'Segoe UI', 'Noto Sans', 'sans-serif'],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 3,
        titleTextStyle: TextStyle(
          fontFamily: sansFamily,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shape: shape,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        // Label sits above the field and helper text below it, so the border
        // never has to double as a label slot.
        border: OutlineInputBorder(borderRadius: borderRadius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        highlightElevation: 0,
        shape: shape,
      ),
      listTileTheme: ListTileThemeData(shape: shape),
      dialogTheme: DialogThemeData(shape: shape),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      chipTheme: ChipThemeData(shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant))),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    );
  }

  /// Monospace, for the things that are literally machine values: addresses,
  /// ports, PINs, timestamps.
  ///
  /// [weight] drives the font's own weight axis. Passing `fontWeight` instead
  /// would make Flutter synthesise a slanted, smeared bold, because only one
  /// face of this family is registered.
  static TextStyle mono(
    BuildContext context, {
    double size = 13,
    Color? color,
    int weight = 400,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: size,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.4,
      fontVariations: [FontVariation('wght', weight.toDouble())],
    );
  }
}
