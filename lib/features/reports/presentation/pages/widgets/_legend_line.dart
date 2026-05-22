part of '../trends_screen.dart';


class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendLine({required this.color, required this.label});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 18,
            height: 2.5,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 11, color: _kSub, fontWeight: FontWeight.w500)),
      ]);
}
