import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseModeService {
  static const _prefKey = 'db_mode_development';
  static const _devRoot = 'testDB';

  static final ValueNotifier<bool> isDevelopment = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isDevelopment.value = prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setDevelopment(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    isDevelopment.value = enabled;
  }

  static Future<void> toggle() => setDevelopment(!isDevelopment.value);

  static String path(String rawPath) {
    final normalized = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
    if (!isDevelopment.value) return normalized;
    if (normalized.isEmpty) return _devRoot;
    return '$_devRoot/$normalized';
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

