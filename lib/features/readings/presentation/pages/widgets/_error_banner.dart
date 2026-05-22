part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// ERROR BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kDanger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kDanger.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: _kDanger, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.dmSans(color: _kDanger, fontSize: 12))),
        ]),
      );
}
