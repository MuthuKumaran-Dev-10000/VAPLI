part of '../dashboard_tab.dart';

class _CompletedTask {
  final String alertId;
  final String completedAt;
  final String completedBy;
  final _AlertModel alert;

  _CompletedTask({
    required this.alertId,
    required this.completedAt,
    required this.completedBy,
    required this.alert,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Severity helpers
// ─────────────────────────────────────────────────────────────────────────────
Color _sevColor(String s) {
  switch (s) {
    case 'critical':
      return _kDanger;
    case 'warning':
      return _kWarn;
    case 'info':
      return _kInfo;
    default:
      return _kWarn;
  }
}

IconData _sevIcon(String s) {
  switch (s) {
    case 'critical':
      return Icons.dangerous_rounded;
    case 'warning':
      return Icons.warning_amber_rounded;
    case 'info':
      return Icons.info_outline_rounded;
    default:
      return Icons.warning_amber_rounded;
  }
}

int _sevOrder(String s) {
  switch (s) {
    case 'critical':
      return 0;
    case 'warning':
      return 1;
    case 'info':
      return 2;
    default:
      return 3;
  }
}

String _fmtTs(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  } catch (_) {
    return iso ?? '—';
  }
}

String _fmtTsShort(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('HH:mm').format(dt);
  } catch (_) {
    return iso ?? '—';
  }
}

bool _isToday(String? iso) {
  if (iso == null || iso.isEmpty) return false;
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter enum
// ─────────────────────────────────────────────────────────────────────────────
