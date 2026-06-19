import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';

class AppSettingsService {
  static const _sessionNode = '${AppConstants.settingsPath}/session';

  static Future<Duration?> getSessionTimeout() async {
    final snap = await DatabaseModeService.ref(_sessionNode).get();
    if (!snap.exists || snap.value == null) {
      return const Duration(minutes: AppConstants.sessionDurationMinutes);
    }
    final data = Map<String, dynamic>.from(snap.value as Map);
    final mode = (data['mode'] ?? 'minutes').toString();
    if (mode == 'none') return null;
    final minutes = (data['minutes'] as num?)?.toInt() ??
        AppConstants.sessionDurationMinutes;
    return Duration(minutes: minutes.clamp(1, 1440));
  }

  static Future<void> setSessionTimeout({
    required bool noTimeout,
    required int minutes,
  }) async {
    await DatabaseModeService.ref(_sessionNode).set({
      'mode': noTimeout ? 'none' : 'minutes',
      'minutes': minutes.clamp(1, 1440),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<Map<String, bool>> getDashboardDisplaySettings() async {
    try {
      final snap = await DatabaseModeService.ref('settings/dashboard_display').get();
      if (!snap.exists || snap.value == null) {
        return {
          'show_inspection_values': true,
          'show_completed_alerts': true,
          'show_active_alerts': true,
          'show_inspection_compliance': true,
        };
      }
      final data = Map<String, dynamic>.from(snap.value as Map);
      return {
        'show_inspection_values': data['show_inspection_values'] ?? true,
        'show_completed_alerts': data['show_completed_alerts'] ?? true,
        'show_active_alerts': data['show_active_alerts'] ?? true,
        'show_inspection_compliance': data['show_inspection_compliance'] ?? true,
      };
    } catch (_) {
      return {
        'show_inspection_values': true,
        'show_completed_alerts': true,
        'show_active_alerts': true,
        'show_inspection_compliance': true,
      };
    }
  }

  static Future<void> setDashboardDisplaySettings({
    required bool showInspectionValues,
    required bool showCompletedAlerts,
    required bool showActiveAlerts,
    required bool showInspectionCompliance,
  }) async {
    await DatabaseModeService.ref('settings/dashboard_display').set({
      'show_inspection_values': showInspectionValues,
      'show_completed_alerts': showCompletedAlerts,
      'show_active_alerts': showActiveAlerts,
      'show_inspection_compliance': showInspectionCompliance,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}

