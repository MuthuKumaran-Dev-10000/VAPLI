// lib/features/dashboard/presentation/pages/dashboard_tab.dart
// ══════════════════════════════════════════════════════════════════════════════
// ALL EXISTING FEATURES PRESERVED — UI unchanged
//
// NEW IN THIS VERSION:
//   ✅ "Today's Tasks" alert panel at the TOP of the dashboard
//        - Reads from Firebase alerts/ node (live stream)
//        - Shows only unacknowledged (acknowledged == false)
//        - Filter bar: by time (newest/oldest) | by severity (critical>warn>info)
//        - Each alert card is expandable (tap) — shows all DB fields
//        - Live badge in top-right corner when alert.live == true
//        - "Complete Task" button → confirmation dialog with checkbox
//          → writes to completed_tasks/ in Firebase → marks acknowledged=true
//        - If no alerts → "No alerts today" empty state
//   ✅ Expected Avg alert — if param_stats[label].avg > inspection_properties
//      expected_avg → synthesises a critical alert shown in the panel
//      (written to alerts/ by the dashboard itself)
//   ✅ NumChip: value text medium size (14px, not 16), colored same as chip
//   ✅ "Tasks Completed Today" section BELOW tank cards
//   ✅ "Tasks in Previous Days" section (descending by completion time)
//   ✅ All tank cards, param blocks, last-inspection panel unchanged
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lubrication_indicator/core/services/audit_log_service.dart';
import 'package:lubrication_indicator/core/utils/session_manager.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:lubrication_indicator/features/dashboard/data/models/dashboard_stats_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/dashboard/data/repositories/dashboard_stats_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
part 'widgets/_alert_card.dart';
part 'widgets/_alert_card_state.dart';
part 'widgets/_completed_card.dart';
part 'widgets/_completed_card_state.dart';
part 'widgets/_alerts_empty.dart';
part 'widgets/_filter_chip.dart';
part 'widgets/_sev_badge.dart';
part 'widgets/_detail_row.dart';
part 'widgets/_image_thumb.dart';
part 'widgets/_fullscreen_image_viewer.dart';
part 'widgets/_summary_strip.dart';
part 'widgets/_summary_strip_state.dart';
part 'widgets/_kpi_chip.dart';
part 'widgets/_tank_stats_card.dart';
part 'widgets/_tank_stats_card_state.dart';
part 'widgets/_numeric_stat_row.dart';
part 'widgets/_dual_stat_block.dart';
part 'widgets/_num_chip.dart';
part 'widgets/_dropdown_stat_block.dart';
part 'widgets/_text_last_value.dart';
part 'widgets/_meta_pill.dart';
part 'widgets/_type_badge.dart';
part 'widgets/_section_label.dart';
part 'widgets/_divider.dart';
part 'dashboard_tab_state.dart';
part 'dashboard_models/_alert_model.dart';
part 'dashboard_models/_completed_task.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — unchanged
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kCardHi = Color(0xFF1F2228);
const _kBorder = Color(0xFF252830);
const _kBorderH = Color(0xFF38404F);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperL = Color(0xFFE8A84E);
const _kCopperD = Color(0xFF8A5A1E);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSubL = Color(0xFF6B7280);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kPurple = Color(0xFFAB8FF0);
const _kBlue = Color(0xFF60A5FA);
const _kInfo = Color(0xFF60A5FA);

// ─────────────────────────────────────────────────────────────────────────────
// Alert model (mirrors Firebase alerts/ node)
// ─────────────────────────────────────────────────────────────────────────────
enum _AlertFilter { time, severity }

// ─────────────────────────────────────────────────────────────────────────────
// DashboardTab
// ─────────────────────────────────────────────────────────────────────────────
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

