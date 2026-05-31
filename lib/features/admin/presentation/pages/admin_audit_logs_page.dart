import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/models/client_model.dart';
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
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
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
    if (_clientFilter != 'all' && log['client_id']?.toString() != _clientFilter) {
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
    final haystack = [
      log['summary'],
      log['operation'],
      log['entity_name'],
      log['entity_type'],
      log['actor_name'],
      log['actor_username'],
      log['client_name'],
      jsonEncode(log['details'] ?? const {}),
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(q);
  }

  String _pretty(String value) {
    return value.replaceAll('_', ' ').trim();
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: _ref.onValue,
      builder: (context, snapshot) {
        final allLogs = _logsFrom(snapshot.data?.snapshot.value);
        final visibleLogs = allLogs.where(_matches).toList();
        final actions = <String>{'all'};
        final actors = <String>{'all'};
        final tanks = <String>{'all'};
        for (final log in allLogs) {
          final op = log['operation']?.toString();
          final actor = log['actor_username']?.toString();
          final tank = _tankLabel(log);
          if (op != null && op.isNotEmpty) actions.add(op);
          if (actor != null && actor.isNotEmpty) actors.add(actor);
          if (tank != null && tank.isNotEmpty) tanks.add(tank);
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderStrip(count: visibleLogs.length, total: allLogs.length),
              const SizedBox(height: 12),
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
                onClientChanged: (value) {
                  setState(() => _clientFilter = value);
                },
                onOperationChanged: (value) {
                  setState(() => _operationFilter = value);
                },
                onTankChanged: (value) {
                  setState(() => _tankFilter = value);
                },
                onActorChanged: (value) {
                  setState(() => _actorFilter = value);
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleLogs.isEmpty
                    ? const Center(child: Text('No audit logs found.'))
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: visibleLogs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      child: Row(
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (_) => onChanged(),
                  decoration: deco('Search summary, tank, user'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 220,
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
              const SizedBox(width: 10),
              SizedBox(
                width: 220,
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
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['super admin', 'admin', 'user', 'system'].map((role) {
                    final selected = roleFilters.contains(role);
                    return FilterChip(
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
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 220,
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
              const SizedBox(width: 10),
              SizedBox(
                width: 220,
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
        ],
      ),
    );
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
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: severityColor.withOpacity(0.15),
          child: Icon(
            _iconFor(log['severity']?.toString()),
            color: severityColor,
          ),
        ),
        title: Text(
          log['summary']?.toString() ?? log['operation']?.toString() ?? 'Audit event',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '$timeLabel • ${log['actor_name'] ?? log['actor_username'] ?? 'System'}',
        ),
        trailing: Wrap(
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1114),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF252830)),
              ),
              child: SelectableText(
                JsonEncoder.withIndent('  ').convert(details),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
      labelStyle: const TextStyle(fontSize: 12),
      backgroundColor: (color ?? const Color(0xFF252830)).withOpacity(0.18),
      side: BorderSide(color: color ?? const Color(0xFF252830)),
    );
  }
}
