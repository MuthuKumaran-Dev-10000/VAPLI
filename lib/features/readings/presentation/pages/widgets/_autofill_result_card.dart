part of '../reading_entry_screen.dart';


class _AutofillResultCard extends StatelessWidget {
  final double value;
  const _AutofillResultCard({required this.value});

  @override
  Widget build(BuildContext context) {
    final display = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kSuccess.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kSuccess.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, size: 14, color: _kSuccess),
        const SizedBox(width: 8),
        Text('Result: ',
            style: GoogleFonts.dmSans(fontSize: 12, color: _kSuccess)),
        Text(display,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: _kSuccess,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('(auto-filled)',
            style: GoogleFonts.dmSans(fontSize: 10, color: _kSub)),
      ]),
    );
  }
}
