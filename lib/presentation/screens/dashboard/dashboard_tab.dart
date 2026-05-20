// lib/presentation/screens/dashboard/dashboard_tab.dart
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

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/models/dashboard_stats_model.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/repositories/dashboard_stats_repository.dart';
import '../../../data/repositories/tank_repository.dart';

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
class _AlertModel {
  final String id;
  final String alertTitle;
  final String message;
  final String op;
  final String severity;
  final String tankId;
  final String tankName;
  final String tankCode;
  final String paramId;
  final String paramLabel;
  final String paramValue;
  final String capturedBy;
  final String capturedByName;
  final String imageUrl;
  final String constraintId;
  final String timestamp;
  final bool acknowledged;
  final bool isLive;

  _AlertModel({
    required this.id,
    required this.alertTitle,
    required this.message,
    required this.severity,
    required this.op,
    required this.tankId,
    required this.tankName,
    required this.tankCode,
    required this.paramId,
    required this.paramLabel,
    required this.paramValue,
    required this.capturedBy,
    required this.capturedByName,
    required this.imageUrl,
    required this.constraintId,
    required this.timestamp,
    required this.acknowledged,
    required this.isLive,
  });

  factory _AlertModel.fromMap(Map<dynamic, dynamic> m) => _AlertModel(
        id: m['id']?.toString() ?? '',
        alertTitle: m['alert_title']?.toString() ?? '',
        message: m['message']?.toString() ?? '',
        severity: m['severity']?.toString() ?? 'warning',
        op : m['op']?.toString() ?? 'null',
        tankId: m['tank_id']?.toString() ?? '',
        tankName: m['tank_name']?.toString() ?? '',
        tankCode: m['tank_code']?.toString() ?? '',
        paramId: m['param_id']?.toString() ?? '',
        paramLabel: m['param_label']?.toString() ?? '',
        paramValue: m['param_value']?.toString() ?? '',
        capturedBy: m['captured_by']?.toString() ?? '',
        capturedByName: m['captured_by_name']?.toString() ?? '',
        imageUrl: m['image_url']?.toString() ?? '',
        constraintId: m['constraint_id']?.toString() ?? '',
        timestamp: m['timestamp']?.toString() ?? '',
        acknowledged: m['acknowledged'] == true,
        isLive: m['live'] == true,
      );
}

// Completed task model (mirrors Firebase completed_tasks/ node)
class _CompletedTask {
  final String alertId;
  final String completedAt;
  final String completedBy;
  final _AlertModel alert;

  _CompletedTask({
    required this.alertId,
    required this.completedAt,
    required this.completedBy,
    required this.alert,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Severity helpers
// ─────────────────────────────────────────────────────────────────────────────
Color _sevColor(String s) {
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

IconData _sevIcon(String s) {
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

int _sevOrder(String s) {
  switch (s) {
    case 'critical':
      return 0;
    case 'warning':
      return 1;
    case 'info':
      return 2;
    default:
      return 3;
  }
}

String _fmtTs(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  } catch (_) {
    return iso ?? '—';
  }
}

String _fmtTsShort(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('HH:mm').format(dt);
  } catch (_) {
    return iso ?? '—';
  }
}

bool _isToday(String? iso) {
  if (iso == null || iso.isEmpty) return false;
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter enum
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

class _DashboardTabState extends State<DashboardTab> {
  List<TankModel> _tanks = [];
  StreamSubscription<List<TankModel>>? _tankSub;

  // Alerts
  List<_AlertModel> _allAlerts = [];
  List<_CompletedTask> _completed = [];
  StreamSubscription? _alertSub;
  StreamSubscription? _completedSub;
  _AlertFilter _filter = _AlertFilter.time;
  bool _filterAscending = false; // newest first for time

  final _db = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _tankSub = TankRepository().watchTanks().listen((tanks) {
      if (mounted) setState(() => _tanks = tanks);
    });
    _subscribeAlerts();
    _subscribeCompleted();
  }

  @override
  void dispose() {
    _tankSub?.cancel();
    _alertSub?.cancel();
    _completedSub?.cancel();
    super.dispose();
  }

  // ── Alert stream ───────────────────────────────────────────────────────────

  void _subscribeAlerts() {
    _alertSub?.cancel();
    _alertSub = _db.child('alerts').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) setState(() => _allAlerts = []);
        return;
      }
      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = raw.values
          .map((v) => _AlertModel.fromMap(Map<dynamic, dynamic>.from(v as Map)))
          .toList();
      if (mounted) setState(() => _allAlerts = list);
    });
  }

  void _subscribeCompleted() {
    _completedSub?.cancel();
    _completedSub = _db.child('completed_tasks').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) setState(() => _completed = []);
        return;
      }
      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = <_CompletedTask>[];
      for (final v in raw.values) {
        final m = Map<dynamic, dynamic>.from(v as Map);
        final alertMap = m['alert'];
        if (alertMap == null) continue;
        list.add(_CompletedTask(
          alertId: m['alert_id']?.toString() ?? '',
          completedAt: m['completed_at']?.toString() ?? '',
          completedBy: m['completed_by']?.toString() ?? '',
          alert:
              _AlertModel.fromMap(Map<dynamic, dynamic>.from(alertMap as Map)),
        ));
      }
      list.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      if (mounted) setState(() => _completed = list);
    });
  }

  // ── Expected-avg alert generator ──────────────────────────────────────────

  /// For every numeric/slider param that has expected_avg defined,
  /// if param_stats.avg > expected_avg → write a synthetic alert to Firebase
  /// (idempotent: uses a stable key so it won't duplicate).
  Future<void> _checkExpectedAvgAlerts(
      TankModel tank, DashboardStatsModel stats) async {
    for (final p in tank.inspectionProperties) {
      final label = p['label'] as String? ?? '';
      final type = p['type'] as String? ?? '';
      final expAvg = (p['expected_avg'] as num?)?.toDouble();
      if (expAvg == null) continue;
      if (type != 'number' && type != 'slider') continue;

      final stat = stats.paramStats[label];
      if (stat == null || stat.avg == null) continue;
      if (stat.avg! <= expAvg) continue;

      // avg exceeded → synthesise alert
      final alertId = 'avg_${tank.id}_${p['id']}';
      final existing = await _db.child('alerts/$alertId').get();
      if (existing.exists) {
        final ack = (existing.value as Map?)?['acknowledged'];
        if (ack == true) continue; // already handled
        continue; // already present and open
      }

      final alert = {
        'id': alertId,
        'alert_title': 'Avg Exceeded Expected',
        'message':
            '"$label" avg ${stat.avg!.toStringAsFixed(2)} exceeds expected avg $expAvg',
        'severity': 'critical',
        'tank_id': tank.id,
        'tank_name': tank.tankName,
        'tank_code': tank.tankCode,
        'param_id': p['id']?.toString() ?? '',
        'param_label': label,
        'param_value': stat.avg!.toStringAsFixed(2),
        'captured_by': '',
        'captured_by_name': 'Dashboard',
        'image_url': '',
        'constraint': '',
        'timestamp': DateTime.now().toIso8601String(),
        'acknowledged': false,
        'live': false,
      };
      await _db.child('alerts/$alertId').set(alert);
      debugPrint('[Dashboard] Expected-avg alert written: $alertId');
    }
  }

  // ── Complete task ──────────────────────────────────────────────────────────

  Future<void> _completeAlert(_AlertModel alert, String completedByName) async {
    final taskId = 'task_${alert.id}';
    final now = DateTime.now().toIso8601String();

    // Write to completed_tasks/
    await _db.child('completed_tasks/$taskId').set({
      'alert_id': alert.id,
      'completed_at': now,
      'completed_by': completedByName,
      'alert': {
        'id': alert.id,
        'alert_title': alert.alertTitle,
        'message': alert.message,
        'severity': alert.severity,
        'tank_id': alert.tankId,
        'tank_name': alert.tankName,
        'tank_code': alert.tankCode,
        'param_id': alert.paramId,
        'param_label': alert.paramLabel,
        'param_value': alert.paramValue,
        'captured_by': alert.capturedBy,
        'captured_by_name': alert.capturedByName,
        'image_url': alert.imageUrl,
        'constraint_id': alert.constraintId,
        'timestamp': alert.timestamp,
        'acknowledged': true,
        'live': alert.isLive,
      },
    });

    // Mark acknowledged in alerts/
    await _db.child('alerts/${alert.id}/acknowledged').set(true);
    debugPrint('[Dashboard] Task completed: ${alert.id}');
  }

  // ── Confirmation dialog ────────────────────────────────────────────────────

  Future<void> _showCompleteDialog(_AlertModel alert) async {
    bool checked = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: _kCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            Icon(_sevIcon(alert.severity),
                color: _sevColor(alert.severity), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Complete Task',
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.alertTitle,
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 4),
              Text(alert.message,
                  style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
              const SizedBox(height: 16),
              // Verification checkbox
              GestureDetector(
                onTap: () => setDlg(() => checked = !checked),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: checked ? _kSuccess.withOpacity(0.15) : _kSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: checked ? _kSuccess : _kBorderH,
                          width: checked ? 2 : 1),
                    ),
                    child: checked
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: _kSuccess)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'I have verified and checked this task has been resolved.',
                      style: GoogleFonts.dmSans(color: _kText, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.dmSans(color: _kSub)),
            ),
            GestureDetector(
              onTap: (!checked || saving)
                  ? null
                  : () async {
                      setDlg(() => saving = true);
                      try {
                        await _completeAlert(alert, 'Inspector');
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDlg(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('Failed: $e'),
                            backgroundColor: _kDanger,
                          ));
                        }
                      }
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: checked && !saving ? _kSuccess : _kSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.dmSans(
                            color: checked ? Colors.white : _kSubL,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sorted / filtered alerts ───────────────────────────────────────────────

  List<_AlertModel> get _todayOpenAlerts {
    final open = _allAlerts
        .where((a) => !a.acknowledged && _isToday(a.timestamp))
        .toList();

    switch (_filter) {
      case _AlertFilter.time:
        open.sort((a, b) => _filterAscending
            ? a.timestamp.compareTo(b.timestamp)
            : b.timestamp.compareTo(a.timestamp));
        break;
      case _AlertFilter.severity:
        open.sort(
            (a, b) => _sevOrder(a.severity).compareTo(_sevOrder(b.severity)));
        break;
    }
    return open;
  }

  List<_CompletedTask> get _completedToday =>
      _completed.where((t) => _isToday(t.completedAt)).toList();

  List<_CompletedTask> get _completedPrevious =>
      _completed.where((t) => !_isToday(t.completedAt)).toList();

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: _tanks.isEmpty
          ? _buildEmpty()
          : CustomScrollView(
              slivers: [
                // ── Header ────────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildHeader()),

                // ── Today's Tasks (alerts) ────────────────────────────────
                SliverToBoxAdapter(child: _buildAlertsPanel()),

                // ── Summary strip ─────────────────────────────────────────
                SliverToBoxAdapter(
                    child: _SummaryStrip(
                  tankCount: _tanks.length,
                  tanks: _tanks,
                  onStatsReady: _checkExpectedAvgAlerts,
                )),

                // ── Tank cards ────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _TankStatsCard(tank: _tanks[i]),
                      childCount: _tanks.length,
                    ),
                  ),
                ),

                // ── Completed Today ───────────────────────────────────────
                SliverToBoxAdapter(
                    child: _buildCompletedSection(
                  'TASKS COMPLETED TODAY',
                  _completedToday,
                  isToday: true,
                )),

                // ── Completed Previous ────────────────────────────────────
                SliverToBoxAdapter(
                    child: _buildCompletedSection(
                  'PREVIOUS DAYS',
                  _completedPrevious,
                  isToday: false,
                )),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
    );
  }

  // ── Header — unchanged ─────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Row(children: [
          Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                  color: _kCopper, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dashboard',
                  style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
              Text('Live aggregated readings per tank',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kSuccess.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kSuccess.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: _kSuccess, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('LIVE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: _kSuccess,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ]),
          ),
        ]),
      );

  // ── Alerts panel ───────────────────────────────────────────────────────────

  Widget _buildAlertsPanel() {
    final alerts = _todayOpenAlerts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header + filter bar
          Row(children: [
            Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                    color: _kDanger, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Text("TODAY'S TASKS",
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _kSub,
                      letterSpacing: 1.5)),
            ),
            if (alerts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kDanger.withOpacity(0.35)),
                ),
                child: Text('${alerts.length}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: _kDanger,
                        fontWeight: FontWeight.w700)),
              ),
          ]),

          const SizedBox(height: 10),

          // Filter chips
          Row(children: [
            _FilterChip(
              label: 'By Time',
              icon: Icons.access_time_rounded,
              selected: _filter == _AlertFilter.time,
              onTap: () => setState(() {
                if (_filter == _AlertFilter.time) {
                  _filterAscending = !_filterAscending;
                } else {
                  _filter = _AlertFilter.time;
                  _filterAscending = false;
                }
              }),
              trailing: _filter == _AlertFilter.time
                  ? (_filterAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : null,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'By Severity',
              icon: Icons.warning_amber_rounded,
              selected: _filter == _AlertFilter.severity,
              onTap: () => setState(() => _filter = _AlertFilter.severity),
            ),
          ]),

          const SizedBox(height: 10),

          // Alert cards or empty state
          if (alerts.isEmpty)
            _AlertsEmpty()
          else
            ...alerts.map((a) => _AlertCard(
                  alert: a,
                  onComplete: () => _showCompleteDialog(a),
                )),
        ],
      ),
    );
  }

  // ── Completed sections ─────────────────────────────────────────────────────

  Widget _buildCompletedSection(
    String title,
    List<_CompletedTask> tasks, {
    required bool isToday,
  }) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                    color: _kSuccess, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kSub,
                    letterSpacing: 1.5)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _kSuccess.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${tasks.length}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: _kSuccess,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          ...tasks.map((t) => _CompletedCard(task: t)),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.analytics_outlined, size: 52, color: _kSubL),
          const SizedBox(height: 14),
          Text('No tanks configured',
              style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w600, color: _kText)),
          const SizedBox(height: 6),
          Text('Add tanks in the Admin panel to see stats here',
              style: GoogleFonts.dmSans(fontSize: 13, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _AlertCard extends StatefulWidget {
  final _AlertModel alert;
  final VoidCallback onComplete;

  const _AlertCard({required this.alert, required this.onComplete});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final color = _sevColor(a.severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // ── Collapsed row ────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(14),
                    bottom:
                        _expanded ? Radius.zero : const Radius.circular(14)),
              ),
              child: Row(children: [
                Icon(_sevIcon(a.severity), color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(a.alertTitle,
                                style: GoogleFonts.dmSans(
                                    color: _kText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                          if (a.isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kDanger.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                    color: _kDanger.withOpacity(0.4)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                            color: _kDanger,
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 3),
                                    Text('LIVE',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 8,
                                            color: _kDanger,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8)),
                                  ]),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          '${a.tankName} · ${a.paramLabel}: ${a.paramValue}',
                          style: GoogleFonts.dmSans(color: _kSub, fontSize: 11),
                        ),
                      ]),
                ),
                const SizedBox(width: 6),
                Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SevBadge(a.severity),
                      const SizedBox(height: 4),
                      Text(_fmtTsShort(a.timestamp),
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, color: _kSubL)),
                    ]),
                const SizedBox(width: 6),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _kSubL,
                    size: 18),
              ]),
            ),
          ),

          // ── Expanded body ─────────────────────────────────────────
          if (_expanded) ...[
            Container(height: 1, color: color.withOpacity(0.2)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // All DB fields
                  _DetailRow('Message', a.message),
                  _DetailRow('Tank', '${a.tankName} (${a.tankCode})'),
                  _DetailRow('Parameter', a.paramLabel),
                  _DetailRow('Value', a.paramValue),
                  _DetailRow('Captured By', a.capturedByName),
                  _DetailRow('Timestamp', _fmtTs(a.timestamp)),
                  // _DetailRow('Constraint ', a.constraintId),
                  _DetailRow(
  'Constraint',
  '${a.paramLabel} ${a.op} ${a.paramValue} then ${a.message}',
),
                  if (a.imageUrl.isNotEmpty) _DetailRow('Image', a.imageUrl),
                  _DetailRow('Alert ID', a.id),

                  const SizedBox(height: 14),

                  // Complete button
                  GestureDetector(
                    onTap: widget.onComplete,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _kSuccess.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kSuccess.withOpacity(0.4)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                color: _kSuccess, size: 16),
                            const SizedBox(width: 7),
                            Text('Complete Task',
                                style: GoogleFonts.dmSans(
                                    color: _kSuccess,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPLETED TASK CARD
// ─────────────────────────────────────────────────────────────────────────────
class _CompletedCard extends StatefulWidget {
  final _CompletedTask task;
  const _CompletedCard({required this.task});

  @override
  State<_CompletedCard> createState() => _CompletedCardState();
}

class _CompletedCardState extends State<_CompletedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.task.alert;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSuccess.withOpacity(0.2)),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _kSuccess.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kSuccess.withOpacity(0.3)),
                ),
                child:
                    const Icon(Icons.check_rounded, size: 14, color: _kSuccess),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.alertTitle,
                          style: GoogleFonts.dmSans(
                              color: _kText,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                      Text(
                        '${a.tankName} · completed ${_fmtTs(widget.task.completedAt)}',
                        style: GoogleFonts.dmSans(color: _kSub, fontSize: 10),
                      ),
                    ]),
              ),
              _SevBadge(a.severity),
              const SizedBox(width: 6),
              Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _kSubL,
                  size: 16),
            ]),
          ),
        ),
        if (_expanded) ...[
          Container(height: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Message', a.message),
                _DetailRow('Tank', '${a.tankName} (${a.tankCode})'),
                _DetailRow('Parameter', a.paramLabel),
                _DetailRow('Value', a.paramValue),
                _DetailRow('Captured By', a.capturedByName),
                _DetailRow('Alert Time', _fmtTs(a.timestamp)),
                _DetailRow('Completed By', widget.task.completedBy),
                _DetailRow('Completed At', _fmtTs(widget.task.completedAt)),
                _DetailRow('Alert ID', a.id),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERTS EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _AlertsEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 28, color: _kSuccess.withOpacity(0.7)),
          const SizedBox(height: 8),
          Text('No alerts today',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 3),
          Text('All clear — no open tasks',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 11)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _kCopper.withOpacity(0.12) : _kSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? _kCopper.withOpacity(0.5) : _kBorder,
                width: selected ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: selected ? _kCopper : _kSub),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: selected ? _kCopper : _kSub,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing!, size: 11, color: selected ? _kCopper : _kSub),
            ],
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SEVERITY BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _SevBadge extends StatelessWidget {
  final String severity;
  const _SevBadge(this.severity);

  @override
  Widget build(BuildContext context) {
    final color = _sevColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(severity.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL ROW
// ─────────────────────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  bool get _isImage {
    final v = value.toLowerCase();
    return v.contains('.png') ||
        v.contains('.jpg') ||
        v.contains('.jpeg') ||
        v.contains('firebasestorage') ||
        v.contains('http');
  }

  String _beautifyConstraint(String raw) {
    if (raw.trim().isEmpty) return '—';

    final v = raw
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();

    return v
        .split(' ')
        .map((e) =>
            e.isEmpty ? '' : '${e[0].toUpperCase()}${e.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final displayValue =
        label.toLowerCase().contains('constraint')
            ? _beautifyConstraint(value)
            : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                color: _kSub,
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _isImage
                ? _ImageThumb(url: value)
                : Text(
                    displayValue,
                    style: GoogleFonts.dmSans(
                      color: _kText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}


class _ImageThumb extends StatelessWidget {
  final String url;

  const _ImageThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullscreenImageViewer(imageUrl: url),
          ),
        );
      },
      child: Hero(
        tag: url,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _kBorderH,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: _kSurface,
              child: const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kCopper,
                  ),
                ),
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: _kSurface,
              child: const Icon(
                Icons.broken_image_outlined,
                color: _kSub,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullscreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullscreenImageViewer({
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Hero(
                tag: imageUrl,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _SummaryStrip — unchanged except callback for expected-avg check
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryStrip extends StatefulWidget {
  final int tankCount;
  final List<TankModel> tanks;
  final Future<void> Function(TankModel, DashboardStatsModel) onStatsReady;

  const _SummaryStrip({
    required this.tankCount,
    required this.tanks,
    required this.onStatsReady,
  });

  @override
  State<_SummaryStrip> createState() => _SummaryStripState();
}

class _SummaryStripState extends State<_SummaryStrip> {
  int _totalReadings = 0;
  int _activeToday = 0;
  final _repo = DashboardStatsRepository();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _subscribeTanks();
  }

  @override
  void didUpdateWidget(_SummaryStrip old) {
    super.didUpdateWidget(old);
    if (old.tankCount != widget.tankCount) _subscribeTanks();
  }

  void _subscribeTanks() {
    _sub?.cancel();
    TankRepository().watchTanks().listen((tanks) async {
      int total = 0, today = 0;
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final t in tanks) {
        final stats = await _repo.getStats(t.id);
        total += stats.count;
        if (stats.lastCapturedAt != null &&
            stats.lastCapturedAt!.startsWith(todayStr)) {
          today++;
        }
        // Trigger expected-avg check
        widget.onStatsReady(t, stats);
      }
      if (mounted) {
        setState(() {
          _totalReadings = total;
          _activeToday = today;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        Expanded(
            child: _KpiChip(
                icon: Icons.storage_outlined,
                label: 'Tanks',
                value: '${widget.tankCount}',
                color: _kTeal)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiChip(
                icon: Icons.receipt_long_outlined,
                label: 'Total Readings',
                value: '$_totalReadings',
                color: _kCopper)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiChip(
                icon: Icons.today_outlined,
                label: 'Active Today',
                value: '$_activeToday',
                color: _kSuccess)),
      ]),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _KpiChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _kText)),
          Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _TankStatsCard — unchanged except NumChip value size now 14px + colored
// ─────────────────────────────────────────────────────────────────────────────
class _TankStatsCard extends StatefulWidget {
  final TankModel tank;
  const _TankStatsCard({required this.tank});

  @override
  State<_TankStatsCard> createState() => _TankStatsCardState();
}

class _TankStatsCardState extends State<_TankStatsCard> {
  DashboardStatsModel? _stats;
  bool _lastExpanded = false;
  StreamSubscription<DashboardStatsModel>? _sub;

  @override
  void initState() {
    super.initState();
    _sub =
        DashboardStatsRepository().watchStats(widget.tank.id).listen((stats) {
      if (mounted) setState(() => _stats = stats);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _fmtNum(double? v) {
    if (v == null) return '—';
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
  }

  String _fmtTs(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('dd MMM yyyy, HH:mm')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  String _fmtLastVal(dynamic v) {
    if (v == null) return '—';
    if (v is Map) {
      return '${v['left'] ?? ''} / ${v['right'] ?? ''}';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final tank = widget.tank;
    final props = List<Map<String, dynamic>>.from(tank.inspectionProperties);
    final hasData = stats != null && stats.count > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(tank, stats),
          if (stats == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kCopper)),
              ),
            )
          else if (!hasData)
            _buildNoData()
          else ...[
            _buildMetaRow(stats),
            const _Divider(),
            if (props.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('PARAMETER STATS'),
                    const SizedBox(height: 12),
                    ...props.map((p) => _buildParamBlock(p, stats)),
                  ],
                ),
              ),
            const _Divider(),
            _buildLastInspection(props, stats),
          ],
        ],
      ),
    );
  }

  Widget _buildCardHeader(TankModel tank, DashboardStatsModel? stats) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _kCopper.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: _kCopper.withOpacity(0.4)),
          ),
          child: Center(
            child: Text(
              tank.tankCode.isNotEmpty ? tank.tankCode[0].toUpperCase() : '?',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _kCopper),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tank.tankName,
                style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _kText)),
            const SizedBox(height: 2),
            Row(children: [
              Text(tank.tankCode,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: _kCopper,
                      fontWeight: FontWeight.w600)),
              if ((tank.location ?? '').isNotEmpty) ...[
                Text('  •  ', style: const TextStyle(color: _kBorderH)),
                const Icon(Icons.location_on_outlined, size: 11, color: _kSub),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(tank.location!,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
                ),
              ],
            ]),
          ]),
        ),
        if (stats != null && stats.count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kCopper.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kCopper.withOpacity(0.3)),
            ),
            child: Column(children: [
              Text('${stats.count}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kCopper)),
              Text('readings',
                  style: GoogleFonts.dmSans(fontSize: 9, color: _kCopperD)),
            ]),
          ),
      ]),
    );
  }

  Widget _buildNoData() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.hourglass_empty_rounded, size: 18, color: _kSubL),
          const SizedBox(width: 8),
          Text('No readings yet for this tank',
              style: GoogleFonts.dmSans(fontSize: 13, color: _kSub)),
        ]),
      );

  Widget _buildMetaRow(DashboardStatsModel stats) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
              child: _MetaPill(
                  icon: Icons.person_outline_rounded,
                  label: 'Captured By',
                  value: stats.lastCapturedBy ?? '—',
                  color: _kTeal)),
          const SizedBox(width: 10),
          Expanded(
              child: _MetaPill(
                  icon: Icons.schedule_outlined,
                  label: 'Last Inspection',
                  value: _fmtTs(stats.lastCapturedAt),
                  color: _kBlue)),
        ]),
      );

  Widget _buildParamBlock(Map<String, dynamic> p, DashboardStatsModel stats) {
    final label = (p['label'] as String?) ?? '';
    final type = (p['type'] as String?) ?? 'text';
    if (label.isEmpty) return const SizedBox.shrink();
    final stat = stats.paramStats[label];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
          ),
          _TypeBadge(type),
        ]),
        const SizedBox(height: 8),
        if (stat == null)
          Text('No data', style: GoogleFonts.dmSans(fontSize: 12, color: _kSub))
        else if (type == 'number' || type == 'slider')
          _NumericStatRow(
  stat: stat,
  fmtNum: _fmtNum,
  expectedAvg: (p['expected_avg'] as num?)?.toDouble(),
  expectedMin: (p['expected_min'] as num?)?.toDouble(),
expectedMax: (p['expected_max'] as num?)?.toDouble(),
  // expectedMin: (p['min'] as num?)?.toDouble(),
  // expectedMax: (p['max'] as num?)?.toDouble(),
)
        else if (type == 'dropdown')
          _DropdownStatBlock(stat: stat, totalCount: stats.count)
        else if (type == 'dual_text')
          _DualStatBlock(stat: stat, fmtNum: _fmtNum, prop: p)
        else
          _TextLastValue(value: _fmtLastVal(stat.lastValue)),
      ]),
    );
  }

  Widget _buildLastInspection(
      List<Map<String, dynamic>> props, DashboardStatsModel stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _lastExpanded = !_lastExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              const Icon(Icons.history_rounded, size: 16, color: _kCopper),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Last Inspection Values',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kText)),
              ),
              Icon(
                  _lastExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _kSub,
                  size: 20),
            ]),
          ),
        ),
        if (_lastExpanded)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: stats.lastReading.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No reading data',
                        style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
                  )
                : Column(
                    children: props.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final lbl = (p['label'] as String?) ?? '';
                      final val = stats.lastReading[lbl];
                      final isLast = i == props.length - 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: isLast
                              ? null
                              : const Border(
                                  bottom: BorderSide(color: _kBorder)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.28,
                              child: Text(lbl,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: _kSub,
                                      fontWeight: FontWeight.w500)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _fmtLastVal(val),
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    color: _kText,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NumericStatRow — value text medium (14px), colored same as chip
// ─────────────────────────────────────────────────────────────────────────────
class _NumericStatRow extends StatelessWidget {
  final ParamStat stat;
  final String Function(double?) fmtNum;

  final double? expectedAvg;
  final double? expectedMin;
  final double? expectedMax;

  const _NumericStatRow({
    required this.stat,
    required this.fmtNum,
    this.expectedAvg,
    this.expectedMin,
    this.expectedMax,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NumChip(
            label: 'AVG',
            value: fmtNum(stat.avg),
            expected: fmtNum(expectedAvg),
            color: _kCopper,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _NumChip(
            label: 'MIN',
            value: fmtNum(stat.min),
            expected: fmtNum(expectedMin),
            color: _kTeal,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _NumChip(
            label: 'MAX',
            value: fmtNum(stat.max),
            expected: fmtNum(expectedMax),
            color: _kWarn,
          ),
        ),
      ],
    );
  }
}
// _DualStatBlock — unchanged
class _DualStatBlock extends StatelessWidget {
  final ParamStat stat;
  final String Function(double?) fmtNum;
  final Map<String, dynamic> prop;

  const _DualStatBlock({
    required this.stat,
    required this.fmtNum,
    required this.prop,
  });

  @override
  Widget build(BuildContext context) {
    final leftLabel =
        (prop['left_label']?.toString().trim().isNotEmpty ?? false)
            ? prop['left_label'].toString()
            : 'Before';

    final rightLabel =
        (prop['right_label']?.toString().trim().isNotEmpty ?? false)
            ? prop['right_label'].toString()
            : 'After';

    final leftStats = stat.dualLeftStats;
    final rightStats = stat.dualRightStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow(
          title: leftLabel,
          stats: leftStats,

          // LEFT EXPECTED VALUES
          expectedAvg:
              (prop['left_expected_avg'] as num?)?.toDouble(),

          expectedMin:
              (prop['left_expected_min'] as num?)?.toDouble(),

          expectedMax:
              (prop['left_expected_max'] as num?)?.toDouble(),
        ),

        const SizedBox(height: 12),

        _buildRow(
          title: rightLabel,
          stats: rightStats,

          // RIGHT EXPECTED VALUES
          expectedAvg:
              (prop['right_expected_avg'] as num?)?.toDouble(),

          expectedMin:
              (prop['right_expected_min'] as num?)?.toDouble(),

          expectedMax:
              (prop['right_expected_max'] as num?)?.toDouble(),
        ),
      ],
    );
  }

  Widget _buildRow({
    required String title,
    required dynamic stats,
    double? expectedAvg,
    double? expectedMin,
    double? expectedMax,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            color: _kSub,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),

        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(
              child: _NumChip(
                label: 'AVG',
                value: fmtNum(stats?.avg),
                expected: fmtNum(expectedAvg),
                color: _kCopper,
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: _NumChip(
                label: 'MIN',
                value: fmtNum(stats?.min),
                expected: fmtNum(expectedMin),
                color: _kTeal,
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: _NumChip(
                label: 'MAX',
                value: fmtNum(stats?.max),
                expected: fmtNum(expectedMax),
                color: _kWarn,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _NumChip — value text now 14px (medium) and colored same as chip color
// ─────────────────────────────────────────────────────────────────────────────
class _NumChip extends StatelessWidget {
  final String label;
  final String value;

  /// optional expected value
  final String? expected;

  final Color color;

  const _NumChip({
    required this.label,
    required this.value,
    this.expected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasExpected =
        expected != null &&
        expected!.trim().isNotEmpty &&
        expected != '—';

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: Stack(
        children: [
          if (hasExpected)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  expected!,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: color.withOpacity(0.85),
                  ),
                ),
              ),
            ),

          Column(
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                value,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _DropdownStatBlock — unchanged
// ─────────────────────────────────────────────────────────────────────────────
class _DropdownStatBlock extends StatelessWidget {
  final ParamStat stat;
  final int totalCount;
  const _DropdownStatBlock({required this.stat, required this.totalCount});

  static const _palette = [
    _kTeal,
    _kCopper,
    _kSuccess,
    _kWarn,
    _kPurple,
    _kBlue,
    _kDanger,
  ];

  @override
  Widget build(BuildContext context) {
    final counts = stat.optionCounts;
    if (counts.isEmpty) {
      return Text('No selections yet',
          style: GoogleFonts.dmSans(fontSize: 12, color: _kSub));
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.asMap().entries.map((e) {
        final idx = e.key;
        final opt = e.value.key;
        final count = e.value.value;
        final pct = total > 0 ? (count / total) : 0.0;
        final color = _palette[idx % _palette.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(opt,
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: _kText,
                          fontWeight: FontWeight.w500)),
                ),
                Text('$count',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: _kSub,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(pct * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TextLastValue — unchanged
// ─────────────────────────────────────────────────────────────────────────────
class _TextLastValue extends StatelessWidget {
  final String value;
  const _TextLastValue({required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.format_quote_rounded, size: 14, color: _kSubL),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _kText, fontStyle: FontStyle.italic)),
          ),
          Text('last',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, color: _kSubL, letterSpacing: 0.5)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable helpers — unchanged
// ─────────────────────────────────────────────────────────────────────────────
class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MetaPill(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.dmSans(fontSize: 9, color: _kSub)),
              Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: _kText,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  static const _colors = <String, Color>{
    'number': _kTeal,
    'slider': Color(0xFF03DAC6),
    'dropdown': _kPurple,
    'text': _kSuccess,
    'multiline': Color(0xFF7986CB),
    'dual_text': _kWarn,
  };
  static const _labels = <String, String>{
    'number': 'NUM',
    'slider': 'SLIDE',
    'dropdown': 'DROP',
    'text': 'TEXT',
    'multiline': 'MULTI',
    'dual_text': 'DUAL',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? _kSub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5)),
      child: Text(
        _labels[type] ?? type.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: _kSubL,
          letterSpacing: 1.5));
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: _kBorder);
}
