part of '../dashboard_tab.dart';

class _AlertModel {
  final String id;
  final String alertTitle;
  final String message;
  final String op;
  final String severity;
  final String tankId;
  final String tankName;
  final String tankCode;
  final String paramId;
  final String paramLabel;
  final String paramValue;
  final String capturedBy;
  final String capturedByName;
  final String imageUrl;
  final String constraintId;
  final String timestamp;
  final bool acknowledged;
  final bool isLive;
  final String status;
  final String readingId; // 🔖 Added for lookup in reports
  final String ifThen; // 🔖 Added for IF-THEN detail

  _AlertModel({
    required this.id,
    required this.alertTitle,
    required this.message,
    required this.severity,
    required this.op,
    required this.tankId,
    required this.tankName,
    required this.tankCode,
    required this.paramId,
    required this.paramLabel,
    required this.paramValue,
    required this.capturedBy,
    required this.capturedByName,
    required this.imageUrl,
    required this.constraintId,
    required this.timestamp,
    required this.acknowledged,
    required this.isLive,
    required this.status,
    this.readingId = '', // 🔖 Added for lookup in reports
    this.ifThen = '', // 🔖 Added for IF-THEN detail
    this.completedDescription = '',
    this.completedPhotoUrl = '',
    this.completedPhotoUrls = const [],
  });

  final String completedDescription;
  final String completedPhotoUrl;
  final List<String> completedPhotoUrls;

  factory _AlertModel.fromMap(Map<dynamic, dynamic> m) {
    final rawUrls = m['completed_photo_urls'];
    final List<String> parsedUrls = (rawUrls is List)
        ? rawUrls.map((e) => e.toString()).toList()
        : (m['completed_photo_url']?.toString().isNotEmpty == true
            ? [m['completed_photo_url'].toString()]
            : []);

    return _AlertModel(
      id: m['id']?.toString() ?? '',
      alertTitle: m['alert_title']?.toString() ?? '',
      message: m['message']?.toString() ?? '',
      severity: m['severity']?.toString() ?? 'warning',
      op: m['op']?.toString() ?? 'null',
      tankId: m['tank_id']?.toString() ?? '',
      tankName: m['tank_name']?.toString() ?? '',
      tankCode: m['tank_code']?.toString() ?? '',
      paramId: m['param_id']?.toString() ?? '',
      paramLabel: m['param_label']?.toString() ?? '',
      paramValue: m['param_value']?.toString() ?? '',
      capturedBy: m['captured_by']?.toString() ?? '',
      capturedByName: m['captured_by_name']?.toString() ?? '',
      imageUrl: m['image_url']?.toString() ?? '',
      constraintId: m['constraint_id']?.toString() ?? '',
      timestamp: m['timestamp']?.toString() ?? '',
      acknowledged: m['acknowledged'] == true,
      isLive: m['live'] == true,
      status: m['status']?.toString() ?? 'active',
      readingId: m['reading_id']?.toString() ?? '', // 🔖 Added for lookup in reports
      ifThen: m['if_then']?.toString() ?? '', // 🔖 Added for IF-THEN detail
      completedDescription: m['completed_description']?.toString() ?? '',
      completedPhotoUrl: m['completed_photo_url']?.toString() ?? '',
      completedPhotoUrls: parsedUrls,
    );
  }
}

// Completed task model (mirrors Firebase completed_tasks/ node)
