part of '../reading_entry_screen.dart';

class _ManualCaptureEntry {
  String? selectedParamId;
  File? capturedImage;
  String? uploadedUrl;
  bool uploading = false;

  _ManualCaptureEntry({this.selectedParamId, this.capturedImage});
}

// ─────────────────────────────────────────────────────────────────────────────
// ReadingEntryScreen
// ─────────────────────────────────────────────────────────────────────────────
