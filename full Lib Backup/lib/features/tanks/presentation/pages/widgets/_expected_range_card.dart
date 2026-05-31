part of '../property_builder_page.dart';


class _ExpectedRangeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _ExpectedRangeCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      padding: const EdgeInsets.all(14),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withOpacity(0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.straighten_outlined,
                size: 15, color: Color(0xFF22C55E)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF0EEE9))),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF8A8F9C))),
              ])),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }
}
