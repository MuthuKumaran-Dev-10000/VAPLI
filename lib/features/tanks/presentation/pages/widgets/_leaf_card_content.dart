part of '../tank_browser_screen.dart';


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
