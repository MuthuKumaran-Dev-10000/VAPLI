part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// ERROR TEXT
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _kDanger.withOpacity(0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: _kDanger.withOpacity(0.28)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: _kDanger, size: 13),
          const SizedBox(width: 7),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.raleway(color: _kDanger, fontSize: 12))),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIRM DIALOG
// ─────────────────────────────────────────────────────────────────────────────
Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title,
          style:
              GoogleFonts.raleway(color: _kText, fontWeight: FontWeight.w800)),
      content:
          Text(message, style: GoogleFonts.raleway(color: _kSub, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: GoogleFonts.raleway(color: _kSub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete',
              style: GoogleFonts.raleway(
                  color: _kDanger, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return result == true;
}
