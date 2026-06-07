part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// META CARD
// ─────────────────────────────────────────────────────────────────────────────
class _MetaCard extends StatelessWidget {
  final TankModel tank;
  final UserModel currentUser;
  final String nowLabel;
  final String? endLabel; // 🔖 Added for Historical Upload Permission
  final VoidCallback? onStartTap; // 🔖 Added for Historical Upload Permission
  final VoidCallback? onEndTap; // 🔖 Added for Historical Upload Permission

  const _MetaCard({
    required this.tank,
    required this.currentUser,
    required this.nowLabel,
    this.endLabel, // 🔖 Added for Historical Upload Permission
    this.onStartTap, // 🔖 Added for Historical Upload Permission
    this.onEndTap, // 🔖 Added for Historical Upload Permission
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
            
            // Start Date Row
            onStartTap != null
                ? InkWell(
                    onTap: onStartTap,
                    child: _MetaRow(
                      label: 'Captured At Start',
                      value: nowLabel,
                      suffixIcon: Icons.edit_calendar_rounded,
                    ),
                  )
                : _MetaRow(label: 'Captured At Start', value: nowLabel),
            
            // End Date Row
            if (endLabel != null)
              onEndTap != null
                  ? InkWell(
                      onTap: onEndTap,
                      child: _MetaRow(
                        label: 'Captured At End',
                        value: endLabel!,
                        suffixIcon: Icons.edit_calendar_rounded,
                      ),
                    )
                  : _MetaRow(label: 'Captured At End', value: endLabel!),
          ]),
        ),
      ]),
    );
  }
}
