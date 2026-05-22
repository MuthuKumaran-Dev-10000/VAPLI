import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ActionBar — the 4-button row shown on each tank card
// ─────────────────────────────────────────────────────────────────────────────

class ActionBar extends StatelessWidget {
  final VoidCallback onDuplicate;
  final VoidCallback onModify;
  final VoidCallback onDownloadQr;
  final VoidCallback onDelete;

  const ActionBar({
    required this.onDuplicate,
    required this.onModify,
    required this.onDownloadQr,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Row 1: Duplicate + Modify
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmallBtn(
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              color: const Color(0xFFFFB703),
              onTap: () {
                debugPrint('[ActionBar] Duplicate tapped');
                onDuplicate();
              },
            ),
            const SizedBox(width: 6),
            _SmallBtn(
              icon: Icons.edit_outlined,
              label: 'Modify',
              color: const Color(0xFF00B4D8),
              onTap: () {
                debugPrint('[ActionBar] Modify tapped');
                onModify();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Row 2: Download + Delete
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmallBtn(
              icon: Icons.download_outlined,
              label: 'Download',
              color: const Color(0xFF06D6A0),
              onTap: () {
                debugPrint('[ActionBar] Download tapped');
                onDownloadQr();
              },
            ),
            const SizedBox(width: 6),
            _SmallBtn(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: const Color(0xFFEF233C),
              onTap: () {
                debugPrint('[ActionBar] Delete tapped');
                onDelete();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SmallBtn — compact icon+label chip button
// ─────────────────────────────────────────────────────────────────────────────

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}
