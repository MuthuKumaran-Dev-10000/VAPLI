part of 'trends_screen.dart'; 

enum _AbnormalityRange { day, week, month, year }

extension _AbnormalityRangeX on _AbnormalityRange {
  String get label {
    switch (this) {
      case _AbnormalityRange.day:
        return 'Day';
      case _AbnormalityRange.week:
        return 'Week';
      case _AbnormalityRange.month:
        return 'Month';
      case _AbnormalityRange.year:
        return 'Year';
    }
  }
}

enum _AbnormalityType { alerts, completed, both }

extension _AbnormalityTypeX on _AbnormalityType {
  String get label {
    switch (this) {
      case _AbnormalityType.alerts:
        return 'Abnormalities';
      case _AbnormalityType.completed:
        return 'Completed';
      case _AbnormalityType.both:
        return 'Both';
    }
  }
}

class _TrendsScreenState extends State<TrendsScreen> {
  // ── Selection state ────────────────────────────────────────────────────────
  String? _selectedTankId;
  Map<String, dynamic>? _selectedParam;

  _Timeline _timeline = _Timeline.week;
  DateTime? _customFrom;
  DateTime? _customTo;

  // ── Load / display state ───────────────────────────────────────────────────
  bool _loading = false;
  bool _chartReady = false;
  bool _exporting = false;
  bool _abnormalityExporting = false;

  _AbnormalityRange _abnormalityRange = _AbnormalityRange.day;
  _AbnormalityType _abnormalityType = _AbnormalityType.both;

  // ── In-memory cache: tankId → sorted readings (oldest→newest) ────────────
  final Map<String, List<ReadingModel>> _cache = {};

  final _chartKey = GlobalKey();
  final _repo = ReadingRepository();

  DateTimeRange _abnormalityWindow() {
    final now = DateTime.now();
    switch (_abnormalityRange) {
      case _AbnormalityRange.day:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        );
      case _AbnormalityRange.week:
        return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
      case _AbnormalityRange.month:
        return DateTimeRange(start: DateTime(now.year, now.month - 1, now.day), end: now);
      case _AbnormalityRange.year:
        return DateTimeRange(start: DateTime(now.year - 1, now.month, now.day), end: now);
    }
  }

  bool _inRange(String? iso, DateTimeRange range) {
    if (iso == null || iso.isEmpty) return false;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return false;
    return !dt.isBefore(range.start) && !dt.isAfter(range.end);
  }

  String _alertTime(Map<dynamic, dynamic> m) =>
      m['captured_at']?.toString() ?? m['timestamp']?.toString() ?? '';

  String _alertSeverity(Map<dynamic, dynamic> m) =>
      m['constraint_severity']?.toString() ??
      m['severity']?.toString() ??
      'warning';

  String _alertParamLabel(Map<dynamic, dynamic> m) =>
      m['constraint_label']?.toString() ??
      m['param_label']?.toString() ??
      '-';

  String _alertParamValue(Map<dynamic, dynamic> m) =>
      m['violated_value']?.toString() ??
      m['param_value']?.toString() ??
      '-';

  String _alertStatus(Map<dynamic, dynamic> m) {
    final statusVal = m['status']?.toString().toLowerCase();
    if (statusVal == 'completed') return 'Completed'; // 🔖 Added for Alert Lifecycle Bug Fix
    if (m['resolved'] == true) return 'Resolved';
    if (m['acknowledged'] == true) return 'Acknowledged';
    return 'Open';
  }

  List<String> _extractAlertImageUrls(Map<dynamic, dynamic> m) {
    final urls = <String>{};
    final top = m['image_url']?.toString() ?? '';
    if (top.startsWith('http')) urls.add(top);

    final lastVals = m['last_inspection_values'];
    if (lastVals is Map) {
      final lv = Map<dynamic, dynamic>.from(lastVals);
      for (final e in lv.entries) {
        final key = e.key.toString().toLowerCase();
        final value = e.value?.toString() ?? '';
        if (!value.startsWith('http')) continue;
        if (key.contains('image_url') || key.contains('violation')) {
          urls.add(value);
        }
      }
    }
    return urls.toList();
  }

  Future<void> _downloadAbnormalityPdf() async {
    if (_selectedTankId == null || _isAllTanks) {
      _snack('Select a single tank for abnormality report');
      return;
    }

    setState(() => _abnormalityExporting = true);
    try {
      final selectedTank = _selectedTank;
      if (selectedTank == null) {
        _snack('Selected tank not found');
        return;
      }

      final window = _abnormalityWindow();
      final alertsSnap = await DatabaseModeService.ref('alerts').get();
      final completedSnap = await DatabaseModeService.ref('completed_tasks').get();

      final alerts = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      final imageUrls = <String>{};

      if (alertsSnap.exists && alertsSnap.value is Map) {
        final raw = Map<dynamic, dynamic>.from(alertsSnap.value as Map);
        for (final v in raw.values) {
          final m = Map<dynamic, dynamic>.from(v as Map);
          if (m['tank_id']?.toString() != _selectedTankId) continue;
          if (!_inRange(_alertTime(m), window)) continue;
          imageUrls.addAll(_extractAlertImageUrls(m));
          alerts.add(m.map((k, val) => MapEntry(k.toString(), val)));
        }
      }

      if (completedSnap.exists && completedSnap.value is Map) {
        final raw = Map<dynamic, dynamic>.from(completedSnap.value as Map);
        for (final v in raw.values) {
          final m = Map<dynamic, dynamic>.from(v as Map);
          final alertMap = m['alert'] is Map
              ? Map<dynamic, dynamic>.from(m['alert'] as Map)
              : <dynamic, dynamic>{};
          if (alertMap['tank_id']?.toString() != _selectedTankId) continue;
          if (!_inRange(m['completed_at']?.toString(), window)) continue;
          imageUrls.addAll(_extractAlertImageUrls(alertMap));
          completed.add({
            ...m.map((k, val) => MapEntry(k.toString(), val)),
            'alert': alertMap.map((k, val) => MapEntry(k.toString(), val)),
          });
        }
      }

      final includeAlerts = _abnormalityType == _AbnormalityType.alerts ||
          _abnormalityType == _AbnormalityType.both;
      final includeCompleted = _abnormalityType == _AbnormalityType.completed ||
          _abnormalityType == _AbnormalityType.both;
      final pdfImages = <MapEntry<String, pw.MemoryImage>>[];
      for (final url in imageUrls) {
        try {
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode < 200 || resp.statusCode >= 300) continue;
          if (resp.bodyBytes.isEmpty) continue;
          pdfImages.add(MapEntry(url, pw.MemoryImage(resp.bodyBytes)));
        } catch (_) {}
      }

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          build: (_) {
            final widgets = <pw.Widget>[
              pw.Text(
                'Abnormality Report',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Tank: ${selectedTank.tankName} (${selectedTank.tankCode})'),
              pw.Text(
                  'Range: ${DateFormat('dd MMM yyyy').format(window.start)} - ${DateFormat('dd MMM yyyy').format(window.end)}'),
              pw.Text('Type: ${_abnormalityType.label}'),
              pw.SizedBox(height: 14),
            ];

            if (includeAlerts) {
              widgets.add(pw.Text('Abnormalities (Alerts)',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
              widgets.add(pw.SizedBox(height: 6));
              if (alerts.isEmpty) {
                widgets.add(pw.Text('No alert records in selected range.'));
              } else {
                widgets.add(pw.TableHelper.fromTextArray(
                  headers: const ['Time', 'Severity', 'Param', 'Value', 'Status'],
                  data: alerts.map((a) {
                    return [
                      _fmt(_alertTime(a), pattern: 'dd-MM-yyyy HH:mm'),
                      _alertSeverity(a),
                      _alertParamLabel(a),
                      _alertParamValue(a),
                      _alertStatus(a),
                    ];
                  }).toList(),
                ));
              }
              widgets.add(pw.SizedBox(height: 12));
            }

            if (includeCompleted) {
              widgets.add(pw.Text('Completed Tasks',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
              widgets.add(pw.SizedBox(height: 6));
              if (completed.isEmpty) {
                widgets.add(pw.Text('No completed records in selected range.'));
              } else {
                widgets.add(pw.TableHelper.fromTextArray(
                  headers: const ['Completed At', 'By', 'Param', 'Value', 'Severity'],
                  data: completed.map((c) {
                    final alert = c['alert'] as Map<String, dynamic>? ?? {};
                    return [
                      _fmt(c['completed_at']?.toString(),
                          pattern: 'dd-MM-yyyy HH:mm'),
                      c['completed_by']?.toString() ?? '-',
                      _alertParamLabel(alert),
                      _alertParamValue(alert),
                      _alertSeverity(alert),
                    ];
                  }).toList(),
                ));
              }
            }

            if (pdfImages.isNotEmpty) {
              widgets.add(pw.SizedBox(height: 12));
              widgets.add(pw.Text('Attached Images',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)));
              widgets.add(pw.SizedBox(height: 6));

              for (final image in pdfImages) {
                widgets.add(
                  pw.UrlLink(
                    destination: image.key,
                    child: pw.Text(
                      image.key,
                      style: pw.TextStyle(
                        fontSize: 8,
                        decoration: pw.TextDecoration.underline,
                        color: pdf.PdfColors.blue700,
                      ),
                    ),
                  ),
                );
                widgets.add(pw.SizedBox(height: 4));
                widgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Image(image.value, fit: pw.BoxFit.contain),
                  ),
                );
              }
            }

            return widgets;
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/abnormality_${selectedTank.tankCode}_$ts.pdf');
      await file.writeAsBytes(await doc.save(), flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Abnormality Report');
    } catch (e) {
      _snack('Abnormality PDF failed: $e');
    } finally {
      if (mounted) setState(() => _abnormalityExporting = false);
    }
  }

  // ── Derived helpers ────────────────────────────────────────────────────────

  bool get _isAllTanks => _selectedTankId == _kAllTanksId;

  TankModel? get _selectedTank => _selectedTankId == null || _isAllTanks
      ? null
      : widget.tanks
          .cast<TankModel?>()
          .firstWhere((t) => t!.id == _selectedTankId, orElse: () => null);

  List<Map<String, dynamic>> get _graphableParams {
    final t = _selectedTank;
    if (t == null) return [];
    return t.inspectionProperties
        .where((p) => _isGraphable(p['type'] as String?))
        .toList();
  }

  DateTime get _rangeFrom {
    final now = DateTime.now();
    switch (_timeline) {
      case _Timeline.week:
        return now.subtract(const Duration(days: 7));
      case _Timeline.month:
        return now.subtract(const Duration(days: 30));
      case _Timeline.year:
        return DateTime(now.year - 1, now.month, now.day);
      case _Timeline.custom:
        return _customFrom ?? now.subtract(const Duration(days: 7));
    }
  }

  DateTime get _rangeTo {
    if (_timeline == _Timeline.custom && _customTo != null) {
      return DateTime(
          _customTo!.year, _customTo!.month, _customTo!.day, 23, 59, 59);
    }
    return DateTime.now();
  }

  // ── Data retrieval (cache-first) ───────────────────────────────────────────

  Future<void> _ensureCached(String tankId) async {
    if (_cache.containsKey(tankId)) return;
    debugPrint('[Trends] Fetching from DB for tank=$tankId');
    final all = await _repo.getAllReadings();
    final filtered = all.where((r) => r.tankId == tankId).toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    _cache[tankId] = filtered;
    debugPrint('[Trends] Cached ${filtered.length} readings for tank=$tankId');
  }

  /// Returns readings for [tankId] within the selected date range,
  /// always sorted oldest → newest.
  List<ReadingModel> _filtered(String tankId) {
    final from = _rangeFrom;
    final to = _rangeTo;
    final list = (_cache[tankId] ?? []).where((r) {
      final t = DateTime.tryParse(r.capturedAt);
      if (t == null) return false;
      return !t.isBefore(from) && !t.isAfter(to);
    }).toList()
      ..sort((a, b) =>
          DateTime.parse(a.capturedAt).compareTo(DateTime.parse(b.capturedAt)));
    return list;
  }

  // ── Show trend ─────────────────────────────────────────────────────────────
  Future<void> _showTrend() async {
    if (_selectedTankId == null) {
      _snack('Select a tank first');
      return;
    }
    if (!_isAllTanks && _selectedParam == null) {
      _snack('Select a parameter');
      return;
    }
    if (_timeline == _Timeline.custom &&
        (_customFrom == null || _customTo == null)) {
      _snack('Set both From and To dates for custom range');
      return;
    }

    setState(() {
      _loading = true;
      _chartReady = false;
    });
    try {
      if (_isAllTanks) {
        for (final t in widget.tanks) {
          await _ensureCached(t.id);
        }
      } else {
        await _ensureCached(_selectedTankId!);
      }
      setState(() {
        _loading = false;
        _chartReady = true;
      });
    } catch (e) {
      setState(() => _loading = false);
      _snack('Load failed: $e');
    }
  }

  // // ── Excel export ───────────────────────────────────────────────────────────
  // Future<void> _exportExcel() async {
  //   if (!_chartReady && _cache.isEmpty) { _snack('Load data first'); return; }
  //   setState(() => _exporting = true);
  //   try {
  //     final excel = xl.Excel.createExcel();

  //     final from    = _rangeFrom;
  //     final to      = _rangeTo;
  //     final fromStr = _fmtFile(from);
  //     final toStr   = _fmtFile(to);

  //     final tanksToExport = _isAllTanks
  //         ? widget.tanks
  //         : widget.tanks.where((t) => t.id == _selectedTankId!).toList();

  //     // ── Sheet 1: Summary ──────────────────────────────────────────────────
  //     final summarySheet = excel['Summary'];
  //     summarySheet.appendRow([
  //       xl.TextCellValue('Tank ID'),
  //       xl.TextCellValue('Tank Name'),
  //       xl.TextCellValue('Inspection Date'),
  //       xl.TextCellValue('Inspection Time'),
  //       xl.TextCellValue('Captured By'),
  //     ]);

  //     for (final tank in tanksToExport) {
  //       for (final r in _filtered(tank.id)) {
  //         final dt = DateTime.tryParse(r.capturedAt)?.toLocal();
  //         summarySheet.appendRow([
  //           xl.TextCellValue(tank.tankCode),
  //           xl.TextCellValue(tank.tankName),
  //           xl.TextCellValue(
  //               dt != null ? DateFormat('dd-MM-yyyy').format(dt) : '—'),
  //           xl.TextCellValue(
  //               dt != null ? DateFormat('HH:mm:ss').format(dt) : '—'),
  //           xl.TextCellValue(r.capturedByName),
  //         ]);
  //       }
  //     }

  //     // ── Sheets 2..N: one per tank ─────────────────────────────────────────
  //     for (final tank in tanksToExport) {
  //       final paramLabels = tank.inspectionProperties
  //           .map((p) => p['label'] as String? ?? '')
  //           .where((l) => l.isNotEmpty)
  //           .toList();

  //       final sheetName =
  //           tank.tankName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
  //       final sheet = excel[
  //           sheetName.length > 31
  //               ? sheetName.substring(0, 31)
  //               : sheetName];
  //       sheet.appendRow([
  //         xl.TextCellValue('Tank ID'),
  //         xl.TextCellValue('Tank Name'),
  //         xl.TextCellValue('Captured At'),
  //         xl.TextCellValue('Captured By'),
  //         ...paramLabels.map((l) => xl.TextCellValue(l)),
  //       ]);

  //       for (final r in _filtered(tank.id)) {
  //         final paramCells = paramLabels.map((l) {
  //           final v = r.inspectionValues[l];
  //           if (v is Map) {
  //             return xl.TextCellValue(
  //                 '${v['left'] ?? ''} | ${v['right'] ?? ''}');
  //           }
  //           return xl.TextCellValue(v?.toString() ?? '');
  //         }).toList();

  //         sheet.appendRow([
  //           xl.TextCellValue(tank.tankCode),
  //           xl.TextCellValue(tank.tankName),
  //           xl.TextCellValue(
  //               _fmt(r.capturedAt, pattern: 'dd-MM-yyyy HH:mm:ss')),
  //           xl.TextCellValue(r.capturedByName),
  //           ...paramCells,
  //         ]);
  //       }
  //     }

  //     // ── File name ──────────────────────────────────────────────────────────
  //     final tankNames = tanksToExport.map((t) => t.tankCode).join('_');
  //     final suffix =
  //         tankNames.length > 40 ? '${tankNames.substring(0, 40)}…' : tankNames;
  //     final fileName =
  //         'Lubrication_Report_${fromStr}_${toStr}_$suffix.xlsx';

  //     final dir  = await getTemporaryDirectory();
  //     final file = File('${dir.path}/$fileName');
  //     await file.writeAsBytes(excel.save()!);
  //     debugPrint('[Trends] Excel saved → ${file.path}');
  //     await Share.shareXFiles([XFile(file.path)], text: 'Lubrication Report');
  //   } catch (e) {
  //     _snack('Excel export failed: $e');
  //     debugPrint('[Trends] Excel error: $e');
  //   } finally {
  //     if (mounted) setState(() => _exporting = false);
  //   }
  // }

  // ── Excel export ───────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    // if (!_chartReady && _cache.isEmpty) {
    //   _snack('Load data first');
    //   return;
    // }
    setState(() => _exporting = true);
    try {
      final excel = xl.Excel.createExcel();
      String _fmtNullableTs(String? iso) {
        if (iso == null || iso.trim().isEmpty) return '';
        final dt = DateTime.tryParse(iso)?.toLocal();
        if (dt == null) return '';
        return DateFormat('dd-MM-yyyy HH:mm:ss').format(dt);
      }

      final from = _rangeFrom;
      final to = _rangeTo;
      final fromStr = _fmtFile(from);
      final toStr = _fmtFile(to);

      final tanksToExport = _isAllTanks
          ? widget.tanks
          : widget.tanks.where((t) => t.id == _selectedTankId!).toList();

      // ── Sheet 1: Summary ──────────────────────────────────────────────────
      final summarySheet = excel['Summary'];
      summarySheet.appendRow([
        xl.TextCellValue('Tank ID'),
        xl.TextCellValue('Tank Name'),
        xl.TextCellValue('Captured At Start'),
        xl.TextCellValue('Captured At'),
        xl.TextCellValue('Inspection Date'),
        xl.TextCellValue('Inspection Time'),
        xl.TextCellValue('Captured By'),
      ]);

      // for (final tank in tanksToExport) {
      //   for (final r in _filtered(tank.id)) {
      //     final dt = DateTime.tryParse(r.capturedAt)?.toLocal();
      //     summarySheet.appendRow([
      //       xl.TextCellValue(tank.tankCode),
      //       xl.TextCellValue(tank.tankName),
      //       xl.TextCellValue(
      //           dt != null ? DateFormat('dd-MM-yyyy').format(dt) : '—'),
      //       xl.TextCellValue(
      //           dt != null ? DateFormat('HH:mm:ss').format(dt) : '—'),
      //       xl.TextCellValue(r.capturedByName),
      //     ]);
      //   }
      // }

       for (final tank in tanksToExport) {

  final allReadings = await _repo.getAllReadings();

  final readings = allReadings.where((r) {
    if (r.tankId != tank.id) return false;

    final dt = DateTime.tryParse(r.capturedAt);
    if (dt == null) return false;

    return !dt.isBefore(_rangeFrom) &&
           !dt.isAfter(_rangeTo);
  }).toList();

  for (final r in readings) {
          final dt = DateTime.tryParse(r.capturedAt)?.toLocal();
          summarySheet.appendRow([
            xl.TextCellValue(tank.tankCode),
            xl.TextCellValue(tank.tankName),
            xl.TextCellValue(_fmtNullableTs(r.capturedAtStart)),
            xl.TextCellValue(_fmtNullableTs(r.capturedAt)),
            xl.TextCellValue(
                dt != null ? DateFormat('dd-MM-yyyy').format(dt) : '—'),
            xl.TextCellValue(
                dt != null ? DateFormat('HH:mm:ss').format(dt) : '—'),
            xl.TextCellValue(r.capturedByName),
          ]);
        }
      }

      // ── Sheets 2..N: one per tank ─────────────────────────────────────────
      for (final tank in tanksToExport) {
        // Build column descriptors: each param may produce 1 or 2 columns
        // depending on whether it has capture_image == true.
        // Descriptor: { 'label': String, 'id': String, 'hasImage': bool }
        final colDescs = <Map<String, dynamic>>[];
        for (final p in tank.inspectionProperties) {
          final type = p['type'] as String? ?? 'text';
          if (type == 'group') continue;
          final label = p['label'] as String? ?? '';
          final id = p['id'] as String? ?? '';
          final hasImage = p['capture_image'] == true;
          if (label.isEmpty) continue;
          colDescs.add({'label': label, 'id': id, 'hasImage': hasImage});
        }

        // Build header row
        final headerCells = <xl.CellValue>[
          xl.TextCellValue('Tank ID'),
          xl.TextCellValue('Tank Name'),
          xl.TextCellValue('Captured At Start'),
          xl.TextCellValue('Captured At'),
          xl.TextCellValue('Captured By'),
        ];
        for (final col in colDescs) {
          headerCells.add(xl.TextCellValue(col['label'] as String));
          if (col['hasImage'] as bool) {
            // Extra column immediately after the param value column
            headerCells.add(xl.TextCellValue('${col['label']} — Photo URL'));
          }
          
        }

        final sheetName =
            tank.tankName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final sheet = excel[
            sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName];
        sheet.appendRow(headerCells);

        // Build data rows
        // Build data rows

final allReadings = await _repo.getAllReadings();

final readings = allReadings.where((r) {
  if (r.tankId != tank.id) return false;

  final dt = DateTime.tryParse(r.capturedAt);
  if (dt == null) return false;

  return !dt.isBefore(_rangeFrom) &&
         !dt.isAfter(_rangeTo);
}).toList();

for (final r in readings) {
          final dataCells = <xl.CellValue>[
            xl.TextCellValue(tank.tankCode),
            xl.TextCellValue(tank.tankName),
            xl.TextCellValue(_fmtNullableTs(r.capturedAtStart)),
            xl.TextCellValue(_fmtNullableTs(r.capturedAt)),
            xl.TextCellValue(r.capturedByName),
          ];

          for (final col in colDescs) {
            final label = col['label'] as String;
            final id = col['id'] as String;
            final hasImage = col['hasImage'] as bool;
            debugPrint(
  'LOOKUP => label=$label value=${r.inspectionValues[label]} keys=${r.inspectionValues.keys.toList()}',
);
            // Param value cell
            final v = r.inspectionValues[label];
            if (v is Map) {
              dataCells.add(
                  xl.TextCellValue('${v['left'] ?? ''} | ${v['right'] ?? ''}'));
            } else {
              dataCells.add(xl.TextCellValue(v?.toString() ?? ''));
            }

            // Photo URL cell (immediately after value, only if hasImage)
            if (hasImage) {
              // Key convention matches reading_entry_screen: "<id>__image_url"
              final imageUrl =
                  r.inspectionValues['${id}__image_url']?.toString() ?? '';
              dataCells.add(xl.TextCellValue(imageUrl));
            }
            debugPrint('COLUMN => ${col['label']}');
            debugPrint('VALUES => ${r.inspectionValues}');
          }

          sheet.appendRow(dataCells);
        }

//         // Build data rows
//         for (final r in _filtered(tank.id)) {
//           final dataCells = <xl.CellValue>[
//             xl.TextCellValue(tank.tankCode),
//             xl.TextCellValue(tank.tankName),
//             xl.TextCellValue(
//                 _fmt(r.capturedAt, pattern: 'dd-MM-yyyy HH:mm:ss')),
//             xl.TextCellValue(r.capturedByName),
//           ];

//           for (final col in colDescs) {
//             final label = col['label'] as String;
//             final id = col['id'] as String;
//             final hasImage = col['hasImage'] as bool;
//             debugPrint(
//   'LOOKUP => label=$label value=${r.inspectionValues[label]} keys=${r.inspectionValues.keys.toList()}',
// );
//             // Param value cell
//             final v = r.inspectionValues[label];
//             if (v is Map) {
//               dataCells.add(
//                   xl.TextCellValue('${v['left'] ?? ''} | ${v['right'] ?? ''}'));
//             } else {
//               dataCells.add(xl.TextCellValue(v?.toString() ?? ''));
//             }

//             // Photo URL cell (immediately after value, only if hasImage)
//             if (hasImage) {
//               // Key convention matches reading_entry_screen: "<id>__image_url"
//               final imageUrl =
//                   r.inspectionValues['${id}__image_url']?.toString() ?? '';
//               dataCells.add(xl.TextCellValue(imageUrl));
//             }
//             debugPrint('COLUMN => ${col['label']}');
//             debugPrint('VALUES => ${r.inspectionValues}');
//           }

//           sheet.appendRow(dataCells);
//         }
      }

      // ── File name ────────────────────────────────────────────────────────
      final tankNames = tanksToExport.map((t) => t.tankCode).join('_');
      final suffix =
          tankNames.length > 40 ? '${tankNames.substring(0, 40)}…' : tankNames;
      final fileName = 'Lubrication_Report_${fromStr}_${toStr}_$suffix.xlsx';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(excel.save()!);
      debugPrint('[Trends] Excel saved → ${file.path}');
      await Share.shareXFiles([XFile(file.path)], text: 'Lubrication Report');
    } catch (e) {
      _snack('Excel export failed: $e');
      debugPrint('[Trends] Excel error: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── PNG export ─────────────────────────────────────────────────────────────
  Future<void> _exportPng() async {
    try {
      final boundary = _chartKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _snack('Chart not rendered yet');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('PNG encode failed');
      final dir = await getTemporaryDirectory();
      final name = '${_selectedTank?.tankCode ?? 'trends'}_'
          '${_selectedParam?['label'] ?? 'all'}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)],
          text: '${_selectedTank?.tankName ?? 'All Tanks'} — '
              '${_selectedParam?['label'] ?? 'Timeline'}');
    } catch (e) {
      _snack('PNG export failed: $e');
    }
  }

  // ── QR scan ────────────────────────────────────────────────────────────────
  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (result == null || !mounted) return;
    try {
      Map<String, dynamic>? data;
      try {
        final json = result.trim();
        if (json.startsWith('{')) {
          final parts = json
              .replaceAll('{', '')
              .replaceAll('}', '')
              .replaceAll('"', '')
              .split(',');
          final m = <String, String>{};
          for (final p in parts) {
            final kv = p.split(':');
            if (kv.length >= 2) {
              m[kv[0].trim()] = kv.sublist(1).join(':').trim();
            }
          }
          data = m;
        }
      } catch (_) {}

      final tankId = data?['tank_id'] as String?;
      final tankCode = data?['tank_code'] as String?;

      TankModel? found;
      if (tankId != null) {
        found = widget.tanks
            .cast<TankModel?>()
            .firstWhere((t) => t!.id == tankId, orElse: () => null);
      }
      if (found == null && tankCode != null) {
        found = widget.tanks
            .cast<TankModel?>()
            .firstWhere((t) => t!.tankCode == tankCode, orElse: () => null);
      }
      if (found != null) {
        setState(() {
          _selectedTankId = found!.id;
          _selectedParam = null;
          _chartReady = false;
        });
        _snack('Tank selected: ${found.tankName}');
      } else {
        _snack('Tank not found for QR');
      }
    } catch (e) {
      _snack('Invalid QR: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText)),
      backgroundColor: _kCard,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Date picker ────────────────────────────────────────────────────────────
  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: (isFrom ? _customFrom : _customTo) ?? now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: _kCopper, surface: _kCard, onSurface: _kText),
        ),
        child: child!,
      ),
    );
    if (d == null) return;
    setState(() => isFrom ? _customFrom = d : _customTo = d);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tank selection ──────────────────────────────────────────────
            _SecLabel('DATA SOURCE'),
            const SizedBox(height: 10),
            _buildTankRow(),

            const SizedBox(height: 16),

            // ── Timeline ────────────────────────────────────────────────────
            _SecLabel('TIME RANGE'),
            const SizedBox(height: 10),
            _buildTimelineRow(),

            if (_timeline == _Timeline.custom) ...[
              const SizedBox(height: 10),
              _buildCustomDateRow(),
            ],

            const SizedBox(height: 16),

            // ── Excel export ─────────────────────────────────────────────────
            _buildExcelButton(),

            const SizedBox(height: 16),

            // ── Parameter selection ───────────────────────────────────────────
            if (!_isAllTanks && _selectedTankId != null) ...[
              _buildParamRow(),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.info_outline_rounded, size: 11, color: _kSubL),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Only numerical and categorical parameters are graphable.',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _kSubL),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // ── Show Trend button ─────────────────────────────────────────────
            _buildShowTrendButton(),

            const SizedBox(height: 24),

            // ── Chart ─────────────────────────────────────────────────────────
            if (_chartReady) ...[
              _buildChartSection(),
              const SizedBox(height: 14),
              _buildPngButton(),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Text(
                'Abnormality report download moved to Dashboard tab.',
                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tank row ───────────────────────────────────────────────────────────────
  Widget _buildTankRow() {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(
        value: _kAllTanksId,
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kCopper.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: _kCopper.withOpacity(0.3)),
            ),
            child: const Icon(Icons.water_outlined, size: 14, color: _kCopper),
          ),
          const SizedBox(width: 10),
          Text('All Tanks',
              style: GoogleFonts.dmSans(
                  color: _kText, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
      ...widget.tanks.map((t) => DropdownMenuItem<String>(
            value: t.id,
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _kCopper.withOpacity(0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kCopper.withOpacity(0.25)),
                ),
                child: Center(
                  child: Text(
                    t.tankCode.isNotEmpty ? t.tankCode[0].toUpperCase() : '?',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: _kCopper,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.tankName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                              color: _kText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${t.tankCode}${t.location != null ? " · ${t.location}" : ""}',
                        overflow: TextOverflow.ellipsis,
                        style:
                            GoogleFonts.spaceGrotesk(fontSize: 9, color: _kSub),
                      ),
                    ]),
              ),
            ]),
          )),
    ];

    return Row(children: [
      Expanded(
        child: _DropContainer(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTankId,
              isExpanded: true,
              dropdownColor: _kCard,
              iconEnabledColor: _kSub,
              hint: Text('Select tank or All Tanks…',
                  style: GoogleFonts.dmSans(color: _kSubL, fontSize: 13)),
              items: items,
              onChanged: (v) => setState(() {
                _selectedTankId = v;
                _selectedParam = null;
                _chartReady = false;
              }),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: _scanQr,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _kTeal.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kTeal.withOpacity(0.35)),
          ),
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: _kTeal, size: 22),
        ),
      ),
    ]);
  }

  // ── Timeline chips ──────────────────────────────────────────────────────────
  Widget _buildTimelineRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _Timeline.values.map((t) {
          final sel = _timeline == t;
          return GestureDetector(
            onTap: () => setState(() {
              _timeline = t;
              _chartReady = false;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? _kCopper.withOpacity(0.13) : _kSurface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: sel ? _kCopper : _kBorder, width: sel ? 1.5 : 1),
              ),
              child: Text(t.label,
                  style: GoogleFonts.dmSans(
                    color: sel ? _kCopper : _kSub,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 13,
                  )),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Custom date pickers ─────────────────────────────────────────────────────
  Widget _buildCustomDateRow() {
    return Row(children: [
      Expanded(
        child: _DateBtn(
          label: _customFrom == null
              ? 'From date'
              : DateFormat('dd MMM yyyy').format(_customFrom!),
          icon: Icons.calendar_today_outlined,
          onTap: () => _pickDate(true),
          active: _customFrom != null,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _DateBtn(
          label: _customTo == null
              ? 'To date'
              : DateFormat('dd MMM yyyy').format(_customTo!),
          icon: Icons.event_outlined,
          onTap: () => _pickDate(false),
          active: _customTo != null,
        ),
      ),
    ]);
  }

  // ── Parameter row ───────────────────────────────────────────────────────────
  Widget _buildParamRow() {
    final params = _graphableParams;
    return _DropContainer(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Map<String, dynamic>>(
          value: _selectedParam,
          isExpanded: true,
          dropdownColor: _kCard,
          iconEnabledColor: params.isEmpty ? _kSubL : _kSub,
          hint: Text(
            params.isEmpty
                ? 'No graphable parameters for this tank'
                : 'Select parameter…',
            style: GoogleFonts.dmSans(color: _kSubL, fontSize: 13),
          ),
          items: params.map((p) {
            final type = p['type'] as String? ?? '';
            final label = p['label'] as String? ?? '';
            final bc = _typeColor(type);
            return DropdownMenuItem<Map<String, dynamic>>(
              value: p,
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: bc.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: bc.withOpacity(0.4)),
                  ),
                  child: Text(_typeShort(type),
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color: bc,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            );
          }).toList(),
          onChanged: params.isEmpty
              ? null
              : (v) => setState(() {
                    _selectedParam = v;
                    _chartReady = false;
                  }),
        ),
      ),
    );
  }

  // ── Excel button ────────────────────────────────────────────────────────────
  Widget _buildExcelButton() {
    final canExport = _selectedTankId != null;
    return GestureDetector(
      onTap: canExport && !_exporting ? _exportExcel : null,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: canExport ? _kSuccess.withOpacity(0.09) : _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: canExport ? _kSuccess.withOpacity(0.4) : _kBorder),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_exporting)
            const SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(color: _kSuccess, strokeWidth: 2))
          else
            Icon(Icons.table_chart_outlined,
                color: canExport ? _kSuccess : _kSubL, size: 18),
          const SizedBox(width: 8),
          Text(
            _exporting ? 'Preparing Excel…' : 'Download Excel Report',
            style: GoogleFonts.dmSans(
              color: canExport ? _kSuccess : _kSubL,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Show Trend button ────────────────────────────────────────────────────────
  Widget _buildShowTrendButton() {
    final ready = _selectedTankId != null &&
        (_isAllTanks || _selectedParam != null) &&
        !(_timeline == _Timeline.custom &&
            (_customFrom == null || _customTo == null));

    return GestureDetector(
      onTap: ready && !_loading ? _showTrend : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: ready
              ? const LinearGradient(
                  colors: [_kCopperD, _kCopper],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)
              : null,
          color: ready ? null : _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: ready ? _kCopper : _kBorder, width: ready ? 0 : 1),
          boxShadow: ready
              ? [
                  BoxShadow(
                      color: _kCopper.withOpacity(0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 5))
                ]
              : [],
        ),
        child: Center(
          child: _loading
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('Loading…',
                      style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.show_chart_rounded,
                      color: ready ? Colors.white : _kSubL, size: 20),
                  const SizedBox(width: 8),
                  Text('Show Trend',
                      style: GoogleFonts.dmSans(
                        color: ready ? Colors.white : _kSubL,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      )),
                ]),
        ),
      ),
    );
  }

  // ── PNG export button ────────────────────────────────────────────────────────
  Widget _buildPngButton() {
    return GestureDetector(
      onTap: _exportPng,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorderH),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.image_outlined, color: _kCopper, size: 17),
          const SizedBox(width: 7),
          Text('Export Chart as PNG',
              style: GoogleFonts.dmSans(
                  color: _kText, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _buildAbnormalityReportSection() {
    final canDownload = _selectedTankId != null && !_isAllTanks;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Download Abnormality Reports',
            style: GoogleFonts.spaceGrotesk(
              color: _kText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DropContainer(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_AbnormalityRange>(
                      value: _abnormalityRange,
                      isExpanded: true,
                      dropdownColor: _kCard,
                      iconEnabledColor: _kSub,
                      items: _AbnormalityRange.values
                          .map((v) => DropdownMenuItem<_AbnormalityRange>(
                                value: v,
                                child: Text(v.label,
                                    style: GoogleFonts.dmSans(
                                        color: _kText, fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _abnormalityRange = v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropContainer(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_AbnormalityType>(
                      value: _abnormalityType,
                      isExpanded: true,
                      dropdownColor: _kCard,
                      iconEnabledColor: _kSub,
                      items: _AbnormalityType.values
                          .map((v) => DropdownMenuItem<_AbnormalityType>(
                                value: v,
                                child: Text(v.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.dmSans(
                                        color: _kText, fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _abnormalityType = v);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: canDownload && !_abnormalityExporting ? _downloadAbnormalityPdf : null,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: canDownload ? _kDanger.withOpacity(0.12) : _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: canDownload ? _kDanger.withOpacity(0.4) : _kBorder),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_abnormalityExporting)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: _kDanger, strokeWidth: 2))
                else
                  Icon(Icons.picture_as_pdf_outlined,
                      color: canDownload ? _kDanger : _kSubL, size: 18),
                const SizedBox(width: 8),
                Text(
                  _abnormalityExporting
                      ? 'Preparing PDF...'
                      : 'Download Alert Report (PDF)',
                  style: GoogleFonts.dmSans(
                    color: canDownload ? _kDanger : _kSubL,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ),
          if (!canDownload) ...[
            const SizedBox(height: 8),
            Text(
              'Select a single tank (not All Tanks) to download abnormality reports.',
              style: GoogleFonts.dmSans(color: _kSubL, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // ── Chart section ────────────────────────────────────────────────────────────
  Widget _buildChartSection() {
    return RepaintBoundary(
      key: _chartKey,
      child: Container(
        color: _kBg,
        child: Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChartTitle(),
              _buildChartBody(),
              _buildLegend(),
              _buildReadingFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chart title strip ────────────────────────────────────────────────────────
  Widget _buildChartTitle() {
    final tankLabel = _isAllTanks
        ? 'All Tanks (${widget.tanks.length})'
        : (_selectedTank?.tankName ?? '—');
    final paramLabel = _isAllTanks
        ? 'Reading Timeline'
        : (_selectedParam?['label'] as String? ?? '—');
    final type = _isAllTanks ? null : _selectedParam?['type'] as String?;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
                color: _kCopper, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tankLabel,
                style: GoogleFonts.dmSans(
                    color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(paramLabel,
                style: GoogleFonts.spaceGrotesk(
                    color: _kCopper,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
            const SizedBox(height: 4),
            Row(children: [
              _MetaChip(
                  icon: Icons.calendar_today_outlined,
                  label: DateFormat('dd MMM yyyy').format(_rangeFrom)),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, size: 10, color: _kSubL),
              const SizedBox(width: 6),
              _MetaChip(
                  icon: Icons.event_rounded,
                  label: DateFormat('dd MMM yyyy').format(_rangeTo)),
            ]),
          ]),
        ),
        if (type != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _typeColor(type).withOpacity(0.13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _typeColor(type).withOpacity(0.35)),
            ),
            child: Text(_typeShort(type),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    color: _typeColor(type),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
      ]),
    );
  }

  // ── Chart body dispatcher ────────────────────────────────────────────────────
  Widget _buildChartBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 16, 8),
      child: SizedBox(
        height: 260,
        child: _isAllTanks ? _buildAllTanksChart() : _buildParamChart(),
      ),
    );
  }

  Widget _buildParamChart() {
    final type = _selectedParam?['type'] as String? ?? 'number';
    final label = _selectedParam?['label'] as String? ?? '';
    final data = _filtered(_selectedTankId!);

    if (data.isEmpty) return _noData('No readings in this time range');

    switch (type) {
      case 'dropdown':
        return _barChart(label, data);
      case 'dual_text':
        return _dualLineChart(label, data);
      default:
        return _singleLineChart(label, data);
    }
  }

  // ── All-tanks multi-line chart ─────────────────────────────────────────────
  // Each tank gets ONE line whose Y position is the tank's index (1-based).
  // X axis = reading index (oldest→newest). Bottom labels = sparse timestamps.
  // Widget _buildAllTanksChart() {
  //   final lines     = <LineChartBarData>[];
  //   final xLabels   = <int, String>{};   // x-index → formatted date label
  //   int   maxPoints = 0;

  //   int colorIdx = 0;
  //   for (final tank in widget.tanks) {
  //     // _filtered already returns sorted oldest→newest
  //     final data = _filtered(tank.id);
  //     if (data.isEmpty) { colorIdx++; continue; }

  //     if (data.length > maxPoints) maxPoints = data.length;

  //     final color  = _kMultiPalette[colorIdx % _kMultiPalette.length];
  //     final spots  = <FlSpot>[];
  //     final yValue = (colorIdx + 1).toDouble(); // one horizontal level per tank

  //     for (int i = 0; i < data.length; i++) {
  //       final xIdx = i + 1;
  //       spots.add(FlSpot(xIdx.toDouble(), yValue));
  //       // Overwrite is fine — label at position i is the same regardless of tank
  //       xLabels[xIdx] = _fmt(data[i].capturedAt);
  //     }

  //     lines.add(LineChartBarData(
  //       spots: spots,
  //       color: color,
  //       barWidth: 3,
  //       isCurved: false,
  //       dotData: FlDotData(
  //         show: true,
  //         getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
  //             radius: 5,
  //             color: color,
  //             strokeWidth: 1.5,
  //             strokeColor: _kBg),
  //       ),
  //       belowBarData: BarAreaData(show: false),
  //     ));
  //     colorIdx++;
  //   }

  //   if (lines.isEmpty) return _noData('No readings in this time range');

  //   return LineChart(LineChartData(
  //     borderData: _borderData,
  //     gridData:   _gridData,
  //     minX: 1,
  //     maxX: maxPoints.toDouble(),
  //     minY: 0,
  //     maxY: (widget.tanks.length + 1).toDouble(),
  //     titlesData: FlTitlesData(
  //       topTitles:
  //           const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  //       rightTitles:
  //           const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  //       leftTitles: AxisTitles(
  //         sideTitles: SideTitles(
  //           showTitles: true,
  //           reservedSize: 52,
  //           interval: 1,
  //           getTitlesWidget: (v, _) {
  //             final idx = v.toInt();
  //             if (idx < 1 || idx > widget.tanks.length) {
  //               return const SizedBox.shrink();
  //             }
  //             final code = widget.tanks[idx - 1].tankCode;
  //             return Padding(
  //               padding: const EdgeInsets.only(right: 4),
  //               child: Text(code,
  //                   style: GoogleFonts.spaceGrotesk(
  //                       fontSize: 8, color: _kSubL)),
  //             );
  //           },
  //         ),
  //       ),
  //       bottomTitles: AxisTitles(
  //         sideTitles: _bottomTitlesSparse(
  //             maxPoints, (idx) => xLabels[idx] ?? ''),
  //       ),
  //     ),
  //     lineBarsData: lines,
  //     lineTouchData: LineTouchData(
  //       touchTooltipData: LineTouchTooltipData(
  //         getTooltipColor: (_) => _kCard,
  //         tooltipBorderRadius: BorderRadius.circular(8),
  //         tooltipBorder: const BorderSide(color: _kBorder),
  //         getTooltipItems: (spots) => spots.map((s) {
  //           final tankIdx = s.y.toInt() - 1;
  //           final tankName = (tankIdx >= 0 && tankIdx < widget.tanks.length)
  //               ? widget.tanks[tankIdx].tankName
  //               : '';
  //           final dateLabel = xLabels[s.x.toInt()] ?? '';
  //           return LineTooltipItem(
  //             '$tankName\n$dateLabel',
  //             GoogleFonts.spaceGrotesk(
  //                 color: _kMultiPalette[tankIdx % _kMultiPalette.length],
  //                 fontWeight: FontWeight.w700,
  //                 fontSize: 11),
  //           );
  //         }).toList(),
  //       ),
  //     ),
  //   ));
  // }

  Widget _buildAllTanksChart() {
    // ── 1. Collect all unique timestamps across all tanks (oldest→newest) ──
    final allTimes = <DateTime>{};
    final tankData = <String, List<ReadingModel>>{};

    for (final tank in widget.tanks) {
      final data = _filtered(tank.id);
      tankData[tank.id] = data;
      for (final r in data) {
        final t = DateTime.tryParse(r.capturedAt);
        if (t != null) allTimes.add(t);
      }
    }

    if (allTimes.isEmpty) return _noData('No readings in this time range');

    // ── 2. Sort global timeline oldest → newest ────────────────────────────
    final globalTimes = allTimes.toList()..sort();

    // ── 3. Map each DateTime → X index (1-based) ──────────────────────────
    final timeToX = <DateTime, int>{};
    for (int i = 0; i < globalTimes.length; i++) {
      timeToX[globalTimes[i]] = i + 1;
    }

    // ── 4. Build X label map: xIndex → formatted label ────────────────────
    final xLabels = <int, String>{};
    for (int i = 0; i < globalTimes.length; i++) {
      xLabels[i + 1] = _fmt(globalTimes[i].toIso8601String());
    }

    // ── 5. Build one line per tank ────────────────────────────────────────
    final lines = <LineChartBarData>[];
    int colorIdx = 0;

    for (final tank in widget.tanks) {
      final data = tankData[tank.id] ?? [];
      if (data.isEmpty) {
        colorIdx++;
        continue;
      }

      final color = _kMultiPalette[colorIdx % _kMultiPalette.length];
      final spots = <FlSpot>[];

      for (final r in data) {
        final t = DateTime.tryParse(r.capturedAt);
        if (t == null) continue;
        // Find closest match in globalTimes (handles sub-second drift)
        DateTime bestMatch = globalTimes.first;
        int bestDiff = (globalTimes.first.difference(t).inMilliseconds).abs();
        for (final gt in globalTimes) {
          final diff = (gt.difference(t).inMilliseconds).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestMatch = gt;
          }
        }
        final xIdx = timeToX[bestMatch];
        if (xIdx == null) continue;
        final yValue = (colorIdx + 1).toDouble();
        spots.add(FlSpot(xIdx.toDouble(), yValue));
      }

      if (spots.isEmpty) {
        colorIdx++;
        continue;
      }

      lines.add(LineChartBarData(
        spots: spots,
        color: color,
        barWidth: 3,
        isCurved: false,
        dotData: FlDotData(
          show: true,
          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 5, color: color, strokeWidth: 1.5, strokeColor: _kBg),
        ),
        belowBarData: BarAreaData(show: false),
      ));
      colorIdx++;
    }

    if (lines.isEmpty) return _noData('No readings in this time range');

    final maxX = globalTimes.length.toDouble();

    return LineChart(LineChartData(
      borderData: _borderData,
      gridData: _gridData,
      minX: 1,
      maxX: maxX,
      minY: 0,
      maxY: (widget.tanks.length + 1).toDouble(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            interval: 1,
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              if (idx < 1 || idx > widget.tanks.length) {
                return const SizedBox.shrink();
              }
              final code = widget.tanks[idx - 1].tankCode;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(code,
                    style:
                        GoogleFonts.spaceGrotesk(fontSize: 8, color: _kSubL)),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: _bottomTitlesSparse(
              globalTimes.length, (idx) => xLabels[idx] ?? ''),
        ),
      ),
      lineBarsData: lines,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _kCard,
          tooltipBorderRadius: BorderRadius.circular(8),
          tooltipBorder: const BorderSide(color: _kBorder),
          getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
            final tankIdx = s.y.toInt() - 1;
            final tankName = (tankIdx >= 0 && tankIdx < widget.tanks.length)
                ? widget.tanks[tankIdx].tankName
                : '';
            final dateLabel = xLabels[s.x.toInt()] ?? '';
            return LineTooltipItem(
              '$tankName\n$dateLabel',
              GoogleFonts.spaceGrotesk(
                  color: _kMultiPalette[tankIdx % _kMultiPalette.length],
                  fontWeight: FontWeight.w700,
                  fontSize: 11),
            );
          }).toList(),
        ),
      ),
    ));
  }

  // ── Single line chart (number / slider) ───────────────────────────────────
  Widget _singleLineChart(String label, List<ReadingModel> data) {
    // LOCAL variables — NOT class fields
    final spots = <FlSpot>[];
    final xLabels = <int, String>{};

    for (int i = 0; i < data.length; i++) {
      final xIdx = i + 1;
      final raw = data[i].inspectionValues[label];
      final v = _toDouble(raw);
      if (v != null) {
        spots.add(FlSpot(xIdx.toDouble(), v));
        xLabels[xIdx] = _fmt(data[i].capturedAt);
      }
    }

    if (spots.isEmpty) return _noData('No numeric values for "$label"');

    return LineChart(LineChartData(
      borderData: _borderData,
      gridData: _gridData,
      minX: 1,
      maxX: spots.length.toDouble(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: _leftTitles),
        bottomTitles: AxisTitles(
            sideTitles:
                _bottomTitlesSparse(spots.length, (idx) => xLabels[idx] ?? '')),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: _kCopper,
          barWidth: 2.5,
          isCurved: true,
          curveSmoothness: 0.3,
          dotData: FlDotData(
            show: spots.length <= 30,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: _kCopper,
                strokeWidth: 1.5,
                strokeColor: _kCopperL),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                _kCopper.withOpacity(0.18),
                _kCopper.withOpacity(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      lineTouchData: _lineTouchData(
          (s) => '${s.y.toStringAsFixed(2)}\n${xLabels[s.x.toInt()] ?? ''}'),
    ));
  }

  // ── Dual line chart (dual_text) ────────────────────────────────────────────
  Widget _dualLineChart(String label, List<ReadingModel> data) {
    // LOCAL variables
    final leftSpots = <FlSpot>[];
    final rightSpots = <FlSpot>[];
    final xLabels = <int, String>{};

    for (int i = 0; i < data.length; i++) {
      final raw = data[i].inspectionValues[label];
      final x = (i + 1).toDouble();
      xLabels[i + 1] = _fmt(data[i].capturedAt);
      if (raw is Map) {
        final lv = _toDouble(raw['left']);
        final rv = _toDouble(raw['right']);
        if (lv != null) leftSpots.add(FlSpot(x, lv));
        if (rv != null) rightSpots.add(FlSpot(x, rv));
      }
    }

    if (leftSpots.isEmpty && rightSpots.isEmpty) {
      return _noData('No numeric dual-input values for "$label"');
    }

    final leftLabel = _selectedParam?['left_label'] as String? ?? 'Left';
    final rightLabel = _selectedParam?['right_label'] as String? ?? 'Right';
    final totalCount = data.length;

    return LineChart(LineChartData(
      borderData: _borderData,
      gridData: _gridData,
      minX: 1,
      maxX: totalCount.toDouble(),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: _leftTitles),
        bottomTitles: AxisTitles(
            sideTitles:
                _bottomTitlesSparse(totalCount, (idx) => xLabels[idx] ?? '')),
      ),
      lineBarsData: [
        if (leftSpots.isNotEmpty)
          LineChartBarData(
            spots: leftSpots,
            color: _kCopper,
            barWidth: 2.5,
            isCurved: true,
            curveSmoothness: 0.3,
            dotData: FlDotData(
              show: leftSpots.length <= 30,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: _kCopper,
                  strokeWidth: 1.5,
                  strokeColor: _kCopperL),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _kCopper.withOpacity(0.15),
                  _kCopper.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        if (rightSpots.isNotEmpty)
          LineChartBarData(
            spots: rightSpots,
            color: _kTeal,
            barWidth: 2.5,
            isCurved: true,
            curveSmoothness: 0.3,
            dotData: FlDotData(
              show: rightSpots.length <= 30,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: _kTeal,
                  strokeWidth: 1.5,
                  strokeColor: _kTeal.withOpacity(0.5)),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _kTeal.withOpacity(0.12),
                  _kTeal.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _kCard,
          tooltipBorderRadius: BorderRadius.circular(8),
          tooltipBorder: const BorderSide(color: _kBorder),
          getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
            final isLeft = s.barIndex == 0;
            final color = isLeft ? _kCopper : _kTeal;
            final seriesL = isLeft ? leftLabel : rightLabel;
            return LineTooltipItem(
              '$seriesL: ${s.y.toStringAsFixed(2)}\n${xLabels[s.x.toInt()] ?? ''}',
              GoogleFonts.spaceGrotesk(
                  color: color, fontWeight: FontWeight.w700, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    ));
  }

  // ── Bar chart (dropdown) ──────────────────────────────────────────────────
  // X axis: iterator (1, 2, 3…) with dropdown option label below.
  // Y axis: occurrence count.
  Widget _barChart(String label, List<ReadingModel> data) {
    // Count occurrences of each dropdown option
    final counts = <String, int>{};
    for (final r in data) {
      final v = r.inspectionValues[label]?.toString() ?? '';
      if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return _noData('No dropdown selections for "$label"');
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxY = entries.first.value.toDouble();

    return BarChart(BarChartData(
      borderData: _borderData,
      gridData: _gridData,
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY * 1.3,
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        // Y axis = occurrence count
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            getTitlesWidget: (v, _) {
              if (v != v.truncateToDouble()) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  v.toInt().toString(),
                  style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _kSubL),
                ),
              );
            },
          ),
        ),
        // X axis = iterator 1, 2, 3… + option label beneath
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, _) {
              final idx = v.toInt();
              if (idx < 0 || idx >= entries.length) {
                return const SizedBox.shrink();
              }
              final opt = entries[idx].key;
              final short = opt.length > 9 ? '${opt.substring(0, 8)}…' : opt;
              return Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '${idx + 1}\n$short',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _kSubL),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: entries.asMap().entries.map((e) {
        final idx = e.key;
        final count = e.value.value.toDouble();
        final color = _kMultiPalette[idx % _kMultiPalette.length];
        return BarChartGroupData(
          x: idx,
          barRods: [
            BarChartRodData(
              toY: count,
              color: color,
              width: 30,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
              backDrawRodData: BackgroundBarChartRodData(
                  show: true, toY: maxY * 1.3, color: color.withOpacity(0.07)),
            ),
          ],
          showingTooltipIndicators: [],
        );
      }).toList(),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => _kCard,
          tooltipBorderRadius: BorderRadius.circular(8),
          getTooltipItem: (group, _, rod, __) {
            final opt = entries[group.x].key;
            final cnt = entries[group.x].value;
            final total = counts.values.fold(0, (a, b) => a + b);
            final pct = (cnt / total * 100).toStringAsFixed(1);
            return BarTooltipItem(
              '$opt\n$cnt readings ($pct%)',
              GoogleFonts.spaceGrotesk(
                  color: _kMultiPalette[group.x % _kMultiPalette.length],
                  fontWeight: FontWeight.w700,
                  fontSize: 11),
            );
          },
        ),
      ),
    ));
  }

  // ── Legend ─────────────────────────────────────────────────────────────────
  Widget _buildLegend() {
    Widget content;
    if (_isAllTanks) {
      content = Wrap(
        spacing: 12,
        runSpacing: 6,
        children: widget.tanks.asMap().entries.map((e) {
          final color = _kMultiPalette[e.key % _kMultiPalette.length];
          return _LegendDot(color: color, label: e.value.tankName);
        }).toList(),
      );
    } else {
      final type = _selectedParam?['type'] as String? ?? 'number';
      final label = _selectedParam?['label'] as String? ?? '';

      if (type == 'dual_text') {
        final ll = _selectedParam?['left_label'] as String? ?? 'Left';
        final rl = _selectedParam?['right_label'] as String? ?? 'Right';
        content = Row(children: [
          _LegendLine(color: _kCopper, label: '← $ll'),
          const SizedBox(width: 16),
          _LegendLine(color: _kTeal, label: '→ $rl'),
        ]);
      } else if (type == 'dropdown') {
        final data = _filtered(_selectedTankId!);
        final counts = <String, int>{};
        for (final r in data) {
          final v = r.inspectionValues[label]?.toString() ?? '';
          if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
        }
        final total = counts.values.fold(0, (a, b) => a + b);
        final entries = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        content = Wrap(
          spacing: 10,
          runSpacing: 6,
          children: entries.asMap().entries.map((e) {
            final color = _kMultiPalette[e.key % _kMultiPalette.length];
            final pct = total > 0
                ? (e.value.value / total * 100).toStringAsFixed(1)
                : '0';
            return _LegendDot(
                color: color,
                label: '${e.value.key}  ${e.value.value}×  ($pct%)');
          }).toList(),
        );
      } else {
        content = _LegendLine(color: _kCopper, label: label);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: content,
    );
  }

  // ── Reading count footer ─────────────────────────────────────────────────
  Widget _buildReadingFooter() {
    int count = 0;
    if (_isAllTanks) {
      for (final t in widget.tanks) count += _filtered(t.id).length;
    } else if (_selectedTankId != null) {
      count = _filtered(_selectedTankId!).length;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Text(
        '$count reading${count == 1 ? '' : 's'} in range · '
        'tap "Export Chart as PNG" to save',
        style: GoogleFonts.dmSans(fontSize: 11, color: _kSubL),
      ),
    );
  }

  // ── Chart style helpers ───────────────────────────────────────────────────

  /// Left + bottom borders only; top + right hidden.
  FlBorderData get _borderData => FlBorderData(
        show: true,
        border: const Border(
          left: BorderSide(color: _kBorderH, width: 1),
          bottom: BorderSide(color: _kBorderH, width: 1),
          top: BorderSide(color: Colors.transparent),
          right: BorderSide(color: Colors.transparent),
        ),
      );

  FlGridData get _gridData => FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: _kBorder, strokeWidth: 1, dashArray: [4, 4]),
      );

  SideTitles get _leftTitles => SideTitles(
        showTitles: true,
        reservedSize: 50,
        getTitlesWidget: (v, _) => Text(
          v == v.truncateToDouble()
              ? v.toInt().toString()
              : v.toStringAsFixed(1),
          style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _kSubL),
        ),
      );

  /// Sparse bottom labels — at most 5 visible, each showing DD/MM/YYYY\nHH:mm.
  SideTitles _bottomTitlesSparse(
    int count,
    String Function(int) getLabel,
  ) {
    final step = (count / 5).ceil().clamp(1, count);

    return SideTitles(
      showTitles: true,
      reservedSize: 58, // enough for two-line timestamp
      interval: step.toDouble(),
      getTitlesWidget: (v, _) {
        final idx = v.toInt();
        if (idx < 1) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: 60,
            child: Text(
              getLabel(idx),
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 8.5,
                height: 1.2,
                color: _kSubL,
              ),
            ),
          ),
        );
      },
    );
  }

  /// ✅ FIX: tooltipRoundedRadius → tooltipBorderRadius in fl_chart 1.2.0
  LineTouchData _lineTouchData(String Function(LineBarSpot) fmt) =>
      LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _kCard,
          tooltipBorderRadius: BorderRadius.circular(8),
          tooltipBorder: const BorderSide(color: _kBorder),
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    fmt(s),
                    GoogleFonts.spaceGrotesk(
                        color: _kCopper,
                        fontWeight: FontWeight.w700,
                        fontSize: 11),
                  ))
              .toList(),
        ),
      );

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Widget _noData(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bar_chart_outlined, size: 36, color: _kSubL),
          const SizedBox(height: 8),
          Text(msg,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// QR SCAN PAGE
// ─────────────────────────────────────────────────────────────────────────────
