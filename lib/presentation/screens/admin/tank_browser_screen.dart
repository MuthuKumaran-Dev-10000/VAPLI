// lib/presentation/screens/admin/tank_browser_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// FEATURES IN THIS VERSION:
//   ✅ All original features preserved (create/modify/duplicate/delete/QR)
//   ✅ Drag-to-reorder nodes within any folder (long-press to lift)
//   ✅ Drag-to-move into a folder — hover a folder node while dragging to
//      drop inside it (folder glows teal as target)
//   ✅ Drag out to parent — drag card to the breadcrumb bar to move to parent
//   ✅ Non-expanding leaf cards — full detail always visible (TankAdminCard style)
//   ✅ Premium folder cards — icon, gradient, child count, zone badge
//   ✅ Animated feedback: lift shadow, scale, drag ghost
//   ✅ Move-to dialog as fallback (long-press context menu → Move to…)
//   ✅ Same dark industrial palette throughout
//   ✅ All repository / model contracts unchanged
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
// PALETTE
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
const _kTealD = Color(0xFF0E8A8B);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSubL = Color(0xFF6B7280);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kPurple = Color(0xFFAB8FF0);

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASS — tracks drag state for a node
// ─────────────────────────────────────────────────────────────────────────────
class _DragPayload {
  final TankNode node;
  final int fromIndex;
  _DragPayload(this.node, this.fromIndex);
}

// ─────────────────────────────────────────────────────────────────────────────
// TankBrowserScreen
// ─────────────────────────────────────────────────────────────────────────────
class TankBrowserScreen extends StatefulWidget {
  const TankBrowserScreen({super.key});

  @override
  State<TankBrowserScreen> createState() => _TankBrowserScreenState();
}

class _TankBrowserScreenState extends State<TankBrowserScreen>
    with TickerProviderStateMixin {
  final _treeRepo = TankTreeRepository();
  final _tankRepo = TankRepository();

  final List<TankNode?> _pathStack = [null];
  List<TankNode> _nodes = [];
  Map<String, TankModel> _tankCache = {};
  StreamSubscription<List<TankNode>>? _sub;
  bool _loading = true;

  // Drag state
  String? _dragOverFolderId; // which folder is being hovered
  bool _dragOverBreadcrumb = false;

  // Folder child counts cache
  final Map<String, int> _childCountCache = {};

  // Animation controller for folder pulse when dragging over
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  TankNode? get _currentFolder => _pathStack.last;
  List<TankNode> get _breadcrumbs => _pathStack.whereType<TankNode>().toList();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.0, end: 1.0).animate(_pulseCtrl);
    _subscribeToCurrentFolder();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Subscribe ──────────────────────────────────────────────────────────────

  void _subscribeToCurrentFolder() {
    _sub?.cancel();
    setState(() => _loading = true);
    debugPrint(
        '[Browser] Subscribing to folder: ${_currentFolder?.id ?? 'ROOT'}');

    _sub = _treeRepo.watchChildren(_currentFolder?.id).listen(
      (nodes) async {
        final missing = nodes
            .where((n) =>
                n.isLeaf &&
                n.tankId != null &&
                !_tankCache.containsKey(n.tankId))
            .toList();
        for (final n in missing) {
          final t = await _tankRepo.getTankById(n.tankId!);
          if (t != null) _tankCache[n.tankId!] = t;
        }
        // Fetch child counts for folders
        for (final n in nodes.where((n) => n.isFolder)) {
          if (!_childCountCache.containsKey(n.id)) {
            _treeRepo.watchChildren(n.id).first.then((children) {
              if (mounted) {
                setState(() => _childCountCache[n.id] = children.length);
              }
            });
          }
        }
        if (mounted) {
          setState(() {
            _nodes = nodes;
            _loading = false;
          });
        }
      },
      onError: (e) {
        debugPrint('[Browser] Stream error: $e');
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openFolder(TankNode folder) {
    HapticFeedback.lightImpact();
    setState(() {
      _pathStack.add(folder);
      _nodes = [];
      _loading = true;
    });
    _subscribeToCurrentFolder();
  }

  void _navigateToBreadcrumb(int stackIndex) {
    if (stackIndex >= _pathStack.length - 1) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pathStack.removeRange(stackIndex + 1, _pathStack.length);
      _nodes = [];
      _loading = true;
    });
    _subscribeToCurrentFolder();
  }

  void _navigateUp() {
    if (_pathStack.length <= 1) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pathStack.removeLast();
      _nodes = [];
      _loading = true;
    });
    _subscribeToCurrentFolder();
  }

  // ── Drag handlers ──────────────────────────────────────────────────────────

  /// Called when a drag is dropped onto a folder node.
  Future<void> _moveNodeToFolder(
      _DragPayload payload, TankNode targetFolder) async {
    if (payload.node.id == targetFolder.id) return;
    HapticFeedback.mediumImpact();
    debugPrint(
        '[DnD] Moving ${payload.node.id} into folder ${targetFolder.id}');
    try {
      await _treeRepo.moveNode(
        nodeId: payload.node.id,
        newParentId: targetFolder.id,
      );
    } catch (e) {
      debugPrint('[DnD] Move failed: $e');
      if (mounted) _snack('Move failed: $e', _kDanger);
    }
  }

  /// Called when a drag is dropped on the breadcrumb (move to parent).
  Future<void> _moveNodeToParent(_DragPayload payload) async {
    HapticFeedback.mediumImpact();
    final newParentId =
        _pathStack.length >= 2 ? _pathStack[_pathStack.length - 2]?.id : null;
    debugPrint(
        '[DnD] Moving ${payload.node.id} to parent: ${newParentId ?? 'ROOT'}');
    try {
      await _treeRepo.moveNode(
        nodeId: payload.node.id,
        newParentId: newParentId,
      );
    } catch (e) {
      debugPrint('[DnD] Move to parent failed: $e');
      if (mounted) _snack('Move failed: $e', _kDanger);
    }
  }

  /// Reorder within current folder.
  Future<void> _reorderNodes(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      final item = _nodes.removeAt(oldIndex);
      _nodes.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    });
    // Persist order
    try {
      final ids = _nodes.map((n) => n.id).toList();
      await _treeRepo.reorderNodes(ids);
    } catch (e) {
      debugPrint('[Reorder] Failed: $e');
    }
  }

  // ── FAB / Create ───────────────────────────────────────────────────────────

  void _showFabMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: _kBorderH, borderRadius: BorderRadius.circular(2)),
              ),
              _SheetOption(
                icon: Icons.folder_open_outlined,
                label: 'New Group',
                sub: 'Organise tanks into folders',
                color: _kCopper,
                onTap: () {
                  Navigator.pop(context);
                  _showCreateFolderDialog();
                },
              ),
              const SizedBox(height: 12),
              _SheetOption(
                icon: Icons.water_outlined,
                label: 'New Tank',
                sub: 'Add a tank to this group',
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
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
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
  }

  Future<void> _deleteNode(TankNode node) async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Delete ${node.isFolder ? 'Group' : 'Tank'}',
      message: node.isFolder
          ? 'This will delete "${node.name}" and all its contents. Cannot be undone.'
          : 'Remove "${node.name}" from this group? The tank record is preserved.',
    );
    if (!confirmed) return;
    await _treeRepo.deleteNode(node.id);
  }

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
                _ErrorText(error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Show a move-to dialog (fallback for users who prefer tapping over dragging)
  Future<void> _showMoveDialog(TankNode node) async {
    // Collect folders at current level excluding this node
    final folders = _nodes.where((n) => n.isFolder && n.id != node.id).toList();

    if (folders.isEmpty && _pathStack.length <= 1) {
      _snack('No other folders to move to', _kWarn);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Move "${node.name}" to…',
            style:
                GoogleFonts.dmSans(color: _kText, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_pathStack.length > 1) ...[
                _MoveTarget(
                  label: '↑ Parent folder',
                  icon: Icons.drive_file_move_outline,
                  color: _kCopper,
                  onTap: () async {
                    Navigator.pop(context);
                    await _moveNodeToParent(_DragPayload(node, 0));
                  },
                ),
                const SizedBox(height: 8),
              ],
              ...folders.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MoveTarget(
                      label: f.name,
                      icon: Icons.folder_outlined,
                      color: _kTeal,
                      onTap: () async {
                        Navigator.pop(context);
                        await _moveNodeToFolder(_DragPayload(node, 0), f);
                      },
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: _kSub)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      floatingActionButton: _buildFab(),
      body: Column(
        children: [
          // ── Breadcrumb bar (also a drag target for moving to parent) ──────
          _buildBreadcrumb(),

          // ── Back row ──────────────────────────────────────────────────────
          if (_pathStack.length > 1)
            _BackRow(
              folderName: _currentFolder?.name ?? '',
              onBack: _navigateUp,
            ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _kCopper))
                : _nodes.isEmpty
                    ? _EmptyState(onAdd: _showFabMenu)
                    : _buildNodeList(),
          ),
        ],
      ),
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildFab() {
    return FloatingActionButton.extended(
      backgroundColor: _kCopper,
      onPressed: _showFabMenu,
      icon: const Icon(Icons.add_rounded, color: Colors.white),
      label: Text('Add',
          style: GoogleFonts.dmSans(
              color: Colors.white, fontWeight: FontWeight.w700)),
      elevation: 8,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
    );
  }

  // ── Breadcrumb bar ─────────────────────────────────────────────────────────

  Widget _buildBreadcrumb() {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragOverBreadcrumb = true);
        return _pathStack.length > 1;
      },
      onLeave: (_) => setState(() => _dragOverBreadcrumb = false),
      onAcceptWithDetails: (details) {
        setState(() => _dragOverBreadcrumb = false);
        _moveNodeToParent(details.data);
      },
      builder: (_, candidateData, __) {
        final isTarget = candidateData.isNotEmpty && _pathStack.length > 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: isTarget ? _kTeal.withOpacity(0.15) : _kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (isTarget)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.drive_file_move_outline,
                      size: 14, color: _kTeal),
                ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Root
                      GestureDetector(
                        onTap: _pathStack.length > 1
                            ? () => _navigateToBreadcrumb(0)
                            : null,
                        child: Row(children: [
                          Icon(Icons.storage_outlined,
                              size: 13,
                              color: _pathStack.length > 1 ? _kCopper : _kText),
                          const SizedBox(width: 4),
                          Text('Tanks',
                              style: GoogleFonts.dmSans(
                                  color:
                                      _pathStack.length > 1 ? _kCopper : _kText,
                                  fontSize: 12,
                                  fontWeight: _pathStack.length == 1
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                        ]),
                      ),
                      // Folder crumbs
                      ..._pathStack.skip(1).toList().asMap().entries.map((e) {
                        final idx = e.key + 1;
                        final node = e.value as TankNode;
                        final isLast = idx == _pathStack.length - 1;
                        return Row(children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 5),
                            child: Icon(Icons.chevron_right_rounded,
                                size: 14, color: _kSubL),
                          ),
                          GestureDetector(
                            onTap: isLast
                                ? null
                                : () => _navigateToBreadcrumb(idx),
                            child: Text(node.name,
                                style: GoogleFonts.dmSans(
                                    color: isLast ? _kText : _kCopper,
                                    fontSize: 12,
                                    fontWeight: isLast
                                        ? FontWeight.w700
                                        : FontWeight.w500)),
                          ),
                        ]);
                      }),
                    ],
                  ),
                ),
              ),
              if (isTarget)
                Text('Drop to move up',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _kTeal)),
            ],
          ),
        );
      },
    );
  }

  // ── Node list with drag-to-reorder ─────────────────────────────────────────

  Widget _buildNodeList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: _nodes.length,
      onReorder: _reorderNodes,
      proxyDecorator: (child, index, animation) {
        // Elevated ghost during drag
        return AnimatedBuilder(
          animation: animation,
          builder: (_, __) {
            final elevation = Tween(begin: 0.0, end: 16.0).evaluate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut)) *
                animation.value;
            return Material(
              elevation: elevation,
              color: Colors.transparent,
              shadowColor: _kCopper.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              child: Transform.scale(
                scale: 1.0 +
                    0.03 *
                        Tween(begin: 0.0, end: 1.0).evaluate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOut)),
                child: child,
              ),
            );
          },
        );
      },
      itemBuilder: (_, i) {
        final node = _nodes[i];
        return node.isFolder
            ? _buildFolderCard(node, i)
            : _buildLeafCard(node, i);
      },
    );
  }

  // ── Folder card ────────────────────────────────────────────────────────────

  Widget _buildFolderCard(TankNode node, int index) {
    final isDropTarget = _dragOverFolderId == node.id;
    final childCount = _childCountCache[node.id];

    return DragTarget<_DragPayload>(
      key: ValueKey('folder-${node.id}'),
      onWillAcceptWithDetails: (details) {
        if (details.data.node.id == node.id) return false;
        HapticFeedback.selectionClick();
        setState(() => _dragOverFolderId = node.id);
        return true;
      },
      onLeave: (_) {
        setState(() {
          if (_dragOverFolderId == node.id) _dragOverFolderId = null;
        });
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragOverFolderId = null);
        _moveNodeToFolder(details.data, node);
      },
      builder: (_, candidateData, __) {
        final glowing = candidateData.isNotEmpty;

        return LongPressDraggable<_DragPayload>(
          data: _DragPayload(node, index),
          hapticFeedbackOnStart: true,
          feedback: _DragGhost(
            child: _FolderCardContent(
              node: node,
              childCount: childCount,
              isDropTarget: false,
              isGhost: true,
              onOpen: () {},
              onRename: () {},
              onDelete: () {},
              onMove: () {},
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _FolderCardContent(
              node: node,
              childCount: childCount,
              isDropTarget: false,
              isGhost: false,
              onOpen: () {},
              onRename: () {},
              onDelete: () {},
              onMove: () {},
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: glowing
                  ? [
                      BoxShadow(
                          color: _kTeal.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2)
                    ]
                  : [],
            ),
            child: _FolderCardContent(
              node: node,
              childCount: childCount,
              isDropTarget: glowing,
              isGhost: false,
              onOpen: () => _openFolder(node),
              onRename: () => _showRenameDialog(node),
              onDelete: () => _deleteNode(node),
              onMove: () => _showMoveDialog(node),
            ),
          ),
        );
      },
    );
  }

  // ── Leaf card ──────────────────────────────────────────────────────────────

  Widget _buildLeafCard(TankNode node, int index) {
    final tank = _tankCache[node.tankId];

    return LongPressDraggable<_DragPayload>(
      key: ValueKey('leaf-${node.id}'),
      data: _DragPayload(node, index),
      hapticFeedbackOnStart: true,
      feedback: _DragGhost(
        child: _LeafCardContent(
          node: node,
          tank: tank,
          isGhost: true,
          treeRepo: _treeRepo,
          tankRepo: _tankRepo,
          currentParentId: _currentFolder?.id,
          onDelete: () {},
          onMove: () {},
          onTankCacheUpdate: (_, __) {},
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _LeafCardContent(
          node: node,
          tank: tank,
          isGhost: false,
          treeRepo: _treeRepo,
          tankRepo: _tankRepo,
          currentParentId: _currentFolder?.id,
          onDelete: () {},
          onMove: () {},
          onTankCacheUpdate: (_, __) {},
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _LeafCardContent(
          node: node,
          tank: tank,
          isGhost: false,
          treeRepo: _treeRepo,
          tankRepo: _tankRepo,
          currentParentId: _currentFolder?.id,
          onDelete: () => _deleteNode(node),
          onMove: () => _showMoveDialog(node),
          onTankCacheUpdate: (id, t) => setState(() => _tankCache[id] = t),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOLDER CARD CONTENT — the premium folder card
// ─────────────────────────────────────────────────────────────────────────────
class _FolderCardContent extends StatelessWidget {
  final TankNode node;
  final int? childCount;
  final bool isDropTarget;
  final bool isGhost;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  const _FolderCardContent({
    required this.node,
    required this.childCount,
    required this.isDropTarget,
    required this.isGhost,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDropTarget ? _kTeal : _kCopper;

    return GestureDetector(
      onTap: isGhost ? null : onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: isDropTarget ? _kTeal.withOpacity(0.08) : _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDropTarget ? _kTeal.withOpacity(0.6) : _kBorder,
              width: isDropTarget ? 1.5 : 1),
        ),
        child: Column(
          children: [
            // ── Header gradient strip ──────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDropTarget
                      ? [
                          _kTeal.withOpacity(0.18),
                          _kTeal.withOpacity(0.06),
                        ]
                      : [
                          _kCopper.withOpacity(0.14),
                          _kCard,
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  // Folder icon with animated drop cue
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: accentColor.withOpacity(0.3)),
                        ),
                      ),
                      Icon(
                        isDropTarget
                            ? Icons.folder_open_rounded
                            : Icons.folder_rounded,
                        color: accentColor,
                        size: 30,
                      ),
                      if (isDropTarget)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                                color: _kTeal, shape: BoxShape.circle),
                            child: const Icon(Icons.add_rounded,
                                size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: GoogleFonts.dmSans(
                              color: _kText,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Row(children: [
                          if ((node.zone ?? '').isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: accentColor.withOpacity(0.3)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.location_on_outlined,
                                        size: 9, color: accentColor),
                                    const SizedBox(width: 3),
                                    Text(node.zone!,
                                        style: GoogleFonts.dmSans(
                                            fontSize: 10,
                                            color: accentColor,
                                            fontWeight: FontWeight.w500)),
                                  ]),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (childCount != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _kBorder),
                              ),
                              child: Text(
                                '$childCount item${childCount == 1 ? '' : 's'}',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 9,
                                    color: _kSub,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ]),
                        if ((node.description ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(node.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.dmSans(
                                  fontSize: 11, color: _kSubL)),
                        ],
                      ],
                    ),
                  ),
                  // Chevron / drop cue
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDropTarget
                            ? Icons.download_rounded
                            : Icons.chevron_right_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.4),
                            shape: BoxShape.circle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Action bar ─────────────────────────────────────────────
            if (!isGhost)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: _kSurface.withOpacity(0.5),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: const Border(top: BorderSide(color: _kBorder)),
                ),
                child: Row(
                  children: [
                    // Drag hint
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.drag_indicator_rounded,
                          size: 14, color: _kSubL),
                      const SizedBox(width: 4),
                      Text('Hold to drag',
                          style:
                              GoogleFonts.dmSans(fontSize: 10, color: _kSubL)),
                    ]),
                    const Spacer(),
                    _MiniAction(
                        icon: Icons.drive_file_move_outline,
                        label: 'Move',
                        color: _kPurple,
                        onTap: onMove),
                    const SizedBox(width: 8),
                    _MiniAction(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        color: _kTeal,
                        onTap: onRename),
                    const SizedBox(width: 8),
                    _MiniAction(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        color: _kDanger,
                        onTap: onDelete),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEAF CARD CONTENT — always-visible tank card (TankAdminCard style)
// ─────────────────────────────────────────────────────────────────────────────
class _LeafCardContent extends StatefulWidget {
  final TankNode node;
  final TankModel? tank;
  final bool isGhost;
  final TankTreeRepository treeRepo;
  final TankRepository tankRepo;
  final String? currentParentId;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final void Function(String tankId, TankModel t) onTankCacheUpdate;

  const _LeafCardContent({
    required this.node,
    required this.tank,
    required this.isGhost,
    required this.treeRepo,
    required this.tankRepo,
    required this.currentParentId,
    required this.onDelete,
    required this.onMove,
    required this.onTankCacheUpdate,
  });

  @override
  State<_LeafCardContent> createState() => _LeafCardContentState();
}

class _LeafCardContentState extends State<_LeafCardContent> {
  final _shotCtrl = ScreenshotController();
  bool _busy = false;

  String get _qrData {
    final t = widget.tank;
    return [
      'path:${widget.node.path}',
      'tank_id:${widget.node.tankId ?? ''}',
      'tank_code:${t?.tankCode ?? ''}',
      'tank_name:${t?.tankName ?? widget.node.name}',
      'zone:${widget.node.zone ?? t?.location ?? ''}',
    ].join('|');
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _kDanger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _modify() => _run(() async {
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
          final updated =
              await widget.tankRepo.getTankById(widget.node.tankId!);
          if (updated != null) {
            widget.onTankCacheUpdate(widget.node.tankId!, updated);
          }
        }
      });

  Future<void> _duplicate() => _run(() async {
        if (widget.tank == null) return;
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
      });

  Future<void> _downloadQr() => _run(() async {
        final bytes = await _shotCtrl.captureFromWidget(
          Material(
              color: Colors.white,
              child: _PrintableQr(node: widget.node, tank: widget.tank)),
          pixelRatio: 3.0,
        );
        final qrUrl = await uploadBytesToCloudinary(bytes, folder: folderMain);
        if (widget.node.tankId != null) {
          await FirebaseDatabase.instance
              .ref('tanks/${widget.node.tankId}')
              .update({'qr_image_url': qrUrl});
        }
        final dir = await getApplicationDocumentsDirectory();
        final file = File(
            '${dir.path}/qr_${widget.tank?.tankCode ?? widget.node.id}.png');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)],
            text: 'QR for ${widget.node.name}');
      });

  @override
  Widget build(BuildContext context) {
    final t = widget.tank;
    final name = t?.tankName ?? widget.node.name;
    final code = t?.tankCode ?? '—';
    final zone = widget.node.zone ?? t?.location ?? '';
    final paramCount = t?.inspectionProperties.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: widget.isGhost
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
      ),
      child: Column(
        children: [
          // ── Main info row ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // QR thumbnail
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1), blurRadius: 4)
                    ],
                  ),
                  child: QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: GoogleFonts.dmSans(
                              color: _kText,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(code,
                          style: GoogleFonts.spaceGrotesk(
                              color: _kCopper,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      if (zone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.location_on_outlined,
                              size: 11, color: _kSub),
                          const SizedBox(width: 3),
                          Expanded(
                              child: Text(zone,
                                  style: GoogleFonts.dmSans(
                                      color: _kSub, fontSize: 11),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                      ],
                      if (paramCount > 0) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 5,
                          children: [
                            _ParamBadge(
                                label:
                                    '$paramCount param${paramCount == 1 ? '' : 's'}',
                                color: _kTeal),
                            if (t?.scaleSide != null)
                              _ParamBadge(
                                  label: 'Scale ${t!.scaleSide}',
                                  color: _kPurple),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Drag hint column
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.drag_indicator_rounded,
                        size: 20, color: _kSubL),
                    const SizedBox(height: 6),
                    if (_busy)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: _kCopper, strokeWidth: 2)),
                  ],
                ),
              ],
            ),
          ),
          // ── Action bar ───────────────────────────────────────────
          if (!widget.isGhost)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              decoration: const BoxDecoration(
                color: _kSurface,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              child: _busy
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: _kCopper, strokeWidth: 2)),
                    ))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _MiniAction(
                            icon: Icons.edit_outlined,
                            label: 'Modify',
                            color: _kTeal,
                            onTap: _modify),
                        _MiniAction(
                            icon: Icons.copy_outlined,
                            label: 'Duplicate',
                            color: _kWarn,
                            onTap: _duplicate),
                        _MiniAction(
                            icon: Icons.download_rounded,
                            label: 'QR',
                            color: _kCopper,
                            onTap: _downloadQr),
                        _MiniAction(
                            icon: Icons.drive_file_move_outline,
                            label: 'Move',
                            color: _kPurple,
                            onTap: widget.onMove),
                        _MiniAction(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete',
                            color: _kDanger,
                            onTap: widget.onDelete),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAG GHOST — material elevation wrapper shown while dragging
// ─────────────────────────────────────────────────────────────────────────────
class _DragGhost extends StatelessWidget {
  final Widget child;
  const _DragGhost({required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.9,
      child: Material(
        color: Colors.transparent,
        elevation: 20,
        shadowColor: _kCopper.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 32,
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRINTABLE QR
// ─────────────────────────────────────────────────────────────────────────────
class _PrintableQr extends StatelessWidget {
  final TankNode node;
  final TankModel? tank;
  const _PrintableQr({required this.node, required this.tank});

  String get _data {
    final t = tank;
    return [
      'path:${node.path}',
      'tank_id:${node.tankId ?? ''}',
      'tank_code:${t?.tankCode ?? ''}',
      'tank_name:${t?.tankName ?? node.name}',
      'zone:${node.zone ?? t?.location ?? ''}',
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final t = tank;
    final name = t?.tankName ?? node.name;
    final code = t?.tankCode ?? '';
    final zone = node.zone ?? t?.location ?? '';

    return Container(
      width: 280,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
              data: _data,
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
                      fontWeight: FontWeight.w900)),
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
                        fontWeight: FontWeight.bold)),
              ],
            ]),
          ),
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kSurface, _kCard],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.folder_open_outlined, size: 36, color: _kSubL),
          ),
          const SizedBox(height: 18),
          Text('Nothing here yet',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text('Tap + to add a group or a tank',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 13)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kCopperD, _kCopper],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: _kCopper.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
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
// BACK ROW
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
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.arrow_back_rounded, size: 15, color: _kCopper),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.folder_rounded, size: 15, color: _kCopper),
          const SizedBox(width: 6),
          Expanded(
            child: Text(folderName,
                style: GoogleFonts.dmSans(
                    color: _kText, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Text('Tap to go up',
              style: GoogleFonts.dmSans(fontSize: 11, color: _kSubL)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: _kSubL),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET OPTION (FAB menu)
// ─────────────────────────────────────────────────────────────────────────────
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _SheetOption(
      {required this.icon,
      required this.label,
      required this.sub,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
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
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: color),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MOVE TARGET (move-to dialog row)
// ─────────────────────────────────────────────────────────────────────────────
class _MoveTarget extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MoveTarget(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.arrow_forward_rounded, size: 14, color: color),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI ACTION BUTTON (action bar)
// ─────────────────────────────────────────────────────────────────────────────
class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 9, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PARAM BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _ParamBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _ParamBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
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

// ─────────────────────────────────────────────────────────────────────────────
// DARK FIELD
// ─────────────────────────────────────────────────────────────────────────────
class _DarkField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  const _DarkField(
      {required this.ctrl, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => TextField(
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

// ─────────────────────────────────────────────────────────────────────────────
// ERROR TEXT
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// CONFIRM DIALOG
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
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
