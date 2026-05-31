part of '../tank_browser_screen.dart';


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
