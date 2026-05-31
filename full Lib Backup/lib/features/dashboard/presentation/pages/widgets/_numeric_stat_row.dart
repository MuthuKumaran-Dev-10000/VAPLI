part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _NumericStatRow — value text medium (14px), colored same as chip
// ─────────────────────────────────────────────────────────────────────────────
class _NumericStatRow extends StatelessWidget {
  final ParamStat stat;
  final String Function(double?) fmtNum;

  final double? expectedAvg;
  final double? expectedMin;
  final double? expectedMax;

  const _NumericStatRow({
    required this.stat,
    required this.fmtNum,
    this.expectedAvg,
    this.expectedMin,
    this.expectedMax,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NumChip(
            label: 'AVG',
            value: fmtNum(stat.avg),
            expected: fmtNum(expectedAvg),
            color: _kCopper,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _NumChip(
            label: 'MIN',
            value: fmtNum(stat.min),
            expected: fmtNum(expectedMin),
            color: _kTeal,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _NumChip(
            label: 'MAX',
            value: fmtNum(stat.max),
            expected: fmtNum(expectedMax),
            color: _kWarn,
          ),
        ),
      ],
    );
  }
}
