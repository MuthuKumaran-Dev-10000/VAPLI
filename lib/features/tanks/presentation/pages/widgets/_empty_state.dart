part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kSurface,
              border: Border.all(color: _kBorder),
            ),
            child:
                const Icon(Icons.folder_open_outlined, size: 34, color: _kSubL),
          ),
          const SizedBox(height: 20),
          Text('Nothing here yet',
              style: GoogleFonts.raleway(
                  color: _kText, fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 6),
          Text('Tap + to add a group or a tank',
              style: GoogleFonts.raleway(color: _kSub, fontSize: 13)),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_kCopperD, _kCopper, _kCopperL],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _kCopper.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 7))
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Add Content',
                    style: GoogleFonts.raleway(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ]),
            ),
          ),
        ]),
      );
}
