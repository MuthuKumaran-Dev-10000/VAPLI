part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// BACK ROW
// ─────────────────────────────────────────────────────────────────────────────
class _BackRow extends StatelessWidget {
  final String folderName;
  final VoidCallback onBack;
  const _BackRow({required this.folderName, required this.onBack});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onBack,
        child: Container(
          color: _kBg,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  size: 14, color: _kCopper),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.folder_rounded, size: 14, color: _kCopper),
            const SizedBox(width: 7),
            Expanded(
                child: Text(folderName,
                    style: GoogleFonts.raleway(
                        color: _kText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13))),
            Text('tap to go up',
                style: GoogleFonts.raleway(fontSize: 10, color: _kSubL)),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_up_rounded,
                size: 15, color: _kSubL),
          ]),
        ),
      );
}
