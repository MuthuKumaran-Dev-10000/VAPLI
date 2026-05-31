part of '../dashboard_tab.dart';


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
