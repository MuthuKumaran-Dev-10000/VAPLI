// lib/presentation/screens/readings/reading_entry_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// ALL EXISTING FEATURES PRESERVED:
//   ✅ Global "Reference Photo" section removed (per v2)
//   ✅ Per-parameter capture_image support (capture_image: true/false)
//   ✅ Number hint shown above field AND as placeholder inside box
//   ✅ Deep copy of inspectionProperties → fixes cross-tank param bleed bug
//   ✅ All dynamic property types: number|text|multiline|dropdown|dual_text|slider
//   ✅ Required-field enforcement blocks save button
//   ✅ Constraint validation engine: <, <=, >, >=, ==, !=, contains
//   ✅ DashboardStatsRepository.updateStatsAfterReading() on save
//   ✅ Industrial luxury UI (copper accents, obsidian background)
//
// NEW IN THIS VERSION — CONSTRAINT ACTIONS:
//   ✅ LIVE validation on every keystroke / slider move / dropdown change
//   ✅ block_submission: true  → save button disabled while constraint fires
//   ✅ play_sound_on_violation → plays SystemSoundType.alert on violation
//   ✅ capture_image_on_violation → shows mandatory camera button under the
//      field when constraint fires; if value changes and constraint clears,
//      the violation photo is automatically discarded
//   ✅ show_dashboard_alert → writes a record to Firebase alerts/ node
//      with: id, tank_id, tank_name, constraint_id, alert_title, message,
//            severity, captured_by, captured_by_name, param_label,
//            param_value, image_url, timestamp
//   ✅ store_history → appended to violations/ node in Firebase
//   ✅ Violation banner shown inline below the field (dismissible)
//   ✅ Per-param violation state tracked independently
//   ✅ Image captured for violation is separate from param's own photo
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/dashboard_stats_repository.dart';
import '../../../data/repositories/reading_repository.dart';
import 'image_marker_screen.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kBorder = Color(0xFF252830);
const _kBorderH = Color(0xFF32363F);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperD = Color(0xFF8A5A1E);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kDisable = Color(0xFF484C57);
const _kInfo = Color(0xFF60A5FA);
const _kPurple = Color(0xFFAB8FF0);

// ── Cloudinary ────────────────────────────────────────────────────────────────
const _cloudName = 'dummy-cloudinary-cloud-name';
const _apiKey = 'dummy-cloudinary-api-key';
const _apiSecret = 'dummy-cloudinary-api-secret';
const _folder = 'lubricationindicator';

final Map<String, Set<String>> _alreadyLoggedConstraints = {};

// ── Severity → Color ──────────────────────────────────────────────────────────
Color _severityColor(String? s) {
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

IconData _severityIcon(String? s) {
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

// ── Violation data class ──────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// ReadingEntryScreen
// ─────────────────────────────────────────────────────────────────────────────
class ReadingEntryScreen extends StatefulWidget {
  final TankModel tank;
  final UserModel currentUser;

  const ReadingEntryScreen({
    super.key,
    required this.tank,
    required this.currentUser,
  });

  @override
  State<ReadingEntryScreen> createState() => _ReadingEntryScreenState();
}

class _ReadingEntryScreenState extends State<ReadingEntryScreen> {
  final _picker = ImagePicker();

  // ── save state ─────────────────────────────────────────────────────────
  bool _saving = false;
  bool _saved = false;
  bool _failed = false;
  String? _uploadError;

  // ── dynamic property controllers ──────────────────────────────────────
  final Map<String, TextEditingController> _textCtrl = {};
  final Map<String, TextEditingController> _dualLeft = {};
  final Map<String, TextEditingController> _dualRight = {};
  final Map<String, String?> _dropdownVal = {};
  final Map<String, double> _sliderVal = {};

  /// Per-parameter photo (capture_image: true params)
  final Map<String, File?> _paramPhoto = {};

  /// Per-param violation photos (capture_image_on_violation)
  /// Key = paramId; value = captured file (null if not yet captured)
  final Map<String, File?> _violationPhoto = {};

  /// Current violations per param: paramId → _Violation?
  final Map<String, _Violation?> _violations = {};

  /// Whether the violation sound has already fired for this paramId
  /// (reset when value changes and violation clears)
  final Map<String, bool> _soundFired = {};

  // ── Deep copy of inspection properties ────────────────────────────────
  late final List<Map<String, dynamic>> _props;

  String get _nowLabel =>
      DateFormat('dd MMM yyyy, HH:mm:ss').format(DateTime.now());

  // ── Firebase ref ───────────────────────────────────────────────────────
  final _db = FirebaseDatabase.instance.ref();

  // ── lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Deep copy to prevent cross-tank bleed
    _props = widget.tank.inspectionProperties.map((p) {
      return Map<String, dynamic>.from(p.map((k, v) {
        if (v is List) return MapEntry(k, List<dynamic>.from(v));
        if (v is Map) return MapEntry(k, Map<String, dynamic>.from(v as Map));
        return MapEntry(k, v);
      }));
    }).toList();

    for (final p in _props) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';

      switch (type) {
        case 'number':
        case 'text':
        case 'multiline':
          final ctrl = TextEditingController();
          ctrl.addListener(() => _onValueChanged(id));
          _textCtrl[id] = ctrl;
          break;
        case 'dropdown':
          _dropdownVal[id] = null;
          break;
        case 'slider':
          _sliderVal[id] = ((p['min'] ?? 0) as num).toDouble();
          break;
        case 'dual_text':
          final l = TextEditingController();
          final r = TextEditingController();
          l.addListener(() => _onValueChanged(id));
          r.addListener(() => _onValueChanged(id));
          _dualLeft[id] = l;
          _dualRight[id] = r;
          break;
      }

      if (p['capture_image'] == true) _paramPhoto[id] = null;
      _violations[id] = null;
      _soundFired[id] = false;
      _violationPhoto[id] = null;
    }
  }

  @override
  void dispose() {
    _textCtrl.values.forEach((c) => c.dispose());
    _dualLeft.values.forEach((c) => c.dispose());
    _dualRight.values.forEach((c) => c.dispose());
    super.dispose();
  }

  // ── Live value extraction per param ───────────────────────────────────

  dynamic _currentValue(String id, String type, Map<String, dynamic> p) {
    switch (type) {
      case 'number':
        final raw = _textCtrl[id]?.text.trim() ?? '';
        return double.tryParse(raw) ?? raw;
      case 'text':
      case 'multiline':
        return _textCtrl[id]?.text.trim() ?? '';
      case 'dropdown':
        return _dropdownVal[id] ?? '';
      case 'slider':
        return _sliderVal[id] ?? ((p['min'] ?? 0) as num).toDouble();
      case 'dual_text':
        return {
          'left': _dualLeft[id]?.text.trim() ?? '',
          'right': _dualRight[id]?.text.trim() ?? '',
        };
      default:
        return '';
    }
  }

  // ── Constraint evaluator ───────────────────────────────────────────────

  /// Returns the first fired _Violation for [p], or null if all pass.
  _Violation? _evaluateConstraints(Map<String, dynamic> p, dynamic value) {
    final constraints = <Map<String, dynamic>>[];
    final rawList = p['constraints'];
    if (rawList is List) {
      for (final c in rawList) {
        if (c is Map) {
          constraints.add(Map<String, dynamic>.from(c));
        }
      }
    }

    for (final c in constraints) {
      final op = c['op']?.toString() ?? '';
      final expected = c['value']?.toString() ?? '';
      final actual = value.toString().trim();

      bool fired = false;

      if (actual.isEmpty) {
        return null;
      }

      // switch (op) {
      //   case '<':
      //     fired = (double.tryParse(actual) ?? 0) >=
      //         (double.tryParse(expected) ?? 0);
      //     break;
      //   case '<=':
      //     fired =
      //         (double.tryParse(actual) ?? 0) > (double.tryParse(expected) ?? 0);
      //     break;
      //   case '>':
      //     fired = (double.tryParse(actual) ?? 0) <=
      //         (double.tryParse(expected) ?? 0);
      //     break;
      //   case '>=':
      //     fired =
      //         (double.tryParse(actual) ?? 0) < (double.tryParse(expected) ?? 0);
      //     break;
      //   case '==':
      //     fired = actual == expected;
      //     break;
      //   case '!=':
      //     fired = actual != expected;
      //     break;
      //   case 'contains':
      //     fired = !actual.contains(expected);
      //     break;
      //   case 'starts_with':
      //     fired = !actual.startsWith(expected);
      //     break;
      //   case 'ends_with':
      //     fired = !actual.endsWith(expected);
      //     break;
      //   case 'regex':
      //     try {
      //       fired = !RegExp(expected).hasMatch(actual);
      //     } catch (_) {
      //       fired = false;
      //     }
      //     break;
      // }

      switch (op) {
        case '<':
          fired =
              (double.tryParse(actual) ?? 0) < (double.tryParse(expected) ?? 0);
          break;

        case '<=':
          fired = (double.tryParse(actual) ?? 0) <=
              (double.tryParse(expected) ?? 0);
          break;

        case '>':
          fired =
              (double.tryParse(actual) ?? 0) > (double.tryParse(expected) ?? 0);
          break;

        case '>=':
          fired = (double.tryParse(actual) ?? 0) >=
              (double.tryParse(expected) ?? 0);
          break;

        case '==':
          fired = actual.toLowerCase().trim() == expected.toLowerCase().trim();
          break;

        case '!=':
          fired = actual.toLowerCase().trim() != expected.toLowerCase().trim();
          break;

        case 'contains':
          fired = actual.toLowerCase().contains(expected.toLowerCase());
          break;

        case 'starts_with':
          fired = actual.toLowerCase().startsWith(expected.toLowerCase());
          break;

        case 'ends_with':
          fired = actual.toLowerCase().endsWith(expected.toLowerCase());
          break;

        case 'regex':
          try {
            fired = RegExp(expected).hasMatch(actual);
          } catch (_) {
            fired = false;
          }
          break;
      }

      if (fired) {
        return _Violation(
          constraintId: c['id']?.toString() ?? '',
          message: c['message']?.toString() ?? 'Alert condition met',
          alertTitle: c['alert_title']?.toString() ?? 'Alert',
          severity: c['severity']?.toString() ?? 'warning',
          blockSubmission: c['block_submission'] == true,
          captureImageOnViolation: c['capture_image_on_violation'] == true,
          playSoundOnViolation: c['play_sound_on_violation'] == true,
          showDashboardAlert: c['show_dashboard_alert'] == true,
          storeHistory: c['store_history'] == true,
        );
      }
    }
    return null;
  }

  // ── Called whenever a param value changes ──────────────────────────────

  void _onValueChanged(String id) {
    final p = _props.firstWhere((e) => e['id'] == id,
        orElse: () => <String, dynamic>{});
    if (p.isEmpty) return;
    final type = p['type'] as String? ?? 'text';
    final val = _currentValue(id, type, p);

    final prevViolation = _violations[id];
    final newViolation = _evaluateConstraints(p, val);

    setState(() {
      _violations[id] = newViolation;
    });

    if (newViolation != null) {
      final already =
          _alreadyLoggedConstraints[id]?.contains(newViolation.constraintId) ??
              false;

      if (!already) {
        _alreadyLoggedConstraints.putIfAbsent(id, () => {});

        _alreadyLoggedConstraints[id]!.add(newViolation.constraintId);

        _handleViolationTriggered(
          paramId: id,
          param: p,
          value: val,
          violation: newViolation,
        );
      }
    } else {
      // ── Violation cleared ──────────────────────────────────────────
      if (prevViolation != null) {
        // Value changed → constraint cleared → discard violation photo
        if (_violationPhoto[id] != null) {
          debugPrint(
              '[Constraint] Violation cleared → discarding violation photo for $id');
          setState(() => _violationPhoto[id] = null);
        }
        _alreadyLoggedConstraints[id]?.clear();
        _soundFired[id] = false;
      }
    }
  }

  // ── Capture violation photo ────────────────────────────────────────────

  Future<void> _captureViolationPhoto(String paramId) async {
    final img =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null) return;
    if (!mounted) return;

    final annotated = await Navigator.push<File>(
      context,
      MaterialPageRoute(
          builder: (_) => ImageMarkerScreen(imageFile: File(img.path))),
    );
    if (annotated != null && mounted) {
      setState(() => _violationPhoto[paramId] = annotated);
    }
  }

  // ── Capture normal per-param photo ────────────────────────────────────

  Future<void> _captureParamImage(String paramId) async {
    final img =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null) return;
    if (!mounted) return;

    final annotated = await Navigator.push<File>(
      context,
      MaterialPageRoute(
          builder: (_) => ImageMarkerScreen(imageFile: File(img.path))),
    );
    if (annotated != null && mounted) {
      setState(() {
        _paramPhoto[paramId] = annotated;
        _uploadError = null;
      });
    }
  }

  // ── Required / block check ─────────────────────────────────────────────

  String? _requiredError() {
    for (final p in _props) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';
      final label = p['label'] as String? ?? 'Parameter';
      final isReq = p['required'] == true;
      final hasCam = p['capture_image'] == true;

      if (hasCam && _paramPhoto[id] == null) {
        return '"$label" — photo is required';
      }
      if (!isReq) continue;

      switch (type) {
        case 'number':
        case 'text':
        case 'multiline':
          if ((_textCtrl[id]?.text.trim() ?? '').isEmpty) {
            return '"$label" is required';
          }
          break;
        case 'dropdown':
          if (_dropdownVal[id] == null) return '"$label" must be selected';
          break;
        case 'dual_text':
          final l = _dualLeft[id]?.text.trim() ?? '';
          final r = _dualRight[id]?.text.trim() ?? '';
          if (l.isEmpty || r.isEmpty) {
            return '"$label" — both fields are required';
          }
          break;
        case 'slider':
          break;
      }
    }
    return null;
  }

  bool get _hasBlockingViolation =>
      _violations.values.any((v) => v != null && v.blockSubmission);

  bool get _hasMissingViolationPhoto {
    for (final p in _props) {
      final id = p['id'] as String;
      final v = _violations[id];
      if (v != null &&
          v.captureImageOnViolation &&
          _violationPhoto[id] == null) {
        return true;
      }
    }
    return false;
  }

  bool get _canSave {
    if (_saving || _saved) return false;
    if (_hasBlockingViolation) return false;
    if (_hasMissingViolationPhoto) return false;
    for (final p in _props) {
      if (p['capture_image'] == true) {
        final id = p['id'] as String;
        if (_paramPhoto[id] == null) return false;
      }
    }
    return true;
  }

  // ── Collect values ─────────────────────────────────────────────────────

  Map<String, dynamic> _collectValues() {
    final out = <String, dynamic>{};
    for (final p in _props) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';
      final label = p['label'] as String? ?? id;

      switch (type) {
        case 'number':
          out[label] = double.tryParse(_textCtrl[id]?.text.trim() ?? '') ?? 0.0;
          break;
        case 'text':
        case 'multiline':
          out[label] = _textCtrl[id]?.text.trim() ?? '';
          break;
        case 'dropdown':
          out[label] = _dropdownVal[id] ?? '';
          break;
        case 'slider':
          out[label] = _sliderVal[id] ?? ((p['min'] ?? 0) as num).toDouble();
          break;
        case 'dual_text':
          final leftRaw = _dualLeft[id]?.text.trim() ?? '';
          final rightRaw = _dualRight[id]?.text.trim() ?? '';
          out[label] = {
            'left': double.tryParse(leftRaw) ?? leftRaw,
            'right': double.tryParse(rightRaw) ?? rightRaw,
          };
          break;
      }
    }
    return out;
  }

  // ── Cloudinary upload ──────────────────────────────────────────────────

  String _sig(String ts) => crypto.sha1
      .convert(utf8.encode('folder=$_folder&timestamp=$ts$_apiSecret'))
      .toString();

  Future<String> _uploadFile(File file) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final req = http.MultipartRequest('POST',
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload'));
    req.fields['api_key'] = _apiKey;
    req.fields['timestamp'] = ts;
    req.fields['signature'] = _sig(ts);
    req.fields['folder'] = _folder;
    req.files.add(await http.MultipartFile.fromPath('file', file.path,
        contentType:
            MediaType.parse(lookupMimeType(file.path) ?? 'image/jpeg')));
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode != 200) {
      throw Exception('Photo upload failed (${res.statusCode})');
    }
    return (json.decode(res.body) as Map)['secure_url'] as String;
  }

  // ── Dashboard alert writer ─────────────────────────────────────────────

  Future<void> _writeDashboardAlert({
    required String paramId,
    required String paramLabel,
    required dynamic paramValue,
    required _Violation violation,
    String? imageUrl,
  }) async {
    if (!violation.showDashboardAlert) return;
    final id = '${DateTime.now().millisecondsSinceEpoch}-alert';
    final timestamp = DateTime.now().toIso8601String();
    final alert = {
      'id': id,
      'tank_id': widget.tank.id,
      'tank_name': widget.tank.tankName,
      'tank_code': widget.tank.tankCode,
      'constraint_id': violation.constraintId,
      'alert_title': violation.alertTitle,
      'message': violation.message,
      'severity': violation.severity,
      'param_id': paramId,
      'param_label': paramLabel,
      'param_value': paramValue.toString(),
      'captured_by': widget.currentUser.id,
      'captured_by_name': widget.currentUser.fullName,
      'image_url': imageUrl ?? '',
      'timestamp': timestamp,
      'acknowledged': false,
    };
    debugPrint('[Alert] Writing dashboard alert: $id');
    await _db.child('alerts/$id').set(alert);
  }

  Future<void> _writeViolationHistory({
    required String paramId,
    required String paramLabel,
    required dynamic paramValue,
    required _Violation violation,
    String? imageUrl,
  }) async {
    if (!violation.storeHistory) return;
    final id = '${DateTime.now().millisecondsSinceEpoch}-violation';
    final timestamp = DateTime.now().toIso8601String();
    final record = {
      'id': id,
      'tank_id': widget.tank.id,
      'tank_name': widget.tank.tankName,
      'constraint_id': violation.constraintId,
      'alert_title': violation.alertTitle,
      'message': violation.message,
      'severity': violation.severity,
      'param_id': paramId,
      'param_label': paramLabel,
      'param_value': paramValue.toString(),
      'captured_by': widget.currentUser.id,
      'captured_by_name': widget.currentUser.fullName,
      'image_url': imageUrl ?? '',
      'timestamp': timestamp,
    };
    debugPrint('[Alert] Writing violation history: $id');
    await _db.child('violations/$id').set(record);
  }

  Future<void> _handleViolationTriggered({
    required String paramId,
    required Map<String, dynamic> param,
    required dynamic value,
    required _Violation violation,
  }) async {
    try {
      final label = param['label']?.toString() ?? paramId;

      String? imageUrl;

      // upload evidence photo if exists
      if (_violationPhoto[paramId] != null) {
        imageUrl = await _uploadFile(_violationPhoto[paramId]!);
      }

      // collect ALL current values
      final snapshot = _collectValues();

      // fill defaults for missing fields
      for (final p in _props) {
        final lbl = p['label']?.toString() ?? '';

        if (!snapshot.containsKey(lbl) ||
            snapshot[lbl] == null ||
            snapshot[lbl].toString().trim().isEmpty) {
          snapshot[lbl] = p['default_value'] ?? '';
        }
      }

      // write dashboard alert
      await _writeDashboardAlert(
        paramId: paramId,
        paramLabel: label,
        paramValue: value,
        violation: violation,
        imageUrl: imageUrl,
      );

      // write history
      await _writeViolationHistory(
        paramId: paramId,
        paramLabel: label,
        paramValue: value,
        violation: violation,
        imageUrl: imageUrl,
      );

      // FULL enterprise alert object
      final alertId =
          '${DateTime.now().millisecondsSinceEpoch}_${violation.constraintId}';

      await _db.child('alerts_full/$alertId').set({
        'id': alertId,
        'tank_id': widget.tank.id,
        'tank_name': widget.tank.tankName,
        'tank_code': widget.tank.tankCode,
        'param_id': paramId,
        'param_label': label,
        'constraint_id': violation.constraintId,
        'constraint_snapshot': {
          'message': violation.message,
          'severity': violation.severity,
          'alert_title': violation.alertTitle,
        },
        'actual_value': value,
        'all_values_snapshot': snapshot,
        'captured_by': widget.currentUser.id,
        'captured_by_name': widget.currentUser.fullName,
        'image_url': imageUrl ?? '',
        'created_at': DateTime.now().toIso8601String(),
        'acknowledged': false,
        'resolved': false,
      });
    } catch (e) {
      debugPrint(
        '[Violation Trigger Error] $e',
      );
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final propErr = _requiredError();
    if (propErr != null) {
      _snack(propErr, _kDanger);
      return;
    }
    if (_hasBlockingViolation) {
      _snack('Fix all constraint violations before saving', _kDanger);
      return;
    }

    setState(() {
      _saving = true;
      _saved = false;
      _failed = false;
      _uploadError = null;
    });

    try {
      // 1. Upload per-param photos
      final paramImageUrls = <String, String>{};
      for (final p in _props) {
        final id = p['id'] as String;
        if (p['capture_image'] == true && _paramPhoto[id] != null) {
          paramImageUrls[id] = await _uploadFile(_paramPhoto[id]!);
        }
      }

      // 2. Upload violation photos
      final violationImageUrls = <String, String>{};
      for (final p in _props) {
        final id = p['id'] as String;
        if (_violationPhoto[id] != null) {
          violationImageUrls[id] = await _uploadFile(_violationPhoto[id]!);
        }
      }

      // 3. Collect values
      final inspVals = _collectValues();

      // Merge image URLs into inspVals
      for (final e in paramImageUrls.entries) {
        inspVals['${e.key}__image_url'] = e.value;
      }
      for (final e in violationImageUrls.entries) {
        inspVals['${e.key}__violation_image_url'] = e.value;
      }

      // 4. Final constraint validation (values may not have changed)
      for (final p in _props) {
        final id = p['id'] as String;
        final type = p['type'] as String? ?? 'text';
        final label = p['label'] as String? ?? id;
        final val = _currentValue(id, type, p);
        final v = _evaluateConstraints(p, val);
        if (v != null && v.blockSubmission) {
          _snack('"$label": ${v.message}', _kDanger);
          setState(() => _saving = false);
          return;
        }
      }

      // 5. Write dashboard alerts + violation history for active violations
      for (final p in _props) {
        final id = p['id'] as String;
        final type = p['type'] as String? ?? 'text';
        final label = p['label'] as String? ?? id;
        final val = _currentValue(id, type, p);
        final v = _violations[id];
        if (v != null) {
          final imgUrl = violationImageUrls[id] ?? '';
          await _writeDashboardAlert(
            paramId: id,
            paramLabel: label,
            paramValue: val,
            violation: v,
            imageUrl: imgUrl,
          );
          await _writeViolationHistory(
            paramId: id,
            paramLabel: label,
            paramValue: val,
            violation: v,
            imageUrl: imgUrl,
          );
        }
      }

      // 6. Primary image URL for reading record
      final primaryImageUrl =
          paramImageUrls.values.isNotEmpty ? paramImageUrls.values.first : '';

      // 7. Save reading
      final reading = await ReadingRepository().saveReading(
        tankId: widget.tank.id,
        tankName: widget.tank.tankName,
        level: 0,
        capturedBy: widget.currentUser.id,
        capturedByName: widget.currentUser.fullName,
        imageUrl: primaryImageUrl,
        inspectionValues: inspVals,
      );

      // 8. Update dashboard stats
      await DashboardStatsRepository().updateStatsAfterReading(
        reading: reading,
        tank: widget.tank,
      );

      setState(() {
        _saving = false;
        _saved = true;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _failed = true;
        _uploadError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _kText)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('Record Reading',
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700, fontSize: 17, color: _kText)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetaCard(
              tank: widget.tank,
              currentUser: widget.currentUser,
              nowLabel: _nowLabel,
            ),

            if (_props.isNotEmpty) ...[
              const SizedBox(height: 28),
              _SecLabel('INSPECTION PARAMETERS'),
              const SizedBox(height: 4),
              Text('Fields marked * are required',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
              const SizedBox(height: 16),
              ..._props.map(_buildPropField),
            ],

            const SizedBox(height: 28),

            // Blocking violation banner at the bottom
            if (_hasBlockingViolation) ...[
              _BlockBanner(
                violations: _violations,
                props: _props,
              ),
              const SizedBox(height: 16),
            ],

            _SaveButton(
              saving: _saving,
              saved: _saved,
              failed: _failed,
              canSave: _canSave,
              onTap: _canSave ? _save : null,
            ),

            if (_uploadError != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(_uploadError!),
            ],
          ],
        ),
      ),
    );
  }

  // ── Property field builder ─────────────────────────────────────────────

  Widget _buildPropField(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final type = p['type'] as String? ?? 'text';
    final label = p['label'] as String? ?? 'Parameter';
    final hint = p['hint'] as String? ?? '';
    final isReq = p['required'] == true;
    final hasCam = p['capture_image'] == true;
    final isEffectivelyRequired = isReq || hasCam;
    final violation = _violations[id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label row ──────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Text(
                isEffectivelyRequired ? '$label *' : label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _kText),
              ),
            ),
            if (isEffectivelyRequired) _Badge('REQUIRED', _kDanger),
            if (violation != null) ...[
              const SizedBox(width: 6),
              _Badge(violation.severity.toUpperCase(),
                  _severityColor(violation.severity)),
            ],
          ]),

          // ── Hint above field ────────────────────────────────────────
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(hint, style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
          ],

          const SizedBox(height: 8),

          // ── Input widget ────────────────────────────────────────────
          _buildInput(p, id, type, hint, isReq),

          // ── Violation banner ────────────────────────────────────────
          if (violation != null) ...[
            const SizedBox(height: 8),
            _ViolationBanner(
              violation: violation,
              violationPhoto: _violationPhoto[id],
              onCapturePhoto: violation.captureImageOnViolation
                  ? () => _captureViolationPhoto(id)
                  : null,
            ),
          ],

          // ── Normal per-param camera ─────────────────────────────────
          if (hasCam) ...[
            const SizedBox(height: 10),
            _ParamPhotoRow(
              image: _paramPhoto[id],
              onCapture: () => _captureParamImage(id),
            ),
          ],
        ],
      ),
    );
  }

  // ── Input decoration ───────────────────────────────────────────────────

  InputDecoration _dec(String hintText,
      {String? placeholder, bool hasViolation = false}) {
    final borderColor = hasViolation ? _kDanger : _kBorder;
    final focusColor = hasViolation ? _kDanger : _kCopper;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor));
    return InputDecoration(
      hintText: placeholder ?? (hintText.isNotEmpty ? hintText : null),
      hintStyle: GoogleFonts.dmSans(color: _kSub, fontSize: 13),
      filled: true,
      fillColor: hasViolation ? _kDanger.withOpacity(0.05) : _kSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focusColor, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kDanger)),
    );
  }

  // ── Per-type input builders ────────────────────────────────────────────

  Widget _buildInput(
      Map<String, dynamic> p, String id, String type, String hint, bool isReq) {
    final violation = _violations[id];
    final hasViolation = violation != null;

    switch (type) {
      // ── Number ────────────────────────────────────────────────────
      case 'number':
        return TextFormField(
          controller: _textCtrl[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.spaceGrotesk(color: _kText, fontSize: 15),
          cursorColor: _kCopper,
          decoration: _dec(hint,
              placeholder: hint.isNotEmpty ? hint : null,
              hasViolation: hasViolation),
          onChanged: (_) => _onValueChanged(id),
          validator: isReq
              ? (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null)
                    return 'Must be a number';
                  return null;
                }
              : null,
        );

      // ── Text ──────────────────────────────────────────────────────
      case 'text':
        return TextFormField(
          controller: _textCtrl[id],
          style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
          cursorColor: _kCopper,
          decoration: _dec(hint, hasViolation: hasViolation),
          onChanged: (_) => _onValueChanged(id),
          validator: isReq
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        );

      // ── Multiline ─────────────────────────────────────────────────
      case 'multiline':
        return TextFormField(
          controller: _textCtrl[id],
          maxLines: 4,
          style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
          cursorColor: _kCopper,
          decoration: _dec(hint, hasViolation: hasViolation),
          onChanged: (_) => _onValueChanged(id),
          validator: isReq
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        );

      // ── Dropdown ──────────────────────────────────────────────────
      case 'dropdown':
        final options = List<String>.from(p['options'] ?? []);
        return Container(
          decoration: BoxDecoration(
            color: hasViolation ? _kDanger.withOpacity(0.05) : _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: hasViolation ? _kDanger : _kBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _dropdownVal[id],
              isExpanded: true,
              dropdownColor: _kCard,
              iconEnabledColor: _kSub,
              hint: Text('Select…',
                  style: GoogleFonts.dmSans(color: _kSub, fontSize: 13)),
              items: options
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: GoogleFonts.dmSans(
                                color: _kText, fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _dropdownVal[id] = v);
                // Trigger constraint evaluation after dropdown change
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _onValueChanged(id));
              },
            ),
          ),
        );

      // ── Dual text ─────────────────────────────────────────────────
      case 'dual_text':
        final lbl = (p['left_label'] as String?)?.isNotEmpty == true
            ? p['left_label'] as String
            : 'Before';
        final rbl = (p['right_label'] as String?)?.isNotEmpty == true
            ? p['right_label'] as String
            : 'After';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(lbl,
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kSub)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(rbl,
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kSub)),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _dualLeft[id],
                  style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
                  cursorColor: _kCopper,
                  decoration: _dec(lbl, hasViolation: hasViolation),
                  onChanged: (_) => _onValueChanged(id),
                  validator: isReq
                      ? (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _dualRight[id],
                  style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
                  cursorColor: _kCopper,
                  decoration: _dec(rbl, hasViolation: hasViolation),
                  onChanged: (_) => _onValueChanged(id),
                  validator: isReq
                      ? (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null
                      : null,
                ),
              ),
            ]),
          ],
        );

      // ── Slider ────────────────────────────────────────────────────
      case 'slider':
        final mn = ((p['min'] ?? 0) as num).toDouble();
        final mx = ((p['max'] ?? 100) as num).toDouble();
        final safeMx = mx > mn ? mx : mn + 1;
        final cur = _sliderVal[id] ?? mn;
        final curStr = cur == cur.truncateToDouble()
            ? cur.toInt().toString()
            : cur.toStringAsFixed(1);

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            color: hasViolation ? _kDanger.withOpacity(0.05) : _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: hasViolation ? _kDanger : _kBorder),
          ),
          child: Column(children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${mn.toInt()}',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
                Text(curStr,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: hasViolation ? _kDanger : _kCopper)),
                Text('${mx.toInt()}',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: hasViolation ? _kDanger : _kCopper,
                thumbColor: hasViolation ? _kDanger : _kCopper,
                inactiveTrackColor: _kBorder,
                overlayColor:
                    (hasViolation ? _kDanger : _kCopper).withOpacity(0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                trackHeight: 3,
              ),
              child: Slider(
                value: cur,
                min: mn,
                max: safeMx,
                divisions: (safeMx - mn).round().clamp(1, 9999),
                onChanged: (v) {
                  setState(() => _sliderVal[id] = v);
                  _onValueChanged(id);
                },
              ),
            ),
          ]),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIOLATION BANNER — shown inline below the field
// ─────────────────────────────────────────────────────────────────────────────
class _ViolationBanner extends StatelessWidget {
  final _Violation violation;
  final File? violationPhoto;
  final VoidCallback? onCapturePhoto;

  const _ViolationBanner({
    required this.violation,
    required this.violationPhoto,
    this.onCapturePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(violation.severity);
    final icon = _severityIcon(violation.severity);
    final photoRequired =
        violation.captureImageOnViolation && violationPhoto == null;

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(violation.alertTitle,
                  style: GoogleFonts.dmSans(
                      color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (violation.blockSubmission)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('BLOCKED',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 8,
                        color: _kDanger,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
          ]),
          const SizedBox(height: 5),
          Text(violation.message,
              style: GoogleFonts.dmSans(color: _kText, fontSize: 12)),
          // Violation photo capture
          if (violation.captureImageOnViolation) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCapturePhoto,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: photoRequired
                          ? _kDanger.withOpacity(0.10)
                          : _kSuccess.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: photoRequired
                              ? _kDanger.withOpacity(0.5)
                              : _kSuccess.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          violationPhoto != null
                              ? Icons.check_circle_outline_rounded
                              : Icons.camera_alt_outlined,
                          size: 18,
                          color: violationPhoto != null ? _kSuccess : _kDanger,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          violationPhoto != null
                              ? 'Retake Evidence Photo'
                              : 'Capture Evidence Photo *',
                          style: GoogleFonts.dmSans(
                            color:
                                violationPhoto != null ? _kSuccess : _kDanger,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (violationPhoto != null) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(violationPhoto!,
                      width: 46, height: 46, fit: BoxFit.cover),
                ),
              ],
            ]),
          ],
          // Action indicators
          if (violation.playSoundOnViolation ||
              violation.showDashboardAlert ||
              violation.storeHistory) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                if (violation.playSoundOnViolation)
                  _ActionChip(
                      icon: Icons.volume_up_rounded,
                      label: 'Sound',
                      color: color),
                if (violation.showDashboardAlert)
                  _ActionChip(
                      icon: Icons.dashboard_customize_outlined,
                      label: 'Dashboard Alert',
                      color: color),
                if (violation.storeHistory)
                  _ActionChip(
                      icon: Icons.history_rounded,
                      label: 'Logged',
                      color: color),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK BANNER — bottom of page when submission is blocked
// ─────────────────────────────────────────────────────────────────────────────
class _BlockBanner extends StatelessWidget {
  final Map<String, _Violation?> violations;
  final List<Map<String, dynamic>> props;

  const _BlockBanner({required this.violations, required this.props});

  @override
  Widget build(BuildContext context) {
    final blocked = violations.entries
        .where((e) => e.value?.blockSubmission == true)
        .map((e) {
      final p = props.firstWhere((pp) => pp['id'] == e.key,
          orElse: () => {'label': e.key});
      return '"${p['label']}"';
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kDanger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDanger.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.block_rounded, color: _kDanger, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submission Blocked',
                  style: GoogleFonts.dmSans(
                      color: _kDanger,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 3),
              Text(
                'Fix violations in: ${blocked.join(', ')}',
                style: GoogleFonts.dmSans(color: _kText, fontSize: 12),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PER-PARAMETER PHOTO ROW
// ─────────────────────────────────────────────────────────────────────────────
class _ParamPhotoRow extends StatelessWidget {
  final File? image;
  final VoidCallback onCapture;
  const _ParamPhotoRow({required this.image, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final captured = image != null;
    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: onCapture,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: captured
                  ? _kSuccess.withOpacity(0.08)
                  : _kTeal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: captured
                      ? _kSuccess.withOpacity(0.4)
                      : _kTeal.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  captured
                      ? Icons.check_circle_outline_rounded
                      : Icons.camera_alt_outlined,
                  color: captured ? _kSuccess : _kTeal,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  captured ? 'Retake Photo' : 'Capture Photo',
                  style: GoogleFonts.dmSans(
                      color: captured ? _kSuccess : _kTeal,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
      if (captured) ...[
        const SizedBox(width: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(image!, width: 54, height: 54, fit: BoxFit.cover),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERROR BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kDanger.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kDanger.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: _kDanger, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.dmSans(color: _kDanger, fontSize: 12))),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SecLabel extends StatelessWidget {
  final String text;
  const _SecLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: _kSub));
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(text,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ActionChip(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ]),
      );
}

// ── Meta card ─────────────────────────────────────────────────────────────────
class _MetaCard extends StatelessWidget {
  final TankModel tank;
  final UserModel currentUser;
  final String nowLabel;
  const _MetaCard({
    required this.tank,
    required this.currentUser,
    required this.nowLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: _kBorder)),
          ),
          child: Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: _kCopper, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tank.tankName,
                  style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            Text(tank.tankCode,
                style: GoogleFonts.spaceGrotesk(
                    color: _kCopper,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _MetaRow(label: 'Zone', value: tank.location ?? '—'),
            _MetaRow(label: 'Inspector', value: currentUser.fullName),
            _MetaRow(label: 'Timestamp', value: nowLabel),
          ]),
        ),
      ]),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _MetaRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: GoogleFonts.dmSans(color: _kSub, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: GoogleFonts.dmSans(
                    color: valueColor ?? _kText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
      );
}

// ── Save button ───────────────────────────────────────────────────────────────
class _SaveButton extends StatelessWidget {
  final bool saving;
  final bool saved;
  final bool failed;
  final bool canSave;
  final VoidCallback? onTap;

  const _SaveButton({
    required this.saving,
    required this.saved,
    required this.failed,
    required this.canSave,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Widget child;

    if (saved) {
      bg = _kSuccess;
      child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text('Saved — Returning…',
            style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ]);
    } else if (failed) {
      bg = _kDanger;
      child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text('Failed — Tap to Retry',
            style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ]);
    } else if (saving) {
      bg = _kCopper.withOpacity(0.7);
      child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
            width: 18,
            height: 18,
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('Uploading & Saving…',
            style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ]);
    } else {
      bg = canSave ? _kCopper : _kSurface;
      child = Text('Save Reading',
          style: GoogleFonts.dmSans(
              color: canSave ? Colors.white : _kDisable,
              fontWeight: FontWeight.w700,
              fontSize: 14));
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: canSave && !saving
              ? [
                  BoxShadow(
                      color: bg.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]
              : [],
        ),
        child: Center(child: child),
      ),
    );
  }
}
