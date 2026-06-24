part of '../tank_browser_screen.dart';


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
  final bool canModify;
  final bool canDelete;
  final bool canDuplicate;
  final bool showModifyParameters;
  final VoidCallback? onModifyParameters;

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
    this.canModify = true,
    this.canDelete = true,
    this.canDuplicate = true,
    this.showModifyParameters = false,
    this.onModifyParameters,
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
                if (showModifyParameters && onModifyParameters != null) ...[
                  _ActionChip(
                      icon: Icons.settings_suggest_outlined,
                      label: 'Modify Params',
                      color: _kTeal,
                      onTap: onModifyParameters!),
                  const SizedBox(width: 6),
                ],
                if (canDuplicate)
                  _ActionChip(
                      icon: Icons.copy_outlined,
                      label: 'Clone',
                      color: _kAmber,
                      onTap: onDuplicate),
                const SizedBox(width: 6),
                if (canModify)
                  _ActionChip(
                      icon: Icons.drive_file_move_outline,
                      label: 'Move',
                      color: _kPurple,
                      onTap: onMove),
                const SizedBox(width: 6),
                if (canModify)
                  _ActionChip(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      color: _kTeal,
                      onTap: onRename),
                const SizedBox(width: 6),
                if (canDelete)
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
