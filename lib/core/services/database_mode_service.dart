import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseModeService {
  static const _prefKey = 'db_mode_development';
  static const _clientScopeKey = 'db_client_scope';
  static const _devRoot = 'testDB';

  static final ValueNotifier<bool> isDevelopment = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> activeClientId =
      ValueNotifier<String?>(null);

  static const Set<String> _globalPaths = {
    'users',
    'clients',
  };

  static const Set<String> _scopedPaths = {
    'Previouscapture',
    'tanks',
    'tank_tree',
    'readings',
    'alerts',
    'completed_tasks',
    'admin_audit_logs',
    'alerts_full',
    'violations',
    'dashboard_stats',
    'reading_feedback',
    'sync_logs',
    'settings',
  };

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isDevelopment.value = prefs.getBool(_prefKey) ?? false;
    final cid = prefs.getString(_clientScopeKey);
    activeClientId.value = (cid == null || cid.trim().isEmpty) ? null : cid;
  }

  static Future<void> setDevelopment(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    isDevelopment.value = enabled;
  }

  static Future<void> toggle() => setDevelopment(!isDevelopment.value);

  static Future<void> setClientScope(String? clientId) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized =
        (clientId == null || clientId.trim().isEmpty) ? null : clientId.trim();
    activeClientId.value = normalized;
    if (normalized == null) {
      await prefs.remove(_clientScopeKey);
    } else {
      await prefs.setString(_clientScopeKey, normalized);
    }
  }

  static String path(String rawPath) {
    final normalized = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
    var resolved = normalized;

    if (resolved.isNotEmpty) {
      final head = resolved.split('/').first;
      if (!_globalPaths.contains(head) &&
          _scopedPaths.contains(head) &&
          activeClientId.value != null) {
        resolved = '${activeClientId.value}/$resolved';
      }
    }

    if (!isDevelopment.value) return resolved;
    if (resolved.isEmpty) return _devRoot;
    return '$_devRoot/$resolved';
  }

  static DatabaseReference ref([String? rawPath]) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return isDevelopment.value
          ? FirebaseDatabase.instance.ref(_devRoot)
          : FirebaseDatabase.instance.ref();
    }
    return FirebaseDatabase.instance.ref(path(rawPath));
  }
}
