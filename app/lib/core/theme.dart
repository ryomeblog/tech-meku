import 'package:flutter/material.dart';

/// デザイントークン（doc/design.md 8.6）
@immutable
class TmColors extends ThemeExtension<TmColors> {
  const TmColors({
    required this.bg,
    required this.card,
    required this.ink,
    required this.active,
    required this.muted,
    required this.line,
    required this.railBg,
    required this.warn,
    required this.ok,
    required this.brand,
  });

  final Color bg, card, ink, active, muted, line, railBg, warn, ok, brand;

  static const dark = TmColors(
    bg: Color(0xFF0B0F14),
    card: Color(0xFF111827),
    ink: Color(0xFFE5E7EB),
    active: Color(0xFF06B6D4),
    muted: Color(0xFF9CA3AF),
    line: Color(0xFF1F2937),
    railBg: Color(0xFF1C2431),
    warn: Color(0xFFFB923C),
    ok: Color(0xFF4ADE80),
    brand: Color(0xFF0B1240),
  );

  static const light = TmColors(
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFF3F4F6),
    ink: Color(0xFF111827),
    active: Color(0xFF0891B2),
    muted: Color(0xFF6B7280),
    line: Color(0xFFE5E7EB),
    railBg: Color(0xFFE5E7EB),
    warn: Color(0xFFC2410C),
    ok: Color(0xFF15803D),
    brand: Color(0xFF0B1240),
  );

  static TmColors of(BuildContext context) => Theme.of(context).extension<TmColors>() ?? dark;

  @override
  TmColors copyWith() => this;

  @override
  TmColors lerp(ThemeExtension<TmColors>? other, double t) => t < 0.5 ? this : (other as TmColors? ?? this);
}

ThemeData buildTheme(Brightness b) {
  final t = b == Brightness.dark ? TmColors.dark : TmColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: t.active, brightness: b).copyWith(
    primary: t.active,
    surface: t.bg,
    onSurface: t.ink,
    error: t.warn,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    iconTheme: IconThemeData(color: t.ink),
    appBarTheme: AppBarTheme(backgroundColor: t.bg, foregroundColor: t.ink, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(color: t.card, elevation: 0, margin: EdgeInsets.zero),
    chipTheme: ChipThemeData(backgroundColor: t.card, side: BorderSide(color: t.line)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: t.bg),
    dialogTheme: DialogThemeData(backgroundColor: t.bg),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.bg,
      indicatorColor: t.active.withValues(alpha: 0.15),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, color: t.ink)),
      height: 64,
    ),
    extensions: [t],
  );
}
