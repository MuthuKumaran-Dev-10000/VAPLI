// lib/features/readings/presentation/pages/reading_entry_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// FEATURES:
//   ✅ ALL original features preserved
//   ✅ Capture image → immediate Cloudinary upload → URL stored in memory
//   ✅ Violation alert written to DB the instant photo is captured (not on save)
//   ✅ Constraint clears → corresponding alert record DELETED from DB dynamically
//   ✅ Value changes → alert updated live in DB if constraint still active
//   ✅ Manual captures hidden behind AppBar toggle (camera icon, top-right)
//   ✅ Manual captures section expands / collapses — add/delete entries freely
//   ✅ All per-param photo captures also upload immediately on capture
//   ✅ On final Save: no re-upload needed (URLs already stored); just assembles
//      the reading record and writes it
//   ✅ NEW: Autofill parameters — disabled by default, radio button to toggle
//      manual entry ("Autofill" label to enable/disable autofill)
//   ✅ NEW: Expression evaluation — auto-calculates when all deps are filled
//   ✅ NEW: Dependency status list with ✓ (green) / ✗ (red) per param
//   ✅ NEW: Re-evaluates when any dependency param changes (edit/delete)
//   ✅ NEW: Math errors caught (divide-by-zero, etc.) shown in layman terms
//   ✅ NEW: Sound + vibration fixed using AudioPlayer with asset fallback
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async'; // 🔖 Added for Alert Lifecycle Bug Fix
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/audit_log_service.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/expression_engine.dart';
import 'package:lubrication_indicator/core/services/env_config.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/dashboard/data/repositories/dashboard_stats_repository.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';
import 'package:lubrication_indicator/features/alerts/data/models/alert_model.dart'; // 🔖 Added for Alert Lifecycle Bug Fix
import 'image_marker_screen.dart';
part 'reading_entry_state.dart';
part 'reading_entry_models/_autofill_result.dart';
part 'reading_entry_models/_violation.dart';
part 'reading_entry_models/_manual_capture_entry.dart';
part '_division_by_zero_exception.dart';
part '_math_exception.dart';
part 'widgets/_autofill_toggle_row.dart';
part 'widgets/_autofill_status_section.dart';
part 'widgets/_autofill_result_card.dart';
part 'widgets/_autofill_error_card.dart';
part 'widgets/_violation_banner.dart';
part 'widgets/_block_banner.dart';
part 'widgets/_uploading_banner.dart';
part 'widgets/_param_photo_row.dart';
part 'widgets/_error_banner.dart';
part 'widgets/_meta_card.dart';
part 'widgets/_meta_row.dart';
part 'widgets/_save_button.dart';
part 'widgets/_sec_label.dart';
part 'widgets/_badge.dart';
part 'widgets/_action_chip.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kBorder = Color(0xFF252830);
const _kBorderH = Color(0xFF32363F);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperD = Color(0xFF8A5A1E);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kDisable = Color(0xFF484C57);
const _kInfo = Color(0xFF60A5FA);
const _kPurple = Color(0xFFAB8FF0);

// ── Cloudinary ────────────────────────────────────────────────────────────────
const _folder = 'lubricationindicator';

// ── Helpers ───────────────────────────────────────────────────────────────────
Color _severityColor(String? s) {
  switch (s) {
    case 'critical':
      return _kDanger;
    case 'warning':
      return _kWarn;
    case 'info':
      return _kInfo;
    default:
      return _kWarn;
  }
}

IconData _severityIcon(String? s) {
  switch (s) {
    case 'critical':
      return Icons.dangerous_rounded;
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'info':
      return Icons.info_outline_rounded;
    default:
      return Icons.warning_amber_rounded;
  }
}

// ── Autofill expression result ────────────────────────────────────────────────
class ReadingEntryScreen extends StatefulWidget {
  final TankModel tank;
  final UserModel currentUser;
  final List<TankModel>? siblingTanks; // 🔖 Added for Reading Capture Flow Refactor
  final int? currentTankIndex; // 🔖 Added for Reading Capture Flow Refactor
  final String? duplicateReason; // 🔖 Added for Duplicate Reading Validation

  const ReadingEntryScreen({
    super.key,
    required this.tank,
    required this.currentUser,
    this.siblingTanks, // 🔖 Added for Reading Capture Flow Refactor
    this.currentTankIndex, // 🔖 Added for Reading Capture Flow Refactor
    this.duplicateReason, // 🔖 Added for Duplicate Reading Validation
  });

  @override
  State<ReadingEntryScreen> createState() => _ReadingEntryScreenState();
}
