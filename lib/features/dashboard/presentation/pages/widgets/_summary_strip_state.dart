part of '../dashboard_tab.dart';


class _SummaryStripState extends State<_SummaryStrip> {
  int _totalReadings = 0;
  int _activeToday = 0;
  final _repo = DashboardStatsRepository();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _subscribeTanks();
  }

  @override
  void didUpdateWidget(_SummaryStrip old) {
    super.didUpdateWidget(old);
    if (old.tankCount != widget.tankCount) _subscribeTanks();
  }

  void _subscribeTanks() {
    _sub?.cancel();
    TankRepository().watchTanks().listen((tanks) async {
      int total = 0, today = 0;
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final t in tanks) {
        final stats = await _repo.getStats(t.id);
        total += stats.count;
        if (stats.lastCapturedAt != null &&
            stats.lastCapturedAt!.startsWith(todayStr)) {
          today++;
        }
        // Trigger expected-avg check
        widget.onStatsReady(t, stats);
      }
      if (mounted) {
        setState(() {
          _totalReadings = total;
          _activeToday = today;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        Expanded(
            child: _KpiChip(
                icon: Icons.storage_outlined,
                label: 'Assets',
                value: '${widget.tankCount}',
                color: _kTeal)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiChip(
                icon: Icons.receipt_long_outlined,
                label: 'Total Readings',
                value: '$_totalReadings',
                color: _kCopper)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiChip(
                icon: Icons.today_outlined,
                label: 'Active Today',
                value: '$_activeToday',
                color: _kSuccess)),
      ]),
    );
  }
}
