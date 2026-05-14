import 'package:flutter/material.dart';

class AppColors {
  // Main backgrounds
  static const background = Color(0xFF0C0D0F);

  static const surface = Color(0xFF141618);

  // App bars / headers
  static const topBar = Color(0xFF1A1C20);

  // Primary action
  // Copper (oil / machinery)
  static const primary = Color(0xFFCB8C3E);

  // Accent / live data
  // Teal
  static const secondary = Color(0xFF1ABCBD);

  // States
  static const success = Color(0xFF22C55E);

  static const error = Color(0xFFEF4444);

  static const warning = Color(0xFFF59E0B);

  static const disabled = Color(0xFF484C57);

  // Text
  static const textPrimary = Color(0xFFF0EEE9);

  static const textSecondary = Color(0xFF8A8F9C);

  // Extra (for borders/cards)
  static const border = Color(0xFF252830);

  static const borderHover = Color(0xFF32363F);

  // Optional darker copper
  static const primaryDark = Color(0xFF8A5A1E);
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
