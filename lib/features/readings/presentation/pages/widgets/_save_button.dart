part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// SAVE BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _SaveButton extends StatelessWidget {
  final bool saving;
  final bool saved;
  final bool failed;
  final bool canSave;
  final VoidCallback? onTap;

  const _SaveButton({
    required this.saving,
    required this.saved,
    required this.failed,
    required this.canSave,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Widget child;

    if (saved) {
      bg = _kSuccess;
      child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text('Saved — Returning…',
            style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ]);
    } else if (failed) {
      bg = _kDanger;
      child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text('Failed — Tap to Retry',
            style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ]);
    } else if (saving) {
      bg = _kCopper.withOpacity(0.7);
      child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 18,
            height: 18,
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('Saving…',
            style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ]);
    } else {
      bg = canSave ? _kCopper : _kSurface;
      child = Text('Save Reading',
          style: GoogleFonts.dmSans(
              color: canSave ? Colors.white : _kDisable,
              fontWeight: FontWeight.w700,
              fontSize: 14));
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: canSave && !saving
              ? [
                  BoxShadow(
                      color: bg.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]
              : [],
        ),
        child: Center(child: child),
      ),
    );
  }
}
