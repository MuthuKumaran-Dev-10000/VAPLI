import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/user_model.dart';
import '../constants/app_constants.dart';

class SessionManager {
  static const _sessionKey = 'active_session';
  static const _sessionExpiry = 'session_expiry';

  static Future<void> saveSession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    final expiry = DateTime.now()
        .add(const Duration(minutes: AppConstants.sessionDurationMinutes))
        .toIso8601String();
    await prefs.setString(_sessionKey, jsonEncode(user.toMap()));
    await prefs.setString(_sessionExpiry, expiry);
  }

  static Future<bool> isSessionValid() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryStr = prefs.getString(_sessionExpiry);
    final sessionStr = prefs.getString(_sessionKey);
    if (expiryStr == null || sessionStr == null) return false;
    final expiry = DateTime.parse(expiryStr);
    return DateTime.now().isBefore(expiry);
  }

  static Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionStr = prefs.getString(_sessionKey);
    if (sessionStr == null) return null;
    final valid = await isSessionValid();
    if (!valid) return null;
    return UserModel.fromMap(jsonDecode(sessionStr));
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_sessionExpiry);
  }

  /// Refresh session (reset 1hr timer)
  static Future<void> refreshSession() async {
    final user = await getCurrentUser();
    if (user != null) await saveSession(user);
  }
}
