part of '../dashboard_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _NumChip — value text now 14px (medium) and colored same as chip color
// ─────────────────────────────────────────────────────────────────────────────
class _NumChip extends StatelessWidget {
  final String label;
  final String value;

  /// optional expected value
  final String? expected;

  final Color color;

  const _NumChip({
    required this.label,
    required this.value,
    this.expected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasExpected =
        expected != null &&
        expected!.trim().isNotEmpty &&
        expected != '—';

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: Stack(
        children: [
          if (hasExpected)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  expected!,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: color.withOpacity(0.85),
                  ),
                ),
              ),
            ),

          Column(
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                value,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
