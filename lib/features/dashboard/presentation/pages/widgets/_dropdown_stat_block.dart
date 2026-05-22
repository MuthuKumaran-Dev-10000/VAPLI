part of '../dashboard_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _DropdownStatBlock — unchanged
// ─────────────────────────────────────────────────────────────────────────────
class _DropdownStatBlock extends StatelessWidget {
  final ParamStat stat;
  final int totalCount;
  const _DropdownStatBlock({required this.stat, required this.totalCount});

  static const _palette = [
    _kTeal,
    _kCopper,
    _kSuccess,
    _kWarn,
    _kPurple,
    _kBlue,
    _kDanger,
  ];

  @override
  Widget build(BuildContext context) {
    final counts = stat.optionCounts;
    if (counts.isEmpty) {
      return Text('No selections yet',
          style: GoogleFonts.dmSans(fontSize: 12, color: _kSub));
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = counts.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.asMap().entries.map((e) {
        final idx = e.key;
        final opt = e.value.key;
        final count = e.value.value;
        final pct = total > 0 ? (count / total) : 0.0;
        final color = _palette[idx % _palette.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(opt,
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: _kText,
                          fontWeight: FontWeight.w500)),
                ),
                Text('$count',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: _kSub,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(pct * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
