import 'package:flutter/material.dart';

class AppColors {
  // Industrial enterprise palette
  static const background = Color(0xFF0B1220); // deep slate navy
  static const surface = Color(0xFF111827); // industrial navy
  static const topBar = Color(0xFF1F2937); // gunmetal
  static const primary = Color(0xFFF97316); // safety orange
  static const secondary = Color(0xFF22D3EE); // cyan highlight

  // States
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const disabled = Color(0xFF484C57);

  // Text
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);

  // Extra (for borders/cards)
  static const border = Color(0xFF334155);
  static const borderHover = Color(0xFF475569);

  static const primaryDark = Color(0xFFC2410C);
}

class AppConstants {
  static const String appName = 'VAPLI';
  static const int sessionDurationMinutes = 60;

  // Firebase RTDB paths
  static const String usersPath = 'users';
  static const String tanksPath = 'tanks';
  static const String readingsPath = 'readings';
  static const String feedbackPath = 'reading_feedback';
  static const String syncLogsPath = 'sync_logs';
  static const String settingsPath = 'system_settings';
}
