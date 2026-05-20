import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'package:firebase_database/firebase_database.dart';

import '../../core/constants/app_constants.dart';

import '../../core/utils/hash_util.dart';

import '../models/tank_model.dart';

import 'tank_tree_repository.dart';

class TankRepository {
  final _db = FirebaseDatabase.instance.ref();

  static const String _cloudName = "dummy-cloudinary-cloud-name";

  static const String _apiKey = "dummy-cloudinary-api-key";

  static const String _apiSecret = "dummy-cloudinary-api-secret";

  Stream<List<TankModel>> watchTanks() {
    return _db
        .child(
          AppConstants.tanksPath,
        )
        .onValue
        .map(
      (event) {
        if (!event.snapshot.exists) {
          return [];
        }

        final map = Map<String, dynamic>.from(
          event.snapshot.value as Map,
        );

        return map.values
            .map(
              (v) => TankModel.fromMap(
                Map<String, dynamic>.from(
                  v as Map,
                ),
              ),
            )
            .where(
              (t) => t.isActive,
            )
            .toList();
      },
    );
  }

  Future<List<TankModel>> getAllTanks() async {
    final snap = await _db
        .child(
          AppConstants.tanksPath,
        )
        .get();

    if (!snap.exists) {
      return [];
    }

    final map = Map<String, dynamic>.from(
      snap.value as Map,
    );

    return map.values
        .map(
          (v) => TankModel.fromMap(
            Map<String, dynamic>.from(
              v as Map,
            ),
          ),
        )
        .where(
          (t) => t.isActive,
        )
        .toList();
  }

  Future<TankModel?> getTankById(
    String id,
  ) async {
    final snap = await _db
        .child(
          "${AppConstants.tanksPath}/$id",
        )
        .get();

    if (!snap.exists) {
      return null;
    }

    return TankModel.fromMap(
      Map<String, dynamic>.from(
        snap.value as Map,
      ),
    );
  }

  Future<TankModel> createTank({
    required String tankCode,
    required String tankName,
    required String location,
    required double scaleMax,
    String? qrImageUrl,
    String? scaleSide,
    required String createdBy,
    required List<Map<String, dynamic>> properties,
  }) async {
    final existing = await getAllTanks();

    final duplicate = existing.any(
      (t) =>
          t.tankCode == tankCode &&
          t.tankName.toLowerCase() == tankName.toLowerCase() &&
          (t.location ?? "").toLowerCase() == location.toLowerCase(),
    );

    if (duplicate) {
      throw Exception(
        "Tank with same Code + Name + Zone already exists",
      );
    }

    final id = HashUtil.generateId();

    final qrPayload = jsonEncode({
      "tank_id": id,
      "tank_code": tankCode,
      "tank_name": tankName,
      "location": location,
    });

    final now = DateTime.now().toIso8601String();

    final tank = TankModel(
      id: id,
      tankCode: tankCode,
      tankName: tankName,
      location: location,
      qrJson: qrPayload,
      qrImageUrl: qrImageUrl,
      inspectionProperties: properties,
      scaleMin: 0,
      scaleMax: scaleMax,
      scaleSide: scaleSide,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );

    await _db
        .child(
          "${AppConstants.tanksPath}/$id",
        )
        .set(
          tank.toMap(),
        );

    return tank;
  }

  String? _extractPublicId(
    String? url,
  ) {
    if (url == null) {
      return null;
    }

    try {
      final uri = Uri.parse(
        url,
      );

      final parts = uri.pathSegments;

      final uploadIndex = parts.indexOf(
        "upload",
      );

      final publicParts = parts.sublist(
        uploadIndex + 2,
      );

      final full = publicParts.join(
        "/",
      );

      return full.replaceAll(
        RegExp(
          r'\.[^.]+$',
        ),
        "",
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteCloudinaryAsset(
    String publicId,
  ) async {
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final toSign = "public_id=$publicId&timestamp=$timestamp$_apiSecret";

    final signature = sha1
        .convert(
          utf8.encode(
            toSign,
          ),
        )
        .toString();

    await http.post(
      Uri.parse(
        "https://api.cloudinary.com/v1_1/$_cloudName/image/destroy",
      ),
      body: {
        "public_id": publicId,
        "api_key": _apiKey,
        "timestamp": timestamp,
        "signature": signature,
      },
    );
  }

  Future<void> updateTank({
    required String id,
    required String tankCode,
    required String tankName,
    required String location,
    required double scaleMax,
    String? scaleSide,
    String? qrImageUrl,
    required List<Map<String, dynamic>> properties,
  }) async {
    final existing = await getAllTanks();

    final duplicate = existing.any(
      (t) =>
          t.id != id &&
          t.tankCode == tankCode &&
          t.tankName.toLowerCase() == tankName.toLowerCase() &&
          (t.location ?? "").toLowerCase() == location.toLowerCase(),
    );

    if (duplicate) {
      throw Exception(
        "Tank with same Code + Name + Zone already exists",
      );
    }

    final qrPayload = jsonEncode({
      "tank_id": id,
      "tank_code": tankCode,
      "tank_name": tankName,
      "location": location,
    });

    final updateMap = {
      "tank_code": tankCode,
      "tank_name": tankName,
      "location": location,
      "qr_json": qrPayload,
      "inspection_properties": properties,
      "scale_max": scaleMax,
      "scale_side": scaleSide,
      "updated_at": DateTime.now().toIso8601String(),
    };

    // only overwrite if create_tank_screen
    // generated a new QR
    if (qrImageUrl != null) {
      updateMap["qr_image_url"] = qrImageUrl;
    }

    await _db
        .child(
          "${AppConstants.tanksPath}/$id",
        )
        .update(
          updateMap,
        );
  }

  Future<void> deleteTankFromTree(
    String tankId,
  ) async {
    final snap = await _db.child("tank_tree").get();

    if (!snap.exists) return;

    final tree = Map<String, dynamic>.from(
      snap.value as Map,
    );

    await _walkAndDeleteTank(
      node: tree,
      currentPath: "tank_tree",
      tankId: tankId,
    );
  }
  // ── HELPERS ───────────────────────────────────────────────────────────────

  Future<void> _walkAndDeleteTank({
    required Map node,
    required String currentPath,
    required String tankId,
  }) async {
    for (final e in node.entries) {
      try {
        final key = e.key.toString();
        final value = e.value;

        final path = "$currentPath/$key";

        // SAFE MAP CHECK
        if (value is Map) {
          final map = Map<String, dynamic>.from(
            value.map(
              (k, v) => MapEntry(
                k.toString(),
                v,
              ),
            ),
          );

          // MATCH TANK
          if (map["tank_id"]?.toString() == tankId ||
              map["id"]?.toString() == tankId) {
            debugPrint(
              "[DELETE] Removing tree node: $path",
            );

            await _db.child(path).remove();

            continue;
          }

          // RECURSIVE WALK
          await _walkAndDeleteTank(
            node: map,
            currentPath: path,
            tankId: tankId,
          );
        }
      } catch (e, s) {
        debugPrint(
          "[DELETE TREE ERROR] $e\n$s",
        );
      }
    }
  }

  Future<void> deleteTank(String id) async {
    final tank = await getTankById(id);

    // ─────────────────────────────────────────────
    // DELETE CLOUDINARY QR
    // ─────────────────────────────────────────────
    if (tank?.qrImageUrl != null) {
      final publicId = _extractPublicId(
        tank!.qrImageUrl,
      );

      if (publicId != null) {
        try {
          await _deleteCloudinaryAsset(publicId);
        } catch (_) {}
      }
    }

    // ─────────────────────────────────────────────
    // DELETE DASHBOARD STATS
    // ─────────────────────────────────────────────
    try {
      await _db.child("dashboard_stats/$id").remove();
    } catch (_) {}

    // ─────────────────────────────────────────────
    // DELETE FROM TANK TREE
    // ─────────────────────────────────────────────
    try {
      await deleteTankFromTree(id);
    } catch (_) {}

    // ─────────────────────────────────────────────
    // DELETE ALERTS
    // ─────────────────────────────────────────────
    await _deleteCollectionByTankId(
      path: "alerts",
      tankId: id,
    );

    await _deleteCollectionByTankId(
      path: "alerts_full",
      tankId: id,
    );

    await _deleteCollectionByTankId(
      path: "violations",
      tankId: id,
    );

    // ─────────────────────────────────────────────
    // DELETE READINGS
    // ─────────────────────────────────────────────
    await _deleteCollectionByTankId(
      path: "readings",
      tankId: id,
    );

    // ─────────────────────────────────────────────
    // FINALLY DELETE TANK
    // ─────────────────────────────────────────────
    await _db.child("${AppConstants.tanksPath}/$id").remove();
  }

  // Future<void> _deleteCollectionByTankId({
  //   required String path,
  //   required String tankId,
  // }) async {
  //   final snap = await _db.child(path).get();

  //   if (!snap.exists) return;

  //   final map = Map<String, dynamic>.from(
  //     snap.value as Map,
  //   );

  //   for (final e in map.entries) {
  //     final data = Map<String, dynamic>.from(
  //       e.value,
  //     );

  //     if (data["tank_id"] == tankId) {
  //       await _db.child("$path/${e.key}").remove();
  //     }
  //   }
  // }
  Future<void> _deleteCollectionByTankId({
  required String path,
  required String tankId,
}) async {
  try {
    final snap = await _db.child(path).get();

    if (!snap.exists || snap.value == null) {
      debugPrint(
        "[DELETE] No data found in $path",
      );
      return;
    }

    // SAFE FIREBASE MAP CAST
    final raw = snap.value as Map;

    final map = Map<String, dynamic>.from(
      raw.map(
        (k, v) => MapEntry(
          k.toString(),
          v,
        ),
      ),
    );

    for (final e in map.entries) {
      try {
        if (e.value is! Map) {
          continue;
        }

        final data = Map<String, dynamic>.from(
          (e.value as Map).map(
            (k, v) => MapEntry(
              k.toString(),
              v,
            ),
          ),
        );

        final currentTankId =
            data["tank_id"]?.toString();

        if (currentTankId == tankId) {
          debugPrint(
            "[DELETE] Removing $path/${e.key}",
          );

          await _db
              .child("$path/${e.key}")
              .remove();
        }
      } catch (e, s) {
        debugPrint(
          "[DELETE ITEM ERROR] $e\n$s",
        );
      }
    }
  } catch (e, s) {
    debugPrint(
      "[DELETE COLLECTION ERROR][$path] $e\n$s",
    );
  }
}

  Future<String> duplicateTank(TankModel tank) async {
    final newRef = FirebaseDatabase.instance.ref('tanks').push();

    final newId = newRef.key!;

    await newRef.set({
      'id': newId,
      'tank_code': tank.tankCode,
      'tank_name': '${tank.tankName} (Copy)',
      'location': tank.location,
      'scale_max': tank.scaleMax,
      'scale_side': tank.scaleSide,
      'qr_image_url': tank.qrImageUrl,
      'qr_json': tank.qrJson,
      'inspection_properties': tank.inspectionProperties,
      'created_at': DateTime.now().toIso8601String(),
    });

    return newId;
  }
}
