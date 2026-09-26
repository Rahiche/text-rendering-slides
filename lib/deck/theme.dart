import 'package:flutter/material.dart';

/// Blueprint palette. Every slide draws with these, nothing else.
abstract final class BP {
  // Paper
  static const bg = Color(0xFF081728);
  static const paper = Color(0xFF0A1B2E);
  static const panel = Color(0xFF0C2137);
  static const gridMinor = Color(0xFF0F2540);
  static const gridMajor = Color(0xFF16345A);

  // Ink
  static const line = Color(0xFF5FB8FF);
  static const lineDim = Color(0xFF2E6DA8);
  static const lineFaint = Color(0xFF1C4570);
  static const ink = Color(0xFFE3F2FF);
  static const inkDim = Color(0xFF8DB7DA);
  static const inkFaint = Color(0xFF4F7AA3);

  // Meaning
  static const amber = Color(0xFFFFC66D); // highlight / attention
  static const red = Color(0xFFFF6F7D); // not possible
  static const green = Color(0xFF6CE5B1); // possible
  static const violet = Color(0xFFC39BFF);
  static const coral = Color(0xFFFF9E7A);
  static const pink = Color(0xFFFF8FC8);

  // Design canvas: every slide is laid out at this size and scaled to fit.
  static const canvas = Size(1600, 900);
  static const margin = 64.0;

  // Fonts
  static const display = 'SpaceGrotesk';
  static const mono = 'JetBrainsMono';
  static const arabic = 'NotoKufiArabic';
}

/// Text style helpers. Variable fonts need the `wght` axis set explicitly.
abstract final class BT {
  static TextStyle display(
    double size, {
    Color color = BP.ink,
    double weight = 500,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: const [BP.arabic],
    fontSize: size,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: [FontVariation.weight(weight)],
  );

  static TextStyle mono(
    double size, {
    Color color = BP.line,
    double weight = 400,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: BP.mono,
    fontFamilyFallback: const [BP.arabic],
    fontSize: size,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    fontVariations: [FontVariation.weight(weight)],
  );

  /// For sample text in many scripts: our display font first, then Arabic,
  /// then whatever the platform (or the web's Noto fallback) provides.
  static TextStyle sample(
    double size, {
    Color color = BP.ink,
    double weight = 400,
    double? height,
    List<FontFeature>? features,
  }) => TextStyle(
    fontFamily: BP.display,
    fontFamilyFallback: const [BP.arabic],
    fontSize: size,
    color: color,
    height: height,
    fontFeatures: features,
    fontVariations: [FontVariation.weight(weight)],
  );
}
