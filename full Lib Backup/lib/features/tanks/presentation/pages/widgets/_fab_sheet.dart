part of '../tank_browser_screen.dart';


class _FabSheet extends StatelessWidget {
  final VoidCallback onNewGroup;
  final VoidCallback onNewTank;
  const _FabSheet({required this.onNewGroup, required this.onNewTank});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
                color: _kBorderH, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 22),
          Text('Add Content',
              style: GoogleFonts.raleway(
                  color: _kTextD,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 16),
          _SheetOption(
            icon: Icons.folder_open_outlined,
            label: 'New Group',
            sub: 'Organise tanks into folders',
            color: _kCopper,
            onTap: onNewGroup,
          ),
          const SizedBox(height: 10),
          _SheetOption(
            icon: Icons.water_outlined,
            label: 'New Tank',
            sub: 'Add a tank to this group',
            color: _kTeal,
            onTap: onNewTank,
          ),
        ]),
      ),
    );
  }
}
