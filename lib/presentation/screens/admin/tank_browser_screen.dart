// lib/presentation/screens/admin/tank_browser_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// FIXES IN THIS VERSION:
//   ✅ Root query fix — Firebase RTDB can't query equalTo(null).
//      Root nodes are fetched by getting ALL nodes and filtering parent_id==null
//      client-side. Child queries use orderByChild('parent_id').equalTo(id).
//   ✅ No Navigator.push for folder drill-down — uses an internal _pathStack
//      so there is NO back button / new route inside the tab. Breadcrumb bar
//      handles all navigation. Completely stays within the tab.
//   ✅ Stream re-subscribes correctly when folder changes (via _pathStack).
//   ✅ All create/modify/duplicate/delete features preserved exactly.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/presentation/screens/admin/admin_cloudinary.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/tank_node_model.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/repositories/tank_tree_repository.dart';
import '../../../data/repositories/tank_repository.dart';
import 'create_tank_screen_main.dart';
import 'create_tank_qr.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
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

// ─────────────────────────────────────────────────────────────────────────────
// TankBrowserScreen
// Self-contained — NO Navigator.push for folder drill-down.
// Uses an internal _pathStack (list of TankNode?) to track current folder.
// null in the stack = root level.
// ─────────────────────────────────────────────────────────────────────────────
class TankBrowserScreen extends StatefulWidget {
  const TankBrowserScreen({super.key});

  @override
  State<TankBrowserScreen> createState() => _TankBrowserScreenState();
}

class _TankBrowserScreenState extends State<TankBrowserScreen> {
  final _treeRepo = TankTreeRepository();
  final _tankRepo = TankRepository();

  // Navigation stack: each entry is a TankNode? (null = root).
  // We always display the LAST item.
  final List<TankNode?> _pathStack = [null]; // start at root

  List<TankNode> _nodes = [];
  Map<String, TankModel> _tankCache = {};
  StreamSubscription<List<TankNode>>? _sub;
  bool _loading = true;

  // ── Current folder ─────────────────────────────────────────────────────────
  TankNode? get _currentFolder => _pathStack.last;

  // Breadcrumb list = everything except the root null
  List<TankNode> get _breadcrumbs => _pathStack.whereType<TankNode>().toList();

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _subscribeToCurrentFolder();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Subscribe to current folder's children ─────────────────────────────────

  void _subscribeToCurrentFolder() {
    _sub?.cancel();
    setState(() => _loading = true);

    debugPrint('[Browser] Subscribing to folder: '
        '${_currentFolder?.id ?? 'ROOT'}');

    final stream = _treeRepo.watchChildren(_currentFolder?.id);

    _sub = stream.listen((nodes) async {
      debugPrint('[Browser] Got ${nodes.length} nodes for folder '
          '${_currentFolder?.id ?? 'ROOT'}');

      // Fetch TankModel for any unseen leaf nodes
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
        if (t != null) _tankCache[n.tankId!] = t;
      }

      if (mounted) {
        setState(() {
          _nodes = nodes;
          _loading = false;
        });
      }
    }, onError: (e) {
      debugPrint('[Browser] Stream error: $e');
      if (mounted) setState(() => _loading = false);
    });
  }

  // ── Navigation (no Navigator.push — all internal) ──────────────────────────

  void _openFolder(TankNode folder) {
    debugPrint('[Browser] Opening folder: ${folder.name} (${folder.id})');
    setState(() {
      _pathStack.add(folder);
      _nodes = [];
      _loading = true;
    });
    _subscribeToCurrentFolder();
  }

  void _navigateToBreadcrumb(int stackIndex) {
    // stackIndex 0 = root null; 1+ = folder nodes
    if (stackIndex >= _pathStack.length - 1) return; // already there
    debugPrint('[Browser] Breadcrumb nav to stack index $stackIndex');
    setState(() {
      _pathStack.removeRange(stackIndex + 1, _pathStack.length);
      _nodes = [];
      _loading = true;
    });
    _subscribeToCurrentFolder();
  }

  void _navigateUp() {
    if (_pathStack.length <= 1) return;
    debugPrint('[Browser] Navigate up from ${_currentFolder?.name}');
    setState(() {
      _pathStack.removeLast();
      _nodes = [];
      _loading = true;
    });
    _subscribeToCurrentFolder();
  }

  // ── CREATE FOLDER dialog ───────────────────────────────────────────────────

  Future<void> _showCreateFolderDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final zoneCtrl = TextEditingController();
    bool saving = false;
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => _StyledDialog(
          title: 'New Group',
          icon: Icons.folder_open_outlined,
          iconColor: _kCopper,
          onConfirm: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              setDlg(() => error = 'Name is required');
              return;
            }
            setDlg(() {
              saving = true;
              error = null;
            });
            try {
              await _treeRepo.createFolder(
                name: name,
                description:
                    descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                zone:
                    zoneCtrl.text.trim().isEmpty ? null : zoneCtrl.text.trim(),
                parentId: _currentFolder?.id,
              );
              debugPrint('[Browser] Folder created successfully');
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              debugPrint('[Browser] Folder create error: $e');
              setDlg(() {
                saving = false;
                error = e.toString();
              });
            }
          },
          confirmLabel: saving ? null : 'Create',
          saving: saving,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DarkField(
                  ctrl: nameCtrl,
                  label: 'Group Name *',
                  icon: Icons.folder_outlined),
              const SizedBox(height: 12),
              _DarkField(
                  ctrl: descCtrl,
                  label: 'Description (optional)',
                  icon: Icons.notes_outlined),
              const SizedBox(height: 12),
              _DarkField(
                  ctrl: zoneCtrl,
                  label: 'Zone / Location (optional)',
                  icon: Icons.location_on_outlined),
              if (error != null) ...[
                const SizedBox(height: 10),
                _ErrorText(error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── CREATE LEAF (Tank) ─────────────────────────────────────────────────────

  Future<void> _showCreateLeafFlow() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTankScreen()),
    );
    if (ok != true || !mounted) return;

    final allTanks = await _tankRepo.getAllTanks();
    if (allTanks.isEmpty) return;
    allTanks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final newTank = allTanks.first;

    await _treeRepo.createLeaf(
      name: newTank.tankName,
      tankId: newTank.id,
      zone: newTank.location,
      parentId: _currentFolder?.id,
    );
    debugPrint('[Browser] Leaf created for tank ${newTank.id}');
  }

  // ── FAB menu ───────────────────────────────────────────────────────────────

  void _showFabMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: _kBorderH, borderRadius: BorderRadius.circular(2)),
              ),
              _FabOption(
                icon: Icons.folder_open_outlined,
                label: 'New Group',
                sub: 'A folder to organise tanks',
                color: _kCopper,
                onTap: () {
                  Navigator.pop(context);
                  _showCreateFolderDialog();
                },
              ),
              const SizedBox(height: 10),
              _FabOption(
                icon: Icons.water_outlined,
                label: 'New Tank',
                sub: 'A leaf node linked to a tank',
                color: _kTeal,
                onTap: () {
                  Navigator.pop(context);
                  _showCreateLeafFlow();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── DELETE node ────────────────────────────────────────────────────────────

  Future<void> _deleteNode(TankNode node) async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Delete ${node.isFolder ? 'Group' : 'Tank'}',
      message: node.isFolder
          ? 'This will delete "${node.name}" and all its contents recursively. This cannot be undone.'
          : 'Remove "${node.name}" from this group? The underlying tank record is preserved.',
    );
    if (!confirmed) return;
    await _treeRepo.deleteNode(node.id);
    debugPrint('[Browser] Deleted node ${node.id}');
  }

  // ── RENAME folder dialog ───────────────────────────────────────────────────

  Future<void> _showRenameDialog(TankNode node) async {
    final nameCtrl = TextEditingController(text: node.name);
    final descCtrl = TextEditingController(text: node.description ?? '');
    final zoneCtrl = TextEditingController(text: node.zone ?? '');
    bool saving = false;
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => _StyledDialog(
          title: 'Modify Group',
          icon: Icons.edit_outlined,
          iconColor: _kTeal,
          onConfirm: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              setDlg(() => error = 'Name is required');
              return;
            }
            setDlg(() {
              saving = true;
              error = null;
            });
            try {
              await _treeRepo.updateFolder(
                id: node.id,
                name: name,
                description:
                    descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                zone:
                    zoneCtrl.text.trim().isEmpty ? null : zoneCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              setDlg(() {
                saving = false;
                error = e.toString();
              });
            }
          },
          confirmLabel: saving ? null : 'Save',
          saving: saving,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DarkField(
                  ctrl: nameCtrl,
                  label: 'Group Name *',
                  icon: Icons.folder_outlined),
              const SizedBox(height: 12),
              _DarkField(
                  ctrl: descCtrl,
                  label: 'Description',
                  icon: Icons.notes_outlined),
              const SizedBox(height: 12),
              _DarkField(
                  ctrl: zoneCtrl,
                  label: 'Zone / Location',
                  icon: Icons.location_on_outlined),
              if (error != null) ...[
                const SizedBox(height: 10),
                _ErrorText(error!)
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      // NO AppBar — this lives inside a tab. The tab bar provides the title.
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kCopper,
        onPressed: _showFabMenu,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
      ),
      body: Column(
        children: [
          // ── Breadcrumb bar ─────────────────────────────────────────────────
          _BreadcrumbBar(
            pathStack: _pathStack,
            onNavigate: _navigateToBreadcrumb,
          ),

          // ── Back row (when inside a folder) ───────────────────────────────
          if (_pathStack.length > 1)
            _BackRow(
              folderName: _currentFolder?.name ?? '',
              onBack: _navigateUp,
            ),

          // ── Content ────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kCopper))
                : _nodes.isEmpty
                    ? _EmptyState(onAdd: _showFabMenu)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _nodes.length,
                        itemBuilder: (_, i) {
                          final node = _nodes[i];
                          return node.isFolder
                              ? _FolderCard(
                                  node: node,
                                  onTap: () => _openFolder(node),
                                  onRename: () => _showRenameDialog(node),
                                  onDelete: () => _deleteNode(node),
                                )
                              : _LeafCard(
                                  node: node,
                                  tank: _tankCache[node.tankId],
                                  treeRepo: _treeRepo,
                                  tankRepo: _tankRepo,
                                  currentParentId: _currentFolder?.id,
                                  onDelete: () => _deleteNode(node),
                                  onTankCacheUpdate: (id, t) {
                                    setState(() => _tankCache[id] = t);
                                  },
                                );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Breadcrumb bar — purely presentational, calls onNavigate(stackIndex)
// ─────────────────────────────────────────────────────────────────────────────
class _BreadcrumbBar extends StatelessWidget {
  final List<TankNode?> pathStack;
  final void Function(int stackIndex) onNavigate;

  const _BreadcrumbBar({required this.pathStack, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Root crumb
            GestureDetector(
              onTap: pathStack.length > 1 ? () => onNavigate(0) : null,
              child: Row(children: [
                Icon(Icons.storage_outlined,
                    size: 13, color: pathStack.length > 1 ? _kCopper : _kText),
                const SizedBox(width: 4),
                Text('Tanks',
                    style: GoogleFonts.dmSans(
                        color: pathStack.length > 1 ? _kCopper : _kText,
                        fontSize: 12,
                        fontWeight: pathStack.length == 1
                            ? FontWeight.w700
                            : FontWeight.w500)),
              ]),
            ),
            // Folder crumbs
            ...pathStack.skip(1).toList().asMap().entries.map((e) {
              final idx = e.key + 1; // index in pathStack
              final node = e.value as TankNode;
              final isLast = idx == pathStack.length - 1;
              return Row(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: const Icon(Icons.chevron_right_rounded,
                      size: 14, color: _kSubL),
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

// ─────────────────────────────────────────────────────────────────────────────
// Back row — shown when inside a folder; single tap goes up one level
// ─────────────────────────────────────────────────────────────────────────────
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.arrow_back_rounded, size: 16, color: _kCopper),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.folder_rounded, size: 16, color: _kCopper),
          const SizedBox(width: 6),
          Expanded(
            child: Text(folderName,
                style: GoogleFonts.dmSans(
                    color: _kText, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: _kSubL),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOLDER CARD
// ─────────────────────────────────────────────────────────────────────────────
class _FolderCard extends StatelessWidget {
  final TankNode node;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FolderCard({
    required this.node,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Folder icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kCopper.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kCopper.withOpacity(0.25)),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  const Icon(Icons.folder_rounded, color: _kCopper, size: 28),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _kBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kCopper.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.storage_rounded,
                          size: 9, color: _kCopper),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(node.name,
                        style: GoogleFonts.dmSans(
                            color: _kText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    if ((node.zone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 11, color: _kSub),
                        const SizedBox(width: 3),
                        Text(node.zone!,
                            style:
                                GoogleFonts.dmSans(color: _kSub, fontSize: 11)),
                      ]),
                    ],
                    if ((node.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(node.description!,
                          style:
                              GoogleFonts.dmSans(color: _kSubL, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),

              // Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chevron_right_rounded,
                      color: _kSubL, size: 22),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _SmallBtn(
                        icon: Icons.edit_outlined,
                        color: _kTeal,
                        onTap: onRename),
                    const SizedBox(width: 6),
                    _SmallBtn(
                        icon: Icons.delete_outline_rounded,
                        color: _kDanger,
                        onTap: onDelete),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEAF CARD
// ─────────────────────────────────────────────────────────────────────────────
class _LeafCard extends StatefulWidget {
  final TankNode node;
  final TankModel? tank;
  final TankTreeRepository treeRepo;
  final TankRepository tankRepo;
  final String? currentParentId;
  final VoidCallback onDelete;
  final void Function(String tankId, TankModel t) onTankCacheUpdate;

  const _LeafCard({
    required this.node,
    required this.tank,
    required this.treeRepo,
    required this.tankRepo,
    required this.currentParentId,
    required this.onDelete,
    required this.onTankCacheUpdate,
  });

  @override
  State<_LeafCard> createState() => _LeafCardState();
}

class _LeafCardState extends State<_LeafCard> {
  final _shotCtrl = ScreenshotController();
  bool _busy = false;
  bool _expanded = false;

  String get _qrData {
    final t = widget.tank;
    final payload = {
      'path': widget.node.path,
      'tank_id': widget.node.tankId ?? '',
      'tank_code': t?.tankCode ?? '',
      'tank_name': t?.tankName ?? widget.node.name,
      'zone': widget.node.zone ?? t?.location ?? '',
    };
    return payload.entries.map((e) => '${e.key}:${e.value}').join('|');
  }

  // ── MODIFY ─────────────────────────────────────────────────────────────────
  Future<void> _modify() async {
    if (widget.tank == null) return;
    final t = widget.tank!;
    final tankMap = {
      'id': t.id,
      'tank_code': t.tankCode,
      'tank_name': t.tankName,
      'location': t.location ?? '',
      'scale_max': t.scaleMax,
      'scale_side': t.scaleSide,
      'qr_image_url': t.qrImageUrl,
      'qr_json': t.qrJson,
      'inspection_properties': t.inspectionProperties
          .map((p) => Map<String, dynamic>.from(p))
          .toList(),
    };
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => CreateTankScreen(existingTank: tankMap)),
    );
    if (ok == true && widget.node.tankId != null && mounted) {
      // Refresh cache
      final updated = await widget.tankRepo.getTankById(widget.node.tankId!);
      if (updated != null)
        widget.onTankCacheUpdate(widget.node.tankId!, updated);
    }
  }

  // ── DUPLICATE ──────────────────────────────────────────────────────────────
  Future<void> _duplicate() async {
    if (widget.tank == null || _busy) return;
    setState(() => _busy = true);
    try {
      final t = widget.tank!;
      final dupMap = {
        'tank_code': '${t.tankCode} (copy)',
        'tank_name': '${t.tankName} (copy)',
        'location': t.location ?? '',
        'scale_max': t.scaleMax,
        'scale_side': t.scaleSide,
        'inspection_properties': t.inspectionProperties
            .map((p) => Map<String, dynamic>.from(p))
            .toList(),
      };
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CreateTankScreen(existingTank: dupMap, isDuplicate: true),
        ),
      );
      if (ok == true && mounted) {
        final allTanks = await widget.tankRepo.getAllTanks();
        allTanks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final newTank = allTanks.first;
        await widget.treeRepo.createLeaf(
          name: newTank.tankName,
          tankId: newTank.id,
          zone: newTank.location,
          parentId: widget.currentParentId,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── DOWNLOAD QR ────────────────────────────────────────────────────────────
  Future<void> _downloadQr() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Future.delayed(const Duration(milliseconds: 80));
      final bytes = await _shotCtrl.captureFromWidget(
        Material(color: Colors.white, child: _buildPrintableQr()),
        pixelRatio: 3.0,
      );
      final qrUrl = await uploadBytesToCloudinary(bytes, folder: folderMain);
      if (widget.node.tankId != null) {
        await FirebaseDatabase.instance
            .ref('tanks/${widget.node.tankId}')
            .update({'qr_image_url': qrUrl});
      }
      final dir = await getApplicationDocumentsDirectory();
      final file =
          File('${dir.path}/qr_${widget.tank?.tankCode ?? widget.node.id}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)],
          text: 'QR for ${widget.node.name}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('QR export failed: $e'),
          backgroundColor: _kDanger.withOpacity(0.85),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildPrintableQr() {
    final t = widget.tank;
    final name = t?.tankName ?? widget.node.name;
    final code = t?.tankCode ?? '';
    final zone = widget.node.zone ?? t?.location ?? '';

    return Container(
      width: 280,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              padding: EdgeInsets.zero),
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Color(0xFFCCCCCC), width: 0.8))),
            child: Column(children: [
              Text(name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3)),
              if (code.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('ID: $code',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
              ],
              if (zone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Zone: $zone',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tank;
    final name = t?.tankName ?? widget.node.name;
    final code = t?.tankCode ?? '—';
    final zone = widget.node.zone ?? t?.location ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // ── Collapsed row ──────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // QR thumbnail
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8)),
                    child: QrImageView(
                        data: _qrData,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero),
                  ),
                  const SizedBox(width: 14),
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
                        if (zone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.location_on_outlined,
                                size: 10, color: _kSub),
                            const SizedBox(width: 3),
                            Text(zone,
                                style: GoogleFonts.dmSans(
                                    color: _kSub, fontSize: 11)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _kSubL,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded ───────────────────────────────────────────────────────
          if (_expanded) ...[
            Container(height: 1, color: _kBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                children: [
                  Center(child: _buildPrintableQr()),
                  const SizedBox(height: 18),
                  if (_busy)
                    const Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: _kCopper, strokeWidth: 2)))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionBtn(
                            icon: Icons.edit_outlined,
                            label: 'Modify',
                            color: _kTeal,
                            onTap: _modify),
                        _ActionBtn(
                            icon: Icons.copy_outlined,
                            label: 'Duplicate',
                            color: _kWarn,
                            onTap: _duplicate),
                        _ActionBtn(
                            icon: Icons.download_rounded,
                            label: 'Save QR',
                            color: _kCopper,
                            onTap: _downloadQr),
                        _ActionBtn(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete',
                            color: _kDanger,
                            onTap: widget.onDelete),
                      ],
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
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.folder_open_outlined, size: 32, color: _kSubL),
          ),
          const SizedBox(height: 16),
          Text('Nothing here yet',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text('Tap + to add a group or a tank',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: _kCopper,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: _kCopper.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text('Add Content',
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB MENU OPTION
// ─────────────────────────────────────────────────────────────────────────────
class _FabOption extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;

  const _FabOption({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.dmSans(
                        color: _kText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(sub,
                    style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
              ],
            )),
            Icon(Icons.arrow_forward_rounded, size: 16, color: color),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MICRO-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SmallBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: color.withOpacity(0.3))),
          child: Icon(icon, size: 15, color: color),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.35))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.dmSans(
                    color: color, fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// STYLED DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _StyledDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final String? confirmLabel;
  final bool saving;
  final VoidCallback onConfirm;

  const _StyledDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    required this.onConfirm,
    this.confirmLabel,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: const BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: GoogleFonts.dmSans(
                          color: _kText,
                          fontWeight: FontWeight.w700,
                          fontSize: 15))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, color: _kSub, size: 18),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child:
                      Text('Cancel', style: GoogleFonts.dmSans(color: _kSub)),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: saving ? null : onConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(9)),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(confirmLabel ?? 'OK',
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  const _DarkField(
      {required this.ctrl, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.dmSans(color: _kSub, fontSize: 13),
        prefixIcon: Icon(icon, color: _kSub, size: 18),
        filled: true,
        fillColor: _kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kCopper, width: 1.5)),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _kDanger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kDanger.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: _kDanger, size: 14),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.dmSans(color: _kDanger, fontSize: 12))),
        ]),
      );
}

// ── confirm dialog helper ──────────────────────────────────────────────────────
Future<bool> _confirmDialog(BuildContext context,
    {required String title, required String message}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title,
          style:
              GoogleFonts.dmSans(color: _kText, fontWeight: FontWeight.w700)),
      content:
          Text(message, style: GoogleFonts.dmSans(color: _kSub, fontSize: 14)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: _kSub))),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: GoogleFonts.dmSans(
                    color: _kDanger, fontWeight: FontWeight.bold))),
      ],
    ),
  );
  return result == true;
}
