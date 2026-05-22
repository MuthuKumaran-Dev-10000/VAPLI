// reading_model.dart
// ══════════════════════════════════════════════════════════════════════════════
// CHANGES:
//   ✅ Added `inspectionValues` — Map<String, dynamic> storing every dynamic
//      parameter the inspector filled in, keyed by the property label.
//      e.g. {"Oil Temperature": 72.0, "Condition": "Good", "Notes": "OK"}
//   ✅ toMap() serialises inspectionValues under "inspection_values"
//   ✅ fromMap() deserialises it safely (handles null + cast)
//   ✅ All existing fields untouched
// ══════════════════════════════════════════════════════════════════════════════

class ReadingModel {
  final String id;
    final String tankId;
      final String? tankSnapshotName;
        final double? finalLevel;

          /// Each key = property label (e.g. "Oil Temperature")
            /// Each value = whatever the inspector entered:
              ///   number  → double
                ///   text    → String
                  ///   multiline → String
                    ///   dropdown  → String (selected option)
                      ///   dual_text → Map {"left": String, "right": String}
                        ///   slider    → double
                          final Map<String, dynamic> inspectionValues;

                            // CLOUDINARY URL
                              final String? imageUrl;

                                final String source;
                                  final String capturedBy;
                                    final String capturedByName;
                                      final String? inferenceTimeMs;
                                        final String capturedAt;

                                          ReadingModel({
                                              required this.id,
                                                  required this.tankId,
                                                      this.tankSnapshotName,
                                                          this.finalLevel,
                                                              Map<String, dynamic>? inspectionValues,
                                                                  this.imageUrl,
                                                                      this.source = "manual",
                                                                          required this.capturedBy,
                                                                              required this.capturedByName,
                                                                                  this.inferenceTimeMs,
                                                                                      required this.capturedAt,
                                                                                        }) : inspectionValues = inspectionValues ?? {};

                                                                                          Map<String, dynamic> toMap() => {
                                                                                                  "id": id,
                                                                                                          "tank_id": tankId,
                                                                                                                  "tank_snapshot_name": tankSnapshotName,
                                                                                                                          "final_level": finalLevel,
                                                                                                                                  "inspection_values": inspectionValues,
                                                                                                                                          // CLOUDINARY
                                                                                                                                                  "image_url": imageUrl,
                                                                                                                                                          "source": source,
                                                                                                                                                                  "captured_by": capturedBy,
                                                                                                                                                                          "captured_by_name": capturedByName,
                                                                                                                                                                                  "inference_time_ms": inferenceTimeMs,
                                                                                                                                                                                          "captured_at": capturedAt,
                                                                                                                                                                                                };

                                                                                                                                                                                                  factory ReadingModel.fromMap(Map<String, dynamic> m) => ReadingModel(
                                                                                                                                                                                                          id: m["id"] ?? "",
                                                                                                                                                                                                                  tankId: m["tank_id"] ?? "",
                                                                                                                                                                                                                          tankSnapshotName: m["tank_snapshot_name"],
                                                                                                                                                                                                                                  finalLevel: m["final_level"] != null
                                                                                                                                                                                                                                              ? (m["final_level"] as num).toDouble()
                                                                                                                                                                                                                                                          : null,
                                                                                                                                                                                                                                                                  inspectionValues: m["inspection_values"] != null
                                                                                                                                                                                                                                                                              ? Map<String, dynamic>.from(m["inspection_values"] as Map)
                                                                                                                                                                                                                                                                                          : {},
                                                                                                                                                                                                                                                                                                  // CLOUDINARY
                                                                                                                                                                                                                                                                                                          imageUrl: m["image_url"],
                                                                                                                                                                                                                                                                                                                  source: m["source"] ?? "manual",
                                                                                                                                                                                                                                                                                                                          capturedBy: m["captured_by"] ?? "",
                                                                                                                                                                                                                                                                                                                                  capturedByName: m["captured_by_name"] ?? "",
                                                                                                                                                                                                                                                                                                                                          inferenceTimeMs: m["inference_time_ms"]?.toString(),
                                                                                                                                                                                                                                                                                                                                                  capturedAt: m["captured_at"] ?? DateTime.now().toIso8601String(),
                                                                                                                                                                                                                                                                                                                                                        );
                                                                                                                                                                                                                                                                                                                                                        }
                                                                                                                                                                                                                                                                                                                                                        