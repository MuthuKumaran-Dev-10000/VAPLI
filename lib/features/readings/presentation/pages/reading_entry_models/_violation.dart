part of '../reading_entry_screen.dart';

class _Violation {
  final String constraintId;
  final String message;
  final String alertTitle;
  final String severity;
  final bool blockSubmission;
  final bool captureImageOnViolation;
  final bool playSoundOnViolation;
  final bool showDashboardAlert;
  final bool storeHistory;

  _Violation({
    required this.constraintId,
    required this.message,
    required this.alertTitle,
    required this.severity,
    required this.blockSubmission,
    required this.captureImageOnViolation,
    required this.playSoundOnViolation,
    required this.showDashboardAlert,
    required this.storeHistory,
  });
}

