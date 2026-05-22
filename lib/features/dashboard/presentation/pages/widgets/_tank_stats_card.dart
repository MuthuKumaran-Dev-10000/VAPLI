part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _TankStatsCard — unchanged except NumChip value size now 14px + colored
// ─────────────────────────────────────────────────────────────────────────────
class _TankStatsCard extends StatefulWidget {
  final TankModel tank;
  const _TankStatsCard({required this.tank});

  @override
  State<_TankStatsCard> createState() => _TankStatsCardState();
}
