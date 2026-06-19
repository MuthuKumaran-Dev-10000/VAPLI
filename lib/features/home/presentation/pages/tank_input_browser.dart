// lib/presentation/screens/readings/tank_input_browser.dart
// ══════════════════════════════════════════════════════════════════════════════
// TankInputBrowser — read-only tank folder browser for the Input tab.
//
// FEATURES:
//   ✅ Mirrors the admin TankBrowserScreen folder structure (same Firebase data)
//   ✅ No Navigator.push for folder drill-down — internal _pathStack, no back button
//   ✅ Search bar at top of every level — matches node names (min-search style)
//      Also searches inside sub-directories (shows path like Windows file explorer)
//   ✅ QR scan button next to search — scans QR, resolves tank, jumps to that
//      leaf's path (clears existing path stack and navigates there directly)
//   ✅ Clicking a FOLDER → drills into it (breadcrumb updates)
//   ✅ Clicking a LEAF → shows tank info card (tank name, code, location, path)
//      + "Take Reading" button → opens ReadingEntryScreen
//   ✅ No modify/delete/duplicate actions — display only
//   ✅ Path shown at top of leaf detail in Windows file-path style
//   ✅ Breadcrumb bar for navigation
//
// USAGE (in HomeScreen's TabBarView):
//   TankInputBrowser(currentUser: _currentUser)
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';
import 'package:lubrication_indicator/features/readings/presentation/pages/reading_entry_screen.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';
import 'package:lubrication_indicator/features/dashboard/data/repositories/dashboard_stats_repository.dart';
import 'package:lubrication_indicator/features/dashboard/data/models/dashboard_stats_model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/features/alerts/data/models/alert_model.dart';
import 'home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — matches the rest of the app (obsidian industrial)
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kBorder = Color(0xFF252830);
const _kBorderH = Color(0xFF38404F);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperL = Color(0xFFE8A84E);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSubL = Color(0xFF6B7280);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kInfo = Color(0xFF60A5FA);

Color _severityColor(String? s) {
  switch (s?.toLowerCase()) {
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
  switch (s?.toLowerCase()) {
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

// ─────────────────────────────────────────────────────────────────────────────
// TankInputBrowser
// ─────────────────────────────────────────────────────────────────────────────
class TankInputBrowser extends StatefulWidget {
  final UserModel? currentUser;
  final String rootTitleOverride;
  final String? rootFolderIdOverride;
  final VoidCallback? onRootTap;

  const TankInputBrowser({
    super.key,
    required this.currentUser,
    this.rootTitleOverride = 'Root',
    this.rootFolderIdOverride,
    this.onRootTap,
  });

  @override
  State<TankInputBrowser> createState() => _TankInputBrowserState();
}

class _TankInputBrowserState extends State<TankInputBrowser> {
  final _treeRepo = TankTreeRepository();
  final _tankRepo = TankRepository();

  // ── Navigation stack ───────────────────────────────────────────────────────
  // null = root. Each entry is a TankNode? representing current folder.
  final List<TankNode?> _pathStack = [null];
  TankNode? get _currentFolder => _pathStack.last;

  // ── Nodes for current level ────────────────────────────────────────────────
  List<TankNode> _nodes = [];
  Map<String, TankModel> _tankCache = {}; // tankId → TankModel
  StreamSubscription<List<TankNode>>? _sub;
  bool _loading = true;

  // ── Search ─────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _query = '';

  // ── Selected leaf (when user taps a tank) ─────────────────────────────────
  TankNode? _selectedLeaf = null;
  TankModel? _selectedTank = null;

  // ── Active alerts for selected tank ──────────────────────────────────────
  StreamSubscription? _activeAlertsSub;
  List<AlertModel> _activeAlerts = [];
  Map<String, String> _activeAlertImages = {};
  bool _hasShownInitialAlertPopup = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── All nodes cache (for deep search + QR path resolution) ────────────────
  List<TankNode> _allNodes = [];
  bool _allNodesFetched = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _query) {
        setState(() {
          _query = q;
          // Clear leaf selection when searching
          if (q.isNotEmpty) {
            _selectedLeaf = null;
            _selectedTank = null;
          }
        });
      }
    });
    _initClientRootAndLoad();
  }

  Future<void> _initClientRootAndLoad() async {
    if (widget.rootFolderIdOverride != null &&
        widget.rootFolderIdOverride!.trim().isNotEmpty) {
      final rootNode = await _treeRepo.fetchNode(widget.rootFolderIdOverride!);
      if (rootNode != null && mounted) {
        _pathStack
          ..clear()
          ..add(rootNode);
      }
    }
    _subscribeToCurrentFolder();
    _fetchAllNodes();
  }

  @override
  void dispose() {
    _activeAlertsSub?.cancel();
    _audioPlayer.dispose();
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Fetch all nodes once (for deep search + QR resolution) ────────────────
  Future<void> _fetchAllNodes() async {
    try {
      _allNodes = await _treeRepo.fetchAll();
      _allNodesFetched = true;
      if (mounted && _query.isNotEmpty) setState(() {});
      debugPrint('[InputBrowser] Fetched all nodes: ${_allNodes.length}');
    } catch (e) {
      debugPrint('[InputBrowser] fetchAll error: $e');
    }
  }

  // ── Subscribe ──────────────────────────────────────────────────────────────
  void _subscribeToCurrentFolder() {
    _sub?.cancel();
    setState(() {
      _loading = true;
      _selectedLeaf = null;
      _selectedTank = null;
    });
    debugPrint(
        '[InputBrowser] Subscribe: folder=${_currentFolder?.id ?? 'ROOT'}');

    _sub = _treeRepo.watchChildren(_currentFolder?.id).listen((nodes) async {
      // Load tank models for leaf nodes not yet cached
      final missing = nodes
          .where(
            (n) =>
                n.isLeaf &&
                n.tankId != null &&
                !_tankCache.containsKey(n.tankId),
          )
          .toList();
      for (final n in missing) {
        final t = await _tankRepo.getTankById(n.tankId!);
        if (t != null && mounted) _tankCache[n.tankId!] = t;
      }
      if (mounted) {
        setState(() {
          _nodes = nodes;
          _loading = false;
        });
      }
      _fetchAllNodes();
    }, onError: (e) {
      debugPrint('[InputBrowser] Stream error: $e');
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _refreshAll() async {
    await _fetchAllNodes();
    _subscribeToCurrentFolder();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _openFolder(TankNode folder) {
    debugPrint('[InputBrowser] Open folder: ${folder.name}');
    setState(() {
      _pathStack.add(folder);
      _nodes = [];
      _query = '';
      _searchCtrl.clear();
      _selectedLeaf = null;
      _selectedTank = null;
    });
    _subscribeToCurrentFolder();
  }

  void _navigateUp() {
    if (_pathStack.length <= 1) return;
    setState(() {
      _pathStack.removeLast();
      _nodes = [];
      _query = '';
      _searchCtrl.clear();
      _selectedLeaf = null;
      _selectedTank = null;
    });
    _subscribeToCurrentFolder();
  }

  void _navigateToBreadcrumb(int stackIdx) {
    if (stackIdx >= _pathStack.length - 1) return;
    _activeAlertsSub?.cancel();
    setState(() {
      _pathStack.removeRange(stackIdx + 1, _pathStack.length);
      _nodes = [];
      _query = '';
      _searchCtrl.clear();
      _selectedLeaf = null;
      _selectedTank = null;
      _activeAlerts = [];
      _activeAlertImages = {};
      _hasShownInitialAlertPopup = false;
    });
    _subscribeToCurrentFolder();
  }

  // ── Tap a leaf ─────────────────────────────────────────────────────────────
  Future<void> _selectLeaf(TankNode leaf) async {
    debugPrint(
        '[InputBrowser] Leaf selected: ${leaf.name} tankId=${leaf.tankId}');
    TankModel? tank = leaf.tankId != null ? _tankCache[leaf.tankId] : null;
    if (tank == null && leaf.tankId != null) {
      tank = await _tankRepo.getTankById(leaf.tankId!);
      if (tank != null && mounted) {
        _tankCache[leaf.tankId!] = tank;
      }
    }
    if (mounted) {
      setState(() {
        _selectedLeaf = leaf;
        _selectedTank = tank;
        _activeAlerts = [];
        _activeAlertImages = {};
        _hasShownInitialAlertPopup = false;
      });
      if (leaf.tankId != null) {
        _subscribeToActiveAlerts(leaf.tankId!);
      }
    }
  }

  void _clearLeafSelection() {
    _activeAlertsSub?.cancel();
    setState(() {
      _selectedLeaf = null;
      _selectedTank = null;
      _activeAlerts = [];
      _activeAlertImages = {};
      _hasShownInitialAlertPopup = false;
    });
  }

  DatabaseReference _ref(String path) => DatabaseModeService.ref(path);

  void _subscribeToActiveAlerts(String tankId) {
    _activeAlertsSub?.cancel();
    _activeAlertsSub = _ref('alerts')
        .orderByChild('tank_id')
        .equalTo(tankId)
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists || event.snapshot.value == null) {
        setState(() {
          _activeAlerts = [];
          _activeAlertImages = {};
        });
        return;
      }
      final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = <AlertModel>[];
      final images = <String, String>{};

      for (final e in raw.entries) {
        final alertId = e.key.toString();
        final alertMap = Map<dynamic, dynamic>.from(e.value as Map);
        final alert = AlertModel.fromMap(alertId, alertMap);

        if (!alert.resolved && alert.status.toLowerCase() != 'completed') {
          list.add(alert);
          final imgUrl = alertMap['image_url']?.toString() ?? '';
          if (imgUrl.isNotEmpty) {
            images[alertId] = imgUrl;
          }
        }
      }

      list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      setState(() {
        _activeAlerts = list;
        _activeAlertImages = images;
      });

      if (list.isNotEmpty && !_hasShownInitialAlertPopup) {
        _hasShownInitialAlertPopup = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _playWarningSoundAndVibration();
          _showActiveAlertsWarningDialog(list);
        });
      }
    });
  }

  Future<void> _playWarningSoundAndVibration() async {
    try {
      await _audioPlayer.stop();
      try {
        await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
      } catch (_) {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }

    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.heavyImpact();
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  Future<void> _showActiveAlertsWarningDialog(List<AlertModel> alerts) async {
    if (alerts.isEmpty || !mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: _kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kBorder, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _kDanger, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Active Asset Alerts!',
                  style: GoogleFonts.spaceGrotesk(
                    color: _kText,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 450.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This tank has ${alerts.length} active alert${alerts.length > 1 ? "s" : ""}. Please review the details below:',
                    style: GoogleFonts.dmSans(
                      color: _kSub,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...alerts.map((a) {
                    final isCritical = a.constraintSeverity.toLowerCase() == 'critical';
                    final isWarning = a.constraintSeverity.toLowerCase() == 'warning';
                    final sevColor = isCritical ? _kDanger : (isWarning ? _kWarn : _kInfo);
                    final timeStr = DateFormat('dd MMM yyyy, HH:mm').format(
                      DateTime.tryParse(a.capturedAt) ?? DateTime.now(),
                    );
                    final alertImgUrl = _activeAlertImages[a.id];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sevColor.withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: sevColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: sevColor.withOpacity(0.35)),
                                ),
                                child: Text(
                                  a.constraintSeverity.toUpperCase(),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: sevColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              Text(
                                timeStr,
                                style: GoogleFonts.spaceGrotesk(
                                  color: _kSub,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            a.alertTitle,
                            style: GoogleFonts.dmSans(
                              color: _kText,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.message,
                            style: GoogleFonts.dmSans(
                              color: _kSub,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: _kBorder, height: 1),
                          const SizedBox(height: 10),
                          _popupDetailRow('Tank Name', '${a.tankName} (${a.tankCode})'),
                          _popupDetailRow('Captured By', a.capturedByName),

                          // If there's an image, show thumbnail
                          if (alertImgUrl != null && alertImgUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Image Captured:',
                              style: GoogleFonts.dmSans(
                                color: _kSub,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      backgroundColor: Colors.black,
                                      appBar: AppBar(
                                        backgroundColor: Colors.black,
                                        iconTheme: const IconThemeData(color: Colors.white),
                                        title: Text(
                                          a.alertTitle,
                                          style: GoogleFonts.dmSans(color: Colors.white),
                                        ),
                                      ),
                                      body: Center(
                                        child: InteractiveViewer(
                                          minScale: 0.5,
                                          maxScale: 4.0,
                                          child: CachedNetworkImage(
                                            imageUrl: alertImgUrl,
                                            fit: BoxFit.contain,
                                            placeholder: (_, __) => const Center(
                                              child: CircularProgressIndicator(color: Colors.white),
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
                                  ),
                                );
                              },
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _kBorderH),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CachedNetworkImage(
                                  imageUrl: alertImgUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: _kSurface,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
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
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  Text(
                    'Do you want to continue recording reading for this tank?',
                    style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _kBorder,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop(false); // NO
                    },
                    child: Text(
                      'No, Skip Tank',
                      style: GoogleFonts.dmSans(
                        color: _kText,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _kCopper,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop(true); // YES
                    },
                    child: Text(
                      'Yes, Continue',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (proceed == false) {
      _navigateToNextTankOrClear();
    }
  }

  Widget _popupDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                color: _kSub,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                color: _kText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToNextTankOrClear() {
    if (_selectedLeaf == null) return;
    final siblingLeafs = _nodes.where((n) => n.isLeaf && n.tankId != null).toList();
    final currentIndex = siblingLeafs.indexWhere((n) => n.tankId == _selectedLeaf!.tankId);

    if (currentIndex >= 0 && currentIndex < siblingLeafs.length - 1) {
      final nextLeaf = siblingLeafs[currentIndex + 1];
      _selectLeaf(nextLeaf);
    } else {
      _clearLeafSelection(); // Last tank: go back to folder list
    }
  }

  // ── QR Scan ────────────────────────────────────────────────────────────────
  Future<void> _scanQr() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    debugPrint('[InputBrowser] QR scanned: $raw');
    await _resolveQr(raw);
  }

  Future<void> _resolveQr(String raw) async {
    // QR format: "path:X|tank_id:Y|tank_code:Z|tank_name:W|zone:V"
    // OR JSON: {"tank_id":"...", ...}
    String? tankId;

    // Try pipe-separated key:value format first
    if (raw.contains('|') && raw.contains(':')) {
      final parts = raw.split('|');
      for (final part in parts) {
        final idx = part.indexOf(':');
        if (idx == -1) continue;
        final key = part.substring(0, idx).trim();
        final val = part.substring(idx + 1).trim();
        if (key == 'tank_id' && val.isNotEmpty) {
          tankId = val;
          break;
        }
      }
    }

    // Fall back to JSON
    if (tankId == null) {
      try {
        final json = jsonDecode(raw) as Map;
        tankId = json['tank_id']?.toString() ?? json['id']?.toString();
      } catch (_) {}
    }

    if (tankId == null || tankId.isEmpty) {
      _snack('Could not find tank ID in QR code', _kDanger);
      return;
    }

    // Ensure all nodes are loaded
    if (!_allNodesFetched) {
      _snack('Loading tree… please try again in a moment', _kWarn);
      _fetchAllNodes();
      return;
    }

    // Find the leaf node for this tank
    final leafNode = _allNodes.firstWhere(
      (n) => n.isLeaf && n.tankId == tankId,
      orElse: () => TankNode(
        id: '',
        type: 'leaf',
        name: '',
        path: '',
        order: 0,
        createdAt: '',
        tankId: tankId,
      ),
    );

    if (leafNode.id.isEmpty) {
      // Tank exists but no tree node — just open it directly
      debugPrint('[InputBrowser] Leaf node not in tree for tankId=$tankId');
      final tank = await _tankRepo.getTankById(tankId);
      if (tank == null) {
        _snack('Tank not found', _kDanger);
        return;
      }
      if (!mounted) return;
      // Navigate to root and show synthetic leaf
      setState(() {
        _pathStack
          ..clear()
          ..add(null);
        _nodes = [];
        _query = '';
        _searchCtrl.clear();
      });
      _subscribeToCurrentFolder();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _selectedLeaf = TankNode(
          id: tankId!,
          type: 'leaf',
          name: tank.tankName,
          zone: (tank.location?.isNotEmpty ?? false) ? tank.location : '',
          path: tank.tankName,
          order: 0,
          createdAt: '',
          tankId: tankId,
        );
        _selectedTank = tank;
      });
      return;
    }

    // Build the ancestor path in the stack
    debugPrint('[InputBrowser] QR resolved to leaf: ${leafNode.path}');
    final ancestors = _buildAncestorChain(leafNode, _allNodes);

    // Load tank model
    final tank = await _tankRepo.getTankById(tankId);
    if (!mounted) return;

    // Navigate to leaf's parent folder
    setState(() {
      _pathStack
        ..clear()
        ..add(null) // root
        ..addAll(ancestors.map((n) => n as TankNode?));
      _nodes = [];
      _query = '';
      _searchCtrl.clear();
    });
    _subscribeToCurrentFolder();
    // After subscription loads, select the leaf
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (tank != null) _tankCache[tankId] = tank;
    setState(() {
      _selectedLeaf = leafNode;
      _selectedTank = tank;
    });
    _snack('Tank found: ${leafNode.name}', _kSuccess);
  }

  /// Returns ancestor folder nodes from root → parent of [leaf], in order.
  List<TankNode> _buildAncestorChain(TankNode leaf, List<TankNode> all) {
    final chain = <TankNode>[];
    String? currentParentId = leaf.parentId;
    while (currentParentId != null) {
      try {
        final parent = all.firstWhere((n) => n.id == currentParentId);
        chain.insert(0, parent);
        currentParentId = parent.parentId;
      } catch (_) {
        break;
      }
    }
    return chain;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Filtered nodes ─────────────────────────────────────────────────────────
  // When query is empty → show current folder's direct children
  // When query non-empty → deep search across ALL nodes, show with path
  List<_SearchResult> get _filteredResults {
    if (_query.isEmpty) return [];
    if (!_allNodesFetched) return [];
    final results = <_SearchResult>[];
    for (final n in _allNodes) {
      if (n.name.toLowerCase().contains(_query)) {
        results.add(_SearchResult(node: n, path: n.path));
      }
    }
    // Sort: folders first, then leaves; alphabetically within each
    results.sort((a, b) {
      if (a.node.isFolder && !b.node.isFolder) return -1;
      if (!a.node.isFolder && b.node.isFolder) return 1;
      return a.node.name.compareTo(b.node.name);
    });
    return results;
  }

  List<TankNode> get _currentLevelNodes => _nodes;

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isSearching = _query.isNotEmpty;
    final searchResult = _filteredResults;

    return Container(
      color: _kBg,
      child: Column(
        children: [
          // ── Breadcrumb bar ───────────────────────────────────────────────
          _BreadcrumbBar(
            pathStack: _pathStack,
            rootLabel: widget.rootTitleOverride,
            onRootTap: widget.onRootTap,
            onNavigate: _navigateToBreadcrumb,
          ),

          // ── Back row (when inside a folder and no leaf selected) ─────────
          if (_pathStack.length > 1 && _selectedLeaf == null)
            _BackRow(
              folderName: _currentFolder?.name ?? '',
              onBack: _navigateUp,
            ),

          // ── Search bar + QR row ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
                      cursorColor: _kCopper,
                      decoration: InputDecoration(
                        hintText: 'Search tanks or groups…',
                        hintStyle:
                            GoogleFonts.dmSans(color: _kSubL, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: _kSubL, size: 20),
                        suffixIcon: _query.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _query = '';
                                    _selectedLeaf = null;
                                    _selectedTank = null;
                                  });
                                },
                                child: const Icon(Icons.close_rounded,
                                    color: _kSubL, size: 18),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // QR scan button
                GestureDetector(
                  onTap: _scanQr,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kCopper,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _kCopper.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.qr_code_scanner_outlined,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),

          // ── Content area ─────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kCopper))
                : _selectedLeaf != null
                    // ── Leaf detail view ───────────────────────────────────
                    ? () {
                        final leafNodes = _nodes.where((n) => n.isLeaf && n.tankId != null).toList();
                        final siblingTanks = leafNodes
                            .map((n) => _tankCache[n.tankId])
                            .whereType<TankModel>()
                            .toList();
                        final currentTankIndex = _selectedTank != null
                            ? siblingTanks.indexWhere((t) => t.id == _selectedTank!.id)
                            : -1;
                        return _LeafDetail(
                          leaf: _selectedLeaf!,
                          tank: _selectedTank,
                          currentUser: widget.currentUser,
                          rootTitleOverride: widget.rootTitleOverride,
                          onBack: _clearLeafSelection,
                          siblingTanks: siblingTanks.isNotEmpty ? siblingTanks : null,
                          currentTankIndex: currentTankIndex >= 0 ? currentTankIndex : null,
                          activeAlerts: _activeAlerts,
                          onTakeReading: () async {
                            final now = DateTime.now();
                            final from = now.subtract(const Duration(minutes: 30));
                            String duplicateReason = '';
                            bool isDuplicate = false;
                            
                            try {
                              final stats = await DashboardStatsRepository().getStats(_selectedTank!.id);
                              if (stats.lastCapturedAt != null) {
                                final lastTime = DateTime.tryParse(stats.lastCapturedAt!);
                                if (lastTime != null) {
                                  final diff = now.difference(lastTime.toLocal()).inMinutes.abs();
                                  debugPrint('[DuplicateCheck Stats] lastCapturedAt: ${stats.lastCapturedAt}, diffMinutes: $diff');
                                  if (diff < 30) {
                                    isDuplicate = true;
                                  }
                                }
                              }
                            } catch (e) {
                              debugPrint('[DuplicateCheck Stats] Error: $e');
                            }

                            if (!isDuplicate) {
                              try {
                                final existing = await ReadingRepository().getReadingsInRange(
                                  tankId: _selectedTank!.id,
                                  from: from,
                                  to: now,
                                );
                                if (existing.isNotEmpty) {
                                  isDuplicate = true;
                                }
                              } catch (e) {
                                debugPrint('[DuplicateCheck Readings] Error: $e');
                              }
                            }

                            try {
                              if (isDuplicate && context.mounted) {
                                final proceed = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: _kCard,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    title: Text(
                                      'Duplicate Reading Alert',
                                      style: GoogleFonts.dmSans(
                                        color: _kText,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    content: Text(
                                      'Do you really want to take a reading for ${_selectedTank!.tankName}? A recent reading already exists.',
                                      style: GoogleFonts.dmSans(color: _kSub, fontSize: 14),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        child: Text(
                                          'NO',
                                          style: GoogleFonts.dmSans(
                                            color: _kSub,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _kCopper,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: () => Navigator.of(context).pop(true),
                                        child: Text(
                                          'YES',
                                          style: GoogleFonts.dmSans(
                                            color: _kBg,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (proceed != true) {
                                  _clearLeafSelection(); // 🔖 Navigate back to folder list on cancel
                                  return;
                                }

                                final reason = await showDialog<String>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) {
                                    final controller = TextEditingController();
                                    final formKey = GlobalKey<FormState>();
                                    return AlertDialog(
                                      backgroundColor: _kCard,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      title: Text(
                                        'Enter Duplicate Reason',
                                        style: GoogleFonts.dmSans(
                                          color: _kText,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      content: Form(
                                        key: formKey,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Please provide a mandatory reason for this duplicate reading.',
                                              style: GoogleFonts.dmSans(color: _kSub, fontSize: 13),
                                            ),
                                            const SizedBox(height: 12),
                                            TextFormField(
                                              controller: controller,
                                              maxLines: 2,
                                              style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
                                              decoration: InputDecoration(
                                                hintText: 'Reason...',
                                                hintStyle: GoogleFonts.dmSans(color: _kSub.withOpacity(0.5)),
                                                filled: true,
                                                fillColor: _kSurface,
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: const BorderSide(color: _kBorder),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: const BorderSide(color: _kCopper),
                                                ),
                                              ),
                                              validator: (value) {
                                                if (value == null || value.trim().isEmpty) {
                                                  return 'Reason cannot be empty';
                                                }
                                                return null;
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          child: Text(
                                            'Cancel',
                                            style: GoogleFonts.dmSans(
                                              color: _kSub,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _kCopper,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () {
                                            if (formKey.currentState?.validate() ?? false) {
                                              Navigator.of(context).pop(controller.text.trim());
                                            }
                                          },
                                          child: Text(
                                            'Submit',
                                            style: GoogleFonts.dmSans(
                                              color: _kBg,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (reason == null || reason.isEmpty) {
                                  _clearLeafSelection(); // 🔖 Navigate back to folder list on cancel
                                  return;
                                }
                                duplicateReason = reason;
                              }
                            } catch (e) {
                              debugPrint('[DuplicateCheck] Error: $e');
                            }

                            if (!context.mounted) return;

                            final result = await Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReadingEntryScreen(
                                  tank: _selectedTank!,
                                  currentUser: widget.currentUser!,
                                  siblingTanks: siblingTanks.isNotEmpty ? siblingTanks : null,
                                  currentTankIndex: currentTankIndex >= 0 ? currentTankIndex : null,
                                  duplicateReason: duplicateReason.isNotEmpty ? duplicateReason : null,
                                ),
                              ),
                            );
                            if (result != null && result['action'] == 'select_tank') {
                              final targetTankId = result['tank_id'];
                              final targetNode = _nodes.firstWhere(
                                (n) => n.isLeaf && n.tankId == targetTankId,
                                orElse: () => _selectedLeaf!,
                              );
                              _selectLeaf(targetNode);
                            } else if (result != null && result['action'] == 'clear_selection') {
                              _clearLeafSelection();
                            } else if (result != null && result['action'] == 'go_to_dashboard') {
                              _clearLeafSelection();
                              SwitchTabNotification(2).dispatch(context);
                            }
                          },
                        );
                      }()
                    : isSearching
                        // ── Search results ─────────────────────────────────
                        ? searchResult.isEmpty
                            ? _EmptySearch(query: _query)
                            : _SearchResultList(
                                results: searchResult,
                                tankCache: _tankCache,
                                tankRepo: _tankRepo,
                                onFolderTap: (node) async {
                                  // Navigate to that folder
                                  final ancestors =
                                      _buildAncestorChain(node, _allNodes);
                                  setState(() {
                                    _pathStack
                                      ..clear()
                                      ..add(null)
                                      ..addAll(
                                          ancestors.map((n) => n as TankNode?))
                                      ..add(node);
                                    _nodes = [];
                                    _query = '';
                                    _searchCtrl.clear();
                                    _selectedLeaf = null;
                                    _selectedTank = null;
                                  });
                                  _subscribeToCurrentFolder();
                                },
                                onLeafTap: (node) async {
                                  // Navigate to leaf's parent, then select leaf
                                  final ancestors =
                                      _buildAncestorChain(node, _allNodes);
                                  setState(() {
                                    _pathStack
                                      ..clear()
                                      ..add(null)
                                      ..addAll(
                                          ancestors.map((n) => n as TankNode?));
                                    _nodes = [];
                                    _query = '';
                                    _searchCtrl.clear();
                                  });
                                  _subscribeToCurrentFolder();
                                  await Future.delayed(
                                      const Duration(milliseconds: 400));
                                  await _selectLeaf(node);
                                },
                              )
                        // ── Normal folder contents ─────────────────────────
                        : _currentLevelNodes.isEmpty
                            ? _EmptyFolder(isRoot: _pathStack.length == 1)
                            : _NodeList(
                                nodes: _currentLevelNodes,
                                tankCache: _tankCache,
                                onFolderTap: _openFolder,
                                onLeafTap: _selectLeaf,
                              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NodeList — current folder contents
// ─────────────────────────────────────────────────────────────────────────────
class _NodeList extends StatelessWidget {
  final List<TankNode> nodes;
  final Map<String, TankModel> tankCache;
  final void Function(TankNode) onFolderTap;
  final void Function(TankNode) onLeafTap;

  const _NodeList({
    required this.nodes,
    required this.tankCache,
    required this.onFolderTap,
    required this.onLeafTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: nodes.length,
      itemBuilder: (_, i) {
        final n = nodes[i];
        return n.isFolder
            ? _FolderRow(node: n, onTap: () => onFolderTap(n))
            : _LeafRow(
                node: n,
                tank: n.tankId != null ? tankCache[n.tankId] : null,
                onTap: () => onLeafTap(n),
              );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchResult model
// ─────────────────────────────────────────────────────────────────────────────
class _SearchResult {
  final TankNode node;
  final String path;
  const _SearchResult({required this.node, required this.path});
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchResultList — deep search results with path shown
// ─────────────────────────────────────────────────────────────────────────────
class _SearchResultList extends StatefulWidget {
  final List<_SearchResult> results;
  final Map<String, TankModel> tankCache;
  final TankRepository tankRepo;
  final void Function(TankNode) onFolderTap;
  final void Function(TankNode) onLeafTap;

  const _SearchResultList({
    required this.results,
    required this.tankCache,
    required this.tankRepo,
    required this.onFolderTap,
    required this.onLeafTap,
  });

  @override
  State<_SearchResultList> createState() => _SearchResultListState();
}

class _SearchResultListState extends State<_SearchResultList> {
  final Map<String, TankModel> _localCache = {};

  @override
  void initState() {
    super.initState();
    _loadMissing();
  }

  Future<void> _loadMissing() async {
    for (final r in widget.results) {
      if (r.node.isLeaf && r.node.tankId != null) {
        final cached =
            widget.tankCache[r.node.tankId] ?? _localCache[r.node.tankId];
        if (cached == null) {
          final t = await widget.tankRepo.getTankById(r.node.tankId!);
          if (t != null && mounted) {
            setState(() => _localCache[r.node.tankId!] = t);
          }
        }
      }
    }
  }

  TankModel? _tank(String? id) =>
      id == null ? null : widget.tankCache[id] ?? _localCache[id];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: widget.results.length,
      itemBuilder: (_, i) {
        final r = widget.results[i];
        final n = r.node;
        return n.isFolder
            ? _FolderRow(
                node: n, path: r.path, onTap: () => widget.onFolderTap(n))
            : _LeafRow(
                node: n,
                tank: _tank(n.tankId),
                path: r.path,
                onTap: () => widget.onLeafTap(n));
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FolderRow — one row for a folder node
// ─────────────────────────────────────────────────────────────────────────────
class _FolderRow extends StatelessWidget {
  final TankNode node;
  final String? path; // shown in search results
  final VoidCallback onTap;

  const _FolderRow({required this.node, required this.onTap, this.path});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _kCopper.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kCopper.withOpacity(0.25)),
              ),
              child:
                  const Icon(Icons.folder_rounded, color: _kCopper, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.name,
                      style: GoogleFonts.dmSans(
                          color: _kText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  if (path != null) ...[
                    const SizedBox(height: 2),
                    _PathLabel(path: path!),
                  ] else if ((node.zone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 11, color: _kSub),
                      const SizedBox(width: 3),
                      Text(node.zone!,
                          style:
                              GoogleFonts.dmSans(color: _kSub, fontSize: 11)),
                    ]),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _kSubL, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LeafRow — one row for a tank leaf node
// ─────────────────────────────────────────────────────────────────────────────
class _LeafRow extends StatelessWidget {
  final TankNode node;
  final TankModel? tank;
  final String? path;
  final VoidCallback onTap;

  const _LeafRow(
      {required this.node, required this.tank, required this.onTap, this.path});

  // QR data same as admin browser
  String get _qrData {
    final payload = {
      'path': node.path,
      'tank_id': node.tankId ?? '',
      'tank_code': tank?.tankCode ?? '',
      'tank_name': tank?.tankName ?? node.name,
      'zone': node.zone ?? tank?.location ?? '',
    };
    return payload.entries.map((e) => '${e.key}:${e.value}').join('|');
  }

  @override
  Widget build(BuildContext context) {
    final name = tank?.tankName ?? node.name;
    final code = tank?.tankCode ?? '—';
    final zone = node.zone ?? tank?.location ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            // QR thumbnail
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: _qrData,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.dmSans(
                          color: _kText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(code,
                      style: GoogleFonts.spaceGrotesk(
                          color: _kCopper,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                  if (path != null) ...[
                    const SizedBox(height: 2),
                    _PathLabel(path: path!),
                  ] else if (zone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 10, color: _kSub),
                      const SizedBox(width: 3),
                      Text(zone,
                          style:
                              GoogleFonts.dmSans(color: _kSub, fontSize: 11)),
                    ]),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _kTeal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kTeal.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.edit_note_rounded, size: 13, color: _kTeal),
                const SizedBox(width: 4),
                Text('Record',
                    style: GoogleFonts.dmSans(
                        color: _kTeal,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LeafDetail — shown when a leaf is tapped: tank info + Take Reading button
// ─────────────────────────────────────────────────────────────────────────────
class _LeafDetail extends StatelessWidget {
  final TankNode leaf;
  final TankModel? tank;
  final UserModel? currentUser;
  final String rootTitleOverride;
  final VoidCallback onBack;
  final List<TankModel>? siblingTanks; // 🔖 Added for Reading Capture Flow Refactor
  final int? currentTankIndex; // 🔖 Added for Reading Capture Flow Refactor
  final VoidCallback onTakeReading; // 🔖 Added for Reading Capture Flow Refactor
  final List<AlertModel> activeAlerts;

  const _LeafDetail({
    required this.leaf,
    required this.tank,
    required this.currentUser,
    required this.rootTitleOverride,
    required this.onBack,
    this.siblingTanks, // 🔖 Added for Reading Capture Flow Refactor
    this.currentTankIndex, // 🔖 Added for Reading Capture Flow Refactor
    required this.onTakeReading, // 🔖 Added for Reading Capture Flow Refactor
    required this.activeAlerts,
  });

  String get _qrData {
    final payload = {
      'path': leaf.path,
      'tank_id': leaf.tankId ?? '',
      'tank_code': tank?.tankCode ?? '',
      'tank_name': tank?.tankName ?? leaf.name,
      'zone': leaf.zone ?? tank?.location ?? '',
    };
    return payload.entries.map((e) => '${e.key}:${e.value}').join('|');
  }

  @override
  Widget build(BuildContext context) {
    final name = tank?.tankName ?? leaf.name;
    final code = tank?.tankCode ?? '—';
    final zone = leaf.zone ?? tank?.location ?? '';
    final path = leaf.path;
    final paramCount = tank == null
        ? 0
        : tank?.inspectionProperties
            .where((p) => (p['type']?.toString() ?? '') != 'group')
            .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Back button ─────────────────────────────────────────────────
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_back_rounded, size: 15, color: _kCopper),
                const SizedBox(width: 6),
                Text('Back to folder',
                    style: GoogleFonts.dmSans(
                        color: _kSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Path (Windows-style) ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child: Row(children: [
              const Icon(Icons.folder_outlined, size: 13, color: _kSubL),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  path.isNotEmpty
                      ? path.replaceAll('/', ' › ')
                      : rootTitleOverride,
                  style: GoogleFonts.spaceGrotesk(
                      color: _kSubL, fontSize: 11, letterSpacing: 0.3),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Active alerts banner (rendered dynamically) ──────────────────
          if (activeAlerts.isNotEmpty) ...[
            (() {
              // Determine highest severity
              String highestSeverity = 'info';
              for (final alert in activeAlerts) {
                final sev = alert.constraintSeverity.toLowerCase();
                if (sev == 'critical') {
                  highestSeverity = 'critical';
                  break;
                } else if (sev == 'warning') {
                  highestSeverity = 'warning';
                }
              }
              final sevColor = _severityColor(highestSeverity);
              final sevIcon = _severityIcon(highestSeverity);

              return Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sevColor.withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: sevColor.withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(sevIcon, color: sevColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'ACTIVE ALERTS FOR THIS ASSET',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: sevColor,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...activeAlerts.map((alert) {
                      final timeStr = DateFormat('dd MMM yyyy, HH:mm').format(
                        DateTime.tryParse(alert.capturedAt) ?? DateTime.now(),
                      );
                      final individualColor = _severityColor(alert.constraintSeverity);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: individualColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          alert.alertTitle,
                                          style: GoogleFonts.dmSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _kText,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        timeStr,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 11,
                                          color: _kSub,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    alert.message,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: _kSub,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            }()),
            const SizedBox(height: 16),
          ],

          // ── Tank info card ────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                // Header strip
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(children: [
                    // QR
                    Container(
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: _qrData,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: GoogleFonts.dmSans(
                                  color: _kText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(code,
                              style: GoogleFonts.spaceGrotesk(
                                  color: _kCopper,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kSuccess.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kSuccess.withOpacity(0.3)),
                      ),
                      child: Text('ACTIVE',
                          style: GoogleFonts.spaceGrotesk(
                              color: _kSuccess,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                    ),
                  ]),
                ),

                // Info rows
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Client',
                          value: zone.isNotEmpty ? zone : '—'),
                      const SizedBox(height: 8),
                      _InfoRow(
                          icon: Icons.folder_outlined,
                          label: 'Path',
                          value: path.isNotEmpty
                              ? path.replaceAll('/', ' › ')
                              : rootTitleOverride),
                      if (tank != null) ...[
                        const SizedBox(height: 8),
                        _InfoRow(
                            icon: Icons.straighten_outlined,
                            label: 'Scale Max',
                            value: tank!.scaleMax.toInt().toString()),
                        if (paramCount! > 0) ...[
                          const SizedBox(height: 8),
                          _InfoRow(
                              icon: Icons.list_alt_outlined,
                              label: 'Parameters',
                              value: '$paramCount field'
                                  '${paramCount == 1 ? '' : 's'}'),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Take Reading button ───────────────────────────────────────
          if (tank == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kWarn.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kWarn.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: _kWarn, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Tank data could not be loaded. '
                      'Please check your connection.',
                      style: GoogleFonts.dmSans(color: _kWarn, fontSize: 13)),
                ),
              ]),
            ),
          ] else if (currentUser == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kDanger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kDanger.withOpacity(0.3)),
              ),
              child: Text('Please log in to record readings.',
                  style: GoogleFonts.dmSans(color: _kDanger, fontSize: 13)),
            ),
          ] else ...[
            _TakeReadingButton(
              onTap: onTakeReading,
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Ready to record reading for $name',
                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TakeReadingButton — copper glowing CTA
// ─────────────────────────────────────────────────────────────────────────────
class _TakeReadingButton extends StatelessWidget {
  final VoidCallback onTap;
  const _TakeReadingButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: _kCopper,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _kCopper.withOpacity(0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.edit_note_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text('Take Reading',
                style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PathLabel extends StatelessWidget {
  final String path;
  const _PathLabel({required this.path});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: const Icon(Icons.folder_outlined, size: 10, color: _kSubL),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              path.replaceAll('/', ' › '),
              style: GoogleFonts.spaceGrotesk(
                  color: _kSubL, fontSize: 10, letterSpacing: 0.2),
            ),
          ),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _kSubL),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(label,
                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.dmSans(
                    color: _kText, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

class _BreadcrumbBar extends StatelessWidget {
  final List<TankNode?> pathStack;
  final String rootLabel;
  final VoidCallback? onRootTap;
  final void Function(int) onNavigate;
  const _BreadcrumbBar({
    required this.pathStack,
    required this.rootLabel,
    this.onRootTap,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: onRootTap ??
                  (pathStack.length > 1 ? () => onNavigate(0) : null),
              child: Row(children: [
                Icon(Icons.storage_outlined,
                    size: 12, color: pathStack.length > 1 ? _kCopper : _kText),
                const SizedBox(width: 4),
                Text(rootLabel,
                    style: GoogleFonts.dmSans(
                        color: pathStack.length > 1 ? _kCopper : _kText,
                        fontSize: 12,
                        fontWeight: pathStack.length == 1
                            ? FontWeight.w700
                            : FontWeight.w500)),
              ]),
            ),
            ...pathStack.skip(1).toList().asMap().entries.map((e) {
              final idx = e.key + 1;
              final node = e.value as TankNode;
              final isLast = idx == pathStack.length - 1;
              return Row(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: const Icon(Icons.chevron_right_rounded,
                      size: 13, color: _kSubL),
                ),
                GestureDetector(
                  onTap: isLast ? null : () => onNavigate(idx),
                  child: Text(node.name,
                      style: GoogleFonts.dmSans(
                          color: isLast ? _kText : _kCopper,
                          fontSize: 12,
                          fontWeight:
                              isLast ? FontWeight.w700 : FontWeight.w500)),
                ),
              ]);
            }),
          ],
        ),
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  final String folderName;
  final VoidCallback onBack;
  const _BackRow({required this.folderName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onBack,
      child: Container(
        color: _kBg,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.arrow_back_rounded, size: 15, color: _kCopper),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.folder_rounded, size: 14, color: _kCopper),
          const SizedBox(width: 5),
          Expanded(
            child: Text(folderName,
                style: GoogleFonts.dmSans(
                    color: _kText, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          const Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: _kSubL),
        ]),
      ),
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  final bool isRoot;
  const _EmptyFolder({required this.isRoot});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(isRoot ? Icons.storage_outlined : Icons.folder_open_outlined,
              size: 40, color: _kSubL),
          const SizedBox(height: 12),
          Text(isRoot ? 'No tanks configured yet' : 'This folder is empty',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Ask your admin to add tanks',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
        ]),
      );
}

class _EmptySearch extends StatelessWidget {
  final String query;
  const _EmptySearch({required this.query});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded, size: 40, color: _kSubL),
          const SizedBox(height: 12),
          Text('No results for "$query"',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Try a different name or check spelling',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// QR Scan screen (reused from HomeScreen, kept local to avoid import cycles)
// ─────────────────────────────────────────────────────────────────────────────
class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();
  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('Scan Tank QR',
            style: GoogleFonts.dmSans(
                color: _kText, fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _scanned = true;
                Navigator.pop(context, barcode!.rawValue);
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _kCopper, width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _kCard.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Point camera at tank QR code',
                    style: GoogleFonts.dmSans(color: _kText, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
