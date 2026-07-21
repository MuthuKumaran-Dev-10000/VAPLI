// lib/features/dashboard_folders/alerts_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'dashboard_alerts_display_model.dart';
import 'dashboard_alerts_sync_service.dart';
import 'folder_alerts_view.dart';

class AlertsScreen extends StatefulWidget {
  final Function(DashboardAlertDisplayItem)? onCompleteTaskRequested;
  final Widget Function(DashboardAlertDisplayItem)? alertCardBuilder;
  final Widget Function(DashboardAlertDisplayItem)? completedCardBuilder;

  const AlertsScreen({
    super.key,
    this.onCompleteTaskRequested,
    this.alertCardBuilder,
    this.completedCardBuilder,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // Database references
  static DatabaseReference _ref(String path) => DatabaseModeService.ref(path);

  // Subscriptions
  StreamSubscription? _alertsSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _settingsSub;

  // Settings flags
  bool _showActiveAlerts = true;
  bool _showCompletedAlerts = true;

  // State data
  List<DashboardAlertDisplayItem> _allActiveAlerts = [];
  List<DashboardAlertDisplayItem> _allCompletedAlerts = [];

  List<AlertFolderGroup> _activeFolders = [];
  List<AlertFolderGroup> _completedFolders = [];

  bool _syncingActive = true;
  bool _syncingCompleted = true;

  // Filter & Sort Selection
  String _activeFilter = 'All'; // Controller 1: 'All', 'Critical', 'Warning'
  String _sortBy = 'Severity'; // Controller 2: 'Severity', 'Time'
  bool _todayOnly = false; // Controller 3: TODAY ONLY toggle

  Future<void> _syncActiveFolders() async {
    if (!mounted) return;
    setState(() => _syncingActive = true);
    try {
      var filtered = List<DashboardAlertDisplayItem>.from(_allActiveAlerts);

      if (_activeFilter == 'Critical') {
        filtered = filtered.where((a) => a.severity.toLowerCase() == 'critical').toList();
      } else if (_activeFilter == 'Warning') {
        filtered = filtered.where((a) => a.severity.toLowerCase() == 'warning').toList();
      }

      if (_todayOnly) {
        final now = DateTime.now();
        filtered = filtered.where((a) {
          try {
            final dt = DateTime.parse(a.timestamp);
            return dt.year == now.year && dt.month == now.month && dt.day == now.day;
          } catch (_) {
            return false;
          }
        }).toList();
      }

      if (_sortBy == 'Time') {
        filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } else {
        filtered.sort((a, b) {
          final rankCompare = b.rankScore.compareTo(a.rankScore);
          if (rankCompare != 0) return rankCompare;
          return b.timestamp.compareTo(a.timestamp);
        });
      }

      final folders = await DashboardAlertsSyncService.syncAndGetFolders(filtered);
      if (mounted) {
        setState(() {
          _activeFolders = folders;
          _syncingActive = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _syncingActive = false);
    }
  }

  Future<void> _syncCompletedFolders() async {
    if (!mounted) return;
    setState(() => _syncingCompleted = true);
    try {
      var filtered = List<DashboardAlertDisplayItem>.from(_allCompletedAlerts);

      if (_todayOnly) {
        final now = DateTime.now();
        filtered = filtered.where((a) {
          try {
            final dt = DateTime.parse(a.timestamp);
            return dt.year == now.year && dt.month == now.month && dt.day == now.day;
          } catch (_) {
            return false;
          }
        }).toList();
      }

      final folders =
          await DashboardAlertsSyncService.syncAndGetCompletedFolders(filtered);
      if (mounted) {
        setState(() {
          _completedFolders = folders;
          _syncingCompleted = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _syncingCompleted = false);
    }
  }

  // Colors
  static const _kBg = Color(0xFF0D0E10);
  static const _kCard = Color(0xFF141618);
  static const _kBorder = Color(0xFF252830);
  static const _kCopper = Color(0xFFCB8C3E);
  static const _kSuccess = Color(0xFF22C55E);
  static const _kDanger = Color(0xFFEF4444);
  static const _kText = Color(0xFFF0EEE9);
  static const _kSub = Color(0xFF8A8F9C);

  @override
  void initState() {
    super.initState();
    _subscribeSettings();
    _subscribeActiveAlerts();
    _subscribeCompletedAlerts();
  }

  @override
  void dispose() {
    _alertsSub?.cancel();
    _completedSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }

  void _subscribeSettings() {
    _settingsSub = _ref('settings/dashboard_visibility').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return;
      try {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        if (mounted) {
          setState(() {
            _showCompletedAlerts = data['show_completed_alerts'] ?? true;
            _showActiveAlerts = data['show_active_alerts'] ?? true;
          });
        }
      } catch (_) {}
    });
  }

  void _subscribeActiveAlerts() {
    _alertsSub = _ref('alerts').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) {
          setState(() {
            _allActiveAlerts = [];
            _activeFolders = [];
            _syncingActive = false;
          });
        }
        return;
      }

      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final items = <DashboardAlertDisplayItem>[];
      for (final v in raw.values) {
        final m = Map<dynamic, dynamic>.from(v as Map);
        final status = m['status']?.toString() ?? 'active';
        final acknowledged = m['acknowledged'] == true;
        if (status == 'COMPLETED' || acknowledged) continue;

        items.add(DashboardAlertDisplayItem.fromMap(m));
      }

      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _allActiveAlerts = items;
        });
        _syncActiveFolders();
      }
    });
  }

  void _subscribeCompletedAlerts() {
    _completedSub = _ref('completed_tasks').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) {
          setState(() {
            _allCompletedAlerts = [];
            _completedFolders = [];
            _syncingCompleted = false;
          });
        }
        return;
      }

      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final items = <DashboardAlertDisplayItem>[];
      for (final v in raw.values) {
        final m = Map<dynamic, dynamic>.from(v as Map);
        final alertMap = m['alert'];
        if (alertMap == null) continue;
        final am = Map<dynamic, dynamic>.from(alertMap as Map);
        final completedAt = m['completed_at']?.toString() ?? am['timestamp']?.toString() ?? '';
        
        final rawUrls = m['completed_photo_urls'];
        final List<String> parsedUrls = (rawUrls is List)
            ? rawUrls.map((e) => e.toString()).toList()
            : (m['completed_photo_url']?.toString().isNotEmpty == true
                ? [m['completed_photo_url'].toString()]
                : []);

        items.add(DashboardAlertDisplayItem(
          id: am['id']?.toString() ?? '',
          alertTitle: am['alert_title']?.toString() ?? '',
          message: am['message']?.toString() ?? '',
          op: am['op']?.toString() ?? '',
          severity: am['severity']?.toString() ?? 'warning',
          tankId: am['tank_id']?.toString() ?? '',
          tankName: am['tank_name']?.toString() ?? '',
          tankCode: am['tank_code']?.toString() ?? '',
          paramId: am['param_id']?.toString() ?? '',
          paramLabel: am['param_label']?.toString() ?? '',
          paramValue: am['param_value']?.toString() ?? '',
          capturedBy: am['captured_by']?.toString() ?? '',
          capturedByName: m['completed_by']?.toString() ?? am['captured_by_name']?.toString() ?? '',
          imageUrl: am['image_url']?.toString() ?? '',
          constraintId: am['constraint_id']?.toString() ?? '',
          timestamp: completedAt,
          acknowledged: true,
          isLive: am['live'] == true,
          status: 'COMPLETED',
          readingId: am['reading_id']?.toString() ?? '',
          ifThen: am['if_then']?.toString() ?? '',
          completedDescription: m['completed_description']?.toString() ?? '',
          completedPhotoUrl: m['completed_photo_url']?.toString() ?? '',
          completedPhotoUrls: parsedUrls,
        ));
      }

      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _allCompletedAlerts = items;
        });
        _syncCompletedFolders();
      }
    });
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF141618),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kCopper, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ALERTS CENTER',
              style: GoogleFonts.spaceGrotesk(
                color: _kText,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '${_allActiveAlerts.length} Active · ${_allCompletedAlerts.length} Completed',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 3-Row Filter Controllers Bar
            _buildFilterControllersBar(),
            const SizedBox(height: 18),

            // Active Alerts Section
            if (_showActiveAlerts) ...[
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _kCopper,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "ACTIVE ALERTS FOLDERS",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _kSub,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_syncingActive && _activeFolders.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: _kCopper),
                  ),
                )
              else if (_activeFolders.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Center(
                    child: Text(
                      'No active alerts',
                      style: TextStyle(color: _kSub, fontSize: 13),
                    ),
                  ),
                )
              else
                FolderAlertsView(
                  folders: _activeFolders,
                  isCompleted: false,
                  alertCardBuilder: widget.alertCardBuilder ?? _defaultLeafAlertCard,
                ),
              const SizedBox(height: 24),
            ],

            // Completed Alerts Section
            if (_showCompletedAlerts) ...[
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _kSuccess,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "COMPLETED ALERTS FOLDERS",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _kSub,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_syncingCompleted && _completedFolders.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: _kSuccess),
                  ),
                )
              else if (_completedFolders.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: const Center(
                    child: Text(
                      'No completed alerts',
                      style: TextStyle(color: _kSub, fontSize: 13),
                    ),
                  ),
                )
              else
                FolderAlertsView(
                  folders: _completedFolders,
                  isCompleted: true,
                  alertCardBuilder: widget.completedCardBuilder ?? _defaultCompletedLeafCard,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, {Color? color}) {
    final selected = _activeFilter == label;
    final chipColor = color ?? _kCopper;

    return InkWell(
      onTap: () {
        setState(() {
          _activeFilter = label;
        });
        _syncActiveFolders();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? chipColor.withOpacity(0.18) : _kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? chipColor : _kBorder,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: selected ? _kText : _kSub,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? chipColor : const Color(0xFF252830),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.spaceGrotesk(
                  color: selected ? Colors.white : _kSub,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterControllersBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Category Filter (All, Critical, Warning)
        Row(
          children: [
            _buildFilterChip('All', _allActiveAlerts.length),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Critical',
              _allActiveAlerts.where((a) => a.severity.toLowerCase() == 'critical').length,
              color: _kDanger,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              'Warning',
              _allActiveAlerts.where((a) => a.severity.toLowerCase() == 'warning').length,
              color: const Color(0xFFF59E0B),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 2: Sort By (Severity Default vs Time) & Today Only Toggle
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'SORT:',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _kSub,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              _buildSortChip('Severity', Icons.workspace_premium_rounded),
              const SizedBox(width: 6),
              _buildSortChip('Time', Icons.access_time_rounded),

              const SizedBox(width: 14),
              Container(width: 1, height: 18, color: _kBorder),
              const SizedBox(width: 14),

              _buildTodayOnlyToggleChip(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSortChip(String label, IconData icon) {
    final selected = _sortBy == label;
    return InkWell(
      onTap: () {
        setState(() {
          _sortBy = label;
        });
        _syncActiveFolders();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _kCopper.withOpacity(0.18) : _kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _kCopper : _kBorder,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? _kCopper : _kSub, size: 13),
            const SizedBox(width: 4),
            Text(
              label == 'Severity' ? 'Severity (Default)' : label,
              style: GoogleFonts.dmSans(
                color: selected ? _kText : _kSub,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayOnlyToggleChip() {
    return InkWell(
      onTap: () {
        setState(() {
          _todayOnly = !_todayOnly;
        });
        _syncActiveFolders();
        _syncCompletedFolders();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _todayOnly ? _kCopper.withOpacity(0.2) : _kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _todayOnly ? _kCopper : _kBorder,
            width: _todayOnly ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TODAY ONLY',
              style: GoogleFonts.spaceGrotesk(
                color: _todayOnly ? _kCopper : _kSub,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
            if (_todayOnly) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: _kCopper,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _defaultLeafAlertCard(DashboardAlertDisplayItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                item.alertTitle,
                style: GoogleFonts.dmSans(
                  color: _kText,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.severity.toLowerCase() == 'critical'
                      ? _kDanger.withOpacity(0.2)
                      : _kCopper.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.severity.toUpperCase(),
                  style: TextStyle(
                    color: item.severity.toLowerCase() == 'critical' ? _kDanger : _kCopper,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.message,
            style: GoogleFonts.dmSans(color: _kSub, fontSize: 11),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => widget.onCompleteTaskRequested?.call(item),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _kSuccess.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kSuccess.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: _kSuccess, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Complete Task',
                    style: GoogleFonts.dmSans(
                      color: _kSuccess,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultCompletedLeafCard(DashboardAlertDisplayItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kSuccess.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: _kSuccess, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.alertTitle,
                  style: GoogleFonts.dmSans(
                    color: _kText,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.tankName} · ${item.paramLabel}',
            style: GoogleFonts.dmSans(color: _kSub, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
