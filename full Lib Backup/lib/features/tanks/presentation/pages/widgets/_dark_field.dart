part of '../tank_browser_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// DARK FIELD
// ─────────────────────────────────────────────────────────────────────────────
class _DarkField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  const _DarkField(
      {required this.ctrl, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        style: GoogleFonts.raleway(color: _kText, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.raleway(color: _kSub, fontSize: 12),
          prefixIcon: Icon(icon, color: _kSub, size: 17),
          filled: true,
          fillColor: _kSurface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _kCopper, width: 1.5)),
        ),
      );
}
