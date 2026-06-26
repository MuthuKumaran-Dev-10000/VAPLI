import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:lubrication_indicator/core/utils/file_folder_opener.dart';
import 'package:flutter/services.dart';
import 'package:lubrication_indicator/core/services/report_storage_service.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/audit_log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/core/services/client_repository.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';
import 'package:lubrication_indicator/features/auth/data/repositories/auth_repository.dart';
import 'package:lubrication_indicator/features/admin/presentation/pages/admin_settings_page.dart';
import 'package:lubrication_indicator/features/admin/presentation/pages/admin_audit_logs_page.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';

import 'package:excel/excel.dart' as xl;
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/presentation/pages/tank_browser_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardTabSpec {
  final String key;
  final String label;

  const _DashboardTabSpec({
    required this.key,
    required this.label,
  });
}

class AdminDashboard extends StatefulWidget {
  final String adminName;
  final UserModel currentUser;
  final ClientModel? activeClient;

  const AdminDashboard({
    super.key,
    required this.adminName,
    required this.currentUser,
    this.activeClient,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabRefreshTick = 0;
  String? _selectedClientId;
  final Set<String> _userRoleFilters = {'super admin', 'admin', 'user'};

  List<Map> _users = [];
  List<ClientModel> _clients = [];
  StreamSubscription<DatabaseEvent>? _usersSub;
  StreamSubscription<List<ClientModel>>? _clientsSub;

  bool _can(String p) => AccessControlService.can(widget.currentUser, p);
  bool get _isSuperAdmin =>
      widget.currentUser.role.toLowerCase() ==
      AccessControlService.roleSuperAdmin;
  bool get _canViewSettings => _can(AccessControlService.pViewSettings);
  bool get _canChangeSettings => _can(AccessControlService.pChangeSettings);
  bool _canViewTab(String privilege) => _isSuperAdmin || _can(privilege);

  List<_DashboardTabSpec> get _dashboardTabs {
    final tabs = <_DashboardTabSpec>[
      const _DashboardTabSpec(key: 'tanks', label: 'Assets'),
      if (_canViewTab(AccessControlService.pViewAdminClients))
        const _DashboardTabSpec(key: 'clients', label: 'Clients'),
      if (_canViewTab(AccessControlService.pViewAdminUsers))
        const _DashboardTabSpec(key: 'users', label: 'Users'),
      if (_canViewSettings)
        const _DashboardTabSpec(key: 'settings', label: 'Settings'),
      if (_canViewTab(AccessControlService.pViewAuditLogs))
        const _DashboardTabSpec(key: 'audit_logs', label: 'Audit'),
    ];
    if (tabs.isEmpty) {
      tabs.add(const _DashboardTabSpec(key: 'empty', label: 'Dashboard'));
    }
    return tabs;
  }

  int get _tabCount => _dashboardTabs.length;

  bool _canManageMap(Map user) {
    final target = UserModel.fromMap(Map<String, dynamic>.from(user));
    return AccessControlService.canManage(widget.currentUser, target);
  }

  String? _clientDbKeyById(String clientId) {
    for (final c in _clients) {
      if (c.id == clientId) return c.dbKey;
    }
    return null;
  }

  String _tabNameByIndex(int idx) {
    final tabs = _dashboardTabs;
    if (idx >= 0 && idx < tabs.length) return tabs[idx].key;
    return 'unknown';
  }

  String _prettyPrivilegeLabel(String key) {
    switch (key) {
      case AccessControlService.pOpenAdminPage:
        return 'Can access admin module';
      case AccessControlService.pViewAdminTanks:
        return 'Can view Assets tab';
      case AccessControlService.pViewAdminClients:
        return 'Can view Clients tab';
      case AccessControlService.pViewAdminUsers:
        return 'Can view Users tab';
      case AccessControlService.pViewSettings:
        return 'Can view Settings tab';
      case AccessControlService.pViewAuditLogs:
        return 'Can view Audit Logs tab';
      case AccessControlService.pCreateClient:
        return 'Can create clients';
      case AccessControlService.pCreateUsers:
        return 'Can create users';
      case AccessControlService.pGrantUsers:
        return 'Can manage user access';
      case AccessControlService.pCreateTanks:
        return 'Can create tanks';
      case AccessControlService.pDeleteTanks:
        return 'Can delete tanks';
      case AccessControlService.pModifyTanks:
        return 'Can modify tank structure';
      case AccessControlService.pAllocateUsersToClients:
        return 'Can assign users to clients';
      case AccessControlService.pChangeSettings:
        return 'Can change settings';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  List<String> _roleCapabilities(String role) {
    switch (role) {
      case 'viewer':
        return const ['View tanks', 'View readings', 'View reports'];
      case 'operator':
        return const ['Create readings', 'Upload images', 'View tanks'];
      case 'supervisor':
        return const ['Review readings', 'View reports', 'Track abnormalities'];
      case 'admin':
        return const ['Manage users', 'Manage tanks', 'Configure operations'];
      case 'super admin':
        return const ['Full control', 'Cross-client management', 'Advanced admin'];
      default:
        return const ['Custom workflow permissions'];
    }
  }

  Future<void> _audit({
    required String operation,
    required String entityType,
    String? entityId,
    String? entityName,
    Map<String, dynamic>? details,
    String outcome = 'success',
    String? clientIdOverride,
    String? clientDbKeyOverride,
    String? clientNameOverride,
    String? cascadeId,
  }) async {
    try {
      final selectedId = clientIdOverride ?? _selectedClientId;
      final selectedDbKey = clientDbKeyOverride ??
          (selectedId == null ? null : _clientDbKeyById(selectedId));
      String? selectedName = clientNameOverride;
      if (selectedName == null && selectedId != null) {
        for (final c in _clients) {
          if (c.id == selectedId) {
            selectedName = c.name;
            break;
          }
        }
      }

      await AuditLogService.record(
        operation: operation,
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        actorId: widget.currentUser.id,
        actorUsername: widget.currentUser.username,
        actorName: widget.currentUser.fullName,
        actorRole: widget.currentUser.role,
        tab: _tabNameByIndex(_tabController.index),
        clientId: selectedId,
        clientDbKey: selectedDbKey,
        clientName: selectedName,
        details: details,
        outcome: outcome,
        cascadeId: cascadeId,
      );
    } catch (_) {}
  }

  Future<void> _auditTankAction(
      String operation, Map<String, dynamic> details) async {
    await _audit(
      operation: operation,
      entityType: 'tank_browser',
      entityId: details['node_id']?.toString(),
      entityName: details['node_name']?.toString(),
      details: details,
    );
  }

  Future<void> _auditSettingsChange({
    required bool noTimeout,
    required int minutes,
  }) async {
    await _audit(
      operation: 'update_settings',
      entityType: 'system_settings',
      details: {
        'no_session_timeout': noTimeout,
        'session_timeout_minutes': minutes,
      },
    );
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: _tabCount,
      vsync: this,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() => _tabRefreshTick++);
      }
    });

    _hydrateSelectedClient();
    _load();
  }

  Future<void> _hydrateSelectedClient() async {
    final active = await ClientContextService.getActiveClient();
    if (!mounted) return;
    if (active == null || active.id.isEmpty) return;
    setState(() {
      _selectedClientId = active.id;
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Load users only
  // Tanks are handled completely by TankBrowserScreen
  // ───────────────────────────────────────────────────────────────────────────
  void _load() {
    debugPrint('[Dashboard] Loading users...');
    _usersSub?.cancel();
    _clientsSub?.cancel();

    _usersSub = DatabaseModeService.ref('users').onValue.listen((event) {
      final users = <Map>[];

      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(
          event.snapshot.value as Map,
        );

        for (final e in data.entries) {
          users.add({
            'id': e.key,
            ...Map<String, dynamic>.from(e.value),
          });
        }
      }

      debugPrint(
        '[Dashboard] Users stream update: ${users.length}',
      );

      if (mounted) {
        setState(() {
          _users = users;
        });
      }
    });

    _clientsSub = ClientRepository().watchClients().listen((items) {
      if (!mounted) return;
      setState(() {
        _clients = items;
        _selectedClientId ??= widget.activeClient?.id;
        _selectedClientId ??= items.isNotEmpty ? items.first.id : null;
      });
    });
  }

  Future<void> _switchClient(String? clientId) async {
    if (!_isSuperAdmin) return;
    if (clientId == null || clientId == _selectedClientId) return;
    final match = _clients.where((c) => c.id == clientId);
    if (match.isEmpty) return;
    final client = match.first;
    await ClientContextService.setActiveClient(client);
    await DatabaseModeService.setClientScope(client.dbKey);
    setState(() {
      _selectedClientId = client.id;
      _tabRefreshTick++;
    });
    _load();
  }

  List<Map> get _scopedUsers {
    var users = _users;
    if (_isSuperAdmin && _selectedClientId != null) {
      users = users.where((u) {
        final ids = ((u['client_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        return ids.contains(_selectedClientId);
      }).toList();
    }
    users = users.where((u) {
      final role = (u['role']?.toString() ?? '').toLowerCase();
      return _userRoleFilters.contains(role);
    }).toList();
    return users;
  }

  Future<void> _reloadAll() async {
    _load();
  }

  Future<void> _exportStructure() async {
    final format = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141618),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF252830), width: 1.5),
        ),
        title: Text(
          'Export Tank Structure',
          style: GoogleFonts.spaceGrotesk(
            color: const Color(0xFFF0EEE9),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          'Select the format to export your asset hierarchy and parameter definitions:',
          style: GoogleFonts.dmSans(color: const Color(0xFF8A8F9C), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A8F9C))),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'json'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF252830)),
            ),
            child: const Text('JSON', style: TextStyle(color: Color(0xFFCB8C3E))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCB8C3E),
              foregroundColor: Colors.white,
            ),
            child: const Text('Excel Spreadsheet'),
          ),
        ],
      ),
    );

    if (format == null) return;

    if (format == 'json') {
      await _exportStructureJson();
    } else {
      await _exportStructureExcel();
    }
  }

  Future<void> _exportStructureJson() async {
    try {
      final tanksSnap = await DatabaseModeService.ref('tanks').get();
      final treeSnap = await DatabaseModeService.ref('tank_tree').get();
      final payload = {
        'exported_at': DateTime.now().toIso8601String(),
        'mode': DatabaseModeService.isDevelopment.value ? 'development' : 'production',
        'tanks': tanksSnap.value ?? <String, dynamic>{},
        'tank_tree': treeSnap.value ?? <String, dynamic>{},
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final bytes = utf8.encode(jsonStr);

      final clientName = widget.activeClient?.name?.replaceAll(RegExp(r'[^\w\-]'), '_') ?? 'All_Clients';
      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileName = '${clientName}_StructureBackup_$ts.json';

      final file = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: bytes,
        subPath: 'Backups',
        exportType: 'Structure Backup',
        username: widget.currentUser.username,
        clientName: widget.activeClient?.name ?? 'All Clients',
      );

      await _showSaveSuccessDialog(file, 'Structure Backup');
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF141618),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF252830), width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 12),
              Text('Export Failed', style: TextStyle(color: Color(0xFFF0EEE9), fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            'Unable to save report. No writable storage location was found. The report was not lost. Please check device storage permissions and available disk space.\n\nDetails: $e',
            style: const TextStyle(color: Color(0xFF8A8F9C), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Color(0xFF8A8F9C))),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _exportStructureExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      
      // Remove Sheet1
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final overviewSheet = excel['Structure_Overview'];
      final explanationSheet = excel['Parameter_Explanation'];
      final thenSheet = excel['THEN_Parameters'];

      // 1. Fetch data from Firebase
      final nodes = await TankTreeRepository().fetchAll();
      final tanksSnap = await DatabaseModeService.ref('tanks').get();
      final tanks = <String, TankModel>{};
      if (tanksSnap.exists && tanksSnap.value is Map) {
        final rawTanks = Map<dynamic, dynamic>.from(tanksSnap.value as Map);
        rawTanks.forEach((k, v) {
          if (v is Map) {
            final m = Map<String, dynamic>.from(v);
            if (!m.containsKey('id')) {
              m['id'] = k.toString();
            }
            tanks[k.toString()] = TankModel.fromMap(m);
          }
        });
      }

      // 2. Separate helper functions for parent properties vs THEN (nested) properties
      List<Map<String, dynamic>> getParentProperties(List<dynamic> props) {
        final list = <Map<String, dynamic>>[];
        for (final p in props) {
          if (p is Map) {
            list.add(Map<String, dynamic>.from(p));
          }
        }
        return list;
      }

      List<Map<String, dynamic>> getThenProperties(List<dynamic> props) {
        final list = <Map<String, dynamic>>[];
        void collect(List<dynamic> parentProps) {
          for (final p in parentProps) {
            if (p is! Map) continue;
            final constraints = p['constraints'] as List?;
            if (constraints != null) {
              for (final c in constraints) {
                if (c is! Map) continue;
                final thenProps = c['then_properties'] as List?;
                if (thenProps != null) {
                  for (final tp in thenProps) {
                    if (tp is Map) {
                      final tpMap = Map<String, dynamic>.from(tp);
                      list.add(tpMap);
                      collect([tpMap]);
                    }
                  }
                }
              }
            }
          }
        }
        collect(props);
        return list;
      }

      String getCanonicalKey(Map<String, dynamic> p) {
        final name = p['label']?.toString() ?? '';
        final type = p['type']?.toString() ?? '';
        final required = p['required'] == true;
        final hint = p['hint']?.toString() ?? '';
        final options = (p['options'] as List?)?.map((e) => e.toString()).join(',') ?? '';
        final autofill = p['autofill'] == true;
        final expr = p['autofill_expression']?.toString() ?? '';
        
        final constraints = (p['constraints'] as List?)?.map((c) {
          if (c is! Map) return c.toString();
          final op = c['op']?.toString() ?? '';
          final val = c['value']?.toString() ?? '';
          final title = c['alert_title']?.toString() ?? '';
          final sev = c['severity']?.toString() ?? '';
          final thenWorkflow = c['then_workflow_enabled'] == true;
          String thenPropsStr = '';
          if (thenWorkflow && c['then_properties'] is List) {
            thenPropsStr = (c['then_properties'] as List)
                .map((tp) => getCanonicalKey(Map<String, dynamic>.from(tp as Map)))
                .join('|');
          }
          return '$op:$val:$title:$sev:$thenWorkflow:$thenPropsStr';
        }).join(';') ?? '';

        return '$name|$type|$required|$hint|$options|$autofill|$expr|$constraints';
      }

      // Collect unique parent and THEN parameters separately, mapping them to first referenced asset
      final Map<String, Map<String, dynamic>> uniqueParams = {};
      final List<String> uniqueKeysInOrder = [];
      final Map<String, String> keyToRefAssetName = {};
      final Map<String, String> keyToRefAssetCode = {};

      tanks.values.forEach((tank) {
        final parentProps = getParentProperties(tank.inspectionProperties);
        for (final p in parentProps) {
          final key = getCanonicalKey(p);
          if (!uniqueParams.containsKey(key)) {
            uniqueParams[key] = p;
            uniqueKeysInOrder.add(key);
          }
          if (!keyToRefAssetName.containsKey(key)) {
            keyToRefAssetName[key] = tank.tankName;
            keyToRefAssetCode[key] = tank.tankCode;
          }
        }
      });

      final Map<String, Map<String, dynamic>> uniqueThenParams = {};
      final List<String> uniqueThenKeysInOrder = [];

      tanks.values.forEach((tank) {
        final thenProps = getThenProperties(tank.inspectionProperties);
        for (final p in thenProps) {
          final key = getCanonicalKey(p);
          if (!uniqueThenParams.containsKey(key)) {
            uniqueThenParams[key] = p;
            uniqueThenKeysInOrder.add(key);
          }
          if (!keyToRefAssetName.containsKey(key)) {
            keyToRefAssetName[key] = tank.tankName;
            keyToRefAssetCode[key] = tank.tankCode;
          }
        }
      });

      // Map child THEN parameters to their parent parameter key
      final Map<String, String> childKeyToParentKey = {};
      uniqueParams.forEach((parentKey, parentParam) {
        final constraints = parentParam['constraints'] as List?;
        if (constraints != null) {
          for (final c in constraints) {
            if (c is! Map) continue;
            final thenProps = c['then_properties'] as List?;
            if (thenProps != null) {
              for (final tp in thenProps) {
                if (tp is Map) {
                  final childKey = getCanonicalKey(Map<String, dynamic>.from(tp));
                  childKeyToParentKey[childKey] = parentKey;
                }
              }
            }
          }
        }
      });

      final List<String> softColors = [
        '#D6E4F0', // Blue
        '#D8EAD3', // Green
        '#FFF2CC', // Yellow
        '#FCE5CD', // Orange
        '#E8D8F8', // Purple
        '#FADBD8', // Pink
        '#D1F2EB', // Teal
        '#D5F5E3', // Mint
        '#E8DAEF', // Lavender
        '#FDEBD0', // Peach
        '#EBF5FB', // Sky
        '#FDEDEC', // Rose
        '#D6DBDF', // Light Grey
        '#FCF3CF', // Light Yellow
        '#D5D8DC', // Darker Grey
        '#EAECEE', // Cool Grey
        '#F5EEF8', // Light Orchid
        '#E8F8F5', // Pale Turquoise
        '#FEF9E7', // Pale Cream
        '#F4ECF7', // Pale Plum
      ];

      final Map<String, String> keyToColor = {};
      int colorCounter = 0;
      for (final key in uniqueKeysInOrder) {
        keyToColor[key] = softColors[colorCounter % softColors.length];
        colorCounter++;
      }
      for (final key in uniqueThenKeysInOrder) {
        if (!keyToColor.containsKey(key)) {
          keyToColor[key] = softColors[colorCounter % softColors.length];
          colorCounter++;
        }
      }

      final headerStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString('#AEB6BF'));

      // 3. Build Sheet 3: "THEN_Parameters" first so we know their row numbers for hyperlinks
      final Map<String, int> thenKeyToRow = {};
      
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = xl.TextCellValue('Unique ID');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = xl.TextCellValue('Parameter Name');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = xl.TextCellValue('Type');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = xl.TextCellValue('Required');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = xl.TextCellValue('Autofill');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0)).value = xl.TextCellValue('Expression');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0)).value = xl.TextCellValue('Options');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0)).value = xl.TextCellValue('Constraints');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 0)).value = xl.TextCellValue('Parent Parameter');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 0)).value = xl.TextCellValue('Ref Asset Name');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 0)).value = xl.TextCellValue('Ref Asset Code');
      // Hidden columns
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: 0)).value = xl.TextCellValue('Backend_ParamID');
      thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: 0)).value = xl.TextCellValue('Backend_ParentParamID');

      for (int col = 0; col < 13; col++) {
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = headerStyle;
      }
      thenSheet.setColumnWidth(11, 0.0);
      thenSheet.setColumnWidth(12, 0.0);

      for (int i = 0; i < uniqueThenKeysInOrder.length; i++) {
        final key = uniqueThenKeysInOrder[i];
        final p = uniqueThenParams[key]!;
        final rowIdx = i + 1;

        final uniqueId = 'T${i + 1}';
        final label = p['label']?.toString() ?? '';
        final type = p['type']?.toString() ?? '';
        final isReq = p['required'] == true ? 'YES' : 'NO';
        final isAutofill = p['autofill'] == true ? 'YES' : 'NO';
        final expr = p['autofill_expression']?.toString() ?? '';
        final options = (p['options'] as List?)?.join(', ') ?? '';

        final constraintsList = p['constraints'] as List?;
        String constraintsStr = '';
        if (constraintsList != null) {
          constraintsStr = constraintsList.map((c) {
            if (c is! Map) return c.toString();
            final op = c['op'] ?? '';
            final val = c['value'] ?? '';
            final title = c['alert_title'] ?? '';
            return '$op $val ("$title")';
          }).join('; ');
        }

        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = xl.TextCellValue(label);
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = xl.TextCellValue(type);
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = xl.TextCellValue(isReq);
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value = xl.TextCellValue(isAutofill);
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = xl.TextCellValue(expr);
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value = xl.TextCellValue(options);
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx)).value = xl.TextCellValue(constraintsStr);
        
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx)).value = xl.TextCellValue(keyToRefAssetName[key] ?? '');
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIdx)).value = xl.TextCellValue(keyToRefAssetCode[key] ?? '');
        thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx)).value = xl.TextCellValue(p['id']?.toString() ?? '');

        thenKeyToRow[key] = rowIdx + 1; // 1-based row index in THEN_Parameters

        final parentKey = childKeyToParentKey[key];
        if (parentKey != null) {
          final parentRow = uniqueKeysInOrder.indexOf(parentKey) + 2;
          final parentP = uniqueParams[parentKey]!;
          final parentName = parentP['label']?.toString() ?? '';
          final parentUniqueId = 'P${uniqueKeysInOrder.indexOf(parentKey) + 1}';

          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = 
              xl.FormulaCellValue('HYPERLINK("#Parameter_Explanation!B$parentRow", "$uniqueId")');
          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).value = 
              xl.FormulaCellValue('HYPERLINK("#Parameter_Explanation!B$parentRow", "$parentUniqueId ($parentName)")');
          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx)).value = 
              xl.TextCellValue(parentP['id']?.toString() ?? '');
        } else {
          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = xl.TextCellValue(uniqueId);
          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).value = xl.TextCellValue('N/A');
          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx)).value = xl.TextCellValue('');
        }

        final colorHex = keyToColor[key]!;
        final rowStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString(colorHex));
        for (int col = 0; col < 13; col++) {
          thenSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx)).cellStyle = rowStyle;
        }
      }

      // 4. Build Sheet 2: "Parameter_Explanation"
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = xl.TextCellValue('Unique ID');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = xl.TextCellValue('Parameter Name');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = xl.TextCellValue('Type');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = xl.TextCellValue('Required');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = xl.TextCellValue('Autofill');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0)).value = xl.TextCellValue('Expression');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0)).value = xl.TextCellValue('Options');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0)).value = xl.TextCellValue('Constraints');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 0)).value = xl.TextCellValue('THEN Workflow Details');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: 0)).value = xl.TextCellValue('Ref Asset Name');
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 0)).value = xl.TextCellValue('Ref Asset Code');
      // Hidden columns
      explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: 0)).value = xl.TextCellValue('Backend_ParamID');

      for (int col = 0; col < 12; col++) {
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = headerStyle;
      }
      explanationSheet.setColumnWidth(11, 0.0);

      final Map<String, int> keyToRowInExplanation = {};

      for (int i = 0; i < uniqueKeysInOrder.length; i++) {
        final key = uniqueKeysInOrder[i];
        final p = uniqueParams[key]!;
        final rowIdx = i + 1;

        final uniqueId = 'P${i + 1}';
        final label = p['label']?.toString() ?? '';
        final type = p['type']?.toString() ?? '';
        final isReq = p['required'] == true ? 'YES' : 'NO';
        final isAutofill = p['autofill'] == true ? 'YES' : 'NO';
        final expr = p['autofill_expression']?.toString() ?? '';
        final options = (p['options'] as List?)?.join(', ') ?? '';

        final constraintsList = p['constraints'] as List?;
        String constraintsStr = '';
        if (constraintsList != null) {
          constraintsStr = constraintsList.map((c) {
            if (c is! Map) return c.toString();
            final op = c['op'] ?? '';
            final val = c['value'] ?? '';
            final title = c['alert_title'] ?? '';
            return '$op $val ("$title")';
          }).join('; ');
        }

        String thenWorkflowStr = '';
        if (constraintsList != null) {
          thenWorkflowStr = constraintsList.map((c) {
            if (c is! Map || c['then_workflow_enabled'] != true) return '';
            final thenProps = c['then_properties'] as List?;
            final propNames = thenProps?.map((tp) => tp['label'] ?? '').join(', ') ?? '';
            return 'IF ${c['op']} ${c['value']} THEN: $propNames';
          }).where((s) => s.isNotEmpty).join('; ');
        }

        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = xl.TextCellValue(label);
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = xl.TextCellValue(type);
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = xl.TextCellValue(isReq);
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value = xl.TextCellValue(isAutofill);
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = xl.TextCellValue(expr);
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value = xl.TextCellValue(options);
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx)).value = xl.TextCellValue(constraintsStr);
        
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx)).value = xl.TextCellValue(keyToRefAssetName[key] ?? '');
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIdx)).value = xl.TextCellValue(keyToRefAssetCode[key] ?? '');
        explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx)).value = xl.TextCellValue(p['id']?.toString() ?? '');

        // Resolve hyperlink to THEN_Parameters if parent has a conditional workflow
        String firstChildKey = '';
        if (constraintsList != null) {
          for (final c in constraintsList) {
            if (c is Map && c['then_workflow_enabled'] == true) {
              final thenProps = c['then_properties'] as List?;
              if (thenProps != null && thenProps.isNotEmpty) {
                final firstTp = thenProps.first;
                if (firstTp is Map) {
                  firstChildKey = getCanonicalKey(Map<String, dynamic>.from(firstTp));
                  break;
                }
              }
            }
          }
        }

        final thenRow = thenKeyToRow[firstChildKey];
        if (thenRow != null && thenWorkflowStr.isNotEmpty) {
          explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).value = 
              xl.FormulaCellValue('HYPERLINK("#THEN_Parameters!B$thenRow", "$thenWorkflowStr")');
        } else {
          explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx)).value = 
              xl.TextCellValue(thenWorkflowStr.isEmpty ? 'N/A' : thenWorkflowStr);
        }

        keyToRowInExplanation[key] = rowIdx + 1; // 1-based row index: rowIdx=1 is Row 2

        final colorHex = keyToColor[key]!;
        final rowStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString(colorHex));
        for (int col = 0; col < 12; col++) {
          explanationSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx)).cellStyle = rowStyle;
        }
      }

      // 5. Build Sheet 1: "Structure_Overview"
      int overviewRow = 0;

      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue('CLIENT ASSETS & GROUP HIERARCHY');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).cellStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString('#AEB6BF'));
      overviewRow++;
      overviewRow++;

      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue('Folder / Group');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: overviewRow)).value = xl.TextCellValue('Subfolder / Subgroup');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: overviewRow)).value = xl.TextCellValue('Asset Name');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: overviewRow)).value = xl.TextCellValue('Asset Code');
      
      // Backend headers at cols 80-85
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_NodeID');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_ParentID');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_TankID');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 83, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_NodeType');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 84, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_Order');
      overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 85, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_IsActive');

      for (int col = 0; col < 4; col++) {
        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: overviewRow)).cellStyle = headerStyle;
      }
      overviewRow++;

      final topFolders = nodes.where((n) => n.isFolder && n.parentId == null).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

      for (final tf in topFolders) {
        final subNodes = nodes.where((n) => n.parentId == tf.id).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        
        if (subNodes.isEmpty) {
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue(tf.name);
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue(tf.id);
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue('');
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue('');
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 83, rowIndex: overviewRow)).value = xl.TextCellValue(tf.type);
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 84, rowIndex: overviewRow)).value = xl.TextCellValue(tf.order.toString());
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 85, rowIndex: overviewRow)).value = xl.TextCellValue('true');
          overviewRow++;
        }

        for (final sn in subNodes) {
          if (sn.isLeaf && sn.tankId != null) {
            final t = tanks[sn.tankId!];
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue(tf.name);
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: overviewRow)).value = xl.TextCellValue(t?.tankName ?? sn.name);
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: overviewRow)).value = xl.TextCellValue(t?.tankCode ?? '');
            
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue(sn.id);
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue(sn.parentId ?? '');
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue(sn.tankId ?? '');
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 83, rowIndex: overviewRow)).value = xl.TextCellValue(sn.type);
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 84, rowIndex: overviewRow)).value = xl.TextCellValue(sn.order.toString());
            overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 85, rowIndex: overviewRow)).value = xl.TextCellValue((t?.isActive ?? true).toString());
            overviewRow++;
          } else if (sn.isFolder) {
            final leaves = nodes.where((n) => n.parentId == sn.id && n.isLeaf).toList()
              ..sort((a, b) => a.order.compareTo(b.order));
            
            if (leaves.isEmpty) {
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue(tf.name);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: overviewRow)).value = xl.TextCellValue(sn.name);
              
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue(sn.id);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue(sn.parentId ?? '');
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue('');
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 83, rowIndex: overviewRow)).value = xl.TextCellValue(sn.type);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 84, rowIndex: overviewRow)).value = xl.TextCellValue(sn.order.toString());
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 85, rowIndex: overviewRow)).value = xl.TextCellValue('true');
              overviewRow++;
            }

            for (final lv in leaves) {
              final t = tanks[lv.tankId!];
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue(tf.name);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: overviewRow)).value = xl.TextCellValue(sn.name);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: overviewRow)).value = xl.TextCellValue(t?.tankName ?? lv.name);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: overviewRow)).value = xl.TextCellValue(t?.tankCode ?? '');
              
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue(lv.id);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue(lv.parentId ?? '');
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue(lv.tankId ?? '');
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 83, rowIndex: overviewRow)).value = xl.TextCellValue(lv.type);
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 84, rowIndex: overviewRow)).value = xl.TextCellValue(lv.order.toString());
              overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 85, rowIndex: overviewRow)).value = xl.TextCellValue((t?.isActive ?? true).toString());
              overviewRow++;
            }
          }
        }
      }

      overviewRow += 3;

      List<TankModel> getTanksInGroup(String groupId) {
        final result = <TankModel>[];
        final queue = <String>[groupId];
        while (queue.isNotEmpty) {
          final current = queue.removeAt(0);
          final children = nodes.where((n) => n.parentId == current);
          for (final c in children) {
            if (c.isLeaf && c.tankId != null) {
              final t = tanks[c.tankId!];
              if (t != null) result.add(t);
            } else if (c.isFolder) {
              queue.add(c.id);
            }
          }
        }
        return result;
      }

      final Map<String, String> keyToFirstRefCell = {};

      for (final tf in topFolders) {
        final groupTanks = getTanksInGroup(tf.id);
        if (groupTanks.isEmpty) continue;

        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue('GROUP DETAILS: ${tf.name.toUpperCase()}');
        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).cellStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString('#D5F5E3'));
        overviewRow++;
        overviewRow++;

        final groupParamLabels = <String>[];
        for (final tank in groupTanks) {
          final flatProps = getParentProperties(tank.inspectionProperties);
          for (final p in flatProps) {
            final label = p['label']?.toString() ?? '';
            if (label.isNotEmpty && !groupParamLabels.contains(label)) {
              groupParamLabels.add(label);
            }
          }
        }

        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue('Asset Name');
        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: overviewRow)).value = xl.TextCellValue('Asset Code');
        for (int col = 0; col < groupParamLabels.length; col++) {
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col + 2, rowIndex: overviewRow)).value = xl.TextCellValue(groupParamLabels[col]);
        }
        // Backend headers
        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_TankID');
        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_GroupID');
        overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue('Backend_Order');

        final groupHeaderStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString('#D5D8DC'));
        for (int col = 0; col < groupParamLabels.length + 2; col++) {
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: overviewRow)).cellStyle = groupHeaderStyle;
        }
        overviewRow++;

        for (final tank in groupTanks) {
          final flatProps = getParentProperties(tank.inspectionProperties);
          
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow)).value = xl.TextCellValue(tank.tankName);
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: overviewRow)).value = xl.TextCellValue(tank.tankCode);

          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 80, rowIndex: overviewRow)).value = xl.TextCellValue(tank.id);
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 81, rowIndex: overviewRow)).value = xl.TextCellValue(tf.id);
          final matchingNodes = nodes.where((n) => n.tankId == tank.id);
          final nodeOrder = matchingNodes.isNotEmpty ? matchingNodes.first.order : 0;
          overviewSheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 82, rowIndex: overviewRow)).value = xl.TextCellValue(nodeOrder.toString());

          for (int j = 0; j < groupParamLabels.length; j++) {
            final targetLabel = groupParamLabels[j];
            final matchProps = flatProps.where((p) => p['label'] == targetLabel);
            if (matchProps.isNotEmpty) {
              final p = matchProps.first;
              final key = getCanonicalKey(p);
              final expRow = keyToRowInExplanation[key] ?? 2;
              final colorHex = keyToColor[key]!;

              final cellIndex = xl.CellIndex.indexByColumnRow(columnIndex: j + 2, rowIndex: overviewRow);
              overviewSheet.cell(cellIndex).value = xl.FormulaCellValue('HYPERLINK("#Parameter_Explanation!B$expRow", "$targetLabel")');
              overviewSheet.cell(cellIndex).cellStyle = xl.CellStyle(backgroundColorHex: xl.ExcelColor.fromHexString(colorHex));

              if (!keyToFirstRefCell.containsKey(key)) {
                keyToFirstRefCell[key] = xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: overviewRow).cellId;
              }
            }
          }
          overviewRow++;
        }
        overviewRow += 2;
      }

      // 5. Update back hyperlinks in Sheet 2 (Parameter_Explanation)
      for (int i = 0; i < uniqueKeysInOrder.length; i++) {
        final key = uniqueKeysInOrder[i];
        final refCell = keyToFirstRefCell[key] ?? 'A1';
        final rowIdx = i + 1; // row 1 is header, so rowIdx starts at 1
        final cellIdx = xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx);
        
        explanationSheet.cell(cellIdx).value = xl.FormulaCellValue('HYPERLINK("#Structure_Overview!$refCell", "P${i + 1}")');
      }

      // Hide backend columns 80 to 90
      for (int c = 80; c <= 90; c++) {
        overviewSheet.setColumnWidth(c, 0.0);
      }

      // Auto-fit columns
      for (int c = 0; c <= 10; c++) {
        overviewSheet.setColumnAutoFit(c);
        explanationSheet.setColumnAutoFit(c);
        thenSheet.setColumnAutoFit(c);
      }

      // Save Excel file
      final clientName = widget.activeClient?.name?.replaceAll(RegExp(r'[^\w\-]'), '_') ?? 'All_Clients';
      final ts = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileName = '${clientName}_StructureBackup_$ts.xlsx';

      final file = await ReportStorageService.saveFile(
        fileName: fileName,
        bytes: excel.save()!,
        subPath: 'Backups',
        exportType: 'Structure Backup',
        username: widget.currentUser.username,
        clientName: widget.activeClient?.name ?? 'All Clients',
      );

      await _showSaveSuccessDialog(file, 'Structure Backup');
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF141618),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF252830), width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 12),
              Text('Export Failed', style: TextStyle(color: Color(0xFFF0EEE9), fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            'Unable to save Excel structure report.\n\nDetails: $e',
            style: const TextStyle(color: Color(0xFF8A8F9C), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Color(0xFF8A8F9C))),
            ),
          ],
        ),
      );
    }
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
                  'Backup Saved Successfully',
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.dmSans(color: const Color(0xFF8A8F9C), fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.dmSans(color: const Color(0xFFF0EEE9), fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _createClient() async {
    if (!_can(AccessControlService.pCreateClient)) return;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Client'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Client Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await ClientRepository().createClient(
                name: name,
                description: descCtrl.text.trim(),
              );
              await _audit(
                operation: 'create_client',
                entityType: 'client',
                entityName: name,
                details: {'description': descCtrl.text.trim()},
                clientNameOverride: name,
              );
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateClient(ClientModel client) async {
    if (!_can(AccessControlService.pCreateClient)) return;
    final nameCtrl = TextEditingController(text: client.name);
    final descCtrl = TextEditingController(text: client.description);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Client'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Client Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await DatabaseModeService.ref('clients/${client.id}').update({
                'name': name,
                'description': descCtrl.text.trim(),
              });
              await _audit(
                operation: 'update_client',
                entityType: 'client',
                entityId: client.id,
                entityName: name,
                details: {'description': descCtrl.text.trim()},
                clientIdOverride: client.id,
                clientDbKeyOverride: client.dbKey,
                clientNameOverride: name,
              );
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteClient(ClientModel client) async {
    if (!_can(AccessControlService.pCreateClient)) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete Client'),
            content: Text(
              'Delete "${client.name}"?\nUsers assigned only to this client will also be deleted.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    final usersSnap = await DatabaseModeService.ref('users').get();
    if (usersSnap.value is Map) {
      final users = Map<String, dynamic>.from(usersSnap.value as Map);
      for (final e in users.entries) {
        final uid = e.key.toString();
        final map = Map<String, dynamic>.from(e.value as Map);
        final ids = ((map['client_ids'] as List?) ?? const [])
            .map((x) => x.toString())
            .toList();
        if (!ids.contains(client.id)) continue;
        if (ids.length == 1) {
          final key = _clientDbKeyById(client.id);
          if (key != null) {
            await DatabaseModeService.ref('$key/users/$uid').remove();
          }
          await DatabaseModeService.ref('users/$uid').remove();
        } else {
          ids.removeWhere((x) => x == client.id);
          await DatabaseModeService.ref('users/$uid').update({'client_ids': ids});
          final key = _clientDbKeyById(client.id);
          if (key != null) {
            await DatabaseModeService.ref('$key/users/$uid').remove();
          }
        }
      }
    }

    await DatabaseModeService.ref('clients/${client.id}').remove();
    await _audit(
      operation: 'delete_client',
      entityType: 'client',
      entityId: client.id,
      entityName: client.name,
      clientIdOverride: client.id,
      clientDbKeyOverride: client.dbKey,
      clientNameOverride: client.name,
    );
  }

  Future<void> _updateUser(Map user) async {
    if (!_can(AccessControlService.pGrantUsers) || !_canManageMap(user)) return;
    final id = user['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final nameCtrl = TextEditingController(text: user['full_name']?.toString() ?? '');
    final userCtrl = TextEditingController(text: user['username']?.toString() ?? '');
    final passCtrl = TextEditingController();
    String role = (user['role']?.toString() ?? 'user').toLowerCase();
    final selectedPriv = <String, bool>{
      ...AccessControlService.sanitizePrivilegesForRole(
        role,
        ((user['privileges'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v == true)),
      ),
    };
    final allowedRoles = <String>['user', 'admin'];
    if (widget.currentUser.role.toLowerCase() == AccessControlService.roleSuperAdmin) {
      allowedRoles.insert(0, AccessControlService.roleSuperAdmin);
    }
    bool showAdvanced = false;
    bool customRole = false;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setD) => AlertDialog(
          title: const Text('Update User Access'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name')),
                  const SizedBox(height: 10),
                  TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Username')),
                  const SizedBox(height: 10),
                  TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'New Password (optional)')),
                  const SizedBox(height: 14),
                  if (widget.currentUser.role.toLowerCase() ==
                      AccessControlService.roleSuperAdmin) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose Access Role',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...allowedRoles.map((r) {
                          final isSelected = role == r && !customRole;
                          final color = r == 'super admin'
                              ? Colors.redAccent
                              : r == 'admin'
                                  ? Colors.orangeAccent
                                  : Colors.cyanAccent;
                          return InkWell(
                            onTap: () => setD(() {
                              role = r;
                              customRole = false;
                              final next = AccessControlService.sanitizePrivilegesForRole(
                                r,
                                Map<String, bool>.from(selectedPriv),
                              );
                              selectedPriv
                                ..clear()
                                ..addAll(next);
                            }),
                            child: Container(
                              width: 194,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? color : const Color(0xFF334155),
                                  width: isSelected ? 1.6 : 1,
                                ),
                                color: const Color(0xFF141618),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        r == 'super admin'
                                            ? Icons.verified_user_outlined
                                            : r == 'admin'
                                                ? Icons.admin_panel_settings_outlined
                                                : Icons.engineering_outlined,
                                        size: 17,
                                        color: color,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        r,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ..._roleCapabilities(r).map(
                                    (cap) => Text('• $cap', style: const TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        InkWell(
                          onTap: () => setD(() {
                            customRole = true;
                          }),
                          child: Container(
                            width: 194,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: customRole ? Colors.cyanAccent : const Color(0xFF334155),
                                width: customRole ? 1.6 : 1,
                              ),
                              color: const Color(0xFF141618),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    Icon(Icons.tune_rounded, size: 17, color: Colors.cyanAccent),
                                    SizedBox(width: 6),
                                    Text('Custom Role', style: TextStyle(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Text('• Tailored by advanced permissions', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'This user can: ${_roleCapabilities(customRole ? 'custom' : role).join(', ')}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setD(() => showAdvanced = !showAdvanced),
                        icon: Icon(showAdvanced ? Icons.expand_less : Icons.tune_rounded, size: 18),
                        label: Text(showAdvanced ? 'Hide Advanced Settings' : 'Advanced Settings'),
                      ),
                    ),
                    if (showAdvanced) ...[
                      const SizedBox(height: 6),
                      if (role == AccessControlService.roleUser)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(
                              'User accounts can only receive view permissions here.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                          color: const Color(0xFF101317),
                        ),
                        child: Column(
                          children: AccessControlService.allPrivileges.map((p) {
                            final isUserRole = role == AccessControlService.roleUser;
                            final canEdit = !isUserRole ||
                                AccessControlService.isViewPrivilege(p);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: isUserRole && !AccessControlService.isViewPrivilege(p)
                                  ? false
                                  : selectedPriv[p] == true,
                              onChanged: canEdit
                                  ? (v) => setD(() => selectedPriv[p] = v == true)
                                  : null,
                              title: Text(_prettyPrivilegeLabel(p), style: const TextStyle(fontSize: 13)),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: Colors.cyanAccent,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: role,
                      items: allowedRoles
                          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (v) => setD(() => role = v ?? role),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final existing = await DatabaseModeService.ref('users')
                    .orderByChild('username')
                    .equalTo(userCtrl.text.trim())
                    .get();
                if (existing.exists) {
                  final data = Map<String, dynamic>.from(existing.value as Map);
                  final selected = _selectedClientId;
                  final hitDifferent = data.entries.any((e) {
                    if (e.key == id) return false;
                    final m = Map<String, dynamic>.from(e.value as Map);
                    final ids = ((m['client_ids'] as List?) ?? const [])
                        .map((x) => x.toString())
                        .toSet();
                    if (selected == null || selected.isEmpty) {
                      return ids.isEmpty;
                    }
                    return ids.contains(selected);
                  });
                  if (hitDifferent) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Username already exists in this client')),
                      );
                    }
                    return;
                  }
                }
                final map = <String, dynamic>{
                  'full_name': nameCtrl.text.trim(),
                  'username': userCtrl.text.trim(),
                  'role': role,
                  'privileges': AccessControlService.sanitizePrivilegesForRole(
                    role,
                    selectedPriv,
                  ),
                };
                await DatabaseModeService.ref('users/$id').update({
                  ...map,
                  if (passCtrl.text.trim().isNotEmpty)
                    'password_hash': HashUtil.hashPassword(passCtrl.text.trim()),
                });
                await _audit(
                  operation: 'update_user',
                  entityType: 'user',
                  entityId: id,
                  entityName: nameCtrl.text.trim(),
                  details: {
                    'username': userCtrl.text.trim(),
                    'role': role,
                    'password_changed': passCtrl.text.trim().isNotEmpty,
                  },
                );
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // Client re-assignment and access toggle removed from UI by requirement.

  Widget _buildTabBody(String key) {
    switch (key) {
      case 'tanks':
        return RefreshIndicator(
          onRefresh: _reloadAll,
          child: TankBrowserScreen(
            key: ValueKey(
              'tank-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}',
            ),
            rootLabel: (() {
              for (final c in _clients) {
                if (c.id == _selectedClientId) return c.name;
              }
              return widget.activeClient?.name ?? 'Client';
            })(),
            rootFolderId: (() {
              for (final c in _clients) {
                if (c.id == _selectedClientId) return c.rootFolderId;
              }
              return widget.activeClient?.rootFolderId;
            })(),
            canCreate: _can(AccessControlService.pCreateTanks),
            canModify: _can(AccessControlService.pModifyTanks),
            canDelete: _can(AccessControlService.pDeleteTanks),
            onAudit: _auditTankAction,
          ),
        );
      case 'clients':
        return RefreshIndicator(
          key: ValueKey(
            'clients-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}',
          ),
          onRefresh: _reloadAll,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _clients.length,
            itemBuilder: (_, i) {
              final c = _clients[i];
              return ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: Text(c.name),
                subtitle: Text(c.description),
                trailing: _can(AccessControlService.pCreateClient)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Update',
                            onPressed: () => _updateClient(c),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _deleteClient(c),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      )
                    : null,
              );
            },
          ),
        );
      case 'users':
        return RefreshIndicator(
          key: ValueKey(
            'users-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}',
          ),
          onRefresh: _reloadAll,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _scopedUsers.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 8,
                    children: ['super admin', 'admin', 'user'].map((role) {
                      final selected = _userRoleFilters.contains(role);
                      return FilterChip(
                        label: Text(role),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _userRoleFilters.add(role);
                            } else {
                              _userRoleFilters.remove(role);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                );
              }

              final user = _scopedUsers[i - 1];

              final isRoot = user['username'] == 'admin' &&
                  user['full_name'] == 'System Administrator';

              return ListTile(
                leading: const Icon(
                  Icons.person,
                ),
                title: Text(
                  user['full_name'],
                ),
                subtitle: Text(
                  '${user['username']} • ${user['role']}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isRoot &&
                        _canManageMap(user) &&
                        _can(AccessControlService.pGrantUsers))
                      IconButton(
                        tooltip: 'Update',
                        onPressed: () => _updateUser(user),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (!isRoot &&
                        _canManageMap(user) &&
                        _can(AccessControlService.pGrantUsers))
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteUser(user['id']),
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      case 'settings':
        return AdminSettingsPage(
          key: ValueKey(
            'settings-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}',
          ),
          canEdit: _canChangeSettings,
          onSettingsSaved: _auditSettingsChange,
        );
      case 'audit_logs':
        return AdminAuditLogsPage(
          key: ValueKey(
            'audit-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}',
          ),
          currentUser: widget.currentUser,
          clients: _clients,
          selectedClientId: _selectedClientId,
          onClientSelected: _switchClient,
        );
      case 'empty':
        return const Center(
          child: Text('No dashboard sections are enabled for this account'),
        );
      default:
        return const Center(child: Text('Unavailable'));
    }
  }

  Future<void> _importStructureDialog() async {
    String? pickedPath;
    bool replace = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Import Structure JSON'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select exported JSON file. This imports "tanks" and "tank_tree".',
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                      allowMultiple: false,
                    );
                    if (result == null || result.files.isEmpty) return;
                    setStateDialog(() => pickedPath = result.files.single.path);
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Choose JSON File'),
                ),
                const SizedBox(height: 8),
                Text(
                  pickedPath == null ? 'No file selected' : pickedPath!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: replace,
                  onChanged: (v) => setStateDialog(() => replace = v),
                  title: const Text('Replace Existing Data'),
                  subtitle: const Text('If off, only updates imported keys'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (pickedPath == null || pickedPath!.trim().isEmpty) {
                    throw Exception('Please choose a JSON file');
                  }
                  final file = File(pickedPath!.trim());
                  if (!await file.exists()) {
                    throw Exception('File not found');
                  }
                  final raw = await file.readAsString();
                  if (raw.trim().isEmpty) throw Exception('JSON is empty');
                  final decoded = jsonDecode(raw);
                  if (decoded is! Map) throw Exception('Invalid JSON root');
                  final clientName = await ClientContextService.resolveClientName(
                    fallback: widget.activeClient?.name,
                  );
                  if (clientName == null || clientName.trim().isEmpty) {
                    throw Exception('Select an active client before importing');
                  }
                  final tanks = decoded['tanks'] is Map
                      ? Map<String, dynamic>.from(decoded['tanks'] as Map)
                      : <String, dynamic>{};
                  final tree = decoded['tank_tree'] is Map
                      ? Map<String, dynamic>.from(decoded['tank_tree'] as Map)
                      : <String, dynamic>{};
                  final cascadeId = HashUtil.generateId();
                  final importedTankNames = <String>[];
                  var importedParamCount = 0;
                  for (final entry in tanks.entries.toList()) {
                    final value = entry.value;
                    if (value is! Map) continue;
                    final tank = Map<String, dynamic>.from(value);
                    final tankName = tank['tank_name']?.toString() ?? '';
                    if (tankName.isNotEmpty) importedTankNames.add(tankName);
                    final params = tank['inspection_properties'] is List
                        ? (tank['inspection_properties'] as List)
                            .whereType<Map>()
                            .toList()
                        : const <Map>[];
                    importedParamCount += params
                        .where((p) => p['type']?.toString() != 'group')
                        .length;
                    tank['location'] = clientName;
                    final qrJson = tank['qr_json'];
                    if (qrJson is String && qrJson.trim().isNotEmpty) {
                      try {
                        final qrMap = Map<String, dynamic>.from(jsonDecode(qrJson) as Map);
                        qrMap['location'] = clientName;
                        tank['qr_json'] = jsonEncode(qrMap);
                      } catch (_) {
                        tank['qr_json'] = jsonEncode({
                          'tank_id': tank['id']?.toString() ?? entry.key.toString(),
                          'tank_code': tank['tank_code']?.toString() ?? '',
                          'tank_name': tank['tank_name']?.toString() ?? '',
                          'location': clientName,
                        });
                      }
                    } else {
                      tank['qr_json'] = jsonEncode({
                        'tank_id': tank['id']?.toString() ?? entry.key.toString(),
                        'tank_code': tank['tank_code']?.toString() ?? '',
                        'tank_name': tank['tank_name']?.toString() ?? '',
                        'location': clientName,
                      });
                    }
                    tanks[entry.key] = tank;
                  }

                  dynamic rewriteTreeZones(dynamic value) {
                    if (value is Map) {
                      final node = <String, dynamic>{};
                      for (final entry in value.entries) {
                        final key = entry.key.toString();
                        final child = entry.value;
                        node[key] = rewriteTreeZones(child);
                      }
                      if (node.containsKey('zone')) {
                        node['zone'] = clientName;
                      }
                      return node;
                    }
                    if (value is List) {
                      return value.map(rewriteTreeZones).toList();
                    }
                    return value;
                  }

                  for (final entry in tree.entries.toList()) {
                    tree[entry.key] = rewriteTreeZones(entry.value);
                  }
                  final tanksRef = DatabaseModeService.ref('tanks');
                  final treeRef = DatabaseModeService.ref('tank_tree');
                  if (replace) {
                    await tanksRef.set(tanks);
                    await treeRef.set(tree);
                  } else {
                    await tanksRef.update(tanks);
                    await treeRef.update(tree);
                  }
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Structure imported successfully')),
                  );
                  await _audit(
                    operation: 'import_structure',
                    entityType: 'tank_structure',
                    details: {
                      'replace_mode': replace,
                      'cascade_id': cascadeId,
                      'imported_tank_count': tanks.length,
                      'imported_parameter_count': importedParamCount,
                      'imported_tanks': importedTankNames,
                    },
                    cascadeId: cascadeId,
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import failed: $e')),
                  );
                  await _audit(
                    operation: 'import_structure',
                    entityType: 'tank_structure',
                    details: {
                      'replace_mode': replace,
                      'error': e.toString(),
                    },
                    outcome: 'failure',
                  );
                }
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Create user (unchanged)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _createUser() async {
    if (!_can(AccessControlService.pCreateUsers)) return;
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    bool obscure = true;
    bool loading = false;

    String role = 'user';
    String? error;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Create User'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialog(() {
                          obscure = !obscure;
                        });
                      },
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField(
                  value: role,
                  items: [
                    if (widget.currentUser.role.toLowerCase() ==
                        AccessControlService.roleSuperAdmin)
                      const DropdownMenuItem(
                        value: 'super admin',
                        child: Text('Super Admin'),
                      ),
                    const DropdownMenuItem(
                      value: 'admin',
                      child: Text('Admin'),
                    ),
                    const DropdownMenuItem(
                      value: 'user',
                      child: Text('User'),
                    ),
                  ],
                  onChanged: (v) {
                    setDialog(() {
                      role = v!;
                    });
                  },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 12,
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                setDialog(() {
                  loading = true;
                  error = null;
                });
                if (_selectedClientId == null || _selectedClientId!.isEmpty) {
                  setDialog(() {
                    loading = false;
                    error = 'Select a client first';
                  });
                  return;
                }

                final snapshot = await DatabaseModeService.ref('users')
                    .orderByChild('username')
                    .equalTo(userCtrl.text.trim())
                    .get();
                if (snapshot.exists) {
                  final data = Map<String, dynamic>.from(snapshot.value as Map);
                  final selected = _selectedClientId;
                  final conflict = data.values.any((raw) {
                    final m = Map<String, dynamic>.from(raw as Map);
                    final ids = ((m['client_ids'] as List?) ?? const [])
                        .map((x) => x.toString())
                        .toSet();
                    if (selected == null || selected.isEmpty) {
                      return ids.isEmpty;
                    }
                    return ids.contains(selected);
                  });
                  if (!conflict) {
                    // Same username exists, but in other client scope.
                  } else {
                  setDialog(() {
                    loading = false;
                    error = 'Username already exists in this client';
                  });
                  return;
                  }
                }

                await AuthRepository().createUser(
                  username: userCtrl.text,
                  fullName: nameCtrl.text,
                  password: passCtrl.text,
                  role: role,
                  clientIds: [_selectedClientId!],
                );
                await _audit(
                  operation: 'create_user',
                  entityType: 'user',
                  entityName: nameCtrl.text.trim(),
                  details: {
                    'username': userCtrl.text.trim(),
                    'role': role,
                    'client_ids': [_selectedClientId!],
                  },
                );

                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Delete user (unchanged)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _deleteUser(String id) async {
    if (!_can(AccessControlService.pGrantUsers)) return;
    final snapshot = await DatabaseModeService.ref('users/$id').get();

    if (!snapshot.exists) {
      return;
    }

    final data = Map<String, dynamic>.from(
      snapshot.value as Map,
    );
    final target = UserModel.fromMap(data);
    if (!AccessControlService.canManage(widget.currentUser, target)) return;

    final isRoot = data['username'] == 'admin' &&
        (data['role']?.toString().toLowerCase() ==
            AccessControlService.roleSuperAdmin);

    if (isRoot) {
      return;
    }

    await DatabaseModeService.ref('users/$id').remove();
    await _audit(
      operation: 'delete_user',
      entityType: 'user',
      entityId: id,
      entityName: data['full_name']?.toString(),
      details: {'username': data['username']?.toString()},
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _usersSub?.cancel();
    _clientsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_can(AccessControlService.pOpenAdminPage)) {
      return const Scaffold(
        body: Center(
          child: Text('Access denied'),
        ),
      );
    }
    final tabs = _dashboardTabs;
    final currentIndex = _tabController.index.clamp(0, tabs.length - 1).toInt();
    final currentTabKey = tabs[currentIndex].key;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        actions: [
          if (currentTabKey == 'clients' &&
              _can(AccessControlService.pCreateClient))
            IconButton(
              tooltip: 'Create Client',
              onPressed: _createClient,
              icon: const Icon(Icons.apartment_outlined),
            ),
          if (currentTabKey == 'tanks') ...[
            IconButton(
              tooltip: 'Export Structure',
              onPressed: _exportStructure,
              icon: const Icon(Icons.download_rounded),
            ),
            IconButton(
              tooltip: 'Import Structure',
              onPressed: _importStructureDialog,
              icon: const Icon(Icons.upload_rounded),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSuperAdmin ? 94 : 48),
          child: Column(
            children: [
              if (_isSuperAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: DropdownButtonFormField<String>(
                        value: _selectedClientId,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Switch Client',
                          border: OutlineInputBorder(),
                        ),
                        items: _clients
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _switchClient,
                      ),
                    ),
                  ),
                ),
              TabBar(
                controller: _tabController,
                onTap: (_) {
                  if (mounted) setState(() {});
                },
                tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: currentTabKey == 'clients' &&
              _can(AccessControlService.pCreateClient)
          ? FloatingActionButton(
              onPressed: _createClient,
              child: const Icon(Icons.apartment_outlined),
            )
          : currentTabKey == 'users' && _can(AccessControlService.pCreateUsers)
              ? FloatingActionButton(
                  onPressed: _createUser,
                  child: const Icon(Icons.person_add_alt_1),
                )
              : null,
      body: TabBarView(
        controller: _tabController,
        children: tabs.map((tab) => _buildTabBody(tab.key)).toList(),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        actions: [
          if (currentTabKey == 'clients' &&
              _can(AccessControlService.pCreateClient))
            IconButton(
              tooltip: 'Create Client',
              onPressed: _createClient,
              icon: const Icon(Icons.apartment_outlined),
            ),
          if (currentTabKey == 'tanks') ...[
            IconButton(
              tooltip: 'Export Structure',
              onPressed: _exportStructure,
              icon: const Icon(Icons.download_rounded),
            ),
            IconButton(
              tooltip: 'Import Structure',
              onPressed: _importStructureDialog,
              icon: const Icon(Icons.upload_rounded),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSuperAdmin ? 94 : 48),
          child: Column(
            children: [
              if (_isSuperAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: DropdownButtonFormField<String>(
                        value: _selectedClientId,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Switch Client',
                          border: OutlineInputBorder(),
                        ),
                        items: _clients
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: _switchClient,
                      ),
                    ),
                  ),
                ),
              TabBar(
                controller: _tabController,
                onTap: (_) {
                  if (mounted) setState(() {});
                },
                tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
              ),
            ],
          ),
        ),
      ),

      // Browser has its own +
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () async {
      //     if (_tabController.index == 1) {
      //       await _createUser();
      //     }
      //   },
      //   child: Icon(
      //     _tabController.index == 0 ? Icons.folder : Icons.add,
      //   ),
      // ),
      floatingActionButton: (_isSuperAdmin &&
                  _tabController.index == 1 &&
                  _can(AccessControlService.pCreateClient))
              ? FloatingActionButton(
                  onPressed: _createClient,
                  child: const Icon(Icons.apartment_outlined),
                )
              : ((_tabController.index == (_isSuperAdmin ? 2 : 1) &&
                      _can(AccessControlService.pCreateUsers))
                  ? FloatingActionButton(
                      onPressed: _createUser,
                      child: const Icon(Icons.person_add_alt_1),
                    )
                  : null),

      body: TabBarView(
        controller: _tabController,
        children: [
          // ───────────────────────────────────────────────────────────────────
          // Infinite hierarchical tank browser
          // ───────────────────────────────────────────────────────────────────
          RefreshIndicator(
            onRefresh: _reloadAll,
            child: TankBrowserScreen(
              key: ValueKey('tank-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}'),
              rootLabel: (() {
                for (final c in _clients) {
                  if (c.id == _selectedClientId) return c.name;
                }
                return widget.activeClient?.name ?? 'Client';
              })(),
              rootFolderId: (() {
                for (final c in _clients) {
                  if (c.id == _selectedClientId) return c.rootFolderId;
                }
                return widget.activeClient?.rootFolderId;
              })(),
              canCreate: _can(AccessControlService.pCreateTanks),
              canModify: _can(AccessControlService.pModifyTanks),
              canDelete: _can(AccessControlService.pDeleteTanks),
              onAudit: _auditTankAction,
            ),
          ),

          if (_isSuperAdmin)
            RefreshIndicator(
              key: ValueKey('clients-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}'),
              onRefresh: _reloadAll,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _clients.length,
                itemBuilder: (_, i) {
                  final c = _clients[i];
                  return ListTile(
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text(c.name),
                    subtitle: Text(c.description),
                    trailing: _can(AccessControlService.pCreateClient)
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Update',
                                onPressed: () => _updateClient(c),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => _deleteClient(c),
                                icon:
                                    const Icon(Icons.delete_outline, color: Colors.red),
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
            ),

          // ───────────────────────────────────────────────────────────────────
          // Users tab
          // ───────────────────────────────────────────────────────────────────
          RefreshIndicator(
            key: ValueKey('users-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}'),
            onRefresh: _reloadAll,
            child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _scopedUsers.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    children: ['super admin', 'admin', 'user'].map((role) {
                      final selected = _userRoleFilters.contains(role);
                      return FilterChip(
                        label: Text(role),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _userRoleFilters.add(role);
                            } else {
                              _userRoleFilters.remove(role);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                );
              }

              final user = _scopedUsers[i - 1];

              final isRoot = user['username'] == 'admin' &&
                  user['full_name'] == 'System Administrator';

              return ListTile(
                leading: const Icon(
                  Icons.person,
                ),
                title: Text(
                  user['full_name'],
                ),
                subtitle: Text(
                  '${user['username']} • ${user['role']}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isRoot && _canManageMap(user) && _can(AccessControlService.pGrantUsers))
                      IconButton(
                        tooltip: 'Update',
                        onPressed: () => _updateUser(user),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (!isRoot && _canManageMap(user) && _can(AccessControlService.pGrantUsers))
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteUser(user['id']),
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          ),
          if (_isSuperAdmin || _canViewSettings)
            AdminSettingsPage(
              key: ValueKey('settings-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}'),
              canEdit: _canChangeSettings,
              onSettingsSaved: _auditSettingsChange,
            ),
          if (_isSuperAdmin)
            AdminAuditLogsPage(
              key: ValueKey('audit-tab-$_tabRefreshTick-${_selectedClientId ?? 'none'}'),
              currentUser: widget.currentUser,
              clients: _clients,
              selectedClientId: _selectedClientId,
              onClientSelected: _switchClient,
            ),
        ],
      ),
    );
  }
}


