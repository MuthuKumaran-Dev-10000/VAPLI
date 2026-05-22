part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// UPLOADING BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _UploadingBanner extends StatelessWidget {
  const _UploadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCopper.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kCopper.withOpacity(0.35)),
      ),
      child: Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(color: _kCopper, strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('Uploading photos, please wait…',
            style: GoogleFonts.dmSans(
                color: _kCopper, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
