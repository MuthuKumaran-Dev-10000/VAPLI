import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';

class AuditLogService {
  static Future<void> record({
    required String operation,
    required String entityType,
    String? entityId,
    String? entityName,
    String? actorId,
    String? actorUsername,
    String? actorName,
    String? actorRole,
    String? tab,
    String? clientId,
    String? clientDbKey,
    String? clientName,
    Map<String, dynamic>? details,
    String outcome = 'success',
    String? summary,
    String? cascadeId,
    String? parentLogId,
  }) async {
    final timestamp = DateTime.now().toIso8601String();
    final logId = HashUtil.generateId();
    final resolvedClientDbKey = (clientDbKey ?? DatabaseModeService.activeClientId.value ?? '')
        .trim();
    final payload = <String, dynamic>{
      'log_id': logId,
      'timestamp': timestamp,
      'operation': operation,
      'summary': summary?.trim().isNotEmpty == true
          ? summary!.trim()
          : _defaultSummary(
              operation: operation,
              entityType: entityType,
              entityName: entityName,
              details: details,
            ),
      'entity_type': entityType,
      'entity_id': entityId ?? '',
      'entity_name': entityName ?? '',
      'entity_path': entityId == null || entityId.trim().isEmpty
          ? entityType
          : '$entityType/$entityId',
      'outcome': outcome,
      'actor_id': actorId ?? 'system',
      'actor_username': actorUsername ?? 'system',
      'actor_name': actorName ?? 'System',
      'actor_role': actorRole ?? 'system',
      'tab': tab ?? '',
      'client_id': clientId ?? '',
      'client_db_key': resolvedClientDbKey,
      'client_name': clientName ?? '',
      'cascade_id': cascadeId ?? '',
      'parent_log_id': parentLogId ?? '',
      'severity': _severityFor(operation, outcome),
      'details': details ?? <String, dynamic>{},
    };

    final scopedRef = resolvedClientDbKey.isNotEmpty
        ? FirebaseDatabase.instance
            .ref('${DatabaseModeService.isDevelopment.value ? 'testDB/' : ''}$resolvedClientDbKey/admin_audit_logs')
            .push()
        : DatabaseModeService.ref('admin_audit_logs').push();
    final rootPrefix = DatabaseModeService.isDevelopment.value ? 'testDB/' : '';
    final masterRef =
        FirebaseDatabase.instance.ref('${rootPrefix}admin_audit_logs_master').push();

    await Future.wait([
      scopedRef.set(payload),
      masterRef.set(payload),
    ]);
  }

  static String _severityFor(String operation, String outcome) {
    if (outcome != 'success') return 'warning';
    switch (operation) {
      case 'delete_tank':
      case 'delete_group':
      case 'delete_user':
      case 'delete_client':
        return 'critical';
      case 'import_structure':
      case 'update_tank':
      case 'update_tank_parameter':
      case 'save_reading':
      case 'download_png':
      case 'download_pdf':
        return 'warning';
      default:
        return 'info';
    }
  }

  static String _defaultSummary({
    required String operation,
    required String entityType,
    String? entityName,
    Map<String, dynamic>? details,
  }) {
    final target = (entityName ?? '').trim();
    switch (operation) {
      case 'create_tank':
        return target.isEmpty ? 'Created tank' : 'Created tank $target';
      case 'update_tank':
        return target.isEmpty ? 'Updated tank' : 'Updated tank $target';
      case 'create_tank_parameter':
        return target.isEmpty
            ? 'Added an inspection parameter'
            : 'Added inspection parameter $target';
      case 'update_tank_parameter':
        return target.isEmpty
            ? 'Updated an inspection parameter'
            : 'Updated inspection parameter $target';
      case 'save_reading':
        return target.isEmpty ? 'Saved reading' : 'Saved reading for $target';
      case 'download_png':
        return target.isEmpty ? 'Downloaded PNG' : 'Downloaded PNG for $target';
      case 'import_structure':
        return 'Imported structure JSON';
      case 'move_node':
      case 'move_node_to_parent':
      case 'reorder_nodes':
      case 'duplicate_group':
      case 'create_group':
      case 'update_group':
      case 'delete_group':
      case 'create_tank_leaf':
      case 'delete_tank':
        return '$operation on ${target.isEmpty ? entityType : target}';
      default:
        return target.isEmpty ? operation : '$operation on $target';
    }
  }
}
