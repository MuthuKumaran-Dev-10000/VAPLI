// lib/presentation/screens/readings/reading_entry_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// FEATURES:
//   ✅ ALL original features preserved
//   ✅ Capture image → immediate Cloudinary upload → URL stored in memory
//   ✅ Violation alert written to DB the instant photo is captured (not on save)
//   ✅ Constraint clears → corresponding alert record DELETED from DB dynamically
//   ✅ Value changes → alert updated live in DB if constraint still active
//   ✅ Manual captures hidden behind AppBar toggle (camera icon, top-right)
//   ✅ Manual captures section expands / collapses — add/delete entries freely
//   ✅ All per-param photo captures also upload immediately on capture
//   ✅ On final Save: no re-upload needed (URLs already stored); just assembles
//      the reading record and writes it
//   ✅ NEW: Autofill parameters — disabled by default, radio button to toggle
//      manual entry ("Autofill" label to enable/disable autofill)
//   ✅ NEW: Expression evaluation — auto-calculates when all deps are filled
//   ✅ NEW: Dependency status list with ✓ (green) / ✗ (red) per param
//   ✅ NEW: Re-evaluates when any dependency param changes (edit/delete)
//   ✅ NEW: Math errors caught (divide-by-zero, etc.) shown in layman terms
//   ✅ NEW: Sound + vibration fixed using AudioPlayer with asset fallback
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
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

// ── Helpers ───────────────────────────────────────────────────────────────────
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

// ── Autofill expression result ────────────────────────────────────────────────
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
  final _db = FirebaseDatabase.instance.ref();

  // ── Audio ──────────────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── Save state ─────────────────────────────────────────────────────────
  bool _saving = false;
  bool _saved = false;
  bool _failed = false;
  String? _uploadError;

  // ── Manual captures toggle ─────────────────────────────────────────────
  bool _showManualCaptures = false;

  // ── Dynamic property controllers ──────────────────────────────────────
  final Map<String, TextEditingController> _textCtrl = {};
  final Map<String, TextEditingController> _dualLeft = {};
  final Map<String, TextEditingController> _dualRight = {};
  final Map<String, String?> _dropdownVal = {};
  final Map<String, double> _sliderVal = {};

  // ── Autofill: per-param → is autofill mode active (true) or manual (false)
  // true = autofill enabled (field disabled), false = manual entry enabled
  final Map<String, bool> _autofillEnabled = {};

  // ── Autofill computed result per param ────────────────────────────────
  final Map<String, _AutofillResult?> _autofillResult = {};

  // ── Per-param photo: File + already-uploaded URL ───────────────────────
  final Map<String, File?> _paramPhoto = {};
  final Map<String, String?> _paramPhotoUrl = {};
  final Map<String, bool> _paramUploading = {};

  // ── Violation photos ──────────────────────────────────────────────────
  final Map<String, Map<String, File?>> _violationPhotos = {};
  final Map<String, Map<String, String?>> _violationPhotoUrls = {};
  final Map<String, Map<String, bool>> _violationUploading = {};

  // ── Current violations per param ──────────────────────────────────────
  final Map<String, List<_Violation>> _violations = {};

  // ── Live DB alert record IDs ──────────────────────────────────────────
  final Map<String, Map<String, String>> _liveAlertIds = {};

  // ── Track side-effects already fired ─────────────────────────────────
  final Map<String, Set<String>> _alreadyFiredConstraints = {};

  // ── Manual captures ───────────────────────────────────────────────────
  final List<_ManualCaptureEntry> _manualCaptures = [];

  // ── Deep copy of inspection properties ────────────────────────────────
  late final List<Map<String, dynamic>> _props;

  // ── Which autofill params depend on which param ids ───────────────────
  // autofillParamId → Set<dependencyParamId>
  final Map<String, Set<String>> _autofillDeps = {};

  String get _nowLabel =>
      DateFormat('dd MMM yyyy, HH:mm:ss').format(DateTime.now());

  // ── lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

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
      final isAutofill = p['autofill'] == true;

      // Set autofill mode: if autofill property exists and is true, start enabled
      if (isAutofill) {
        _autofillEnabled[id] = true;
        _autofillResult[id] = null;
        // Parse dependency IDs from expression
        _autofillDeps[id] = _parseDependencyIds(
            p['autofill_expression'] as String? ?? '');
      }

      switch (type) {
        case 'number':
        case 'text':
        case 'multiline':
          final ctrl = TextEditingController();
          // Only add listener for non-autofill OR manual override
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

      if (p['capture_image'] == true) {
        _paramPhoto[id] = null;
        _paramPhotoUrl[id] = null;
        _paramUploading[id] = false;
      }

      _violations[id] = [];
      _violationPhotos[id] = {};
      _violationPhotoUrls[id] = {};
      _violationUploading[id] = {};
      _liveAlertIds[id] = {};
      _alreadyFiredConstraints[id] = {};
    }

    _manualCaptures.add(_ManualCaptureEntry());
  }

  @override
  void dispose() {
    _textCtrl.values.forEach((c) => c.dispose());
    _dualLeft.values.forEach((c) => c.dispose());
    _dualRight.values.forEach((c) => c.dispose());
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Sound + Vibration (fixed) ──────────────────────────────────────────

  Future<void> _playViolationSound() async {
    try {
      // Try to play a built-in alert sound via AudioPlayer
      // Uses the default system alert sound asset — add 'assets/sounds/alert.mp3'
      // to your pubspec.yaml under flutter > assets if you have a custom sound.
      // Fallback: SystemSound + vibration
      await _audioPlayer.stop();
      try {
        await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
      } catch (_) {
        // Asset not found — use system sound as fallback
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }

    // Vibration: use HapticFeedback with heavy impact for better effect
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.heavyImpact();
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  // ── Autofill: parse dependency IDs from expression ─────────────────────
  // Expression format: ${paramId_label_side} e.g. ${1779288073832_operands_left}
  Set<String> _parseDependencyIds(String expression) {
    final deps = <String>{};
    final regex = RegExp(r'\$\{([^}]+)\}');
    for (final match in regex.allMatches(expression)) {
      final token = match.group(1)!; // e.g. "1779288073832_operands_left"
      // The param ID is the first segment (before first underscore that starts label)
      // But param IDs can contain hyphens. The token format is: {id}_{label}_{side?}
      // We need to find the param id — match against known param IDs
      for (final p in _props) {
        final pid = p['id'] as String;
        if (token.startsWith(pid)) {
          deps.add(pid);
          break;
        }
      }
    }
    return deps;
  }

  // ── Autofill: get the value of a dependency token ─────────────────────
  // Token format from expression: ${paramId_label_left} or ${paramId_label}
  double? _resolveToken(String token) {
    for (final p in _props) {
      final pid = p['id'] as String;
      if (!token.startsWith(pid)) continue;
      final type = p['type'] as String? ?? 'text';
      final remainder = token.substring(pid.length); // e.g. "_operands_left"

      if (type == 'dual_text') {
        if (remainder.endsWith('_left')) {
          final raw = _dualLeft[pid]?.text.trim() ?? '';
          return double.tryParse(raw);
        } else if (remainder.endsWith('_right')) {
          final raw = _dualRight[pid]?.text.trim() ?? '';
          return double.tryParse(raw);
        }
      } else if (type == 'number') {
        final raw = _textCtrl[pid]?.text.trim() ?? '';
        return double.tryParse(raw);
      } else if (type == 'slider') {
        return _sliderVal[pid];
      }
    }
    return null;
  }

  // ── Autofill: evaluate the expression ────────────────────────────────
  _AutofillResult _evaluateExpression(String expression) {
    try {
      // Replace all ${token} with their numeric values
      String expr = expression;
      final regex = RegExp(r'\$\{([^}]+)\}');

      for (final match in regex.allMatches(expression)) {
        final token = match.group(1)!;
        final val = _resolveToken(token);
        if (val == null) {
          return const _AutofillResult.error(
            'Some required values are not filled in yet.',
            'NullValueException',
          );
        }
        expr = expr.replaceFirst('\${$token}', val.toString());
      }

      // Safe math evaluation (support +, -, *, /, ^, parentheses)
      final result = _evalMathExpr(expr);
      return _AutofillResult.value(result);
    } on _DivisionByZeroException catch (e) {
      return _AutofillResult.error(
        'You\'re trying to divide by zero — that\'s not mathematically possible. Please check the divisor value.',
        'DivisionByZeroException',
      );
    } on _MathException catch (e) {
      return _AutofillResult.error(e.layman, e.name);
    } catch (e) {
      return _AutofillResult.error(
        'Something went wrong while calculating the result. Please check all values.',
        e.runtimeType.toString(),
      );
    }
  }

  // ── Simple recursive math expression evaluator ────────────────────────
  double _evalMathExpr(String expr) {
    expr = expr.trim();

    // Handle parentheses
    if (expr.startsWith('(') && expr.endsWith(')')) {
      // Find matching close paren
      int depth = 0;
      bool fullyWrapped = true;
      for (int i = 0; i < expr.length; i++) {
        if (expr[i] == '(') depth++;
        if (expr[i] == ')') depth--;
        if (depth == 0 && i < expr.length - 1) {
          fullyWrapped = false;
          break;
        }
      }
      if (fullyWrapped) {
        return _evalMathExpr(expr.substring(1, expr.length - 1));
      }
    }

    // Find last + or - outside parentheses (lowest precedence, right to left)
    int depth2 = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final ch = expr[i];
      if (ch == ')') depth2++;
      if (ch == '(') depth2--;
      if (depth2 == 0 && (ch == '+' || ch == '-') && i > 0) {
        final left = expr.substring(0, i);
        final right = expr.substring(i + 1);
        if (ch == '+') return _evalMathExpr(left) + _evalMathExpr(right);
        if (ch == '-') return _evalMathExpr(left) - _evalMathExpr(right);
      }
    }

    // Find last * or / outside parentheses
    depth2 = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final ch = expr[i];
      if (ch == ')') depth2++;
      if (ch == '(') depth2--;
      if (depth2 == 0 && (ch == '*' || ch == '/')) {
        final left = _evalMathExpr(expr.substring(0, i));
        final right = _evalMathExpr(expr.substring(i + 1));
        if (ch == '*') return left * right;
        if (ch == '/') {
          if (right == 0) throw _DivisionByZeroException();
          return left / right;
        }
      }
    }

    // Find ^ (power)
    depth2 = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final ch = expr[i];
      if (ch == ')') depth2++;
      if (ch == '(') depth2--;
      if (depth2 == 0 && ch == '^') {
        final base = _evalMathExpr(expr.substring(0, i));
        final exp = _evalMathExpr(expr.substring(i + 1));
        final result = math.pow(base, exp).toDouble();
        if (result.isInfinite || result.isNaN) {
          throw _MathException(
            'The calculation produced a number too large or undefined (e.g. 0^0 or overflow).',
            'InfiniteOrNaNException',
          );
        }
        return result;
      }
    }

    // Try parsing as a plain number
    final parsed = double.tryParse(expr);
    if (parsed == null) {
      throw _MathException(
        'Could not understand part of the formula: "$expr". Please check the expression.',
        'ParseException',
      );
    }

    if (parsed.isNaN || parsed.isInfinite) {
      throw _MathException(
        'The result is not a valid number. Check for invalid operations like sqrt of a negative number.',
        'InvalidNumberException',
      );
    }

    return parsed;
  }

  // ── Autofill: check if all deps are filled ────────────────────────────
  Map<String, bool> _getDepsFillStatus(String autofillParamId) {
    final deps = _autofillDeps[autofillParamId] ?? {};
    final status = <String, bool>{};

    for (final depId in deps) {
      final p = _props.firstWhere((pp) => pp['id'] == depId,
          orElse: () => <String, dynamic>{});
      if (p.isEmpty) {
        status[depId] = false;
        continue;
      }
      final type = p['type'] as String? ?? 'text';
      bool filled = false;
      switch (type) {
        case 'number':
          final raw = _textCtrl[depId]?.text.trim() ?? '';
          filled = raw.isNotEmpty && double.tryParse(raw) != null;
          break;
        case 'text':
        case 'multiline':
          filled = (_textCtrl[depId]?.text.trim() ?? '').isNotEmpty;
          break;
        case 'dropdown':
          filled = _dropdownVal[depId] != null;
          break;
        case 'slider':
          filled = true; // slider always has a value
          break;
        case 'dual_text':
          final l = _dualLeft[depId]?.text.trim() ?? '';
          final r = _dualRight[depId]?.text.trim() ?? '';
          filled = l.isNotEmpty && r.isNotEmpty;
          break;
      }
      status[depId] = filled;
    }

    return status;
  }

  // ── Re-evaluate autofill params that depend on a changed param ─────────
  void _reevaluateAutofillDependents(String changedParamId) {
    for (final entry in _autofillDeps.entries) {
      final autofillId = entry.key;
      final deps = entry.value;
      if (!deps.contains(changedParamId)) continue;

      // Only re-evaluate if autofill mode is active
      if (_autofillEnabled[autofillId] != true) continue;

      final p = _props.firstWhere((pp) => pp['id'] == autofillId,
          orElse: () => <String, dynamic>{});
      if (p.isEmpty) continue;

      final expression = p['autofill_expression'] as String? ?? '';
      final depsStatus = _getDepsFillStatus(autofillId);
      final allFilled = depsStatus.values.every((v) => v);

      if (allFilled) {
        final result = _evaluateExpression(expression);
        setState(() {
          _autofillResult[autofillId] = result;
          if (!result.hasError && result.value != null) {
            // Update the text controller with the computed value
            final formatted = result.value! == result.value!.truncateToDouble()
                ? result.value!.toInt().toString()
                : result.value!.toStringAsFixed(4);
            _textCtrl[autofillId]?.removeListener(() => _onValueChanged(autofillId));
            _textCtrl[autofillId]?.text = formatted;
            // Re-add listener after setting text
          }
        });
        // Trigger constraint evaluation for the autofill param
        _onValueChanged(autofillId);
      } else {
        setState(() {
          _autofillResult[autofillId] = null;
          // Clear the field if deps not all filled
          _textCtrl[autofillId]?.text = '';
        });
      }
    }
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

  // ── Immediate param photo upload ───────────────────────────────────────

  Future<void> _captureParamImage(String paramId) async {
    final img =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null || !mounted) return;

    final annotated = await Navigator.push<File>(
        context,
        MaterialPageRoute(
            builder: (_) => ImageMarkerScreen(imageFile: File(img.path))));
    if (annotated == null || !mounted) return;

    setState(() {
      _paramPhoto[paramId] = annotated;
      _paramPhotoUrl[paramId] = null;
      _paramUploading[paramId] = true;
    });

    try {
      final url = await _uploadFile(annotated);
      if (mounted) {
        setState(() {
          _paramPhotoUrl[paramId] = url;
          _paramUploading[paramId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _paramUploading[paramId] = false);
        _snack('Photo upload failed: $e', _kDanger);
      }
    }
  }

  // ── Immediate violation photo upload + live DB write ───────────────────

  Future<void> _captureViolationPhoto(
      String paramId, String constraintId) async {
    final img =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null || !mounted) return;

    final annotated = await Navigator.push<File>(
        context,
        MaterialPageRoute(
            builder: (_) => ImageMarkerScreen(imageFile: File(img.path))));
    if (annotated == null || !mounted) return;

    setState(() {
      _violationPhotos[paramId] ??= {};
      _violationPhotoUrls[paramId] ??= {};
      _violationUploading[paramId] ??= {};
      _violationPhotos[paramId]![constraintId] = annotated;
      _violationUploading[paramId]![constraintId] = true;
    });

    try {
      final url = await _uploadFile(annotated);
      if (mounted) {
        setState(() {
          _violationPhotoUrls[paramId]![constraintId] = url;
          _violationUploading[paramId]![constraintId] = false;
        });
        await _writeLiveAlertWithPhoto(
            paramId: paramId, constraintId: constraintId, imageUrl: url);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _violationUploading[paramId]![constraintId] = false);
        _snack('Evidence upload failed: $e', _kDanger);
      }
    }
  }

  // ── Immediate manual photo upload ──────────────────────────────────────

  Future<void> _captureManualPhoto(int index) async {
    final img =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null || !mounted) return;

    final annotated = await Navigator.push<File>(
        context,
        MaterialPageRoute(
            builder: (_) => ImageMarkerScreen(imageFile: File(img.path))));
    if (annotated == null || !mounted) return;

    setState(() {
      _manualCaptures[index].capturedImage = annotated;
      _manualCaptures[index].uploadedUrl = null;
      _manualCaptures[index].uploading = true;
    });

    try {
      final url = await _uploadFile(annotated);
      if (mounted) {
        setState(() {
          _manualCaptures[index].uploadedUrl = url;
          _manualCaptures[index].uploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _manualCaptures[index].uploading = false);
        _snack('Manual photo upload failed: $e', _kDanger);
      }
    }
  }

  // ── Live alert DB helpers ──────────────────────────────────────────────

  String _alertKey(String paramId, String constraintId) =>
      'live_${widget.tank.id}_${paramId}_$constraintId';

  Future<void> _writeLiveAlertWithPhoto({
    required String paramId,
    required String constraintId,
    String? imageUrl,
  }) async {
    final vList = _violations[paramId] ?? [];
    final v = vList
        .cast<_Violation?>()
        .firstWhere((x) => x?.constraintId == constraintId, orElse: () => null);
    if (v == null) return;

    final p = _props.firstWhere((pp) => pp['id'] == paramId,
        orElse: () => <String, dynamic>{});
    if (p.isEmpty) return;
    final type = p['type'] as String? ?? 'text';
    final label = p['label'] as String? ?? paramId;
    final val = _currentValue(paramId, type, p);

    _liveAlertIds[paramId] ??= {};
    final existingId = _liveAlertIds[paramId]![constraintId];
    final alertId = existingId ?? _alertKey(paramId, constraintId);
    _liveAlertIds[paramId]![constraintId] = alertId;

    final photoUrl =
        imageUrl ?? _violationPhotoUrls[paramId]?[constraintId] ?? '';

    final record = {
      'id': alertId,
      'tank_id': widget.tank.id,
      'tank_name': widget.tank.tankName,
      'tank_code': widget.tank.tankCode,
      'constraint_id': constraintId,
      'alert_title': v.alertTitle,
      'message': v.message,
      'severity': v.severity,
      'param_id': paramId,
      'param_label': label,
      'param_value': val.toString(),
      'captured_by': widget.currentUser.id,
      'captured_by_name': widget.currentUser.fullName,
      'image_url': photoUrl,
      'timestamp': DateTime.now().toIso8601String(),
      'acknowledged': false,
      'live': true,
    };

    try {
      if (v.showDashboardAlert) {
        await _db.child('alerts/$alertId').set(record);
      }
      if (v.storeHistory) {
        await _db.child('violations/$alertId').set(record);
      }
      await _db.child('alerts_full/$alertId').set({
        ...record,
        'all_values_snapshot': _collectValues(),
        'resolved': false,
      });
    } catch (e) {
      debugPrint('[LiveAlert] Write failed: $e');
    }
  }

  Future<void> _deleteLiveAlert({
    required String paramId,
    required String constraintId,
  }) async {
    final alertId = _liveAlertIds[paramId]?[constraintId];
    if (alertId == null) return;

    _liveAlertIds[paramId]!.remove(constraintId);

    try {
      await _db.child('alerts/$alertId').remove();
      await _db.child('violations/$alertId').remove();
      await _db.child('alerts_full/$alertId').remove();
    } catch (e) {
      debugPrint('[LiveAlert] Delete failed: $e');
    }
  }

  // ── Value extraction ───────────────────────────────────────────────────

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

  List<_Violation> _evaluateAllConstraints(
      Map<String, dynamic> p, dynamic value) {
    final fired = <_Violation>[];
    final rawList = p['constraints'];
    if (rawList is! List) return fired;

    final actual = value.toString().trim();
    if (actual.isEmpty) return fired;

    for (final c in rawList) {
      if (c is! Map) continue;
      final constraint = Map<String, dynamic>.from(c);
      final op = constraint['op']?.toString() ?? '';
      final expected = constraint['value']?.toString() ?? '';

      bool isFired = false;
      switch (op) {
        case '<':
          isFired =
              (double.tryParse(actual) ?? 0) < (double.tryParse(expected) ?? 0);
          break;
        case '<=':
          isFired = (double.tryParse(actual) ?? 0) <=
              (double.tryParse(expected) ?? 0);
          break;
        case '>':
          isFired =
              (double.tryParse(actual) ?? 0) > (double.tryParse(expected) ?? 0);
          break;
        case '>=':
          isFired = (double.tryParse(actual) ?? 0) >=
              (double.tryParse(expected) ?? 0);
          break;
        case '==':
          isFired = actual.toLowerCase() == expected.toLowerCase();
          break;
        case '!=':
          isFired = actual.toLowerCase() != expected.toLowerCase();
          break;
        case 'contains':
          isFired = actual.toLowerCase().contains(expected.toLowerCase());
          break;
        case 'starts_with':
          isFired = actual.toLowerCase().startsWith(expected.toLowerCase());
          break;
        case 'ends_with':
          isFired = actual.toLowerCase().endsWith(expected.toLowerCase());
          break;
        case 'regex':
          try {
            isFired = RegExp(expected).hasMatch(actual);
          } catch (_) {}
          break;
      }

      if (isFired) {
        fired.add(_Violation(
          constraintId: constraint['id']?.toString() ?? '',
          message: constraint['message']?.toString() ?? 'Alert condition met',
          alertTitle: constraint['alert_title']?.toString() ?? 'Alert',
          severity: constraint['severity']?.toString() ?? 'warning',
          blockSubmission: constraint['block_submission'] == true,
          captureImageOnViolation:
              constraint['capture_image_on_violation'] == true,
          playSoundOnViolation: constraint['play_sound_on_violation'] == true,
          showDashboardAlert: constraint['show_dashboard_alert'] == true,
          storeHistory: constraint['store_history'] == true,
        ));
      }
    }
    return fired;
  }

  // ── Called on every value change ───────────────────────────────────────

  void _onValueChanged(String id) {
    final p = _props.firstWhere((e) => e['id'] == id,
        orElse: () => <String, dynamic>{});
    if (p.isEmpty) return;

    final type = p['type'] as String? ?? 'text';
    final val = _currentValue(id, type, p);
    final prevViolations = List<_Violation>.from(_violations[id] ?? []);
    final newViolations = _evaluateAllConstraints(p, val);
    final newIds = newViolations.map((v) => v.constraintId).toSet();
    final prevIds = prevViolations.map((v) => v.constraintId).toSet();

    // Constraints that CLEARED → delete DB alerts
    for (final clearedId in prevIds.difference(newIds)) {
      _violationPhotos[id]?.remove(clearedId);
      _violationPhotoUrls[id]?.remove(clearedId);
      _alreadyFiredConstraints[id]?.remove(clearedId);
      _deleteLiveAlert(paramId: id, constraintId: clearedId);
    }

    setState(() => _violations[id] = newViolations);

    // Newly fired constraints
    for (final v in newViolations) {
      final alreadyFired =
          _alreadyFiredConstraints[id]?.contains(v.constraintId) ?? false;

      if (!alreadyFired) {
        _alreadyFiredConstraints[id]?.add(v.constraintId);
        _handleConstraintFired(paramId: id, param: p, value: val, violation: v);
      } else {
        _updateLiveAlert(
            paramId: id, constraintId: v.constraintId, newValue: val);
      }
    }

    if (newViolations.isEmpty && prevViolations.isNotEmpty) {
      _alreadyFiredConstraints[id]?.clear();
    }

    // Re-evaluate any autofill params that depend on this param
    _reevaluateAutofillDependents(id);
  }

  // ── Handle first fire of a constraint ─────────────────────────────────

  Future<void> _handleConstraintFired({
    required String paramId,
    required Map<String, dynamic> param,
    required dynamic value,
    required _Violation violation,
  }) async {
    if (violation.playSoundOnViolation) {
      await _playViolationSound();
    }

    await _writeLiveAlertWithPhoto(
        paramId: paramId, constraintId: violation.constraintId);
  }

  Future<void> _updateLiveAlert({
    required String paramId,
    required String constraintId,
    required dynamic newValue,
  }) async {
    final alertId = _liveAlertIds[paramId]?[constraintId];
    if (alertId == null) return;
    try {
      final update = {
        'param_value': newValue.toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'all_values_snapshot': _collectValues(),
      };
      await _db.child('alerts/$alertId').update(update);
      await _db.child('alerts_full/$alertId').update(update);
    } catch (e) {
      debugPrint('[LiveAlert] Update failed: $e');
    }
  }

  // ── Required / block checks ────────────────────────────────────────────

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
      _violations.values.any((list) => list.any((v) => v.blockSubmission));

  bool get _hasMissingViolationPhoto {
    for (final p in _props) {
      final id = p['id'] as String;
      final vList = _violations[id] ?? [];
      for (final v in vList) {
        if (v.captureImageOnViolation &&
            (_violationPhotos[id]?[v.constraintId] == null)) {
          return true;
        }
      }
    }
    return false;
  }

  bool get _hasUploadInProgress {
    if (_paramUploading.values.any((v) => v == true)) return true;
    if (_violationUploading.values.any((m) => m.values.any((v) => v == true)))
      return true;
    if (_manualCaptures.any((e) => e.uploading)) return true;
    return false;
  }

  bool get _canSave {
    if (_saving || _saved) return false;
    if (_hasBlockingViolation) return false;
    if (_hasMissingViolationPhoto) return false;
    if (_hasUploadInProgress) return false;
    for (final p in _props) {
      if (p['capture_image'] == true) {
        if (_paramPhoto[p['id'] as String] == null) return false;
      }
    }
    return true;
  }

  // ── Collect values for the reading record ──────────────────────────────

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
      final inspVals = _collectValues();

      for (final e in _paramPhotoUrl.entries) {
        if (e.value != null) inspVals['${e.key}__image_url'] = e.value!;
      }

      for (final paramEntry in _violationPhotoUrls.entries) {
        for (final cEntry in paramEntry.value.entries) {
          if (cEntry.value != null) {
            inspVals['${paramEntry.key}__violation_${cEntry.key}_image_url'] =
                cEntry.value!;
          }
        }
      }

      for (int i = 0; i < _manualCaptures.length; i++) {
        final entry = _manualCaptures[i];
        if (entry.selectedParamId != null && entry.uploadedUrl != null) {
          final paramLabel = _props.firstWhere(
                      (p) => p['id'] == entry.selectedParamId,
                      orElse: () => {'label': entry.selectedParamId})['label']
                  as String? ??
              entry.selectedParamId!;
          final key = 'manual_${paramLabel}_captured_image';
          if (inspVals.containsKey(key)) {
            inspVals['manual_${paramLabel}_captured_image_$i'] =
                entry.uploadedUrl!;
          } else {
            inspVals[key] = entry.uploadedUrl!;
          }
        }
      }

      for (final p in _props) {
        final id = p['id'] as String;
        final type = p['type'] as String? ?? 'text';
        final label = p['label'] as String? ?? id;
        final val = _currentValue(id, type, p);
        final blocking = _evaluateAllConstraints(p, val)
            .where((v) => v.blockSubmission)
            .toList();
        if (blocking.isNotEmpty) {
          _snack('"$label": ${blocking.first.message}', _kDanger);
          setState(() => _saving = false);
          return;
        }
      }

      final primaryImageUrl = _paramPhotoUrl.values
              .firstWhere((u) => u != null, orElse: () => null) ??
          '';

      final reading = await ReadingRepository().saveReading(
        tankId: widget.tank.id,
        tankName: widget.tank.tankName,
        level: 0,
        capturedBy: widget.currentUser.id,
        capturedByName: widget.currentUser.fullName,
        imageUrl: primaryImageUrl,
        inspectionValues: inspVals,
      );

      await DashboardStatsRepository().updateStatsAfterReading(
        reading: reading,
        tank: widget.tank,
      );

      for (final paramMap in _liveAlertIds.values) {
        for (final alertId in paramMap.values) {
          try {
            await _db.child('alerts/$alertId').update({
              'live': false,
              'reading_id': reading.id ?? '',
            });
            await _db.child('alerts_full/$alertId').update({
              'live': false,
              'reading_id': reading.id ?? '',
            });
          } catch (_) {}
        }
      }

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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _showManualCaptures = !_showManualCaptures),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _showManualCaptures
                      ? _kCopper.withOpacity(0.18)
                      : _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _showManualCaptures
                        ? _kCopper.withOpacity(0.55)
                        : _kBorderH,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.camera_alt_outlined,
                      size: 15, color: _showManualCaptures ? _kCopper : _kSub),
                  const SizedBox(width: 5),
                  Text('Manual',
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: _showManualCaptures ? _kCopper : _kSub,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ],
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

            if (_showManualCaptures) ...[
              const SizedBox(height: 28),
              _buildManualCaptureSection(),
            ],

            const SizedBox(height: 28),

            if (_hasBlockingViolation) ...[
              _BlockBanner(violations: _violations, props: _props),
              const SizedBox(height: 16),
            ],

            if (_hasUploadInProgress) ...[
              const _UploadingBanner(),
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

  // ── Manual Capture Section ─────────────────────────────────────────────

  Widget _buildManualCaptureSection() {
    final paramOptions = _props
        .map((p) => MapEntry(
            p['id'] as String, p['label'] as String? ?? p['id'] as String))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _SecLabel('MANUAL CAPTURES'),
          const Spacer(),
          GestureDetector(
            onTap: () =>
                setState(() => _manualCaptures.add(_ManualCaptureEntry())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kCopper.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kCopper.withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, size: 14, color: _kCopper),
                const SizedBox(width: 4),
                Text('Add',
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: _kCopper,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Attach extra photos to any parameter',
            style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
        const SizedBox(height: 14),
        ..._manualCaptures.asMap().entries.map(
              (entry) =>
                  _buildManualEntry(entry.key, entry.value, paramOptions),
            ),
      ],
    );
  }

  Widget _buildManualEntry(
    int index,
    _ManualCaptureEntry entry,
    List<MapEntry<String, String>> paramOptions,
  ) {
    final hasCaptured = entry.capturedImage != null;
    final hasParam = entry.selectedParamId != null;
    final isUploading = entry.uploading;
    final hasUrl = entry.uploadedUrl != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _kCopper.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kCopper.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text('${index + 1}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: _kCopper,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Text('Manual Capture',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: _kSub, fontWeight: FontWeight.w500)),
              if (isUploading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        color: _kCopper, strokeWidth: 1.5)),
                const SizedBox(width: 4),
                Text('Uploading…',
                    style: GoogleFonts.dmSans(fontSize: 10, color: _kCopper)),
              ] else if (hasUrl) ...[
                const SizedBox(width: 8),
                const Icon(Icons.cloud_done_rounded,
                    size: 13, color: _kSuccess),
                const SizedBox(width: 3),
                Text('Uploaded',
                    style: GoogleFonts.dmSans(fontSize: 10, color: _kSuccess)),
              ],
              const Spacer(),
              if (_manualCaptures.length > 1)
                GestureDetector(
                  onTap: () => setState(() => _manualCaptures.removeAt(index)),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _kDanger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _kDanger.withOpacity(0.25)),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 14, color: _kDanger),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Text('Parameter',
                style: GoogleFonts.dmSans(
                    fontSize: 11, fontWeight: FontWeight.w600, color: _kSub)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: entry.selectedParamId,
                  isExpanded: true,
                  dropdownColor: _kCard,
                  iconEnabledColor: _kSub,
                  hint: Text('Select parameter…',
                      style: GoogleFonts.dmSans(color: _kSub, fontSize: 13)),
                  items: paramOptions
                      .map((opt) => DropdownMenuItem(
                            value: opt.key,
                            child: Text(opt.value,
                                style: GoogleFonts.dmSans(
                                    color: _kText, fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(
                      () => _manualCaptures[index].selectedParamId = v),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: (hasParam && !isUploading)
                      ? () => _captureManualPhoto(index)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 50,
                    decoration: BoxDecoration(
                      color: !hasParam
                          ? _kSurface
                          : hasUrl
                              ? _kSuccess.withOpacity(0.08)
                              : hasCaptured
                                  ? _kCopper.withOpacity(0.08)
                                  : _kTeal.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !hasParam
                            ? _kBorder
                            : hasUrl
                                ? _kSuccess.withOpacity(0.4)
                                : hasCaptured
                                    ? _kCopper.withOpacity(0.4)
                                    : _kTeal.withOpacity(0.4),
                      ),
                    ),
                    child: isUploading
                        ? const Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: _kCopper, strokeWidth: 2)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hasUrl
                                    ? Icons.cloud_done_rounded
                                    : hasCaptured
                                        ? Icons.camera_alt_rounded
                                        : Icons.camera_alt_outlined,
                                size: 18,
                                color: !hasParam
                                    ? _kDisable
                                    : hasUrl
                                        ? _kSuccess
                                        : hasCaptured
                                            ? _kCopper
                                            : _kTeal,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                hasUrl
                                    ? 'Retake Photo'
                                    : hasCaptured
                                        ? 'Uploading…'
                                        : 'Capture Photo',
                                style: GoogleFonts.dmSans(
                                  color: !hasParam
                                      ? _kDisable
                                      : hasUrl
                                          ? _kSuccess
                                          : hasCaptured
                                              ? _kCopper
                                              : _kTeal,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              if (hasCaptured) ...[
                const SizedBox(width: 10),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(entry.capturedImage!,
                          width: 50, height: 50, fit: BoxFit.cover),
                    ),
                    if (hasUrl)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                              color: _kSuccess, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              size: 9, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
            ]),
            if (hasParam && hasUrl) ...[
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final lbl = paramOptions
                    .firstWhere((o) => o.key == entry.selectedParamId,
                        orElse: () => MapEntry(entry.selectedParamId!, ''))
                    .value;
                return Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 11, color: _kSuccess),
                  const SizedBox(width: 4),
                  Text(
                    'Saved as: manual_${lbl}_captured_image',
                    style: GoogleFonts.dmSans(fontSize: 10, color: _kSuccess),
                  ),
                ]);
              }),
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
    final isEffReq = isReq || hasCam;
    final vList = _violations[id] ?? [];
    final hasVio = vList.isNotEmpty;
    final isAutofill = p['autofill'] == true;

    String? topSeverity;
    if (hasVio) {
      if (vList.any((v) => v.severity == 'critical'))
        topSeverity = 'critical';
      else if (vList.any((v) => v.severity == 'warning'))
        topSeverity = 'warning';
      else
        topSeverity = 'info';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label row ────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Text(isEffReq ? '$label *' : label,
                  style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kText)),
            ),
            if (isEffReq) _Badge('REQUIRED', _kDanger),
            if (isAutofill) ...[
              const SizedBox(width: 6),
              _Badge('AUTOFILL', _kPurple),
            ],
            if (hasVio) ...[
              const SizedBox(width: 6),
              _Badge('${vList.length} ALERT${vList.length > 1 ? 'S' : ''}',
                  _severityColor(topSeverity)),
            ],
          ]),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(hint, style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
          ],

          // ── Autofill toggle radio ─────────────────────────────────
          if (isAutofill) ...[
            const SizedBox(height: 8),
            _AutofillToggleRow(
              isAutofillEnabled: _autofillEnabled[id] ?? true,
              onToggle: (enabled) {
                setState(() {
                  _autofillEnabled[id] = enabled;
                  if (enabled) {
                    // Re-evaluate when switching back to autofill
                    final expr = p['autofill_expression'] as String? ?? '';
                    final depsStatus = _getDepsFillStatus(id);
                    final allFilled = depsStatus.values.every((v) => v);
                    if (allFilled && expr.isNotEmpty) {
                      final result = _evaluateExpression(expr);
                      _autofillResult[id] = result;
                      if (!result.hasError && result.value != null) {
                        final formatted =
                            result.value! == result.value!.truncateToDouble()
                                ? result.value!.toInt().toString()
                                : result.value!.toStringAsFixed(4);
                        _textCtrl[id]?.text = formatted;
                      }
                    } else {
                      _autofillResult[id] = null;
                      _textCtrl[id]?.text = '';
                    }
                  } else {
                    // Manual mode — clear autofill result, let user type
                    _autofillResult[id] = null;
                  }
                });
              },
            ),
          ],

          const SizedBox(height: 8),
          _buildInput(p, id, type, hint, isReq),

          // ── Autofill dependency status + result ───────────────────
          if (isAutofill) ...[
            const SizedBox(height: 8),
            _AutofillStatusSection(
              paramId: id,
              props: _props,
              depsStatus: _getDepsFillStatus(id),
              autofillResult: _autofillResult[id],
              isAutofillEnabled: _autofillEnabled[id] ?? true,
              expressionDisplay:
                  p['autofill_expression_display'] as String? ??
                      p['autofill_expression'] as String? ??
                      '',
            ),
          ],

          // ── Violation banners ─────────────────────────────────────
          ...vList.map((v) {
            final isUploading =
                _violationUploading[id]?[v.constraintId] == true;
            final hasUrl = _violationPhotoUrls[id]?[v.constraintId] != null;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ViolationBanner(
                violation: v,
                violationPhoto: _violationPhotos[id]?[v.constraintId],
                isUploading: isUploading,
                hasUploadedUrl: hasUrl,
                onCapturePhoto: (v.captureImageOnViolation && !isUploading)
                    ? () => _captureViolationPhoto(id, v.constraintId)
                    : null,
              ),
            );
          }),

          // ── Per-param camera ──────────────────────────────────────
          if (hasCam) ...[
            const SizedBox(height: 10),
            _ParamPhotoRow(
              image: _paramPhoto[id],
              uploadedUrl: _paramPhotoUrl[id],
              uploading: _paramUploading[id] == true,
              onCapture: () => _captureParamImage(id),
            ),
          ],
        ],
      ),
    );
  }

  // ── Input decoration ───────────────────────────────────────────────────

  InputDecoration _dec(String hintText, {bool hasViolation = false}) {
    final borderColor = hasViolation ? _kDanger : _kBorder;
    final focusColor = hasViolation ? _kDanger : _kCopper;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor));
    return InputDecoration(
      hintText: hintText.isNotEmpty ? hintText : null,
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
    );
  }

  InputDecoration _decDisabled(String hintText) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder));
    return InputDecoration(
      hintText: hintText.isNotEmpty ? hintText : null,
      hintStyle: GoogleFonts.dmSans(color: _kDisable, fontSize: 13),
      filled: true,
      fillColor: _kSurface.withOpacity(0.5),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      suffixIcon: const Padding(
        padding: EdgeInsets.only(right: 10),
        child: Icon(Icons.auto_fix_high_rounded, size: 16, color: _kPurple),
      ),
    );
  }

  Widget _buildInput(
      Map<String, dynamic> p, String id, String type, String hint, bool isReq) {
    final violations = _violations[id] ?? [];
    final hasViolation = violations.isNotEmpty;
    final isAutofill = p['autofill'] == true;
    final autofillActive = isAutofill && (_autofillEnabled[id] ?? true);

    switch (type) {
      case 'number':
        // If autofill is active, show a disabled field with the computed value
        if (autofillActive) {
          return TextFormField(
            controller: _textCtrl[id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.spaceGrotesk(color: _kSub, fontSize: 15),
            cursorColor: _kCopper,
            decoration: _decDisabled(hint),
            enabled: false,
          );
        }
        return TextFormField(
          controller: _textCtrl[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.spaceGrotesk(color: _kText, fontSize: 15),
          cursorColor: _kCopper,
          decoration: _dec(hint, hasViolation: hasViolation),
          onChanged: (_) => _onValueChanged(id),
        );

      case 'text':
        if (autofillActive) {
          return TextFormField(
            controller: _textCtrl[id],
            style: GoogleFonts.dmSans(color: _kSub, fontSize: 14),
            cursorColor: _kCopper,
            decoration: _decDisabled(hint),
            enabled: false,
          );
        }
        return TextFormField(
          controller: _textCtrl[id],
          style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
          cursorColor: _kCopper,
          decoration: _dec(hint, hasViolation: hasViolation),
          onChanged: (_) => _onValueChanged(id),
        );

      case 'multiline':
        if (autofillActive) {
          return TextFormField(
            controller: _textCtrl[id],
            maxLines: 4,
            style: GoogleFonts.dmSans(color: _kSub, fontSize: 14),
            cursorColor: _kCopper,
            decoration: _decDisabled(hint),
            enabled: false,
          );
        }
        return TextFormField(
          controller: _textCtrl[id],
          maxLines: 4,
          style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
          cursorColor: _kCopper,
          decoration: _dec(hint, hasViolation: hasViolation),
          onChanged: (_) => _onValueChanged(id),
        );

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
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _onValueChanged(id));
              },
            ),
          ),
        );

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
                          color: _kSub))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(rbl,
                      style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kSub))),
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
                ),
              ),
            ]),
          ],
        );

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
// AUTOFILL TOGGLE ROW — radio button to switch autofill on/off
// ─────────────────────────────────────────────────────────────────────────────
class _AutofillToggleRow extends StatelessWidget {
  final bool isAutofillEnabled;
  final ValueChanged<bool> onToggle;

  const _AutofillToggleRow({
    required this.isAutofillEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kPurple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high_rounded, size: 14, color: _kPurple),
          const SizedBox(width: 8),
          Text('Autofill',
              style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: _kPurple,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text('(auto-calculate)',
              style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
          const Spacer(),
          // Autofill ON radio
          GestureDetector(
            onTap: () => onToggle(true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: isAutofillEnabled,
                  onChanged: (v) => onToggle(true),
                  activeColor: _kPurple,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Text('ON',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: isAutofillEnabled ? _kPurple : _kSub,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Manual (autofill OFF) radio
          GestureDetector(
            onTap: () => onToggle(false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<bool>(
                  value: false,
                  groupValue: isAutofillEnabled,
                  onChanged: (v) => onToggle(false),
                  activeColor: _kCopper,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Text('Manual',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: !isAutofillEnabled ? _kCopper : _kSub,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTOFILL STATUS SECTION
// Shows: expression display, dependency status list, computed result / error
// ─────────────────────────────────────────────────────────────────────────────
class _AutofillStatusSection extends StatelessWidget {
  final String paramId;
  final List<Map<String, dynamic>> props;
  final Map<String, bool> depsStatus;
  final _AutofillResult? autofillResult;
  final bool isAutofillEnabled;
  final String expressionDisplay;

  const _AutofillStatusSection({
    required this.paramId,
    required this.props,
    required this.depsStatus,
    required this.autofillResult,
    required this.isAutofillEnabled,
    required this.expressionDisplay,
  });

  String _labelForId(String id) {
    final p = props.firstWhere((pp) => pp['id'] == id,
        orElse: () => {'label': id});
    return p['label'] as String? ?? id;
  }

  @override
  Widget build(BuildContext context) {
    if (!isAutofillEnabled) return const SizedBox.shrink();
    if (depsStatus.isEmpty) return const SizedBox.shrink();

    final allFilled = depsStatus.values.every((v) => v);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kPurple.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPurple.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expression display
          if (expressionDisplay.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.functions_rounded, size: 13, color: _kPurple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  expressionDisplay,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: _kPurple,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 10),
          ],

          // Dependency status list
          Text('Required fields for calculation:',
              style: GoogleFonts.dmSans(
                  fontSize: 10, color: _kSub, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...depsStatus.entries.map((entry) {
            final filled = entry.value;
            final lbl = _labelForId(entry.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: filled
                        ? const Icon(Icons.check_circle_rounded,
                            size: 14,
                            color: _kSuccess,
                            key: ValueKey('filled'))
                        : const Icon(Icons.cancel_rounded,
                            size: 14,
                            color: _kDanger,
                            key: ValueKey('empty')),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    lbl,
                    style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: filled ? _kSuccess : _kDanger,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    filled ? 'filled' : 'not filled',
                    style: GoogleFonts.dmSans(
                        fontSize: 10,
                        color: filled
                            ? _kSuccess.withOpacity(0.7)
                            : _kDanger.withOpacity(0.7)),
                  ),
                ],
              ),
            );
          }),

          // Result / waiting / error
          const SizedBox(height: 8),
          if (!allFilled)
            Row(children: [
              const Icon(Icons.hourglass_empty_rounded,
                  size: 13, color: _kSub),
              const SizedBox(width: 6),
              Text('Fill all required fields to calculate',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
            ])
          else if (autofillResult == null)
            Row(children: [
              const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      color: _kPurple, strokeWidth: 1.5)),
              const SizedBox(width: 6),
              Text('Calculating…',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kPurple)),
            ])
          else if (autofillResult!.hasError)
            _AutofillErrorCard(
              laymanMessage: autofillResult!.errorMessage ?? 'Unknown error',
              exceptionName: autofillResult!.exceptionName ?? '',
            )
          else
            _AutofillResultCard(value: autofillResult!.value!),
        ],
      ),
    );
  }
}

class _AutofillResultCard extends StatelessWidget {
  final double value;
  const _AutofillResultCard({required this.value});

  @override
  Widget build(BuildContext context) {
    final display = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kSuccess.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kSuccess.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, size: 14, color: _kSuccess),
        const SizedBox(width: 8),
        Text('Result: ',
            style: GoogleFonts.dmSans(fontSize: 12, color: _kSuccess)),
        Text(display,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: _kSuccess,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('(auto-filled)',
            style: GoogleFonts.dmSans(fontSize: 10, color: _kSub)),
      ]),
    );
  }
}

class _AutofillErrorCard extends StatelessWidget {
  final String laymanMessage;
  final String exceptionName;
  const _AutofillErrorCard(
      {required this.laymanMessage, required this.exceptionName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kDanger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kDanger.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded, size: 14, color: _kDanger),
            const SizedBox(width: 6),
            Text('Calculation Error',
                style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: _kDanger,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 5),
          Text(laymanMessage,
              style: GoogleFonts.dmSans(fontSize: 12, color: _kText)),
          if (exceptionName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Technical: $exceptionName',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: _kSub, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MATH EXCEPTIONS
// ─────────────────────────────────────────────────────────────────────────────
class _DivisionByZeroException implements Exception {}

class _MathException implements Exception {
  final String layman;
  final String name;
  const _MathException(this.layman, this.name);
}

// ─────────────────────────────────────────────────────────────────────────────
// VIOLATION BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _ViolationBanner extends StatelessWidget {
  final _Violation violation;
  final File? violationPhoto;
  final bool isUploading;
  final bool hasUploadedUrl;
  final VoidCallback? onCapturePhoto;

  const _ViolationBanner({
    required this.violation,
    required this.violationPhoto,
    required this.isUploading,
    required this.hasUploadedUrl,
    this.onCapturePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(violation.severity);
    final icon = _severityIcon(violation.severity);

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
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 3),
                Text('LIVE',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 7,
                        color: color,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 5),
          Text(violation.message,
              style: GoogleFonts.dmSans(color: _kText, fontSize: 12)),

          if (violation.captureImageOnViolation) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCapturePhoto,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: hasUploadedUrl
                          ? _kSuccess.withOpacity(0.08)
                          : violationPhoto != null
                              ? _kCopper.withOpacity(0.08)
                              : _kDanger.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: hasUploadedUrl
                              ? _kSuccess.withOpacity(0.4)
                              : violationPhoto != null
                                  ? _kCopper.withOpacity(0.4)
                                  : _kDanger.withOpacity(0.5)),
                    ),
                    child: isUploading
                        ? const Center(
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: _kCopper, strokeWidth: 2)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hasUploadedUrl
                                    ? Icons.cloud_done_rounded
                                    : violationPhoto != null
                                        ? Icons.camera_alt_rounded
                                        : Icons.camera_alt_outlined,
                                size: 18,
                                color: hasUploadedUrl
                                    ? _kSuccess
                                    : violationPhoto != null
                                        ? _kCopper
                                        : _kDanger,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                hasUploadedUrl
                                    ? 'Retake Evidence Photo'
                                    : violationPhoto != null
                                        ? 'Uploading…'
                                        : 'Capture Evidence Photo *',
                                style: GoogleFonts.dmSans(
                                  color: hasUploadedUrl
                                      ? _kSuccess
                                      : violationPhoto != null
                                          ? _kCopper
                                          : _kDanger,
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
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(violationPhoto!,
                        width: 46, height: 46, fit: BoxFit.cover),
                  ),
                  if (hasUploadedUrl)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: const BoxDecoration(
                            color: _kSuccess, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 8, color: Colors.white),
                      ),
                    ),
                ]),
              ],
            ]),
          ],

          if (violation.playSoundOnViolation ||
              violation.showDashboardAlert ||
              violation.storeHistory) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
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
                    icon: Icons.history_rounded, label: 'Logged', color: color),
            ]),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOCK BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _BlockBanner extends StatelessWidget {
  final Map<String, List<_Violation>> violations;
  final List<Map<String, dynamic>> props;

  const _BlockBanner({required this.violations, required this.props});

  @override
  Widget build(BuildContext context) {
    final blocked = violations.entries
        .where((e) => e.value.any((v) => v.blockSubmission))
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
              Text('Fix violations in: ${blocked.join(', ')}',
                  style: GoogleFonts.dmSans(color: _kText, fontSize: 12)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UPLOADING BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _UploadingBanner extends StatelessWidget {
  const _UploadingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCopper.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kCopper.withOpacity(0.35)),
      ),
      child: Row(children: [
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(color: _kCopper, strokeWidth: 2)),
        const SizedBox(width: 10),
        Text('Uploading photos, please wait…',
            style: GoogleFonts.dmSans(
                color: _kCopper, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PER-PARAM PHOTO ROW
// ─────────────────────────────────────────────────────────────────────────────
class _ParamPhotoRow extends StatelessWidget {
  final File? image;
  final String? uploadedUrl;
  final bool uploading;
  final VoidCallback onCapture;

  const _ParamPhotoRow({
    required this.image,
    required this.uploadedUrl,
    required this.uploading,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    final captured = image != null;
    final hasUrl = uploadedUrl != null;

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: uploading ? null : onCapture,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: hasUrl
                  ? _kSuccess.withOpacity(0.08)
                  : captured
                      ? _kCopper.withOpacity(0.08)
                      : _kTeal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: hasUrl
                      ? _kSuccess.withOpacity(0.4)
                      : captured
                          ? _kCopper.withOpacity(0.4)
                          : _kTeal.withOpacity(0.4)),
            ),
            child: uploading
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: _kCopper, strokeWidth: 2)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasUrl
                            ? Icons.cloud_done_rounded
                            : captured
                                ? Icons.camera_alt_rounded
                                : Icons.camera_alt_outlined,
                        color: hasUrl
                            ? _kSuccess
                            : captured
                                ? _kCopper
                                : _kTeal,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasUrl
                            ? 'Retake Photo'
                            : captured
                                ? 'Uploading…'
                                : 'Capture Photo',
                        style: GoogleFonts.dmSans(
                            color: hasUrl
                                ? _kSuccess
                                : captured
                                    ? _kCopper
                                    : _kTeal,
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
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(image!, width: 54, height: 54, fit: BoxFit.cover),
          ),
          if (hasUrl)
            Positioned(
              bottom: 2,
              right: 2,
              child: Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                    color: _kSuccess, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 9, color: Colors.white),
              ),
            ),
        ]),
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
// META CARD
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// SAVE BUTTON
// ─────────────────────────────────────────────────────────────────────────────
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
        Text('Saving…',
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