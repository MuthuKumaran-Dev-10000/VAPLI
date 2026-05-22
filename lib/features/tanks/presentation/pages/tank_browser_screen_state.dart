part of 'tank_browser_screen.dart'; 
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
                  zone: 'root',
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
      zone: 'root',
      parentId: _currentFolder?.id,
    );
  }

  // Future<void> _deleteNode(TankNode node) async {
  //   final confirmed = await _confirmDialog(
  //     context,
  //     title: 'Delete ${node.isFolder ? 'Group' : 'Tank'}',
  //     message: node.isFolder
  //         ? 'Delete "${node.name}" and all its contents? Cannot be undone.'
  //         : 'Remove "${node.name}" from this group? The tank record is preserved.',
  //   );
  //   if (!confirmed) return;
  //   await _treeRepo.deleteNode(node.id);
  // }

  Future<void> _deleteNode(TankNode node) async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Delete ${node.isFolder ? 'Group' : 'Tank'}',
      message: node.isFolder
          ? 'Delete "${node.name}" and all its contents? Cannot be undone.'
          : 'Delete "${node.name}" completely? This removes tank, dashboard stats, alerts, readings, and tree references.',
    );

    if (!confirmed) return;

    try {
      // ─────────────────────────────────────────────
      // LEAF = REAL TANK DELETE
      // ─────────────────────────────────────────────
      if (node.isLeaf && node.tankId != null) {
        debugPrint(
          '[DELETE] Full tank delete tankId=${node.tankId}',
        );

        await _tankRepo.deleteTank(
          node.tankId!,
        );
      }

      // ─────────────────────────────────────────────
      // FOLDER DELETE
      // ─────────────────────────────────────────────
      else {
        debugPrint(
          '[DELETE] Folder delete nodeId=${node.id}',
        );

        final subtree = await _treeRepo.fetchSubtree(node.id);
        final tankIds = subtree
            .where((n) => n.isLeaf && n.tankId != null)
            .map((n) => n.tankId!)
            .toSet();

        for (final tankId in tankIds) {
          await _tankRepo.deleteTank(tankId);
        }

        await _treeRepo.deleteNode(
          node.id,
        );
      }

      if (mounted) {
        _snack(
          '${node.isFolder ? 'Group' : 'Tank'} deleted successfully',
          _kSuccess,
        );
      }
    } catch (e, s) {
      debugPrint(
        '[DELETE ERROR] $e\n$s',
      );

      if (mounted) {
        _snack(
          'Delete failed: $e',
          _kDanger,
        );
      }
    }
  }

  Future<void> _showRenameDialog(TankNode node) async {
    final nameCtrl = TextEditingController(text: node.name);
    final descCtrl = TextEditingController(text: node.description ?? '');

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
                  zone: 'root',
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
