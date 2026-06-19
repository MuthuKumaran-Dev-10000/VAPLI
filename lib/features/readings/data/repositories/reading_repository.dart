// reading_repository.dart
// ══════════════════════════════════════════════════════════════════════════════
// CHANGES:
//   ✅ saveReading() now accepts `inspectionValues` and passes it to the model
//   ✅ All existing query helpers (watchReadingsForTank, getReadingsInRange,
//      getAllReadings) untouched — they pull fromMap() which already handles
//      the new field gracefully (defaults to {} when absent in old records)
// ══════════════════════════════════════════════════════════════════════════════

import 'package:firebase_database/firebase_database.dart';

import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';
import '../models/reading_model.dart';

class ReadingRepository {
  Future<ReadingModel> saveReading({
    required String tankId,
    required String tankName,
    required double level,
    required String capturedBy,
    required String capturedByName,
    String? capturedAtStart,
    String? capturedAt, // 🔖 Added for Historical Upload Permission
    Map<String, dynamic>? inspectionValues,
    String? imageUrl,
  }) async {
    final id = HashUtil.generateId();

    final reading = ReadingModel(
      id: id,
      tankId: tankId,
      tankSnapshotName: tankName,
      finalLevel: level,
      inspectionValues: inspectionValues ?? {},
      imageUrl: imageUrl,
      source: "manual",
      capturedBy: capturedBy,
      capturedByName: capturedByName,
      capturedAtStart: capturedAtStart,
      capturedAt: capturedAt ?? DateTime.now().toIso8601String(), // 🔖 Added for Historical Upload Permission
    );

    await DatabaseModeService.ref("${AppConstants.readingsPath}/$id")
        .set(reading.toMap());

    return reading;
  }

  Stream<List<ReadingModel>> watchReadingsForTank(String tankId) {
    return DatabaseModeService.ref(AppConstants.readingsPath)
        .orderByChild("tank_id")
        .equalTo(tankId)
        .onValue
        .map((event) {
      if (!event.snapshot.exists) return [];
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      return map.values
          .map((v) => ReadingModel.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList()
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    });
  }

  Future<List<ReadingModel>> getReadingsInRange({
    required String tankId,
    required DateTime from,
    required DateTime to,
  }) async {
    final snap = await DatabaseModeService.ref(AppConstants.readingsPath)
        .orderByChild("tank_id")
        .equalTo(tankId)
        .get();

    if (!snap.exists) return [];

    final map = Map<String, dynamic>.from(snap.value as Map);
    final readings = map.values
        .map((v) => ReadingModel.fromMap(Map<String, dynamic>.from(v as Map)))
        .where((r) {
      final t = DateTime.tryParse(r.capturedAt);
      if (t == null) return false;
      return !t.toLocal().isBefore(from.toLocal()) && !t.toLocal().isAfter(to.toLocal());
    }).toList();

    readings.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return readings;
  }

  Future<List<ReadingModel>> getAllReadings() async {
    final snap = await DatabaseModeService.ref(AppConstants.readingsPath).get();
    if (!snap.exists) return [];
    final map = Map<String, dynamic>.from(snap.value as Map);
    return map.values
        .map((v) => ReadingModel.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }
}