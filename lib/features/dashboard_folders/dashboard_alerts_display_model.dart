// lib/features/dashboard_folders/dashboard_alerts_display_model.dart

class DashboardAlertDisplayItem {
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
  final String readingId;
  final String ifThen;
  final String completedDescription;
  final String completedPhotoUrl;
  final List<String> completedPhotoUrls;
  final int rankScore;
  final int severityRating;
  final String dueTimeRange;
  final String dueDate;

  DashboardAlertDisplayItem({
    required this.id,
    required this.alertTitle,
    required this.message,
    required this.op,
    required this.severity,
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
    this.readingId = '',
    this.ifThen = '',
    this.completedDescription = '',
    this.completedPhotoUrl = '',
    this.completedPhotoUrls = const [],
    this.rankScore = 0,
    this.severityRating = 50,
    this.dueTimeRange = 'today',
    this.dueDate = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alert_title': alertTitle,
      'message': message,
      'op': op,
      'severity': severity,
      'tank_id': tankId,
      'tank_name': tankName,
      'tank_code': tankCode,
      'param_id': paramId,
      'param_label': paramLabel,
      'param_value': paramValue,
      'captured_by': capturedBy,
      'captured_by_name': capturedByName,
      'image_url': imageUrl,
      'constraint_id': constraintId,
      'timestamp': timestamp,
      'acknowledged': acknowledged,
      'live': isLive,
      'status': status,
      'reading_id': readingId,
      'if_then': ifThen,
      'completed_description': completedDescription,
      'completed_photo_url': completedPhotoUrl,
      'completed_photo_urls': completedPhotoUrls,
      'rank_score': rankScore,
      'severity_rating': severityRating,
      'due_time_range': dueTimeRange,
      'due_date': dueDate,
    };
  }

  static int calcRankScore(String severity, int rating, String timeRange, String dueDateIso) {
    // 1. Severity Base (Max 40 points)
    int sevScore = 10;
    final s = severity.toLowerCase();
    if (s == 'critical') {
      sevScore = 40;
    } else if (s == 'warning') {
      sevScore = 25;
    }

    // 2. Time Urgency Base (Max 30 points)
    int timeScore = 10;
    if (timeRange == 'today') {
      timeScore = 30;
    } else if (timeRange == 'tomorrow') {
      timeScore = 20;
    } else if (timeRange == '1_week') {
      timeScore = 10;
    } else if (dueDateIso.isNotEmpty) {
      try {
        final dt = DateTime.parse(dueDateIso);
        final diff = dt.difference(DateTime.now()).inDays;
        if (diff <= 0) {
          timeScore = 30;
        } else if (diff == 1) {
          timeScore = 20;
        } else if (diff <= 7) {
          timeScore = 15;
        } else {
          timeScore = (30 / (diff + 1)).round().clamp(1, 30);
        }
      } catch (_) {}
    }

    // 3. User Rating (Max 30 points scaled from 0-100)
    final double ratingScore = (rating.clamp(0, 100) / 100.0) * 30.0;

    // Total Normalized Score (0 to 100)
    final int total = (sevScore + timeScore + ratingScore).round();
    return total.clamp(0, 100);
  }

  factory DashboardAlertDisplayItem.fromMap(Map<dynamic, dynamic> m) {
    final rawUrls = m['completed_photo_urls'];
    final List<String> parsedUrls = (rawUrls is List)
        ? rawUrls.map((e) => e.toString()).toList()
        : (m['completed_photo_url']?.toString().isNotEmpty == true
            ? [m['completed_photo_url'].toString()]
            : []);

    final int rating = int.tryParse(m['severity_rating']?.toString() ?? '') ?? 50;
    final String timeRange = m['due_time_range']?.toString() ?? 'today';
    final String dueDateStr = m['due_date']?.toString() ?? '';
    final String sev = m['severity']?.toString() ?? 'warning';
    final int score = int.tryParse(m['rank_score']?.toString() ?? '') ??
        calcRankScore(sev, rating, timeRange, dueDateStr);

    return DashboardAlertDisplayItem(
      id: m['id']?.toString() ?? '',
      alertTitle: m['alert_title']?.toString() ?? '',
      message: m['message']?.toString() ?? '',
      op: m['op']?.toString() ?? '',
      severity: sev,
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
      readingId: m['reading_id']?.toString() ?? '',
      ifThen: m['if_then']?.toString() ?? '',
      completedDescription: m['completed_description']?.toString() ?? '',
      completedPhotoUrl: m['completed_photo_url']?.toString() ?? '',
      completedPhotoUrls: parsedUrls,
      rankScore: score,
      severityRating: rating,
      dueTimeRange: timeRange,
      dueDate: dueDateStr,
    );
  }
}

class AssetFolderGroup {
  final String tankId;
  final String tankName;
  final String tankCode;
  final List<DashboardAlertDisplayItem> alerts;
  final int alertCount;

  AssetFolderGroup({
    required this.tankId,
    required this.tankName,
    required this.tankCode,
    required this.alerts,
    required this.alertCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'tank_id': tankId,
      'tank_name': tankName,
      'tank_code': tankCode,
      'alerts': alerts.map((a) => a.toMap()).toList(),
      'alert_count': alertCount,
    };
  }

  factory AssetFolderGroup.fromMap(Map<dynamic, dynamic> m) {
    final rawAlerts = m['alerts'] as List? ?? [];
    return AssetFolderGroup(
      tankId: m['tank_id']?.toString() ?? '',
      tankName: m['tank_name']?.toString() ?? '',
      tankCode: m['tank_code']?.toString() ?? '',
      alerts: rawAlerts
          .map((a) => DashboardAlertDisplayItem.fromMap(Map<dynamic, dynamic>.from(a as Map)))
          .toList(),
      alertCount: m['alert_count'] as int? ?? rawAlerts.length,
    );
  }
}

class AlertFolderGroup {
  final String paramLabel;
  final List<AssetFolderGroup> assets;
  final int totalAlerts;
  final int totalAssets;

  AlertFolderGroup({
    required this.paramLabel,
    required this.assets,
    required this.totalAlerts,
    required this.totalAssets,
  });

  Map<String, dynamic> toMap() {
    return {
      'param_label': paramLabel,
      'assets': assets.map((a) => a.toMap()).toList(),
      'total_alerts': totalAlerts,
      'total_assets': totalAssets,
    };
  }

  factory AlertFolderGroup.fromMap(Map<dynamic, dynamic> m) {
    final rawAssets = m['assets'] as List? ?? [];
    return AlertFolderGroup(
      paramLabel: m['param_label']?.toString() ?? '',
      assets: rawAssets
          .map((a) => AssetFolderGroup.fromMap(Map<dynamic, dynamic>.from(a as Map)))
          .toList(),
      totalAlerts: m['total_alerts'] as int? ?? 0,
      totalAssets: m['total_assets'] as int? ?? 0,
    );
  }
}
