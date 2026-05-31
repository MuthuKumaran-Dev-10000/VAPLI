part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// META CARD
// ─────────────────────────────────────────────────────────────────────────────
class _MetaCard extends StatelessWidget {
  final TankModel tank;
  final UserModel currentUser;
  final String nowLabel;

  const _MetaCard({
    required this.tank,
    required this.currentUser,
    required this.nowLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: _kCopper, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tank.tankName,
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            Text(tank.tankCode,
                style: GoogleFonts.spaceGrotesk(
                    color: _kCopper,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _MetaRow(label: 'Zone', value: tank.location ?? '—'),
            _MetaRow(label: 'Inspector', value: currentUser.fullName),
            _MetaRow(label: 'Timestamp', value: nowLabel),
          ]),
        ),
      ]),
    );
  }
}
