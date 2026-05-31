part of '../dashboard_tab.dart';


// ─────────────────────────────────────────────────────────────────────────────
// _TankStatsCard — unchanged except NumChip value size now 14px + colored
// ─────────────────────────────────────────────────────────────────────────────
class _TankStatsCard extends StatefulWidget {
  final TankModel tank;
  final GlobalKey captureKey;
  final Future<void> Function() onDownloadPng;
  final bool forceExpandLastInspection;
  const _TankStatsCard({
    required this.tank,
    required this.captureKey,
    required this.onDownloadPng,
    this.forceExpandLastInspection = false,
  });

  @override
  State<_TankStatsCard> createState() => _TankStatsCardState();
}
