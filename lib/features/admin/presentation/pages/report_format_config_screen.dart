import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';
import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';
import 'package:lubrication_indicator/features/alerts/data/models/alert_model.dart';
import 'package:lubrication_indicator/features/dashboard/data/models/dashboard_stats_model.dart';
import 'package:lubrication_indicator/core/constants/app_constants.dart';

// Styling Palette (Obsidian/Copper)
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kBorder = Color(0xFF252830);
const _kCopper = Color(0xFFCB8C3E);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kInfo = Color(0xFF60A5FA);

class ParamItem {
  final String key;
  final String name;
  final String type;
  final List<String> options;
  final List<TankModel> tanks;
  final bool selected;
  final int order;

  ParamItem({
    required this.key,
    required this.name,
    required this.type,
    required this.options,
    required this.tanks,
    required this.selected,
    required this.order,
  });
}

class ReportFormatConfigScreen extends StatefulWidget {
  final bool isViolationMode;
  final String? folderIdOverride;

  const ReportFormatConfigScreen({
    super.key,
    this.isViolationMode = false,
    this.folderIdOverride,
  });

  @override
  State<ReportFormatConfigScreen> createState() => _ReportFormatConfigScreenState();
}

class _ReportFormatConfigScreenState extends State<ReportFormatConfigScreen> {
  final _treeRepo = TankTreeRepository();
  final _tankRepo = TankRepository();

  List<TankNode?> _pathStack = [null];
  TankNode? get _currentFolder => _pathStack.last;

  List<TankNode> _allNodes = [];
  List<TankModel> _allTanks = [];
  List<ReadingModel> _allReadings = [];
  List<AlertModel> _allAlerts = [];
  Map<String, dynamic> _configsByFolder = {}; // folderId -> config map
  Map<String, DashboardStatsModel> _statsByTank = {}; // tankId -> stats map
  bool _loading = true;

  final TextEditingController _stripTextCtrl = TextEditingController();
  final TextEditingController _pdfThresholdCtrl = TextEditingController();
  final TextEditingController _excelThresholdCtrl = TextEditingController();
  String _stripPosition = 'start';
  final Map<String, bool> _expandedParams = {};
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _stripTextCtrl.dispose();
    _pdfThresholdCtrl.dispose();
    _excelThresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      final nodes = await _treeRepo.fetchAll();
      final tanks = await _tankRepo.getAllTanks();
      final readings = await ReadingRepository().getAllReadings();
      
      final alertsSnap = await DatabaseModeService.ref('alerts').get();
      List<AlertModel> alerts = [];
      if (alertsSnap.exists && alertsSnap.value != null) {
        final raw = Map<dynamic, dynamic>.from(alertsSnap.value as Map);
        alerts = raw.entries.map((e) {
          final map = Map<dynamic, dynamic>.from(e.value as Map);
          return AlertModel.fromMap(e.key.toString(), map);
        }).toList();
      }

      final snap = await DatabaseModeService.ref('settings/report_format').get();
      
      Map<String, dynamic> configs = {};
      if (snap.exists && snap.value != null) {
        final rawMap = snap.value as Map;
        configs = rawMap.map((key, val) => MapEntry(key.toString(), Map<String, dynamic>.from(val as Map)));
      }

      final statsSnap = await DatabaseModeService.ref('dashboard_stats').get();
      Map<String, DashboardStatsModel> statsByTank = {};
      if (statsSnap.exists && statsSnap.value != null) {
        final raw = Map<dynamic, dynamic>.from(statsSnap.value as Map);
        statsByTank = raw.map((key, val) => MapEntry(
          key.toString(),
          DashboardStatsModel.fromMap(key.toString(), Map<dynamic, dynamic>.from(val as Map)),
        ));
      }

      setState(() {
        _allNodes = nodes;
        _allTanks = tanks;
        _allReadings = readings;
        _allAlerts = alerts;
        _configsByFolder = configs;
        _statsByTank = statsByTank;
        if (widget.folderIdOverride != null) {
          final overrideNode = nodes.cast<TankNode?>().firstWhere(
                (n) => n != null && n.id == widget.folderIdOverride,
                orElse: () => null,
              );
          if (overrideNode != null) {
            _pathStack = [null, overrideNode];
          }
        }
        _loading = false;
      });

      _initStripControls();
    } catch (e) {
      debugPrint('[ReportConfig] load error: $e');
      setState(() => _loading = false);
    }
  }

  void _initStripControls() {
    final folderKey = _currentFolder?.id ?? 'root';
    final config = _configsByFolder[folderKey] ?? {};
    
    _stripTextCtrl.text = config['strip_text']?.toString() ?? '';
    _pdfThresholdCtrl.text = (config['pdf_threshold']?.toString() ?? '6');
    _excelThresholdCtrl.text = (config['excel_threshold']?.toString() ?? '12');
    _stripPosition = config['strip_position']?.toString() ?? 'start';
  }

  List<TankModel> _getTanksInFolder(TankNode? folder) {
    final folderId = folder?.id; // null represents Root
    final childLeafNodes = _allNodes.where((n) {
      if (folderId == null) {
        return (n.parentId == null || n.parentId == 'root') && n.isLeaf;
      } else {
        return n.parentId == folderId && n.isLeaf;
      }
    });
    final tankIdSet = childLeafNodes.map((n) => n.tankId).whereType<String>().toSet();
    return _allTanks.where((t) => tankIdSet.contains(t.id)).toList();
  }

  // Helper: Generate parameter unique key
  String getParamUniqueKey(Map<String, dynamic> p) {
    final name = (p['label'] ?? p['name'] ?? '').toString().trim();
    final type = (p['type'] ?? 'text').toString().trim();
    final options = List<String>.from(p['options'] ?? []);
    options.sort();
    return '${name}_${type}_${options.join(",")}';
  }

  // Get sorted list of parameters for the current level
  List<ParamItem> _getParamsList() {
    final folderKey = _currentFolder?.id ?? 'root';
    final config = _configsByFolder[folderKey] ?? {};
    final selectedParams = widget.isViolationMode
        ? config['violation_params'] as Map?
        : config['selected_params'] as Map?;

    final tanks = _getTanksInFolder(_currentFolder);
    final Map<String, ParamItem> discovered = {};

    for (final tank in tanks) {
      for (final prop in tank.inspectionProperties) {
        final type = prop['type'] as String? ?? 'text';
        if (type == 'group') continue;
        
        final key = getParamUniqueKey(prop);
        final name = (prop['label'] ?? prop['name'] ?? '').toString();
        final options = List<String>.from(prop['options'] ?? []);

        if (discovered.containsKey(key)) {
          if (!discovered[key]!.tanks.any((t) => t.id == tank.id)) {
            discovered[key]!.tanks.add(tank);
          }
        } else {
          discovered[key] = ParamItem(
            key: key,
            name: name,
            type: type,
            options: options,
            tanks: [tank],
            selected: true,
            order: 0,
          );
        }
      }
    }

    final List<ParamItem> items = [];
    int maxDbOrder = 0;
    if (selectedParams != null) {
      selectedParams.forEach((k, v) {
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
      if (selectedParams != null && selectedParams.containsKey(key)) {
        final map = selectedParams[key] as Map?;
        selected = map?['selected'] ?? true;
        order = (map?['order'] as num?)?.toInt() ?? 0;
      }
      items.add(ParamItem(
        key: item.key,
        name: item.name,
        type: item.type,
        options: item.options,
        tanks: item.tanks,
        selected: selected,
        order: order,
      ));
    });

    final selectedConfigured = items.where((i) => i.selected && i.order > 0).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    
    final selectedUnconfigured = items.where((i) => i.selected && i.order == 0).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    
    final unselected = items.where((i) => !i.selected).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final List<ParamItem> finalResult = [];
    finalResult.addAll(selectedConfigured);
    
    int nextOrder = maxDbOrder + 1;
    for (final item in selectedUnconfigured) {
      finalResult.add(ParamItem(
        key: item.key,
        name: item.name,
        type: item.type,
        options: item.options,
        tanks: item.tanks,
        selected: true,
        order: nextOrder++,
      ));
    }
    
    finalResult.addAll(unselected);
    return finalResult;
  }

  // Toggling parameter selected status
  Future<void> _toggleParam(String paramKey, bool check) async {
    final folderKey = _currentFolder?.id ?? 'root';
    final paramPath = widget.isViolationMode ? 'violation_params' : 'selected_params';
    final ref = DatabaseModeService.ref('settings/report_format/$folderKey/$paramPath');
    
    final config = _configsByFolder[folderKey] ?? {};
    final selectedParams = Map<String, dynamic>.from(config[paramPath] ?? {});

    if (check) {
      int maxOrder = 0;
      selectedParams.forEach((k, v) {
        if (v is Map && v['selected'] == true) {
          final ord = (v['order'] as num?)?.toInt() ?? 0;
          if (ord > maxOrder) maxOrder = ord;
        }
      });
      selectedParams[paramKey] = {
        'selected': true,
        'order': maxOrder + 1,
      };
    } else {
      final currentMap = selectedParams[paramKey] as Map?;
      final int currentOrder = (currentMap?['order'] as num?)?.toInt() ?? 0;
      selectedParams[paramKey] = {
        'selected': false,
        'order': 0,
      };
      
      // Shift orders of other checked params
      selectedParams.forEach((k, v) {
        if (v is Map && v['selected'] == true) {
          final ord = (v['order'] as num?)?.toInt() ?? 0;
          if (ord > currentOrder) {
            selectedParams[k] = {
              'selected': true,
              'order': ord - 1,
            };
          }
        }
      });
    }

    setState(() {
      config[paramPath] = selectedParams;
      _configsByFolder[folderKey] = config;
    });

    await ref.set(selectedParams);
  }

  // Reorder index up/down swap
  Future<void> _reorderParam(String paramKey, bool up) async {
    final folderKey = _currentFolder?.id ?? 'root';
    final paramPath = widget.isViolationMode ? 'violation_params' : 'selected_params';
    final ref = DatabaseModeService.ref('settings/report_format/$folderKey/$paramPath');
    
    final config = _configsByFolder[folderKey] ?? {};
    final selectedParams = Map<String, dynamic>.from(config[paramPath] ?? {});
    
    final currentMap = selectedParams[paramKey] as Map?;
    if (currentMap == null || currentMap['selected'] != true) return;
    final int currentOrder = (currentMap['order'] as num?)?.toInt() ?? 0;
    
    if (up && currentOrder <= 1) return;

    final targetOrder = up ? currentOrder - 1 : currentOrder + 1;
    String? partnerKey;
    selectedParams.forEach((k, v) {
      if (v is Map && v['selected'] == true) {
        final ord = (v['order'] as num?)?.toInt() ?? 0;
        if (ord == targetOrder) {
          partnerKey = k;
        }
      }
    });

    if (partnerKey != null) {
      selectedParams[paramKey] = {
        'selected': true,
        'order': targetOrder,
      };
      selectedParams[partnerKey!] = {
        'selected': true,
        'order': currentOrder,
      };
      
      setState(() {
        config[paramPath] = selectedParams;
        _configsByFolder[folderKey] = config;
      });

      await ref.set(selectedParams);
    }
  }

  // Debounced DB sync for the Text Stripping input
  void _onStripTextChanged(String val) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final folderKey = _currentFolder?.id ?? 'root';
      final ref = DatabaseModeService.ref('settings/report_format/$folderKey/strip_text');
      
      final config = _configsByFolder[folderKey] ?? {};
      config['strip_text'] = val;
      _configsByFolder[folderKey] = config;

      await ref.set(val);
    });
  }

  // Radio button strip sync
  Future<void> _onStripPositionChanged(String? val) async {
    if (val == null) return;
    setState(() {
      _stripPosition = val;
    });

    final folderKey = _currentFolder?.id ?? 'root';
    final ref = DatabaseModeService.ref('settings/report_format/$folderKey/strip_position');
    
    final config = _configsByFolder[folderKey] ?? {};
    config['strip_position'] = val;
    _configsByFolder[folderKey] = config;

    await ref.set(val);
  }

  // Type Badges Styling Helper
  IconData _typeIconFor(String t) {
    switch (t) {
      case 'number':
        return Icons.pin_outlined;
      case 'text':
        return Icons.text_fields;
      case 'dropdown':
        return Icons.arrow_drop_down_circle_outlined;
      case 'dual_text':
        return Icons.view_column_outlined;
      case 'slider':
        return Icons.linear_scale;
      case 'multiline':
        return Icons.notes;
      default:
        return Icons.help_outline;
    }
  }

  Color _typeColorFor(String t) {
    switch (t) {
      case 'number':
        return _kCopper;
      case 'text':
        return _kSuccess;
      case 'dropdown':
        return const Color(0xFFBB86FC);
      case 'dual_text':
        return _kWarn;
      case 'slider':
        return const Color(0xFF03DAC6);
      case 'multiline':
        return const Color(0xFF7986CB);
      default:
        return _kSub;
    }
  }

  // Breadcrumbs Navigation Action
  void _jumpToBreadcrumb(int index) {
    if (index >= _pathStack.length - 1) return;
    setState(() {
      _pathStack.removeRange(index + 1, _pathStack.length);
    });
    _initStripControls();
  }

  void _drillIntoFolder(TankNode folder) {
    setState(() {
      _pathStack.add(folder);
    });
    _initStripControls();
  }

  // Interactive PDF/Excel Preview Modal Launcher
  void _openReportMockupPreview() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Report Mockup',
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, anim1, anim2) {
        return _ReportMockupPreviewModal(
          allNodes: _allNodes,
          allTanks: _allTanks,
          allReadings: _allReadings,
          allAlerts: _allAlerts,
          configsByFolder: _configsByFolder,
          statsByTank: _statsByTank,
          currentFolder: _currentFolder,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        foregroundColor: _kText,
        title: Text(
          widget.isViolationMode
              ? 'Violation Columns Configuration'
              : 'Report Format Settings',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kCopper))
          : Column(
              children: [
                // 1. Path/Breadcrumbs Navigation Bar
                Container(
                  color: _kSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_outlined, color: _kCopper, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(_pathStack.length, (idx) {
                              final isLast = idx == _pathStack.length - 1;
                              final node = _pathStack[idx];
                              final label = node?.name ?? 'Root';
                              return Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => widget.isViolationMode ? null : _jumpToBreadcrumb(idx),
                                    child: Text(
                                      label,
                                      style: GoogleFonts.inter(
                                        color: isLast ? _kText : (widget.isViolationMode ? _kSub : _kCopper),
                                        fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 6),
                                      child: Icon(Icons.chevron_right, color: _kSub, size: 14),
                                    ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _kBorder),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!widget.isViolationMode) ...[
                        // 2. Folder Navigation List (Drill deeper)
                        _buildFolderBrowsingList(),

                        const SizedBox(height: 16),
                        const Divider(color: _kBorder),
                        const SizedBox(height: 8),

                        // 3. Name/Text Stripping Configuration
                        _buildTextStrippingSection(),

                        const SizedBox(height: 16),
                        const Divider(color: _kBorder),
                        const SizedBox(height: 8),

                        // General Settings (Include Timestamp Toggle)
                        _buildGeneralSettingsSection(),

                        const SizedBox(height: 16),
                        const Divider(color: _kBorder),
                        const SizedBox(height: 8),
                      ] else ...[
                        Text(
                          'Configure the columns to be displayed when a constraint is violated in reports generated under this group.',
                          style: GoogleFonts.inter(color: _kSub, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: _kBorder),
                        const SizedBox(height: 16),
                      ],

                      // 4. Unique Parameters List for columns config
                      _buildParametersConfigSection(),
                    ],
                  ),
                ),

                // 5. PDF Thumbnail Preview Panel at Bottom
                if (!widget.isViolationMode)
                  _buildThumbnailPreviewPanel(),
              ],
            ),
    );
  }

  Widget _buildFolderBrowsingList() {
    final currentId = _currentFolder?.id;
    final childFolders = _allNodes.where((n) => n.parentId == currentId && n.isFolder).toList();

    if (childFolders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Navigate Deeper into Groups',
          style: GoogleFonts.inter(color: _kSub, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: childFolders.map((folder) {
            return OutlinedButton.icon(
              onPressed: () => _drillIntoFolder(folder),
              icon: const Icon(Icons.folder, size: 16, color: _kCopper),
              label: Text(
                folder.name,
                style: GoogleFonts.inter(fontSize: 13, color: _kText),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBorder),
                backgroundColor: _kSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTextStrippingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repetitive Word Removal from Tank Names',
          style: GoogleFonts.inter(color: _kCopper, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Clean redundant group tags (e.g. remove "PM6" prefix to display "m701" instead of "PM6 m701").',
          style: GoogleFonts.inter(color: _kSub, fontSize: 11),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _stripTextCtrl,
          onChanged: _onStripTextChanged,
          style: GoogleFonts.inter(color: _kText, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Text to remove (case-insensitive)',
            labelStyle: GoogleFonts.inter(color: _kSub, fontSize: 13),
            filled: true,
            fillColor: _kSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kCopper),
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              'Remove word at:',
              style: GoogleFonts.inter(color: _kText, fontSize: 13),
            ),
            const SizedBox(width: 16),
            Radio<String>(
              value: 'start',
              groupValue: _stripPosition,
              activeColor: _kCopper,
              onChanged: _onStripPositionChanged,
            ),
            Text('Start', style: GoogleFonts.inter(color: _kText, fontSize: 13)),
            const SizedBox(width: 16),
            Radio<String>(
              value: 'end',
              groupValue: _stripPosition,
              activeColor: _kCopper,
              onChanged: _onStripPositionChanged,
            ),
            Text('End', style: GoogleFonts.inter(color: _kText, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildGeneralSettingsSection() {
    final folderKey = _currentFolder?.id ?? 'root';
    final config = _configsByFolder[folderKey] ?? {};
    final includeTimestamp = config['include_timestamp'] == true;
    final pdfAbbreviate = config['pdf_abbreviate'] != false;
    final excelAbbreviate = config['excel_abbreviate'] != false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'General Report Settings',
          style: GoogleFonts.inter(color: _kCopper, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(
                  'Include Timestamp in Cells',
                  style: GoogleFonts.inter(color: _kText, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Show reading time (HH:MM AM/PM in green) below values in table cells.',
                  style: GoogleFonts.inter(color: _kSub, fontSize: 11),
                ),
                value: includeTimestamp,
                activeColor: _kCopper,
                activeTrackColor: _kCopper.withOpacity(0.3),
                inactiveThumbColor: _kSub,
                inactiveTrackColor: _kBg,
                onChanged: (val) async {
                  setState(() {
                    config['include_timestamp'] = val;
                    _configsByFolder[folderKey] = config;
                  });
                  final ref = DatabaseModeService.ref('settings/report_format/$folderKey/include_timestamp');
                  await ref.set(val);
                },
              ),
              const Divider(color: _kBorder, height: 1),
              SwitchListTile(
                title: Text(
                  'Use Abbreviations in PDF if Cols exceed limit',
                  style: GoogleFonts.inter(color: _kText, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Use abbreviations for PDF tables when parameter columns exceed 6.',
                  style: GoogleFonts.inter(color: _kSub, fontSize: 11),
                ),
                value: pdfAbbreviate,
                activeColor: _kCopper,
                activeTrackColor: _kCopper.withOpacity(0.3),
                inactiveThumbColor: _kSub,
                inactiveTrackColor: _kBg,
                onChanged: (val) async {
                  setState(() {
                    config['pdf_abbreviate'] = val;
                    _configsByFolder[folderKey] = config;
                  });
                  final ref = DatabaseModeService.ref('settings/report_format/$folderKey/pdf_abbreviate');
                  await ref.set(val);
                },
              ),
              // Compression Threshold Input for PDF
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextFormField(
                  controller: _pdfThresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'PDF Compression Threshold',
                    hintText: 'Enter a number > 0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) async {
                    final numVal = int.tryParse(val);
                    if (numVal == null || numVal <= 0) {
                      // ignore invalid input
                      return;
                    }
                    setState(() {
                      config['pdf_threshold'] = numVal;
                      _configsByFolder[folderKey] = config;
                    });
                    final ref = DatabaseModeService.ref('settings/report_format/$folderKey/pdf_threshold');
                    await ref.set(numVal);
                  },
                ),
              ),
              const Divider(color: _kBorder, height: 1),
              SwitchListTile(
                title: Text(
                  'Use Abbreviations in Excel if Cols exceed limit',
                  style: GoogleFonts.inter(color: _kText, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Use abbreviations for Excel sheets when parameter columns exceed 6.',
                  style: GoogleFonts.inter(color: _kSub, fontSize: 11),
                ),
                value: excelAbbreviate,
                activeColor: _kCopper,
                activeTrackColor: _kCopper.withOpacity(0.3),
                inactiveThumbColor: _kSub,
                inactiveTrackColor: _kBg,
                onChanged: (val) async {
                  setState(() {
                    config['excel_abbreviate'] = val;
                    _configsByFolder[folderKey] = config;
                  });
                  final ref = DatabaseModeService.ref('settings/report_format/$folderKey/excel_abbreviate');
                  await ref.set(val);
                },
              ),
              // Compression Threshold Input for Excel
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextFormField(
                  controller: _excelThresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Excel Compression Threshold',
                    hintText: 'Enter a number > 0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) async {
                    final numVal = int.tryParse(val);
                    if (numVal == null || numVal <= 0) {
                      return;
                    }
                    setState(() {
                      config['excel_threshold'] = numVal;
                      _configsByFolder[folderKey] = config;
                    });
                    final ref = DatabaseModeService.ref('settings/report_format/$folderKey/excel_threshold');
                    await ref.set(numVal);
                  },
                ),
              ),
            ],
          ),
        ),
        if (!widget.isViolationMode) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kCopper,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportFormatConfigScreen(
                      isViolationMode: true,
                      folderIdOverride: folderKey,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(
                'Configure "If Constraint is Violated"',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildParametersConfigSection() {
    final params = _getParamsList();

    if (params.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text(
            'No inspection parameters found in this folder/subfolders.',
            style: GoogleFonts.inter(color: _kSub, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Columns Configuration',
              style: GoogleFonts.inter(color: _kCopper, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              'Total: ${params.where((p) => p.selected).length}',
              style: GoogleFonts.inter(color: _kSub, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: params.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final param = params[idx];
            final color = _typeColorFor(param.type);
            final icon = _typeIconFor(param.type);
            final isExpanded = _expandedParams[param.key] ?? false;

            // Clean list of tank names
            final tankNames = param.tanks.map((t) => t.tankName).toList();
            final displayedTanks = isExpanded
                ? tankNames.join(', ')
                : (tankNames.take(3).join(', ') + (tankNames.length > 3 ? '...' : ''));

            return Container(
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: param.selected ? _kCopper.withOpacity(0.5) : _kBorder),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 100, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: param.selected,
                              activeColor: _kCopper,
                              checkColor: _kBg,
                              onChanged: (val) => _toggleParam(param.key, val ?? true),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    param.name,
                                    style: GoogleFonts.inter(
                                      color: _kText,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // Type badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 10, color: color),
                                        const SizedBox(width: 4),
                                        Text(
                                          param.type.toUpperCase(),
                                          style: GoogleFonts.inter(
                                            color: color,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Tanks usage list
                        Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Tanks: $displayedTanks',
                                  style: GoogleFonts.inter(color: _kSub, fontSize: 11),
                                ),
                              ),
                              if (tankNames.length > 3)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _expandedParams[param.key] = !isExpanded;
                                    });
                                  },
                                  child: Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: _kCopper,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top right: Reordering Badge + Up/Down arrows
                  if (param.selected)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _kCopper, width: 1.2),
                            ),
                            child: Text(
                              'Col #${param.order}',
                              style: GoogleFonts.inter(
                                color: _kCopper,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => _reorderParam(param.key, true),
                                child: const Icon(Icons.arrow_drop_up, color: _kSub, size: 20),
                              ),
                              GestureDetector(
                                onTap: () => _reorderParam(param.key, false),
                                child: const Icon(Icons.arrow_drop_down, color: _kSub, size: 20),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildThumbnailPreviewPanel() {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Thumbnail Page Design
            GestureDetector(
              onTap: _openReportMockupPreview,
              child: Container(
                width: 54,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    // Mock title block
                    Container(height: 4, color: Colors.grey[400]),
                    const SizedBox(height: 3),
                    // Mock table rows
                    Container(height: 5, color: Colors.orange[200]),
                    const SizedBox(height: 2),
                    Container(height: 5, color: Colors.cyan[100]),
                    const SizedBox(height: 2),
                    Container(height: 5, color: Colors.red[100]),
                    const SizedBox(height: 2),
                    Container(height: 5, color: Colors.yellow[100]),
                    const SizedBox(height: 4),
                    // Tiny arrows simulated
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.zoom_in, size: 10, color: Colors.blue[800]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview Sample Report Mockups',
                    style: GoogleFonts.inter(
                      color: _kText,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Inspect Daily/Weekly formats & severity markings.',
                    style: GoogleFonts.inter(color: _kSub, fontSize: 11),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _openReportMockupPreview,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kCopper,
                foregroundColor: _kBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: Text(
                'Preview',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Interactive full page report format preview modal ─────────────────────────
class _ReportMockupPreviewModal extends StatefulWidget {
  final List<TankNode> allNodes;
  final List<TankModel> allTanks;
  final List<ReadingModel> allReadings;
  final List<AlertModel> allAlerts;
  final Map<String, dynamic> configsByFolder;
  final Map<String, DashboardStatsModel> statsByTank;
  final TankNode? currentFolder;

  const _ReportMockupPreviewModal({
    super.key,
    required this.allNodes,
    required this.allTanks,
    required this.allReadings,
    required this.allAlerts,
    required this.configsByFolder,
    required this.statsByTank,
    required this.currentFolder,
  });

  @override
  State<_ReportMockupPreviewModal> createState() => _ReportMockupPreviewModalState();
}

class _ReportMockupPreviewModalState extends State<_ReportMockupPreviewModal> {
  int _activeTab = 0; // 0 = Daily, 1 = Weekly

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

  pw.Widget _pdfHeader(String title, String clientName, String subtitle) {
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

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 11.5,
          fontWeight: pw.FontWeight.bold,
        ),
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

  List<String> _getParamImages(Map<String, dynamic> values, String paramLabel, {String paramId = ''}) {
    final urls = <String>[];
    if (paramLabel.isEmpty && paramId.isEmpty) return urls;

    void addUrl(dynamic val) {
      final s = val?.toString().trim() ?? '';
      if (s.startsWith('http')) {
        urls.add(s);
      }
    }

    // 1. Check ID-based keys
    if (paramId.isNotEmpty) {
      addUrl(values['${paramId}__image_url']);
      for (final entry in values.entries) {
        final key = entry.key;
        if (key.startsWith('${paramId}__violation_') && key.endsWith('_image_url')) {
          addUrl(entry.value);
        }
      }
    }

    // 2. Check label-based keys
    if (paramLabel.isNotEmpty) {
      addUrl(values['${paramLabel}__image_url']);
      for (final entry in values.entries) {
        final key = entry.key;
        if (key.startsWith('manual_${paramLabel}_captured_image') || 
            (key.startsWith('${paramLabel}__violation_') && key.endsWith('_image_url'))) {
          addUrl(entry.value);
        }
      }
    }

    return urls;
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

  dynamic _getMockOrRealValue(
    TankModel tank,
    Map<String, dynamic> param,
    DateTime date,
    List<ReadingModel> folderReadings,
    bool isDaily,
  ) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    
    if (isDaily) {
      final stats = widget.statsByTank[tank.id];
      if (stats != null && stats.lastReading.containsKey(param['label'])) {
        return stats.lastReading[param['label']];
      }
    }

    final realReadings = folderReadings.where((r) {
      if (r.tankId != tank.id) return false;
      final dt = DateTime.parse(r.capturedAt).toLocal();
      return DateFormat('yyyy-MM-dd').format(dt) == dateStr;
    }).toList();

    if (realReadings.isNotEmpty) {
      realReadings.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      final val = realReadings.first.inspectionValues[param['label']];
      if (val != null) return val;
    }

    final historyReadings = widget.allReadings.where((r) => r.tankId == tank.id && r.inspectionValues.containsKey(param['label'])).toList();
    if (historyReadings.isNotEmpty) {
      historyReadings.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      final val = historyReadings.first.inspectionValues[param['label']];
      if (val != null) return val;
    }

    final prop = _getTankParamProp(tank, param['label'].toString());
    final type = param['type']?.toString().toLowerCase() ?? 'text';
    final options = List<String>.from(prop?['options'] ?? param['options'] ?? []);

    if (type == 'dropdown') {
      if (options.isNotEmpty) {
        final seed = (tank.id + param['label'].toString() + dateStr).hashCode;
        return options[seed.abs() % options.length];
      }
      return 'Normal';
    } else if (type == 'number' || type == 'slider') {
      final seed = (tank.id + param['label'].toString() + dateStr).hashCode;
      final random = Random(seed);
      final expectedMinVal = prop?['expected_min'] ?? param['expected_min'];
      final expectedMaxVal = prop?['expected_max'] ?? param['expected_max'];
      final expectedAvgVal = prop?['expected_avg'] ?? param['expected_avg'];

      double min = 40.0;
      double max = 90.0;

      if (expectedMinVal is num) min = expectedMinVal.toDouble();
      else if (expectedMinVal != null) min = double.tryParse(expectedMinVal.toString()) ?? 40.0;

      if (expectedMaxVal is num) max = expectedMaxVal.toDouble();
      else if (expectedMaxVal != null) max = double.tryParse(expectedMaxVal.toString()) ?? 90.0;

      if (expectedAvgVal is num) {
        min = expectedAvgVal.toDouble() - 10.0;
        max = expectedAvgVal.toDouble() + 10.0;
      }

      if (type == 'slider') {
        int imin = min.toInt();
        int imax = max.toInt();
        if (imax <= imin) imax = imin + 5;
        return imin + (random.nextInt(imax - imin + 1));
      }

      final val = min + (random.nextDouble() * (max - min));
      return double.parse(val.toStringAsFixed(1));
    } else if (type == 'dual_text') {
      final seed = (tank.id + param['label'].toString() + dateStr).hashCode;
      final random = Random(seed);
      return {
        'left': (50 + random.nextInt(30)).toString(),
        'right': (60 + random.nextInt(30)).toString(),
      };
    } else if (type == 'text' || type == 'multiline') {
      return 'Normal';
    }

    return 'Normal';
  }

  List<String> _getMockOrRealImages(
    TankModel tank,
    Map<String, dynamic> param,
    DateTime date,
    List<ReadingModel> folderReadings,
    bool isDaily,
  ) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final label = param['label']?.toString() ?? '';
    if (label.isEmpty) return [];

    final prop = _getTankParamProp(tank, label);
    final propId = prop?['id']?.toString() ?? '';

    if (isDaily) {
      final stats = widget.statsByTank[tank.id];
      if (stats != null) {
        final urls = _getParamImages(stats.lastReading, label, paramId: propId);
        if (urls.isNotEmpty) return urls;
      }
    }

    final realReadings = folderReadings.where((r) {
      if (r.tankId != tank.id) return false;
      final dt = DateTime.parse(r.capturedAt).toLocal();
      return DateFormat('yyyy-MM-dd').format(dt) == dateStr;
    }).toList();

    if (realReadings.isNotEmpty) {
      realReadings.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      final urls = _getParamImages(realReadings.first.inspectionValues, label, paramId: propId);
      if (urls.isNotEmpty) return urls;
    }

    final historyReadings = widget.allReadings.where((r) => r.tankId == tank.id).toList();
    if (historyReadings.isNotEmpty) {
      historyReadings.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      for (final r in historyReadings) {
        final urls = _getParamImages(r.inspectionValues, label, paramId: propId);
        if (urls.isNotEmpty) return urls;
      }
    }

    if (label.toLowerCase().contains('oil') || label.toLowerCase().contains('temp') || label.toLowerCase().contains('level')) {
      return ['https://example.com/mock_image.jpg'];
    }

    return [];
  }

  String _getMockOrRealTime(
    TankModel tank,
    DateTime date,
    List<ReadingModel> folderReadings,
    bool isDaily,
  ) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    
    if (isDaily) {
      final stats = widget.statsByTank[tank.id];
      if (stats != null && stats.lastCapturedAt != null) {
        return DateFormat('hh:mm a').format(DateTime.parse(stats.lastCapturedAt!).toLocal());
      }
    }

    final realReadings = folderReadings.where((r) {
      if (r.tankId != tank.id) return false;
      final dt = DateTime.parse(r.capturedAt).toLocal();
      return DateFormat('yyyy-MM-dd').format(dt) == dateStr;
    }).toList();

    if (realReadings.isNotEmpty) {
      realReadings.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      return DateFormat('hh:mm a').format(DateTime.parse(realReadings.first.capturedAt).toLocal());
    }

    final seed = (tank.id + dateStr).hashCode;
    final random = Random(seed);
    final hour = 8 + random.nextInt(9); 
    final minute = random.nextInt(60);
    final period = hour >= 12 ? 'PM' : 'AM';
    final dispHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${dispHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  String? _getTankActiveAlertSeverity(String tankId, List<AlertModel> openAlerts) {
    final tankAlerts = openAlerts.where((a) => a.tankId == tankId).toList();
    if (tankAlerts.isEmpty) return null;
    if (tankAlerts.any((a) => a.constraintSeverity.toLowerCase() == 'critical')) return 'critical';
    if (tankAlerts.any((a) => a.constraintSeverity.toLowerCase() == 'warning')) return 'warning';
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
        final key = '${label.trim()}_${type.trim()}_${options.join(",")}';

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

  Future<Uint8List> _buildPdfBytes(pdf.PdfPageFormat pageFormat) async {
    final generatedAt = DateFormat('dd MMMM yyyy - HH:mm').format(DateTime.now());
    
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final filtered = widget.allReadings.where((r) {
      final dt = DateTime.tryParse(r.capturedAt);
      return dt != null && !dt.isBefore(start) && !dt.isAfter(end);
    }).toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    final doc = pw.Document();

    final rootFolder = TankNode(
      id: 'root',
      type: 'folder',
      name: 'General',
      path: 'General',
      order: 0,
      createdAt: '',
    );

    final tankFolderMap = <String, TankNode>{};
    for (final n in widget.allNodes) {
      if (n.isLeaf && n.tankId != null) {
        final parent = widget.allNodes.cast<TankNode?>().firstWhere(
              (p) => p != null && p.isFolder && p.id == n.parentId,
              orElse: () => null,
            );
        if (parent != null) {
          tankFolderMap[n.tankId!] = parent;
        }
      }
    }

    final folderGroups = <String, List<TankModel>>{};
    for (final tank in widget.allTanks) {
      final folder = tankFolderMap[tank.id] ?? rootFolder;
      if (widget.currentFolder == null || folder.id == widget.currentFolder!.id) {
        folderGroups.putIfAbsent(folder.id, () => []).add(tank);
      }
    }

    final sortedFolderIds = folderGroups.keys.toList()
      ..sort((a, b) {
        final nameA = (a == 'root') ? 'General' : (widget.allNodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == a, orElse: () => null)?.name ?? 'General');
        final nameB = (b == 'root') ? 'General' : (widget.allNodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == b, orElse: () => null)?.name ?? 'General');
        return nameA.compareTo(nameB);
      });

    final inspectedTankIds = filtered.map((r) => r.tankId).toSet();
    final allTanksInPreview = widget.allTanks.where((t) {
      final folder = tankFolderMap[t.id] ?? rootFolder;
      return widget.currentFolder == null || folder.id == widget.currentFolder!.id;
    }).toList();

    final inspectedTanks = allTanksInPreview.where((t) => inspectedTankIds.contains(t.id)).toList();
    final pendingTanks = allTanksInPreview.where((t) => !inspectedTankIds.contains(t.id)).toList();
    final openAlerts = widget.allAlerts.where((a) => !a.resolved && a.status.toLowerCase() != 'completed').toList();

    final folderKey = widget.currentFolder?.id ?? 'root';
    final currentConfig = widget.configsByFolder[folderKey] ?? {};
    final includeTimestamp = currentConfig['include_timestamp'] == true;

    final resolvedClient = await ClientContextService.resolveClientName();
    final clientName = resolvedClient ?? (widget.allTanks.isEmpty
        ? 'All Tanks'
        : (widget.allTanks.first.location?.trim().isNotEmpty == true
            ? widget.allTanks.first.location!
            : 'Dashboard'));

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pdf.PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(12),
        ),
        header: (_) => _pdfHeader(
          'Live Inspection Report Preview',
          clientName,
          'Generated: $generatedAt',
        ),
        footer: _pdfFooter,
        build: (_) {
          final pendingTanksText = pendingTanks.isEmpty
              ? 'No assets pending readings.'
              : pendingTanks.map((t) => '${t.tankName} (${t.tankCode})').join(', ');

          pw.TableRow buildStatsLinkRow(String labelText, String countVal, String dest) {
            return pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: pw.Text(labelText, style: const pw.TextStyle(fontSize: 7.5)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Link(
                    destination: dest,
                    child: pw.Text(
                      countVal,
                      style: pw.TextStyle(
                        fontSize: 7.5,
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

          pw.TableRow buildStatsPlainRow(String labelText, String countVal) {
            return pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: pw.Text(labelText, style: const pw.TextStyle(fontSize: 7.5)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    countVal,
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }

          return [
            _pdfSectionTitle('Inspection Summary (Active Configuration)'),
            pw.SizedBox(height: 4),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('General Info', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.SizedBox(height: 2),
                      pw.Text('Preview Mode: ${_activeTab == 0 ? "Daily" : "Weekly"}', style: const pw.TextStyle(fontSize: 7.2)),
                      pw.Text('Date Range (Last 7 Days): ${DateFormat('dd MMM yyyy').format(start)} to ${DateFormat('dd MMM yyyy').format(end)}', style: const pw.TextStyle(fontSize: 7.2)),
                      pw.Text('Compliance Rate: ${allTanksInPreview.isEmpty ? "0.0%" : "${(inspectedTanks.length / allTanksInPreview.length * 100).toStringAsFixed(1)}%"}', style: const pw.TextStyle(fontSize: 7.2)),
                      pw.SizedBox(height: 6),
                      pw.Text('Reading & Alert Statistics', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.SizedBox(height: 3),
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
                              _pdfCell('Metric', header: true, fontSize: 7.2),
                              _pdfCell('Count', header: true, fontSize: 7.2),
                            ],
                          ),
                          buildStatsPlainRow('Total Configured Assets', allTanksInPreview.length.toString()),
                          buildStatsPlainRow('Assets with Readings', inspectedTanks.length.toString()),
                          buildStatsPlainRow('Assets Pending Readings', pendingTanks.length.toString()),
                          buildStatsLinkRow('Active Unresolved Alerts (Click to view)', openAlerts.where((a) => allTanksInPreview.any((t) => t.id == a.tankId)).length.toString(), 'unresolved_alerts'),
                        ],
                      ),
                      pw.SizedBox(height: 6),
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
                      pw.Text('Assets Pending Inspections (No Readings)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: pdf.PdfColors.red900)),
                      pw.SizedBox(height: 3),
                      if (pendingTanks.isEmpty)
                        pw.Text('No assets pending readings.', style: pw.TextStyle(fontSize: 7.2, color: pdf.PdfColors.green800, fontWeight: pw.FontWeight.bold))
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
                                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5, horizontal: 2),
                                    child: pw.Text(
                                      '• ${t.tankName} (${t.tankCode})',
                                      style: const pw.TextStyle(fontSize: 7.0, color: pdf.PdfColors.grey800),
                                    ),
                                  );
                                }
                                return pw.Container();
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

    if (_activeTab == 0) {
      for (final folderId in sortedFolderIds) {
        final folderTanks = folderGroups[folderId]!..sort((a, b) => a.tankName.compareTo(b.tankName));
        final folderNode = (folderId == 'root') ? rootFolder : (widget.allNodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == folderId, orElse: () => null) ?? rootFolder);

        final selectedParams = _getSelectedParamsForFolder(
          folderId: folderId,
          allNodes: widget.allNodes,
          allTanks: widget.allTanks,
          formatConfigs: widget.configsByFolder,
        );

        if (selectedParams.isEmpty) continue;

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
          final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
          final sectionTitle = '${folderNode.name} - ${DateFormat('dd/MM/yyyy').format(parsedDate)}';

          final rows = <pw.TableRow>[];
          final tableRows = <pw.Widget>[];
          tableRows.add(
            pw.Table(
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
              border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.3),
                for (int i = 1; i <= selectedParams.length; i++) i: const pw.FlexColumnWidth(1.0),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
                  children: [
                    _pdfCell('Asset Name', header: true, fontSize: 7.5, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                    ...selectedParams.map((p) => _pdfCell(p['label'].toString(), header: true, fontSize: 7.5, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2))),
                  ],
                ),
              ],
            ),
          );

          for (final tank in folderTanks) {
            final alertSev = _getTankActiveAlertSeverity(tank.id, openAlerts);
            final rowBg = _getRowColor(alertSev);
            final cleanName = _cleanAssetName(
              tankName: tank.tankName,
              folderId: folderId,
              formatConfigs: widget.configsByFolder,
            );

            final hasReadings = folderReadings.any((r) => r.tankId == tank.id) || widget.statsByTank[tank.id] != null;
            if (!hasReadings) {
              final pendingBg = _getRowColor(null, pending: true);
              tableRows.add(
                pw.Table(
                  defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
                  border: const pw.TableBorder(
                    left: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                    right: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                    bottom: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.3),
                    1: pw.FlexColumnWidth(selectedParams.length * 1.0),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: pendingBg),
                      children: [
                        _pdfCell('$cleanName\n-', fill: pendingBg, fontSize: 7.0, fontWeight: pw.FontWeight.bold, textColor: pdf.PdfColors.black, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                        _pdfCell('------- Readings not taken ------', fill: pendingBg, fontSize: 7.0, fontWeight: pw.FontWeight.bold, alignment: pw.Alignment.center, textColor: pdf.PdfColors.black, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                      ],
                    ),
                  ],
                ),
              );
            } else {
              final List<pw.Widget> rowCells = [];
              rowCells.add(_pdfCell(cleanName, fill: rowBg, fontSize: 7.0, fontWeight: pw.FontWeight.bold, textColor: rowBg != null ? pdf.PdfColors.black : null, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)));

              for (final p in selectedParams) {
                final rawVal = _getMockOrRealValue(tank, p, parsedDate, folderReadings, true);
                final timeStr = _getMockOrRealTime(tank, parsedDate, folderReadings, true);
                final valStr = _formatValueWithArrow(rawVal, _getTankParamProp(tank, p['label'].toString()));

                final paramImages = _getMockOrRealImages(tank, p, parsedDate, folderReadings, true);

                final cellContent = pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(valStr, style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.normal, color: rowBg != null ? pdf.PdfColors.black : null)),
                    if (includeTimestamp && valStr != '-')
                      pw.Text(
                        timeStr,
                        style: pw.TextStyle(
                          fontSize: 5.5,
                          color: pdf.PdfColor.fromInt(0xFF1B5E20),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (paramImages.isNotEmpty) ...[
                      pw.SizedBox(height: 1.5),
                      ...paramImages.asMap().entries.map((e) {
                        final idx = e.key + 1;
                        final url = e.value;
                        return pw.UrlLink(
                          destination: url,
                          child: pw.Text(
                            paramImages.length == 1 ? '[Photo]' : '[Photo $idx]',
                            style: pw.TextStyle(
                              fontSize: 5.2,
                              color: pdf.PdfColors.blue900,
                              decoration: pw.TextDecoration.underline,
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                );
                rowCells.add(_pdfCellWidget(cellContent, fill: rowBg, alignment: pw.Alignment.center, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)));
              }

              tableRows.add(
                pw.Table(
                  defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
                  border: const pw.TableBorder(
                    left: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                    right: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                    bottom: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                    verticalInside: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.3),
                    for (int i = 1; i <= selectedParams.length; i++) i: const pw.FlexColumnWidth(1.0),
                  },
                  children: [
                    pw.TableRow(
                      decoration: rowBg != null ? pw.BoxDecoration(color: rowBg) : null,
                      children: rowCells,
                    ),
                  ],
                ),
              );
            }
          }

          detailedWidgets.add(
            pw.Inseparable(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 8),
                  pw.Text(sectionTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: pdf.PdfColors.blue900)),
                  pw.SizedBox(height: 3),
                  pw.Column(children: tableRows),
                ],
              ),
            ),
          );
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

      final Set<String> activeDateStrings = {};
      for (final r in filtered) {
        if (allTanksInPreview.any((t) => t.id == r.tankId)) {
          final dt = DateTime.parse(r.capturedAt).toLocal();
          activeDateStrings.add(DateFormat('yyyy-MM-dd').format(dt));
        }
      }
      List<DateTime> days = activeDateStrings.map((s) => DateTime.parse(s)).toList()
        ..sort((a, b) => a.compareTo(b));

      if (days.isEmpty) {
        days = [
          now.subtract(const Duration(days: 2)),
          now.subtract(const Duration(days: 1)),
          now,
        ];
      }

      for (final folderId in sortedFolderIds) {
        final folderTanks = folderGroups[folderId]!..sort((a, b) => a.tankName.compareTo(b.tankName));
        final folderNode = (folderId == 'root') ? rootFolder : (widget.allNodes.cast<TankNode?>().firstWhere((n) => n != null && n.id == folderId, orElse: () => null) ?? rootFolder);

        final selectedParams = _getSelectedParamsForFolder(
          folderId: folderId,
          allNodes: widget.allNodes,
          allTanks: widget.allTanks,
          formatConfigs: widget.configsByFolder,
        );
final startLabel = DateFormat('dd/MM/yy').format(days.first);
        final endLabel = DateFormat('dd/MM/yy').format(days.last);
        final sectionTitle = '${folderNode.name} - $startLabel to $endLabel';

        final tableRows = <pw.Widget>[];

        tableRows.add(
          pw.Table(
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
            border: pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.4),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              for (int i = 1; i <= selectedParams.length; i++) i: pw.FlexColumnWidth(days.length * 0.7),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey300),
                children: [
                  _pdfCell('', header: true, fontSize: 7.0, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                  ...selectedParams.map((p) {
                    return _pdfCell(
                      p['label'].toString(),
                      header: true,
                      fontSize: 7.0,
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    );
                  }),
                ],
              ),
            ],
          ),
        );

        tableRows.add(
          pw.Table(
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
            border: const pw.TableBorder(
              left: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
              right: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
              bottom: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
              verticalInside: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              for (int i = 1; i <= selectedParams.length; i++) i: pw.FlexColumnWidth(days.length * 0.7),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey200),
                children: [
                  _pdfCell('Asset Name', header: true, fontSize: 7.0, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                  ...selectedParams.map((p) {
                    return pw.Table(
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
                              fontSize: 6.0,
                              alignment: pw.Alignment.center,
                              textColor: pdf.PdfColors.black,
                              padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            );
                          }),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        );

        final folderTankIds = folderTanks.map((t) => t.id).toSet();
        final folderReadings = filtered.where((r) => folderTankIds.contains(r.tankId)).toList();

        for (final tank in folderTanks) {
          final alertSev = _getTankActiveAlertSeverity(tank.id, openAlerts);
          final cleanName = _cleanAssetName(
            tankName: tank.tankName,
            folderId: folderId,
            formatConfigs: widget.configsByFolder,
          );

          final hasAnyReadings = folderReadings.any((r) => r.tankId == tank.id);
          final alertBg = hasAnyReadings ? _getRowColor(alertSev) : _getRowColor(null, pending: true);
          final List<pw.Widget> parentCells = [];

          if (!hasAnyReadings) {
            tableRows.add(
              pw.Table(
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
                border: const pw.TableBorder(
                  left: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                  right: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                  bottom: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  1: pw.FlexColumnWidth(selectedParams.length * days.length * 0.7),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: alertBg),
                    children: [
                      _pdfCell(cleanName, fill: alertBg, fontSize: 7.0, fontWeight: pw.FontWeight.bold, textColor: pdf.PdfColors.black, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                      _pdfCell('------- Readings not taken ------', fill: alertBg, fontSize: 7.0, fontWeight: pw.FontWeight.bold, alignment: pw.Alignment.center, textColor: pdf.PdfColors.black, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)),
                    ],
                  ),
                ],
              ),
            );
          } else {
            parentCells.add(_pdfCell(cleanName, fill: alertBg, fontSize: 7.0, fontWeight: pw.FontWeight.bold, textColor: alertBg != null ? pdf.PdfColors.black : null, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2)));

            for (final p in selectedParams) {
              final prop = _getTankParamProp(tank, p['label'].toString());

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

                        final rawVal = _getMockOrRealValue(tank, p, day, folderReadings, false);
                        final timeStr = _getMockOrRealTime(tank, day, folderReadings, false);
                        final valStr = _formatValueWithArrow(rawVal, prop);

                        final paramImages = _getMockOrRealImages(tank, p, day, folderReadings, false);

                        final cellContent = pw.Column(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(valStr, style: pw.TextStyle(fontSize: 6.0, fontWeight: pw.FontWeight.normal, color: colBg != null ? pdf.PdfColors.black : null)),
                            if (includeTimestamp && valStr != '-')
                              pw.Text(
                                timeStr,
                                style: pw.TextStyle(
                                  fontSize: 4.8,
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
                                    paramImages.length == 1 ? '[Photo]' : '[Photo $idx]',
                                    style: pw.TextStyle(
                                      fontSize: 4.6,
                                      color: pdf.PdfColors.blue900,
                                      decoration: pw.TextDecoration.underline,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        );

                        return _pdfCellWidget(cellContent, fill: colBg, alignment: pw.Alignment.center, padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2));
                      }),
                    ),
                  ],
                ),
              );
            }

            tableRows.add(
              pw.Table(
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
                border: const pw.TableBorder(
                  left: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                  right: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                  bottom: pw.BorderSide(color: pdf.PdfColors.grey400, width: 0.4),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  for (int i = 1; i <= selectedParams.length; i++) i: pw.FlexColumnWidth(days.length * 0.7),
                },
                children: [
                  pw.TableRow(
                    decoration: alertBg != null ? pw.BoxDecoration(color: alertBg) : null,
                    children: parentCells,
                  ),
                ],
              ),
            );
          }
        }

        detailedWidgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 8),
                pw.Text(sectionTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: pdf.PdfColors.blue900)),
                pw.SizedBox(height: 3),
                pw.Column(children: tableRows),
              ],
            ),
          ),
        );
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pdf.PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(12),
        ),
        header: (_) => _pdfHeader(
          'Live Inspection Report Preview',
          clientName,
          'Asset Inspection Detailed List',
        ),
        footer: _pdfFooter,
        build: (_) => detailedWidgets,
      ),
    );

    // Simulated alerts page
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: pdf.PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(12),
        ),
        header: (_) => _pdfHeader(
          'Live Inspection Report Preview',
          clientName,
          'Active Unresolved Alerts',
        ),
        footer: _pdfFooter,
        build: (_) => [
          pw.Anchor(
            name: 'unresolved_alerts',
            child: _pdfSectionTitle('SAMPLE ACTIVE UNRESOLVED ALERTS'),
          ),
          pw.SizedBox(height: 6),
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
            children: [
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
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: pdf.PdfColor.fromInt(0xFFE57373)),
                children: [
                  _pdfCell(DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now().subtract(const Duration(hours: 2))), fill: pdf.PdfColor.fromInt(0xFFE57373), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Mock Lube Tank (PM6-LT01)', fill: pdf.PdfColor.fromInt(0xFFE57373), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('CRITICAL', fill: pdf.PdfColor.fromInt(0xFFE57373), fontWeight: pw.FontWeight.bold, fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Oil Temperature', fill: pdf.PdfColor.fromInt(0xFFE57373), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('85.4 C (^)', fill: pdf.PdfColor.fromInt(0xFFE57373), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Temperature exceeds critical threshold limit of 80 C.', fill: pdf.PdfColor.fromInt(0xFFE57373), fontSize: 7.0, textColor: pdf.PdfColors.black),
                ],
              ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: pdf.PdfColor.fromInt(0xFFFFD54F)),
                children: [
                  _pdfCell(DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now().subtract(const Duration(hours: 5))), fill: pdf.PdfColor.fromInt(0xFFFFD54F), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Mock Gearbox (PM6-GB02)', fill: pdf.PdfColor.fromInt(0xFFFFD54F), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('WARNING', fill: pdf.PdfColor.fromInt(0xFFFFD54F), fontWeight: pw.FontWeight.bold, fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Oil Level', fill: pdf.PdfColor.fromInt(0xFFFFD54F), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Low (v)', fill: pdf.PdfColor.fromInt(0xFFFFD54F), fontSize: 7.2, textColor: pdf.PdfColors.black),
                  _pdfCell('Oil level is near the minimum warning threshold.', fill: pdf.PdfColor.fromInt(0xFFFFD54F), fontSize: 7.0, textColor: pdf.PdfColors.black),
                ],
              ),
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
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Container(
        color: _kBg,
        child: Column(
          children: [
            Container(
              color: _kSurface,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Live Report Customization Preview',
                    style: GoogleFonts.inter(
                      color: _kText,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: _kText),
                  ),
                ],
              ),
            ),
            Container(
              color: _kSurface,
              padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 0 ? _kCopper.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _activeTab == 0 ? _kCopper : _kBorder),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Daily Format',
                          style: GoogleFonts.inter(
                            color: _activeTab == 0 ? _kCopper : _kText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _activeTab == 1 ? _kCopper.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _activeTab == 1 ? _kCopper : _kBorder),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Weekly Format',
                          style: GoogleFonts.inter(
                            color: _activeTab == 1 ? _kCopper : _kText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: PdfPreview(
                      build: (format) => _buildPdfBytes(format),
                      allowPrinting: true,
                      allowSharing: true,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      loadingWidget: const Center(child: CircularProgressIndicator(color: _kCopper)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

