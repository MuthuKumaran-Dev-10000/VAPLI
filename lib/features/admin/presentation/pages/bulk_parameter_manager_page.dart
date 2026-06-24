// lib/features/admin/presentation/pages/bulk_parameter_manager_page.dart
// ══════════════════════════════════════════════════════════════════════════════
// CENTRALIZED BULK EDIT FOR FOLDER-LEVEL PARAMETERS
// ══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/core/services/audit_log_service.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/utils/session_manager.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';
import 'package:lubrication_indicator/features/tanks/presentation/pages/property_builder_page.dart';

const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kAccent = Color(0xFF1ABCBD);
const _kBorder = Color(0xFF252830);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);

class BulkParameterManagerPage extends StatefulWidget {
  final TankNode folderNode;
  final Future<void> Function(String operation, Map<String, dynamic> details)? onAudit;

  const BulkParameterManagerPage({
    required this.folderNode,
    this.onAudit,
    super.key,
  });

  @override
  State<BulkParameterManagerPage> createState() => _BulkParameterManagerPageState();
}

class _BulkParameterManagerPageState extends State<BulkParameterManagerPage> {
  final _treeRepo = TankTreeRepository();
  final _tankRepo = TankRepository();

  bool _loading = true;
  String _searchQuery = '';
  List<TankModel> _allFolderTanks = [];
  List<_ParameterGroup> _parameterGroups = [];

  // Batch execution state
  bool _executing = false;
  int _updatedCount = 0;
  int _skippedCount = 0;
  int _errorCount = 0;
  String? _executionStatus;

  @override
  void initState() {
    super.initState();
    _loadTanksAndScan();
  }

  Future<void> _loadTanksAndScan() async {
    setState(() => _loading = true);
    try {
      // 1. Fetch subtree recursively to find all leaf nodes with tank_id
      final subtree = await _treeRepo.fetchSubtree(widget.folderNode.id);
      final leafTankIds = subtree
          .where((n) => n.isLeaf && n.tankId != null)
          .map((n) => n.tankId!)
          .toSet();

      if (leafTankIds.isEmpty) {
        setState(() {
          _allFolderTanks = [];
          _parameterGroups = [];
          _loading = false;
        });
        return;
      }

      // 2. Fetch all tanks at once and filter
      final allTanks = await _tankRepo.getAllTanks();
      final folderTanks = allTanks.where((t) => leafTankIds.contains(t.id)).toList();

      // 3. Scan properties and group by normalized name + type
      final groupMap = <String, _ParameterGroup>{};
      for (final tank in folderTanks) {
        for (final param in tank.inspectionProperties) {
          final label = param['label']?.toString() ?? '';
          final type = param['type']?.toString() ?? 'text';
          final normalized = label.trim().toLowerCase();
          if (normalized.isEmpty || type == 'group') continue;

          final key = '${normalized}_$type';
          groupMap.putIfAbsent(key, () => _ParameterGroup(
            normalizedName: normalized,
            type: type,
            sampleLabel: label,
            occurrences: [],
          ));

          groupMap[key]!.occurrences.add(_ParameterOccurrence(
            tank: tank,
            parameter: param,
          ));
        }
      }

      setState(() {
        _allFolderTanks = folderTanks;
        _parameterGroups = groupMap.values.toList()
          ..sort((a, b) => b.occurrences.length.compareTo(a.occurrences.length));
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showSnack('Scan failed: $e', _kDanger);
    }
  }

  void _showSnack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _openBulkEditFlow(_ParameterGroup group) {
    // We preload with the first occurrence as baseline
    final baseline = group.occurrences.first.parameter;
    // Preload properties inside session param store so autofills works
    final childScope = 'bulk_edit_${DateTime.now().millisecondsSinceEpoch}';

    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyBuilderPage(
          scopeId: childScope,
          existing: baseline,
          onSave: (updatedParam) {
            // Delay to prevent overlay dialog rendering issues when PropertyBuilder pops itself
            Future.delayed(const Duration(milliseconds: 150), () {
              if (mounted) {
                _showTargetSelectionDialog(group, updatedParam);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _showTargetSelectionDialog(_ParameterGroup group, Map<String, dynamic> updatedParam) async {
    final targets = List<_ParameterOccurrence>.from(group.occurrences);
    final selectedOccurrences = List<_ParameterOccurrence>.from(targets);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final allSelected = selectedOccurrences.length == targets.length;

          return AlertDialog(
            backgroundColor: _kCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Select Target Tanks',
                style: GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Apply updates to "${group.sampleLabel}" across selected tanks:',
                    style: const TextStyle(fontSize: 13, color: _kSub),
                  ),
                  const SizedBox(height: 12),
                  // Select All row
                  CheckboxListTile(
                    title: Text(allSelected ? 'Deselect All' : 'Select All',
                        style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w600)),
                    value: allSelected,
                    activeColor: _kAccent,
                    onChanged: (val) {
                      setDlg(() {
                        if (val == true) {
                          selectedOccurrences
                            ..clear()
                            ..addAll(targets);
                        } else {
                          selectedOccurrences.clear();
                        }
                      });
                    },
                  ),
                  const Divider(color: _kBorder),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: targets.map((occ) {
                          final selected = selectedOccurrences.contains(occ);
                          return CheckboxListTile(
                            title: Text(occ.tank.tankName,
                                style: const TextStyle(color: _kText, fontSize: 13)),
                            subtitle: Text('Location: ${occ.tank.location ?? "N/A"}',
                                style: const TextStyle(fontSize: 11, color: _kSub)),
                            value: selected,
                            activeColor: _kAccent,
                            onChanged: (val) {
                              setDlg(() {
                                if (val == true) {
                                  selectedOccurrences.add(occ);
                                } else {
                                  selectedOccurrences.remove(occ);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel', style: TextStyle(color: _kSub)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: selectedOccurrences.isEmpty
                    ? null
                    : () {
                        Navigator.pop(dlgCtx);
                        _applyBulkChanges(group, selectedOccurrences, updatedParam);
                      },
                child: const Text('Apply Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _applyBulkChanges(
    _ParameterGroup group,
    List<_ParameterOccurrence> selectedOccurrences,
    Map<String, dynamic> updatedParam,
  ) async {
    if (!mounted) return;
    setState(() {
      _executing = true;
      _updatedCount = 0;
      _skippedCount = 0;
      _errorCount = 0;
      _executionStatus = 'Starting batch update…';
    });

    final updates = <String, dynamic>{};
    final user = await SessionManager.getCurrentUser();
    final nowStr = DateTime.now().toIso8601String();

    int successLocal = 0;
    int errorLocal = 0;

    debugPrint('Bulk update: applying changes to parameter: ${updatedParam['label']} (${group.type})');
    debugPrint('Bulk update: selected occurrences count: ${selectedOccurrences.length}');

    for (final occ in selectedOccurrences) {
      try {
        final tank = occ.tank;
        final propsList = List<Map<String, dynamic>>.from(tank.inspectionProperties);

        // Find the index of the matching parameter map in this tank
        final idx = propsList.indexWhere((p) {
          final label = p['label']?.toString() ?? '';
          final type = p['type']?.toString() ?? 'text';
          final normalized = label.trim().toLowerCase();
          return p['id'] == occ.parameter['id'] ||
              (normalized == group.normalizedName && type == group.type);
        });

        if (idx == -1) {
          debugPrint('Bulk update: parameter not found in tank ${tank.tankName} (${tank.id})');
          errorLocal++;
          continue;
        }

        // Merge properties while keeping the original stable ID
        final origId = propsList[idx]['id'] ?? 'p_${DateTime.now().millisecondsSinceEpoch}';
        final newParam = Map<String, dynamic>.from(updatedParam)..['id'] = origId;

        propsList[idx] = newParam;

        final pathProps = DatabaseModeService.path('tanks/${tank.id}/inspection_properties');
        final pathUpdated = DatabaseModeService.path('tanks/${tank.id}/updated_at');

        updates[pathProps] = propsList;
        updates[pathUpdated] = nowStr;

        debugPrint('Bulk update: queued tank ${tank.tankName} (${tank.id}) properties at path: $pathProps');

        successLocal++;

        // Audit log for this tank
        await AuditLogService.record(
          operation: 'bulk_update_tank_parameter',
          entityType: 'inspection_parameter',
          entityId: origId.toString(),
          entityName: newParam['label']?.toString(),
          actorId: user?.id,
          actorUsername: user?.username,
          actorName: user?.fullName,
          actorRole: user?.role,
          tab: 'tanks',
          summary: 'Bulk updated parameter "${newParam['label']}" in tank "${tank.tankName}"',
          details: {
            'tank_id': tank.id,
            'tank_name': tank.tankName,
            'parameter_id': origId,
            'parameter_label': newParam['label'],
          },
        );
      } catch (e) {
        debugPrint('Bulk update: error processing tank ${occ.tank.tankName}: $e');
        errorLocal++;
      }
    }

    if (updates.isNotEmpty) {
      try {
        if (mounted) {
          setState(() => _executionStatus = 'Writing changes to database…');
        }
        debugPrint('Bulk update: executing Firebase batch update with ${updates.length} keys');
        await FirebaseDatabase.instance.ref().update(updates);
        debugPrint('Bulk update: Firebase batch write succeeded');
      } catch (e) {
        debugPrint('Bulk update: Firebase batch write failed: $e');
        errorLocal = selectedOccurrences.length;
        successLocal = 0;
        _showSnack('Firebase batch write failed: $e', _kDanger);
      }
    }

    // Complete audit summary log for the folder node
    await widget.onAudit?.call('bulk_parameter_edit', {
      'folder_id': widget.folderNode.id,
      'folder_name': widget.folderNode.name,
      'parameter_name': updatedParam['label'],
      'tanks_updated': successLocal,
      'errors_encountered': errorLocal,
    });

    if (!mounted) return;
    setState(() {
      _updatedCount = successLocal;
      _errorCount = errorLocal;
      _skippedCount = group.occurrences.length - selectedOccurrences.length;
      _executionStatus = 'Finished!';
    });

    // Short delay and reload data
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _executing = false;
          _executionStatus = null;
        });
        _loadTanksAndScan();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = _parameterGroups.where((g) {
      if (_searchQuery.isEmpty) return true;
      return g.sampleLabel.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(
          'Bulk Parameter Editor',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: _kText),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: _kSub),
            onPressed: _executing ? null : _loadTanksAndScan,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Folder Header Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: _kSurface,
                  border: Border(bottom: BorderSide(color: _kBorder)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, color: _kWarn, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.folderNode.name,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: _kText)),
                          const SizedBox(height: 2),
                          Text('Managing parameters inside folder and subfolders recursively',
                              style: GoogleFonts.inter(fontSize: 11, color: _kSub)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_allFolderTanks.length} Tanks Found',
                        style: const TextStyle(fontSize: 10, color: _kAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  style: const TextStyle(color: _kText, fontSize: 13),
                  cursorColor: _kAccent,
                  decoration: InputDecoration(
                    hintText: 'Search shared parameters…',
                    hintStyle: const TextStyle(color: _kSub, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18, color: _kSub),
                    filled: true,
                    fillColor: _kSurface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kAccent, width: 1.5),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              // Parameter Groups List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _kAccent))
                    : filteredGroups.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filteredGroups.length,
                            itemBuilder: (_, i) => _buildGroupCard(filteredGroups[i]),
                          ),
              ),
            ],
          ),

          // Execution overlay modal when applying batch changes
          if (_executing) _buildExecutionOverlay(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.settings_suggest, size: 36, color: _kSub),
          const SizedBox(height: 10),
          Text(
            _searchQuery.isEmpty ? 'No parameters found' : 'No matching parameters',
            style: GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isEmpty ? 'Make sure leaf tanks contain configuration.' : 'Try another query.',
            style: const TextStyle(fontSize: 11, color: _kSub),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(_ParameterGroup g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: InkWell(
        onTap: () => _openBulkEditFlow(g),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon based on type
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _typeColor(g.type).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_typeIcon(g.type), size: 18, color: _typeColor(g.type)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.sampleLabel,
                        style: GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _typeBadge(g.type),
                        const SizedBox(width: 8),
                        Text(
                          'Used in ${g.occurrences.length} Tank${g.occurrences.length == 1 ? "" : "s"}',
                          style: const TextStyle(fontSize: 11, color: _kSub),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: _kSub),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExecutionOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(color: _kAccent, strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                'Applying Bulk Changes',
                style: GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              if (_executionStatus != null)
                Text(_executionStatus!, style: const TextStyle(fontSize: 12, color: _kSub)),
              const SizedBox(height: 18),
              const Divider(color: _kBorder),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statCol('UPDATED', _updatedCount, _kSuccess),
                  _statCol('SKIPPED', _skippedCount, _kSub),
                  _statCol('ERRORS', _errorCount, _kDanger),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCol(String label, int value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: _kSub, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'number':
        return Icons.pin_outlined;
      case 'text':
        return Icons.text_fields_outlined;
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

  Color _typeColor(String t) {
    return const {
          'number': _kAccent,
          'text': _kSuccess,
          'dropdown': Color(0xFFBB86FC),
          'dual_text': _kWarn,
          'slider': Color(0xFF03DAC6),
          'multiline': Color(0xFF7986CB),
        }[t] ??
        _kSub;
  }

  Widget _typeBadge(String type) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _typeColor(type).withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          type.toUpperCase(),
          style: TextStyle(color: _typeColor(type), fontSize: 9, fontWeight: FontWeight.bold),
        ),
      );
}

class _ParameterGroup {
  final String normalizedName;
  final String type;
  final String sampleLabel;
  final List<_ParameterOccurrence> occurrences;

  _ParameterGroup({
    required this.normalizedName,
    required this.type,
    required this.sampleLabel,
    required this.occurrences,
  });
}

class _ParameterOccurrence {
  final TankModel tank;
  final Map<String, dynamic> parameter;

  _ParameterOccurrence({
    required this.tank,
    required this.parameter,
  });
}
