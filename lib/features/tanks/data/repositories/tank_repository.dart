import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'package:firebase_database/firebase_database.dart';

import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/env_config.dart';

import 'package:lubrication_indicator/core/utils/hash_util.dart';

import '../models/tank_model.dart';

import 'tank_tree_repository.dart';

class TankRepository {
  DatabaseReference _ref(String path) => DatabaseModeService.ref(path);

  Map<String, dynamic>? _safeMap(dynamic value) {
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(
        (value as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _clientNameOrFallback(String fallback) async {
    final resolved = await ClientContextService.resolveClientName(
      fallback: fallback,
    );
    return resolved?.trim() ?? fallback.trim();
  }

  Stream<List<TankModel>> watchTanks() {
    return _ref(
          AppConstants.tanksPath,
        )
        .onValue
        .map(
      (event) {
        if (!event.snapshot.exists) {
          return [];
        }

        final map = _safeMap(event.snapshot.value);
        if (map == null) return <TankModel>[];

        return map.values
            .where((v) => v is Map)
            .map((v) {
              final m = _safeMap(v);
              if (m == null) return null;
              return TankModel.fromMap(m);
            })
            .whereType<TankModel>()
            .where(
              (t) => t.isActive,
            )
            .toList();
      },
    );
  }

  Future<List<TankModel>> getAllTanks() async {
    final snap = await _ref(
          AppConstants.tanksPath,
        )
        .get();

    if (!snap.exists) {
      return [];
    }

    final map = _safeMap(snap.value);
    if (map == null) return <TankModel>[];

    return map.values
        .where((v) => v is Map)
        .map((v) {
          final m = _safeMap(v);
          if (m == null) return null;
          return TankModel.fromMap(m);
        })
        .whereType<TankModel>()
        .where(
          (t) => t.isActive,
        )
        .toList();
  }

  Future<TankModel?> getTankById(
    String id,
  ) async {
    final snap = await _ref(
          "${AppConstants.tanksPath}/$id",
        )
        .get();

    if (!snap.exists) {
      return null;
    }

    final m = _safeMap(snap.value);
    if (m == null) return null;
    return TankModel.fromMap(m);
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
    final resolvedLocation = await _clientNameOrFallback(location);
    final existing = await getAllTanks();

    final duplicate = existing.any(
      (t) =>
          t.tankCode == tankCode &&
          t.tankName.toLowerCase() == tankName.toLowerCase() &&
          (t.location ?? "").toLowerCase() == resolvedLocation.toLowerCase(),
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
      "location": resolvedLocation,
    });

    final now = DateTime.now().toIso8601String();

    final groupsMap = <String, dynamic>{};
    for (final entry in properties.asMap().entries) {
      final index = entry.key;
      final prop = entry.value;
      if (prop['type'] == 'group') {
        final gId = prop['id'] as String;
        groupsMap[gId] = {
          'id': gId,
          'name': prop['label'] ?? '',
          'order': index,
          'rows': prop['rows'] ?? 1,
          'cols': prop['cols'] ?? 1,
          'grid_params': prop['grid_params'] ?? [],
        };
      }
    }

    final tank = TankModel(
      id: id,
      tankCode: tankCode,
      tankName: tankName,
      location: resolvedLocation,
      qrJson: qrPayload,
      qrImageUrl: qrImageUrl,
      inspectionProperties: properties,
      scaleMin: 0,
      scaleMax: scaleMax,
      scaleSide: scaleSide,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
      groups: groupsMap,
    );

    await _ref(
      "${AppConstants.tanksPath}/$id",
    ).set(
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

    final toSign =
        "public_id=$publicId&timestamp=$timestamp${EnvConfig.cloudinaryApiSecret}";

    final signature = sha1
        .convert(
          utf8.encode(
            toSign,
          ),
        )
        .toString();

    await http.post(
      Uri.parse(
        "https://api.cloudinary.com/v1_1/${EnvConfig.cloudinaryCloudName}/image/destroy",
      ),
      body: {
        "public_id": publicId,
        "api_key": EnvConfig.cloudinaryApiKey,
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
    final resolvedLocation = await _clientNameOrFallback(location);
    final existing = await getAllTanks();

    final duplicate = existing.any(
      (t) =>
          t.id != id &&
          t.tankCode == tankCode &&
          t.tankName.toLowerCase() == tankName.toLowerCase() &&
          (t.location ?? "").toLowerCase() == resolvedLocation.toLowerCase(),
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
      "location": resolvedLocation,
    });

    final groupsMap = <String, dynamic>{};
    for (final entry in properties.asMap().entries) {
      final index = entry.key;
      final prop = entry.value;
      if (prop['type'] == 'group') {
        final gId = prop['id'] as String;
        groupsMap[gId] = {
          'id': gId,
          'name': prop['label'] ?? '',
          'order': index,
          'rows': prop['rows'] ?? 1,
          'cols': prop['cols'] ?? 1,
          'grid_params': prop['grid_params'] ?? [],
        };
      }
    }

    final updateMap = {
      "tank_code": tankCode,
      "tank_name": tankName,
      "location": resolvedLocation,
      "qr_json": qrPayload,
      "inspection_properties": properties,
      "scale_max": scaleMax,
      "scale_side": scaleSide,
      "updated_at": DateTime.now().toIso8601String(),
      "Groups": groupsMap,
    };

    // only overwrite if create_tank_screen
    // generated a new QR
    if (qrImageUrl != null) {
      updateMap["qr_image_url"] = qrImageUrl;
    }

    await _ref(
      "${AppConstants.tanksPath}/$id",
    ).update(
      updateMap,
    );

    try {
      final treeSnap = await _ref("tank_tree").get();
      if (treeSnap.exists && treeSnap.value != null) {
        final raw = _safeMap(treeSnap.value);
        if (raw == null) return;
        final updates = <String, Object?>{};
        for (final e in raw.entries) {
          if (e.value is! Map) continue;
          final node = _safeMap(e.value);
          if (node == null) continue;
          if (node['tank_id']?.toString() == id) {
            final nodeId = e.key.toString();
            final oldPath = (node['path'] ?? '').toString();
            String newPath = oldPath;
            if (oldPath.isNotEmpty) {
              final lastSlash = oldPath.lastIndexOf('/');
              newPath = lastSlash == -1
                  ? tankName
                  : '${oldPath.substring(0, lastSlash)}/$tankName';
            }
            updates['$nodeId/name'] = tankName;
            // updates['${e.key}/zone'] = resolvedLocation;
            if (resolvedLocation.trim().isNotEmpty) {
                updates['${e.key}/zone'] = resolvedLocation;
            }
            if (newPath.isNotEmpty && newPath != oldPath) {
              updates['$nodeId/path'] = newPath;

              for (final d in raw.entries) {
                if (d.value is! Map) continue;
                final dn = _safeMap(d.value);
                if (dn == null) continue;
                final dPath = (dn['path'] ?? '').toString();
                if (dPath.startsWith('$oldPath/')) {
                  updates['${d.key}/path'] =
                      dPath.replaceFirst('$oldPath/', '$newPath/');
                }
              }
            }
          }
        }
        if (updates.isNotEmpty) {
          await _ref("tank_tree").update(updates);
        }
      }
    } catch (_) {}
  }

  Future<void> deleteTankFromTree(
    String tankId,
  ) async {
    final snap = await _ref("tank_tree").get();

    if (!snap.exists || snap.value == null) return;
    final root = _safeMap(snap.value);
    if (root == null) return;
    final tree = Map<String, dynamic>.from(root);

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

            await _ref(path).remove();

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
      await _ref("dashboard_stats/$id").remove();
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
    // Keep readings history for compliance/audit use-cases.
    // Uncomment if future phase requires full purge.
    // await _deleteCollectionByTankId(
    //   path: "readings",
    //   tankId: id,
    // );

    // ─────────────────────────────────────────────
    // FINALLY DELETE TANK
    // ─────────────────────────────────────────────
    await _ref("${AppConstants.tanksPath}/$id").remove();
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
    final snap = await _ref(path).get();

    if (!snap.exists || snap.value == null) {
      debugPrint(
        "[DELETE] No data found in $path",
      );
      return;
    }

    // SAFE FIREBASE MAP CAST
    final map = _safeMap(snap.value);
    if (map == null) return;

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

          await _ref(
                "$path/${e.key}",
              )
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
    final newRef = DatabaseModeService.ref('tanks').push();

    final newId = newRef.key!;
    final resolvedLocation = await _clientNameOrFallback(tank.location ?? '');
    String? updatedQrJson;
    if (tank.qrJson != null && tank.qrJson!.trim().isNotEmpty) {
      try {
        final qrMap = Map<String, dynamic>.from(jsonDecode(tank.qrJson!) as Map);
        qrMap['location'] = resolvedLocation;
        updatedQrJson = jsonEncode(qrMap);
      } catch (_) {
        updatedQrJson = jsonEncode({
          'tank_id': newId,
          'tank_code': tank.tankCode,
          'tank_name': '${tank.tankName} (Copy)',
          'location': resolvedLocation,
        });
      }
    } else {
      updatedQrJson = jsonEncode({
        'tank_id': newId,
        'tank_code': tank.tankCode,
        'tank_name': '${tank.tankName} (Copy)',
        'location': resolvedLocation,
      });
    }

    await newRef.set({
      'id': newId,
      'tank_code': tank.tankCode,
      'tank_name': '${tank.tankName} (Copy)',
      'location': resolvedLocation,
      'scale_max': tank.scaleMax,
      'scale_side': tank.scaleSide,
      'qr_image_url': tank.qrImageUrl,
      'qr_json': updatedQrJson,
      'inspection_properties': tank.inspectionProperties,
      'inspection_frequency_type': tank.inspectionFrequencyType,
      'inspection_frequency_days': tank.inspectionFrequencyDays,
      'created_at': DateTime.now().toIso8601String(),
    });

    return newId;
  }

  Future<void> updateInspectionFrequency({
    required String tankId,
    required String type,
    required int days,
  }) async {
    await _ref('tanks/$tankId').update({
      'inspection_frequency_type': type,
      'inspection_frequency_days': days < 1 ? 1 : days,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
