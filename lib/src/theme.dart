import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';

/// PeerChat – Premium dark theme inspired by the website
class AppTheme {
  AppTheme._();

  // ─── Brand Colors (Violet Theme) ───
  static const Color bgDeep       = Color(0xFF181626); // graphite (dark violet)
  static const Color bgCard       = Color(0xFF262438); // slate (medium violet background)
  static const Color bgSurface    = Color(0xFF383554); // lighter violet surface
  static const Color primary      = Color(0xFF8B5CF6); // ember
  static const Color accent       = Color(0xFFA78BFA); // copper
  static const Color accentPurple = Color(0xFFC4B5FD); // gold (light purple option)
  static const Color textPrimary  = Color(0xFFF5F3FF); // ivory
  static const Color textSecondary= Color(0xFFD4D0E0); // mist
  static const Color online       = Color(0xFF10B981); // Emerald
  static const Color success      = Color(0xFF10B981); // Emerald (alias for online)
  static const Color danger       = Color(0xFFF43F5E); // Rose
  static const Color warning      = Color(0xFFF59E0B); // Amber
  static const Color sent         = Color(0xFF6366F1); // sage

  // ─── Gradients ───
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [bgCard, bgDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient appBarGradient = LinearGradient(
    colors: [bgDeep, bgCard],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Decoration Helpers ───
  static BoxDecoration glassCard({double radius = 16}) => BoxDecoration(
    gradient: cardGradient,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration accentBorderCard({double radius = 16}) => BoxDecoration(
    gradient: cardGradient,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: primary.withValues(alpha: 0.25),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: primary.withValues(alpha: 0.08),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // ─── ThemeData ───
  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bgDeep,
      canvasColor: bgDeep,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: bgCard,
        error: danger,
        onPrimary: bgDeep,
        onSecondary: bgDeep,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      textTheme: textTheme,

      // AppBar
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        margin: EdgeInsets.zero,
      ),

      // Tabs
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
      ),

      // Elevated buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: bgDeep,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: bgDeep,
        elevation: 6,
        shape: CircleBorder(),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        hintStyle: GoogleFonts.inter(color: textSecondary, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        thickness: 1,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgSurface,
        contentTextStyle: GoogleFonts.inter(color: textPrimary, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Bottom sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
