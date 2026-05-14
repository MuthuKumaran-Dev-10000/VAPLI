import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

import 'package:firebase_database/firebase_database.dart';

import '../../core/constants/app_constants.dart';

import '../../core/utils/hash_util.dart';

import '../models/tank_model.dart';

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

  Future<void> deleteTank(
    String id,
  ) async {
    final tank = await getTankById(
      id,
    );

    if (tank?.qrImageUrl != null) {
      final publicId = _extractPublicId(
        tank!.qrImageUrl,
      );

      if (publicId != null) {
        try {
          await _deleteCloudinaryAsset(
            publicId,
          );
        } catch (_) {}
      }
    }

    await _db
        .child(
      "${AppConstants.tanksPath}/$id",
    )
        .update({
      "is_active": false,
      "updated_at": DateTime.now().toIso8601String(),
    });
  }
}
