part of '../reading_entry_screen.dart';


class _AutofillErrorCard extends StatelessWidget {
  final String laymanMessage;
  final String exceptionName;
  const _AutofillErrorCard(
      {required this.laymanMessage, required this.exceptionName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kDanger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kDanger.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded, size: 14, color: _kDanger),
            const SizedBox(width: 6),
            Text('Calculation Error',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _kDanger,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 5),
          Text(laymanMessage,
              style: GoogleFonts.dmSans(fontSize: 12, color: _kText)),
          if (exceptionName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Technical: $exceptionName',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: _kSub, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}
