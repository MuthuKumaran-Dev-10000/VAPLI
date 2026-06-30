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
  bool _filterTodayOnly = false; // "Today Only" filter toggle
  bool _abnormalityExporting = false;
  _DashboardReportRange _abnormalityRange = _DashboardReportRange.day;
  _DashboardReportType _abnormalityType = _DashboardReportType.both;
  String _abnormalityTankId = _allTanksFilterId;
  _DashboardPdfRange _pdfRange = _DashboardPdfRange.current;
  DateTimeRange? _customPdfRange;
  String _reportRangeMode = 'daily';
  String _reportFormat = 'pdf';
  String _reportType = 'inspection';
  String _alertFormatVal = 'pdf';
  String _inspectionFormatVal = 'pdf';

  // 🔖 Exporting state flags to prevent duplicate clicks and show loaders
  bool _dashboardPdfExporting = false;
  bool _alertsPdfExporting = false;
  bool _inspectionPdfExporting = false;
  bool _alertsPngExporting = false;
  bool _alertsSummaryExporting = false;

  // Dashboard settings visibility flags
  StreamSubscription? _settingsSub;
  bool _showInspectionValues = true;
  bool _showCompletedAlerts = true;
  bool _showActiveAlerts = true;
  bool _showInspectionCompliance = true;

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
    _subscribeSettings();
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
    final isAlerts = fileName == 'dashboard_alerts';
    if (isAlerts) {
      if (_alertsPngExporting) return;
      setState(() => _alertsPngExporting = true);
    }
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
    } finally {
      if (isAlerts && mounted) {
        setState(() => _alertsPngExporting = false);
      }
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

  String _fmtPdfNum(dynamic value) {
    if (value == null) return '-';
    double? asDouble;
    if (value is num) {
      asDouble = value.toDouble();
    } else if (value is String) {
      asDouble = double.tryParse(value);
    }
    if (asDouble == null) return '-';
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
          pw.Expanded(
            child: pw.Column(
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
          ),
          pw.SizedBox(width: 12),
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
    pw.Alignment? alignment,
    double fontSize = 8.4,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    pw.EdgeInsets? padding,
    pdf.PdfColor? textColor,
  }) {
    return pw.Container(
      padding: padding ?? const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      color: fill,
      alignment: alignment,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: header ? pw.FontWeight.bold : fontWeight,
          color: textColor,
        ),
      ),
    );
  }

  pw.Widget _pdfCellWidget(
    pw.Widget child, {
    pdf.PdfColor? fill,
    pw.Alignment? alignment,
    pw.EdgeInsets? padding,
  }) {
    return pw.Container(
      padding: padding ?? const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      color: fill,
      alignment: alignment,
      child: child,
    );
  }

  Map<String, dynamic>? _getTankParamProp(TankModel tank, String paramLabel) {
    for (final prop in tank.inspectionProperties) {
      final label = (prop['label'] ?? prop['name'] ?? '').toString();
      if (label == paramLabel) {
        return Map<String, dynamic>.from(prop);
      }
    }
    return null;
  }

  bool _shouldAbbreviateTitle(String title, bool compress, bool abbrTitlesEnabled) {
    if (!abbrTitlesEnabled) return false;
    if (!compress) return false;
    if (title.length <= 12) return false;
    return true;
  }

  bool _isNumericOrRange(String value) {
    final RegExp numericRangeRegExp = RegExp(r'^[0-9\.\-\/\+\s]+$');
    return numericRangeRegExp.hasMatch(value.trim());
  }

  bool _isCapturedToday(String? capturedAt) {
    if (capturedAt == null) return false;
    try {
      final dt = DateTime.parse(capturedAt).toLocal();
      final now = DateTime.now();
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    } catch (_) {
      return false;
    }
  }

  String _formatValueWithArrow(dynamic val, Map<String, dynamic>? paramProp, {bool forExcel = false}) {
    if (val == null) return '-';
    final valStr = _fmtPdfAny(val);
    if (valStr == '-') return '-';

    if (paramProp != null) {
      final type = paramProp['type']?.toString().toLowerCase() ?? '';
      if (type == 'number' || type == 'slider') {
        final expectedAvgVal = paramProp['expected_avg'];
        double? expectedAvg;
        if (expectedAvgVal is num) {
          expectedAvg = expectedAvgVal.toDouble();
        } else if (expectedAvgVal != null) {
          expectedAvg = double.tryParse(expectedAvgVal.toString());
        }

        double? valueDouble;
        if (val is num) {
          valueDouble = val.toDouble();
        } else {
          valueDouble = double.tryParse(val.toString());
        }

        if (expectedAvg != null && valueDouble != null) {
          if (valueDouble < expectedAvg) {
            return forExcel ? '$valStr \u2193' : '$valStr (v)'; // ↓ for Excel, (v) for PDF
          } else if (valueDouble > expectedAvg) {
            return forExcel ? '$valStr \u2191' : '$valStr (^)'; // ↑ for Excel, (^) for PDF
          }
        }
      }
    }
    return valStr;
  }

  pw.Widget _buildMultiColumnLegend(String title, Map<String, String> legendsMap) {
    if (legendsMap.isEmpty) return pw.SizedBox.shrink();
    
    final entries = legendsMap.entries.toList();
    const int colCount = 3;
    final int itemsPerCol = (entries.length / colCount).ceil();
    
    final columns = List.generate(colCount, (colIdx) {
      final start = colIdx * itemsPerCol;
      final end = (start + itemsPerCol < entries.length) ? start + itemsPerCol : entries.length;
      if (start >= entries.length) {
        return pw.Expanded(child: pw.SizedBox());
      }
      
      final colEntries = entries.sublist(start, end);
      return pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: colEntries.map((e) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '${e.value} = ${e.key}',
                style: const pw.TextStyle(fontSize: 6.5, color: pdf.PdfColors.grey800),
              ),
            );
          }).toList(),
        ),
      );
    });

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.0)),
          pw.SizedBox(height: 3),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: columns,
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfLegendChip(String text, pdf.PdfColor color) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 7,
          height: 7,
          color: color,
        ),
        pw.SizedBox(width: 3.5),
        pw.Text(text, style: const pw.TextStyle(fontSize: 7.2)),
      ],
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
          _pdfCell('Asset', header: true),
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
          'Asset: ${tank.tankName} (${tank.tankCode})',
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

  List<pw.Widget> _buildAlertWidgets({ // 🔖 Added/Refactored for Alert Image Link Support in PDF
    required List<_AlertModel> alerts,
    required List<_CompletedTask> completed,
    required bool includeCompleted,
  }) {
    final widgets = <pw.Widget>[];
    widgets.add(_pdfSectionTitle('Active Alerts'));
    if (alerts.isEmpty) {
      widgets.add(pw.Text('No alerts in selected range.', style: pw.TextStyle(fontSize: 8.5)));
    } else {
      final headerRow = pw.TableRow(
        decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
        children: [
          _pdfCell('Time', header: true),
          _pdfCell('Asset', header: true),
          _pdfCell('Severity', header: true),
          _pdfCell('Parameter', header: true),
          _pdfCell('Value', header: true),
          _pdfCell('By', header: true),
          _pdfCell('Message', header: true),
          _pdfCell('Images', header: true),
        ],
      );

      final dataRows = alerts.map((a) {
        final sevColor = a.severity.toLowerCase() == 'critical'
            ? pdf.PdfColor.fromInt(0xFFF2E6E6)
            : (a.severity.toLowerCase() == 'warning' ? pdf.PdfColor.fromInt(0xFFF7EAD7) : pdf.PdfColor.fromInt(0xFFECEFF1));
        final cleanVal = a.paramValue.replaceAll('↑', '(^)').replaceAll('↓', '(v)');
        final cleanMsg = a.message.replaceAll('↑', '(^)').replaceAll('↓', '(v)');
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: sevColor),
          children: [
            _pdfCell(_fmtPdfTs(a.timestamp), fill: sevColor),
            _pdfCell('${a.tankName} (${a.tankCode})', fill: sevColor),
            _pdfCell(a.severity.toUpperCase(), fill: sevColor, fontWeight: pw.FontWeight.bold),
            _pdfCell(a.paramLabel, fill: sevColor),
            _pdfCell(cleanVal.isEmpty ? '-' : cleanVal, fill: sevColor),
            _pdfCell(a.capturedByName.isEmpty ? 'Dashboard' : a.capturedByName, fill: sevColor),
            _pdfCell(cleanMsg.isEmpty ? '-' : cleanMsg, fill: sevColor),
            _buildAlertImageCell(a.imageUrl, fill: sevColor),
          ],
        );
      }).toList();

      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.3), // Time
            1: pw.FlexColumnWidth(1.5), // Tank
            2: pw.FlexColumnWidth(0.9), // Severity
            3: pw.FlexColumnWidth(1.2), // Parameter
            4: pw.FlexColumnWidth(0.9), // Value
            5: pw.FlexColumnWidth(1.1), // By
            6: pw.FlexColumnWidth(2.0), // Message
            7: pw.FlexColumnWidth(0.8), // Images
          },
          children: [headerRow, ...dataRows],
        ),
      );

      widgets.add(pw.SizedBox(height: 5));
      widgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            pw.Text('Color Coding Legend:  ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
            _pdfLegendChip('Critical', pdf.PdfColor.fromInt(0xFFF2E6E6)),
            pw.SizedBox(width: 8),
            _pdfLegendChip('Warning', pdf.PdfColor.fromInt(0xFFF7EAD7)),
            pw.SizedBox(width: 8),
            _pdfLegendChip('Info', pdf.PdfColor.fromInt(0xFFECEFF1)),
          ],
        ),
      );
    }

    if (includeCompleted) {
      widgets.add(pw.SizedBox(height: 14));
      widgets.add(_pdfSectionTitle('Resolved Alerts'));
      if (completed.isEmpty) {
        widgets.add(pw.Text('No completed tasks in selected range.', style: pw.TextStyle(fontSize: 8.5)));
      } else {
        final headerRow = pw.TableRow(
          decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
          children: [
            _pdfCell('Completed At', header: true),
            _pdfCell('Asset', header: true),
            _pdfCell('Severity', header: true),
            _pdfCell('Parameter', header: true),
            _pdfCell('Completed By', header: true),
            _pdfCell('Message', header: true),
            _pdfCell('Images', header: true),
          ],
        );

        final dataRows = completed.map((c) {
          final a = c.alert;
          final sevColor = a.severity.toLowerCase() == 'critical'
              ? pdf.PdfColor.fromInt(0xFFF2E6E6)
              : (a.severity.toLowerCase() == 'warning' ? pdf.PdfColor.fromInt(0xFFF7EAD7) : pdf.PdfColor.fromInt(0xFFECEFF1));
          final cleanVal = a.paramValue.replaceAll('↑', '(^)').replaceAll('↓', '(v)');
          final cleanMsg = a.message.replaceAll('↑', '(^)').replaceAll('↓', '(v)');
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: sevColor),
            children: [
              _pdfCell(_fmtPdfTs(c.completedAt), fill: sevColor),
              _pdfCell('${a.tankName} (${a.tankCode})', fill: sevColor),
              _pdfCell(a.severity.toUpperCase(), fill: sevColor, fontWeight: pw.FontWeight.bold),
              _pdfCell(a.paramLabel, fill: sevColor),
              _pdfCell(c.completedBy, fill: sevColor),
              _pdfCell(cleanMsg.isEmpty ? '-' : cleanMsg, fill: sevColor),
              _buildAlertImageCell(a.imageUrl, fill: sevColor),
            ],
          );
        }).toList();

        widgets.add(
          pw.Table(
            border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.3), // Completed At
              1: pw.FlexColumnWidth(1.5), // Tank
              2: pw.FlexColumnWidth(0.9), // Severity
              3: pw.FlexColumnWidth(1.2), // Parameter
              4: pw.FlexColumnWidth(1.2), // Completed By
              5: pw.FlexColumnWidth(2.2), // Message
              6: pw.FlexColumnWidth(0.8), // Images
            },
            children: [headerRow, ...dataRows],
          ),
        );

        widgets.add(pw.SizedBox(height: 5));
        widgets.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: [
              pw.Text('Color Coding Legend:  ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
              _pdfLegendChip('Critical', pdf.PdfColor.fromInt(0xFFF2E6E6)),
              pw.SizedBox(width: 8),
              _pdfLegendChip('Warning', pdf.PdfColor.fromInt(0xFFF7EAD7)),
              pw.SizedBox(width: 8),
              _pdfLegendChip('Info', pdf.PdfColor.fromInt(0xFFECEFF1)),
            ],
          ),
        );
      }
    }
    return widgets;
  }

  pw.Widget _buildAlertImageCell(String imageUrl, {pdf.PdfColor? fill}) { // 🔖 Added for Alert Image Link Support in PDF
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return _pdfCell('-', fill: fill);
    }
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      color: fill,
      alignment: pw.Alignment.centerLeft,
      child: pw.UrlLink(
        destination: imageUrl,
        child: pw.Text(
          '[Photo]',
          style: pw.TextStyle(
            fontSize: 7.5,
            color: pdf.PdfColors.blue800,
            decoration: pw.TextDecoration.underline,
          ),
        ),
      ),
    );
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

  // 🔖 Helper to collect all image URLs associated with a specific parameter in a reading
  List<String> _getParamImages(Map<String, dynamic> values, Map<String, dynamic> p) {
    final urls = <String>[];
    final id = p['id']?.toString() ?? '';
    final label = p['label']?.toString() ?? '';
    if (id.isEmpty && label.isEmpty) return urls;

    void addUrl(dynamic val) {
      final s = val?.toString().trim() ?? '';
      if (s.startsWith('http')) {
        urls.add(s);
      }
    }

    // 1. Check ID-based keys
    if (id.isNotEmpty) {
      addUrl(values['${id}__image_url']);
      for (final entry in values.entries) {
        final key = entry.key;
        if (key.startsWith('${id}__violation_') && key.endsWith('_image_url')) {
          addUrl(entry.value);
        }
      }
    }

    // 2. Check label-based keys
    if (label.isNotEmpty) {
      addUrl(values['${label}__image_url']);
      for (final entry in values.entries) {
        final key = entry.key;
        if (key.startsWith('manual_${label}_captured_image') || 
            (key.startsWith('${label}__violation_') && key.endsWith('_image_url'))) {
          addUrl(entry.value);
        }
      }
    }

    return urls;
  }

  // 🔖 Helper to build a cell displaying parameter value, trend arrow, and clickable image URLs
  pw.Widget _buildParameterCell(String text, List<String> images, {pw.Widget? trendIndicator}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Wrap(
            crossAxisAlignment: pw.WrapCrossAlignment.center,
            children: [
              pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
              if (trendIndicator != null) ...[
                pw.SizedBox(width: 3),
                trendIndicator,
              ],
            ],
          ),
          if (images.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            ...images.asMap().entries.map((e) {
              final idx = e.key + 1;
              final url = e.value;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1.5),
                child: pw.UrlLink(
                  destination: url,
                  child: pw.Text(
                    '[Photo $idx]',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: pdf.PdfColors.blue800,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // 🔖 Helper to build a clickable list of images in a separate column if needed
  pw.Widget _buildImagesCell(List<String> urls, {pdf.PdfColor? fill}) {
    if (urls.isEmpty) {
      return pw.Container(
        color: fill,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text('-', style: const pw.TextStyle(fontSize: 8)),
      );
    }
    return pw.Container(
      color: fill,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: urls.asMap().entries.map((e) {
          final idx = e.key + 1;
          final url = e.value;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.UrlLink(
              destination: url,
              child: pw.Text(
                'Link $idx',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: pdf.PdfColors.blue800,
                  decoration: pw.TextDecoration.underline,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _downloadDashboardPdf() async {
    if (_dashboardPdfExporting) return;
    setState(() => _dashboardPdfExporting = true);
    try {
      final statsRepo = DashboardStatsRepository();
      final statsByTank = <String, DashboardStatsModel>{};
      for (final tank in _tanks) {
        statsByTank[tank.id] = await statsRepo.getStats(tank.id);
      }

      final formatSettingsSnap = await DatabaseModeService.ref('settings/report_format').get();
      final formatSettings = formatSettingsSnap.exists && formatSettingsSnap.value != null
          ? Map<String, dynamic>.from(formatSettingsSnap.value as Map)
          : <String, dynamic>{};

      final openAlerts = _allAlerts.where((a) => !a.acknowledged).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final completed = List<_CompletedTask>.from(_completed);
      final generatedAt = DateFormat('dd MMMM yyyy - HH:mm').format(DateTime.now());
      
      final resolvedClient = await ClientContextService.resolveClientName();
      final clientName = resolvedClient ?? (_tanks.isEmpty
          ? 'All Assets'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard'));

      final window = _reportWindow();
      final readings = await ReadingRepository().getAllReadings();
      final filteredReadings = readings.where((r) {
        final dt = DateTime.tryParse(r.capturedAt);
        return dt != null && !dt.isBefore(window.start) && !dt.isAfter(window.end);
      }).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      final inspectedTanksCount = statsByTank.values.where((s) => s.lastCapturedAt != null).length;

      // 🔖 Fetch folder mappings from tree node repository
      final nodes = await TankTreeRepository().fetchAll();
      final folderNameMap = <String, String>{};
      for (final n in nodes) {
        if (n.isFolder) {
          folderNameMap[n.id] = n.name;
        }
      }
      final tankFolderMap = <String, String>{};
      for (final tank in _tanks) {
        final leaf = nodes.cast<TankNode?>().firstWhere(
              (n) => n != null && n.isLeaf && n.tankId == tank.id,
              orElse: () => null,
            );
        if (leaf != null && leaf.parentId != null) {
          tankFolderMap[tank.id] = folderNameMap[leaf.parentId] ?? 'General';
        } else {
          tankFolderMap[tank.id] = (tank.location?.trim().isNotEmpty == true) ? tank.location! : 'General';
        }
      }

      // Group tanks by folder
      final groupedTanks = <String, List<TankModel>>{};
      for (final tank in _tanks) {
        final folderName = tankFolderMap[tank.id] ?? 'General';
        groupedTanks.putIfAbsent(folderName, () => []).add(tank);
      }

      // Build records to show
      final records = <Map<String, dynamic>>[];
      if (_pdfRange == _DashboardPdfRange.current) {
        for (final tank in _tanks) {
          final stats = statsByTank[tank.id];
          if (stats != null && stats.lastCapturedAt != null && stats.lastReading.isNotEmpty) {
            records.add({
              'tankId': tank.id,
              'tankCode': tank.tankCode,
              'tankName': tank.tankName,
              'date': stats.lastCapturedAt!,
              'values': stats.lastReading,
              'inspector': stats.lastCapturedBy ?? '',
              'duplicateReason': stats.lastDuplicateReason ?? '',
            });
          }
        }
      } else {
        for (final r in filteredReadings) {
          final tank = _tanks.cast<TankModel?>().firstWhere(
                (t) => t != null && t.id == r.tankId,
                orElse: () => null,
              );
          if (tank != null) {
            records.add({
              'tankId': r.tankId,
              'tankCode': tank.tankCode,
              'tankName': tank.tankName,
              'date': r.capturedAt,
              'values': r.inspectionValues,
              'inspector': r.capturedByName,
              'duplicateReason': r.inspectionValues['duplicate_reason']?.toString() ?? r.inspectionValues['reason']?.toString() ?? '',
            });
          }
        }
      }

      final doc = pw.Document();
      
      // Page 1: Cover Sheet / Executive Summary only
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
          ),
          header: (_) => _pdfHeader(
            'Official Dashboard Report',
            clientName,
            'Generated: $generatedAt | Executive Summary and Compliance Snapshot.',
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
                ['Total Assets', _tanks.length.toString()],
                ['Inspected Assets Count', inspectedTanksCount.toString()],
                ['Total Readings Submitted', statsByTank.values.fold<int>(0, (sum, s) => sum + s.count).toString()],
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
          ],
        ),
      );

      // Subsequent pages: Group by Folder
      final sortedFolders = groupedTanks.keys.toList()..sort();
      for (final folderName in sortedFolders) {
        final folderTanks = groupedTanks[folderName] ?? [];
        final folderReadings = records.where((rec) => folderTanks.any((t) => t.id == rec['tankId'])).toList()
          ..sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));

        if (folderReadings.isEmpty) continue; // Skip empty folders

        // Collect parameters (labels) of assets in this folder, skipping 'group' type parameters
        final folderParams = <Map<String, dynamic>>[];
        final folderParamLabels = <String>[];
        for (final tank in folderTanks) {
          for (final prop in tank.inspectionProperties) {
            final type = prop['type'] as String? ?? 'text';
            if (type == 'group') continue;
            final label = prop['label'] as String? ?? '';
            if (label.isNotEmpty && !folderParamLabels.contains(label)) {
              folderParamLabels.add(label);
              folderParams.add(prop);
            }
          }
        }

        doc.addPage(
          pw.MultiPage(
            pageTheme: pw.PageTheme(
              pageFormat: pdf.PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
            ),
            header: (_) => _pdfHeader(
              'Official Dashboard Report',
              clientName,
              'Generated: $generatedAt | $folderName readings.',
            ),
            footer: _pdfFooter,
            build: (_) => [
              _pdfSectionTitle(folderName),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
                columnWidths: (() {
                  final colWidths = <int, pw.TableColumnWidth>{};
                  colWidths[0] = const pw.FlexColumnWidth(1.8); // Date
                  colWidths[1] = const pw.FlexColumnWidth(1.6); // Asset Name
                  int colIdx = 2;
                  for (final _ in folderParamLabels) {
                    colWidths[colIdx] = const pw.FlexColumnWidth(1.0); // Parameters
                    colIdx++;
                  }
                  colWidths[colIdx] = const pw.FlexColumnWidth(1.0); // Images
                  colWidths[colIdx + 1] = const pw.FlexColumnWidth(1.2); // Duplicate Reason
                  return colWidths;
                })(),
                children: [
                  // Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
                    children: [
                      _pdfCell('Date', header: true),
                      _pdfCell('Asset Name', header: true),
                      ...folderParamLabels.map((l) => _pdfCell(l, header: true)),
                      _pdfCell('Images', header: true),
                      _pdfCell('Duplicate Reason', header: true),
                    ],
                  ),
                  // Data Rows
                  ...folderReadings.map((rec) {
                    final tankId = rec['tankId'] as String;
                    final tankCode = rec['tankCode'] as String;
                    final tankName = rec['tankName'] as String;
                    final dateStr = DateFormat('dd MMMM yyyy - HH:mm').format(DateTime.parse(rec['date'] as String).toLocal());
                    final values = rec['values'] as Map<String, dynamic>;
                    final stats = statsByTank[tankId];

                    // Gather all manual capture image URLs for this reading record
                    final allImages = <String>[];
                    for (final p in folderParams) {
                      allImages.addAll(_getParamImages(values, p));
                    }

                    return pw.TableRow(
                      children: [
                        _pdfCell(dateStr),
                        _pdfCell('$tankName ($tankCode)'),
                        // Parameter columns with values and trend indicators + parameter specific image links
                        ...folderParams.map((p) {
                          final lbl = p['label'] as String;
                          final val = values[lbl];
                          final valText = _fmtPdfAny(val);
                          final pStats = stats?.paramStats[lbl];
                          
                          // Trend Indicator (red vector arrow)
                          pw.Widget? trendArrow;
                          final expAvg = p['expected_avg'];
                          double? expAvgVal;
                          if (expAvg is num) {
                            expAvgVal = expAvg.toDouble();
                          } else if (expAvg != null) {
                            expAvgVal = double.tryParse(expAvg.toString());
                          }

                          if (val != null && pStats != null && pStats.avg != null && expAvgVal != null) {
                            final numVal = double.tryParse(val.toString());
                            if (numVal != null) {
                              if (numVal > pStats.avg!) {
                                trendArrow = pw.CustomPaint(
                                  size: const pdf.PdfPoint(6, 6),
                                  painter: (canvas, size) {
                                    canvas.setFillColor(pdf.PdfColors.red500);
                                    canvas.moveTo(size.x / 2, size.y);
                                    canvas.lineTo(0, 0);
                                    canvas.lineTo(size.x, 0);
                                    canvas.fillPath();
                                  },
                                );
                              } else if (numVal < pStats.avg!) {
                                trendArrow = pw.CustomPaint(
                                  size: const pdf.PdfPoint(6, 6),
                                  painter: (canvas, size) {
                                    canvas.setFillColor(pdf.PdfColors.red500);
                                    canvas.moveTo(size.x / 2, 0);
                                    canvas.lineTo(0, size.y);
                                    canvas.lineTo(size.x, size.y);
                                    canvas.fillPath();
                                  },
                                );
                              }
                            }
                          }


                          // Param specific images under the value
                          final paramImages = _getParamImages(values, p);

                          return _buildParameterCell(valText, paramImages, trendIndicator: trendArrow);
                        }),
                        _buildImagesCell(allImages),
                        _pdfCell(rec['duplicateReason']?.toString() ?? '-'),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ],
          ),
        );
      }

      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final safeClient = clientName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final fileName = '${safeClient}_DashboardReport_$ts.pdf';

      final savedFile = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: await doc.save(),
        subPath: 'Reports/PDF',
        exportType: 'PDF Report',
        username: await _getCurrentUsername(),
        clientName: clientName,
      );

      await _showSaveSuccessDialog(savedFile, 'PDF Report');

      await _auditExport('download_pdf', 'dashboard_report', {
        'format': 'pdf',
        'report_type': 'dashboard_snapshot',
        'path': savedFile.path,
      });
    } catch (e) {
      _snack('PDF export failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _dashboardPdfExporting = false);
      }
    }
  }

  Future<void> _downloadAlertsPdf() async {
    if (_alertsPdfExporting) return;
    setState(() => _alertsPdfExporting = true);
    try {
      final window = _reportWindow();
      final alerts = _allAlerts
          .where((a) {
            final isActive = !a.acknowledged && a.status.toLowerCase() != 'completed';
            if (isActive) return _tankMatch(a.tankId);
            return _inRange(a.timestamp, window) && _tankMatch(a.tankId);
          })
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final completed = _completed
          .where((c) => _inRange(c.completedAt, window))
          .where((c) => _tankMatch(c.alert.tankId))
          .toList();
      final generatedAt = _fmtPdfTs(DateTime.now().toIso8601String());
      final resolvedClient = await ClientContextService.resolveClientName();
      final clientName = resolvedClient ?? (_tanks.isEmpty
          ? 'All Assets'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard'));

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4.portrait,
            margin: const pw.EdgeInsets.all(12),
          ),
          header: (_) => _pdfHeader(
            'Official Alerts Report',
            clientName,
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

      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final safeClient = clientName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final fileName = '${safeClient}_AlertsReport_$ts.pdf';

      final savedFile = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: await doc.save(),
        subPath: 'Reports/PDF',
        exportType: 'PDF Report',
        username: await _getCurrentUsername(),
        clientName: clientName,
      );

      await _showSaveSuccessDialog(savedFile, 'PDF Report');

      await _auditExport('download_pdf', 'alerts_report', {
        'format': 'pdf',
        'report_type': 'alerts',
        'path': savedFile.path,
      });
    } catch (e) {
      _snack('Alerts PDF export failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _alertsPdfExporting = false);
      }
    }
  }

  Future<Map<String, dynamic>> _fetchReportFormatConfigs() async {
    try {
      final snap = await DatabaseModeService.ref('settings/report_format').get();
      if (snap.exists && snap.value != null) {
        return Map<String, dynamic>.from(snap.value as Map);
      }
    } catch (e) {
      debugPrint('[PDF/Excel Export] Fetch format settings error: $e');
    }
    return {};
  }

  List<Map<String, dynamic>> _getSelectedParamsForFolder({
    required String folderId,
    required List<TankNode> allNodes,
    required List<TankModel> allTanks,
    required Map<String, dynamic> formatConfigs,
  }) {
    final folderConfig = formatConfigs[folderId] as Map?;
    final selectedParamsMap = folderConfig?['selected_params'] as Map?;

    final List<String> descendantTankIds = [];
    final children = allNodes.where((n) {
      if (folderId == 'root') {
        return (n.parentId == null || n.parentId == 'root') && n.isLeaf;
      } else {
        return n.parentId == folderId && n.isLeaf;
      }
    });
    for (final c in children) {
      if (c.tankId != null) {
        descendantTankIds.add(c.tankId!);
      }
    }
    final folderTanks = allTanks.where((t) => descendantTankIds.contains(t.id)).toList();

    final Map<String, Map<String, dynamic>> discovered = {};
    for (final tank in folderTanks) {
      for (final prop in tank.inspectionProperties) {
        final type = prop['type'] as String? ?? 'text';
        if (type == 'group') continue;
        
        final label = (prop['label'] ?? prop['name'] ?? '').toString();
        final options = List<String>.from(prop['options'] ?? []);
        options.sort();
        final key = '${label.trim()}_${type.trim()}';

        if (!discovered.containsKey(key)) {
          discovered[key] = {
            'key': key,
            'label': label,
            'type': type,
            'options': options,
            'selected': true,
            'order': 0,
          };
        }
      }
    }

    final List<Map<String, dynamic>> items = [];
    int maxDbOrder = 0;
    if (selectedParamsMap != null) {
      selectedParamsMap.forEach((k, v) {
        if (v is Map) {
          final sel = v['selected'] ?? true;
          final ord = (v['order'] as num?)?.toInt() ?? 0;
          if (sel == true && ord > maxDbOrder) {
            maxDbOrder = ord;
          }
        }
      });
    }

    discovered.forEach((key, item) {
      bool selected = true;
      int order = 0;
      if (selectedParamsMap != null && selectedParamsMap.containsKey(key)) {
        final map = selectedParamsMap[key] as Map?;
        selected = map?['selected'] ?? true;
        order = (map?['order'] as num?)?.toInt() ?? 0;
      }
      items.add({
        ...item,
        'selected': selected,
        'order': order,
      });
    });

    final selectedItems = items.where((i) => i['selected'] == true).toList();
    
    final configured = selectedItems.where((i) => i['order'] > 0).toList()
      ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    
    final unconfigured = selectedItems.where((i) => i['order'] == 0).toList()
      ..sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));

    final List<Map<String, dynamic>> finalResult = [];
    finalResult.addAll(configured);
    
    int nextOrder = maxDbOrder + 1;
    for (final item in unconfigured) {
      finalResult.add({
        ...item,
        'order': nextOrder++,
      });
    }

    return finalResult;
  }

  List<Map<String, dynamic>> _getViolationParamsForFolder({
    required String folderId,
    required List<TankNode> allNodes,
    required List<TankModel> allTanks,
    required Map<String, dynamic> formatConfigs,
  }) {
    final folderConfig = formatConfigs[folderId] as Map?;
    final violationParamsMap = folderConfig?['violation_params'] as Map?;

    final List<String> descendantTankIds = [];
    final children = allNodes.where((n) {
      if (folderId == 'root') {
        return (n.parentId == null || n.parentId == 'root') && n.isLeaf;
      } else {
        return n.parentId == folderId && n.isLeaf;
      }
    });
    for (final c in children) {
      if (c.tankId != null) {
        descendantTankIds.add(c.tankId!);
      }
    }
    final folderTanks = allTanks.where((t) => descendantTankIds.contains(t.id)).toList();

    final Map<String, Map<String, dynamic>> discovered = {};
    for (final tank in folderTanks) {
      for (final prop in tank.inspectionProperties) {
        final type = prop['type'] as String? ?? 'text';
        if (type == 'group') continue;
        
        final label = (prop['label'] ?? prop['name'] ?? '').toString();
        final options = List<String>.from(prop['options'] ?? []);
        options.sort();
        final key = '${label.trim()}_${type.trim()}';

        if (!discovered.containsKey(key)) {
          discovered[key] = {
            'key': key,
            'label': label,
            'type': type,
            'options': options,
            'selected': true,
            'order': 0,
          };
        }
      }
    }

    final List<Map<String, dynamic>> items = [];
    int maxDbOrder = 0;
    if (violationParamsMap != null) {
      violationParamsMap.forEach((k, v) {
        if (v is Map) {
          final sel = v['selected'] ?? true;
          final ord = (v['order'] as num?)?.toInt() ?? 0;
          if (sel == true && ord > maxDbOrder) {
            maxDbOrder = ord;
          }
        }
      });
    }

    discovered.forEach((key, item) {
      bool selected = true;
      int order = 0;
      if (violationParamsMap != null && violationParamsMap.containsKey(key)) {
        final map = violationParamsMap[key] as Map?;
        selected = map?['selected'] ?? true;
        order = (map?['order'] as num?)?.toInt() ?? 0;
      }
      items.add({
        ...item,
        'selected': selected,
        'order': order,
      });
    });

    final selectedItems = items.where((i) => i['selected'] == true).toList();
    
    final configured = selectedItems.where((i) => i['order'] > 0).toList()
      ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    
    final unconfigured = selectedItems.where((i) => i['order'] == 0).toList()
      ..sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));

    final List<Map<String, dynamic>> finalResult = [];
    finalResult.addAll(configured);
    
    int nextOrder = maxDbOrder + 1;
    for (final item in unconfigured) {
      finalResult.add({
        ...item,
        'order': nextOrder++,
      });
    }

    return finalResult;
  }

  bool _isReadingViolated(ReadingModel r, List<_AlertModel> openAlerts) {
    return openAlerts.any((a) => a.tankId == r.tankId);
  }

  String _cleanAssetName({
    required String tankName,
    required String folderId,
    required Map<String, dynamic> formatConfigs,
  }) {
    final folderConfig = formatConfigs[folderId] as Map?;
    if (folderConfig == null) return tankName;
    final stripText = folderConfig['strip_text']?.toString() ?? '';
    final stripPos = folderConfig['strip_position']?.toString() ?? 'start';

    if (stripText.isEmpty) return tankName;
    
    String clean = tankName;
    final lowerClean = clean.toLowerCase();
    final lowerStrip = stripText.toLowerCase();
    if (stripPos == 'start' && lowerClean.startsWith(lowerStrip)) {
      clean = clean.substring(stripText.length).trim();
    } else if (stripPos == 'end' && lowerClean.endsWith(lowerStrip)) {
      clean = clean.substring(0, clean.length - stripText.length).trim();
    }
    return clean;
  }

  DateTimeRange _inspectionReportWindow() {
    final now = DateTime.now();
    if (_reportRangeMode == 'daily') {
      return DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: now,
      );
    } else {
      final startDay = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      return DateTimeRange(
        start: startDay,
        end: now,
      );
    }
  }

  List<DateTime> _getDaysInWindow(DateTimeRange window) {
    final List<DateTime> days = [];
    var current = DateTime(window.start.year, window.start.month, window.start.day);
    final endDay = DateTime(window.end.year, window.end.month, window.end.day);
    while (!current.isAfter(endDay)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    return days;
  }

  String? _getTankActiveAlertSeverity(String tankId, List<dynamic> openAlerts) {
    final tankAlerts = openAlerts.where((a) => a.tankId == tankId).toList();
    if (tankAlerts.isEmpty) return null;
    if (tankAlerts.any((a) => a.severity.toLowerCase() == 'critical')) return 'critical';
    if (tankAlerts.any((a) => a.severity.toLowerCase() == 'warning')) return 'warning';
    return 'info';
  }

  pdf.PdfColor? _getRowColor(String? severity, {bool pending = false}) {
    if (pending) {
      return pdf.PdfColor.fromInt(0xFF81C784); // Vibrant Green
    }
    if (severity == null) return null;
    switch (severity.toLowerCase()) {
      case 'critical':
        return pdf.PdfColor.fromInt(0xFFE57373); // Vibrant Red
      case 'warning':
        return pdf.PdfColor.fromInt(0xFFFFD54F); // Vibrant Yellow
      case 'info':
        return pdf.PdfColor.fromInt(0xFF64B5F6); // Vibrant Blue
      default:
        return null;
    }
  }

  Future<void> _downloadInspectionReportPdf() async {
    if (_inspectionPdfExporting) return;
    setState(() => _inspectionPdfExporting = true);
    try {
      final window = _inspectionReportWindow();
      final readings = await ReadingRepository().getAllReadings();
      final filtered = readings.where((r) {
        final dt = DateTime.tryParse(r.capturedAt);
        return dt != null && !dt.isBefore(window.start) && !dt.isAfter(window.end);
      }).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      
      final generatedAt = DateFormat('dd MMMM yyyy - HH:mm').format(DateTime.now());

      final formatConfigs = await _fetchReportFormatConfigs();
      final Map<String, dynamic> localColorsCache = Map<String, dynamic>.from(formatConfigs['param_colors'] ?? {});
      final List<Map<String, dynamic>> pendingDbWrites = [];

      final nodes = await TankTreeRepository().fetchAll();
      final rootFolder = TankNode(
        id: 'root',
        type: 'folder',
        name: 'General',
        path: 'General',
        order: 0,
        createdAt: '',
      );

      final tankFolderMap = <String, TankNode>{};
      for (final n in nodes) {
        if (n.isLeaf && n.tankId != null) {
          final parent = nodes.cast<TankNode?>().firstWhere(
                (p) => p != null && p.isFolder && p.id == n.parentId,
                orElse: () => null,
              );
          if (parent != null) {
            tankFolderMap[n.tankId!] = parent;
          }
        }
      }

      final folderGroups = <String, List<TankModel>>{};
      for (final tank in _tanks) {
        final folder = tankFolderMap[tank.id] ?? rootFolder;
        folderGroups.putIfAbsent(folder.id, () => []).add(tank);
      }

      final sortedFolderIds = folderGroups.keys.toList()
        ..sort((a, b) {
          final nameA = (a == 'root') ? 'General' : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == a, orElse: () => null)?.name ?? 'General');
          final nameB = (b == 'root') ? 'General' : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == b, orElse: () => null)?.name ?? 'General');
          return nameA.compareTo(nameB);
        });

      final doc = pw.Document();

      final inspectedTankIds = filtered.map((r) => r.tankId).toSet();
      final inspectedTanks = _tanks.where((t) => inspectedTankIds.contains(t.id)).toList();
      final pendingTanks = _tanks.where((t) => !inspectedTankIds.contains(t.id)).toList();
      final openAlerts = _allAlerts.where((a) => !a.acknowledged && a.status.toLowerCase() != 'completed').toList();

      final resolvedClient = await ClientContextService.resolveClientName();
      final clientName = resolvedClient ?? (_tanks.isEmpty
          ? 'All Assets'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard'));

      final isTodaySelected = _pdfRange == _DashboardPdfRange.current;

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(12),
          ),
          header: (_) => _pdfHeader(
            'Official Inspection Report',
            clientName,
            'Summary Page | Generated: $generatedAt',
          ),
          footer: _pdfFooter,
          build: (_) {
            pw.TableRow buildStatsPlainRow(String labelText, String countVal) {
              return pw.TableRow(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    child: pw.Text(labelText, style: const pw.TextStyle(fontSize: 8)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      countVal,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            }

            pw.TableRow buildStatsLinkRow(String labelText, String countVal, String dest) {
              return pw.TableRow(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    child: pw.Text(labelText, style: const pw.TextStyle(fontSize: 8)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Link(
                      destination: dest,
                      child: pw.Text(
                        countVal,
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: pdf.PdfColors.blue800,
                          decoration: pw.TextDecoration.underline,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return [
              _pdfSectionTitle('Professional Inspection Summary'),
              pw.SizedBox(height: 6),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('General Info', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 4),
                        pw.Text('Report Mode: ${_reportRangeMode.toUpperCase()}', style: const pw.TextStyle(fontSize: 8, color: pdf.PdfColors.grey800)),
                        pw.Text('Report Date Range: ${DateFormat('dd MMM yyyy').format(window.start)} to ${DateFormat('dd MMM yyyy').format(window.end)}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Row(
                          children: [
                            pw.Text('Compliance Rate: ${_tanks.isEmpty ? '0.0%' : '${(inspectedTanks.length / _tanks.length * 100).toStringAsFixed(1)}%'}', style: const pw.TextStyle(fontSize: 8)),
                            pw.SizedBox(width: 8),
                            pw.Container(
                              height: 6,
                              width: 80,
                              decoration: const pw.BoxDecoration(
                                color: pdf.PdfColors.grey300,
                                borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                              ),
                              child: pw.Align(
                                alignment: pw.Alignment.centerLeft,
                                child: pw.Container(
                                  height: 6,
                                  width: 80 * (_tanks.isEmpty ? 0.0 : (inspectedTanks.length / _tanks.length)),
                                  decoration: pw.BoxDecoration(
                                    color: (inspectedTanks.length / (_tanks.isEmpty ? 1 : _tanks.length)) >= 0.8
                                        ? pdf.PdfColors.green
                                        : ((inspectedTanks.length / (_tanks.isEmpty ? 1 : _tanks.length)) >= 0.5 ? pdf.PdfColors.orange : pdf.PdfColors.red),
                                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 10),
                        pw.Text('Reading & Alert Statistics', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 4),
                        pw.Table(
                          border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
                          columnWidths: const {
                            0: pw.FlexColumnWidth(1.8),
                            1: pw.FlexColumnWidth(1.2),
                          },
                          children: [
                            pw.TableRow(
                              decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
                              children: [
                                _pdfCell('Metric', header: true, fontSize: 8),
                                _pdfCell('Count', header: true, fontSize: 8),
                              ],
                            ),
                            buildStatsPlainRow('Total Configured Assets', _tanks.length.toString()),
                            buildStatsPlainRow('Assets with Readings', inspectedTanks.length.toString()),
                            buildStatsPlainRow('Assets Pending Readings', pendingTanks.length.toString()),
                            buildStatsLinkRow('Active Unresolved Alerts (Click to view)', openAlerts.length.toString(), 'unresolved_alerts'),
                          ],
                        ),
                        pw.SizedBox(height: 8),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.start,
                          children: [
                            pw.Text('Color Coding Legend:  ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                            _pdfLegendChip('Critical', pdf.PdfColor.fromInt(0xFFE57373)),
                            pw.SizedBox(width: 8),
                            _pdfLegendChip('Warning', pdf.PdfColor.fromInt(0xFFFFD54F)),
                            pw.SizedBox(width: 8),
                            _pdfLegendChip('Info', pdf.PdfColor.fromInt(0xFF64B5F6)),
                            pw.SizedBox(width: 8),
                            _pdfLegendChip('Pending', pdf.PdfColor.fromInt(0xFF81C784)),
                          ],
                        ),
                        pw.SizedBox(height: 10),
                        pw.Text('Assets Pending Inspections (No Readings)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: pdf.PdfColors.red900)),
                        pw.SizedBox(height: 4),
                        if (pendingTanks.isEmpty)
                          pw.Text('No assets pending readings.', style: pw.TextStyle(fontSize: 8.0, color: pdf.PdfColors.green800, fontWeight: pw.FontWeight.bold))
                        else
                          pw.Table(
                            columnWidths: const {
                              0: pw.FlexColumnWidth(1.0),
                              1: pw.FlexColumnWidth(1.0),
                              2: pw.FlexColumnWidth(1.0),
                            },
                            children: List.generate((pendingTanks.length / 3).ceil(), (rowIdx) {
                              return pw.TableRow(
                                children: List.generate(3, (colIdx) {
                                  final idx = rowIdx * 3 + colIdx;
                                  if (idx < pendingTanks.length) {
                                    final t = pendingTanks[idx];
                                    return pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
                                      child: pw.Text(
                                        '- ${t.tankName} (${t.tankCode})',
                                        style: const pw.TextStyle(fontSize: 7.5, color: pdf.PdfColors.grey800),
                                      ),
                                    );
                                  } else {
                                    return pw.Container();
                                  }
                                }),
                              );
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final List<pw.Widget> detailedWidgets = [];
      detailedWidgets.add(
        pw.Anchor(
          name: 'combined_table',
          child: _pdfSectionTitle('ASSET INSPECTION DETAILED LIST'),
        ),
      );

      final abbrService = AbbreviationService();

      if (_reportRangeMode == 'daily') {
        Map<String, DashboardStatsModel> statsByTank = {};
        if (isTodaySelected) {
          for (final tank in _tanks) {
            statsByTank[tank.id] = await DashboardStatsRepository().getStats(tank.id);
          }
        }

        for (final folderId in sortedFolderIds) {
          final folderTanks = folderGroups[folderId]!..sort((a, b) => a.tankName.compareTo(b.tankName));
          final folderNode = (folderId == 'root') ? rootFolder : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == folderId, orElse: () => null) ?? rootFolder);

          final selectedParams = _getSelectedParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );
          final violationParams = _getViolationParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );

          if (selectedParams.isEmpty) continue;

          final folderConfig = formatConfigs[folderId] as Map?;
          final includeTimestamp = folderConfig?['include_timestamp'] == true;

          if (isTodaySelected) {
            final folderWidgets = _buildFolderInspectionSectionPdf(
              folderNode: folderNode,
              folderTanks: folderTanks,
              selectedParams: selectedParams,
              violationParams: violationParams,
              readings: [],
              isToday: true,
              statsByTank: statsByTank,
              openAlerts: openAlerts,
              includeTimestamp: includeTimestamp,
              formatConfigs: formatConfigs,
              abbrService: abbrService,
              localColorsCache: localColorsCache,
              pendingDbWrites: pendingDbWrites,
            );
            detailedWidgets.addAll(folderWidgets);
          } else {
            final folderTankIds = folderTanks.map((t) => t.id).toSet();
            final folderReadings = filtered.where((r) => folderTankIds.contains(r.tankId)).toList();
            final datesSet = folderReadings.map((r) {
              final dt = DateTime.parse(r.capturedAt).toLocal();
              return DateFormat('yyyy-MM-dd').format(dt);
            }).toSet().toList()
              ..sort((a, b) => b.compareTo(a));

            if (datesSet.isEmpty) {
              datesSet.add(DateFormat('yyyy-MM-dd').format(DateTime.now()));
            }

            for (final dateStr in datesSet) {
              final folderWidgets = _buildFolderInspectionSectionPdf(
                folderNode: folderNode,
                folderTanks: folderTanks,
                selectedParams: selectedParams,
                violationParams: violationParams,
                readings: filtered,
                isToday: false,
                statsByTank: {},
                openAlerts: openAlerts,
                includeTimestamp: includeTimestamp,
                formatConfigs: formatConfigs,
                abbrService: abbrService,
                localColorsCache: localColorsCache,
                pendingDbWrites: pendingDbWrites,
                dateStr: dateStr,
              );
              detailedWidgets.addAll(folderWidgets);
            }
          }
        }
      } else {
        final dayColors = [
          pdf.PdfColor.fromInt(0xFFE1BEE7), // Lavender
          pdf.PdfColor.fromInt(0xFFD1C4E9), // Soft Purple
          pdf.PdfColor.fromInt(0xFFF8BBD0), // Soft Pink
          pdf.PdfColor.fromInt(0xFFFFCC80), // Soft Peach
          pdf.PdfColor.fromInt(0xFFD7CCC8), // Soft Tan
          pdf.PdfColor.fromInt(0xFFB0BEC5), // Soft Slate
          pdf.PdfColor.fromInt(0xFFF5F5DC), // Soft Beige
        ];

        for (final folderId in sortedFolderIds) {
          final folderTanks = folderGroups[folderId]!..sort((a, b) => a.tankName.compareTo(b.tankName));
          final folderNode = (folderId == 'root') ? rootFolder : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == folderId, orElse: () => null) ?? rootFolder);

          final selectedParams = _getSelectedParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );
          final violationParams = _getViolationParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );

          if (selectedParams.isEmpty) continue;

          final folderConfig = formatConfigs[folderId] as Map?;
          final includeTimestamp = folderConfig?['include_timestamp'] == true;

          final folderTankIds = folderTanks.map((t) => t.id).toSet();
          final folderReadings = filtered.where((r) => folderTankIds.contains(r.tankId)).toList();

          final Set<String> activeDateStrings = {};
          for (final r in folderReadings) {
            final dt = DateTime.parse(r.capturedAt).toLocal();
            activeDateStrings.add(DateFormat('yyyy-MM-dd').format(dt));
          }
          final List<DateTime> days = activeDateStrings.map((s) => DateTime.parse(s)).toList()
            ..sort((a, b) => a.compareTo(b));

          if (days.isEmpty) {
            days.add(window.end);
          }

          final startLabel = DateFormat('dd/MM/yy').format(days.first);
          final endLabel = DateFormat('dd/MM/yy').format(days.last);
          final sectionTitle = '${folderNode.name} - $startLabel to $endLabel';

          final List<TankModel> normalTanks = [];
          final List<TankModel> violatedTanks = [];
          final List<ReadingModel> normalReadings = [];
          final List<ReadingModel> violatedReadings = [];

          for (final tank in folderTanks) {
            final hasAnyReadings = folderReadings.any((r) => r.tankId == tank.id);
            if (!hasAnyReadings) {
              normalTanks.add(tank);
            } else {
              final isViolated = openAlerts.any((a) => a.tankId == tank.id);
              if (isViolated) {
                violatedTanks.add(tank);
                violatedReadings.addAll(folderReadings.where((r) => r.tankId == tank.id));
              } else {
                normalTanks.add(tank);
                normalReadings.addAll(folderReadings.where((r) => r.tankId == tank.id));
              }
            }
          }

          if (normalTanks.isNotEmpty || violatedTanks.isEmpty) {
            final tableWidget = _buildPdfWeeklyTable(
              title: '$sectionTitle - Normal',
              tanks: normalTanks,
              params: selectedParams,
              readings: normalReadings,
              days: days,
              formatConfigs: formatConfigs,
              includeTimestamp: includeTimestamp,
              abbrService: abbrService,
              folderId: folderId,
              dayColors: dayColors,
              localColorsCache: localColorsCache,
              pendingDbWrites: pendingDbWrites,
            );
            detailedWidgets.add(
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(height: 8),
                    pw.Text('$sectionTitle - Normal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: pdf.PdfColors.blue900)),
                    pw.SizedBox(height: 3),
                    tableWidget,
                  ],
                ),
              ),
            );
          }

          if (violatedTanks.isNotEmpty) {
            final vParams = violationParams.isNotEmpty ? violationParams : selectedParams;
            final tableWidget = _buildPdfWeeklyTable(
              title: '$sectionTitle - Violated',
              tanks: violatedTanks,
              params: vParams,
              readings: violatedReadings,
              days: days,
              formatConfigs: formatConfigs,
              includeTimestamp: includeTimestamp,
              abbrService: abbrService,
              folderId: folderId,
              dayColors: dayColors,
              localColorsCache: localColorsCache,
              pendingDbWrites: pendingDbWrites,
            );
            detailedWidgets.add(
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(height: 8),
                    pw.Text('$sectionTitle - Violated', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: pdf.PdfColors.red900)),
                    pw.SizedBox(height: 3),
                    tableWidget,
                  ],
                ),
              ),
            );
          }
        }
      }

      if (abbrService.headerLegends.isNotEmpty || abbrService.valueLegends.isNotEmpty) {
        detailedWidgets.add(pw.SizedBox(height: 12));
        detailedWidgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildMultiColumnLegend('Title Abbreviations', abbrService.headerLegends),
                if (abbrService.headerLegends.isNotEmpty && abbrService.valueLegends.isNotEmpty)
                  pw.SizedBox(height: 8),
                _buildMultiColumnLegend('Abbreviations', abbrService.valueLegends),
              ],
            ),
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(12),
          ),
          header: (_) => _pdfHeader(
            'Official Inspection Report',
            clientName,
            'Asset Inspection Detailed List',
          ),
          footer: _pdfFooter,
          build: (_) => detailedWidgets,
        ),
      );

      final alertRows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
          children: [
            _pdfCell('Date / Time', header: true, fontSize: 8),
            _pdfCell('Asset Name', header: true, fontSize: 8),
            _pdfCell('Severity', header: true, fontSize: 8),
            _pdfCell('Parameter', header: true, fontSize: 8),
            _pdfCell('Value', header: true, fontSize: 8),
            _pdfCell('Message / Details', header: true, fontSize: 8),
          ],
        ),
      ];

      for (final a in openAlerts) {
        final alertDate = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(a.timestamp).toLocal());
        final sevColor = a.severity.toLowerCase() == 'critical'
            ? pdf.PdfColor.fromInt(0xFFF2E6E6)
            : (a.severity.toLowerCase() == 'warning' ? pdf.PdfColor.fromInt(0xFFF7EAD7) : pdf.PdfColor.fromInt(0xFFECEFF1));
        final cleanVal = a.paramValue.replaceAll('↑', '(^)').replaceAll('↓', '(v)');
        final cleanMsg = a.message.replaceAll('↑', '(^)').replaceAll('↓', '(v)');

        alertRows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(color: sevColor),
            children: [
              _pdfCell(alertDate, fill: sevColor, fontSize: 7.2),
              _pdfCell('${a.tankName} (${a.tankCode})', fill: sevColor, fontSize: 7.2),
              _pdfCell(a.severity.toUpperCase(), fill: sevColor, fontWeight: pw.FontWeight.bold, fontSize: 7.2),
              _pdfCell(a.paramLabel, fill: sevColor, fontSize: 7.2),
              _pdfCell(cleanVal.isEmpty ? '-' : cleanVal, fill: sevColor, fontSize: 7.2),
              _pdfCell(cleanMsg.isEmpty ? '-' : cleanMsg, fill: sevColor, fontSize: 7.0),
            ],
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(12),
          ),
          header: (_) => _pdfHeader(
            'Official Inspection Report',
            clientName,
            'Active Unresolved Alerts',
          ),
          footer: _pdfFooter,
          build: (_) => [
            pw.Anchor(
              name: 'unresolved_alerts',
              child: _pdfSectionTitle('ACTIVE UNRESOLVED ALERTS'),
            ),
            pw.SizedBox(height: 6),
            if (openAlerts.isEmpty)
              pw.Text('No active unresolved alerts found.', style: const pw.TextStyle(fontSize: 8.5))
            else ...[
              pw.Table(
                border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.0),
                  1: pw.FlexColumnWidth(1.2),
                  2: pw.FlexColumnWidth(0.8),
                  3: pw.FlexColumnWidth(1.0),
                  4: pw.FlexColumnWidth(0.8),
                  5: pw.FlexColumnWidth(2.2),
                },
                children: alertRows,
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  pw.Text('Color Coding Legend:  ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                  _pdfLegendChip('Critical', pdf.PdfColor.fromInt(0xFFF2E6E6)),
                  pw.SizedBox(width: 8),
                  _pdfLegendChip('Warning', pdf.PdfColor.fromInt(0xFFF7EAD7)),
                  pw.SizedBox(width: 8),
                  _pdfLegendChip('Info', pdf.PdfColor.fromInt(0xFFECEFF1)),
                ],
              ),
            ],
          ],
        ),
      );

      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final safeClient = clientName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final fileName = '${safeClient}_InspectionReport_$ts.pdf';

      _flushParamColors(pendingDbWrites);

      final savedFile = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: await doc.save(),
        subPath: 'Reports/PDF',
        exportType: 'PDF Report',
        username: await _getCurrentUsername(),
        clientName: clientName,
      );

      await _showSaveSuccessDialog(savedFile, 'PDF Report');

      await _auditExport('download_pdf', 'inspection_report', {
        'format': 'pdf',
        'report_type': 'inspections',
        'path': savedFile.path,
      });
    } catch (e, stack) {
      debugPrint('[PDF EXPORT ERROR] $e\n$stack');
      _snack('Inspection PDF export failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _inspectionPdfExporting = false);
      }
    }
  }

  Future<void> _downloadInspectionReportExcel() async {
    if (_inspectionPdfExporting) return;
    setState(() => _inspectionPdfExporting = true);
    try {
      final window = _inspectionReportWindow();
      final readings = await ReadingRepository().getAllReadings();
      final filtered = readings.where((r) {
        final dt = DateTime.tryParse(r.capturedAt);
        return dt != null && !dt.isBefore(window.start) && !dt.isAfter(window.end);
      }).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      final formatConfigs = await _fetchReportFormatConfigs();
      final Map<String, dynamic> localColorsCache = Map<String, dynamic>.from(formatConfigs['param_colors'] ?? {});
      final List<Map<String, dynamic>> pendingDbWrites = [];
      final nodes = await TankTreeRepository().fetchAll();
      final rootFolder = TankNode(
        id: 'root',
        type: 'folder',
        name: 'General',
        path: 'General',
        order: 0,
        createdAt: '',
      );

      final tankFolderMap = <String, TankNode>{};
      for (final n in nodes) {
        if (n.isLeaf && n.tankId != null) {
          final parent = nodes.cast<TankNode?>().firstWhere(
                (p) => p != null && p.isFolder && p.id == n.parentId,
                orElse: () => null,
              );
          if (parent != null) {
            tankFolderMap[n.tankId!] = parent;
          }
        }
      }

      final folderGroups = <String, List<TankModel>>{};
      for (final tank in _tanks) {
        final folder = tankFolderMap[tank.id] ?? rootFolder;
        folderGroups.putIfAbsent(folder.id, () => []).add(tank);
      }

      final sortedFolderIds = folderGroups.keys.toList()
        ..sort((a, b) {
          final nameA = (a == 'root') ? 'General' : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == a, orElse: () => null)?.name ?? 'General');
          final nameB = (b == 'root') ? 'General' : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == b, orElse: () => null)?.name ?? 'General');
          return nameA.compareTo(nameB);
        });

      final openAlerts = _allAlerts.where((a) => !a.acknowledged && a.status.toLowerCase() != 'completed').toList();

      final resolvedClient = await ClientContextService.resolveClientName();
      final clientName = resolvedClient ?? (_tanks.isEmpty
          ? 'All Assets'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard'));

      final isTodaySelected = _pdfRange == _DashboardPdfRange.current;
      Map<String, DashboardStatsModel> statsByTank = {};
      if (isTodaySelected) {
        for (final tank in _tanks) {
          statsByTank[tank.id] = await DashboardStatsRepository().getStats(tank.id);
        }
      }

      final excel = xl.Excel.createExcel();
      const sheetName = 'Inspection_Report';
      final sheet = excel[sheetName];
      if (excel.tables.containsKey('Sheet1') && 'Sheet1' != sheetName) {
        excel.delete('Sheet1');
      }

      void setCellBg(int colIdx, int rowIdx, String hexColor) {
        try {
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx));
          cell.cellStyle = xl.CellStyle(
            backgroundColorHex: xl.ExcelColor.fromHexString(hexColor),
          );
        } catch (e) {
          debugPrint('[Excel Export] Style error: $e');
        }
      }

      int currentRow = 0;

      sheet.appendRow([xl.TextCellValue('OFFICIAL INSPECTION REPORT')]);
      currentRow++;
      sheet.appendRow([xl.TextCellValue('Client Name: $clientName')]);
      currentRow++;
      sheet.appendRow([xl.TextCellValue('Report Mode: ${_reportRangeMode.toUpperCase()}')]);
      currentRow++;
      sheet.appendRow([xl.TextCellValue('Date Range: ${DateFormat('dd-MM-yyyy').format(window.start)} to ${DateFormat('dd-MM-yyyy').format(window.end)}')]);
      currentRow++;
      sheet.appendRow([xl.TextCellValue('Generated At: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}')]);
      currentRow++;
      sheet.appendRow([
        xl.TextCellValue('Color Coding Legend:'),
        xl.TextCellValue('Critical'),
        xl.TextCellValue('Warning'),
        xl.TextCellValue('Info'),
        xl.TextCellValue('Pending'),
      ]);
      setCellBg(1, currentRow, '#F2E6E6');
      setCellBg(2, currentRow, '#F7EAD7');
      setCellBg(3, currentRow, '#ECEFF1');
      setCellBg(4, currentRow, '#EAF2E8');
      currentRow++;
      sheet.appendRow([xl.TextCellValue('')]);
      currentRow++;

      final abbrService = AbbreviationService();

      if (_reportRangeMode == 'daily') {
        final refCurrentRowBox = [currentRow];
        for (final folderId in sortedFolderIds) {
          final folderTanks = folderGroups[folderId]!..sort((a, b) => a.tankName.compareTo(b.tankName));
          final folderNode = (folderId == 'root') ? rootFolder : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == folderId, orElse: () => null) ?? rootFolder);

          final selectedParams = _getSelectedParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );
          final violationParams = _getViolationParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );

          if (selectedParams.isEmpty) continue;

          final folderConfig = formatConfigs[folderId] as Map?;
          final includeTimestamp = folderConfig?['include_timestamp'] == true;

          if (isTodaySelected) {
            _buildFolderInspectionSectionExcel(
              sheet: sheet,
              folderNode: folderNode,
              folderTanks: folderTanks,
              selectedParams: selectedParams,
              violationParams: violationParams,
              readings: [],
              isToday: true,
              statsByTank: statsByTank,
              openAlerts: openAlerts,
              includeTimestamp: includeTimestamp,
              formatConfigs: formatConfigs,
              abbrService: abbrService,
              setCellBg: setCellBg,
              refCurrentRowBox: refCurrentRowBox,
              localColorsCache: localColorsCache,
              pendingDbWrites: pendingDbWrites,
            );
          } else {
            final folderTankIds = folderTanks.map((t) => t.id).toSet();
            final folderReadings = filtered.where((r) => folderTankIds.contains(r.tankId)).toList();
            final datesSet = folderReadings.map((r) {
              final dt = DateTime.parse(r.capturedAt).toLocal();
              return DateFormat('yyyy-MM-dd').format(dt);
            }).toSet().toList()
              ..sort((a, b) => b.compareTo(a));

            if (datesSet.isEmpty) {
              datesSet.add(DateFormat('yyyy-MM-dd').format(DateTime.now()));
            }

            for (final dateStr in datesSet) {
              _buildFolderInspectionSectionExcel(
                sheet: sheet,
                folderNode: folderNode,
                folderTanks: folderTanks,
                selectedParams: selectedParams,
                violationParams: violationParams,
                readings: filtered,
                isToday: false,
                statsByTank: {},
                openAlerts: openAlerts,
                includeTimestamp: includeTimestamp,
                formatConfigs: formatConfigs,
                abbrService: abbrService,
                setCellBg: setCellBg,
                refCurrentRowBox: refCurrentRowBox,
                localColorsCache: localColorsCache,
                pendingDbWrites: pendingDbWrites,
                dateStr: dateStr,
              );
            }
          }
        }
        currentRow = refCurrentRowBox[0];
      } else {
        final dayColors = [
          '#E1BEE7', // Lavender
          '#D1C4E9', // Soft Purple
          '#F8BBD0', // Soft Pink
          '#FFCC80', // Soft Peach
          '#D7CCC8', // Soft Tan
          '#B0BEC5', // Soft Slate
          '#F5F5DC', // Soft Beige
        ];

        final refCurrentRowBox = [currentRow];
        for (final folderId in sortedFolderIds) {
          final folderTanks = folderGroups[folderId]!..sort((a, b) => a.tankName.compareTo(b.tankName));
          final folderNode = (folderId == 'root') ? rootFolder : (nodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == folderId, orElse: () => null) ?? rootFolder);

          final selectedParams = _getSelectedParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );
          final violationParams = _getViolationParamsForFolder(
            folderId: folderId,
            allNodes: nodes,
            allTanks: _tanks,
            formatConfigs: formatConfigs,
          );

          if (selectedParams.isEmpty) continue;

          final folderConfig = formatConfigs[folderId] as Map?;
          final includeTimestamp = folderConfig?['include_timestamp'] == true;

          final folderTankIds = folderTanks.map((t) => t.id).toSet();
          final folderReadings = filtered.where((r) => folderTankIds.contains(r.tankId)).toList();

          final Set<String> activeDateStrings = {};
          for (final r in folderReadings) {
            final dt = DateTime.parse(r.capturedAt).toLocal();
            activeDateStrings.add(DateFormat('yyyy-MM-dd').format(dt));
          }
          final List<DateTime> days = activeDateStrings.map((s) => DateTime.parse(s)).toList()
            ..sort((a, b) => a.compareTo(b));

          if (days.isEmpty) {
            days.add(window.end);
          }

          _buildFolderWeeklyInspectionSectionExcel(
            sheet: sheet,
            folderNode: folderNode,
            folderTanks: folderTanks,
            selectedParams: selectedParams,
            violationParams: violationParams,
            readings: filtered,
            days: days,
            dayColors: dayColors,
            includeTimestamp: includeTimestamp,
            formatConfigs: formatConfigs,
            abbrService: abbrService,
            setCellBg: setCellBg,
            refCurrentRowBox: refCurrentRowBox,
            openAlerts: openAlerts,
            localColorsCache: localColorsCache,
            pendingDbWrites: pendingDbWrites,
          );
        }
        currentRow = refCurrentRowBox[0];
      }

      if (abbrService.headerLegends.isNotEmpty) {
        sheet.appendRow([xl.TextCellValue('')]);
        currentRow++;
        sheet.appendRow([xl.TextCellValue('Title Abbreviations:')]);
        currentRow++;
        for (final entry in abbrService.headerLegends.entries) {
          sheet.appendRow([xl.TextCellValue(entry.value), xl.TextCellValue(entry.key)]);
          currentRow++;
        }
      }

      if (abbrService.valueLegends.isNotEmpty) {
        sheet.appendRow([xl.TextCellValue('')]);
        currentRow++;
        sheet.appendRow([xl.TextCellValue('Abbreviations:')]);
        currentRow++;
        for (final entry in abbrService.valueLegends.entries) {
          sheet.appendRow([xl.TextCellValue(entry.value), xl.TextCellValue(entry.key)]);
          currentRow++;
        }
      }

      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final safeClient = clientName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final fileName = '${safeClient}_InspectionReport_$ts.xlsx';

      _flushParamColors(pendingDbWrites);

      final excelBytes = excel.save()!;
      final savedFile = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: excelBytes,
        subPath: 'Reports/Excel',
        exportType: 'Excel Report',
        username: await _getCurrentUsername(),
        clientName: clientName,
      );

      await _showSaveSuccessDialog(savedFile, 'Excel Report');

      await _auditExport('download_excel', 'inspection_report', {
        'format': 'xlsx',
        'report_type': 'inspections',
        'path': savedFile.path,
      });
    } catch (e, stack) {
      debugPrint('[EXCEL EXPORT ERROR] $e\n$stack');
      _snack('Inspection Excel export failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _inspectionPdfExporting = false);
      }
    }
  }


  Future<void> _downloadAbnormalityExcel() async { // 🔖 Added/Refactored for Alerts Excel Export
    if (_abnormalityExporting) return;
    setState(() => _abnormalityExporting = true);
    try {
      final window = _abnormalityWindow();
      final activeAlerts = _allAlerts
          .where((a) {
            final isActive = !a.acknowledged && a.status.toLowerCase() != 'completed';
            if (isActive) return _tankMatch(a.tankId);
            return _inRange(a.timestamp, window) && _tankMatch(a.tankId);
          })
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final completedAlerts = _completed
          .where((c) => _inRange(c.completedAt, window))
          .where((c) => _tankMatch(c.alert.tankId))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

      final resolvedClient = await ClientContextService.resolveClientName();
      final clientName = resolvedClient ?? (_tanks.isEmpty
          ? 'All Assets'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard'));

      final excel = xl.Excel.createExcel();

      // Setup sheets based on _abnormalityType
      final showActive = _abnormalityType == _DashboardReportType.abnormalities || _abnormalityType == _DashboardReportType.both;
      final showCompleted = _abnormalityType == _DashboardReportType.completed || _abnormalityType == _DashboardReportType.both;

      // Summary Sheet
      final summarySheet = excel['Summary'];
      if (excel.tables.containsKey('Sheet1') && 'Sheet1' != 'Summary') {
        excel.delete('Sheet1');
      }

      int summaryRow = 0;
      summarySheet.appendRow([
        xl.TextCellValue('Metric'),
        xl.TextCellValue('Value'),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Client Name'),
        xl.TextCellValue(clientName),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Generated At'),
        xl.TextCellValue(DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.now())),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Time Range'),
        xl.TextCellValue(_abnormalityRange.label),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Start Date'),
        xl.TextCellValue(DateFormat('dd-MM-yyyy HH:mm:ss').format(window.start.toLocal())),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('End Date'),
        xl.TextCellValue(DateFormat('dd-MM-yyyy HH:mm:ss').format(window.end.toLocal())),
      ]);
      summaryRow++;
      if (showActive) {
        summarySheet.appendRow([
          xl.TextCellValue('Active Alerts'),
          xl.TextCellValue(activeAlerts.length.toString()),
        ]);
        summaryRow++;
      }
      if (showCompleted) {
        summarySheet.appendRow([
          xl.TextCellValue('Resolved Alerts'),
          xl.TextCellValue(completedAlerts.length.toString()),
        ]);
        summaryRow++;
      }

      summarySheet.appendRow([xl.TextCellValue('')]);
      summaryRow++;

      summarySheet.appendRow([
        xl.TextCellValue('Color Coding Legend:'),
        xl.TextCellValue('Critical'),
        xl.TextCellValue('Warning'),
        xl.TextCellValue('Info'),
      ]);

      void setSummaryCellBg(int col, int row, String hex) {
        try {
          summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).cellStyle = xl.CellStyle(
            backgroundColorHex: xl.ExcelColor.fromHexString(hex),
          );
        } catch (_) {}
      }
      setSummaryCellBg(1, summaryRow, '#F2E6E6');
      setSummaryCellBg(2, summaryRow, '#F7EAD7');
      setSummaryCellBg(3, summaryRow, '#ECEFF1');
      summaryRow++;

      // Active Alerts Sheet
      if (showActive) {
        final activeSheet = excel['Active Alerts'];
        int activeRow = 0;
        activeSheet.appendRow([
          xl.TextCellValue('Time'),
          xl.TextCellValue('Asset Name'),
          xl.TextCellValue('Asset Code'),
          xl.TextCellValue('Severity'),
          xl.TextCellValue('Parameter'),
          xl.TextCellValue('Value'),
          xl.TextCellValue('Created By'),
          xl.TextCellValue('Message'),
          xl.TextCellValue('Image URL'),
        ]);
        for (int col = 0; col < 9; col++) {
          try {
            activeSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: activeRow)).cellStyle = xl.CellStyle(
              backgroundColorHex: xl.ExcelColor.fromHexString('#ECEFF1'),
            );
          } catch (_) {}
        }
        activeRow++;

        for (final a in activeAlerts) {
          final dateStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(a.timestamp).toLocal());
          activeSheet.appendRow([
            xl.TextCellValue(dateStr),
            xl.TextCellValue(a.tankName),
            xl.TextCellValue(a.tankCode),
            xl.TextCellValue(a.severity.toUpperCase()),
            xl.TextCellValue(a.paramLabel),
            xl.TextCellValue(a.paramValue.isEmpty ? '-' : a.paramValue),
            xl.TextCellValue(a.capturedByName.isEmpty ? 'Dashboard' : a.capturedByName),
            xl.TextCellValue(a.message.isEmpty ? '-' : a.message),
            xl.TextCellValue(a.imageUrl),
          ]);

          final hex = a.severity.toLowerCase() == 'critical'
              ? '#F2E6E6'
              : (a.severity.toLowerCase() == 'warning' ? '#F7EAD7' : '#ECEFF1');
          for (int col = 0; col < 9; col++) {
            try {
              activeSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: activeRow)).cellStyle = xl.CellStyle(
                backgroundColorHex: xl.ExcelColor.fromHexString(hex),
              );
            } catch (_) {}
          }
          activeRow++;
        }
      }

      // Completed Alerts Sheet
      if (showCompleted) {
        final completedSheet = excel['Completed Alerts'];
        int completedRow = 0;
        completedSheet.appendRow([
          xl.TextCellValue('Completed At'),
          xl.TextCellValue('Alert Time'),
          xl.TextCellValue('Asset Name'),
          xl.TextCellValue('Asset Code'),
          xl.TextCellValue('Severity'),
          xl.TextCellValue('Parameter'),
          xl.TextCellValue('Value'),
          xl.TextCellValue('Created By'),
          xl.TextCellValue('Resolved By'),
          xl.TextCellValue('Message'),
          xl.TextCellValue('Image URL'),
        ]);
        for (int col = 0; col < 11; col++) {
          try {
            completedSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: completedRow)).cellStyle = xl.CellStyle(
              backgroundColorHex: xl.ExcelColor.fromHexString('#ECEFF1'),
            );
          } catch (_) {}
        }
        completedRow++;

        for (final c in completedAlerts) {
          final a = c.alert;
          final compDateStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(c.completedAt).toLocal());
          final alertDateStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(a.timestamp).toLocal());
          completedSheet.appendRow([
            xl.TextCellValue(compDateStr),
            xl.TextCellValue(alertDateStr),
            xl.TextCellValue(a.tankName),
            xl.TextCellValue(a.tankCode),
            xl.TextCellValue(a.severity.toUpperCase()),
            xl.TextCellValue(a.paramLabel),
            xl.TextCellValue(a.paramValue.isEmpty ? '-' : a.paramValue),
            xl.TextCellValue(a.capturedByName.isEmpty ? 'Dashboard' : a.capturedByName),
            xl.TextCellValue(c.completedBy),
            xl.TextCellValue(a.message.isEmpty ? '-' : a.message),
            xl.TextCellValue(a.imageUrl),
          ]);

          final hex = a.severity.toLowerCase() == 'critical'
              ? '#F2E6E6'
              : (a.severity.toLowerCase() == 'warning' ? '#F7EAD7' : '#ECEFF1');
          for (int col = 0; col < 11; col++) {
            try {
              completedSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: completedRow)).cellStyle = xl.CellStyle(
                backgroundColorHex: xl.ExcelColor.fromHexString(hex),
              );
            } catch (_) {}
          }
          completedRow++;
        }
      }

      final dir = await _preferredExportDir();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/abnormality_report_$ts.xlsx');
      await file.writeAsBytes(excel.save()!, flush: true);
      _snack('Saved: ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Abnormality Report Excel');
      await _auditExport('download_excel', 'abnormality_report', {
        'format': 'xlsx',
        'report_type': 'abnormalities',
        'path': file.path,
      });
    } catch (e) {
      _snack('Abnormality Excel export failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _abnormalityExporting = false);
      }
    }
  }

  // 🔖 Restored helper methods for auditing and filtering dashboard tasks
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

  @override
  void dispose() {
    _tankSub?.cancel();
    _alertSub?.cancel();
    _completedSub?.cancel();
    _settingsSub?.cancel();
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

  void _subscribeSettings() {
    _settingsSub?.cancel();
    _settingsSub = _ref('settings/dashboard_display').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        if (mounted) {
          setState(() {
            _showInspectionValues = true;
            _showCompletedAlerts = true;
            _showActiveAlerts = true;
            _showInspectionCompliance = true;
          });
        }
        return;
      }
      try {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        if (mounted) {
          setState(() {
            _showInspectionValues = data['show_inspection_values'] ?? true;
            _showCompletedAlerts = data['show_completed_alerts'] ?? true;
            _showActiveAlerts = data['show_active_alerts'] ?? true;
            _showInspectionCompliance = data['show_inspection_compliance'] ?? true;
          });
        }
      } catch (_) {
        // Fallbacks
      }
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
        'status': 'active', // 🔖 Added for Alert Lifecycle Bug Fix
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
        'status': 'COMPLETED', // 🔖 Added for Alert Lifecycle Bug Fix
        'if_then': alert.ifThen,
        'reading_id': alert.readingId,
      },
    });

    // Mark acknowledged and status: COMPLETED in alerts/
    await _ref('alerts/${alert.id}').update({
      'acknowledged': true,
      'status': 'COMPLETED', // 🔖 Added for Alert Lifecycle Bug Fix
    });
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
    var open = _allAlerts
        .where((a) => !a.acknowledged && a.status.toLowerCase() != 'completed')
        .toList();

    if (_filterTodayOnly) {
      open = open.where((a) => _isToday(a.timestamp)).toList();
    }

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

                // ── Download buttons and time range selectors (At the TOP!) ──
                SliverToBoxAdapter(child: _buildDownloadButtonsSection()),

                // ── Today's Tasks (alerts) ────────────────────────────────
                if (_showActiveAlerts)
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      key: _alertsCaptureKey,
                      child: _buildAlertsPanel(),
                    ),
                  ),

                // ── Completed Today ───────────────────────────────────────
                if (_showCompletedAlerts)
                  SliverToBoxAdapter(
                      child: _buildCompletedSection(
                    'TASKS COMPLETED TODAY',
                    _completedToday,
                    isToday: true,
                  )),

                // ── Completed Previous ────────────────────────────────────
                if (_showCompletedAlerts)
                  SliverToBoxAdapter(
                      child: _buildCompletedSection(
                    'PREVIOUS DAYS',
                    _completedPrevious,
                    isToday: false,
                  )),

                // ── Summary strip ─────────────────────────────────────────
                if (_showInspectionValues)
                  SliverToBoxAdapter(
                      child: _SummaryStrip(
                    tankCount: _tanks.length,
                    tanks: _tanks,
                    onStatsReady: _checkExpectedAvgAlerts,
                  )),

                // ── Tank cards ────────────────────────────────────────────
                if (_showInspectionValues)
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

                // ── Inspection Compliance ─────────────────────────────────
                if (_showInspectionCompliance)
                  SliverToBoxAdapter(child: _buildInspectionComplianceSection()),
              ],
            ),
    );
  }

  Widget _buildDownloadButtonsSection() {
    final bool isExporting = _inspectionPdfExporting || _alertsPdfExporting || _dashboardPdfExporting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
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
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kText,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 14),

                // Report Range
                Text(
                  'Report Range',
                  style: GoogleFonts.inter(
                    color: _kSub,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<_DashboardPdfRange>(
                  value: _pdfRange,
                  dropdownColor: _kSurface,
                  style: GoogleFonts.inter(color: _kText, fontSize: 13),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kCopper),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  onChanged: isExporting
                      ? null
                      : (v) async {
                          if (v == null) return;
                          if (v == _DashboardPdfRange.custom) {
                            await _pickCustomPdfRange();
                          } else {
                            setState(() => _pdfRange = v);
                          }
                        },
                ),
                const SizedBox(height: 16),

                // Download Alert Summary Button and Format Dropdown
                Text(
                  'Alerts Report',
                  style: GoogleFonts.inter(
                    color: _kSub,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kCopper,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _kCopper.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: isExporting
                              ? null
                              : () {
                                  if (_alertFormatVal == 'pdf') {
                                    _downloadAlertsPdf();
                                  } else {
                                    _downloadAlertsExcel();
                                  }
                                },
                          icon: isExporting && _alertsPdfExporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            'Download Alert Summary',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<String>(
                          value: _alertFormatVal,
                          dropdownColor: _kSurface,
                          style: GoogleFonts.inter(color: _kText, fontSize: 13),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kCopper),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                            DropdownMenuItem(value: 'excel', child: Text('Excel')),
                          ],
                          onChanged: isExporting
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() => _alertFormatVal = v);
                                  }
                                },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Inspection Mode
                Text(
                  'Inspection Mode',
                  style: GoogleFonts.inter(
                    color: _kSub,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _reportRangeMode,
                  dropdownColor: _kSurface,
                  style: GoogleFonts.inter(color: _kText, fontSize: 13),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kCopper),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Today (Daily)')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  ],
                  onChanged: isExporting
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() => _reportRangeMode = v);
                          }
                        },
                ),
                const SizedBox(height: 16),

                // Download Inspection Report Button and Format Dropdown
                Text(
                  'Inspection Report',
                  style: GoogleFonts.inter(
                    color: _kSub,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kCopper,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _kCopper.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: isExporting
                              ? null
                              : () {
                                  if (_inspectionFormatVal == 'pdf') {
                                    _downloadInspectionReportPdf();
                                  } else {
                                    _downloadInspectionReportExcel();
                                  }
                                },
                          icon: isExporting && _inspectionPdfExporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            'Download Inspection Report',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 40,
                        child: DropdownButtonFormField<String>(
                          value: _inspectionFormatVal,
                          dropdownColor: _kSurface,
                          style: GoogleFonts.inter(color: _kText, fontSize: 13),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _kCopper),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                            DropdownMenuItem(value: 'excel', child: Text('Excel')),
                          ],
                          onChanged: isExporting
                              ? null
                              : (v) {
                                  if (v != null) {
                                    setState(() => _inspectionFormatVal = v);
                                  }
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
              child: Text("ACTIVE ALERTS", // 🔖 Renamed for Alert Lifecycle Bug Fix
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
            const SizedBox(width: 8),
            _FilterChip(
              label: 'Today Only',
              icon: Icons.today_rounded,
              selected: _filterTodayOnly,
              onTap: () => setState(() => _filterTodayOnly = !_filterTodayOnly),
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
              Builder(
                builder: (context) {
                  int compliantCount = 0;
                  for (int i = 0; i < _tanks.length; i++) {
                    final t = _tanks[i];
                    final s = i < stats.length ? stats[i] : DashboardStatsModel.empty(t.id);
                    if (_isCompliant(t, s.lastCapturedAt)) {
                      compliantCount++;
                    }
                  }
                  final double complianceRate = _tanks.isEmpty ? 0.0 : (compliantCount / _tanks.length);
                  final int compliancePercent = (complianceRate * 100).round();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16, top: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Compliance Rate',
                                  style: GoogleFonts.dmSans(
                                    color: _kSub,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$compliantCount of ${_tanks.length} assets compliant',
                                  style: GoogleFonts.dmSans(
                                    color: _kSubL,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '$compliancePercent%',
                              style: GoogleFonts.spaceGrotesk(
                                color: compliancePercent >= 80
                                    ? _kSuccess
                                    : (compliancePercent >= 50 ? _kWarn : _kDanger),
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 8,
                            width: double.infinity,
                            color: _kBorder,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: complianceRate,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      compliancePercent >= 80
                                          ? _kSuccess.withOpacity(0.8)
                                          : (compliancePercent >= 50 ? _kWarn.withOpacity(0.8) : _kDanger.withOpacity(0.8)),
                                      compliancePercent >= 80
                                          ? _kSuccess
                                          : (compliancePercent >= 50 ? _kWarn : _kDanger),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
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

  Future<String> _getCurrentUsername() async {
    try {
      final user = await SessionManager.getCurrentUser();
      return user?.username ?? 'anonymous';
    } catch (_) {
      return 'anonymous';
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> _showSaveSuccessDialog(File file, String exportType) async {
    final size = await file.length();
    final createdTime = await file.lastModified();
    final sizeStr = _formatSize(size);
    final timeStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(createdTime);
    final fileName = file.path.split('/').last.split('\\').last;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141618),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF252830), width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF22C55E), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Report Saved Successfully',
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFFF0EEE9),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogDetailRow('File Name', fileName),
                const SizedBox(height: 8),
                _dialogDetailRow('Created Time', timeStr),
                const SizedBox(height: 8),
                _dialogDetailRow('File Size', sizeStr),
                const SizedBox(height: 8),
                const Divider(color: Color(0xFF252830), height: 16),
                const SizedBox(height: 4),
                Text(
                  'Full Path',
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFF8A8F9C),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0D0F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF252830)),
                  ),
                  child: SelectableText(
                    file.path,
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFFF0EEE9),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          backgroundColor: const Color(0xFFCB8C3E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          try {
                            await FileFolderOpener.openFile(file.path);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not open file: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text(
                          'Open',
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          backgroundColor: const Color(0xFF252830),
                          foregroundColor: const Color(0xFFF0EEE9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          final parentPath = file.parent.path;
                          try {
                            await Clipboard.setData(ClipboardData(text: parentPath));
                            await FileFolderOpener.openFolder(parentPath);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Opening folder and path copied!'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Folder path copied! Saved to: $parentPath')),
                            );
                          }
                        },
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: Text(
                          'Open Folder',
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          side: const BorderSide(color: Color(0xFF252830)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          try {
                            await Share.shareXFiles([XFile(file.path)], text: exportType);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not share file: $e')),
                            );
                          }
                        },
                        icon: const Icon(Icons.share_rounded, size: 16, color: Color(0xFF8A8F9C)),
                        label: Text(
                          'Share',
                          style: GoogleFonts.dmSans(
                            color: const Color(0xFFF0EEE9),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          'Close',
                          style: GoogleFonts.dmSans(
                            color: const Color(0xFF8A8F9C),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _dialogDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(color: const Color(0xFF8A8F9C), fontSize: 13),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFFF0EEE9),
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _getIfThenForTank(String tankId, String? capturedAt, ReadingModel? reading) {
    for (final a in _allAlerts) {
      if (a.tankId == tankId) {
        bool match = false;
        if (reading != null && reading.id != null && reading.id!.isNotEmpty && a.readingId == reading.id) {
          match = true;
        } else if (reading != null && a.timestamp == reading.capturedAt) {
          match = true;
        } else if (capturedAt != null) {
          try {
            final dtA = DateTime.parse(a.timestamp).toLocal();
            final dtCap = DateTime.parse(capturedAt).toLocal();
            if (dtA.year == dtCap.year && dtA.month == dtCap.month && dtA.day == dtCap.day) {
              match = true;
            }
          } catch (_) {
            if (a.timestamp == capturedAt) match = true;
          }
        }
        if (match && a.ifThen.isNotEmpty) {
          return a.ifThen;
        }
      }
    }
    return '';
  }

  pw.Widget _buildPdfTable({
    required String title,
    required List<TankModel> tanks,
    required List<Map<String, dynamic>> params,
    required Map<String, DashboardStatsModel> statsByTank,
    required List<ReadingModel> readings, // empty if today
    required bool isToday,
    required Map<String, dynamic> formatConfigs,
    required bool includeTimestamp,
    required AbbreviationService abbrService,
    required String folderId,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
  }) {
    // Check if any row has an IF-THEN alert value
    bool hasIfThen = false;
    if (isToday) {
      hasIfThen = tanks.any((t) {
        final stats = statsByTank[t.id];
        if (stats == null || !_isCapturedToday(stats.lastCapturedAt)) return false;
        return _getIfThenForTank(t.id, stats.lastCapturedAt, null).isNotEmpty;
      });
    } else {
      hasIfThen = readings.any((r) {
        return _getIfThenForTank(r.tankId, r.capturedAt, r).isNotEmpty;
      });
    }

    bool hasDuplicateReason = false;
    if (isToday) {
      hasDuplicateReason = tanks.any((t) {
        final stats = statsByTank[t.id];
        if (stats == null || !_isCapturedToday(stats.lastCapturedAt)) return false;
        return stats.lastDuplicateReason != null && stats.lastDuplicateReason!.trim().isNotEmpty;
      });
    } else {
      hasDuplicateReason = readings.any((r) {
        return r.inspectionValues['duplicate_reason'] != null && r.inspectionValues['duplicate_reason'].toString().trim().isNotEmpty;
      });
    }

    // ── Parameter consolidation ───────────────────────────────────────────
    final folderConfig = formatConfigs[folderId] as Map?;
    final int uncommonThreshold = (folderConfig?['uncommon_threshold'] as num?)?.toInt() ?? 50;
    final bool consolidateUncommon = formatConfigs['consolidate_uncommon'] != false && folderConfig?['consolidate_uncommon'] != false;

    final bool compactionEnabled = formatConfigs['compaction_enabled'] == true;
    final bool abbrTitlesEnabled = formatConfigs['abbr_titles_enabled'] == true;

    final Map<String, int> paramTankCount = {};
    for (final p in params) {
      final label = p['label'].toString();
      int count = 0;
      for (final tank in tanks) {
        if (tank.inspectionProperties.any((prop) =>
            (prop['label'] ?? prop['name'] ?? '').toString() == label)) {
          count++;
        }
      }
      paramTankCount[label] = count;
    }

    final int totalTanks = tanks.isEmpty ? 1 : tanks.length;
    final List<Map<String, dynamic>> commonParams = [];
    final List<Map<String, dynamic>> uncommonParams = [];

    for (final p in params) {
      final label = p['label'].toString();
      final pct = ((paramTankCount[label] ?? 0) / totalTanks * 100).round();
      if (consolidateUncommon && pct < uncommonThreshold) {
        uncommonParams.add(p);
      } else {
        commonParams.add(p);
      }
    }
    uncommonParams.sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));
    final bool hasOtherCol = uncommonParams.isNotEmpty;

    final int totalCols = 1 +
        commonParams.length +
        (hasOtherCol ? 1 : 0) +
        (hasIfThen ? 1 : 0) +
        (hasDuplicateReason ? 1 : 0);

    final excelAbbreviate = folderConfig?['excel_abbreviate'] != false;
    final bool compress = excelAbbreviate && (totalCols > 6);

    // ── Header row ────────────────────────────────────────────────────────
    final List<String> headers = ['Asset Name'];
    for (final p in commonParams) {
      final label = p['label'].toString();
      final shouldAbbr = _shouldAbbreviateTitle(label, compress, abbrTitlesEnabled);
      headers.add(shouldAbbr ? abbrService.abbreviate(label, isHeader: true) : label);
    }
    if (hasOtherCol) {
      headers.add('Other Parameters');
    }
    if (hasIfThen) {
      final shouldAbbr = _shouldAbbreviateTitle('IF-THEN', compress, abbrTitlesEnabled);
      headers.add(shouldAbbr ? abbrService.abbreviate('IF-THEN', isHeader: true) : 'IF-THEN');
    }
    if (hasDuplicateReason) {
      final shouldAbbr = _shouldAbbreviateTitle('Duplicate Reason', compress, abbrTitlesEnabled);
      headers.add(shouldAbbr ? abbrService.abbreviate('Duplicate Reason', isHeader: true) : 'Duplicate Reason');
    }

    final double cellFontSize = compactionEnabled ? 5.8 : (compress ? 6.2 : 6.8);
    final double headerFontSize = compactionEnabled ? 6.2 : (compress ? 6.5 : 7.2);
    final pw.EdgeInsets cellPadding = compactionEnabled
        ? const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.5)
        : const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 2.5);

    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
      children: headers.map((h) => _pdfCell(h, header: true, fontSize: headerFontSize, padding: cellPadding)).toList(),
    );

    final List<pw.TableRow> rows = [headerRow];

    // ── Helper: build Other Parameters cell ──────────────────────────────
    pw.Widget buildOtherParamsCell({
      required Map<String, dynamic> readingValues,
      required TankModel tank,
      required pw.BoxDecoration? rowBg,
    }) {
      final List<Map<String, dynamic>> entries = [];
      for (final p in uncommonParams) {
        final label = p['label'].toString();
        final val = readingValues[label];
        if (val == null) continue;
        final prop = _getTankParamProp(tank, label) ?? p;
        final valStr = _formatValueWithArrow(val, prop);
        if (valStr == '-') continue;
        entries.add({'label': label, 'value': valStr});
      }
      entries.sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));

      if (entries.isEmpty) {
        return _pdfCell('-', fill: rowBg?.color, fontSize: cellFontSize, padding: cellPadding);
      }

      final textSpans = <pw.TextSpan>[];
      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final label = entry['label'].toString();
        final valStr = entry['value'].toString();

        final pdfColor = _resolveParamColorPdfSync(
          label: label,
          localColorsCache: localColorsCache,
          pendingDbWrites: pendingDbWrites,
        );

        if (i > 0) {
          textSpans.add(const pw.TextSpan(text: '\n'));
        }
        textSpans.add(
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(
              color: pdfColor,
              fontWeight: pw.FontWeight.bold,
              fontSize: cellFontSize - 0.5,
            ),
          ),
        );
        textSpans.add(
          pw.TextSpan(
            text: valStr,
            style: pw.TextStyle(
              color: rowBg != null ? pdf.PdfColors.black : null,
              fontSize: cellFontSize - 0.5,
            ),
          ),
        );
      }

      return _pdfCellWidget(
        pw.RichText(
          text: pw.TextSpan(children: textSpans),
        ),
        fill: rowBg?.color,
        padding: cellPadding,
      );
    }

    if (isToday) {
      for (final tank in tanks) {
        final stats = statsByTank[tank.id];
        final cleanName = _cleanAssetName(tankName: tank.tankName, folderId: folderId, formatConfigs: formatConfigs);

        if (stats == null || !_isCapturedToday(stats.lastCapturedAt)) {
          final pendingBg = _getRowColor(null, pending: true);
          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(color: pendingBg),
              children: [
                _pdfCell('$cleanName\n-', fill: pendingBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, textColor: pdf.PdfColors.black, padding: cellPadding),
                _pdfCell('------- Readings not taken ------', fill: pendingBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, alignment: pw.Alignment.center, textColor: pdf.PdfColors.black, padding: cellPadding),
                for (int i = 0; i < totalCols - 2; i++) pw.Container(),
              ],
            ),
          );
        } else {
          final alertSev = _getTankActiveAlertSeverity(tank.id, _allAlerts.where((a) => !a.acknowledged && a.status.toLowerCase() != 'completed').toList());
          final rowBg = _getRowColor(alertSev);
          final timeStr = DateFormat('hh:mm a').format(DateTime.parse(stats.lastCapturedAt!).toLocal());

          final List<pw.Widget> cells = [];
          cells.add(_pdfCell('$cleanName\n$timeStr', fill: rowBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, textColor: rowBg != null ? pdf.PdfColors.black : null, padding: cellPadding));

          for (final p in commonParams) {
            final val = stats.lastReading[p['label']];
            var valStr = _formatValueWithArrow(val, _getTankParamProp(tank, p['label'].toString()));
            if (compress && valStr != '-' && valStr.length > 5 && !_isNumericOrRange(valStr)) {
              valStr = abbrService.abbreviate(valStr);
            }
            final paramImages = _getParamImages(stats.lastReading, _getTankParamProp(tank, p['label'].toString()) ?? p);

            cells.add(
              _pdfCellWidget(
                pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(valStr, style: pw.TextStyle(fontSize: cellFontSize, fontWeight: pw.FontWeight.normal, color: rowBg != null ? pdf.PdfColors.black : null)),
                    if (includeTimestamp && valStr != '-')
                      pw.Text(
                        timeStr,
                        style: pw.TextStyle(
                          fontSize: cellFontSize - 1.2,
                          color: pdf.PdfColor.fromInt(0xFF1B5E20),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (paramImages.isNotEmpty) ...[
                      pw.SizedBox(height: 1.0),
                      ...paramImages.asMap().entries.map((e) {
                        final idx = e.key + 1;
                        final url = e.value;
                        return pw.UrlLink(
                          destination: url,
                          child: pw.Text(
                            paramImages.length == 1 ? '[Photo]' : '[P$idx]',
                            style: pw.TextStyle(
                              fontSize: cellFontSize - 1.5,
                              color: pdf.PdfColors.blue800,
                              decoration: pw.TextDecoration.underline,
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
                fill: rowBg,
                alignment: pw.Alignment.center,
                padding: cellPadding,
              ),
            );
          }

          if (hasOtherCol) {
            cells.add(
              buildOtherParamsCell(
                readingValues: stats.lastReading,
                tank: tank,
                rowBg: rowBg != null ? pw.BoxDecoration(color: rowBg) : null,
              ),
            );
          }

          if (hasIfThen) {
            final ifThenVal = _getIfThenForTank(tank.id, stats.lastCapturedAt, null);
            cells.add(_pdfCell(ifThenVal.isNotEmpty ? ifThenVal : '-', fill: rowBg, fontSize: cellFontSize, padding: cellPadding));
          }

          if (hasDuplicateReason) {
            var reason = stats.lastDuplicateReason ?? '-';
            if (compress && reason != '-' && reason.length > 8) {
              reason = abbrService.abbreviate(reason);
            }
            cells.add(_pdfCell(reason, fill: rowBg, fontSize: cellFontSize, padding: cellPadding));
          }

          rows.add(pw.TableRow(children: cells));
        }
      }
    } else {
      final tankToReadings = <String, List<ReadingModel>>{};
      for (final r in readings) {
        tankToReadings.putIfAbsent(r.tankId, () => []).add(r);
      }

      for (final tank in tanks) {
        final cleanName = _cleanAssetName(tankName: tank.tankName, folderId: folderId, formatConfigs: formatConfigs);
        final tankReadings = tankToReadings[tank.id] ?? [];

        if (tankReadings.isEmpty) {
          final pendingBg = _getRowColor(null, pending: true);
          rows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(color: pendingBg),
              children: [
                _pdfCell('$cleanName\n-', fill: pendingBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, textColor: pdf.PdfColors.black, padding: cellPadding),
                _pdfCell('------- Readings not taken ------', fill: pendingBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, alignment: pw.Alignment.center, textColor: pdf.PdfColors.black, padding: cellPadding),
                for (int i = 0; i < totalCols - 2; i++) pw.Container(),
              ],
            ),
          );
        } else {
          for (final r in tankReadings) {
            final alertSev = _getTankActiveAlertSeverity(tank.id, _allAlerts.where((a) => !a.acknowledged && a.status.toLowerCase() != 'completed').toList());
            final rowBg = _getRowColor(alertSev);
            final timeStr = DateFormat('hh:mm a').format(DateTime.parse(r.capturedAt).toLocal());

            final List<pw.Widget> cells = [];
            cells.add(_pdfCell('$cleanName\n$timeStr', fill: rowBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, textColor: rowBg != null ? pdf.PdfColors.black : null, padding: cellPadding));

            for (final p in commonParams) {
              final val = r.inspectionValues[p['label']];
              var valStr = _formatValueWithArrow(val, _getTankParamProp(tank, p['label'].toString()));
              if (compress && valStr != '-' && valStr.length > 5 && !_isNumericOrRange(valStr)) {
                valStr = abbrService.abbreviate(valStr);
              }
              final paramImages = _getParamImages(r.inspectionValues, _getTankParamProp(tank, p['label'].toString()) ?? p);

              cells.add(
                _pdfCellWidget(
                  pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(valStr, style: pw.TextStyle(fontSize: cellFontSize, fontWeight: pw.FontWeight.normal, color: rowBg != null ? pdf.PdfColors.black : null)),
                      if (includeTimestamp && valStr != '-')
                        pw.Text(
                          timeStr,
                          style: pw.TextStyle(
                            fontSize: cellFontSize - 1.2,
                            color: pdf.PdfColor.fromInt(0xFF1B5E20),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      if (paramImages.isNotEmpty) ...[
                        pw.SizedBox(height: 1.0),
                        ...paramImages.asMap().entries.map((e) {
                          final idx = e.key + 1;
                          final url = e.value;
                          return pw.UrlLink(
                            destination: url,
                            child: pw.Text(
                              paramImages.length == 1 ? '[Photo]' : '[P$idx]',
                              style: pw.TextStyle(
                                fontSize: cellFontSize - 1.5,
                                color: pdf.PdfColors.blue800,
                                decoration: pw.TextDecoration.underline,
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                  fill: rowBg,
                  alignment: pw.Alignment.center,
                  padding: cellPadding,
                ),
              );
            }

            if (hasOtherCol) {
              cells.add(
                buildOtherParamsCell(
                  readingValues: r.inspectionValues,
                  tank: tank,
                  rowBg: rowBg != null ? pw.BoxDecoration(color: rowBg) : null,
                ),
              );
            }

            if (hasIfThen) {
              final ifThenVal = _getIfThenForTank(r.tankId, r.capturedAt, r);
              cells.add(_pdfCell(ifThenVal.isNotEmpty ? ifThenVal : '-', fill: rowBg, fontSize: cellFontSize, padding: cellPadding));
            }

            if (hasDuplicateReason) {
              var reason = r.inspectionValues['duplicate_reason']?.toString() ?? '-';
              if (compress && reason != '-' && reason.length > 8) {
                reason = abbrService.abbreviate(reason);
              }
              cells.add(_pdfCell(reason, fill: rowBg, fontSize: cellFontSize, padding: cellPadding));
            }

            rows.add(pw.TableRow(children: cells));
          }
        }
      }
    }

    final List<pw.TableColumnWidth> colWidthList = [
      const pw.FlexColumnWidth(1.3), // Asset Name
    ];
    for (int i = 0; i < commonParams.length; i++) {
      colWidthList.add(const pw.FlexColumnWidth(1.0)); // Params
    }
    if (hasOtherCol) {
      colWidthList.add(const pw.FlexColumnWidth(1.6)); // Other Parameters
    }
    if (hasIfThen) {
      colWidthList.add(const pw.FlexColumnWidth(1.5)); // IF-THEN
    }
    if (hasDuplicateReason) {
      colWidthList.add(const pw.FlexColumnWidth(1.2)); // Duplicate Reason
    }
    final Map<int, pw.TableColumnWidth> colWidths = colWidthList.asMap();

    return pw.Table(
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
      columnWidths: colWidths,
      children: rows,
    );
  }

  pw.Widget _buildPdfWeeklyTable({
    required String title,
    required List<TankModel> tanks,
    required List<Map<String, dynamic>> params,
    required List<ReadingModel> readings,
    required List<DateTime> days,
    required Map<String, dynamic> formatConfigs,
    required bool includeTimestamp,
    required AbbreviationService abbrService,
    required String folderId,
    required List<pdf.PdfColor> dayColors,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
  }) {
    final hasDuplicateReason = readings.any((r) {
      return r.inspectionValues['duplicate_reason'] != null && r.inspectionValues['duplicate_reason'].toString().trim().isNotEmpty;
    });

    // ── Parameter consolidation ───────────────────────────────────────────
    final folderConfig = formatConfigs[folderId] as Map?;
    final int uncommonThreshold = (folderConfig?['uncommon_threshold'] as num?)?.toInt() ?? 50;
    final bool consolidateUncommon = formatConfigs['consolidate_uncommon'] != false && folderConfig?['consolidate_uncommon'] != false;

    final bool compactionEnabled = formatConfigs['compaction_enabled'] == true;
    final bool abbrTitlesEnabled = formatConfigs['abbr_titles_enabled'] == true;

    final Map<String, int> paramTankCount = {};
    for (final p in params) {
      final label = p['label'].toString();
      int count = 0;
      for (final tank in tanks) {
        if (tank.inspectionProperties.any((prop) {
          return (prop['label'] ?? prop['name'] ?? '').toString() == label;
        })) {
          count++;
        }
      }
      paramTankCount[label] = count;
    }

    final int totalTanks = tanks.isEmpty ? 1 : tanks.length;
    final List<Map<String, dynamic>> commonParams = [];
    final List<Map<String, dynamic>> uncommonParams = [];

    for (final p in params) {
      final label = p['label'].toString();
      final pct = ((paramTankCount[label] ?? 0) / totalTanks * 100).round();
      if (consolidateUncommon && pct < uncommonThreshold) {
        uncommonParams.add(p);
      } else {
        commonParams.add(p);
      }
    }
    uncommonParams.sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));
    final bool hasOtherCol = uncommonParams.isNotEmpty;

    final int totalCols = 1 + commonParams.length * days.length + (hasOtherCol ? 1 : 0) + (hasDuplicateReason ? 1 : 0);
    final pdfAbbreviate = folderConfig?['pdf_abbreviate'] != false;
    final bool compress = pdfAbbreviate && (totalCols > 6);

    final double cellFontSize = compactionEnabled ? 5.2 : (compress ? 5.6 : 6.2);
    final double headerFontSize = compactionEnabled ? 5.8 : (compress ? 6.2 : 6.8);
    final pw.EdgeInsets cellPadding = compactionEnabled
        ? const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 1.5)
        : const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 2.5);

    // ── Header Row 1: Parameter Groups ────────────────────────────────────
    final header1Cells = <pw.Widget>[
      _pdfCell('', header: true, fontSize: headerFontSize, padding: cellPadding),
    ];
    for (final p in commonParams) {
      final label = p['label'].toString();
      final shouldAbbr = _shouldAbbreviateTitle(label, compress, abbrTitlesEnabled);
      header1Cells.add(
        _pdfCell(
          shouldAbbr ? abbrService.abbreviate(label, isHeader: true) : label,
          header: true,
          fontSize: headerFontSize,
          alignment: pw.Alignment.center,
          padding: cellPadding,
        ),
      );
    }
    if (hasOtherCol) {
      header1Cells.add(
        _pdfCell(
          'Other Parameters',
          header: true,
          fontSize: headerFontSize,
          alignment: pw.Alignment.center,
          padding: cellPadding,
        ),
      );
    }
    if (hasDuplicateReason) {
      final shouldAbbr = _shouldAbbreviateTitle('Duplicate Reason', compress, abbrTitlesEnabled);
      header1Cells.add(
        _pdfCell(
          shouldAbbr ? abbrService.abbreviate('Duplicate Reason', isHeader: true) : 'Duplicate Reason',
          header: true,
          fontSize: headerFontSize,
          alignment: pw.Alignment.center,
          padding: cellPadding,
        ),
      );
    }

    // ── Header Row 2: Date sub-columns ────────────────────────────────────
    final header2Cells = <pw.Widget>[
      _pdfCell('Asset Name', header: true, fontSize: headerFontSize, padding: cellPadding),
    ];
    for (final p in commonParams) {
      header2Cells.add(
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
          border: pw.TableBorder(verticalInside: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4)),
          columnWidths: {
            for (int i = 0; i < days.length; i++) i: const pw.FlexColumnWidth(1.0),
          },
          children: [
            pw.TableRow(
              children: List.generate(days.length, (dIdx) {
                final day = days[dIdx];
                final dateLabel = DateFormat('dd/MM').format(day);
                final colBg = dayColors[dIdx % dayColors.length];
                return _pdfCell(
                  dateLabel,
                  header: true,
                  fill: colBg,
                  fontSize: cellFontSize,
                  alignment: pw.Alignment.center,
                  textColor: pdf.PdfColors.black,
                  padding: cellPadding,
                );
              }),
            ),
          ],
        ),
      );
    }
    if (hasOtherCol) {
      header2Cells.add(
        _pdfCell(
          'Name : Value (per day)',
          header: true,
          fontSize: cellFontSize,
          alignment: pw.Alignment.center,
          padding: cellPadding,
        ),
      );
    }
    if (hasDuplicateReason) {
      header2Cells.add(_pdfCell('-', header: true, fontSize: headerFontSize, padding: cellPadding));
    }

    final List<pw.TableRow> rows = [
      pw.TableRow(children: header1Cells),
      pw.TableRow(children: header2Cells),
    ];

    // ── Helper: build weekly Other Parameters rich cell ───────────────────
    pw.Widget buildWeeklyOtherParamsCell({
      required List<ReadingModel> tankReadings,
      required TankModel tank,
      required pw.BoxDecoration? rowBg,
    }) {
      final textSpans = <pw.TextSpan>[];
      int dayCount = 0;

      for (int dIdx = 0; dIdx < days.length; dIdx++) {
        final day = days[dIdx];
        final dateLabel = DateFormat('dd/MM').format(day);

        final dayReadings = tankReadings.where((r) {
          final dt = DateTime.parse(r.capturedAt).toLocal();
          return DateFormat('yyyy-MM-dd').format(dt) == DateFormat('yyyy-MM-dd').format(day);
        }).toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

        final ReadingModel? latestReading = dayReadings.isNotEmpty ? dayReadings.first : null;

        final List<Map<String, dynamic>> dayEntries = [];
        for (final p in uncommonParams) {
          final label = p['label'].toString();
          String valText = '-';
          if (latestReading != null) {
            final val = latestReading.inspectionValues[label];
            if (val != null) {
              final prop = _getTankParamProp(tank, label) ?? p;
              valText = _formatValueWithArrow(val, prop);
            }
          }
          if (valText != '-') {
            dayEntries.add({'label': label, 'value': valText});
          }
        }
        dayEntries.sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));

        if (dayEntries.isNotEmpty) {
          if (dayCount > 0) {
            textSpans.add(const pw.TextSpan(text: '\n'));
          }
          textSpans.add(
            pw.TextSpan(
              text: '[$dateLabel]\n',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: cellFontSize - 0.5,
                color: pdf.PdfColors.grey800,
              ),
            ),
          );

          for (int entryIdx = 0; entryIdx < dayEntries.length; entryIdx++) {
            final entry = dayEntries[entryIdx];
            final label = entry['label'].toString();
            final value = entry['value'].toString();

            final pdfColor = _resolveParamColorPdfSync(
              label: label,
              localColorsCache: localColorsCache,
              pendingDbWrites: pendingDbWrites,
            );

            if (entryIdx > 0) {
              textSpans.add(const pw.TextSpan(text: '\n'));
            }
            textSpans.add(
              pw.TextSpan(
                text: '  $label: ',
                style: pw.TextStyle(
                  color: pdfColor,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: cellFontSize - 0.8,
                ),
              ),
            );
            textSpans.add(
              pw.TextSpan(
                text: value,
                style: pw.TextStyle(
                  color: rowBg != null ? pdf.PdfColors.black : null,
                  fontSize: cellFontSize - 0.8,
                ),
              ),
            );
          }
          dayCount++;
        }
      }

      if (textSpans.isEmpty) {
        return _pdfCell('-', fill: rowBg?.color, fontSize: cellFontSize, padding: cellPadding);
      }

      return _pdfCellWidget(
        pw.RichText(
          text: pw.TextSpan(children: textSpans),
        ),
        fill: rowBg?.color,
        padding: cellPadding,
      );
    }

    // ── Table Rows ────────────────────────────────────────────────────────
    for (final tank in tanks) {
      final alertSev = _getTankActiveAlertSeverity(tank.id, _allAlerts.where((a) => !a.acknowledged && a.status.toLowerCase() != 'completed').toList());
      final cleanName = _cleanAssetName(tankName: tank.tankName, folderId: folderId, formatConfigs: formatConfigs);

      final folderReadings = readings.where((r) => r.tankId == tank.id).toList();
      final hasAnyReadings = folderReadings.isNotEmpty;
      final alertBg = hasAnyReadings ? _getRowColor(alertSev) : _getRowColor(null, pending: true);

      if (!hasAnyReadings) {
        rows.add(
          pw.TableRow(
            decoration: pw.BoxDecoration(color: alertBg),
            children: [
              _pdfCell(cleanName, fill: alertBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, textColor: pdf.PdfColors.black, padding: cellPadding),
              _pdfCell('------- Readings not taken ------', fill: alertBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, alignment: pw.Alignment.center, textColor: pdf.PdfColors.black, padding: cellPadding),
              for (int i = 0; i < totalCols - 2; i++) pw.Container(),
            ],
          ),
        );
      } else {
        final List<pw.Widget> parentCells = [
          _pdfCell(cleanName, fill: alertBg, fontSize: cellFontSize, fontWeight: pw.FontWeight.bold, textColor: alertBg != null ? pdf.PdfColors.black : null, padding: cellPadding),
        ];

        for (final p in commonParams) {
          final prop = _getTankParamProp(tank, p['label'].toString()) ?? p;

          parentCells.add(
            pw.Table(
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
              border: pw.TableBorder(verticalInside: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4)),
              columnWidths: {
                for (int i = 0; i < days.length; i++) i: const pw.FlexColumnWidth(1.0),
              },
              children: [
                pw.TableRow(
                  children: List.generate(days.length, (dIdx) {
                    final day = days[dIdx];
                    final colBg = alertBg ?? dayColors[dIdx % dayColors.length];

                    final dayReadings = folderReadings.where((r) {
                      final dt = DateTime.parse(r.capturedAt).toLocal();
                      return DateFormat('yyyy-MM-dd').format(dt) == DateFormat('yyyy-MM-dd').format(day);
                    }).toList()
                      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

                    String valText = '-';
                    String timeStr = '';
                    List<String> paramImages = [];
                    if (dayReadings.isNotEmpty) {
                      final latest = dayReadings.first;
                      final val = latest.inspectionValues[p['label']];
                      if (val != null) {
                        valText = _formatValueWithArrow(val, prop);
                        if (compress && valText != '-' && valText.length > 5 && !_isNumericOrRange(valText)) {
                          valText = abbrService.abbreviate(valText);
                        }
                        timeStr = DateFormat('hh:mm a').format(DateTime.parse(latest.capturedAt).toLocal());
                        paramImages = _getParamImages(latest.inspectionValues, prop);
                      }
                    }

                    final cellContent = pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(valText, style: pw.TextStyle(fontSize: cellFontSize, fontWeight: pw.FontWeight.normal, color: colBg != null ? pdf.PdfColors.black : null)),
                        if (includeTimestamp && valText != '-' && timeStr.isNotEmpty)
                          pw.Text(
                            timeStr,
                            style: pw.TextStyle(
                              fontSize: cellFontSize - 1.2,
                              color: pdf.PdfColor.fromInt(0xFF1B5E20),
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (paramImages.isNotEmpty) ...[
                          pw.SizedBox(height: 1.0),
                          ...paramImages.asMap().entries.map((e) {
                            final idx = e.key + 1;
                            final url = e.value;
                            return pw.UrlLink(
                              destination: url,
                              child: pw.Text(
                                paramImages.length == 1 ? '[Photo]' : '[P$idx]',
                                style: pw.TextStyle(
                                  fontSize: cellFontSize - 1.4,
                                  color: pdf.PdfColors.blue800,
                                  decoration: pw.TextDecoration.underline,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    );

                    return _pdfCellWidget(cellContent, fill: colBg, alignment: pw.Alignment.center, padding: cellPadding);
                  }),
                ),
              ],
            ),
          );
        }

        if (hasOtherCol) {
          parentCells.add(
            buildWeeklyOtherParamsCell(
              tankReadings: folderReadings,
              tank: tank,
              rowBg: alertBg != null ? pw.BoxDecoration(color: alertBg) : null,
            ),
          );
        }

        if (hasDuplicateReason) {
          final List<String> reasons = [];
          for (final day in days) {
            final dayReadings = folderReadings.where((r) {
              final dt = DateTime.parse(r.capturedAt).toLocal();
              return DateFormat('yyyy-MM-dd').format(dt) == DateFormat('yyyy-MM-dd').format(day);
            }).toList();
            for (final dr in dayReadings) {
              final reason = dr.inspectionValues['duplicate_reason']?.toString() ?? '';
              if (reason.trim().isNotEmpty) {
                final prefix = DateFormat('dd/MM').format(day);
                reasons.add('$prefix: $reason');
              }
            }
          }
          var reasonStr = reasons.isEmpty ? '-' : reasons.join('\n');
          if (compress && reasonStr != '-' && reasonStr.length > 10) {
            reasonStr = abbrService.abbreviate(reasonStr);
          }
          parentCells.add(_pdfCell(reasonStr, fill: alertBg, fontSize: cellFontSize, padding: cellPadding));
        }

        rows.add(pw.TableRow(decoration: alertBg != null ? pw.BoxDecoration(color: alertBg) : null, children: parentCells));
      }
    }

    final Map<int, pw.TableColumnWidth> colWidths = {
      0: const pw.FlexColumnWidth(1.2),
    };
    for (int i = 1; i <= commonParams.length; i++) {
      colWidths[i] = pw.FlexColumnWidth(days.length * 0.7);
    }
    int colIdxOffset = commonParams.length + 1;
    if (hasOtherCol) {
      colWidths[colIdxOffset] = const pw.FlexColumnWidth(1.8);
      colIdxOffset++;
    }
    if (hasDuplicateReason) {
      colWidths[colIdxOffset] = const pw.FlexColumnWidth(1.2);
    }

    return pw.Table(
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
      border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
      columnWidths: colWidths,
      children: rows,
    );
  }

  List<pw.Widget> _buildFolderInspectionSectionPdf({
    required TankNode folderNode,
    required List<TankModel> folderTanks,
    required List<Map<String, dynamic>> selectedParams,
    required List<Map<String, dynamic>> violationParams,
    required List<ReadingModel> readings,
    required bool isToday,
    required Map<String, DashboardStatsModel> statsByTank,
    required List<_AlertModel> openAlerts,
    required bool includeTimestamp,
    required Map<String, dynamic> formatConfigs,
    required AbbreviationService abbrService,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
    String? dateStr,
  }) {
    final widgets = <pw.Widget>[];

    final List<TankModel> normalTanks = [];
    final List<TankModel> violatedTanks = [];
    final List<ReadingModel> normalReadings = [];
    final List<ReadingModel> violatedReadings = [];
    final List<TankModel> pendingTanks = [];

    if (isToday) {
      for (final t in folderTanks) {
        final stats = statsByTank[t.id];
        final hasReading = stats != null && stats.lastCapturedAt != null;
        if (!hasReading) {
          pendingTanks.add(t);
          normalTanks.add(t);
        } else {
          final isViolated = openAlerts.any((a) => a.tankId == t.id);
          if (isViolated) {
            violatedTanks.add(t);
          } else {
            normalTanks.add(t);
          }
        }
      }
    } else {
      final folderTankIds = folderTanks.map((t) => t.id).toSet();
      final filteredReadings = readings.where((r) {
        if (!folderTankIds.contains(r.tankId)) return false;
        if (dateStr != null) {
          final dt = DateTime.parse(r.capturedAt).toLocal();
          return DateFormat('yyyy-MM-dd').format(dt) == dateStr;
        }
        return true;
      }).toList();

      for (final t in folderTanks) {
        final tankReadings = filteredReadings.where((r) => r.tankId == t.id).toList();
        if (tankReadings.isEmpty) {
          pendingTanks.add(t);
        } else {
          for (final r in tankReadings) {
            final isViolated = openAlerts.any((a) => a.tankId == t.id);
            if (isViolated) {
              if (!violatedTanks.contains(t)) violatedTanks.add(t);
              violatedReadings.add(r);
            } else {
              if (!normalTanks.contains(t)) normalTanks.add(t);
              normalReadings.add(r);
            }
          }
        }
      }
      for (final t in pendingTanks) {
        if (!normalTanks.contains(t)) normalTanks.add(t);
      }
    }

    final String sectionBaseTitle = dateStr != null 
        ? '${folderNode.name} - ${DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))}'
        : (isToday ? '${folderNode.name} - Today (${DateFormat('dd/MM/yyyy').format(DateTime.now())})' : folderNode.name);

    if (normalTanks.isNotEmpty || violatedTanks.isEmpty) {
      if (selectedParams.isNotEmpty) {
        final tableWidget = _buildPdfTable(
          title: '$sectionBaseTitle - Normal',
          tanks: normalTanks,
          params: selectedParams,
          statsByTank: statsByTank,
          readings: isToday ? [] : normalReadings,
          isToday: isToday,
          formatConfigs: formatConfigs,
          includeTimestamp: includeTimestamp,
          abbrService: abbrService,
          folderId: folderNode.id,
          localColorsCache: localColorsCache,
          pendingDbWrites: pendingDbWrites,
        );

        widgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 8),
                pw.Text('$sectionBaseTitle - Normal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: pdf.PdfColors.blue900)),
                pw.SizedBox(height: 3),
                tableWidget,
              ],
            ),
          ),
        );
      }
    }

    if (violatedTanks.isNotEmpty) {
      final vParams = violationParams.isNotEmpty ? violationParams : selectedParams;
      if (vParams.isNotEmpty) {
        final tableWidget = _buildPdfTable(
          title: '$sectionBaseTitle - Violated',
          tanks: violatedTanks,
          params: vParams,
          statsByTank: statsByTank,
          readings: isToday ? [] : violatedReadings,
          isToday: isToday,
          formatConfigs: formatConfigs,
          includeTimestamp: includeTimestamp,
          abbrService: abbrService,
          folderId: folderNode.id,
          localColorsCache: localColorsCache,
          pendingDbWrites: pendingDbWrites,
        );

        widgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 8),
                pw.Text('$sectionBaseTitle - Violated', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: pdf.PdfColors.red900)),
                pw.SizedBox(height: 3),
                tableWidget,
              ],
            ),
          ),
        );
      }
    }

    return widgets;
  }

  void _buildFolderInspectionSectionExcel({
    required xl.Sheet sheet,
    required TankNode folderNode,
    required List<TankModel> folderTanks,
    required List<Map<String, dynamic>> selectedParams,
    required List<Map<String, dynamic>> violationParams,
    required List<ReadingModel> readings,
    required bool isToday,
    required Map<String, DashboardStatsModel> statsByTank,
    required List<_AlertModel> openAlerts,
    required bool includeTimestamp,
    required Map<String, dynamic> formatConfigs,
    required AbbreviationService abbrService,
    required void Function(int col, int row, String colorHex) setCellBg,
    required refCurrentRowBox,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
    String? dateStr,
  }) {
    final List<TankModel> normalTanks = [];
    final List<TankModel> violatedTanks = [];
    final List<ReadingModel> normalReadings = [];
    final List<ReadingModel> violatedReadings = [];
    final List<TankModel> pendingTanks = [];

    if (isToday) {
      for (final t in folderTanks) {
        final stats = statsByTank[t.id];
        final hasReading = stats != null && stats.lastCapturedAt != null;
        if (!hasReading) {
          pendingTanks.add(t);
          normalTanks.add(t);
        } else {
          final isViolated = openAlerts.any((a) => a.tankId == t.id);
          if (isViolated) {
            violatedTanks.add(t);
          } else {
            normalTanks.add(t);
          }
        }
      }
    } else {
      final folderTankIds = folderTanks.map((t) => t.id).toSet();
      final filteredReadings = readings.where((r) {
        if (!folderTankIds.contains(r.tankId)) return false;
        if (dateStr != null) {
          final dt = DateTime.parse(r.capturedAt).toLocal();
          return DateFormat('yyyy-MM-dd').format(dt) == dateStr;
        }
        return true;
      }).toList();

      for (final t in folderTanks) {
        final tankReadings = filteredReadings.where((r) => r.tankId == t.id).toList();
        if (tankReadings.isEmpty) {
          pendingTanks.add(t);
        } else {
          for (final r in tankReadings) {
            final isViolated = openAlerts.any((a) => a.tankId == t.id);
            if (isViolated) {
              if (!violatedTanks.contains(t)) violatedTanks.add(t);
              violatedReadings.add(r);
            } else {
              if (!normalTanks.contains(t)) normalTanks.add(t);
              normalReadings.add(r);
            }
          }
        }
      }
      for (final t in pendingTanks) {
        if (!normalTanks.contains(t)) normalTanks.add(t);
      }
    }

    final String sectionBaseTitle = dateStr != null 
        ? '${folderNode.name} - ${DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr))}'
        : (isToday ? '${folderNode.name} - Today (${DateFormat('dd/MM/yyyy').format(DateTime.now())})' : folderNode.name);

    void renderExcelTable({
      required String title,
      required List<TankModel> tanks,
      required List<Map<String, dynamic>> params,
      required List<ReadingModel> tableReadings,
      required String headerBgHex,
    }) {
      int currentRow = refCurrentRowBox[0] as int;

      sheet.appendRow([xl.TextCellValue(title)]);
      currentRow++;

      bool hasIfThen = false;
      if (isToday) {
        hasIfThen = tanks.any((t) {
          final stats = statsByTank[t.id];
          if (stats == null || !_isCapturedToday(stats.lastCapturedAt)) return false;
          return _getIfThenForTank(t.id, stats.lastCapturedAt, null).isNotEmpty;
        });
      } else {
        hasIfThen = tableReadings.any((r) {
          return _getIfThenForTank(r.tankId, r.capturedAt, r).isNotEmpty;
        });
      }

      bool hasDuplicateReason = false;
      if (isToday) {
        hasDuplicateReason = tanks.any((t) {
          final stats = statsByTank[t.id];
          if (stats == null || !_isCapturedToday(stats.lastCapturedAt)) return false;
          return stats.lastDuplicateReason != null && stats.lastDuplicateReason!.trim().isNotEmpty;
        });
      } else {
        hasDuplicateReason = tableReadings.any((r) {
          return r.inspectionValues['duplicate_reason'] != null && r.inspectionValues['duplicate_reason'].toString().trim().isNotEmpty;
        });
      }

      final int totalCols = 1 + params.length + (hasIfThen ? 1 : 0) + (hasDuplicateReason ? 1 : 0);
      final folderConfig = formatConfigs[folderNode.id] as Map?;
      final excelAbbreviate = folderConfig?['excel_abbreviate'] != false;
      final int excelThreshold = (folderConfig?['excel_threshold'] as num?)?.toInt() ?? 12;
      final bool compress = excelAbbreviate && (totalCols > excelThreshold);

      final headerCells = <xl.CellValue>[
        xl.TextCellValue('Asset Name'),
        ...params.map((p) => xl.TextCellValue(compress ? abbrService.abbreviate(p['label'].toString(), isHeader: true) : p['label'].toString())),
      ];
      if (hasIfThen) {
        headerCells.add(xl.TextCellValue(compress ? abbrService.abbreviate('IF-THEN', isHeader: true) : 'IF-THEN'));
      }
      if (hasDuplicateReason) {
        headerCells.add(xl.TextCellValue(compress ? abbrService.abbreviate('Duplicate Reason', isHeader: true) : 'Duplicate Reason'));
      }

      sheet.appendRow(headerCells);
      for (int col = 0; col < headerCells.length; col++) {
        setCellBg(col, currentRow, '#ECEFF1');
      }
      currentRow++;

      if (isToday) {
        for (final tank in tanks) {
          final stats = statsByTank[tank.id];
          final cleanName = _cleanAssetName(tankName: tank.tankName, folderId: folderNode.id, formatConfigs: formatConfigs);

          if (stats == null || !_isCapturedToday(stats.lastCapturedAt)) {
            final nameCell = xl.TextCellValue('$cleanName\n-');
            final mergedCell = xl.TextCellValue('------- Readings not taken ------');
            final rowCells = <xl.CellValue>[nameCell, mergedCell];
            sheet.appendRow(rowCells);
            sheet.merge(
              xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow),
              xl.CellIndex.indexByColumnRow(columnIndex: params.length, rowIndex: currentRow),
            );
            for (int col = 0; col <= params.length; col++) {
              setCellBg(col, currentRow, '#EAF2E8');
            }
            currentRow++;
          } else {
            final alertSev = _getTankActiveAlertSeverity(tank.id, openAlerts);
            final rowBg = alertSev == 'critical'
                ? '#F2E6E6'
                : (alertSev == 'warning' ? '#F7EAD7' : (alertSev == 'info' ? '#ECEFF1' : null));

            final timeStr = DateFormat('hh:mm a').format(DateTime.parse(stats.lastCapturedAt!).toLocal());
            final nameCellVal = '$cleanName\n$timeStr';

            final rowCells = <xl.CellValue>[
              xl.TextCellValue(nameCellVal),
              ...params.map((p) {
                final val = stats.lastReading[p['label']];
                final prop = _getTankParamProp(tank, p['label'].toString()) ?? p;
                var valStr = _formatValueWithArrow(val, prop, forExcel: true);
                if (compress && valStr != '-' && valStr.length > 5) {
                  valStr = abbrService.abbreviate(valStr);
                }
                final paramImages = _getParamImages(stats.lastReading, prop);
                String cellVal = valStr;
                if (paramImages.isNotEmpty) {
                  for (final imgUrl in paramImages) {
                    cellVal += '\n(Image: $imgUrl)';
                  }
                }
                if (includeTimestamp && valStr != '-') {
                  return xl.TextCellValue('$cellVal\n$timeStr');
                }
                return xl.TextCellValue(cellVal);
              }),
            ];



            if (hasIfThen) {
              final ifThenVal = _getIfThenForTank(tank.id, stats.lastCapturedAt, null);
              rowCells.add(xl.TextCellValue(ifThenVal.isNotEmpty ? ifThenVal : '-'));
            }

            if (hasDuplicateReason) {
              var reason = stats.lastDuplicateReason ?? '-';
              if (compress && reason != '-' && reason.length > 8) {
                reason = abbrService.abbreviate(reason);
              }
              rowCells.add(xl.TextCellValue(reason));
            }

            sheet.appendRow(rowCells);
            if (rowBg != null) {
              for (int col = 0; col < rowCells.length; col++) {
                setCellBg(col, currentRow, rowBg);
              }
            }
            currentRow++;
          }
        }
      } else {
        final tankToReadings = <String, List<ReadingModel>>{};
        for (final r in tableReadings) {
          tankToReadings.putIfAbsent(r.tankId, () => []).add(r);
        }

        for (final tank in tanks) {
          final cleanName = _cleanAssetName(tankName: tank.tankName, folderId: folderNode.id, formatConfigs: formatConfigs);
          final tankReadings = tankToReadings[tank.id] ?? [];

          if (tankReadings.isEmpty) {
            final nameCell = xl.TextCellValue('$cleanName\n-');
            final mergedCell = xl.TextCellValue('------- Readings not taken ------');
            final rowCells = <xl.CellValue>[nameCell, mergedCell];
            sheet.appendRow(rowCells);
            sheet.merge(
              xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow),
              xl.CellIndex.indexByColumnRow(columnIndex: params.length, rowIndex: currentRow),
            );
            for (int col = 0; col <= params.length; col++) {
              setCellBg(col, currentRow, '#EAF2E8');
            }
            currentRow++;
          } else {
            for (final r in tankReadings) {
              final alertSev = _getTankActiveAlertSeverity(tank.id, openAlerts);
              final rowBg = alertSev == 'critical'
                  ? '#F2E6E6'
                  : (alertSev == 'warning' ? '#F7EAD7' : (alertSev == 'info' ? '#ECEFF1' : null));

              final timeStr = DateFormat('hh:mm a').format(DateTime.parse(r.capturedAt).toLocal());
              final nameCellVal = '$cleanName\n$timeStr';

              final rowCells = <xl.CellValue>[
                xl.TextCellValue(nameCellVal),
                ...params.map((p) {
                  final val = r.inspectionValues[p['label']];
                  final prop = _getTankParamProp(tank, p['label'].toString()) ?? p;
                  var valStr = _formatValueWithArrow(val, prop, forExcel: true);
                  if (compress && valStr != '-' && valStr.length > 5) {
                    valStr = abbrService.abbreviate(valStr);
                  }
                  final paramImages = _getParamImages(r.inspectionValues, prop);
                  String cellVal = valStr;
                  if (paramImages.isNotEmpty) {
                    for (final imgUrl in paramImages) {
                      cellVal += '\n(Image: $imgUrl)';
                    }
                  }
                  if (includeTimestamp && valStr != '-') {
                    return xl.TextCellValue('$cellVal\n$timeStr');
                  }
                  return xl.TextCellValue(cellVal);
                }),
              ];



              if (hasIfThen) {
                final ifThenVal = _getIfThenForTank(r.tankId, r.capturedAt, r);
                rowCells.add(xl.TextCellValue(ifThenVal.isNotEmpty ? ifThenVal : '-'));
              }

              if (hasDuplicateReason) {
                var reason = r.inspectionValues['duplicate_reason']?.toString() ?? '-';
                if (compress && reason != '-' && reason.length > 8) {
                  reason = abbrService.abbreviate(reason);
                }
                rowCells.add(xl.TextCellValue(reason));
              }

              sheet.appendRow(rowCells);
              if (rowBg != null) {
                for (int col = 0; col < rowCells.length; col++) {
                  setCellBg(col, currentRow, rowBg);
                }
              }
              currentRow++;
            }
          }
        }
      }

      sheet.appendRow([xl.TextCellValue('')]);
      currentRow++;

      refCurrentRowBox[0] = currentRow;
    }

    if (normalTanks.isNotEmpty || violatedTanks.isEmpty) {
      if (selectedParams.isNotEmpty) {
        renderExcelTable(
          title: '$sectionBaseTitle - Normal',
          tanks: normalTanks,
          params: selectedParams,
          tableReadings: normalReadings,
          headerBgHex: '#ECEFF1',
        );
      }
    }

    if (violatedTanks.isNotEmpty) {
      final vParams = violationParams.isNotEmpty ? violationParams : selectedParams;
      if (vParams.isNotEmpty) {
        renderExcelTable(
          title: '$sectionBaseTitle - Violated',
          tanks: violatedTanks,
          params: vParams,
          tableReadings: violatedReadings,
          headerBgHex: '#F2E6E6',
        );
      }
    }
  }

  void _buildFolderWeeklyInspectionSectionExcel({
    required xl.Sheet sheet,
    required TankNode folderNode,
    required List<TankModel> folderTanks,
    required List<Map<String, dynamic>> selectedParams,
    required List<Map<String, dynamic>> violationParams,
    required List<ReadingModel> readings,
    required List<DateTime> days,
    required List<String> dayColors,
    required bool includeTimestamp,
    required Map<String, dynamic> formatConfigs,
    required AbbreviationService abbrService,
    required void Function(int col, int row, String colorHex) setCellBg,
    required refCurrentRowBox,
    required List<_AlertModel> openAlerts,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
  }) {
    final List<TankModel> normalTanks = [];
    final List<TankModel> violatedTanks = [];
    final List<ReadingModel> normalReadings = [];
    final List<ReadingModel> violatedReadings = [];

    for (final tank in folderTanks) {
      final hasAnyReadings = readings.any((r) => r.tankId == tank.id);
      if (!hasAnyReadings) {
        normalTanks.add(tank);
      } else {
        final isViolated = openAlerts.any((a) => a.tankId == tank.id);
        if (isViolated) {
          violatedTanks.add(tank);
          violatedReadings.addAll(readings.where((r) => r.tankId == tank.id));
        } else {
          normalTanks.add(tank);
          normalReadings.addAll(readings.where((r) => r.tankId == tank.id));
        }
      }
    }

    final startLabel = DateFormat('dd/MM/yy').format(days.first);
    final endLabel = DateFormat('dd/MM/yy').format(days.last);

    void renderWeeklyExcelTable({
      required String title,
      required List<TankModel> tanks,
      required List<Map<String, dynamic>> params,
      required List<ReadingModel> tableReadings,
      required String headerBgHex,
    }) {
      int currentRow = refCurrentRowBox[0] as int;

      sheet.appendRow([xl.TextCellValue(title)]);
      currentRow++;

      final hasDuplicateReason = tableReadings.any((r) {
        return r.inspectionValues['duplicate_reason'] != null && r.inspectionValues['duplicate_reason'].toString().trim().isNotEmpty;
      });

      // ── Parameter consolidation ───────────────────────────────────────────
      final folderConfig = formatConfigs[folderNode.id] as Map?;
      final int uncommonThreshold = (folderConfig?['uncommon_threshold'] as num?)?.toInt() ?? 50;
      final bool consolidateUncommon = formatConfigs['consolidate_uncommon'] != false && folderConfig?['consolidate_uncommon'] != false;

      final bool compactionEnabled = formatConfigs['compaction_enabled'] == true;
      final bool abbrTitlesEnabled = formatConfigs['abbr_titles_enabled'] == true;

      final Map<String, int> paramTankCount = {};
      for (final p in params) {
        final label = p['label'].toString();
        int count = 0;
        for (final tank in tanks) {
          if (tank.inspectionProperties.any((prop) {
            return (prop['label'] ?? prop['name'] ?? '').toString() == label;
          })) {
            count++;
          }
        }
        paramTankCount[label] = count;
      }

      final int totalTanks = tanks.isEmpty ? 1 : tanks.length;
      final List<Map<String, dynamic>> commonParams = [];
      final List<Map<String, dynamic>> uncommonParams = [];

      for (final p in params) {
        final label = p['label'].toString();
        final pct = ((paramTankCount[label] ?? 0) / totalTanks * 100).round();
        if (consolidateUncommon && pct < uncommonThreshold) {
          uncommonParams.add(p);
        } else {
          commonParams.add(p);
        }
      }
      uncommonParams.sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));
      final bool hasOtherCol = uncommonParams.isNotEmpty;

      final int totalCols = 1 + commonParams.length * days.length + (hasOtherCol ? 1 : 0) + (hasDuplicateReason ? 1 : 0);
      final excelAbbreviate = folderConfig?['excel_abbreviate'] != false;
      final bool compress = excelAbbreviate && (totalCols > 6);

      // ── Header row 1: param labels (merged across days) ───────────────────
      final headerRow1 = <xl.CellValue>[xl.TextCellValue('Asset Name')];
      for (final p in commonParams) {
        final label = p['label'].toString();
        final shouldAbbr = _shouldAbbreviateTitle(label, compress, abbrTitlesEnabled);
        final finalLabel = shouldAbbr ? abbrService.abbreviate(label, isHeader: true) : label;
        headerRow1.addAll(List.generate(days.length, (dIdx) => xl.TextCellValue(dIdx == 0 ? finalLabel : '')));
      }
      if (hasOtherCol) {
        headerRow1.add(xl.TextCellValue('Other Parameters'));
      }
      if (hasDuplicateReason) {
        final shouldAbbr = _shouldAbbreviateTitle('Duplicate Reason', compress, abbrTitlesEnabled);
        headerRow1.add(xl.TextCellValue(shouldAbbr ? abbrService.abbreviate('Duplicate Reason', isHeader: true) : 'Duplicate Reason'));
      }

      sheet.appendRow(headerRow1);
      for (int col = 0; col < headerRow1.length; col++) {
        setCellBg(col, currentRow, '#ECEFF1');
      }
      for (int pIdx = 0; pIdx < commonParams.length; pIdx++) {
        int startCol = 1 + pIdx * days.length;
        int endCol = startCol + days.length - 1;
        if (days.length > 1) {
          sheet.merge(
            xl.CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: currentRow),
            xl.CellIndex.indexByColumnRow(columnIndex: endCol, rowIndex: currentRow),
          );
        }
      }
      currentRow++;

      // ── Header row 2: date sub-columns ─────────────────────────────────────
      final headerRow2 = <xl.CellValue>[xl.TextCellValue('')];
      for (final _ in commonParams) {
        headerRow2.addAll(days.map((day) => xl.TextCellValue(DateFormat('dd/MM').format(day))));
      }
      if (hasOtherCol) {
        headerRow2.add(xl.TextCellValue('Name : Value (per day)'));
      }
      if (hasDuplicateReason) {
        headerRow2.add(xl.TextCellValue(''));
      }

      sheet.appendRow(headerRow2);
      for (int col = 0; col < headerRow2.length; col++) {
        if (col == 0) {
          setCellBg(col, currentRow, '#ECEFF1');
        } else if (hasOtherCol && col == 1 + commonParams.length * days.length) {
          setCellBg(col, currentRow, '#ECEFF1');
        } else if (hasDuplicateReason && col == headerRow2.length - 1) {
          setCellBg(col, currentRow, '#ECEFF1');
        } else {
          final dIdx = (col - 1) % days.length;
          setCellBg(col, currentRow, dayColors[dIdx % dayColors.length]);
        }
      }
      currentRow++;

      for (final tank in tanks) {
        final alertSev = _getTankActiveAlertSeverity(tank.id, openAlerts);
        final cleanName = _cleanAssetName(tankName: tank.tankName, folderId: folderNode.id, formatConfigs: formatConfigs);

        final hasAnyReadingsForTank = tableReadings.any((r) => r.tankId == tank.id);
        final alertBg = hasAnyReadingsForTank
            ? (alertSev == 'critical'
                ? '#F2E6E6'
                : (alertSev == 'warning' ? '#F7EAD7' : (alertSev == 'info' ? '#ECEFF1' : null)))
            : '#EAF2E8';

        final rowCells = <xl.CellValue>[xl.TextCellValue(cleanName)];

        if (!hasAnyReadingsForTank) {
          rowCells.add(xl.TextCellValue('------- Readings not taken ------'));
          sheet.appendRow(rowCells);
          final lastDataCol = commonParams.length * days.length + (hasOtherCol ? 1 : 0) + (hasDuplicateReason ? 1 : 0);
          sheet.merge(
            xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow),
            xl.CellIndex.indexByColumnRow(columnIndex: lastDataCol, rowIndex: currentRow),
          );
          for (int col = 0; col <= lastDataCol; col++) {
            setCellBg(col, currentRow, '#EAF2E8');
          }
          currentRow++;
        } else {
          // ── Common parameter value cells ───────────────────────────────────
          for (final p in commonParams) {
            for (int dIdx = 0; dIdx < days.length; dIdx++) {
              final day = days[dIdx];

              final dayReadings = tableReadings.where((r) {
                if (r.tankId != tank.id) return false;
                final dt = DateTime.parse(r.capturedAt).toLocal();
                return DateFormat('yyyy-MM-dd').format(dt) == DateFormat('yyyy-MM-dd').format(day);
              }).toList()
                ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

              String valText = '-';
              if (dayReadings.isNotEmpty) {
                final latest = dayReadings.first;
                final val = latest.inspectionValues[p['label']];
                final prop = _getTankParamProp(tank, p['label'].toString()) ?? p;
                var valStr = _formatValueWithArrow(val, prop, forExcel: true);
                if (compress && valStr != '-' && valStr.length > 5 && !_isNumericOrRange(valStr)) {
                  valStr = abbrService.abbreviate(valStr);
                }

                if (valStr != '-') {
                  final paramImages = _getParamImages(latest.inspectionValues, prop);
                  String cellVal = valStr;
                  if (paramImages.isNotEmpty) {
                    for (final imgUrl in paramImages) {
                      cellVal += '\n(Image: $imgUrl)';
                    }
                  }
                  if (includeTimestamp) {
                    final timeStr = DateFormat('hh:mm a').format(DateTime.parse(latest.capturedAt).toLocal());
                    valText = '$cellVal\n$timeStr';
                  } else {
                    valText = cellVal;
                  }
                }
              }
              rowCells.add(xl.TextCellValue(valText));
            }
          }

          // ── Other Parameters merged cell ───────────────────────────────────
          if (hasOtherCol) {
            final StringBuffer otherBuf = StringBuffer();
            for (int dIdx = 0; dIdx < days.length; dIdx++) {
              final day = days[dIdx];
              final dateLabel = DateFormat('dd/MM').format(day);

              final dayReadings = tableReadings.where((r) {
                if (r.tankId != tank.id) return false;
                final dt = DateTime.parse(r.capturedAt).toLocal();
                return DateFormat('yyyy-MM-dd').format(dt) == DateFormat('yyyy-MM-dd').format(day);
              }).toList()
                ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

              final ReadingModel? latestReading = dayReadings.isNotEmpty ? dayReadings.first : null;

              final List<Map<String, dynamic>> dayEntries = [];
              for (final p in uncommonParams) {
                final label = p['label'].toString();
                String valText = '-';
                if (latestReading != null) {
                  final val = latestReading.inspectionValues[label];
                  if (val != null) {
                    final prop = _getTankParamProp(tank, label) ?? p;
                    valText = _formatValueWithArrow(val, prop, forExcel: true);
                  }
                }
                if (valText != '-') {
                  dayEntries.add({'label': label, 'value': valText});
                }
              }
              dayEntries.sort((a, b) => a['label'].toString().compareTo(b['label'].toString()));

              if (dayEntries.isNotEmpty) {
                if (otherBuf.isNotEmpty) otherBuf.write('\n');
                otherBuf.write('[$dateLabel]');
                for (final entry in dayEntries) {
                  final label = entry['label'].toString();
                  final value = entry['value'].toString();
                  // Trigger color registration in cache (return value intentionally discarded).
                  // ignore: unused_local_variable
                  final _colorHex = _resolveParamColorExcelSync(
                    label: label,
                    localColorsCache: localColorsCache,
                    pendingDbWrites: pendingDbWrites,
                  );
                  otherBuf.write('\n  $label : $value');
                }
              }
            }

            final otherText = otherBuf.isEmpty ? '-' : otherBuf.toString();
            rowCells.add(xl.TextCellValue(otherText));
          }

          if (hasDuplicateReason) {
            final List<String> reasons = [];
            for (final day in days) {
              final dayReadings = tableReadings.where((r) {
                if (r.tankId != tank.id) return false;
                final dt = DateTime.parse(r.capturedAt).toLocal();
                return DateFormat('yyyy-MM-dd').format(dt) == DateFormat('yyyy-MM-dd').format(day);
              }).toList();
              for (final dr in dayReadings) {
                final reason = dr.inspectionValues['duplicate_reason']?.toString() ?? '';
                if (reason.trim().isNotEmpty) {
                  final prefix = DateFormat('dd/MM').format(day);
                  reasons.add('$prefix: $reason');
                }
              }
            }
            var reasonStr = reasons.isEmpty ? '-' : reasons.join('\n');
            if (compress && reasonStr != '-' && reasonStr.length > 10) {
              reasonStr = abbrService.abbreviate(reasonStr);
            }
            rowCells.add(xl.TextCellValue(reasonStr));
          }

          sheet.appendRow(rowCells);
          for (int col = 0; col < rowCells.length; col++) {
            if (alertBg != null) {
              setCellBg(col, currentRow, alertBg);
            } else if (col > 0) {
              final otherColIdx = 1 + commonParams.length * days.length;
              if (hasOtherCol && col == otherColIdx) {
                // No special background for Other Parameters column
              } else if (hasDuplicateReason && col == rowCells.length - 1) {
                setCellBg(col, currentRow, '#FFFFFF');
              } else if (col <= commonParams.length * days.length) {
                final dIdx = (col - 1) % days.length;
                setCellBg(col, currentRow, dayColors[dIdx % dayColors.length]);
              }
            }
          }
          currentRow++;
        }
      }

      sheet.appendRow([xl.TextCellValue('')]);
      currentRow++;

      refCurrentRowBox[0] = currentRow;
    }

    if (normalTanks.isNotEmpty || violatedTanks.isEmpty) {
      if (selectedParams.isNotEmpty) {
        renderWeeklyExcelTable(
          title: '${folderNode.name} - $startLabel to $endLabel - Normal',
          tanks: normalTanks,
          params: selectedParams,
          tableReadings: normalReadings,
          headerBgHex: '#ECEFF1',
        );
      }
    }

    if (violatedTanks.isNotEmpty) {
      final vParams = violationParams.isNotEmpty ? violationParams : selectedParams;
      if (vParams.isNotEmpty) {
        renderWeeklyExcelTable(
          title: '${folderNode.name} - $startLabel to $endLabel - Violated',
          tanks: violatedTanks,
          params: vParams,
          tableReadings: violatedReadings,
          headerBgHex: '#F2E6E6',
        );
      }
    }
  }

  Future<void> _downloadAlertsExcel() async {
    if (_alertsPdfExporting) return;
    setState(() => _alertsPdfExporting = true);
    try {
      final window = _reportWindow();
      final activeAlerts = _allAlerts
          .where((a) {
            final isActive = !a.acknowledged && a.status.toLowerCase() != 'completed';
            if (isActive) return _tankMatch(a.tankId);
            return _inRange(a.timestamp, window) && _tankMatch(a.tankId);
          })
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final completedAlerts = _completed
          .where((c) => _inRange(c.completedAt, window))
          .where((c) => _tankMatch(c.alert.tankId))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

      final resolvedClient = await ClientContextService.resolveClientName();
      final clientName = resolvedClient ?? (_tanks.isEmpty
          ? 'All Assets'
          : (_tanks.first.location?.trim().isNotEmpty == true
              ? _tanks.first.location!
              : 'Dashboard'));

      final excel = xl.Excel.createExcel();

      final summarySheet = excel['Summary'];
      if (excel.tables.containsKey('Sheet1') && 'Sheet1' != 'Summary') {
        excel.delete('Sheet1');
      }

      int summaryRow = 0;
      summarySheet.appendRow([
        xl.TextCellValue('Metric'),
        xl.TextCellValue('Value'),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Client Name'),
        xl.TextCellValue(clientName),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Generated At'),
        xl.TextCellValue(DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.now())),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Time Range'),
        xl.TextCellValue(_pdfRange.label),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Start Date'),
        xl.TextCellValue(DateFormat('dd-MM-yyyy HH:mm:ss').format(window.start.toLocal())),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('End Date'),
        xl.TextCellValue(DateFormat('dd-MM-yyyy HH:mm:ss').format(window.end.toLocal())),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Active Alerts'),
        xl.TextCellValue(activeAlerts.length.toString()),
      ]);
      summaryRow++;
      summarySheet.appendRow([
        xl.TextCellValue('Resolved Alerts'),
        xl.TextCellValue(completedAlerts.length.toString()),
      ]);
      summaryRow++;

      summarySheet.appendRow([xl.TextCellValue('')]);
      summaryRow++;

      summarySheet.appendRow([
        xl.TextCellValue('Color Coding Legend:'),
        xl.TextCellValue('Critical'),
        xl.TextCellValue('Warning'),
        xl.TextCellValue('Info'),
      ]);

      void setSummaryCellBg(int col, int row, String hex) {
        try {
          summarySheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).cellStyle = xl.CellStyle(
            backgroundColorHex: xl.ExcelColor.fromHexString(hex),
          );
        } catch (_) {}
      }
      setSummaryCellBg(1, summaryRow, '#F2E6E6');
      setSummaryCellBg(2, summaryRow, '#F7EAD7');
      setSummaryCellBg(3, summaryRow, '#ECEFF1');
      summaryRow++;

      final activeSheet = excel['Active Alerts'];
      int activeRow = 0;
      activeSheet.appendRow([
        xl.TextCellValue('Time'),
        xl.TextCellValue('Asset Name'),
        xl.TextCellValue('Asset Code'),
        xl.TextCellValue('Severity'),
        xl.TextCellValue('Parameter'),
        xl.TextCellValue('Value'),
        xl.TextCellValue('Created By'),
        xl.TextCellValue('Message'),
        xl.TextCellValue('Image URL'),
      ]);
      for (int col = 0; col < 9; col++) {
        try {
          activeSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: activeRow)).cellStyle = xl.CellStyle(
            backgroundColorHex: xl.ExcelColor.fromHexString('#ECEFF1'),
          );
        } catch (_) {}
      }
      activeRow++;

      for (final a in activeAlerts) {
        final dateStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(a.timestamp).toLocal());
        activeSheet.appendRow([
          xl.TextCellValue(dateStr),
          xl.TextCellValue(a.tankName),
          xl.TextCellValue(a.tankCode),
          xl.TextCellValue(a.severity.toUpperCase()),
          xl.TextCellValue(a.paramLabel),
          xl.TextCellValue(a.paramValue.isEmpty ? '-' : a.paramValue),
          xl.TextCellValue(a.capturedByName.isEmpty ? 'Dashboard' : a.capturedByName),
          xl.TextCellValue(a.message.isEmpty ? '-' : a.message),
          xl.TextCellValue(a.imageUrl),
        ]);

        final hex = a.severity.toLowerCase() == 'critical'
            ? '#F2E6E6'
            : (a.severity.toLowerCase() == 'warning' ? '#F7EAD7' : '#ECEFF1');
        for (int col = 0; col < 9; col++) {
          try {
            activeSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: activeRow)).cellStyle = xl.CellStyle(
              backgroundColorHex: xl.ExcelColor.fromHexString(hex),
            );
          } catch (_) {}
        }
        activeRow++;
      }

      final completedSheet = excel['Completed Alerts'];
      int completedRow = 0;
      completedSheet.appendRow([
        xl.TextCellValue('Completed At'),
        xl.TextCellValue('Alert Time'),
        xl.TextCellValue('Asset Name'),
        xl.TextCellValue('Asset Code'),
        xl.TextCellValue('Severity'),
        xl.TextCellValue('Parameter'),
        xl.TextCellValue('Value'),
        xl.TextCellValue('Created By'),
        xl.TextCellValue('Resolved By'),
        xl.TextCellValue('Message'),
        xl.TextCellValue('Image URL'),
      ]);
      for (int col = 0; col < 11; col++) {
        try {
          completedSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: completedRow)).cellStyle = xl.CellStyle(
            backgroundColorHex: xl.ExcelColor.fromHexString('#ECEFF1'),
          );
        } catch (_) {}
      }
      completedRow++;

      for (final c in completedAlerts) {
        final a = c.alert;
        final compDateStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(c.completedAt).toLocal());
        final alertDateStr = DateFormat('dd-MM-yyyy HH:mm:ss').format(DateTime.parse(a.timestamp).toLocal());
        completedSheet.appendRow([
          xl.TextCellValue(compDateStr),
          xl.TextCellValue(alertDateStr),
          xl.TextCellValue(a.tankName),
          xl.TextCellValue(a.tankCode),
          xl.TextCellValue(a.severity.toUpperCase()),
          xl.TextCellValue(a.paramLabel),
          xl.TextCellValue(a.paramValue.isEmpty ? '-' : a.paramValue),
          xl.TextCellValue(a.capturedByName.isEmpty ? 'Dashboard' : a.capturedByName),
          xl.TextCellValue(c.completedBy),
          xl.TextCellValue(a.message.isEmpty ? '-' : a.message),
          xl.TextCellValue(a.imageUrl),
        ]);

        final hex = a.severity.toLowerCase() == 'critical'
            ? '#F2E6E6'
            : (a.severity.toLowerCase() == 'warning' ? '#F7EAD7' : '#ECEFF1');
        for (int col = 0; col < 11; col++) {
          try {
            completedSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: completedRow)).cellStyle = xl.CellStyle(
              backgroundColorHex: xl.ExcelColor.fromHexString(hex),
            );
          } catch (_) {}
        }
        completedRow++;
      }

      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final safeClient = clientName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final fileName = '${safeClient}_AlertsReport_$ts.xlsx';

      final excelBytes = excel.save()!;
      final savedFile = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: excelBytes,
        subPath: 'Reports/Excel',
        exportType: 'Excel Report',
        username: await _getCurrentUsername(),
        clientName: clientName,
      );

      await _showSaveSuccessDialog(savedFile, 'Excel Report');

      await _auditExport('download_excel', 'alerts_report', {
        'format': 'xlsx',
        'report_type': 'alerts',
        'path': savedFile.path,
      });
    } catch (e) {
      _snack('Alerts Excel export failed: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _alertsPdfExporting = false);
      }
    }
  }

  int _getStableHash(String s) {
    int hash = 5381;
    for (int i = 0; i < s.length; i++) {
      hash = ((hash << 5) + hash) + s.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash;
  }

  String _hsvToHex(double h, double s, double v) {
    final double c = v * s;
    final double x = c * (1 - ((h / 60.0) % 2 - 1).abs());
    final double m = v - c;

    double r = 0, g = 0, b = 0;
    if (h < 60) {
      r = c; g = x; b = 0;
    } else if (h < 120) {
      r = x; g = c; b = 0;
    } else if (h < 180) {
      r = 0; g = c; b = x;
    } else if (h < 240) {
      r = 0; g = x; b = c;
    } else if (h < 300) {
      r = x; g = 0; b = c;
    } else {
      r = c; g = 0; b = x;
    }

    final int ri = ((r + m) * 255).round().clamp(0, 255);
    final int gi = ((g + m) * 255).round().clamp(0, 255);
    final int bi = ((b + m) * 255).round().clamp(0, 255);

    final String rs = ri.toRadixString(16).padLeft(2, '0');
    final String gs = gi.toRadixString(16).padLeft(2, '0');
    final String bs = bi.toRadixString(16).padLeft(2, '0');

    return '#$rs$gs$bs';
  }

  String _sanitizeDbKey(String s) {
    return s.replaceAll(RegExp(r'[\.\$\#\[\]\/]'), '_');
  }

  pdf.PdfColor _resolveParamColorPdfSync({
    required String label,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
  }) {
    final String dbKey = _sanitizeDbKey(label);
    if (localColorsCache.containsKey(dbKey)) {
      final item = localColorsCache[dbKey];
      if (item is Map && item.containsKey('color')) {
        final colorHex = item['color'].toString();
        try {
          final int val = int.parse(colorHex.replaceAll('#', 'FF'), radix: 16);
          return pdf.PdfColor.fromInt(val);
        } catch (_) {}
      }
    }

    final int hashVal = _getStableHash(label);
    final double hue = (hashVal % 360).toDouble();
    final String generatedHex = _hsvToHex(hue, 0.85, 0.45);

    localColorsCache[dbKey] = {
      'color': generatedHex,
      'displayName': label,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'lastUsed': DateTime.now().toUtc().toIso8601String(),
    };

    pendingDbWrites.add({
      'key': dbKey,
      'data': localColorsCache[dbKey],
    });

    final int val = int.parse(generatedHex.replaceAll('#', 'FF'), radix: 16);
    return pdf.PdfColor.fromInt(val);
  }

  String _resolveParamColorExcelSync({
    required String label,
    required Map<String, dynamic> localColorsCache,
    required List<Map<String, dynamic>> pendingDbWrites,
  }) {
    final String dbKey = _sanitizeDbKey(label);
    if (localColorsCache.containsKey(dbKey)) {
      final item = localColorsCache[dbKey];
      if (item is Map && item.containsKey('color')) {
        return item['color'].toString();
      }
    }

    final int hashVal = _getStableHash(label);
    final double hue = (hashVal % 360).toDouble();
    final String generatedHex = _hsvToHex(hue, 0.85, 0.45);

    localColorsCache[dbKey] = {
      'color': generatedHex,
      'displayName': label,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'lastUsed': DateTime.now().toUtc().toIso8601String(),
    };

    pendingDbWrites.add({
      'key': dbKey,
      'data': localColorsCache[dbKey],
    });

    return generatedHex;
  }

  void _flushParamColors(List<Map<String, dynamic>> pendingDbWrites) {
    if (pendingDbWrites.isEmpty) return;
    try {
      final dbRef = FirebaseDatabase.instance.ref('settings/report_format/param_colors');
      for (final write in pendingDbWrites) {
        dbRef.child(write['key']).update(Map<String, dynamic>.from(write['data']));
      }
    } catch (_) {}
  }
}