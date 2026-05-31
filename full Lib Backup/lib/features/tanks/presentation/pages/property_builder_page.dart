// lib/features/tanks/presentation/pages/property_builder_page.dart
// ══════════════════════════════════════════════════════════════════════════════
// FIXES IN THIS VERSION:
//
//   FIX 1 — Expression is now properly SAVED:
//     • Added a "Save Expression" button inside the AutoFill section.
//     • Tapping it validates the expression, sets autofill: true, and
//       commits both the raw token expression and the display expression.
//     • autofill: true is now correctly stored on _save() because
//       _autoFillEnabled is properly managed.
//
//   FIX 2 — Two-expression storage:
//     • _exprCtrl         → raw expression  e.g. ${id_OilTemp}*0.5+${id2_Pressure}
//                           Used by the reading page for eval().
//     • _displayExprCtrl  → human-readable  e.g. OilTemp * 0.5 + Pressure
//                           Shown inside the editor so the user isn't confused.
//     • Saved as:
//         'autofill_expression'         → raw token string  (eval-ready)
//         'autofill_expression_display' → human name string (UI label)
//
//   FIX 3 — Expression editor shows human-readable names:
//     • The editable text field inside the AutoFill box shows _displayExprCtrl
//       (param names + operators, no ${...} noise).
//     • A collapsible "Raw Expression" chip row above shows the token preview
//       so the developer/admin can verify the stored form.
//
//   FIX 4 — Operator row and numpad write to both controllers in sync.
//
//   FIX 5 — DEL deletes from both controllers in sync (whole token on
//     _exprCtrl, whole name-token on _displayExprCtrl).
//
//   STORAGE RULES (unchanged):
//     • left_label / right_label only for dual_text.
//     • expected_min/avg/max for number/slider.
//     • left/right_expected_min/avg/max for dual_text.
//
//   LOCAL SQLite SCHEMA (unchanged):
//     Table: session_params
//       id           TEXT PRIMARY KEY
//       session_id   TEXT
//       label        TEXT
//       type         TEXT
//       left_label   TEXT
//       right_label  TEXT
//
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:lubrication_indicator/core/services/expression_engine.dart';

import 'package:lubrication_indicator/features/tanks/presentation/widgets/create_tank_screen_helpers.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/types_and_small_widgets.dart';
part 'widgets/_param_dropdown.dart';
part 'widgets/_param_dropdown_state.dart';
part 'widgets/_param_picker_sheet.dart';
part 'widgets/_picker_tile.dart';
part 'widgets/_expression_display.dart';
part 'widgets/_operator_row.dart';
part 'widgets/_numpad.dart';
part 'widgets/_type_chip.dart';
part 'widgets/_side_button.dart';
part 'widgets/_constraint_flag.dart';
part 'widgets/_expected_range_card.dart';
part 'widgets/_range_row.dart';
part 'widgets/_dark_text_field.dart';
part 'property_builder_page_state.dart';
part 'property_builder_models/session_param_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kAccent = Color(0xFF1ABCBD);
const _kBorder = Color(0xFF252830);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);

const _kSevInfo = Color(0xFF60A5FA);
const _kSevWarning = Color(0xFFF59E0B);
const _kSevCritical = Color(0xFFEF4444);
const _kAutoFill = Color(0xFFBB86FC);

Color _sevColor(String s) {
  switch (s) {
    case 'critical':
      return _kSevCritical;
    case 'warning':
      return _kSevWarning;
    default:
      return _kSevInfo;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionParamStore
// ─────────────────────────────────────────────────────────────────────────────
class PropertyBuilderPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final void Function(Map<String, dynamic>) onSave;
  final String scopeId;

  const PropertyBuilderPage({
    required this.onSave,
    required this.scopeId,
    this.existing,
    super.key,
  });

  static Future<void> clearScope(String scopeId) =>
      SessionParamStore.clearScope(scopeId);

  @override
  State<PropertyBuilderPage> createState() => PropertyBuilderPageState();
}

