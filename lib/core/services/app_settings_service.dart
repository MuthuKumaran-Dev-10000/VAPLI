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
}

