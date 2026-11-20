import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KT {
  static const ink = Color(0xFF101114);
  static const orange = Color(0xFFFF5B14);
  static const paper = Color(0xFFF7F7F5);
  static const white = Colors.white;
  static const grey = Color(0xFF5C5F66);
  static const grey2 = Color(0xFF8A8D94);
  static const line = Color(0xFFECECE9);
  static const peach = Color(0xFFFFEFE6);
  static const mint = Color(0xFFE6F6EE);
  static const sky = Color(0xFFE8F1FF);
  static const butter = Color(0xFFFFF4CC);
  static const lilac = Color(0xFFF0EAFF);
  static const green = Color(0xFF0E7A4B);
  static const red = Color(0xFFD92D20);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: orange, primary: ink, secondary: orange, surface: white),
      scaffoldBackgroundColor: paper,
    );
    final text = GoogleFonts.figtreeTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink);
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: paper, foregroundColor: ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: GoogleFonts.figtree(fontSize: 20, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: ink, width: 1.5)),
        labelStyle: const TextStyle(color: grey, fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(color: grey2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating, backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: GoogleFonts.figtree(color: white, fontWeight: FontWeight.w600),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: white, showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    );
  }

  static TextStyle h1 = GoogleFonts.figtree(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.05);
  static TextStyle h2 = GoogleFonts.figtree(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.7);
  static TextStyle h3 = GoogleFonts.figtree(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3);
  static TextStyle body = GoogleFonts.figtree(fontSize: 15, fontWeight: FontWeight.w500, color: grey, height: 1.45);
  static TextStyle small = GoogleFonts.figtree(fontSize: 12.5, fontWeight: FontWeight.w600, color: grey2);
  static TextStyle label = GoogleFonts.figtree(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: grey);
}
