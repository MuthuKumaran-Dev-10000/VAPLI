part of '../tank_browser_screen.dart';


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
