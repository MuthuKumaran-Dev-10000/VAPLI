part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// STYLED DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _StyledDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final String? confirmLabel;
  final bool saving;
  final VoidCallback onConfirm;

  const _StyledDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    required this.onConfirm,
    this.confirmLabel,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: iconColor, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.raleway(
                        color: _kText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15))),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close_rounded, color: _kSub, size: 17),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(20), child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.raleway(color: _kSub)),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: saving ? null : onConfirm,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                    color: iconColor, borderRadius: BorderRadius.circular(10)),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(confirmLabel ?? 'OK',
                        style: GoogleFonts.raleway(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
