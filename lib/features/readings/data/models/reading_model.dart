class ReadingModel {
  final String id;
  final String tankId;
  final String? tankSnapshotName;
  final double? finalLevel;
  final Map<String, dynamic> inspectionValues;
  final String? imageUrl;
  final String source;
  final String capturedBy;
  final String capturedByName;
  final String? inferenceTimeMs;
  final String? capturedAtStart;
  final String capturedAt;

  ReadingModel({
    required this.id,
    required this.tankId,
    this.tankSnapshotName,
    this.finalLevel,
    Map<String, dynamic>? inspectionValues,
    this.imageUrl,
    this.source = 'manual',
    required this.capturedBy,
    required this.capturedByName,
    this.inferenceTimeMs,
    this.capturedAtStart,
    required this.capturedAt,
  }) : inspectionValues = inspectionValues ?? {};

  Map<String, dynamic> toMap() => {
        'id': id,
        'tank_id': tankId,
        'tank_snapshot_name': tankSnapshotName,
        'final_level': finalLevel,
        'inspection_values': inspectionValues,
        'image_url': imageUrl,
        'source': source,
        'captured_by': capturedBy,
        'captured_by_name': capturedByName,
        'inference_time_ms': inferenceTimeMs,
        'captured_at_start': capturedAtStart,
        'captured_at': capturedAt,
      };

  factory ReadingModel.fromMap(Map<String, dynamic> m) => ReadingModel(
        id: m['id']?.toString() ?? '',
        tankId: m['tank_id']?.toString() ?? '',
        tankSnapshotName: m['tank_snapshot_name']?.toString(),
        finalLevel: m['final_level'] != null
            ? (m['final_level'] as num).toDouble()
            : null,
        inspectionValues: m['inspection_values'] != null
            ? Map<String, dynamic>.from(m['inspection_values'] as Map)
            : {},
        imageUrl: m['image_url']?.toString(),
        source: m['source']?.toString() ?? 'manual',
        capturedBy: m['captured_by']?.toString() ?? '',
        capturedByName: m['captured_by_name']?.toString() ?? '',
        inferenceTimeMs: m['inference_time_ms']?.toString(),
        capturedAtStart: m['captured_at_start']?.toString(),
        capturedAt: m['captured_at']?.toString() ??
            DateTime.now().toIso8601String(),
      );
}
