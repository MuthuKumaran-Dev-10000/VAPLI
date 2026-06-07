part of '../dashboard_tab.dart';

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
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 28, color: _kSuccess.withOpacity(0.7)),
            const SizedBox(height: 8),
            Text(
              'No open alerts',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Text(
              'All clear - no unresolved alerts',
              style: GoogleFonts.dmSans(color: _kSub, fontSize: 11),
            ),
          ],
        ),
      );
}
