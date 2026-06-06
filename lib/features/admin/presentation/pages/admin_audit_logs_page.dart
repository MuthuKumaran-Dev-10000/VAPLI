import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';

class AdminAuditLogsPage extends StatefulWidget {
  final UserModel currentUser;
  final List<ClientModel> clients;
  final String? selectedClientId;
  final ValueChanged<String?>? onClientSelected;

  const AdminAuditLogsPage({
    super.key,
    required this.currentUser,
    required this.clients,
    required this.selectedClientId,
    this.onClientSelected,
  });

  @override
  State<AdminAuditLogsPage> createState() => _AdminAuditLogsPageState();
}

class _AdminAuditLogsPageState extends State<AdminAuditLogsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _roleFilters = {'super admin', 'admin', 'user', 'system'};
  String _clientFilter = 'all';
  String _operationFilter = 'all';
  String _tankFilter = 'all';
  String _actorFilter = 'all';

  DatabaseReference get _ref {
    final rootPrefix = DatabaseModeService.isDevelopment.value ? 'testDB/' : '';
    final client = _selectedClientModel();
    if (client != null && client.dbKey.trim().isNotEmpty) {
      return FirebaseDatabase.instance
          .ref('${rootPrefix}${client.dbKey.trim()}/admin_audit_logs');
    }
    return FirebaseDatabase.instance.ref('${rootPrefix}admin_audit_logs_master');
  }

  @override
  void initState() {
    super.initState();
    _clientFilter = widget.selectedClientId ?? 'all';
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  ClientModel? _selectedClientModel() {
    final selectedId = widget.selectedClientId;
    if (selectedId == 'all') return null;
    if (selectedId == null || selectedId.trim().isEmpty) return null;
    for (final client in widget.clients) {
      if (client.id == selectedId) return client;
    }
    return null;
  }

  bool _clientMatches(Map<String, dynamic> log) {
    if (_clientFilter == 'all') return true;
    final selected = _selectedClientModel();
    final candidates = <String>{
      log['client_id']?.toString() ?? '',
      log['client_db_key']?.toString() ?? '',
      log['client_name']?.toString() ?? '',
    };
    final details = log['details'] is Map
        ? Map<String, dynamic>.from(log['details'] as Map)
        : <String, dynamic>{};
    candidates.add(details['client_id']?.toString() ?? '');
    candidates.add(details['client_db_key']?.toString() ?? '');
    candidates.add(details['scope_id']?.toString() ?? '');
    candidates.add(details['client_name']?.toString() ?? '');
    candidates.removeWhere((value) => value.trim().isEmpty);

    final tokens = <String>{
      _clientFilter,
      selected?.dbKey ?? '',
      selected?.name ?? '',
      selected?.rootFolderId ?? '',
    }..removeWhere((value) => value.trim().isEmpty);

    return candidates.any(tokens.contains);
  }

  List<Map<String, dynamic>> _logsFrom(dynamic value) {
    if (value is! Map) return [];
    final logs = <Map<String, dynamic>>[];
    for (final entry in value.entries) {
      final row = _mapOf(entry.value);
      row['__key'] = entry.key.toString();
      logs.add(row);
    }
    logs.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return logs;
  }

  bool _matches(Map<String, dynamic> log) {
    final role = (log['actor_role']?.toString() ?? 'system').toLowerCase();
    if (!_roleFilters.contains(role)) return false;
    if (!_clientMatches(log)) {
      return false;
    }
    if (_operationFilter != 'all' && log['operation']?.toString() != _operationFilter) {
      return false;
    }
    if (_tankFilter != 'all' && _tankLabel(log) != _tankFilter) {
      return false;
    }
    if (_actorFilter != 'all' &&
        log['actor_username']?.toString() != _actorFilter &&
        log['actor_name']?.toString() != _actorFilter) {
      return false;
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;

    final details = log['details'] is Map
        ? Map<String, dynamic>.from(log['details'] as Map)
        : <String, dynamic>{};
    final haystack = [
      log['summary'],
      log['operation'],
      log['entity_name'],
      log['entity_type'],
      log['actor_name'],
      log['actor_username'],
      log['client_name'],
      log['client_id'],
      log['client_db_key'],
      log['entity_path'],
      details['tank_name'],
      details['tank_code'],
      details['old_name'],
      details['new_name'],
      details['client_id'],
      details['client_db_key'],
      details['scope_id'],
      jsonEncode(details),
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(q);
  }

  String _pretty(String value) => value.replaceAll('_', ' ').trim();

  String _textOrDash(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _roleLabel(String? role) {
    final text = (role ?? 'system').trim();
    if (text.isEmpty) return 'System';
    return text[0].toUpperCase() + text.substring(1);
  }

  String _tankLabel(Map<String, dynamic> log) {
    final details = log['details'] is Map
        ? Map<String, dynamic>.from(log['details'] as Map)
        : <String, dynamic>{};
    final tankName = details['tank_name']?.toString();
    if (tankName != null && tankName.isNotEmpty) return tankName;
    final tankCode = details['tank_code']?.toString();
    if (tankCode != null && tankCode.isNotEmpty) return tankCode;
    final entityType = log['entity_type']?.toString();
    if (entityType == 'tank') {
      return log['entity_name']?.toString() ?? '';
    }
    return '';
  }

  String _timeLabel(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return 'Unknown time';
    return DateFormat('dd MMM yyyy, HH:mm').format(dt.toLocal());
  }

  Color _severityColor(String? severity) {
    switch ((severity ?? '').toLowerCase()) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'warning':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF60A5FA);
    }
  }

  String _auditTitle(Map<String, dynamic> log) {
    final summary = log['summary']?.toString().trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final operation = _pretty(log['operation']?.toString() ?? 'audit event');
    final entity = _pretty(log['entity_type']?.toString() ?? '');
    if (entity.isEmpty) return operation;
    return '$operation · $entity';
  }

  String _auditSummary(Map<String, dynamic> log) {
    final details = log['details'] is Map
        ? Map<String, dynamic>.from(log['details'] as Map)
        : <String, dynamic>{};
    final actorName = _textOrDash(log['actor_name'] ?? log['actor_username'] ?? 'System');
    final actorRole = _roleLabel(log['actor_role']?.toString());
    final clientName = _textOrDash(log['client_name']);
    final entityName = _textOrDash(log['entity_name']);
    final path = _textOrDash(details['path']);
    final tankName = _textOrDash(details['tank_name'] ?? details['tank_code'] ?? entityName);
    final oldName = _textOrDash(details['old_name']);
    final newName = _textOrDash(details['new_name']);
    final timestamp = _timeLabel(log['timestamp']?.toString());
    final operation = (log['operation']?.toString() ?? '').toLowerCase();

    switch (operation) {
      case 'client_rename':
        return 'The $actorRole $actorName renamed client $oldName to $newName at $timestamp.';
      case 'client_create':
        return 'The $actorRole $actorName created client $entityName at $timestamp.';
      case 'client_delete':
        return 'The $actorRole $actorName deleted client $entityName at $timestamp.';
      case 'tank_create':
        return 'The $actorRole $actorName created a new tank $tankName at $path for client $clientName at $timestamp.';
      case 'tank_update':
      case 'tank_modify':
      case 'tank_edit':
        return 'The $actorRole $actorName updated tank $tankName for client $clientName at $timestamp.';
      case 'tank_delete':
        return 'The $actorRole $actorName deleted tank $tankName for client $clientName at $timestamp.';
      case 'user_create':
        return 'The $actorRole $actorName created a new user account $entityName at $timestamp.';
      case 'user_update':
        return 'The $actorRole $actorName updated user account $entityName at $timestamp.';
      case 'user_delete':
        return 'The $actorRole $actorName deleted user account $entityName at $timestamp.';
      case 'settings_update':
      case 'update_settings':
        return 'The $actorRole $actorName changed system settings at $timestamp.';
      default:
        final operationLabel = _pretty(operation);
        return 'The $actorRole $actorName performed $operationLabel on $entityName for client $clientName at $timestamp.';
    }
  }

  Future<void> _openCompactFiltersSheet({
    required List<ClientModel> clients,
    required List<String> actions,
    required List<String> actors,
    required List<String> tanks,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.86,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (_, controller) {
              return SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(12),
                child: _FilterPanel(
                  searchCtrl: _searchCtrl,
                  roleFilters: _roleFilters,
                  clientFilter: _clientFilter,
                  operationFilter: _operationFilter,
                  tankFilter: _tankFilter,
                  actorFilter: _actorFilter,
                  clients: clients,
                  actions: actions,
                  actors: actors,
                  tanks: tanks,
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                  onClientChanged: (value) {
                    if (mounted) setState(() => _clientFilter = value);
                  },
                  onOperationChanged: (value) {
                    if (mounted) setState(() => _operationFilter = value);
                  },
                  onTankChanged: (value) {
                    if (mounted) setState(() => _tankFilter = value);
                  },
                  onActorChanged: (value) {
                    if (mounted) setState(() => _actorFilter = value);
                  },
                  compact: true,
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _ref.onValue,
      builder: (context, snapshot) {
        final allLogs = _logsFrom(snapshot.data?.snapshot.value);
        final visibleLogs = allLogs.where(_matches).toList();
        final isCompact = MediaQuery.sizeOf(context).width < 700;

        final actions = <String>{'all'};
        final actors = <String>{'all'};
        final tanks = <String>{'all'};
        for (final log in allLogs) {
          final op = log['operation']?.toString();
          final actor = log['actor_username']?.toString();
          final tank = _tankLabel(log);
          if (op != null && op.isNotEmpty) actions.add(op);
          if (actor != null && actor.isNotEmpty) actors.add(actor);
          if (tank.isNotEmpty) tanks.add(tank);
        }

        return Padding(
          padding: EdgeInsets.all(isCompact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderStrip(count: visibleLogs.length, total: allLogs.length),
              SizedBox(height: isCompact ? 8 : 12),
              if (isCompact)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Search logs',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openCompactFiltersSheet(
                        clients: widget.clients,
                        actions: actions.toList()..sort(),
                        actors: actors.toList()..sort(),
                        tanks: tanks.toList()..sort(),
                      ),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Filters'),
                    ),
                  ],
                )
              else
                _FilterPanel(
                  searchCtrl: _searchCtrl,
                  roleFilters: _roleFilters,
                  clientFilter: _clientFilter,
                  operationFilter: _operationFilter,
                  tankFilter: _tankFilter,
                  actorFilter: _actorFilter,
                  clients: widget.clients,
                  actions: actions.toList()..sort(),
                  actors: actors.toList()..sort(),
                  tanks: tanks.toList()..sort(),
                  onChanged: () => setState(() {}),
                  onClientChanged: (value) => setState(() => _clientFilter = value),
                  onOperationChanged: (value) => setState(() => _operationFilter = value),
                  onTankChanged: (value) => setState(() => _tankFilter = value),
                  onActorChanged: (value) => setState(() => _actorFilter = value),
                  compact: false,
                ),
              SizedBox(height: isCompact ? 8 : 12),
              Expanded(
                child: visibleLogs.isEmpty
                    ? const Center(child: Text('No audit logs found.'))
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: visibleLogs.length,
                        separatorBuilder: (_, __) => SizedBox(height: isCompact ? 8 : 10),
                        itemBuilder: (_, index) {
                          final log = visibleLogs[index];
                          return _AuditLogCard(
                            log: log,
                            severityColor: _severityColor(log['severity']?.toString()),
                            timeLabel: _timeLabel(log['timestamp']?.toString()),
                            pretty: _pretty,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderStrip extends StatelessWidget {
  final int count;
  final int total;

  const _HeaderStrip({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.manage_search_rounded, color: Color(0xFF1ABCBD)),
                const SizedBox(height: 8),
                Text(
                  'Audit Logs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count visible / $total total entries',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : Row(
              children: [
                const Icon(Icons.manage_search_rounded, color: Color(0xFF1ABCBD)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Audit Logs',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count visible / $total total entries',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  final TextEditingController searchCtrl;
  final Set<String> roleFilters;
  final String clientFilter;
  final String operationFilter;
  final String tankFilter;
  final String actorFilter;
  final List<ClientModel> clients;
  final List<String> actions;
  final List<String> actors;
  final List<String> tanks;
  final VoidCallback onChanged;
  final ValueChanged<String> onClientChanged;
  final ValueChanged<String> onOperationChanged;
  final ValueChanged<String> onTankChanged;
  final ValueChanged<String> onActorChanged;
  final bool compact;

  const _FilterPanel({
    required this.searchCtrl,
    required this.roleFilters,
    required this.clientFilter,
    required this.operationFilter,
    required this.tankFilter,
    required this.actorFilter,
    required this.clients,
    required this.actions,
    required this.actors,
    required this.tanks,
    required this.onChanged,
    required this.onClientChanged,
    required this.onOperationChanged,
    required this.onTankChanged,
    required this.onActorChanged,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: const Color(0xFF141618),
        );

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: compact ? double.infinity : 320,
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (_) => onChanged(),
                  decoration: deco('Search summary, tank, user'),
                ),
              ),
              SizedBox(
                width: compact ? double.infinity : 220,
                child: DropdownButtonFormField<String>(
                  value: clientFilter,
                  decoration: deco('Client'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All clients')),
                    ...clients.map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onClientChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: compact ? double.infinity : 220,
                child: DropdownButtonFormField<String>(
                  value: operationFilter,
                  decoration: deco('Action'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All actions')),
                    ...actions.where((a) => a != 'all').map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(a, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) onOperationChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: compact ? double.infinity : 220,
                child: DropdownButtonFormField<String>(
                  value: tankFilter,
                  decoration: deco('Tank'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All tanks')),
                    ...tanks.where((t) => t != 'all').map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) onTankChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: compact ? double.infinity : 220,
                child: DropdownButtonFormField<String>(
                  value: actorFilter,
                  decoration: deco('Actor'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All users')),
                    ...actors.where((a) => a != 'all').map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text(a, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) onActorChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['super admin', 'admin', 'user', 'system'].map((role) {
              final selected = roleFilters.contains(role);
              return FilterChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(role),
                selected: selected,
                onSelected: (value) {
                  if (value) {
                    roleFilters.add(role);
                  } else {
                    roleFilters.remove(role);
                  }
                  onChanged();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

String _auditTitle(Map<String, dynamic> log) {
  final summary = log['summary']?.toString().trim();
  if (summary != null && summary.isNotEmpty) return summary;
  final operation = (log['operation']?.toString() ?? 'audit event').replaceAll('_', ' ').trim();
  final entity = (log['entity_type']?.toString() ?? '').replaceAll('_', ' ').trim();
  if (entity.isEmpty) return operation;
  return '$operation · $entity';
}

String _auditSummary(Map<String, dynamic> log) {
  final details = log['details'] is Map
      ? Map<String, dynamic>.from(log['details'] as Map)
      : <String, dynamic>{};
  final actorName = (log['actor_name'] ?? log['actor_username'] ?? 'System').toString().trim();
  final actorRole = (log['actor_role']?.toString() ?? 'system').trim();
  final clientName = (log['client_name'] ?? '-').toString().trim();
  final entityName = (log['entity_name'] ?? '-').toString().trim();
  final path = (details['path'] ?? '-').toString().trim();
  final tankName = (details['tank_name'] ?? details['tank_code'] ?? entityName).toString().trim();
  final oldName = (details['old_name'] ?? '-').toString().trim();
  final newName = (details['new_name'] ?? '-').toString().trim();
  final timestamp = DateTime.tryParse(log['timestamp']?.toString() ?? '')?.toLocal();
  final timeText = timestamp == null ? 'unknown time' : DateFormat('dd MMM yyyy, HH:mm').format(timestamp);
  final roleText = actorRole.isEmpty ? 'System' : actorRole[0].toUpperCase() + actorRole.substring(1);
  final actorText = actorName.isEmpty ? 'System' : actorName;
  final op = (log['operation']?.toString() ?? '').toLowerCase();

  if (op.contains('client') && op.contains('rename')) {
    return 'The $roleText $actorText renamed client $oldName to $newName at $timeText.';
  }
  if (op.contains('client') && op.contains('create')) {
    return 'The $roleText $actorText created client $entityName at $timeText.';
  }
  if (op.contains('client') && op.contains('delete')) {
    return 'The $roleText $actorText deleted client $entityName at $timeText.';
  }
  if (op.contains('tank') && (op.contains('create') || op.contains('add'))) {
    return 'The $roleText $actorText created a new tank $tankName at $path for client $clientName at $timeText.';
  }
  if (op.contains('tank') &&
      (op.contains('update') || op.contains('modify') || op.contains('edit') || op.contains('save'))) {
    return 'The $roleText $actorText updated tank $tankName for client $clientName at $timeText.';
  }
  if (op.contains('tank') && op.contains('delete')) {
    return 'The $roleText $actorText deleted tank $tankName for client $clientName at $timeText.';
  }
  if (op.contains('user') && op.contains('create')) {
    return 'The $roleText $actorText created a new user account $entityName at $timeText.';
  }
  if (op.contains('user') &&
      (op.contains('update') || op.contains('modify') || op.contains('edit') || op.contains('save'))) {
    return 'The $roleText $actorText updated user account $entityName at $timeText.';
  }
  if (op.contains('user') && op.contains('delete')) {
    return 'The $roleText $actorText deleted user account $entityName at $timeText.';
  }
  if (op.contains('settings') || op.contains('permission')) {
    return 'The $roleText $actorText changed system settings at $timeText.';
  }

  switch (op) {
    case 'client_rename':
      return 'The $roleText $actorText renamed client $oldName to $newName at $timeText.';
    case 'client_create':
      return 'The $roleText $actorText created client $entityName at $timeText.';
    case 'client_delete':
      return 'The $roleText $actorText deleted client $entityName at $timeText.';
    case 'tank_create':
      return 'The $roleText $actorText created a new tank $tankName at $path for client $clientName at $timeText.';
    case 'tank_update':
    case 'tank_modify':
    case 'tank_edit':
      return 'The $roleText $actorText updated tank $tankName for client $clientName at $timeText.';
    case 'tank_delete':
      return 'The $roleText $actorText deleted tank $tankName for client $clientName at $timeText.';
    case 'user_create':
      return 'The $roleText $actorText created a new user account $entityName at $timeText.';
    case 'user_update':
      return 'The $roleText $actorText updated user account $entityName at $timeText.';
    case 'user_delete':
      return 'The $roleText $actorText deleted user account $entityName at $timeText.';
    case 'settings_update':
    case 'update_settings':
      return 'The $roleText $actorText changed system settings at $timeText.';
    default:
      final operationLabel = (op.isEmpty ? 'performed an action' : 'performed ${op.replaceAll('_', ' ')}');
      return 'The $roleText $actorText $operationLabel on $entityName for client $clientName at $timeText.';
  }
}

class _AuditLogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final Color severityColor;
  final String timeLabel;
  final String Function(String) pretty;

  const _AuditLogCard({
    required this.log,
    required this.severityColor,
    required this.timeLabel,
    required this.pretty,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final details = log['details'] is Map
        ? Map<String, dynamic>.from(log['details'] as Map)
        : <String, dynamic>{};
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 4 : 8),
        childrenPadding: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, compact ? 12 : 16),
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        leading: CircleAvatar(
          backgroundColor: severityColor.withOpacity(0.15),
          child: Icon(
            _iconFor(log['severity']?.toString()),
            color: severityColor,
          ),
        ),
        title: Text(
          _auditTitle(log),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 14 : 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$timeLabel • ${log['actor_name'] ?? log['actor_username'] ?? 'System'}',
              style: TextStyle(fontSize: compact ? 12 : 13),
            ),
            const SizedBox(height: 4),
            Text(
              _auditSummary(log),
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: const Color(0xFFB7C0CC),
              ),
            ),
          ],
        ),
        trailing: compact
            ? null
            : Wrap(
                spacing: 8,
                children: [
                  _Chip(text: pretty(log['operation']?.toString() ?? '')),
                  _Chip(text: (log['outcome']?.toString() ?? 'success').toUpperCase(), color: severityColor),
                ],
              ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(text: 'Actor: ${log['actor_username'] ?? 'system'}'),
              _Chip(text: 'Role: ${log['actor_role'] ?? 'system'}'),
              _Chip(text: 'Client: ${log['client_name'] ?? '-'}'),
              _Chip(text: 'Entity: ${log['entity_type'] ?? '-'}'),
              _Chip(text: 'Target: ${log['entity_name'] ?? '-'}'),
            ],
          ),
          const SizedBox(height: 12),
          if (details.isNotEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 10 : 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1114),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF252830)),
              ),
              child: SelectableText(
                JsonEncoder.withIndent('  ').convert(details),
                style: TextStyle(fontFamily: 'monospace', fontSize: compact ? 10 : 12),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(String? severity) {
    switch ((severity ?? '').toLowerCase()) {
      case 'critical':
        return Icons.dangerous_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      default:
        return Icons.history_rounded;
    }
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color? color;

  const _Chip({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      labelStyle: const TextStyle(fontSize: 11),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      backgroundColor: (color ?? const Color(0xFF252830)).withOpacity(0.18),
      side: BorderSide(color: color ?? const Color(0xFF252830)),
    );
  }
}
