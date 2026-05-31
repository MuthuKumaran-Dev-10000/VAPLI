import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:lubrication_indicator/features/tanks/presentation/pages/create_tank_screen.dart';
// ─────────────────────────────────────────────────────────────────────────────
// Colour aliases — pulled straight from AppTheme
// ─────────────────────────────────────────────────────────────────────────────
// const _kBg = Color(0xFF0A2342);
// const _kSurface = Color(0xFF112240);
// const _kCard = Color(0xFF1A2F4A);
// const _kAccent = Color(0xFF00B4D8);
// const _kBorder = Color(0xFF1E3A5F);
// const _kText = Color(0xFFE8F0FE);
// const _kSub = Color(0xFF8892A4);
// const _kSuccess = Color(0xFF06D6A0);
// const _kWarn = Color(0xFFFFB703);
// const _kDanger = Color(0xFFEF233C);

// INDUSTRIAL PALETTE
// Same variable names preserved

const kBg = Color(0xFF0C0D0F);

const kSurface = Color(0xFF141618);

const kCard = Color(0xFF1A1C20);

// Accent (teal/live data)
const kAccent = Color(0xFF1ABCBD);

// Border
const kBorder = Color(0xFF252830);

// Text
const kText = Color(0xFFF0EEE9);

const kSub = Color(0xFF8A8F9C);

// States
const kSuccess = Color(0xFF22C55E);

const kWarn = Color(0xFFF59E0B);

const kDanger = Color(0xFFEF4444);

// ─────────────────────────────────────────────────────────────────────────────
// Shared InputDecoration helper — used everywhere so theme is consistent
// ─────────────────────────────────────────────────────────────────────────────
InputDecoration darkDeco({
  required String label,
  required IconData icon,
  String? hint,
}) =>
    InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: kSub, fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(color: kSub, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: kSub),
      filled: true,
      fillColor: kSurface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kAccent, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger, width: 2)),
    );

// Compact decoration (for inner forms inside builder page)
InputDecoration compactDeco({required String hint, required IconData icon}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kSub, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: kSub),
      isDense: true,
      filled: true,
      fillColor: kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kAccent, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger)),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Constraint operator metadata
// ─────────────────────────────────────────────────────────────────────────────

class _OpMeta {
  final String value;
  final String label;
  final String symbol;
  const _OpMeta(this.value, this.label, this.symbol);
}

// Operators available for each property type
const Map<String, List<_OpMeta>> _kTypeOps = {
  'number': [
    _OpMeta('==', 'Equals', '='),
    _OpMeta('!=', 'Not equals', '≠'),
    _OpMeta('<', 'Less than', '<'),
    _OpMeta('<=', 'Less than or equal', '≤'),
    _OpMeta('>', 'Greater than', '>'),
    _OpMeta('>=', 'Greater than / equal', '≥'),
  ],
  'text': [
    _OpMeta('==', 'Equals', '='),
    _OpMeta('!=', 'Not equals', '≠'),
    _OpMeta('contains', 'Contains', '⊃'),
    _OpMeta('starts_with', 'Starts with', '^'),
    _OpMeta('ends_with', 'Ends with', '\$'),
    _OpMeta('regex', 'Regex match', '.*'),
  ],
  'multiline': [
    _OpMeta('contains', 'Contains', '⊃'),
    _OpMeta('starts_with', 'Starts with', '^'),
    _OpMeta('ends_with', 'Ends with', '\$'),
    _OpMeta('regex', 'Regex match', '.*'),
  ],
  'dropdown': [
    _OpMeta('==', 'Must equal', '='),
    _OpMeta('!=', 'Must not equal', '≠'),
  ],
  'dual_text': [
    _OpMeta('contains', 'Contains', '⊃'),
    _OpMeta('starts_with', 'Starts with', '^'),
    _OpMeta('ends_with', 'Ends with', '\$'),
    _OpMeta('regex', 'Regex match', '.*'),
  ],
  'slider': [
    _OpMeta('==', 'Equals', '='),
    _OpMeta('!=', 'Not equals', '≠'),
    _OpMeta('<', 'Less than', '<'),
    _OpMeta('<=', 'Less than or equal', '≤'),
    _OpMeta('>', 'Greater than', '>'),
    _OpMeta('>=', 'Greater than / equal', '≥'),
  ],
};

List<_OpMeta> opsForType(String type) => _kTypeOps[type] ?? _kTypeOps['text']!;

String opSymbol(String type, String op) => opsForType(type)
    .firstWhere((o) => o.value == op, orElse: () => _OpMeta(op, op, op))
    .symbol;

String opLabel(String type, String op) => opsForType(type)
    .firstWhere((o) => o.value == op, orElse: () => _OpMeta(op, op, op))
    .label;

// ─────────────────────────────────────────────────────────────────────────────
// Deep cast helper
//
// Firebase RTDB returns nested maps as Map<Object?, Object?>.
// A shallow Map<String, dynamic>.from() only fixes the top level — nested
// maps and list elements remain wrongly typed and throw cast errors at runtime.
// This helper recurses through the entire structure.
// ─────────────────────────────────────────────────────────────────────────────

dynamic deepCast(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(
      value.entries.map(
        (e) => MapEntry(e.key.toString(), deepCast(e.value)),
      ),
    );
  }
  if (value is List) {
    return value.map(deepCast).toList();
  }
  return value;
}
