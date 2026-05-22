part of 'dashboard_tab.dart'; 
class _DashboardTabState extends State<DashboardTab> {
  List<TankModel> _tanks = [];
  StreamSubscription<List<TankModel>>? _tankSub;

  // Alerts
  List<_AlertModel> _allAlerts = [];
  List<_CompletedTask> _completed = [];
  StreamSubscription? _alertSub;
  StreamSubscription? _completedSub;
  _AlertFilter _filter = _AlertFilter.time;
  bool _filterAscending = false; // newest first for time

  final _db = DatabaseModeService.ref();

  @override
  void initState() {
    super.initState();
    _tankSub = TankRepository().watchTanks().listen((tanks) {
      if (mounted) setState(() => _tanks = tanks);
    });
    _subscribeAlerts();
    _subscribeCompleted();
  }

  @override
  void dispose() {
    _tankSub?.cancel();
    _alertSub?.cancel();
    _completedSub?.cancel();
    super.dispose();
  }

  // ── Alert stream ───────────────────────────────────────────────────────────

  void _subscribeAlerts() {
    _alertSub?.cancel();
    _alertSub = _db.child('alerts').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) setState(() => _allAlerts = []);
        return;
      }
      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = raw.values
          .map((v) => _AlertModel.fromMap(Map<dynamic, dynamic>.from(v as Map)))
          .toList();
      if (mounted) setState(() => _allAlerts = list);
    });
  }

  void _subscribeCompleted() {
    _completedSub?.cancel();
    _completedSub = _db.child('completed_tasks').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) setState(() => _completed = []);
        return;
      }
      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final list = <_CompletedTask>[];
      for (final v in raw.values) {
        final m = Map<dynamic, dynamic>.from(v as Map);
        final alertMap = m['alert'];
        if (alertMap == null) continue;
        list.add(_CompletedTask(
          alertId: m['alert_id']?.toString() ?? '',
          completedAt: m['completed_at']?.toString() ?? '',
          completedBy: m['completed_by']?.toString() ?? '',
          alert:
              _AlertModel.fromMap(Map<dynamic, dynamic>.from(alertMap as Map)),
        ));
      }
      list.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      if (mounted) setState(() => _completed = list);
    });
  }

  // ── Expected-avg alert generator ──────────────────────────────────────────

  /// For every numeric/slider param that has expected_avg defined,
  /// if param_stats.avg > expected_avg → write a synthetic alert to Firebase
  /// (idempotent: uses a stable key so it won't duplicate).
  Future<void> _checkExpectedAvgAlerts(
      TankModel tank, DashboardStatsModel stats) async {
    for (final p in tank.inspectionProperties) {
      final label = p['label'] as String? ?? '';
      final type = p['type'] as String? ?? '';
      final expAvg = (p['expected_avg'] as num?)?.toDouble();
      if (expAvg == null) continue;
      if (type != 'number' && type != 'slider') continue;

      final stat = stats.paramStats[label];
      if (stat == null || stat.avg == null) continue;
      if (stat.avg! <= expAvg) continue;

      // avg exceeded → synthesise alert
      final alertId = 'avg_${tank.id}_${p['id']}';
      final existing = await _db.child('alerts/$alertId').get();
      if (existing.exists) {
        final ack = (existing.value as Map?)?['acknowledged'];
        if (ack == true) continue; // already handled
        continue; // already present and open
      }

      final alert = {
        'id': alertId,
        'alert_title': 'Avg Exceeded Expected',
        'message':
            '"$label" avg ${stat.avg!.toStringAsFixed(2)} exceeds expected avg $expAvg',
        'severity': 'critical',
        'tank_id': tank.id,
        'tank_name': tank.tankName,
        'tank_code': tank.tankCode,
        'param_id': p['id']?.toString() ?? '',
        'param_label': label,
        'param_value': stat.avg!.toStringAsFixed(2),
        'captured_by': '',
        'captured_by_name': 'Dashboard',
        'image_url': '',
        'constraint': '',
        'timestamp': DateTime.now().toIso8601String(),
        'acknowledged': false,
        'live': false,
      };
      await _db.child('alerts/$alertId').set(alert);
      debugPrint('[Dashboard] Expected-avg alert written: $alertId');
    }
  }

  // ── Complete task ──────────────────────────────────────────────────────────

  Future<void> _completeAlert(_AlertModel alert, String completedByName) async {
    final taskId = 'task_${alert.id}';
    final now = DateTime.now().toIso8601String();

    // Write to completed_tasks/
    await _db.child('completed_tasks/$taskId').set({
      'alert_id': alert.id,
      'completed_at': now,
      'completed_by': completedByName,
      'alert': {
        'id': alert.id,
        'alert_title': alert.alertTitle,
        'message': alert.message,
        'severity': alert.severity,
        'tank_id': alert.tankId,
        'tank_name': alert.tankName,
        'tank_code': alert.tankCode,
        'param_id': alert.paramId,
        'param_label': alert.paramLabel,
        'param_value': alert.paramValue,
        'captured_by': alert.capturedBy,
        'captured_by_name': alert.capturedByName,
        'image_url': alert.imageUrl,
        'constraint_id': alert.constraintId,
        'timestamp': alert.timestamp,
        'acknowledged': true,
        'live': alert.isLive,
      },
    });

    // Mark acknowledged in alerts/
    await _db.child('alerts/${alert.id}/acknowledged').set(true);
    debugPrint('[Dashboard] Task completed: ${alert.id}');
  }

  // ── Confirmation dialog ────────────────────────────────────────────────────

  Future<void> _showCompleteDialog(_AlertModel alert) async {
    bool checked = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: _kCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            Icon(_sevIcon(alert.severity),
                color: _sevColor(alert.severity), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Complete Task',
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.alertTitle,
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 4),
              Text(alert.message,
                  style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
              const SizedBox(height: 16),
              // Verification checkbox
              GestureDetector(
                onTap: () => setDlg(() => checked = !checked),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: checked ? _kSuccess.withOpacity(0.15) : _kSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: checked ? _kSuccess : _kBorderH,
                          width: checked ? 2 : 1),
                    ),
                    child: checked
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: _kSuccess)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'I have verified and checked this task has been resolved.',
                      style: GoogleFonts.dmSans(color: _kText, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.dmSans(color: _kSub)),
            ),
            GestureDetector(
              onTap: (!checked || saving)
                  ? null
                  : () async {
                      setDlg(() => saving = true);
                      try {
                        await _completeAlert(alert, 'Inspector');
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDlg(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('Failed: $e'),
                            backgroundColor: _kDanger,
                          ));
                        }
                      }
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: checked && !saving ? _kSuccess : _kSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.dmSans(
                            color: checked ? Colors.white : _kSubL,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sorted / filtered alerts ───────────────────────────────────────────────

  List<_AlertModel> get _todayOpenAlerts {
    final open = _allAlerts
        .where((a) => !a.acknowledged && _isToday(a.timestamp))
        .toList();

    switch (_filter) {
      case _AlertFilter.time:
        open.sort((a, b) => _filterAscending
            ? a.timestamp.compareTo(b.timestamp)
            : b.timestamp.compareTo(a.timestamp));
        break;
      case _AlertFilter.severity:
        open.sort(
            (a, b) => _sevOrder(a.severity).compareTo(_sevOrder(b.severity)));
        break;
    }
    return open;
  }

  List<_CompletedTask> get _completedToday =>
      _completed.where((t) => _isToday(t.completedAt)).toList();

  List<_CompletedTask> get _completedPrevious =>
      _completed.where((t) => !_isToday(t.completedAt)).toList();

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: _tanks.isEmpty
          ? _buildEmpty()
          : CustomScrollView(
              slivers: [
                // ── Header ────────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildHeader()),

                // ── Today's Tasks (alerts) ────────────────────────────────
                SliverToBoxAdapter(child: _buildAlertsPanel()),

                // ── Summary strip ─────────────────────────────────────────
                SliverToBoxAdapter(
                    child: _SummaryStrip(
                  tankCount: _tanks.length,
                  tanks: _tanks,
                  onStatsReady: _checkExpectedAvgAlerts,
                )),

                // ── Tank cards ────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _TankStatsCard(tank: _tanks[i]),
                      childCount: _tanks.length,
                    ),
                  ),
                ),

                // ── Completed Today ───────────────────────────────────────
                SliverToBoxAdapter(
                    child: _buildCompletedSection(
                  'TASKS COMPLETED TODAY',
                  _completedToday,
                  isToday: true,
                )),

                // ── Completed Previous ────────────────────────────────────
                SliverToBoxAdapter(
                    child: _buildCompletedSection(
                  'PREVIOUS DAYS',
                  _completedPrevious,
                  isToday: false,
                )),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
    );
  }

  // ── Header — unchanged ─────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Row(children: [
          Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                  color: _kCopper, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dashboard',
                  style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
              Text('Live aggregated readings per tank',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kSuccess.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kSuccess.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: _kSuccess, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('LIVE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: _kSuccess,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ]),
          ),
        ]),
      );

  // ── Alerts panel ───────────────────────────────────────────────────────────

  Widget _buildAlertsPanel() {
    final alerts = _todayOpenAlerts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header + filter bar
          Row(children: [
            Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                    color: _kDanger, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Text("TODAY'S TASKS",
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _kSub,
                      letterSpacing: 1.5)),
            ),
            if (alerts.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kDanger.withOpacity(0.35)),
                ),
                child: Text('${alerts.length}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: _kDanger,
                        fontWeight: FontWeight.w700)),
              ),
          ]),

          const SizedBox(height: 10),

          // Filter chips
          Row(children: [
            _FilterChip(
              label: 'By Time',
              icon: Icons.access_time_rounded,
              selected: _filter == _AlertFilter.time,
              onTap: () => setState(() {
                if (_filter == _AlertFilter.time) {
                  _filterAscending = !_filterAscending;
                } else {
                  _filter = _AlertFilter.time;
                  _filterAscending = false;
                }
              }),
              trailing: _filter == _AlertFilter.time
                  ? (_filterAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : null,
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: 'By Severity',
              icon: Icons.warning_amber_rounded,
              selected: _filter == _AlertFilter.severity,
              onTap: () => setState(() => _filter = _AlertFilter.severity),
            ),
          ]),

          const SizedBox(height: 10),

          // Alert cards or empty state
          if (alerts.isEmpty)
            _AlertsEmpty()
          else
            ...alerts.map((a) => _AlertCard(
                  alert: a,
                  onComplete: () => _showCompleteDialog(a),
                )),
        ],
      ),
    );
  }

  // ── Completed sections ─────────────────────────────────────────────────────

  Widget _buildCompletedSection(
    String title,
    List<_CompletedTask> tasks, {
    required bool isToday,
  }) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                    color: _kSuccess, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kSub,
                    letterSpacing: 1.5)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _kSuccess.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${tasks.length}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: _kSuccess,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          ...tasks.map((t) => _CompletedCard(task: t)),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.analytics_outlined, size: 52, color: _kSubL),
          const SizedBox(height: 14),
          Text('No tanks configured',
              style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w600, color: _kText)),
          const SizedBox(height: 6),
          Text('Add tanks in the Admin panel to see stats here',
              style: GoogleFonts.dmSans(fontSize: 13, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERT CARD
// ─────────────────────────────────────────────────────────────────────────────
