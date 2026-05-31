part of '../trends_screen.dart';


class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: _kSubL),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: _kSubL)),
      ]);
}
