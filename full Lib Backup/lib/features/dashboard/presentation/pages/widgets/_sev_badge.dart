part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// SEVERITY BADGE
// ─────────────────────────────────────────────────────────────────────────────
class _SevBadge extends StatelessWidget {
  final String severity;
  const _SevBadge(this.severity);

  @override
  Widget build(BuildContext context) {
    final color = _sevColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(severity.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    );
  }
}
