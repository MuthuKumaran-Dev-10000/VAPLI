// lib/features/dashboard/data/repositories/dashboard_stats_repository.dart
// ══════════════════════════════════════════════════════════════════════════════
// Manages /dashboard_stats/{tankId} in Firebase RTDB.
//
// Responsibilities:
//   • getStats(tankId) — one-shot fetch
//   • watchStats(tankId) — realtime stream
//   • updateStatsAfterReading() — incremental update called right after
//     a new reading is saved; no bulk reprocessing needed.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_database/firebase_database.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import '../models/dashboard_stats_model.dart';
import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';

class DashboardStatsRepository {
  static const _path = 'dashboard_stats';
  DatabaseReference _ref(String tankId) =>
      DatabaseModeService.ref('$_path/$tankId');

  // ── Read ──────────────────────────────────────────────────────────────────

  Stream<DashboardStatsModel> watchStats(String tankId) {
    return _ref(tankId).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return DashboardStatsModel.empty(tankId);
      }
      return DashboardStatsModel.fromMap(
          tankId, Map<dynamic, dynamic>.from(event.snapshot.value as Map));
    });
  }

  Future<DashboardStatsModel> getStats(String tankId) async {
    final snap = await _ref(tankId).get();
    if (!snap.exists || snap.value == null) {
      return DashboardStatsModel.empty(tankId);
    }
    return DashboardStatsModel.fromMap(
        tankId, Map<dynamic, dynamic>.from(snap.value as Map));
  }

  // ── Incremental update after a new reading ────────────────────────────────

  /// Call this immediately after `ReadingRepository.saveReading()`.
  /// Reads current stats, aQpplies the new reading incrementally, and writes
  /// back in a single set() call.  No bulk processing needed.
  Future<void> updateStatsAfterReading({
    required ReadingModel reading,
    required TankModel tank,
  }) async {
    final prev = await getStats(tank.id);
    final newCount = prev.count + 1;

    // Build updated paramStats
    final updatedStats = Map<String, ParamStat>.from(prev.paramStats);

    for (final prop in tank.inspectionProperties) {
      final label = (prop['label'] as String?) ?? '';
      if (label.isEmpty) continue;

      final type = (prop['type'] as String?) ?? 'text';
      final rawValue = reading.inspectionValues[label];

      final existing = updatedStats[label] ?? ParamStat(type: type);

      if (type == 'number' || type == 'slider') {
        double? numVal;
        if (rawValue is num) {
          numVal = rawValue.toDouble();
        } else if (rawValue is String) {
          numVal = double.tryParse(rawValue);
        }
        if (numVal != null) {
          updatedStats[label] = existing.withNewNumeric(numVal, prev.count);
        } else {
          updatedStats[label] = existing; // keep old if value missing/invalid
        }
      } else if (type == 'dropdown') {
        final option = rawValue?.toString() ?? '';
        if (option.isNotEmpty) {
          updatedStats[label] = existing.withNewOption(option);
        } else {
          updatedStats[label] = existing;
        }
      } else if (type == 'dual_text') {
        if (rawValue is Map) {
          final left = (rawValue["left"] as num?)?.toDouble();

          final right = (rawValue["right"] as num?)?.toDouble();

          final leftStats = left != null
              ? (existing.dualLeftStats ??
                      const ParamStat(
                        type: "number",
                      ))
                  .withNewNumeric(
                  left,
                  prev.count,
                )
              : existing.dualLeftStats;

          final rightStats = right != null
              ? (existing.dualRightStats ??
                      const ParamStat(
                        type: "number",
                      ))
                  .withNewNumeric(
                  right,
                  prev.count,
                )
              : existing.dualRightStats;

          updatedStats[label] = ParamStat(
            type: type,
            lastValue: rawValue,
            dualLeftStats: leftStats,
            dualRightStats: rightStats,
          );
        } else {
          updatedStats[label] = existing.withLastValue(
            rawValue,
          );
        }
      } else {
        // text / multiline / dual_text — just track latest value
        updatedStats[label] = existing.withLastValue(rawValue);
      }
    }

    final updated = DashboardStatsModel(
      tankId: tank.id,
      count: newCount,
      lastCapturedAt: reading.capturedAt,
      lastCapturedBy: reading.capturedByName,
      lastReading: Map<String, dynamic>.from(reading.inspectionValues),
      paramStats: updatedStats,
    );

    await _ref(tank.id).set(updated.toMap());
  }
}
