part of '../trends_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE MICRO-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SecLabel extends StatelessWidget {
  final String text;
  const _SecLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: _kSubL,
          letterSpacing: 1.8));
}
