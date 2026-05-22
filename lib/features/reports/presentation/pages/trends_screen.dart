// lib/features/reports/presentation/pages/trends_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// Production-grade TrendsScreen for VAPLI Lubrication Monitor
//
// FEATURES:
//   ✅ Tank selector (single + "All Tanks") with QR scan button
//   ✅ Timeline: Week / Month / Year / Custom (from→to calendars)
//   ✅ Graphable param dropdown: number | slider | dual_text | dropdown only
//      (type badge shown inline, text/multiline excluded)
//   ✅ "All Tanks" mode → multi-line timeline graph (one line per tank)
//   ✅ Aggressive in-memory cache (tankId → readings); zero extra reads on
//      param switch, excel export, png export
//   ✅ Graph types:
//        number/slider  → single copper line
//        dual_text      → two lines (copper=left, teal=right)
//        dropdown       → bar chart per option (X=iterator+label, Y=count)
//        all tanks      → multi-line, one per tank
//   ✅ Axes: left + bottom ONLY (right + top hidden). X starts at 1.
//      X label = capturedAt formatted date (DD/MM/YYYY\nHH:mm, sparse ≤5)
//   ✅ Graph title strip: Tank • Param • From • To
//   ✅ RepaintBoundary PNG export (title + chart + legend)
//   ✅ Excel export: Sheet1=summary, SheetN=per tank, all param columns
//      File name: Lubrication_Report_<from>_<to>_<tanks>.xlsx
//   ✅ Handles 1000+ readings / 50+ tanks — no unnecessary rebuilds
//   ✅ Matches existing dark industrial palette exactly
//   ✅ All chart variables are LOCAL (no class-scope spots/xLabels leakage)
//   ✅ Sorted oldest→newest everywhere; newest always on RIGHT edge
//
// FIX (fl_chart 1.2.0):
//   tooltipRoundedRadius (removed) → tooltipBorderRadius: BorderRadius.circular(8)
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui' as ui;

import 'package:excel/excel.dart' as xl;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';
part 'widgets/_qr_scan_page.dart';
part 'widgets/_qr_scan_page_state.dart';
part 'widgets/_overlay_painter.dart';
part 'widgets/_corner.dart';
part 'widgets/_sec_label.dart';
part 'widgets/_drop_container.dart';
part 'widgets/_date_btn.dart';
part 'widgets/_meta_chip.dart';
part 'widgets/_legend_dot.dart';
part 'widgets/_legend_line.dart';
part 'trends_screen_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PALETTE — identical to ReadingEntryScreen + DashboardTab
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
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
const _kIndigo = Color(0xFF818CF8);

// Bar / multi-line colour palette
const _kMultiPalette = [
  _kCopper,
  _kTeal,
  _kSuccess,
  _kWarn,
  _kPurple,
  _kBlue,
  _kDanger,
  _kIndigo,
  Color(0xFFFF6B6B),
  Color(0xFF4ECDC4),
];

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
const _kAllTanksId = '__ALL__';

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

bool _isGraphable(String? type) =>
    type == 'number' ||
    type == 'slider' ||
    type == 'dual_text' ||
    type == 'dropdown';

String _typeShort(String? type) {
  switch (type) {
    case 'number':
      return 'NUM';
    case 'slider':
      return 'SLIDE';
    case 'dual_text':
      return 'DUAL';
    case 'dropdown':
      return 'DROP';
    default:
      return (type ?? '').toUpperCase();
  }
}

Color _typeColor(String? type) {
  switch (type) {
    case 'number':
      return _kTeal;
    case 'slider':
      return const Color(0xFF03DAC6);
    case 'dual_text':
      return _kWarn;
    case 'dropdown':
      return _kPurple;
    default:
      return _kSubL;
  }
}

/// Format an ISO datetime string.
/// Default: two-line DD/MM/YYYY\nHH:mm for axis labels.
String _fmt(String? iso, {String pattern = 'dd/MM/yyyy\nHH:mm'}) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat(pattern).format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

String _fmtFull(String? iso) => _fmt(iso, pattern: 'dd MMM yyyy, HH:mm');

String _fmtFile(DateTime d) => DateFormat('yyyyMMdd').format(d);

// ─────────────────────────────────────────────────────────────────────────────
// TIMELINE ENUM
// ─────────────────────────────────────────────────────────────────────────────
enum _Timeline { week, month, year, custom }

extension _TL on _Timeline {
  String get label {
    switch (this) {
      case _Timeline.week:
        return 'Last 7 Days';
      case _Timeline.month:
        return 'Last 30 Days';
      case _Timeline.year:
        return 'Last Year';
      case _Timeline.custom:
        return 'Custom Range';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TrendsScreen
// ─────────────────────────────────────────────────────────────────────────────
class TrendsScreen extends StatefulWidget {
  final List<TankModel> tanks;
  const TrendsScreen({super.key, required this.tanks});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

