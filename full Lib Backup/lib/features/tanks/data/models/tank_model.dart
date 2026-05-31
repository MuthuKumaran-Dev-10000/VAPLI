class TankModel {
  final String id;

  final String tankCode;

  final String tankName;

  final String? location;

  final String? qrJson;

  final String? qrImageUrl;

  final List<Map<String, dynamic>> inspectionProperties;

  final double scaleMin;

  final double scaleMax;

  final String? scaleSide;

  final bool isActive;

  final String createdBy;

  final String createdAt;

  final String updatedAt;
  final String inspectionFrequencyType; // daily|weekly_once|weekly_thrice|custom_days
  final int inspectionFrequencyDays;

  TankModel({
    required this.id,
    required this.tankCode,
    required this.tankName,
    this.location,
    this.qrJson,
    this.qrImageUrl,
    this.inspectionProperties = const [],
    this.scaleMin = 0,
    required this.scaleMax,
    this.scaleSide,
    this.isActive = true,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.inspectionFrequencyType = 'daily',
    this.inspectionFrequencyDays = 1,
  });

  String get uniqueKey => "${tankCode}_${tankName}_${location ?? "nozone"}"
      .toLowerCase()
      .replaceAll(
        " ",
        "_",
      );

  Map<String, dynamic> toMap() => {
        "id": id,
        "tank_code": tankCode,
        "tank_name": tankName,
        "location": location,
        "qr_json": qrJson,
        "qr_image_url": qrImageUrl,
        "inspection_properties": inspectionProperties,
        "scale_min": scaleMin,
        "scale_max": scaleMax,
        "scale_side": scaleSide,
        "is_active": isActive,
        "created_by": createdBy,
        "created_at": createdAt,
        "updated_at": updatedAt,
        "inspection_frequency_type": inspectionFrequencyType,
        "inspection_frequency_days": inspectionFrequencyDays,
      };

  factory TankModel.fromMap(
    Map<String, dynamic> m,
  ) {
    List<Map<String, dynamic>> properties = [];

    if (m["inspection_properties"] != null) {
      final raw = m["inspection_properties"];
      if (raw is List) {
        properties = raw
            .whereType<Map>()
            .map(
              (e) => Map<String, dynamic>.from(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
      } else if (raw is Map) {
        properties = raw.values
            .whereType<Map>()
            .map(
              (e) => Map<String, dynamic>.from(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
      }
    }

    return TankModel(
      id: m["id"] ?? "",
      tankCode: m["tank_code"] ?? "",
      tankName: m["tank_name"] ?? "",
      location: m["location"],
      qrJson: m["qr_json"],
      qrImageUrl: m["qr_image_url"],
      inspectionProperties: properties,
      scaleMin: (m["scale_min"] ?? 0).toDouble(),
      scaleMax: (m["scale_max"] ?? 100).toDouble(),
      scaleSide: m["scale_side"],
      isActive: m["is_active"] ?? true,
      createdBy: m["created_by"] ?? "",
      createdAt: m["created_at"] ?? DateTime.now().toIso8601String(),
      updatedAt: m["updated_at"] ?? DateTime.now().toIso8601String(),
      inspectionFrequencyType:
          (m["inspection_frequency_type"] ?? 'daily').toString(),
      inspectionFrequencyDays: (m["inspection_frequency_days"] as num?)?.toInt() ??
          (((m["inspection_frequency_type"] ?? 'daily').toString() == 'weekly_once')
              ? 7
              : ((m["inspection_frequency_type"] ?? 'daily').toString() ==
                      'weekly_thrice')
                  ? 2
                  : 1),
    );
  }
}
