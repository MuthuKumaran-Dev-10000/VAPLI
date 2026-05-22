part of '../tank_browser_screen.dart';


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
