part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// ALERTS EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _AlertsEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Column(children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 28, color: _kSuccess.withOpacity(0.7)),
          const SizedBox(height: 8),
          Text('No alerts today',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 3),
          Text('All clear — no open tasks',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 11)),
        ]),
      );
}
