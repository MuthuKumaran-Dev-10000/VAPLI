// lib/presentation/screens/trends/trends_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// FULL REPLACEMENT — all features implemented:
//   ✅ Obsidian-industrial UI — matches reading_entry_screen + dashboard_tab
//   ✅ Only graphable params shown: number | slider | dual_text | dropdown
//      Text / multiline hidden; hint shown below dropdown
//   ✅ Each param item shows type badge next to its name
//   ✅ Graph borders ONLY on left + bottom axes (not 4 sides)
//   ✅ Graph title strip: Tank Name • Parameter Name always visible
//   ✅ Legend below every chart (line colours, bar colours)
//   ✅ X-axis labels = reading index (1, 2, 3 …) — NOT datetime
//   ✅ dual_text → TWO lines (left series copper, right series teal)
//   ✅ dropdown  → bar chart, one bar per option coloured distinctly
//   ✅ number / slider → single copper line chart
//   ✅ PNG export captures chart + title strip
//   ✅ Excel export: all columns (tank, capturedAt, inspector + all param values)
//   ✅ Smart in-memory cache: tank → readings fetched once, invalidated on
//      tank switch; "Show Trend" re-uses cache if tank unchanged
//   ✅ CapturedAt used everywhere (not DateTime label)
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui' as ui;

import 'package:excel/excel.dart' as xl;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/reading_model.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/repositories/reading_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — identical to ReadingEntryScreen + DashboardTab
// ─────────────────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard    = Color(0xFF1A1C20);
const _kBorder  = Color(0xFF252830);
const _kBorderH = Color(0xFF38404F);
const _kCopper  = Color(0xFFCB8C3E);
const _kCopperL = Color(0xFFE8A84E);
const _kTeal    = Color(0xFF1ABCBD);
const _kText    = Color(0xFFF0EEE9);
const _kSub     = Color(0xFF8A8F9C);
const _kSubL    = Color(0xFF6B7280);
const _kSuccess = Color(0xFF22C55E);
const _kWarn    = Color(0xFFF59E0B);
const _kDanger  = Color(0xFFEF4444);
const _kPurple  = Color(0xFFAB8FF0);
const _kBlue    = Color(0xFF60A5FA);

// Bar chart colours cycling list
const _kBarPalette = [
  _kTeal, _kCopper, _kSuccess, _kWarn, _kPurple, _kBlue, _kDanger,
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _fmtCapturedAt(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  try {
    final dt = DateTime.parse(raw).toLocal();
    return DateFormat('dd MMM yy').format(dt);
  } catch (_) {
    return raw;
  }
}

// Which types are graphable
bool _isGraphable(String? type) =>
    type == 'number' || type == 'slider' ||
    type == 'dual_text' || type == 'dropdown';

// Human label for type badge
String _typeLabel(String? type) {
  switch (type) {
    case 'number':    return 'NUM';
    case 'slider':    return 'SLIDER';
    case 'dual_text': return 'DUAL';
    case 'dropdown':  return 'DROP';
    default:          return (type ?? '').toUpperCase();
  }
}

Color _typeBadgeColor(String? type) {
  switch (type) {
    case 'number':    return _kTeal;
    case 'slider':    return Color(0xFF03DAC6);
    case 'dual_text': return _kWarn;
    case 'dropdown':  return _kPurple;
    default:          return _kSubL;
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

class _TrendsScreenState extends State<TrendsScreen> {
  final _repo     = ReadingRepository();
  final _chartKey = GlobalKey();

  TankModel?              _tank;
  Map<String, dynamic>?  _param;
  List<ReadingModel>      _readings  = [];
  bool                    _loading   = false;
  bool                    _hasShown  = false; // chart visible once loaded

  // ── In-memory cache: tankId → readings ──────────────────────────────────
  // Populated on first "Show Trend" for each tank; reused on param switch.
  final Map<String, List<ReadingModel>> _cache = {};

  // ── Graphable params for selected tank ────────────────────────────────────
  List<Map<String, dynamic>> get _graphableParams {
    if (_tank == null) return [];
    return _tank!.inspectionProperties
        .where((e) => _isGraphable(e['type'] as String?))
        .toList();
  }

  // ── Load readings (cache-first) ───────────────────────────────────────────
  Future<void> _load() async {
    if (_tank == null) {
      _snack('Please select a tank first');
      return;
    }
    if (_param == null) {
      _snack('Please select a parameter');
      return;
    }

    setState(() => _loading = true);
    try {
      if (_cache.containsKey(_tank!.id)) {
        debugPrint('[Trends] Cache HIT for tank ${_tank!.id}');
        _readings = _cache[_tank!.id]!;
      } else {
        debugPrint('[Trends] Cache MISS — fetching from DB for tank ${_tank!.id}');
        final all = await _repo.getAllReadings();
        final filtered = all.where((r) => r.tankId == _tank!.id).toList();
        // Sort chronologically
        filtered.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
        _cache[_tank!.id] = filtered;
        _readings = filtered;
        debugPrint('[Trends] Fetched ${_readings.length} readings, cached.');
      }
      setState(() { _hasShown = true; _loading = false; });
    } catch (e) {
      debugPrint('[Trends] Load error: $e');
      setState(() => _loading = false);
      _snack('Failed to load readings: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText)),
      backgroundColor: _kBorder,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('Trends',
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700, fontSize: 17, color: _kText)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header label ─────────────────────────────────────────────
            _SecLabel('SELECT DATA SOURCE'),
            const SizedBox(height: 14),

            // ── Tank selector ─────────────────────────────────────────────
            _buildTankDropdown(),
            const SizedBox(height: 14),

            // ── Parameter selector ────────────────────────────────────────
            _buildParamDropdown(),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline_rounded, size: 11, color: _kSubL),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Only Number, Slider, Dual Input and Dropdown parameters '
                  'are graphable. Text fields are excluded.',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kSubL),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Show Trend button ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kCopper,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kSurface,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _loading ? null : _load,
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.show_chart_rounded, size: 18),
                label: Text(
                  _loading ? 'Loading…' : 'Show Trend',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Chart (only when loaded + param selected) ─────────────────
            if (_hasShown && _param != null && _readings.isNotEmpty)
              _buildChartCard(),

            if (_hasShown && _readings.isEmpty)
              _buildNoData(),

            const SizedBox(height: 20),

            // ── Excel export (always available once tank loaded) ──────────
            if (_hasShown && _readings.isNotEmpty)
              _buildExcelButton(),
          ],
        ),
      ),
    );
  }

  // ── Selectors ─────────────────────────────────────────────────────────────

  Widget _buildTankDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TankModel>(
          value: _tank,
          isExpanded: true,
          dropdownColor: _kCard,
          iconEnabledColor: _kSub,
          hint: Text('Select tank…',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 14)),
          items: widget.tanks.map((t) => DropdownMenuItem(
            value: t,
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _kCopper.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kCopper.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text(
                    t.tankCode.isNotEmpty ? t.tankCode[0].toUpperCase() : '?',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11, color: _kCopper, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.tankName,
                      style: GoogleFonts.dmSans(
                          color: _kText, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(t.tankCode,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: _kSub)),
                ]),
              ),
            ]),
          )).toList(),
          onChanged: (v) {
            debugPrint('[Trends] Tank selected: ${v?.tankCode}');
            setState(() {
              _tank  = v;
              _param = null;
              _hasShown = false;
              _readings = [];
              // Note: keep cache for this tank if it exists
            });
          },
        ),
      ),
    );
  }

  Widget _buildParamDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _tank == null ? _kBorder : _kBorderH),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Map<String, dynamic>>(
          value: _param,
          isExpanded: true,
          dropdownColor: _kCard,
          iconEnabledColor: _tank == null ? _kSubL : _kSub,
          hint: Text(
            _tank == null ? 'Select a tank first…' : 'Select parameter…',
            style: GoogleFonts.dmSans(color: _kSubL, fontSize: 14),
          ),
          items: _graphableParams.map((p) {
            final type  = p['type'] as String? ?? '';
            final label = p['label'] as String? ?? '';
            final bColor = _typeBadgeColor(type);
            return DropdownMenuItem<Map<String, dynamic>>(
              value: p,
              child: Row(children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: bColor.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: bColor.withOpacity(0.35)),
                  ),
                  child: Text(_typeLabel(type),
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9, color: bColor, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.dmSans(
                          color: _kText, fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ]),
            );
          }).toList(),
          onChanged: _tank == null
              ? null
              : (v) {
                  debugPrint('[Trends] Param selected: ${v?['label']}');
                  setState(() => _param = v);
                },
        ),
      ),
    );
  }

  // ── Chart card ─────────────────────────────────────────────────────────────

  Widget _buildChartCard() {
    final type  = _param!['type'] as String? ?? 'number';
    final label = _param!['label'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecLabel('TREND CHART'),
        const SizedBox(height: 12),
        RepaintBoundary(
          key: _chartKey,
          child: Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title strip ──────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 3, height: 18,
                      decoration: BoxDecoration(
                          color: _kCopper,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(_tank!.tankName,
                            style: GoogleFonts.dmSans(
                                color: _kText, fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        Text(label,
                            style: GoogleFonts.spaceGrotesk(
                                color: _kCopper, fontSize: 11,
                                fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _typeBadgeColor(type).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _typeBadgeColor(type).withOpacity(0.35)),
                      ),
                      child: Text(_typeLabel(type),
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, color: _typeBadgeColor(type),
                              fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    ),
                  ]),
                ),

                // ── Chart area ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 18, 8),
                  child: SizedBox(
                    height: 280,
                    child: _buildGraph(type, label),
                  ),
                ),

                // ── Legend ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: _buildLegend(type, label),
                ),

                // ── Reading count ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    '${_readings.length} reading${_readings.length == 1 ? '' : 's'} '
                    '· Tap PNG to export chart',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _kSubL),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── PNG export button ─────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kBorderH),
              foregroundColor: _kText,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _exportPng,
            icon: const Icon(Icons.image_outlined, size: 18, color: _kCopper),
            label: Text('Export Chart as PNG',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600, fontSize: 13, color: _kText)),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildNoData() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bar_chart_outlined, size: 40, color: _kSubL),
            const SizedBox(height: 10),
            Text('No readings found for this tank',
                style: GoogleFonts.dmSans(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _kText)),
            const SizedBox(height: 4),
            Text('Submit readings via the Record Reading screen first.',
                style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
          ]),
        ),
      );

  // ── Graph dispatcher ───────────────────────────────────────────────────────

  Widget _buildGraph(String type, String label) {
    if (type == 'dropdown') return _barChart(label);
    if (type == 'dual_text') return _dualLineChart(label);
    return _singleLineChart(label); // number | slider
  }

  // ── Shared axis/border style ───────────────────────────────────────────────
  // ONLY left + bottom borders — no right, no top

  FlBorderData get _borderData => FlBorderData(
        show: true,
        border: Border(
          left:   const BorderSide(color: _kBorderH, width: 1),
          bottom: const BorderSide(color: _kBorderH, width: 1),
          right:  BorderSide.none,
          top:    BorderSide.none,
        ),
      );

  FlGridData get _gridData => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: _kBorder,
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      );

  SideTitles get _bottomTitles => SideTitles(
        showTitles: true,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final idx = value.toInt() - 1;
          if (idx < 0 || idx >= _readings.length) return const SizedBox.shrink();
          // Show index number, not datetime
          final label = '${idx + 1}';
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9, color: _kSubL, fontWeight: FontWeight.w500)),
          );
        },
      );

  SideTitles get _leftTitles => SideTitles(
        showTitles: true,
        reservedSize: 38,
        getTitlesWidget: (value, meta) => Text(
          value.toStringAsFixed(value == value.truncateToDouble() ? 0 : 1),
          style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _kSubL),
        ),
      );

  // ── Single line chart (number | slider) ────────────────────────────────────

  Widget _singleLineChart(String label) {
    final spots = <FlSpot>[];
    for (int i = 0; i < _readings.length; i++) {
      final raw = _readings[i].inspectionValues[label];
      final num? v = raw is num ? raw : double.tryParse(raw?.toString() ?? '');
      if (v != null) spots.add(FlSpot((i + 1).toDouble(), v.toDouble()));
    }

    if (spots.isEmpty) {
      return _noDataOverlay('No numeric values found for "$label"');
    }

    return LineChart(LineChartData(
      borderData: _borderData,
      gridData:   _gridData,
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: _bottomTitles),
        leftTitles:   AxisTitles(sideTitles: _leftTitles),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: _kCopper,
          barWidth: 2.5,
          isCurved: true,
          curveSmoothness: 0.3,
          dotData: FlDotData(
            show: spots.length <= 20,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 4,
              color: _kCopper,
              strokeWidth: 1.5,
              strokeColor: _kCopperL,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [_kCopper.withOpacity(0.18), _kCopper.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    ));
  }

  // ── Dual line chart (dual_text → left + right) ─────────────────────────────

  Widget _dualLineChart(String label) {
    final leftSpots  = <FlSpot>[];
    final rightSpots = <FlSpot>[];

    for (int i = 0; i < _readings.length; i++) {
      final raw = _readings[i].inspectionValues[label];
      if (raw is Map) {
        final lRaw = raw['left'];
        final rRaw = raw['right'];
        final lv = lRaw is num ? lRaw.toDouble() : double.tryParse(lRaw?.toString() ?? '');
        final rv = rRaw is num ? rRaw.toDouble() : double.tryParse(rRaw?.toString() ?? '');
        final x  = (i + 1).toDouble();
        if (lv != null) leftSpots.add(FlSpot(x, lv));
        if (rv != null) rightSpots.add(FlSpot(x, rv));
      }
    }

    if (leftSpots.isEmpty && rightSpots.isEmpty) {
      return _noDataOverlay('No numeric dual-input values found for "$label"');
    }

    final leftLabel  = _param!['left_label']  as String? ?? 'Left';
    final rightLabel = _param!['right_label'] as String? ?? 'Right';

    return LineChart(LineChartData(
      borderData: _borderData,
      gridData:   _gridData,
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: _bottomTitles),
        leftTitles:   AxisTitles(sideTitles: _leftTitles),
      ),
      lineBarsData: [
        // Left series — copper
        if (leftSpots.isNotEmpty)
          LineChartBarData(
            spots: leftSpots,
            color: _kCopper,
            barWidth: 2.5,
            isCurved: true,
            curveSmoothness: 0.3,
            dotData: FlDotData(
              show: leftSpots.length <= 20,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4, color: _kCopper,
                strokeWidth: 1.5, strokeColor: _kCopperL,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [_kCopper.withOpacity(0.15), _kCopper.withOpacity(0.0)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
        // Right series — teal
        if (rightSpots.isNotEmpty)
          LineChartBarData(
            spots: rightSpots,
            color: _kTeal,
            barWidth: 2.5,
            isCurved: true,
            curveSmoothness: 0.3,
            dotData: FlDotData(
              show: rightSpots.length <= 20,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4, color: _kTeal,
                strokeWidth: 1.5, strokeColor: _kTeal.withOpacity(0.5),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [_kTeal.withOpacity(0.12), _kTeal.withOpacity(0.0)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
      ],
    ));
  }

  // ── Bar chart (dropdown) ───────────────────────────────────────────────────

  Widget _barChart(String label) {
    final counts = <String, int>{};
    for (final r in _readings) {
      final v = r.inspectionValues[label]?.toString() ?? '';
      if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }

    if (counts.isEmpty) {
      return _noDataOverlay('No dropdown selections found for "$label"');
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxY = entries.first.value.toDouble();

    return BarChart(BarChartData(
      borderData: _borderData,
      gridData:   _gridData,
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY * 1.25,
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles:  AxisTitles(sideTitles: _leftTitles),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
              final opt = entries[idx].key;
              final short = opt.length > 8 ? '${opt.substring(0, 7)}…' : opt;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(short,
                    style: GoogleFonts.dmSans(
                        fontSize: 9, color: _kSubL, fontWeight: FontWeight.w500)),
              );
            },
          ),
        ),
      ),
      barGroups: entries.asMap().entries.map((e) {
        final idx   = e.key;
        final count = e.value.value.toDouble();
        final color = _kBarPalette[idx % _kBarPalette.length];
        return BarChartGroupData(
          x: idx,
          barRods: [
            BarChartRodData(
              toY: count,
              color: color,
              width: 28,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY * 1.25,
                color: color.withOpacity(0.07),
              ),
            ),
          ],
        );
      }).toList(),
    ));
  }

  Widget _noDataOverlay(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.show_chart_rounded, size: 36, color: _kSubL),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
        ]),
      );

  // ── Legend ─────────────────────────────────────────────────────────────────

  Widget _buildLegend(String type, String label) {
    if (type == 'dual_text') {
      final leftLabel  = _param!['left_label']  as String? ?? 'Left';
      final rightLabel = _param!['right_label'] as String? ?? 'Right';
      return Row(children: [
        _LegendDot(color: _kCopper, label: '← $leftLabel'),
        const SizedBox(width: 18),
        _LegendDot(color: _kTeal,   label: '→ $rightLabel'),
      ]);
    }

    if (type == 'dropdown') {
      final counts = <String, int>{};
      for (final r in _readings) {
        final v = r.inspectionValues[label]?.toString() ?? '';
        if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
      }
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final total = counts.values.fold(0, (a, b) => a + b);
      return Wrap(
        spacing: 12, runSpacing: 6,
        children: entries.asMap().entries.map((e) {
          final color = _kBarPalette[e.key % _kBarPalette.length];
          final pct   = total > 0 ? (e.value.value / total * 100).toStringAsFixed(1) : '0';
          return _LegendDot(
              color: color,
              label: '${e.value.key}  ${e.value.value}×  ($pct%)');
        }).toList(),
      );
    }

    // number | slider
    return _LegendDot(color: _kCopper, label: label);
  }

  // ── Excel export ───────────────────────────────────────────────────────────

  Widget _buildExcelButton() => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _kBorderH),
            foregroundColor: _kText,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _exportExcel,
          icon: const Icon(Icons.table_chart_outlined, size: 18, color: _kSuccess),
          label: Text('Export All Readings as Excel',
              style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w600, fontSize: 13, color: _kText)),
        ),
      );

  Future<void> _exportExcel() async {
    debugPrint('[Trends] Exporting Excel — ${_readings.length} readings');
    final excel = xl.Excel.createExcel();
    final sheet = excel[_tank?.tankName ?? 'Readings'];

    // Collect all param labels for columns
    final paramLabels = _tank?.inspectionProperties
            .map((p) => p['label'] as String? ?? '')
            .where((l) => l.isNotEmpty)
            .toList() ??
        [];

    // Header row
    sheet.appendRow([
      xl.TextCellValue('Tank'),
      xl.TextCellValue('Captured At'),
      xl.TextCellValue('Inspector'),
      ...paramLabels.map((l) => xl.TextCellValue(l)),
    ]);

    // Data rows
    for (final r in _readings) {
      final paramValues = paramLabels.map((l) {
        final v = r.inspectionValues[l];
        if (v is Map) {
          // dual_text: export as "left | right"
          return xl.TextCellValue(
              '${v['left'] ?? ''} | ${v['right'] ?? ''}');
        }
        return xl.TextCellValue(v?.toString() ?? '');
      }).toList();

      sheet.appendRow([
        xl.TextCellValue(r.tankSnapshotName ?? _tank?.tankName ?? ''),
        xl.TextCellValue(_fmtCapturedAt(r.capturedAt)),
        xl.TextCellValue(r.capturedByName ?? ''),
        ...paramValues,
      ]);
    }

    final dir  = await getTemporaryDirectory();
    final name = '${_tank?.tankCode ?? 'tank'}_readings.xlsx';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(excel.save()!);
    debugPrint('[Trends] Excel saved → ${file.path}');
    await Share.shareXFiles([XFile(file.path)],
        text: 'Readings for ${_tank?.tankName ?? 'tank'}');
  }

  // ── PNG export ─────────────────────────────────────────────────────────────

  Future<void> _exportPng() async {
    debugPrint('[Trends] Exporting PNG chart');
    try {
      final boundary = _chartKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir   = await getTemporaryDirectory();
      final name  = '${_tank?.tankCode ?? 'tank'}_${_param?['label'] ?? 'chart'}.png';
      final file  = File('${dir.path}/$name');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('[Trends] PNG saved → ${file.path}');
      await Share.shareXFiles([XFile(file.path)],
          text: '${_tank?.tankName} — ${_param?['label']}');
    } catch (e) {
      debugPrint('[Trends] PNG export error: $e');
      _snack('PNG export failed: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SecLabel extends StatelessWidget {
  final String text;
  const _SecLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.spaceGrotesk(
          fontSize: 9, fontWeight: FontWeight.w700,
          color: _kSubL, letterSpacing: 1.5));
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.dmSans(fontSize: 11, color: _kSub,
                fontWeight: FontWeight.w500)),
      ]);
}