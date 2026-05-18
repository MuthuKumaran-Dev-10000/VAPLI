// lib/presentation/screens/admin/tank_browser_screen.dart

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
const _kBg = Color(0xFF080909);
const _kSurface = Color(0xFF0F1012);
const _kCard = Color(0xFF151719);
const _kBorder = Color(0xFF222529);
const _kBorderH = Color(0xFF343840);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperL = Color(0xFFE8A84E);
const _kCopperD = Color(0xFF7A5020);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFEDEBE6);
const _kTextD = Color(0xFFB0AEA9);
const _kSub = Color(0xFF6B7080);
const _kSubL = Color(0xFF464C5C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kPurple = Color(0xFF9B7FE0);
const _kAmber = Color(0xFFD97706);

// ─────────────────────────────────────────────────────────────────────────────
// DRAG PAYLOAD
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
  String? _dragOverFolderId;
  bool _dragOverBreadcrumb = false;
  int? _reorderHoverIndex;
  bool _isDragging = false;

  final Map<String, int> _childCountCache = {};

  TankNode? get _currentFolder => _pathStack.last;

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

  // ── Subscribe ──────────────────────────────────────────────────────────────

  void _subscribeToCurrentFolder() {
    _sub?.cancel();
    setState(() => _loading = true);

    _sub = _treeRepo.watchChildren(_currentFolder?.id).listen(
      (nodes) async {
        for (final n in nodes) {
          if (n.isLeaf) {
            final tid = n.tankId;
            if (tid != null && !_tankCache.containsKey(tid)) {
              final t = await _tankRepo.getTankById(tid);
              if (t != null) _tankCache[tid] = t;
            }
          }
        }
        // for (final n in nodes.where((n) => n.isFolder)) {
        //   if (!_childCountCache.containsKey(n.id)) {
        //     _treeRepo.watchChildren(n.id).first.then((children) {
        //       if (mounted)
        //         setState(() => _childCountCache[n.id] = children.length);
        //     });
        //   }
        // }

        // for (final n in nodes.where((n) => n.isFolder)) {
        //   if (_childCountCache.containsKey(n.id)) continue;

        //   final children = await _treeRepo.watchChildren(n.id).first;

        //   _childCountCache[n.id] = children.length;
        // }

        for (final n in nodes.where((n) => n.isFolder)) {
          if (_childCountCache.containsKey(n.id)) continue;

          _childCountCache[n.id] = await _treeRepo.countChildren(n.id);
        }
        if (mounted) {
          setState(() {
            _nodes = nodes;
            _loading = false;
          });
        }
      },
      onError: (_) {
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

  // ── Drag → Move into folder ────────────────────────────────────────────────

  Future<void> _moveNodeToFolder(
      _DragPayload payload, TankNode targetFolder) async {
    if (payload.node.id == targetFolder.id) return;
    HapticFeedback.mediumImpact();
    try {
      await _treeRepo.moveNode(
          nodeId: payload.node.id, newParentId: targetFolder.id);
    } catch (e) {
      if (mounted) _snack('Move failed: $e', _kDanger);
    }
  }

  Future<void> _moveNodeToParent(_DragPayload payload) async {
    HapticFeedback.mediumImpact();
    final newParentId =
        _pathStack.length >= 2 ? _pathStack[_pathStack.length - 2]?.id : null;
    try {
      await _treeRepo.moveNode(
          nodeId: payload.node.id, newParentId: newParentId);
    } catch (e) {
      if (mounted) _snack('Move failed: $e', _kDanger);
    }
  }

  // ── Drag → Reorder ─────────────────────────────────────────────────────────

  Future<void> _reorderDrop(_DragPayload payload, int gapIndex) async {
    final fromIndex = payload.fromIndex;
    if (fromIndex == gapIndex || fromIndex == gapIndex - 1) return;
    HapticFeedback.selectionClick();

    setState(() {
      final item = _nodes.removeAt(fromIndex);
      final insertAt = gapIndex > fromIndex ? gapIndex - 1 : gapIndex;
      _nodes.insert(insertAt, item);
    });

    try {
      await _treeRepo.reorderNodes(_nodes.map((n) => n.id).toList());
    } catch (_) {}
  }

  // ── Folder deep-clone ──────────────────────────────────────────────────────

  Future<void> _deepCloneFolder({
    required TankNode sourceNode,
    required String? destParentId,
    required List<String> siblingNames,
  }) async {
    assert(sourceNode.isFolder);
    final newName = _uniqueName(sourceNode.name, siblingNames);
    final clonedFolder = await _treeRepo.createFolder(
      name: newName,
      description: sourceNode.description,
      zone: sourceNode.zone,
      parentId: destParentId,
    );
    final children = await _treeRepo.watchChildren(sourceNode.id).first;
    final childNames = children.map((c) => c.name).toList();
    for (final child in children) {
      if (child.isFolder) {
        await _deepCloneFolder(
          sourceNode: child,
          destParentId: clonedFolder.id,
          siblingNames: childNames,
        );
      } else {
        final tid = child.tankId;
        if (tid == null) continue;
        await _deepCloneLeaf(
          sourceNode: child,
          sourceTankId: tid,
          destParentId: clonedFolder.id,
          siblingNames: childNames,
        );
      }
    }
  }

  Future<void> _deepCloneLeaf({
    required TankNode sourceNode,
    required String sourceTankId,
    required String? destParentId,
    required List<String> siblingNames,
  }) async {
    TankModel? sourceTank = _tankCache[sourceTankId];
    sourceTank ??= await _tankRepo.getTankById(sourceTankId);
    if (sourceTank == null) return;
    final newName = _uniqueName(sourceTank.tankName, siblingNames);
    final newTankId = await _tankRepo.duplicateTank(sourceTank);
    await _treeRepo.createLeaf(
      name: newName,
      tankId: newTankId,
      zone: sourceNode.zone ?? sourceTank.location,
      parentId: destParentId,
    );
  }

  String _uniqueName(String base, List<String> existing) {
    final stripped = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    if (!existing.contains(stripped)) return stripped;
    int i = 1;
    while (existing.contains('$stripped ($i)')) i++;
    return '$stripped ($i)';
  }

  Future<void> _duplicateFolder(TankNode node) async {
    _snack('Cloning "${node.name}"…', _kCopper);
    try {
      final siblingNames = _nodes.map((n) => n.name).toList();
      await _deepCloneFolder(
        sourceNode: node,
        destParentId: _currentFolder?.id,
        siblingNames: siblingNames,
      );
      if (mounted) _snack('"${node.name}" cloned successfully', _kSuccess);
    } catch (e) {
      if (mounted) _snack('Clone failed: $e', _kDanger);
    }
  }

  // ── FAB ────────────────────────────────────────────────────────────────────
  // Uses a plain InkWell inside a Stack so no Flutter FAB theme issues.

  void _showFabMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      builder: (sheetCtx) => _FabSheet(
        onNewGroup: () {
          Navigator.pop(sheetCtx);
          // slight delay so sheet fully closes before dialog opens
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _showCreateFolderDialog();
          });
        },
        onNewTank: () {
          Navigator.pop(sheetCtx);
          Future.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _showCreateLeafFlow();
          });
        },
      ),
    );
  }

  // ── Create folder dialog ────────────────────────────────────────────────────

  Future<void> _showCreateFolderDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final zoneCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        bool saving = false;
        String? error;
        return StatefulBuilder(
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
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  zone: zoneCtrl.text.trim().isEmpty
                      ? null
                      : zoneCtrl.text.trim(),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                _ErrorText(error!)
              ],
            ]),
          ),
        );
      },
    );

    nameCtrl.dispose();
    descCtrl.dispose();
    zoneCtrl.dispose();
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
          ? 'Delete "${node.name}" and all its contents? Cannot be undone.'
          : 'Remove "${node.name}" from this group? The tank record is preserved.',
    );
    if (!confirmed) return;
    await _treeRepo.deleteNode(node.id);
  }

  Future<void> _showRenameDialog(TankNode node) async {
    final nameCtrl = TextEditingController(text: node.name);
    final descCtrl = TextEditingController(text: node.description ?? '');
    final zoneCtrl = TextEditingController(text: node.zone ?? '');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        bool saving = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDlg) => _StyledDialog(
            title: 'Edit Group',
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
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  zone: zoneCtrl.text.trim().isEmpty
                      ? null
                      : zoneCtrl.text.trim(),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            ]),
          ),
        );
      },
    );

    nameCtrl.dispose();
    descCtrl.dispose();
    zoneCtrl.dispose();
  }

  Future<void> _showMoveDialog(TankNode node) async {
    final folders = _nodes.where((n) => n.isFolder && n.id != node.id).toList();
    if (folders.isEmpty && _pathStack.length <= 1) {
      _snack('No other folders to move to', _kWarn);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Move to…',
            style: GoogleFonts.raleway(
                color: _kText, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.raleway(color: _kSub)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style:
              GoogleFonts.raleway(color: _kText, fontWeight: FontWeight.w600)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  // FAB is built manually inside a Stack so it is completely theme-independent.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── Main content column ──────────────────────────────────────
          Column(children: [
            _buildBreadcrumb(),
            if (_pathStack.length > 1)
              _BackRow(
                  folderName: _currentFolder?.name ?? '', onBack: _navigateUp),
            if (_isDragging) _buildDragHintBanner(),
            Expanded(
              child: _loading
                  ? const Center(child: _LoadingPulse())
                  : _nodes.isEmpty
                      ? _EmptyState(onAdd: _showFabMenu)
                      : _buildNodeList(),
            ),
          ]),

          // ── FAB (theme-independent, always visible) ──────────────────
          Positioned(
            right: 20,
            bottom: 28,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showFabMenu,
                borderRadius: BorderRadius.circular(28),
                child: Ink(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_kCopperL, _kCopper, _kCopperD],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    // boxShadow: [
                    //   // BoxShadow(
                    //   //   color: _kCopper.withOpacity(0.55),
                    //   //   blurRadius: 22,
                    //   //   offset: const Offset(0, 7),
                    //   // ),
                    //   // BoxShadow(
                    //   //   color: _kCopper.withOpacity(0.18),
                    //   //   blurRadius: 44,
                    //   //   spreadRadius: 6,
                    //   // ),
                    // ],
                  ),
                  child: const Center(
                    child:
                        Icon(Icons.add_rounded, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Drag hint banner ───────────────────────────────────────────────────────

  Widget _buildDragHintBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _kSurface,
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, size: 12, color: _kSub),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Drop ON a folder → move inside it   ·   Drop BETWEEN cards → reorder',
            style: GoogleFonts.raleway(fontSize: 10, color: _kSub),
          ),
        ),
      ]),
    );
  }

  // ── Breadcrumb ─────────────────────────────────────────────────────────────

  Widget _buildBreadcrumb() {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (d) {
        setState(() => _dragOverBreadcrumb = true);
        return _pathStack.length > 1;
      },
      onLeave: (_) => setState(() => _dragOverBreadcrumb = false),
      onAcceptWithDetails: (d) {
        setState(() => _dragOverBreadcrumb = false);
        _moveNodeToParent(d.data);
      },
      builder: (_, candidateData, __) {
        final isTarget = candidateData.isNotEmpty && _pathStack.length > 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isTarget ? _kTeal.withOpacity(0.1) : _kSurface,
            border: Border(
                bottom: BorderSide(
                    color: isTarget ? _kTeal.withOpacity(0.4) : _kBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            if (isTarget)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.drive_file_move_outline,
                    size: 13, color: _kTeal),
              ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  GestureDetector(
                    onTap: _pathStack.length > 1
                        ? () => _navigateToBreadcrumb(0)
                        : null,
                    child: Row(children: [
                      Icon(Icons.storage_outlined,
                          size: 12,
                          color: _pathStack.length > 1 ? _kCopper : _kText),
                      const SizedBox(width: 5),
                      Text('Root',
                          style: GoogleFonts.raleway(
                              color: _pathStack.length > 1 ? _kCopper : _kText,
                              fontSize: 12,
                              fontWeight: _pathStack.length == 1
                                  ? FontWeight.w800
                                  : FontWeight.w600)),
                    ]),
                  ),
                  ..._pathStack.skip(1).toList().asMap().entries.map((e) {
                    final stackIdx = e.key + 1;
                    final node = e.value as TankNode;
                    final isLast = stackIdx == _pathStack.length - 1;
                    return Row(children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 13, color: _kSubL),
                      ),
                      GestureDetector(
                        onTap: isLast
                            ? null
                            : () => _navigateToBreadcrumb(stackIdx),
                        child: Text(node.name,
                            style: GoogleFonts.raleway(
                                color: isLast ? _kText : _kCopper,
                                fontSize: 12,
                                fontWeight: isLast
                                    ? FontWeight.w800
                                    : FontWeight.w600)),
                      ),
                    ]);
                  }),
                ]),
              ),
            ),
            if (isTarget)
              Text('drop to move up',
                  style: GoogleFonts.raleway(fontSize: 10, color: _kTeal)),
          ]),
        );
      },
    );
  }

  // ── Node list ──────────────────────────────────────────────────────────────
  // Interleaved gaps for reorder + folder DragTargets for move-into.

  Widget _buildNodeList() {
    final count = _nodes.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
      // 2*count+1 items: gap, card, gap, card … gap
      itemCount: count * 2 + 1,
      itemBuilder: (_, listIdx) {
        if (listIdx.isEven) {
          return _buildReorderGap(listIdx ~/ 2);
        } else {
          final nodeIndex = listIdx ~/ 2;
          final node = _nodes[nodeIndex];
          return node.isFolder
              ? _buildFolderCard(node, nodeIndex)
              : _buildLeafCard(node, nodeIndex);
        }
      },
    );
  }

  // ── Reorder gap ────────────────────────────────────────────────────────────

  Widget _buildReorderGap(int gapIndex) {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (details) {
        setState(() {
          _reorderHoverIndex = gapIndex;
          _isDragging = true;
        });
        return true;
      },
      onLeave: (_) => setState(() {
        if (_reorderHoverIndex == gapIndex) _reorderHoverIndex = null;
      }),
      onAcceptWithDetails: (details) {
        setState(() {
          _reorderHoverIndex = null;
          _isDragging = false;
        });
        _reorderDrop(details.data, gapIndex);
      },
      builder: (_, candidateData, __) {
        final active = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: active ? 52 : 8,
          margin: EdgeInsets.symmetric(vertical: active ? 4 : 0),
          decoration: active
              ? BoxDecoration(
                  color: _kCopper.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: _kCopper.withOpacity(0.50), width: 1.5),
                )
              : null,
          child: active
              ? Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.swap_vert_rounded,
                        size: 14, color: _kCopper),
                    const SizedBox(width: 6),
                    Text('Drop here to reorder',
                        style: GoogleFonts.raleway(
                            fontSize: 11,
                            color: _kCopper,
                            fontWeight: FontWeight.w700)),
                  ]),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  // ── Folder card ────────────────────────────────────────────────────────────

  Widget _buildFolderCard(TankNode node, int index) {
    return DragTarget<_DragPayload>(
      key: ValueKey('folder-drop-${node.id}'),
      onWillAcceptWithDetails: (d) {
        if (d.data.node.id == node.id) return false;
        HapticFeedback.selectionClick();
        setState(() {
          _dragOverFolderId = node.id;
          _reorderHoverIndex = null; // stop gap from also lighting up
          _isDragging = true;
        });
        return true;
      },
      onLeave: (_) => setState(() {
        if (_dragOverFolderId == node.id) _dragOverFolderId = null;
      }),
      onAcceptWithDetails: (d) {
        setState(() {
          _dragOverFolderId = null;
          _isDragging = false;
        });
        _moveNodeToFolder(d.data, node);
      },
      builder: (_, candidateData, __) {
        final isDropTarget = candidateData.isNotEmpty;
        final childCount = _childCountCache[node.id];

        return LongPressDraggable<_DragPayload>(
          data: _DragPayload(node, index),
          hapticFeedbackOnStart: true,
          onDragStarted: () => setState(() => _isDragging = true),
          onDragEnd: (_) => setState(() {
            _isDragging = false;
            _dragOverFolderId = null;
          }),
          onDraggableCanceled: (_, __) => setState(() {
            _isDragging = false;
            _dragOverFolderId = null;
          }),
          feedback: _DragGhost(
            width: MediaQuery.of(context).size.width - 32,
            child: _FolderCardContent(
              node: node,
              childCount: childCount,
              isDropTarget: false,
              isGhost: true,
              onOpen: () {},
              onRename: () {},
              onDelete: () {},
              onMove: () {},
              onDuplicate: () {},
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.25,
            child: _FolderCardContent(
              node: node,
              childCount: childCount,
              isDropTarget: false,
              isGhost: true,
              onOpen: () {},
              onRename: () {},
              onDelete: () {},
              onMove: () {},
              onDuplicate: () {},
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: isDropTarget
                  ? [
                      BoxShadow(
                          color: _kTeal.withOpacity(0.45),
                          blurRadius: 24,
                          spreadRadius: 3)
                    ]
                  : [],
            ),
            child: _FolderCardContent(
              node: node,
              childCount: childCount,
              isDropTarget: isDropTarget,
              isGhost: false,
              onOpen: () => _openFolder(node),
              onRename: () => _showRenameDialog(node),
              onDelete: () => _deleteNode(node),
              onMove: () => _showMoveDialog(node),
              onDuplicate: () => _duplicateFolder(node),
            ),
          ),
        );
      },
    );
  }

  // ── Leaf card ──────────────────────────────────────────────────────────────

  Widget _buildLeafCard(TankNode node, int index) {
    final tank = node.tankId != null ? _tankCache[node.tankId] : null;

    return LongPressDraggable<_DragPayload>(
      key: ValueKey('leaf-drag-${node.id}'),
      data: _DragPayload(node, index),
      hapticFeedbackOnStart: true,
      onDragStarted: () => setState(() => _isDragging = true),
      onDragEnd: (_) => setState(() => _isDragging = false),
      onDraggableCanceled: (_, __) => setState(() => _isDragging = false),
      feedback: _DragGhost(
        width: MediaQuery.of(context).size.width - 32,
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
        opacity: 0.25,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _FabSheet extends StatelessWidget {
  final VoidCallback onNewGroup;
  final VoidCallback onNewTank;
  const _FabSheet({required this.onNewGroup, required this.onNewTank});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
                color: _kBorderH, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 22),
          Text('Add Content',
              style: GoogleFonts.raleway(
                  color: _kTextD,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 16),
          _SheetOption(
            icon: Icons.folder_open_outlined,
            label: 'New Group',
            sub: 'Organise tanks into folders',
            color: _kCopper,
            onTap: onNewGroup,
          ),
          const SizedBox(height: 10),
          _SheetOption(
            icon: Icons.water_outlined,
            label: 'New Tank',
            sub: 'Add a tank to this group',
            color: _kTeal,
            onTap: onNewTank,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOLDER CARD CONTENT
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
  final VoidCallback onDuplicate;

  const _FolderCardContent({
    required this.node,
    required this.childCount,
    required this.isDropTarget,
    required this.isGhost,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDropTarget ? _kTeal : _kCopper;
    return GestureDetector(
      onTap: isGhost ? null : onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: isDropTarget ? _kTeal.withOpacity(0.06) : _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDropTarget ? _kTeal.withOpacity(0.55) : _kBorder,
            width: isDropTarget ? 1.5 : 1,
          ),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDropTarget
                    ? [_kTeal.withOpacity(0.15), _kTeal.withOpacity(0.03)]
                    : [_kCopper.withOpacity(0.12), _kCard],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.25)),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  Icon(
                    isDropTarget
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded,
                    color: accent,
                    size: 28,
                  ),
                  if (isDropTarget)
                    Positioned(
                      bottom: 3,
                      right: 3,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: const BoxDecoration(
                            color: _kTeal, shape: BoxShape.circle),
                        child: const Icon(Icons.add_rounded,
                            size: 9, color: Colors.white),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(node.name,
                          style: GoogleFonts.raleway(
                              color: _kText,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const SizedBox(height: 5),
                      Wrap(spacing: 5, runSpacing: 4, children: [
                        if ((node.zone ?? '').isNotEmpty)
                          _Pill(
                              label: node.zone!,
                              icon: Icons.location_on_outlined,
                              color: accent),
                        if (childCount != null)
                          _Pill(
                            label:
                                '$childCount item${childCount == 1 ? '' : 's'}',
                            icon: Icons.layers_outlined,
                            color: _kSubL,
                          ),
                      ]),
                      if ((node.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(node.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.raleway(
                                fontSize: 11, color: _kSub)),
                      ],
                    ]),
              ),
              Icon(
                isDropTarget
                    ? Icons.download_rounded
                    : Icons.chevron_right_rounded,
                color: accent.withOpacity(0.7),
                size: 20,
              ),
            ]),
          ),
          if (!isGhost)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(18)),
                border: const Border(top: BorderSide(color: _kBorder)),
              ),
              child: Row(children: [
                const Icon(Icons.drag_indicator_rounded,
                    size: 13, color: _kSubL),
                const SizedBox(width: 4),
                Text('hold to drag',
                    style: GoogleFonts.raleway(fontSize: 9, color: _kSubL)),
                const Spacer(),
                _ActionChip(
                    icon: Icons.copy_outlined,
                    label: 'Clone',
                    color: _kAmber,
                    onTap: onDuplicate),
                const SizedBox(width: 6),
                _ActionChip(
                    icon: Icons.drive_file_move_outline,
                    label: 'Move',
                    color: _kPurple,
                    onTap: onMove),
                const SizedBox(width: 6),
                _ActionChip(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: _kTeal,
                    onTap: onRename),
                const SizedBox(width: 6),
                _ActionChip(
                    icon: Icons.delete_outline_rounded,
                    label: 'Del',
                    color: _kDanger,
                    onTap: onDelete),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEAF CARD CONTENT
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _kDanger,
          behavior: SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _modify() => _run(() async {
        final t = widget.tank;
        if (t == null) return;
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
                builder: (_) => CreateTankScreen(existingTank: tankMap)));
        final tid = widget.node.tankId;
        if (ok == true && tid != null && mounted) {
          final updated = await widget.tankRepo.getTankById(tid);
          if (updated != null) widget.onTankCacheUpdate(tid, updated);
        }
      });

  Future<void> _duplicate() => _run(() async {
        final t = widget.tank;
        final tid = widget.node.tankId;
        if (t == null || tid == null) return;
        final base = t.tankName.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
        final newName = '$base (1)';
        final newTankId = await widget.tankRepo.duplicateTank(t);
        await widget.treeRepo.createLeaf(
          name: newName,
          tankId: newTankId,
          zone: widget.node.zone ?? t.location,
          parentId: widget.currentParentId,
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cloned as "$newName"',
                style: GoogleFonts.raleway(
                    color: _kText, fontWeight: FontWeight.w600)),
            backgroundColor: _kSuccess,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
      });

  Future<void> _downloadQr() => _run(() async {
        final bytes = await _shotCtrl.captureFromWidget(
          Material(
              color: Colors.white,
              child: _PrintableQr(node: widget.node, tank: widget.tank)),
          pixelRatio: 3.0,
        );
        final qrUrl = await uploadBytesToCloudinary(bytes, folder: folderMain);
        final tid = widget.node.tankId;
        if (tid != null) {
          await FirebaseDatabase.instance
              .ref('tanks/$tid')
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: widget.isGhost
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.12), blurRadius: 6)
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
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.raleway(
                            color: _kText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(code,
                        style: GoogleFonts.sourceCodePro(
                            color: _kCopper,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    if (zone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 11, color: _kSub),
                        const SizedBox(width: 3),
                        Expanded(
                            child: Text(zone,
                                style: GoogleFonts.raleway(
                                    color: _kSub, fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                    if (paramCount > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 5, children: [
                        _Pill(
                            label:
                                '$paramCount param${paramCount == 1 ? '' : 's'}',
                            icon: Icons.tune_rounded,
                            color: _kTeal),
                        if (t?.scaleSide != null)
                          _Pill(
                              label: 'Scale ${t!.scaleSide}',
                              icon: Icons.straighten_rounded,
                              color: _kPurple),
                      ]),
                    ],
                  ]),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.drag_indicator_rounded, size: 18, color: _kSubL),
              if (_busy) ...[
                const SizedBox(height: 8),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: _kCopper, strokeWidth: 1.8)),
              ],
            ]),
          ]),
        ),
        if (!widget.isGhost)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: _busy
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: _kCopper, strokeWidth: 2)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                        _ActionChip(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            color: _kTeal,
                            onTap: _modify),
                        _ActionChip(
                            icon: Icons.copy_outlined,
                            label: 'Clone',
                            color: _kAmber,
                            onTap: _duplicate),
                        _ActionChip(
                            icon: Icons.qr_code_rounded,
                            label: 'QR',
                            color: _kCopper,
                            onTap: _downloadQr),
                        _ActionChip(
                            icon: Icons.drive_file_move_outline,
                            label: 'Move',
                            color: _kPurple,
                            onTap: widget.onMove),
                        _ActionChip(
                            icon: Icons.delete_outline_rounded,
                            label: 'Del',
                            color: _kDanger,
                            onTap: widget.onDelete),
                      ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAG GHOST
// ─────────────────────────────────────────────────────────────────────────────
class _DragGhost extends StatelessWidget {
  final Widget child;
  final double width;
  const _DragGhost({required this.child, required this.width});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: 0.88,
        child: Material(
          color: Colors.transparent,
          elevation: 24,
          shadowColor: _kCopper.withOpacity(0.45),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(width: width, child: child),
        ),
      );
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING PULSE
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingPulse extends StatefulWidget {
  const _LoadingPulse();
  @override
  State<_LoadingPulse> createState() => _LoadingPulseState();
}

class _LoadingPulseState extends State<_LoadingPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _anim,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _kCopper.withOpacity(0.5), width: 1.5),
            ),
            child:
                const Icon(Icons.storage_outlined, color: _kCopper, size: 22),
          ),
          const SizedBox(height: 14),
          Text('Loading…',
              style: GoogleFonts.raleway(color: _kSub, fontSize: 13)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kSurface,
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.folder_open_outlined, size: 34, color: _kSubL),
          ),
          const SizedBox(height: 20),
          Text('Nothing here yet',
              style: GoogleFonts.raleway(
                  color: _kText, fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 6),
          Text('Tap + to add a group or a tank',
              style: GoogleFonts.raleway(color: _kSub, fontSize: 13)),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kCopperD, _kCopper, _kCopperL],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _kCopper.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 7))
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Add Content',
                    style: GoogleFonts.raleway(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ]),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// BACK ROW
// ─────────────────────────────────────────────────────────────────────────────
class _BackRow extends StatelessWidget {
  final String folderName;
  final VoidCallback onBack;
  const _BackRow({required this.folderName, required this.onBack});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onBack,
        child: Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  size: 14, color: _kCopper),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.folder_rounded, size: 14, color: _kCopper),
            const SizedBox(width: 7),
            Expanded(
                child: Text(folderName,
                    style: GoogleFonts.raleway(
                        color: _kText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13))),
            Text('tap to go up',
                style: GoogleFonts.raleway(fontSize: 10, color: _kSubL)),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_up_rounded,
                size: 15, color: _kSubL),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET OPTION
// ─────────────────────────────────────────────────────────────────────────────
class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        style: GoogleFonts.raleway(
                            color: _kText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    Text(sub,
                        style: GoogleFonts.raleway(color: _kSub, fontSize: 12)),
                  ])),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: color.withOpacity(0.7)),
            ]),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MOVE TARGET
// ─────────────────────────────────────────────────────────────────────────────
class _MoveTarget extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MoveTarget({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.25)),
            ),
            child: Row(children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      style: GoogleFonts.raleway(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700))),
              Icon(Icons.arrow_forward_rounded,
                  size: 13, color: color.withOpacity(0.7)),
            ]),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.raleway(
                    fontSize: 8, color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PILL BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Pill({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: GoogleFonts.raleway(
                  fontSize: 9, color: color, fontWeight: FontWeight.w700)),
        ]),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: iconColor, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.raleway(
                        color: _kText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15))),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close_rounded, color: _kSub, size: 17),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(20), child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.raleway(color: _kSub)),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: saving ? null : onConfirm,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                    color: iconColor, borderRadius: BorderRadius.circular(10)),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(confirmLabel ?? 'OK',
                        style: GoogleFonts.raleway(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
              ),
            ),
          ]),
        ),
      ]),
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
        style: GoogleFonts.raleway(color: _kText, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.raleway(color: _kSub, fontSize: 12),
          prefixIcon: Icon(icon, color: _kSub, size: 17),
          filled: true,
          fillColor: _kSurface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
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
          color: _kDanger.withOpacity(0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _kDanger.withOpacity(0.28)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: _kDanger, size: 13),
          const SizedBox(width: 7),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.raleway(color: _kDanger, fontSize: 12))),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title,
          style:
              GoogleFonts.raleway(color: _kText, fontWeight: FontWeight.w800)),
      content:
          Text(message, style: GoogleFonts.raleway(color: _kSub, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: GoogleFonts.raleway(color: _kSub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete',
              style: GoogleFonts.raleway(
                  color: _kDanger, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return result == true;
}
