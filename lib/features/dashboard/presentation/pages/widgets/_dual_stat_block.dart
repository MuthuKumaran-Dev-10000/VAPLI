part of '../dashboard_tab.dart';

// _DualStatBlock — unchanged
class _DualStatBlock extends StatelessWidget {
  final ParamStat stat;
  final String Function(double?) fmtNum;
  final Map<String, dynamic> prop;

  const _DualStatBlock({
    required this.stat,
    required this.fmtNum,
    required this.prop,
  });

  @override
  Widget build(BuildContext context) {
    final leftLabel =
        (prop['left_label']?.toString().trim().isNotEmpty ?? false)
            ? prop['left_label'].toString()
            : 'Before';

    final rightLabel =
        (prop['right_label']?.toString().trim().isNotEmpty ?? false)
            ? prop['right_label'].toString()
            : 'After';

    final leftStats = stat.dualLeftStats;
    final rightStats = stat.dualRightStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRow(
          title: leftLabel,
          stats: leftStats,

          // LEFT EXPECTED VALUES
          expectedAvg:
              (prop['left_expected_avg'] as num?)?.toDouble(),

          expectedMin:
              (prop['left_expected_min'] as num?)?.toDouble(),

          expectedMax:
              (prop['left_expected_max'] as num?)?.toDouble(),
        ),

        const SizedBox(height: 12),

        _buildRow(
          title: rightLabel,
          stats: rightStats,

          // RIGHT EXPECTED VALUES
          expectedAvg:
              (prop['right_expected_avg'] as num?)?.toDouble(),

          expectedMin:
              (prop['right_expected_min'] as num?)?.toDouble(),

          expectedMax:
              (prop['right_expected_max'] as num?)?.toDouble(),
        ),
      ],
    );
  }

  Widget _buildRow({
    required String title,
    required dynamic stats,
    double? expectedAvg,
    double? expectedMin,
    double? expectedMax,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            color: _kSub,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),

        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(
              child: _NumChip(
                label: 'AVG',
                value: fmtNum(stats?.avg),
                expected: fmtNum(expectedAvg),
                color: _kCopper,
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: _NumChip(
                label: 'MIN',
                value: fmtNum(stats?.min),
                expected: fmtNum(expectedMin),
                color: _kTeal,
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: _NumChip(
                label: 'MAX',
                value: fmtNum(stats?.max),
                expected: fmtNum(expectedMax),
                color: _kWarn,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
