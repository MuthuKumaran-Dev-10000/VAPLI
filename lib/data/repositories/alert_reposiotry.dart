// lib/data/repositories/alert_repository.dart
// ══════════════════════════════════════════════════════════════════════════════
// AlertRepository — CRUD for /alerts in Firebase RTDB.
//
// CALL createAlert() from ReadingEntryScreen (or ReadingRepository) when a
// constraint violation with store_history==true is detected after the reading
// has been saved.
//
// Usage example (in reading_entry_screen.dart after _save()):
//
//   for (final violation in violations) {
//     await AlertRepository().createAlert(
//       tankId:           widget.tank.id,
//       tankCode:         widget.tank.tankCode,
//       tankName:         widget.tank.tankName,
//       tankLocation:     widget.tank.location,
//       tankPath:         widget.node?.path,          // pass from TankNode if available
//       readingId:        reading.id,
//       capturedBy:       widget.currentUser.id,
//       capturedByName:   widget.currentUser.fullName,
//       capturedAt:       reading.capturedAt,
//       constraint:       violation.constraint,        // the Map from inspectionProperties
//       constraintLabel:  violation.paramLabel,
//       violatedValue:    violation.value.toString(),
//       lastInspectionValues: inspVals,
//     );
//   }
// ══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/alert_model.dart';

class AlertRepository {
  static const _path = 'alerts';
  final _ref = FirebaseDatabase.instance.ref(_path);

  // ── CREATE ─────────────────────────────────────────────────────────────────

  /// Creates a new alert record in /alerts/{newPushId}.
  /// Only writes if the constraint has store_history == true (caller's
  /// responsibility to check; this repo always writes when called).
  Future<AlertModel> createAlert({
    required String tankId,
    required String tankCode,
    required String tankName,
    String? tankLocation,
    String? tankPath,
    required String readingId,
    required String capturedBy,
    required String capturedByName,
    required String capturedAt,
    // The full constraint Map from inspectionProperties[n]['constraints'][m]
    required Map<String, dynamic> constraint,
    // The label of the parameter whose value violated the constraint
    required String constraintLabel,
    // The actual value (as string) that violated
    required String violatedValue,
    // Full inspection_values snapshot from the reading
    required Map<String, dynamic> lastInspectionValues,
  }) async {
    final newRef = _ref.push();
    final id = newRef.key!;

    final severity = constraint['severity']?.toString() ?? 'warning';
    final title =
        constraint['alert_title']?.toString().trim().isNotEmpty == true
            ? constraint['alert_title'].toString().trim()
            : _defaultTitle(severity, constraintLabel);

    final message = constraint['message']?.toString().trim().isNotEmpty == true
        ? constraint['message'].toString().trim()
        : _defaultMessage(
            op: constraint['op']?.toString() ?? '',
            value: constraint['value']?.toString() ?? '',
            label: constraintLabel,
            actual: violatedValue,
          );

    final alert = AlertModel(
      id: id,
      tankId: tankId,
      tankCode: tankCode,
      tankName: tankName,
      tankLocation: tankLocation,
      tankPath: tankPath,
      readingId: readingId,
      capturedBy: capturedBy,
      capturedByName: capturedByName,
      capturedAt: capturedAt,
      constraintId: constraint['id']?.toString() ?? '',
      constraintOp: constraint['op']?.toString() ?? '',
      constraintValue: constraint['value']?.toString() ?? '',
      constraintSeverity: severity,
      constraintLabel: constraintLabel,
      violatedValue: violatedValue,
      alertTitle: title,
      message: message,
      showDashboardAlert: constraint['show_dashboard_alert'] == true,
      playSound: constraint['play_sound_on_violation'] == true,
      captureImageOnViolation: constraint['capture_image_on_violation'] == true,
      blockSubmission: constraint['block_submission'] == true,
      lastInspectionValues: lastInspectionValues,
      resolved: false,
    );

    await newRef.set(alert.toMap());
    debugPrint('[AlertRepository] Alert created: id=$id '
        'tank=$tankCode param=$constraintLabel '
        'severity=$severity op=${constraint['op']} value=${constraint['value']} '
        'actual=$violatedValue');
    return alert;
  }

  // ── READ ───────────────────────────────────────────────────────────────────

  /// Live stream of ALL alerts, newest first.
  Stream<List<AlertModel>> watchAll() {
    return _ref.orderByChild('captured_at').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = raw.entries
          .map((e) => AlertModel.fromMap(
                e.key.toString(),
                Map<dynamic, dynamic>.from(e.value as Map),
              ))
          .toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      debugPrint('[AlertRepository] watchAll → ${list.length} alerts');
      return list;
    });
  }

  /// Live stream of alerts for a specific tank, newest first.
  Stream<List<AlertModel>> watchForTank(String tankId) {
    return _ref.orderByChild('tank_id').equalTo(tankId).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return [];
      final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = raw.entries
          .map((e) => AlertModel.fromMap(
                e.key.toString(),
                Map<dynamic, dynamic>.from(e.value as Map),
              ))
          .where((a) => a.tankId == tankId)
          .toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      return list;
    });
  }

  /// One-shot fetch of all UNRESOLVED alerts that have show_dashboard_alert==true.
  Future<List<AlertModel>> getActiveDashboardAlerts() async {
    final snap = await _ref.orderByChild('resolved').equalTo(false).get();
    if (!snap.exists || snap.value == null) return [];
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    return raw.entries
        .map((e) => AlertModel.fromMap(
              e.key.toString(),
              Map<dynamic, dynamic>.from(e.value as Map),
            ))
        .where((a) => !a.resolved && a.showDashboardAlert)
        .toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }

  /// One-shot fetch of all alerts (resolved + unresolved).
  Future<List<AlertModel>> getAll() async {
    final snap = await _ref.get();
    if (!snap.exists || snap.value == null) return [];
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    return raw.entries
        .map((e) => AlertModel.fromMap(
              e.key.toString(),
              Map<dynamic, dynamic>.from(e.value as Map),
            ))
        .toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }

  // ── RESOLVE ────────────────────────────────────────────────────────────────

  /// Marks an alert as resolved. Call from admin dashboard.
  Future<void> resolveAlert({
    required String alertId,
    required String resolvedBy,
  }) async {
    debugPrint('[AlertRepository] Resolving alert: $alertId by $resolvedBy');
    await _ref.child(alertId).update({
      'resolved': true,
      'resolved_at': DateTime.now().toIso8601String(),
      'resolved_by': resolvedBy,
    });
  }

  /// Hard-delete an alert record.
  Future<void> deleteAlert(String alertId) async {
    debugPrint('[AlertRepository] Deleting alert: $alertId');
    await _ref.child(alertId).remove();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _defaultTitle(String severity, String label) {
    switch (severity) {
      case 'critical':
        return 'Critical: $label';
      case 'warning':
        return 'Warning: $label';
      default:
        return 'Alert: $label';
    }
  }

  String _defaultMessage({
    required String op,
    required String value,
    required String label,
    required String actual,
  }) {
    final opStr = _opHuman(op);
    return '$label must be $opStr $value (recorded: $actual)';
  }

  String _opHuman(String op) {
    switch (op) {
      case '>':
        return 'greater than';
      case '>=':
        return 'at least';
      case '<':
        return 'less than';
      case '<=':
        return 'at most';
      case '==':
        return 'equal to';
      case '!=':
        return 'not equal to';
      case 'contains':
        return 'containing';
      case 'starts_with':
        return 'starting with';
      case 'ends_with':
        return 'ending with';
      case 'regex':
        return 'matching pattern';
      default:
        return op;
    }
  }
}
