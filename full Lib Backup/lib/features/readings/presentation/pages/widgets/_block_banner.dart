part of '../reading_entry_screen.dart';


// ─────────────────────────────────────────────────────────────────────────────
// BLOCK BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _BlockBanner extends StatelessWidget {
  final Map<String, List<_Violation>> violations;
  final List<Map<String, dynamic>> props;

  const _BlockBanner({required this.violations, required this.props});

  @override
  Widget build(BuildContext context) {
    final blocked = violations.entries
        .where((e) => e.value.any((v) => v.blockSubmission))
        .map((e) {
      final p = props.firstWhere((pp) => pp['id'] == e.key,
          orElse: () => {'label': e.key});
      return '"${p['label']}"';
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kDanger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDanger.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.block_rounded, color: _kDanger, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submission Blocked',
                  style: GoogleFonts.dmSans(
                      color: _kDanger,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 3),
              Text('Fix violations in: ${blocked.join(', ')}',
                  style: GoogleFonts.dmSans(color: _kText, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}
