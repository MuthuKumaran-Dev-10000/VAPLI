part of '../dashboard_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryStrip — unchanged except callback for expected-avg check
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryStrip extends StatefulWidget {
  final int tankCount;
  final List<TankModel> tanks;
  final Future<void> Function(TankModel, DashboardStatsModel) onStatsReady;

  const _SummaryStrip({
    required this.tankCount,
    required this.tanks,
    required this.onStatsReady,
  });

  @override
  State<_SummaryStrip> createState() => _SummaryStripState();
}
