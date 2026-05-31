part of '../reading_entry_screen.dart';

class _AutofillResult {
  final double? value;
  final String? errorMessage;       // layman-friendly
  final String? exceptionName;      // technical name
  final bool hasError;

  const _AutofillResult.value(this.value)
      : errorMessage = null,
        exceptionName = null,
        hasError = false;

  const _AutofillResult.error(this.errorMessage, this.exceptionName)
      : value = null,
        hasError = true;
}

// ── Data classes ──────────────────────────────────────────────────────────────
