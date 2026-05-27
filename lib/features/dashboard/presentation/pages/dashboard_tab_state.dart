part of 'dashboard_tab.dart'; 

enum _DashboardReportRange { day, week, month, year }

extension _DashboardReportRangeX on _DashboardReportRange {
  String get label {
    switch (this) {
      case _DashboardReportRange.day:
        return 'Day';
      case _DashboardReportRange.week:
        return 'Week';
      case _DashboardReportRange.month:
        return 'Month';
      case _DashboardReportRange.year:
        return 'Year';
    }
  }
}

enum _DashboardReportType { abnormalities, completed, both }

extension _DashboardReportTypeX on _DashboardReportType {
  String get label {
    switch (this) {
      case _DashboardReportType.abnormalities:
        return 'Abnormalities';
      case _DashboardReportType.completed:
        return 'Completed';
      case _DashboardReportType.both:
        return 'Both';
    }
  }
}

class _DashboardTabState extends State<DashboardTab> {
  static const String _allTanksFilterId = '__all_tanks__';
  List<TankModel> _tanks = [];
  StreamSubscription<List<TankModel>>? _tankSub;
  final Map<String, GlobalKey> _tankCaptureKeys = {};
  final GlobalKey _alertsCaptureKey = GlobalKey();
  String? _exportingTankId;

  // Alerts
  List<_AlertModel> _allAlerts = [];
  List<_CompletedTask> _completed = [];
  StreamSubscription? _alertSub;
  StreamSubscription? _completedSub;
  _AlertFilter _filter = _AlertFilter.time;
  bool _filterAscending = false; // newest first for time
  bool _abnormalityExporting = false;
  _DashboardReportRange _abnormalityRange = _DashboardReportRange.day;
  _DashboardReportType _abnormalityType = _DashboardReportType.both;
  String _abnormalityTankId = _allTanksFilterId;

  DatabaseReference _ref(String path) => DatabaseModeService.ref(path);
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? _kDanger : _kSuccess,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tankSub = TankRepository().watchTanks().listen((tanks) {
      if (!mounted) return;
      setState(() {
        _tanks = tanks;
        final exists = tanks.any((t) => t.id == _abnormalityTankId);
        if (!exists && _abnormalityTankId != _allTanksFilterId) {
          _abnormalityTankId = _allTanksFilterId;
        }
      });
    });
    _subscribeAlerts();
    _subscribeCompleted();
  }

  Future<Uint8List?> _capture(GlobalKey key) async {
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 80));
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<Directory> _preferredExportDir() async {
    final down = await getDownloadsDirectory();
    if (down != null) return down;
    return getTemporaryDirectory();
  }

  Future<void> _downloadPng(GlobalKey key, String fileName) async {
    try {
      final bytes = await _capture(key);
      if (bytes == null) {
        _snack('Could not capture image. Please try again.', error: true);
        return;
      }
      final dir = await _preferredExportDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/$fileName-$ts.png');
      await file.writeAsBytes(bytes, flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: fileName);
    } catch (e) {
      _snack('PNG export failed: $e', error: true);
    }
  }

  Future<void> _downloadTankCardPng(TankModel tank, GlobalKey key) async {
    setState(() => _exportingTankId = tank.id);
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 120));
    await _downloadPng(key, 'dashboard_${tank.tankCode}');
    if (mounted) {
      setState(() => _exportingTankId = null);
    }
  }

  Future<void> _downloadDashboardPdf() async {
    try {
      final doc = pw.Document();
      final captures = <MapEntry<String, Uint8List>>[];
      final alerts = await _capture(_alertsCaptureKey);
      if (alerts != null) {
        captures.add(MapEntry('Alerts', alerts));
      }
      for (final tank in _tanks) {
        final key = _tankCaptureKeys[tank.id];
        if (key == null) continue;
        if (mounted) {
          setState(() => _exportingTankId = tank.id);
        }
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 120));
        final bytes = await _capture(key);
        if (bytes != null) {
          captures.add(MapEntry(tank.tankName, bytes));
        }
      }
      if (mounted) {
        setState(() => _exportingTankId = null);
      }
      if (captures.isEmpty) {
        _snack('No dashboard images available to export.', error: true);
        return;
      }
      for (final c in captures) {
        final image = pw.MemoryImage(c.value);
        doc.addPage(
          pw.Page(
            margin: const pw.EdgeInsets.all(24),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  c.key,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  width: double.infinity,
                  height: 700,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.5),
                  ),
                  child: pw.FittedBox(
                    fit: pw.BoxFit.contain,
                    child: pw.Image(image),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      final dir = await _preferredExportDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/dashboard_export_$ts.pdf');
      await file.writeAsBytes(await doc.save(), flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Dashboard PDF');
    } catch (e) {
      _snack('PDF export failed: $e', error: true);
    }
  }

  DateTimeRange _abnormalityWindow() {
    final now = DateTime.now();
    switch (_abnormalityRange) {
      case _DashboardReportRange.day:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case _DashboardReportRange.week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case _DashboardReportRange.month:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: now,
        );
      case _DashboardReportRange.year:
        return DateTimeRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: now,
        );
    }
  }

  bool _inRange(String? iso, DateTimeRange range) {
    if (iso == null || iso.isEmpty) return false;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return false;
    return !dt.isBefore(range.start) && !dt.isAfter(range.end);
  }

  bool _tankMatch(String? tankId) {
    if (_abnormalityTankId == _allTanksFilterId) return true;
    return tankId == _abnormalityTankId;
  }

  List<_AlertModel> _orderedAbnormalities(DateTimeRange range) {
    final alerts = _allAlerts
        .where((a) => !a.acknowledged)
        .where((a) => _tankMatch(a.tankId))
        .where((a) => _inRange(a.timestamp, range))
        .toList();

    switch (_filter) {
      case _AlertFilter.time:
        alerts.sort((a, b) => _filterAscending
            ? a.timestamp.compareTo(b.timestamp)
            : b.timestamp.compareTo(a.timestamp));
        break;
      case _AlertFilter.severity:
        alerts.sort(
          (a, b) => _sevOrder(a.severity).compareTo(_sevOrder(b.severity)),
        );
        break;
    }
    return alerts;
  }

  List<_CompletedTask> _orderedCompleted(DateTimeRange range) {
    final filtered = _completed
        .where((t) => _tankMatch(t.alert.tankId))
        .where((t) => _inRange(t.completedAt, range))
        .toList();

    final today = filtered.where((t) => _isToday(t.completedAt)).toList();
    final previous = filtered.where((t) => !_isToday(t.completedAt)).toList();
    return [...today, ...previous];
  }

  String _tankLabel(String tankId) {
    for (final t in _tanks) {
      if (t.id == tankId) return '${t.tankName} (${t.tankCode})';
    }
    return tankId;
  }

  String _fmtExcelTs(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(dt);
  }

  Future<void> _downloadAbnormalityExcel() async {
    setState(() => _abnormalityExporting = true);
    try {
      final window = _abnormalityWindow();
      final includeAlerts = _abnormalityType == _DashboardReportType.abnormalities ||
          _abnormalityType == _DashboardReportType.both;
      final includeCompleted = _abnormalityType == _DashboardReportType.completed ||
          _abnormalityType == _DashboardReportType.both;

      final alerts = includeAlerts ? _orderedAbnormalities(window) : <_AlertModel>[];
      final completed = includeCompleted ? _orderedCompleted(window) : <_CompletedTask>[];

      if (alerts.isEmpty && completed.isEmpty) {
        _snack('No records available for selected filters.', error: true);
        return;
      }

      final excel = xl.Excel.createExcel();
      final sheet = excel['Abnormality_Report'];
      if (excel.tables.containsKey('Sheet1') && 'Sheet1' != 'Abnormality_Report') {
        excel.delete('Sheet1');
      }

      sheet.appendRow([
        xl.TextCellValue('Range'),
        xl.TextCellValue(_abnormalityRange.label),
        xl.TextCellValue('Type'),
        xl.TextCellValue(_abnormalityType.label),
      ]);
      sheet.appendRow([
        xl.TextCellValue('From'),
        xl.TextCellValue(_fmtExcelTs(window.start.toIso8601String())),
        xl.TextCellValue('To'),
        xl.TextCellValue(_fmtExcelTs(window.end.toIso8601String())),
      ]);
      sheet.appendRow([
        xl.TextCellValue('Tank Filter'),
        xl.TextCellValue(
          _abnormalityTankId == _allTanksFilterId
              ? 'All Tanks'
              : _tankLabel(_abnormalityTankId),
        ),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
      ]);
      sheet.appendRow([
        xl.TextCellValue(''),
      ]);

      sheet.appendRow([
        xl.TextCellValue('Order'),
        xl.TextCellValue('Record Type'),
        xl.TextCellValue('Time'),
        xl.TextCellValue('Tank Code'),
        xl.TextCellValue('Tank Name'),
        xl.TextCellValue('Alert Title'),
        xl.TextCellValue('Severity'),
        xl.TextCellValue('Parameter'),
        xl.TextCellValue('Value'),
        xl.TextCellValue('Status'),
        xl.TextCellValue('Completed By'),
        xl.TextCellValue('Message'),
        xl.TextCellValue('Image URL'),
      ]);

      var order = 1;
      if (includeAlerts) {
        for (final a in alerts) {
          sheet.appendRow([
            xl.TextCellValue(order.toString()),
            xl.TextCellValue('Abnormality'),
            xl.TextCellValue(_fmtExcelTs(a.timestamp)),
            xl.TextCellValue(a.tankCode),
            xl.TextCellValue(a.tankName),
            xl.TextCellValue(a.alertTitle),
            xl.TextCellValue(a.severity),
            xl.TextCellValue(a.paramLabel),
            xl.TextCellValue(a.paramValue),
            xl.TextCellValue('Open'),
            xl.TextCellValue(''),
            xl.TextCellValue(a.message),
            xl.TextCellValue(a.imageUrl),
          ]);
          order++;
        }
      }

      if (includeCompleted) {
        for (final c in completed) {
          final a = c.alert;
          sheet.appendRow([
            xl.TextCellValue(order.toString()),
            xl.TextCellValue('Completed'),
            xl.TextCellValue(_fmtExcelTs(c.completedAt)),
            xl.TextCellValue(a.tankCode),
            xl.TextCellValue(a.tankName),
            xl.TextCellValue(a.alertTitle),
            xl.TextCellValue(a.severity),
            xl.TextCellValue(a.paramLabel),
            xl.TextCellValue(a.paramValue),
            xl.TextCellValue('Completed'),
            xl.TextCellValue(c.completedBy),
            xl.TextCellValue(a.message),
            xl.TextCellValue(a.imageUrl),
          ]);
          order++;
        }
      }

      final dir = await _preferredExportDir();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/dashboard_abnormality_report_$ts.xlsx');
      await file.writeAsBytes(excel.save()!, flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Dashboard Abnormality Report');
    } catch (e) {
      _snack('Abnormality export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _abnormalityExporting = false);
    }
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
    _alertSub = _ref('alerts').onValue.listen((event) {
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
    _completedSub = _ref('completed_tasks').onValue.listen((event) {
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
      final existing = await _ref('alerts/$alertId').get();
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
      await _ref('alerts/$alertId').set(alert);
      debugPrint('[Dashboard] Expected-avg alert written: $alertId');
    }
  }

  // ── Complete task ──────────────────────────────────────────────────────────

  Future<void> _completeAlert(_AlertModel alert, String completedByName) async {
    final taskId = 'task_${alert.id}';
    final now = DateTime.now().toIso8601String();

    // Write to completed_tasks/
    await _ref('completed_tasks/$taskId').set({
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
    await _ref('alerts/${alert.id}/acknowledged').set(true);
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
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    key: _alertsCaptureKey,
                    child: _buildAlertsPanel(),
                  ),
                ),

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
                      (_, i) {
                        final tank = _tanks[i];
                        final key = _tankCaptureKeys.putIfAbsent(
                            tank.id, () => GlobalKey());
                        return _TankStatsCard(
                          tank: tank,
                          captureKey: key,
                          forceExpandLastInspection:
                              _exportingTankId == tank.id,
                          onDownloadPng: () => _downloadTankCardPng(tank, key),
                        );
                      },
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

                SliverToBoxAdapter(child: _buildInspectionComplianceSection()),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _downloadPng(
                            _alertsCaptureKey,
                            'dashboard_alerts',
                          ),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Download Alerts as PNG'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _downloadDashboardPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Download Dashboard as PDF'),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kCard,
                            border: Border.all(color: _kBorder),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Abnormality Report Download',
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _kText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<_DashboardReportRange>(
                                value: _abnormalityRange,
                                decoration: const InputDecoration(
                                  labelText: 'Time Range',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _DashboardReportRange.values
                                    .map(
                                      (v) => DropdownMenuItem<_DashboardReportRange>(
                                        value: v,
                                        child: Text(v.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _abnormalityRange = v);
                                },
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<_DashboardReportType>(
                                value: _abnormalityType,
                                decoration: const InputDecoration(
                                  labelText: 'Data Type',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _DashboardReportType.values
                                    .map(
                                      (v) => DropdownMenuItem<_DashboardReportType>(
                                        value: v,
                                        child: Text(v.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _abnormalityType = v);
                                },
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                value: _abnormalityTankId,
                                decoration: const InputDecoration(
                                  labelText: 'Tank',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: _allTanksFilterId,
                                    child: Text('All Tanks'),
                                  ),
                                  ..._tanks.map(
                                    (t) => DropdownMenuItem<String>(
                                      value: t.id,
                                      child: Text('${t.tankName} (${t.tankCode})'),
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _abnormalityTankId = v);
                                },
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _abnormalityExporting
                                      ? null
                                      : _downloadAbnormalityExcel,
                                  icon: _abnormalityExporting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.table_view_rounded),
                                  label: Text(
                                    _abnormalityExporting
                                        ? 'Generating Excel...'
                                        : 'Download Abnormality Report (Excel)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

  String _tankRoute(TankModel t) => t.location?.trim().isNotEmpty == true
      ? '${t.location} / ${t.tankName}'
      : t.tankName;

  int _freqDays(TankModel t) {
    if (t.inspectionFrequencyDays > 0) return t.inspectionFrequencyDays;
    if (t.inspectionFrequencyType == 'weekly_once') return 7;
    if (t.inspectionFrequencyType == 'weekly_thrice') return 2;
    return 1;
  }

  bool _isCompliant(TankModel t, String? lastCapturedAt) {
    if (lastCapturedAt == null || lastCapturedAt.isEmpty) return false;
    final dt = DateTime.tryParse(lastCapturedAt);
    if (dt == null) return false;
    final now = DateTime.now();
    final diff = now.difference(dt.toLocal()).inDays;
    return diff < _freqDays(t);
  }

  Widget _buildInspectionComplianceSection() {
    return FutureBuilder<List<DashboardStatsModel>>(
      future: Future.wait(_tanks.map((t) => DashboardStatsRepository().getStats(t.id))),
      builder: (context, snap) {
        final stats = snap.data ?? const <DashboardStatsModel>[];
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
                        color: _kBlue, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Text('INSPECTION COMPLIANCE',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _kSub,
                        letterSpacing: 1.5)),
              ]),
              const SizedBox(height: 8),
              ..._tanks.asMap().entries.map((e) {
                final t = e.value;
                final s = e.key < stats.length ? stats[e.key] : DashboardStatsModel.empty(t.id);
                final ok = _isCompliant(t, s.lastCapturedAt);
                final c = ok ? _kSuccess : _kDanger;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.withOpacity(0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${t.tankName} (${t.tankCode})',
                                style: GoogleFonts.dmSans(
                                    color: _kText, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Tank id: ${t.id}',
                                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('Tank route: ${_tankRoute(t)}',
                                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(
                              'Last inspected: ${s.lastCapturedAt == null ? 'Never' : DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(s.lastCapturedAt!).toLocal())}',
                              style: GoogleFonts.dmSans(color: _kSub, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(ok ? Icons.check_circle : Icons.cancel, color: c),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALERT CARD
// ─────────────────────────────────────────────────────────────────────────────
