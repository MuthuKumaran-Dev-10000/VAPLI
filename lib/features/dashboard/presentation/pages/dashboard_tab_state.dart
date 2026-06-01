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

enum _DashboardPdfRange { current, week, month, custom }

extension _DashboardPdfRangeX on _DashboardPdfRange {
  String get label {
    switch (this) {
      case _DashboardPdfRange.current:
        return 'Current';
      case _DashboardPdfRange.week:
        return '1 week';
      case _DashboardPdfRange.month:
        return '1 month';
      case _DashboardPdfRange.custom:
        return 'Custom Time Range';
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
  _DashboardPdfRange _pdfRange = _DashboardPdfRange.current;
  DateTimeRange? _customPdfRange;

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
      await _auditExport('download_png', fileName, {
        'file_name': fileName,
        'bytes': bytes.length,
        'path': file.path,
      });
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

  DateTimeRange _reportWindow() {
    final now = DateTime.now();
    switch (_pdfRange) {
      case _DashboardPdfRange.current:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case _DashboardPdfRange.week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case _DashboardPdfRange.month:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
      case _DashboardPdfRange.custom:
        return _customPdfRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            );
    }
  }

  String _fmtPdfTs(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }

  String _fmtPdfDateOnly(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return DateFormat('dd MMM yyyy').format(dt);
  }

  String _fmtPdfNum(num? value) {
    if (value == null) return '-';
    final asDouble = value.toDouble();
    return asDouble == asDouble.truncateToDouble()
        ? asDouble.toInt().toString()
        : asDouble.toStringAsFixed(2);
  }

  String _fmtPdfAny(dynamic value) {
    if (value == null) return '-';
    if (value is Map) {
      final left = value['left']?.toString().trim() ?? '';
      final right = value['right']?.toString().trim() ?? '';
      final combined = '$left / $right'.trim();
      return combined == '/' ? '-' : combined;
    }
    if (value is num) return _fmtPdfNum(value);
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  bool _isTextualParamType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'text' ||
        normalized == 'multiline' ||
        normalized == 'dropdown' ||
        normalized == 'label';
  }

  Future<void> _pickCustomPdfRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _customPdfRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      helpText: 'Select report range',
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _customPdfRange = picked;
      _pdfRange = _DashboardPdfRange.custom;
    });
  }

  pw.Widget _pdfHeader(
    String title,
    String clientName,
    String subtitle,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.6, color: pdf.PdfColors.grey700),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: pdf.PdfColors.black,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                subtitle,
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: pdf.PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.Text(
            clientName,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(width: 0.6, color: pdf.PdfColors.grey700),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()),
            style: const pw.TextStyle(
              fontSize: 8,
              color: pdf.PdfColors.grey700,
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: pdf.PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String title, {String? subtitle}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                subtitle,
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: pdf.PdfColors.grey700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(
    String text, {
    bool header = false,
    pdf.PdfColor? fill,
    pw.Alignment alignment = pw.Alignment.centerLeft,
    double fontSize = 8.4,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      color: fill,
      alignment: alignment,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: header ? pw.FontWeight.bold : fontWeight,
        ),
      ),
    );
  }

  List<pw.TableRow> _buildComplianceRows(
    Map<String, DashboardStatsModel> statsByTank,
    DateTimeRange window,
  ) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
        children: [
          _pdfCell('Tank', header: true),
          _pdfCell('Route', header: true),
          _pdfCell('Freq', header: true),
          _pdfCell('Last Inspection', header: true),
          _pdfCell('Next Due', header: true),
          _pdfCell('Status', header: true),
        ],
      ),
    ];

    for (final tank in _tanks) {
      final stats = statsByTank[tank.id] ?? DashboardStatsModel.empty(tank.id);
      if (stats.lastCapturedAt == null) continue;
      final ok = _isCompliant(tank, stats.lastCapturedAt);
      final baseColor = ok
          ? pdf.PdfColor.fromInt(0xFFE8F5E9)
          : pdf.PdfColor.fromInt(0xFFFFEBEE);
      final last = stats.lastCapturedAt == null
          ? '-'
          : _fmtPdfTs(stats.lastCapturedAt);
      final lastDt = DateTime.tryParse(stats.lastCapturedAt ?? '');
      final nextDue = lastDt == null
          ? '-'
          : _fmtPdfDateOnly(lastDt.add(Duration(days: _freqDays(tank))).toIso8601String());
      rows.add(
        pw.TableRow(
          children: [
            _pdfCell('${tank.tankName} (${tank.tankCode})', fill: baseColor),
            _pdfCell(_tankRoute(tank), fill: baseColor),
            _pdfCell('${_freqDays(tank)} day(s)', fill: baseColor),
            _pdfCell(last, fill: baseColor),
            _pdfCell(nextDue, fill: baseColor),
            _pdfCell(ok ? 'On time' : 'Late', fill: baseColor),
          ],
        ),
      );
    }
    return rows;
  }

  List<pw.Widget> _buildTankStatsWidgets(Map<String, DashboardStatsModel> statsByTank) {
    final widgets = <pw.Widget>[];
    var addedTank = false;
    for (final tank in _tanks) {
      final stats = statsByTank[tank.id] ?? DashboardStatsModel.empty(tank.id);
      if (stats.lastCapturedAt == null) continue;
      if (addedTank) {
        widgets.add(pw.NewPage());
      }
      addedTank = true;
      widgets.add(
        _pdfSectionTitle(
          'Tank: ${tank.tankName} (${tank.tankCode})',
          subtitle: 'Last inspection: ${_fmtPdfTs(stats.lastCapturedAt)}',
        ),
      );
      final rows = <List<String>>[];
      for (final prop in tank.inspectionProperties) {
        final type = (prop['type'] as String?) ?? 'text';
        if (type == 'group') continue;
        final label = (prop['label'] as String?) ?? '';
        if (label.isEmpty) continue;
        final stat = stats.paramStats[label];
        final isTextual = _isTextualParamType(type);
        rows.add([
          label,
          type,
          _fmtPdfAny(stat?.lastValue ?? stats.lastReading[label]),
          isTextual ? '-' : _fmtPdfNum(stat?.avg),
          isTextual ? '-' : _fmtPdfNum(stat?.min),
          isTextual ? '-' : _fmtPdfNum(stat?.max),
          isTextual ? '-' : _fmtPdfAny(prop['expected_avg']),
          isTextual ? '-' : _fmtPdfAny(prop['expected_min']),
          isTextual ? '-' : _fmtPdfAny(prop['expected_max']),
        ]);
      }

      if (rows.isEmpty) {
        widgets.add(
          pw.Text(
            'No parameter data available.',
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        );
      } else {
        widgets.add(
          pw.Table.fromTextArray(
            headers: const [
              'Parameter',
              'Type',
              'Last Value',
              'Avg',
              'Min',
              'Max',
              'Expected Avg',
              'Expected Min',
              'Expected Max',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8.2,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.6),
            headerDecoration: const pw.BoxDecoration(
              color: pdf.PdfColors.grey300,
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(width: 0.4, color: pdf.PdfColors.grey400),
              ),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(2.6),
              1: const pw.FlexColumnWidth(0.9),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FlexColumnWidth(0.8),
              4: const pw.FlexColumnWidth(0.8),
              5: const pw.FlexColumnWidth(0.8),
              6: const pw.FlexColumnWidth(0.9),
              7: const pw.FlexColumnWidth(0.9),
              8: const pw.FlexColumnWidth(0.9),
            },
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 8));
    }
    if (!addedTank) {
      widgets.add(
        pw.Text(
          'No inspected tanks found in the selected range.',
          style: const pw.TextStyle(fontSize: 8.5),
        ),
      );
    }
    return widgets;
  }

  List<pw.Widget> _buildAlertWidgets({
    required List<_AlertModel> alerts,
    required List<_CompletedTask> completed,
    required bool includeCompleted,
  }) {
    final widgets = <pw.Widget>[];
    widgets.add(_pdfSectionTitle('Active Alerts'));
    if (alerts.isEmpty) {
      widgets.add(pw.Text('No alerts in selected range.', style: pw.TextStyle(fontSize: 8.5)));
    } else {
      final rows = alerts.map((a) {
        return [
          _fmtPdfTs(a.timestamp),
          '${a.tankName} (${a.tankCode})',
          a.severity,
          a.paramLabel,
          a.paramValue.isEmpty ? '-' : a.paramValue,
          a.capturedByName.isEmpty ? 'Dashboard' : a.capturedByName,
          a.message.isEmpty ? '-' : a.message,
        ];
      }).toList();
      widgets.add(
        pw.Table.fromTextArray(
          headers: const [
            'Time',
            'Tank',
            'Severity',
            'Parameter',
            'Value',
            'By',
            'Message',
          ],
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.2),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          headerDecoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
          rowDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 0.4, color: pdf.PdfColors.grey400)),
          ),
          cellAlignment: pw.Alignment.centerLeft,
        ),
      );
    }

    if (includeCompleted) {
      widgets.add(_pdfSectionTitle('Resolved Alerts'));
      if (completed.isEmpty) {
        widgets.add(pw.Text('No completed tasks in selected range.', style: pw.TextStyle(fontSize: 8.5)));
      } else {
        widgets.add(
          pw.Table.fromTextArray(
            headers: const ['Completed At', 'Tank', 'Severity', 'Parameter', 'Completed By', 'Message'],
            data: completed.map((c) {
              final a = c.alert;
              return [
                _fmtPdfTs(c.completedAt),
                '${a.tankName} (${a.tankCode})',
                a.severity,
                a.paramLabel,
                c.completedBy,
                a.message.isEmpty ? '-' : a.message,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.2),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            headerDecoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.4, color: pdf.PdfColors.grey400)),
            ),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        );
      }
    }
    return widgets;
  }

  List<pw.Widget> _buildInspectionReportWidgets(List<ReadingModel> readings) {
    final widgets = <pw.Widget>[];
    widgets.add(
      _pdfSectionTitle(
        'Inspection Compliance Detail',
        subtitle: 'Rows are highlighted green when the interval to the previous reading stays within the tank frequency, otherwise red.',
      ),
    );

    if (readings.isEmpty) {
      widgets.add(pw.Text('No readings in the selected range.', style: pw.TextStyle(fontSize: 8.5)));
      return widgets;
    }

    final byTank = <String, List<ReadingModel>>{};
    for (final reading in readings) {
      byTank.putIfAbsent(reading.tankId, () => []).add(reading);
    }

    var addedTank = false;
    for (final tank in _tanks) {
      final tankReadings = byTank[tank.id];
      if (tankReadings == null || tankReadings.isEmpty) continue;
      tankReadings.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      if (addedTank) {
        widgets.add(pw.NewPage());
      }
      addedTank = true;
      widgets.add(
        _pdfSectionTitle(
          '${tank.tankName} (${tank.tankCode})',
          subtitle: 'Frequency: every ${_freqDays(tank)} day(s)',
        ),
      );

      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
          children: [
            _pdfCell('Captured At', header: true),
            _pdfCell('Captured At Start', header: true),
            _pdfCell('Gap From Previous', header: true),
            _pdfCell('Allowed Gap', header: true),
            _pdfCell('Inspector', header: true),
            _pdfCell('Status', header: true),
          ],
        ),
      ];

      DateTime? previous;
      for (final reading in tankReadings) {
        final captured = DateTime.tryParse(reading.capturedAt)?.toLocal();
        final gap = previous == null || captured == null
            ? null
            : captured.difference(previous);
        final allowed = Duration(days: _freqDays(tank));
        final ok = previous == null ? true : gap != null && gap <= allowed;
        final rowColor = ok
            ? pdf.PdfColor.fromInt(0xFFE8F5E9)
            : pdf.PdfColor.fromInt(0xFFFFEBEE);
        rows.add(
          pw.TableRow(
            children: [
              _pdfCell(_fmtPdfTs(reading.capturedAt), fill: rowColor),
              _pdfCell(_fmtPdfTs(reading.capturedAtStart), fill: rowColor),
              _pdfCell(
                gap == null ? '-' : '${gap.inHours} hr ${gap.inMinutes.remainder(60)} m',
                fill: rowColor,
              ),
              _pdfCell('${allowed.inDays} day(s)', fill: rowColor),
              _pdfCell(reading.capturedByName.isEmpty ? '-' : reading.capturedByName, fill: rowColor),
              _pdfCell(ok ? 'On time' : 'Late', fill: rowColor),
            ],
          ),
        );
        if (captured != null) previous = captured;
      }

      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.3),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(1.0),
            3: pw.FlexColumnWidth(0.9),
            4: pw.FlexColumnWidth(1.0),
            5: pw.FlexColumnWidth(0.8),
          },
          children: rows,
        ),
      );
      widgets.add(pw.SizedBox(height: 8));
    }
    if (!addedTank) {
      widgets.add(
        pw.Text(
          'No tank readings were found for the selected window.',
          style: const pw.TextStyle(fontSize: 8.5),
        ),
      );
    }
    return widgets;
  }

  Future<void> _downloadDashboardPdf() async {
    try {
      final statsRepo = DashboardStatsRepository();
      final statsByTank = <String, DashboardStatsModel>{};
      for (final tank in _tanks) {
        statsByTank[tank.id] = await statsRepo.getStats(tank.id);
      }

      final openAlerts = _allAlerts.where((a) => !a.acknowledged).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final completed = List<_CompletedTask>.from(_completed);
      final generatedAt = _fmtPdfTs(DateTime.now().toIso8601String());
      final clientName = _tanks.isEmpty
          ? 'All Tanks'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard');
      final inspectedTanks = statsByTank.values.where((s) => s.lastCapturedAt != null).length;

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
          ),
          header: (_) => _pdfHeader(
            'Official Dashboard Report',
            clientName,
            'Generated: $generatedAt | Current dashboard summary and compliance snapshot.',
          ),
          footer: _pdfFooter,
          build: (_) => [
            _pdfSectionTitle(
              'Executive Summary',
              subtitle: 'Generated: $generatedAt',
            ),
            pw.Table.fromTextArray(
              headers: const ['Metric', 'Value'],
              data: [
                ['Tanks', _tanks.length.toString()],
                ['Inspected Tanks', inspectedTanks.toString()],
                ['Total Readings', statsByTank.values.fold<int>(0, (sum, s) => sum + s.count).toString()],
                ['Open Alerts', openAlerts.length.toString()],
                ['Resolved Alerts', completed.length.toString()],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2),
                1: pw.FlexColumnWidth(1.8),
              },
            ),
            pw.NewPage(),
            if (inspectedTanks > 0) ...[
              _pdfSectionTitle(
                'Inspection Compliance',
                subtitle: 'Tanks without a recorded inspection are omitted from the report.',
              ),
              pw.Table(
                border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
                children: _buildComplianceRows(statsByTank, _reportWindow()),
              ),
            ],
            ..._buildTankStatsWidgets(statsByTank),
            if (openAlerts.isNotEmpty || completed.isNotEmpty) pw.NewPage(),
            ..._buildAlertWidgets(
              alerts: openAlerts,
              completed: completed,
              includeCompleted: true,
            ),
          ],
        ),
      );

      final dir = await _preferredExportDir();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/dashboard_report_$ts.pdf');
      await file.writeAsBytes(await doc.save(), flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Dashboard Report PDF');
      await _auditExport('download_pdf', 'dashboard_report', {
        'format': 'pdf',
        'report_type': 'dashboard_snapshot',
        'path': file.path,
      });
    } catch (e) {
      _snack('PDF export failed: $e', error: true);
    }
  }

  Future<void> _downloadAlertsPdf() async {
    try {
      final window = _reportWindow();
      final alerts = _allAlerts
          .where((a) => _inRange(a.timestamp, window))
          .where((a) => _tankMatch(a.tankId))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final completed = _completed
          .where((c) => _inRange(c.completedAt, window))
          .where((c) => _tankMatch(c.alert.tankId))
          .toList();
      final generatedAt = _fmtPdfTs(DateTime.now().toIso8601String());

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
          ),
          header: (_) => _pdfHeader(
            'Official Alerts Report',
            'All Tanks',
            'Generated: $generatedAt | Tabular alert summary and resolved items.',
          ),
          footer: _pdfFooter,
          build: (_) => [
            _pdfSectionTitle(
              'Report Window',
              subtitle:
                  '${_fmtPdfDateOnly(window.start.toIso8601String())} to ${_fmtPdfDateOnly(window.end.toIso8601String())}',
            ),
            ..._buildAlertWidgets(
              alerts: alerts,
              completed: completed,
              includeCompleted: true,
            ),
          ],
        ),
      );

      final dir = await _preferredExportDir();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/alerts_report_$ts.pdf');
      await file.writeAsBytes(await doc.save(), flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Alerts Report PDF');
      await _auditExport('download_pdf', 'alerts_report', {
        'format': 'pdf',
        'report_type': 'alerts',
        'path': file.path,
      });
    } catch (e) {
      _snack('Alerts PDF export failed: $e', error: true);
    }
  }

  Future<void> _downloadInspectionReportPdf() async {
    try {
      final window = _reportWindow();
      final readings = await ReadingRepository().getAllReadings();
      final filtered = readings.where((r) {
        final dt = DateTime.tryParse(r.capturedAt);
        return dt != null && !dt.isBefore(window.start) && !dt.isAfter(window.end);
      }).toList();
      final generatedAt = _fmtPdfTs(DateTime.now().toIso8601String());

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
          ),
          header: (_) => _pdfHeader(
            'Official Inspection Report',
            'All Tanks',
            'Generated: $generatedAt | Detailed inspection compliance table.',
          ),
          footer: _pdfFooter,
          build: (_) => [
            _pdfSectionTitle(
              'Range',
              subtitle:
                  '${_fmtPdfDateOnly(window.start.toIso8601String())} to ${_fmtPdfDateOnly(window.end.toIso8601String())}',
            ),
            pw.NewPage(),
            ..._buildInspectionReportWidgets(filtered),
          ],
        ),
      );

      final dir = await _preferredExportDir();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/inspection_report_$ts.pdf');
      await file.writeAsBytes(await doc.save(), flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Inspection Report PDF');
      await _auditExport('download_pdf', 'inspection_report', {
        'format': 'pdf',
        'report_type': 'inspection',
        'range': _pdfRange.label,
        'path': file.path,
      });
    } catch (e) {
      _snack('Inspection PDF export failed: $e', error: true);
    }
  }

  Future<void> _auditExport(
    String operation,
    String label,
    Map<String, dynamic> details,
  ) async {
    try {
      final user = await SessionManager.getCurrentUser();
      await AuditLogService.record(
        operation: operation,
        entityType: 'dashboard_export',
        entityName: label,
        actorId: user?.id,
        actorUsername: user?.username,
        actorName: user?.fullName,
        actorRole: user?.role,
        tab: 'dashboard',
        details: {
          ...details,
          'summary': operation == 'download_png'
              ? 'Downloaded PNG export for $label'
              : 'Downloaded PDF export for $label',
        },
        summary: operation == 'download_png'
            ? 'Downloaded PNG export for $label'
            : 'Downloaded PDF export for $label',
      );
    } catch (_) {}
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
                          label: const Text('Download Dashboard Report (PDF)'),
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
                                'Professional Reports',
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _kText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<_DashboardPdfRange>(
                                value: _pdfRange,
                                decoration: const InputDecoration(
                                  labelText: 'Report Range',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _DashboardPdfRange.values
                                    .map(
                                      (v) => DropdownMenuItem<_DashboardPdfRange>(
                                        value: v,
                                        child: Text(v.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) async {
                                  if (v == null) return;
                                  if (v == _DashboardPdfRange.custom) {
                                    await _pickCustomPdfRange();
                                  } else {
                                    setState(() => _pdfRange = v);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _downloadAlertsPdf,
                                  icon: const Icon(Icons.notifications_outlined),
                                  label: const Text('Download Alerts PDF'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _downloadInspectionReportPdf,
                                  icon: const Icon(Icons.fact_check_outlined),
                                  label: const Text('Download Inspection Report'),
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
