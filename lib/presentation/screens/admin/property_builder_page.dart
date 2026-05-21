// lib/presentation/screens/admin/property_builder_page.dart
// ══════════════════════════════════════════════════════════════════════════════
// FIXES IN THIS VERSION:
//
//   FIX 1 — Expression is now properly SAVED:
//     • Added a "Save Expression" button inside the AutoFill section.
//     • Tapping it validates the expression, sets autofill: true, and
//       commits both the raw token expression and the display expression.
//     • autofill: true is now correctly stored on _save() because
//       _autoFillEnabled is properly managed.
//
//   FIX 2 — Two-expression storage:
//     • _exprCtrl         → raw expression  e.g. ${id_OilTemp}*0.5+${id2_Pressure}
//                           Used by the reading page for eval().
//     • _displayExprCtrl  → human-readable  e.g. OilTemp * 0.5 + Pressure
//                           Shown inside the editor so the user isn't confused.
//     • Saved as:
//         'autofill_expression'         → raw token string  (eval-ready)
//         'autofill_expression_display' → human name string (UI label)
//
//   FIX 3 — Expression editor shows human-readable names:
//     • The editable text field inside the AutoFill box shows _displayExprCtrl
//       (param names + operators, no ${...} noise).
//     • A collapsible "Raw Expression" chip row above shows the token preview
//       so the developer/admin can verify the stored form.
//
//   FIX 4 — Operator row and numpad write to both controllers in sync.
//
//   FIX 5 — DEL deletes from both controllers in sync (whole token on
//     _exprCtrl, whole name-token on _displayExprCtrl).
//
//   STORAGE RULES (unchanged):
//     • left_label / right_label only for dual_text.
//     • expected_min/avg/max for number/slider.
//     • left/right_expected_min/avg/max for dual_text.
//
//   LOCAL SQLite SCHEMA (unchanged):
//     Table: session_params
//       id           TEXT PRIMARY KEY
//       session_id   TEXT
//       label        TEXT
//       type         TEXT
//       left_label   TEXT
//       right_label  TEXT
//
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'create_tank_screen_helpers.dart';
import 'types_and_small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kAccent = Color(0xFF1ABCBD);
const _kBorder = Color(0xFF252830);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);

const _kSevInfo = Color(0xFF60A5FA);
const _kSevWarning = Color(0xFFF59E0B);
const _kSevCritical = Color(0xFFEF4444);
const _kAutoFill = Color(0xFFBB86FC);

Color _sevColor(String s) {
  switch (s) {
    case 'critical':
      return _kSevCritical;
    case 'warning':
      return _kSevWarning;
    default:
      return _kSevInfo;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionParamStore
// ─────────────────────────────────────────────────────────────────────────────
class SessionParamStore {
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'session_params.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE session_params (
          id          TEXT PRIMARY KEY,
          session_id  TEXT NOT NULL,
          label       TEXT NOT NULL,
          type        TEXT NOT NULL,
          left_label  TEXT,
          right_label TEXT
        )
      '''),
    );
    return _db!;
  }

  static Future<void> upsert(
      String sessionId, Map<String, dynamic> param) async {
    final db = await _open();
    await db.insert(
      'session_params',
      {
        'id': param['id']?.toString() ?? '',
        'session_id': sessionId,
        'label': param['label']?.toString() ?? '',
        'type': param['type']?.toString() ?? '',
        'left_label': param['left_label']?.toString(),
        'right_label': param['right_label']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getAll(
      String sessionId, String excludeId) async {
    final db = await _open();
    final rows = await db.query(
      'session_params',
      where: 'session_id = ? AND id != ?',
      whereArgs: [sessionId, excludeId],
    );
    return rows;
  }

  static Future<void> clearSession(String sessionId) async {
    final db = await _open();
    await db.delete('session_params',
        where: 'session_id = ?', whereArgs: [sessionId]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PropertyBuilderPage
// ─────────────────────────────────────────────────────────────────────────────
class PropertyBuilderPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final void Function(Map<String, dynamic>) onSave;
  final String sessionId;

  const PropertyBuilderPage({
    required this.onSave,
    required this.sessionId,
    this.existing,
    super.key,
  });

  static Future<void> clearSession(String sessionId) =>
      SessionParamStore.clearSession(sessionId);

  @override
  State<PropertyBuilderPage> createState() => PropertyBuilderPageState();
}

class PropertyBuilderPageState extends State<PropertyBuilderPage> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _hintCtrl = TextEditingController();
  final _leftLabelCtrl = TextEditingController();
  final _rightLabelCtrl = TextEditingController();
  final _minCtrl = TextEditingController(text: '0');
  final _maxCtrl = TextEditingController(text: '100');

  // Expected range — number / slider
  final _expMinCtrl = TextEditingController();
  final _expAvgCtrl = TextEditingController();
  final _expMaxCtrl = TextEditingController();
  // Expected range — dual_text left
  final _leftExpMinCtrl = TextEditingController();
  final _leftExpAvgCtrl = TextEditingController();
  final _leftExpMaxCtrl = TextEditingController();
  // Expected range — dual_text right
  final _rightExpMinCtrl = TextEditingController();
  final _rightExpAvgCtrl = TextEditingController();
  final _rightExpMaxCtrl = TextEditingController();

  // ── AutoFill ───────────────────────────────────────────────────────────────
  /// Raw expression with ${paramId_paramName} tokens — used for eval at read time.
  final _exprCtrl = TextEditingController();

  /// Human-readable display expression — param names + operators, shown in editor.
  final _displayExprCtrl = TextEditingController();

  final _exprFocus = FocusNode();

  /// True only after the user explicitly taps "Save Expression".
  bool _autoFillEnabled = false;

  /// Tracks whether the expression has unsaved changes since last save.
  bool _exprDirty = false;

  String? _exprError;
  List<Map<String, dynamic>> _sessionParams = [];

  // Keeps a parallel list of "display-token" boundaries so DEL can delete
  // entire name-tokens from _displayExprCtrl in sync with raw ${...} tokens.
  // Each entry: {'raw': '${id_name}', 'display': 'name'}
  final List<Map<String, String>> _insertedTokens = [];

  String _type = 'number';
  bool _required = true;
  bool _captureImage = false;
  final List<String> _options = [];
  final List<Map<String, dynamic>> _constraints = [];
  bool _constraintsExpanded = false;
  bool _autoFillExpanded = false;
  bool _rawExprVisible = false; // toggle to show raw token expression

  static const _types = [
    TypeMeta('number', 'Number', Icons.pin_outlined),
    TypeMeta('text', 'Text', Icons.text_fields),
    TypeMeta('dropdown', 'Dropdown', Icons.arrow_drop_down_circle_outlined),
    TypeMeta('dual_text', 'Dual Input', Icons.view_column_outlined),
    TypeMeta('slider', 'Slider', Icons.linear_scale),
    TypeMeta('multiline', 'Multiline', Icons.notes),
  ];

  bool get _supportsAutoFill =>
      _type == 'number' || _type == 'slider' || _type == 'dual_text';

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    for (final c in _allControllers) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }

    // Mark dirty when user types directly into display expr field
    _displayExprCtrl.addListener(() {
      if (mounted) setState(() => _exprDirty = true);
    });
    _exprCtrl.addListener(() {
      if (mounted) setState(() => _exprError = _validateExpr(_exprCtrl.text));
    });

    if (widget.existing != null) {
      final ep = widget.existing!;
      _labelCtrl.text = ep['label'] ?? '';
      _hintCtrl.text = ep['hint'] ?? '';
      _type = ep['type'] ?? 'number';
      _required = ep['required'] == true;
      _captureImage = ep['capture_image'] == true;
      _leftLabelCtrl.text = ep['left_label'] ?? 'Before';
      _rightLabelCtrl.text = ep['right_label'] ?? 'After';
      _minCtrl.text = (ep['min'] ?? 0).toString();
      _maxCtrl.text = (ep['max'] ?? 100).toString();
      _expMinCtrl.text = ep['expected_min']?.toString() ?? '';
      _expAvgCtrl.text = ep['expected_avg']?.toString() ?? '';
      _expMaxCtrl.text = ep['expected_max']?.toString() ?? '';
      _leftExpMinCtrl.text = ep['left_expected_min']?.toString() ?? '';
      _leftExpAvgCtrl.text = ep['left_expected_avg']?.toString() ?? '';
      _leftExpMaxCtrl.text = ep['left_expected_max']?.toString() ?? '';
      _rightExpMinCtrl.text = ep['right_expected_min']?.toString() ?? '';
      _rightExpAvgCtrl.text = ep['right_expected_avg']?.toString() ?? '';
      _rightExpMaxCtrl.text = ep['right_expected_max']?.toString() ?? '';

      // AutoFill — restore both expressions
      _autoFillEnabled = ep['autofill'] == true;
      _exprCtrl.text = ep['autofill_expression']?.toString() ?? '';
      _displayExprCtrl.text =
          ep['autofill_expression_display']?.toString() ?? '';

      if (_autoFillEnabled) {
        _autoFillExpanded = true;
        _exprDirty = false; // loaded from saved state, not dirty
      }

      if (ep['options'] != null) {
        _options.addAll(List<String>.from(ep['options'] as List));
      }
      if (ep['constraints'] != null) {
        _constraints.addAll(
          (ep['constraints'] as List)
              .map((e) => deepCast(e) as Map<String, dynamic>),
        );
        if (_constraints.isNotEmpty) _constraintsExpanded = true;
      }
    }

    _loadSessionParams();
  }

  List<TextEditingController> get _allControllers => [
        _labelCtrl,
        _hintCtrl,
        _leftLabelCtrl,
        _rightLabelCtrl,
        _minCtrl,
        _maxCtrl,
        _expMinCtrl,
        _expAvgCtrl,
        _expMaxCtrl,
        _leftExpMinCtrl,
        _leftExpAvgCtrl,
        _leftExpMaxCtrl,
        _rightExpMinCtrl,
        _rightExpAvgCtrl,
        _rightExpMaxCtrl,
      ];

  Future<void> _loadSessionParams() async {
    final myId = widget.existing?['id']?.toString() ?? '';
    final rows = await SessionParamStore.getAll(widget.sessionId, myId);
    if (mounted) setState(() => _sessionParams = rows);
  }

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.dispose();
    }
    _exprCtrl.dispose();
    _displayExprCtrl.dispose();
    _exprFocus.dispose();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  bool get _isNumerical => _type == 'number' || _type == 'slider';
  bool get _isDualText => _type == 'dual_text';

  double? _parseOpt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  String? _validateExpr(String expr) {
    if (expr.trim().isEmpty) return null;
    int depth = 0;
    for (final ch in expr.characters) {
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (depth < 0) return 'Unmatched closing parenthesis';
    }
    if (depth != 0) return 'Unmatched opening parenthesis';
    final sanitized = expr.replaceAll(RegExp(r'\$\{[^}]+\}'), '1');
    if (!RegExp(r'^[\d\s\+\-\*\/\(\)\.]+$').hasMatch(sanitized)) {
      return 'Expression contains invalid characters';
    }
    return null;
  }

  // ── Insert at cursor — writes to BOTH controllers ──────────────────────────

  /// Insert a raw token (e.g. `${id_Name}`) into _exprCtrl and the
  /// human display label (e.g. `Name`) into _displayExprCtrl, both at
  /// the current cursor position.
  void _insertTokenAtCursor(String rawToken, String displayLabel) {
    _insertRaw(rawToken);
    _insertDisplay(displayLabel);
    setState(() => _exprDirty = true);
    _exprFocus.requestFocus();
  }

  /// Insert a plain string (operator / number) into BOTH controllers.
  void _insertAtCursor(String text) {
    _insertRaw(text);
    _insertDisplay(text);
    setState(() => _exprDirty = true);
    _exprFocus.requestFocus();
  }

  void _insertRaw(String text) {
    final ctrl = _exprCtrl;
    final sel = ctrl.selection;
    final current = ctrl.text;
    final start = sel.start < 0 ? current.length : sel.start;
    final end = sel.end < 0 ? current.length : sel.end;
    final newText = current.replaceRange(start, end, text);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  void _insertDisplay(String text) {
    final ctrl = _displayExprCtrl;
    final current = ctrl.text;
    ctrl.value = TextEditingValue(
      text: current + text,
      selection: TextSelection.collapsed(offset: current.length + text.length),
    );
  }

  // ── Delete — removes full token from raw, matching part from display ───────

  void _deleteAtCursor() {
    // Delete from raw expression
    final ctrl = _exprCtrl;
    final sel = ctrl.selection;
    final current = ctrl.text;
    if (current.isEmpty) return;
    final start = sel.start < 0 ? current.length : sel.start;
    final end = sel.end < 0 ? current.length : sel.end;

    if (start != end) {
      ctrl.value = TextEditingValue(
        text: current.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      final before = current.substring(0, start);
      final tokenMatch = RegExp(r'\$\{[^}]*\}$').firstMatch(before);
      if (tokenMatch != null) {
        // Deleted a whole ${...} token from raw
        final tokenStart = tokenMatch.start;
        ctrl.value = TextEditingValue(
          text: current.replaceRange(tokenStart, start, ''),
          selection: TextSelection.collapsed(offset: tokenStart),
        );
        // Also delete the matching display name token from _displayExprCtrl
        _deleteLastDisplayToken();
      } else {
        ctrl.value = TextEditingValue(
          text: current.replaceRange(start - 1, start, ''),
          selection: TextSelection.collapsed(offset: start - 1),
        );
        // Delete one char from display too
        final dCtrl = _displayExprCtrl;
        if (dCtrl.text.isNotEmpty) {
          dCtrl.value = TextEditingValue(
            text: dCtrl.text.substring(0, dCtrl.text.length - 1),
            selection:
                TextSelection.collapsed(offset: dCtrl.text.length - 1),
          );
        }
      }
    }

    setState(() => _exprDirty = true);
    _exprFocus.requestFocus();
  }

  /// Removes the last bracketed name token from the display expression.
  /// Display tokens are wrapped like [Name] so we can find them.
  void _deleteLastDisplayToken() {
    final ctrl = _displayExprCtrl;
    final text = ctrl.text;
    // Try to find a trailing [...] block first
    final tokenMatch = RegExp(r'\[[^\]]+\]$').firstMatch(text);
    if (tokenMatch != null) {
      ctrl.value = TextEditingValue(
        text: text.substring(0, tokenMatch.start),
        selection: TextSelection.collapsed(offset: tokenMatch.start),
      );
    } else if (text.isNotEmpty) {
      ctrl.value = TextEditingValue(
        text: text.substring(0, text.length - 1),
        selection: TextSelection.collapsed(offset: text.length - 1),
      );
    }
  }

  // ── Save expression — commits expression and sets autofill: true ──────────

  void _saveExpression() {
    final rawExpr = _exprCtrl.text.trim();
    final displayExpr = _displayExprCtrl.text.trim();

    if (rawExpr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Expression is empty — nothing to save.',
            style: TextStyle(color: _kText)),
        backgroundColor: _kWarn,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final err = _validateExpr(rawExpr);
    if (err != null) {
      setState(() => _exprError = err);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Expression error: $err',
            style: const TextStyle(color: _kText)),
        backgroundColor: _kDanger,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() {
      _autoFillEnabled = true;
      _exprDirty = false;
      _exprError = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, size: 16, color: _kAutoFill),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'AutoFill expression saved — autofill: true',
            style: GoogleFonts.inter(color: _kText, fontSize: 13),
          ),
        ),
      ]),
      backgroundColor: _kSurface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: _kAutoFill),
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Param selected from dropdown ──────────────────────────────────────────

  Future<void> _onParamSelected(Map<String, dynamic>? param) async {
    if (param == null) return;
    final id = param['id']?.toString() ?? '';
    final label = param['label']?.toString() ?? '';
    final type = param['type']?.toString() ?? '';

    if (type == 'dual_text') {
      final side = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: _kCard,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) {
          final leftLabel =
              (param['left_label']?.toString().trim().isEmpty ?? true)
                  ? 'Before'
                  : param['left_label'];
          final rightLabel =
              (param['right_label']?.toString().trim().isEmpty ?? true)
                  ? 'After'
                  : param['right_label'];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: _kBorder,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('Which side of "$label"?',
                    style: GoogleFonts.inter(
                        color: _kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Choose the column whose value to use in the expression.',
                    style: const TextStyle(color: _kSub, fontSize: 12)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                      child: _SideButton(
                          label: '$leftLabel (Left)',
                          icon: Icons.align_horizontal_left_outlined,
                          color: _kWarn,
                          onTap: () => Navigator.pop(context, 'left'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _SideButton(
                          label: '$rightLabel (Right)',
                          icon: Icons.align_horizontal_right_outlined,
                          color: _kAccent,
                          onTap: () => Navigator.pop(context, 'right'))),
                ]),
              ]),
            ),
          );
        },
      );
      if (side == null) return;
      // Raw: ${id_label_side}  Display: [label·side]
      _insertTokenAtCursor('\${${id}_${label}_$side}', '[$label·$side]');
    } else {
      // Raw: ${id_label}  Display: [label]
      _insertTokenAtCursor('\${${id}_$label}', '[$label]');
    }
  }

  // ── Clear expression ───────────────────────────────────────────────────────

  void _clearExpression() {
    setState(() {
      _exprCtrl.clear();
      _displayExprCtrl.clear();
      _insertedTokens.clear();
      _autoFillEnabled = false;
      _exprDirty = false;
      _exprError = null;
    });
  }

  // ── Dropdown option management ─────────────────────────────────────────────

  Future<void> _addOrEditOption({int? idx}) async {
    final ctrl = TextEditingController(text: idx != null ? _options[idx] : '');
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: Text(idx != null ? 'Edit Option' : 'Add Option',
            style:
                GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: _kText),
          cursorColor: _kAccent,
          decoration:
              compactDeco(hint: 'Option text', icon: Icons.label_outline),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _kSub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isEmpty) return;
              setState(
                  () => idx != null ? _options[idx] = val : _options.add(val));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Constraint dialog ──────────────────────────────────────────────────────

  Future<void> _addOrEditConstraint({int? idx}) async {
    final existing = idx != null ? _constraints[idx] : null;
    final ops = opsForType(_type);

    String selectedOp = existing?['op']?.toString() ?? ops.first.value;
    String severity = existing?['severity']?.toString() ?? 'warning';
    final valueCtrl =
        TextEditingController(text: existing?['value']?.toString() ?? '');
    final errorMsgCtrl =
        TextEditingController(text: existing?['message']?.toString() ?? '');
    final alertTitleCtrl =
        TextEditingController(text: existing?['alert_title']?.toString() ?? '');

    bool storeHistory = existing?['store_history'] == true;
    bool showDashboard = existing?['show_dashboard_alert'] == true;
    bool playSound = existing?['play_sound_on_violation'] == true;
    bool captureOnViolation = existing?['capture_image_on_violation'] == true;
    bool blockSubmission = existing?['block_submission'] == true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          Widget checkTile({
            required bool value,
            required String label,
            required String sub,
            required IconData icon,
            required Color activeColor,
            required ValueChanged<bool?> onChanged,
          }) {
            return GestureDetector(
              onTap: () => onChanged(!value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: value ? activeColor.withOpacity(0.08) : _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: value ? activeColor.withOpacity(0.45) : _kBorder,
                    width: value ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Icon(icon, size: 16, color: value ? activeColor : _kSub),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(label,
                            style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: value ? activeColor : _kText)),
                        Text(sub,
                            style:
                                GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
                      ])),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: value ? activeColor : Colors.transparent,
                      border: Border.all(
                          color: value ? activeColor : _kBorder, width: 2),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: value
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white)
                        : null,
                  ),
                ]),
              ),
            );
          }

          return Dialog(
            backgroundColor: _kCard,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(18)),
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: const Color(0xFFBB86FC).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.rule_outlined,
                          size: 15, color: Color(0xFFBB86FC)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                      idx != null ? 'Edit Constraint' : 'Add Constraint',
                      style: GoogleFonts.dmSans(
                          color: _kText,
                          fontWeight: FontWeight.w700,
                          fontSize: 15),
                    )),
                    GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(Icons.close_rounded,
                            color: _kSub, size: 18)),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _dlgLabel('Operator'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: ops.map((op) {
                            final sel = selectedOp == op.value;
                            return GestureDetector(
                              onTap: () => setDlg(() => selectedOp = op.value),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 130),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? _kAccent.withOpacity(0.14)
                                      : _kSurface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: sel ? _kAccent : _kBorder,
                                      width: sel ? 1.5 : 1),
                                ),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(op.symbol,
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  sel ? _kAccent : _kText)),
                                      const SizedBox(height: 2),
                                      Text(op.label,
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: sel ? _kAccent : _kSub)),
                                    ]),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        _dlgLabel('Threshold Value *'),
                        const SizedBox(height: 8),
                        _DarkTextField(
                          ctrl: valueCtrl,
                          hint: (_type == 'number' || _type == 'slider')
                              ? 'e.g. 80'
                              : 'e.g. OK',
                          icon: Icons.tag_rounded,
                          keyboardType: (_type == 'number' || _type == 'slider')
                              ? const TextInputType.numberWithOptions(
                                  decimal: true)
                              : TextInputType.text,
                        ),
                        const SizedBox(height: 16),
                        _dlgLabel('Severity'),
                        const SizedBox(height: 8),
                        Row(children: [
                          for (final sev in ['info', 'warning', 'critical'])
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setDlg(() => severity = sev),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  margin: EdgeInsets.only(
                                      right: sev == 'critical' ? 0 : 8),
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: severity == sev
                                        ? _sevColor(sev).withOpacity(0.14)
                                        : _kSurface,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                        color: severity == sev
                                            ? _sevColor(sev)
                                            : _kBorder,
                                        width: severity == sev ? 1.5 : 1),
                                  ),
                                  child: Center(
                                      child: Text(
                                    sev[0].toUpperCase() + sev.substring(1),
                                    style: GoogleFonts.dmSans(
                                        color: severity == sev
                                            ? _sevColor(sev)
                                            : _kSub,
                                        fontWeight: severity == sev
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                        fontSize: 12),
                                  )),
                                ),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 16),
                        _dlgLabel('Alert Title  (optional)'),
                        const SizedBox(height: 8),
                        _DarkTextField(
                            ctrl: alertTitleCtrl,
                            hint: 'e.g. Overheat Detected',
                            icon: Icons.title_rounded),
                        const SizedBox(height: 16),
                        _dlgLabel('Error Message  (optional)'),
                        const SizedBox(height: 8),
                        _DarkTextField(
                            ctrl: errorMsgCtrl,
                            hint: 'e.g. Temperature exceeded safe limit',
                            icon: Icons.warning_amber_outlined,
                            maxLines: 2),
                        const SizedBox(height: 18),
                        _dlgLabel('BEHAVIOUR ON VIOLATION'),
                        const SizedBox(height: 10),
                        checkTile(
                            value: storeHistory,
                            label: 'Store history',
                            sub: 'Save this violation as an Alert record in DB',
                            icon: Icons.history_rounded,
                            activeColor: _kAccent,
                            onChanged: (v) =>
                                setDlg(() => storeHistory = v ?? false)),
                        checkTile(
                            value: showDashboard,
                            label: 'Show dashboard alert',
                            sub: 'Surface this alert on the dashboard',
                            icon: Icons.dashboard_outlined,
                            activeColor: _kSevWarning,
                            onChanged: (v) =>
                                setDlg(() => showDashboard = v ?? false)),
                        checkTile(
                            value: playSound,
                            label: 'Play sound on violation',
                            sub:
                                'Trigger beep / alert sound when constraint fails',
                            icon: Icons.volume_up_outlined,
                            activeColor: _kSevCritical,
                            onChanged: (v) =>
                                setDlg(() => playSound = v ?? false)),
                        checkTile(
                            value: captureOnViolation,
                            label: 'Capture image on violation',
                            sub:
                                'Force inspector to take photo when this fires',
                            icon: Icons.camera_alt_outlined,
                            activeColor: _kSevWarning,
                            onChanged: (v) =>
                                setDlg(() => captureOnViolation = v ?? false)),
                        checkTile(
                            value: blockSubmission,
                            label: 'Block submission',
                            sub: 'Prevent saving the reading until corrected',
                            icon: Icons.block_rounded,
                            activeColor: _kSevCritical,
                            onChanged: (v) =>
                                setDlg(() => blockSubmission = v ?? false)),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(18)),
                    border: Border(top: BorderSide(color: _kBorder)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Cancel',
                                style: GoogleFonts.dmSans(color: _kSub))),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            final val = valueCtrl.text.trim();
                            if (val.isEmpty) return;
                            final c = {
                              'id': existing?['id'] ??
                                  'c_${DateTime.now().millisecondsSinceEpoch}',
                              'op': selectedOp,
                              'value': val,
                              'severity': severity,
                              'alert_title': alertTitleCtrl.text.trim(),
                              'message': errorMsgCtrl.text.trim(),
                              'store_history': storeHistory,
                              'show_dashboard_alert': showDashboard,
                              'play_sound_on_violation': playSound,
                              'capture_image_on_violation': captureOnViolation,
                              'block_submission': blockSubmission,
                            };
                            setState(() {
                              idx != null
                                  ? _constraints[idx] = c
                                  : _constraints.add(c);
                            });
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                                color: _kAccent,
                                borderRadius: BorderRadius.circular(9)),
                            child: Text(idx != null ? 'Update' : 'Add',
                                style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                        ),
                      ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _deleteConstraint(int idx) =>
      setState(() => _constraints.removeAt(idx));

  // ── Save (final) ───────────────────────────────────────────────────────────

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_type == 'dropdown' && _options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add at least one dropdown option',
            style: TextStyle(color: _kText)),
        backgroundColor: _kWarn,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // If there's an unsaved expression, warn and block
    if (_exprDirty && _exprCtrl.text.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: _kWarn),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
            'You have an unsaved AutoFill expression. Tap "Save Expression" first.',
            style: GoogleFonts.inter(color: _kText, fontSize: 13),
          )),
        ]),
        backgroundColor: _kSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: _kWarn),
            borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Save now',
          textColor: _kAutoFill,
          onPressed: _saveExpression,
        ),
      ));
      return;
    }

    // Validate expression if autofill is enabled
    if (_autoFillEnabled && _exprCtrl.text.trim().isNotEmpty) {
      final err = _validateExpr(_exprCtrl.text.trim());
      if (err != null) {
        setState(() => _exprError = err);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('AutoFill expression error: $err',
              style: const TextStyle(color: _kText)),
          backgroundColor: _kDanger,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
    }

    final id = widget.existing?['id'] ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // autofill is true ONLY if the user explicitly saved the expression
    final hasExpression =
        _autoFillEnabled && _exprCtrl.text.trim().isNotEmpty;

    final prop = <String, dynamic>{
      'id': id,
      'label': _labelCtrl.text.trim(),
      'hint': _hintCtrl.text.trim(),
      'type': _type,
      'required': _required,
      'capture_image': _captureImage,
      'options': List<String>.from(_options),
      if (_type == 'dual_text') ...{
        'left_label': _leftLabelCtrl.text.trim().isEmpty
            ? 'Before'
            : _leftLabelCtrl.text.trim(),
        'right_label': _rightLabelCtrl.text.trim().isEmpty
            ? 'After'
            : _rightLabelCtrl.text.trim(),
      },
      if (_type == 'slider') ...{
        'min': double.tryParse(_minCtrl.text.trim()) ?? 0,
        'max': double.tryParse(_maxCtrl.text.trim()) ?? 100,
      },
      if (_isNumerical) ...{
        if (_parseOpt(_expMinCtrl) != null)
          'expected_min': _parseOpt(_expMinCtrl),
        if (_parseOpt(_expAvgCtrl) != null)
          'expected_avg': _parseOpt(_expAvgCtrl),
        if (_parseOpt(_expMaxCtrl) != null)
          'expected_max': _parseOpt(_expMaxCtrl),
      },
      if (_isDualText) ...{
        if (_parseOpt(_leftExpMinCtrl) != null)
          'left_expected_min': _parseOpt(_leftExpMinCtrl),
        if (_parseOpt(_leftExpAvgCtrl) != null)
          'left_expected_avg': _parseOpt(_leftExpAvgCtrl),
        if (_parseOpt(_leftExpMaxCtrl) != null)
          'left_expected_max': _parseOpt(_leftExpMaxCtrl),
        if (_parseOpt(_rightExpMinCtrl) != null)
          'right_expected_min': _parseOpt(_rightExpMinCtrl),
        if (_parseOpt(_rightExpAvgCtrl) != null)
          'right_expected_avg': _parseOpt(_rightExpAvgCtrl),
        if (_parseOpt(_rightExpMaxCtrl) != null)
          'right_expected_max': _parseOpt(_rightExpMaxCtrl),
      },
      // AutoFill fields
      'autofill': hasExpression, // true ONLY after explicit save
      if (hasExpression) ...{
        // Raw expression with ${paramId_paramName} tokens — used for eval
        'autofill_expression': _exprCtrl.text.trim(),
        // Human-readable display expression — used for UI labels
        'autofill_expression_display': _displayExprCtrl.text.trim(),
      },
      'constraints': List<Map<String, dynamic>>.from(_constraints),
    };

    SessionParamStore.upsert(widget.sessionId, prop);
    widget.onSave(prop);
    Navigator.pop(context);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(
          widget.existing != null ? 'Edit Parameter' : 'New Parameter',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w700, fontSize: 17, color: _kText),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _kAccent,
                    fontSize: 15)),
          ),
        ],
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: _kAccent, surface: _kSurface, onSurface: _kText),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sl('Parameter Type'),
                const SizedBox(height: 10),
                _buildTypePicker(),

                const SizedBox(height: 20),
                _sl('Label *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _labelCtrl,
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  decoration: compactDeco(
                      hint: 'e.g. Oil Temperature',
                      icon: Icons.label_outline),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Label is required' : null,
                ),

                const SizedBox(height: 16),
                _sl('Hint / Helper Text'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hintCtrl,
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  decoration: compactDeco(
                      hint: 'e.g. Enter between 5 – 10',
                      icon: Icons.info_outline),
                ),

                const SizedBox(height: 16),

                // Required toggle
                Container(
                  decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder)),
                  child: SwitchListTile(
                    title: Text('Required field',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: _kText)),
                    subtitle: Text(
                      _required
                          ? 'Inspector must fill this in'
                          : 'Optional – can be skipped',
                      style: const TextStyle(fontSize: 12, color: _kSub),
                    ),
                    activeColor: _kAccent,
                    value: _required,
                    onChanged: _captureImage
                        ? null
                        : (v) => setState(() => _required = v),
                  ),
                ),

                const SizedBox(height: 12),

                // Capture image toggle
                Container(
                  decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder)),
                  child: SwitchListTile(
                    value: _captureImage,
                    activeColor: _kAccent,
                    title: Text('Capture Image',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: _kText)),
                    subtitle: Text(
                      _captureImage
                          ? 'Inspector must capture image for this parameter'
                          : 'No image required',
                      style: const TextStyle(color: _kSub, fontSize: 12),
                    ),
                    onChanged: (v) => setState(() {
                      _captureImage = v;
                      if (v) _required = true;
                    }),
                  ),
                ),

                const SizedBox(height: 20),
                _buildTypeConfig(),

                if (_isNumerical || _isDualText) ...[
                  const SizedBox(height: 20),
                  _buildExpectedRange(),
                ],

                if (_supportsAutoFill) ...[
                  const SizedBox(height: 20),
                  _buildAutoFillSection(),
                ],

                const SizedBox(height: 24),
                _buildConstraintsSection(),

                const SizedBox(height: 28),
                _sl('Live Preview  (updates as you type)'),
                const SizedBox(height: 10),
                _buildLivePreview(),
                const SizedBox(height: 36),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _save,
                    child: Text(
                      widget.existing != null
                          ? 'Update Parameter'
                          : 'Add Parameter',
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Type picker ────────────────────────────────────────────────────────────

  Widget _buildTypePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((t) {
        final selected = _type == t.value;
        final color = _typeColorFor(t.value);
        return GestureDetector(
          onTap: () => setState(() {
            _type = t.value;
            _constraints.clear();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.15) : _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? color : _kBorder,
                  width: selected ? 2 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(t.icon, size: 16, color: selected ? color : _kSub),
              const SizedBox(width: 6),
              Text(t.label,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? color : _kText)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTypeConfig() {
    switch (_type) {
      case 'dropdown':
        return _dropdownConfig();
      case 'dual_text':
        return _dualTextConfig();
      case 'slider':
        return _sliderConfig();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _dropdownConfig() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sl('Dropdown Options *'),
          const SizedBox(height: 4),
          const Text('Drag to reorder • Pencil to rename • Bin to delete',
              style: TextStyle(fontSize: 11, color: _kSub)),
          const SizedBox(height: 10),
          if (_options.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder)),
              child: const Center(
                  child: Text('No options yet',
                      style: TextStyle(color: _kSub, fontSize: 13))),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _options.length,
              onReorder: (o, n) {
                setState(() {
                  if (n > o) n--;
                  final i = _options.removeAt(o);
                  _options.insert(n, i);
                });
              },
              itemBuilder: (_, i) => ListTile(
                key: ValueKey('opt-$i-${_options[i]}'),
                tileColor: _kSurface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                leading:
                    const Icon(Icons.drag_indicator, size: 18, color: _kSub),
                title: Text(_options[i],
                    style: GoogleFonts.inter(fontSize: 14, color: _kText)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: _kAccent),
                      onPressed: () => _addOrEditOption(idx: i)),
                  IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: _kDanger),
                      onPressed: () =>
                          setState(() => _options.removeAt(i))),
                ]),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kAccent),
                foregroundColor: _kAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add Option'),
              onPressed: _addOrEditOption,
            ),
          ),
        ],
      );

  Widget _dualTextConfig() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sl('Column Labels'),
          const SizedBox(height: 4),
          const Text('One label row, two text boxes in a single row.',
              style: TextStyle(fontSize: 11, color: _kSub)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextFormField(
              controller: _leftLabelCtrl,
              style: const TextStyle(color: _kText),
              cursorColor: _kAccent,
              decoration: compactDeco(
                  hint: 'Left (e.g. Before)',
                  icon: Icons.align_horizontal_left_outlined),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: TextFormField(
              controller: _rightLabelCtrl,
              style: const TextStyle(color: _kText),
              cursorColor: _kAccent,
              decoration: compactDeco(
                  hint: 'Right (e.g. After)',
                  icon: Icons.align_horizontal_right_outlined),
              validator: (v) => v!.trim().isEmpty ? 'Required' : null,
            )),
          ]),
        ],
      );

  Widget _sliderConfig() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sl('Slider Range'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: TextFormField(
              controller: _minCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _kText),
              cursorColor: _kAccent,
              decoration: compactDeco(hint: 'Min', icon: Icons.first_page),
              validator: (v) =>
                  double.tryParse(v ?? '') == null ? 'Invalid' : null,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: TextFormField(
              controller: _maxCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: _kText),
              cursorColor: _kAccent,
              decoration: compactDeco(hint: 'Max', icon: Icons.last_page),
              validator: (v) {
                final max = double.tryParse(v ?? '');
                if (max == null) return 'Invalid';
                if (max <= (double.tryParse(_minCtrl.text) ?? 0)) {
                  return 'Must be > Min';
                }
                return null;
              },
            )),
          ]),
        ],
      );

  Widget _buildExpectedRange() {
    const numKb = TextInputType.numberWithOptions(decimal: true);

    if (_isNumerical) {
      return _ExpectedRangeCard(
        title: 'Expected Range',
        subtitle: 'Optional reference values used for alerts and dashboards.',
        children: [
          _RangeRow(
            minCtrl: _expMinCtrl,
            avgCtrl: _expAvgCtrl,
            maxCtrl: _expMaxCtrl,
            keyboardType: numKb,
          ),
        ],
      );
    }

    final leftLabel = _leftLabelCtrl.text.trim().isEmpty
        ? 'Left (Before)'
        : _leftLabelCtrl.text.trim();
    final rightLabel = _rightLabelCtrl.text.trim().isEmpty
        ? 'Right (After)'
        : _rightLabelCtrl.text.trim();

    return _ExpectedRangeCard(
      title: 'Expected Range',
      subtitle:
          'Set Min / Avg / Max for each column. Only values you enter will be stored.',
      children: [
        _sl('$leftLabel column'),
        const SizedBox(height: 8),
        _RangeRow(
          minCtrl: _leftExpMinCtrl,
          avgCtrl: _leftExpAvgCtrl,
          maxCtrl: _leftExpMaxCtrl,
          keyboardType: numKb,
        ),
        const SizedBox(height: 14),
        _sl('$rightLabel column'),
        const SizedBox(height: 8),
        _RangeRow(
          minCtrl: _rightExpMinCtrl,
          avgCtrl: _rightExpAvgCtrl,
          maxCtrl: _rightExpMaxCtrl,
          keyboardType: numKb,
        ),
      ],
    );
  }

  // ── ✨ AutoFill Expression Editor (REDESIGNED) ─────────────────────────────

  Widget _buildAutoFillSection() {
    return Container(
      decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _autoFillEnabled
                  ? _kAutoFill.withOpacity(0.5)
                  : _autoFillExpanded
                      ? _kAutoFill.withOpacity(0.25)
                      : _kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        InkWell(
          onTap: () =>
              setState(() => _autoFillExpanded = !_autoFillExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: _kAutoFill.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.auto_fix_high_outlined,
                    size: 16, color: _kAutoFill),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('AutoFill Expression',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kText)),
                    Text(
                      _autoFillEnabled && _exprCtrl.text.trim().isNotEmpty
                          ? 'Active — autofill: true'
                          : _exprDirty
                              ? 'Unsaved changes — tap "Save Expression"'
                              : 'Auto-calculate this field from other parameters',
                      style: TextStyle(
                          fontSize: 11,
                          color: _autoFillEnabled &&
                                  _exprCtrl.text.trim().isNotEmpty
                              ? _kAutoFill
                              : _exprDirty
                                  ? _kWarn
                                  : _kSub),
                    ),
                  ])),
              // Status badge
              if (_autoFillEnabled && _exprCtrl.text.trim().isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: _kAutoFill.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle_outline,
                        size: 11, color: _kAutoFill),
                    const SizedBox(width: 3),
                    Text('SAVED',
                        style: TextStyle(
                            fontSize: 10,
                            color: _kAutoFill,
                            fontWeight: FontWeight.w700)),
                  ]),
                )
              else if (_exprDirty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: _kWarn.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit_rounded, size: 11, color: _kWarn),
                    const SizedBox(width: 3),
                    Text('UNSAVED',
                        style: TextStyle(
                            fontSize: 10,
                            color: _kWarn,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              const SizedBox(width: 6),
              Icon(
                  _autoFillExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: _kSub),
            ]),
          ),
        ),

        // ── Expanded body ──
        if (_autoFillExpanded) ...[
          const Divider(height: 1, thickness: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _kAutoFill.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: _kAutoFill.withOpacity(0.2))),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: _kAutoFill),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                        'Select parameters from the dropdown and use the operator row / numpad to build your formula. '
                        'Tap "Save Expression" when done — only then will autofill: true be stored.',
                        style: const TextStyle(
                            fontSize: 11, color: _kSub, height: 1.5),
                      )),
                    ]),
              ),
              const SizedBox(height: 14),

              // ── Raw expression preview (collapsible, shown at top) ──
              if (_exprCtrl.text.trim().isNotEmpty) ...[
                _sl('Stored Token Expression  (eval-ready)'),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () =>
                      setState(() => _rawExprVisible = !_rawExprVisible),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kBg,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _kAutoFill.withOpacity(0.25)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.code_rounded,
                          size: 13, color: _kAutoFill),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _rawExprVisible
                            ? Text(
                                _exprCtrl.text,
                                style: GoogleFonts.sourceCodePro(
                                    fontSize: 11, color: _kAutoFill),
                              )
                            : Text(
                                'Tap to reveal raw \${token} expression',
                                style: const TextStyle(
                                    fontSize: 11, color: _kSub),
                              ),
                      ),
                      Icon(
                          _rawExprVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 14,
                          color: _kSub),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Param dropdown ──
              _sl('Insert Parameter'),
              const SizedBox(height: 8),
              _ParamDropdown(
                params: _sessionParams,
                onSelected: _onParamSelected,
              ),
              const SizedBox(height: 14),

              // ── Human-readable expression editor ──
              _sl('Expression  (edit below — param names shown as tags)'),
              const SizedBox(height: 8),
              _ExpressionDisplay(
                rawController: _exprCtrl,
                displayController: _displayExprCtrl,
                focusNode: _exprFocus,
                error: _exprError,
              ),
              const SizedBox(height: 10),

              // ── Operator row ──
              _OperatorRow(onInsert: _insertAtCursor),
              const SizedBox(height: 12),

              // ── Numpad ──
              _Numpad(
                onInsert: _insertAtCursor,
                onDelete: _deleteAtCursor,
              ),

              const SizedBox(height: 16),

              // ── SAVE EXPRESSION BUTTON ── (the main fix)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _autoFillEnabled && !_exprDirty
                        ? _kAutoFill.withOpacity(0.2)
                        : _kAutoFill,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: Icon(
                    _autoFillEnabled && !_exprDirty
                        ? Icons.check_circle_outline
                        : Icons.save_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _autoFillEnabled && !_exprDirty
                        ? 'Expression Saved  (autofill: true)'
                        : 'Save Expression',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: (_autoFillEnabled && !_exprDirty)
                      ? null // Already saved and no changes
                      : _saveExpression,
                ),
              ),

              // ── Clear button ──
              if (_exprCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kDanger),
                      foregroundColor: _kDanger,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('Clear Expression',
                        style: TextStyle(fontSize: 13)),
                    onPressed: _clearExpression,
                  ),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Constraints section ────────────────────────────────────────────────────

  Widget _buildConstraintsSection() {
    final ops = opsForType(_type);
    if (ops.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(
              () => _constraintsExpanded = !_constraintsExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: const Color(0xFFBB86FC).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.rule_outlined,
                    size: 16, color: Color(0xFFBB86FC)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Validation Constraints',
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kText)),
                    Text(
                      _constraints.isEmpty
                          ? 'Optional — add rules the inspector\'s input must satisfy'
                          : '${_constraints.length} constraint${_constraints.length == 1 ? '' : 's'} active',
                      style: const TextStyle(fontSize: 11, color: _kSub),
                    ),
                  ])),
              if (_constraints.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFBB86FC).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${_constraints.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFBB86FC),
                          fontWeight: FontWeight.w700)),
                ),
              const SizedBox(width: 6),
              Icon(
                  _constraintsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: _kSub),
            ]),
          ),
        ),

        if (_constraintsExpanded) ...[
          const Divider(height: 1, thickness: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('All constraints must pass (AND logic).',
                      style: TextStyle(fontSize: 11, color: _kSub)),
                  const SizedBox(height: 12),
                  if (_constraints.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _kBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder)),
                      child: const Center(
                          child: Text('No constraints yet',
                              style:
                                  TextStyle(fontSize: 12, color: _kSub))),
                    )
                  else
                    ...List.generate(_constraints.length, (i) {
                      final c = _constraints[i];
                      final op = c['op']?.toString() ?? '';
                      final val = c['value']?.toString() ?? '';
                      final msg = c['message']?.toString() ?? '';
                      final sev = c['severity']?.toString() ?? 'warning';
                      final sc = _sevColor(sev);

                      final flags = <_ConstraintFlag>[];
                      if (c['store_history'] == true)
                        flags.add(_ConstraintFlag(
                            Icons.history_rounded, _kAccent, 'Stored'));
                      if (c['show_dashboard_alert'] == true)
                        flags.add(_ConstraintFlag(
                            Icons.dashboard_outlined,
                            _kSevWarning,
                            'Dashboard'));
                      if (c['play_sound_on_violation'] == true)
                        flags.add(_ConstraintFlag(
                            Icons.volume_up_outlined,
                            _kSevCritical,
                            'Sound'));
                      if (c['capture_image_on_violation'] == true)
                        flags.add(_ConstraintFlag(
                            Icons.camera_alt_outlined,
                            _kSevWarning,
                            'Camera'));
                      if (c['block_submission'] == true)
                        flags.add(_ConstraintFlag(
                            Icons.block_rounded,
                            _kSevCritical,
                            'Blocks'));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                            color: _kBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: sc.withOpacity(0.3))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 8, 8),
                                child: Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: sc.withOpacity(0.13),
                                        borderRadius:
                                            BorderRadius.circular(5),
                                        border: Border.all(
                                            color: sc.withOpacity(0.4))),
                                    child: Text(sev.toUpperCase(),
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 8,
                                            color: sc,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8)),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFBB86FC)
                                            .withOpacity(0.13),
                                        borderRadius:
                                            BorderRadius.circular(7)),
                                    child: Center(
                                        child: Text(opSymbol(_type, op),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    Color(0xFFBB86FC)))),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            '${opLabel(_type, op)}  "$val"',
                                            style: GoogleFonts.dmSans(
                                                fontSize: 13,
                                                color: _kText,
                                                fontWeight:
                                                    FontWeight.w600)),
                                        if (msg.isNotEmpty)
                                          Text(msg,
                                              style: GoogleFonts.dmSans(
                                                  fontSize: 11,
                                                  color: _kSub)),
                                      ])),
                                  _iconTap(
                                      Icons.edit_outlined,
                                      _kAccent,
                                      () =>
                                          _addOrEditConstraint(idx: i)),
                                  _iconTap(
                                      Icons.delete_outline,
                                      _kDanger,
                                      () => _deleteConstraint(i)),
                                ]),
                              ),
                              if (flags.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 0, 12, 10),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: flags
                                        .map((f) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                  color:
                                                      f.color.withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                  border: Border.all(
                                                      color: f.color
                                                          .withOpacity(0.3))),
                                              child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(f.icon,
                                                        size: 10,
                                                        color: f.color),
                                                    const SizedBox(width: 4),
                                                    Text(f.label,
                                                        style: GoogleFonts
                                                            .spaceGrotesk(
                                                                fontSize: 8,
                                                                color: f.color,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    0.4)),
                                                  ]),
                                            ))
                                        .toList(),
                                  ),
                                ),
                            ]),
                      );
                    }),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                            color: Color(0xFFBB86FC)),
                        foregroundColor: const Color(0xFFBB86FC),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Constraint'),
                      onPressed: _addOrEditConstraint,
                    ),
                  ),
                ]),
          ),
        ],
      ]),
    );
  }

  // ── Live preview ───────────────────────────────────────────────────────────

  Widget _buildLivePreview() {
    final label = _labelCtrl.text.trim().isEmpty
        ? 'Parameter Label'
        : _labelCtrl.text.trim();
    final hint =
        _hintCtrl.text.trim().isEmpty ? 'Value…' : _hintCtrl.text.trim();

    return Container(
      decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      padding: const EdgeInsets.all(16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.22,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: _kText)),
                ),
              ),
              if (_required)
                const Padding(
                    padding: EdgeInsets.only(top: 10, right: 2),
                    child: Text(' *',
                        style: TextStyle(color: _kDanger, fontSize: 13))),
              Expanded(child: _liveInput(hint)),
            ]),
            if (_hintCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_hintCtrl.text.trim(),
                  style: const TextStyle(fontSize: 11, color: _kSub)),
            ],
            // AutoFill preview — show DISPLAY expression (human-readable)
            if (_autoFillEnabled &&
                _displayExprCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: _kAutoFill.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: _kAutoFill.withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.auto_fix_high_outlined,
                      size: 12, color: _kAutoFill),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'AutoFill: ${_displayExprCtrl.text.trim()}',
                      style: GoogleFonts.sourceCodePro(
                          fontSize: 11, color: _kAutoFill),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ],
          ]),
    );
  }

  Widget _liveInput(String hint) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder));
    final baseDec = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: _kSurface,
      hintStyle: const TextStyle(color: _kSub, fontSize: 13),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kAccent, width: 2)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    switch (_type) {
      case 'dropdown':
        final pv = _options.isNotEmpty ? _options.first : null;
        return DropdownButtonFormField<String>(
          value: pv,
          items: _options.isNotEmpty
              ? _options
                  .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(o,
                          style: const TextStyle(
                              color: _kText, fontSize: 13))))
                  .toList()
              : [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('Select…',
                          style:
                              TextStyle(color: _kSub, fontSize: 13)))
                ],
          onChanged: null,
          dropdownColor: _kCard,
          iconEnabledColor: _kSub,
          iconDisabledColor: _kSub,
          style: const TextStyle(color: _kText),
          decoration: baseDec.copyWith(
              hintText: _options.isEmpty ? 'Select…' : null),
        );

      case 'dual_text':
        final left = _leftLabelCtrl.text.trim().isEmpty
            ? 'Before'
            : _leftLabelCtrl.text.trim();
        final right = _rightLabelCtrl.text.trim().isEmpty
            ? 'After'
            : _rightLabelCtrl.text.trim();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(left,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kSub))),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(right,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kSub))),
              ]),
              const SizedBox(height: 5),
              Row(children: [
                Expanded(
                    child: TextField(
                        readOnly: true,
                        style:
                            const TextStyle(color: _kText, fontSize: 13),
                        decoration: baseDec.copyWith(hintText: left))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        readOnly: true,
                        style:
                            const TextStyle(color: _kText, fontSize: 13),
                        decoration: baseDec.copyWith(hintText: right))),
              ]),
            ]);

      case 'slider':
        final mn = double.tryParse(_minCtrl.text) ?? 0;
        final mx = double.tryParse(_maxCtrl.text) ?? 100;
        final sMx = mx > mn ? mx : mn + 1;
        return Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _kAccent,
              thumbColor: _kAccent,
              inactiveTrackColor: _kBorder,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: mn, min: mn, max: sMx, onChanged: null),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Text('$mn',
                style: const TextStyle(fontSize: 11, color: _kSub)),
            Text('$mx',
                style: const TextStyle(fontSize: 11, color: _kSub)),
          ]),
        ]);

      case 'multiline':
        return TextField(
            readOnly: true,
            maxLines: 3,
            style: const TextStyle(color: _kText, fontSize: 13),
            decoration: baseDec.copyWith(hintText: hint));

      default:
        return TextField(
            readOnly: true,
            keyboardType: _type == 'number'
                ? TextInputType.number
                : TextInputType.text,
            style: const TextStyle(color: _kText, fontSize: 13),
            decoration: baseDec.copyWith(hintText: hint));
    }
  }

  // ── tiny helpers ───────────────────────────────────────────────────────────

  Widget _sl(String t) => Text(t,
      style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kSub,
          letterSpacing: 0.9));

  Widget _dlgLabel(String t) => Text(t,
      style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kSub,
          letterSpacing: 0.8));

  Widget _iconTap(IconData icon, Color color, VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 18, color: color)));

  Color _typeColorFor(String t) =>
      const {
        'number': _kAccent,
        'text': _kSuccess,
        'dropdown': Color(0xFFBB86FC),
        'dual_text': _kWarn,
        'slider': Color(0xFF03DAC6),
        'multiline': Color(0xFF7986CB),
      }[t] ??
      _kSub;
}

// ─────────────────────────────────────────────────────────────────────────────
// _ParamDropdown
// ─────────────────────────────────────────────────────────────────────────────
class _ParamDropdown extends StatefulWidget {
  final List<Map<String, dynamic>> params;
  final Future<void> Function(Map<String, dynamic>? param) onSelected;

  const _ParamDropdown({required this.params, required this.onSelected});

  @override
  State<_ParamDropdown> createState() => _ParamDropdownState();
}

class _ParamDropdownState extends State<_ParamDropdown> {
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(children: [
          const Icon(Icons.data_object_rounded, size: 15, color: _kSub),
          const SizedBox(width: 8),
          Expanded(
            child: _selected == null
                ? const Text('Select a parameter to insert…',
                    style: TextStyle(color: _kSub, fontSize: 13))
                : Row(children: [
                    Text(
                        _selected!['label']?.toString() ?? '',
                        style: const TextStyle(
                            color: _kText, fontSize: 13)),
                    const SizedBox(width: 8),
                    _TypeChip(
                        type: _selected!['type']?.toString() ?? ''),
                  ]),
          ),
          const Icon(Icons.arrow_drop_down, color: _kSub, size: 20),
        ]),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _ParamPickerSheet(params: widget.params, current: _selected),
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      setState(() => _selected = null);
      return;
    }
    setState(() => _selected = picked);
    await widget.onSelected(picked);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ParamPickerSheet
// ─────────────────────────────────────────────────────────────────────────────
class _ParamPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> params;
  final Map<String, dynamic>? current;

  const _ParamPickerSheet({required this.params, this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _kBorder,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.data_object_rounded,
                    size: 16, color: _kAutoFill),
                const SizedBox(width: 8),
                Text('Select Parameter',
                    style: GoogleFonts.inter(
                        color: _kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                  'The parameter\'s live value will be substituted into the expression at read time.',
                  style: const TextStyle(color: _kSub, fontSize: 11)),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: _kBorder),
            _PickerTile(
              icon: Icons.block_outlined,
              label: 'None',
              subtitle: 'Clear selection',
              typeColor: _kSub,
              isSelected: current == null,
              onTap: () => Navigator.pop(context, <String, dynamic>{}),
            ),
            if (params.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Icon(Icons.inbox_outlined,
                      color: _kSub, size: 32),
                  const SizedBox(height: 8),
                  const Text('No other parameters in this session yet.',
                      style: TextStyle(color: _kSub, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text(
                      'Add more parameters first; they\'ll appear here.',
                      style: TextStyle(color: _kSub, fontSize: 11)),
                ]),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.of(context).size.height * 0.45),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: params.length,
                  itemBuilder: (_, i) {
                    final p = params[i];
                    final isSelected = current?['id'] == p['id'];
                    return _PickerTile(
                      icon: _iconForType(p['type']?.toString() ?? ''),
                      label: p['label']?.toString() ?? '',
                      subtitle: p['type']?.toString() ?? '',
                      typeColor:
                          _colorForType(p['type']?.toString() ?? ''),
                      isSelected: isSelected,
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String t) {
    switch (t) {
      case 'number':
        return Icons.pin_outlined;
      case 'slider':
        return Icons.linear_scale;
      case 'dual_text':
        return Icons.view_column_outlined;
      default:
        return Icons.text_fields;
    }
  }

  Color _colorForType(String t) => const {
        'number': _kAccent,
        'text': _kSuccess,
        'dropdown': Color(0xFFBB86FC),
        'dual_text': _kWarn,
        'slider': Color(0xFF03DAC6),
        'multiline': Color(0xFF7986CB),
      }[t] ??
      _kSub;
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color typeColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.typeColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: isSelected
            ? _kAutoFill.withOpacity(0.07)
            : Colors.transparent,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 15, color: typeColor),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _kText)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: _kSub)),
              ])),
          if (isSelected)
            const Icon(Icons.check_rounded,
                size: 16, color: _kAutoFill),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ✨ _ExpressionDisplay — REDESIGNED
//    • Shows _displayExprCtrl (human-readable) in the editable field
//    • Param tokens show as [Name] styled chips in the preview above the field
//    • Raw _exprCtrl is managed separately and shown in the collapsible above
// ─────────────────────────────────────────────────────────────────────────────
class _ExpressionDisplay extends StatelessWidget {
  final TextEditingController rawController;
  final TextEditingController displayController;
  final FocusNode focusNode;
  final String? error;

  const _ExpressionDisplay({
    required this.rawController,
    required this.displayController,
    required this.focusNode,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.isNotEmpty;
    final isEmpty = displayController.text.trim().isEmpty;
    final borderColor = hasError
        ? _kDanger
        : isEmpty
            ? _kBorder
            : _kAutoFill.withOpacity(0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(children: [
            // Visual token preview — shows param names as styled chips
            if (displayController.text.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: _kBorder)),
                ),
                child: _buildDisplayPreview(displayController.text),
              ),

            // Editable display field — shows human-readable names
            TextField(
              controller: displayController,
              focusNode: focusNode,
              style: GoogleFonts.sourceCodePro(
                  color: _kText, fontSize: 13),
              cursorColor: _kAutoFill,
              // Allow alphanumeric (param names) + operators + brackets
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[\d\+\-\*\/\(\)\.\s\[\]a-zA-Z_·]')),
              ],
              decoration: InputDecoration(
                hintText: 'e.g.  OilTemp * 0.5 + Pressure',
                hintStyle: const TextStyle(
                    color: _kSub, fontSize: 12, fontFamily: 'monospace'),
                filled: true,
                fillColor: _kBg,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 5),

        if (hasError)
          Row(children: [
            const Icon(Icons.error_outline, size: 12, color: _kDanger),
            const SizedBox(width: 4),
            Text(error!,
                style:
                    const TextStyle(color: _kDanger, fontSize: 11)),
          ])
        else if (!isEmpty)
          Row(children: [
            const Icon(Icons.check_circle_outline,
                size: 12, color: _kSuccess),
            const SizedBox(width: 4),
            const Text('Expression looks valid — tap "Save Expression" to commit',
                style: TextStyle(color: _kSuccess, fontSize: 11)),
          ]),
      ],
    );
  }

  /// Renders the display expression as a RichText where [Name] tokens
  /// appear as styled inline chips.
  Widget _buildDisplayPreview(String expr) {
    final parts = <InlineSpan>[];
    final tokenRe = RegExp(r'\[([^\]]+)\]');
    int lastEnd = 0;
    for (final m in tokenRe.allMatches(expr)) {
      if (m.start > lastEnd) {
        parts.add(TextSpan(
          text: expr.substring(lastEnd, m.start),
          style: GoogleFonts.sourceCodePro(color: _kText, fontSize: 12),
        ));
      }
      // Render [Name] as a styled chip
      parts.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: _kAutoFill.withOpacity(0.15),
              borderRadius: BorderRadius.circular(5),
              border:
                  Border.all(color: _kAutoFill.withOpacity(0.4))),
          child: Text(m.group(1) ?? '',
              style: GoogleFonts.sourceCodePro(
                  color: _kAutoFill,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < expr.length) {
      parts.add(TextSpan(
        text: expr.substring(lastEnd),
        style: GoogleFonts.sourceCodePro(color: _kText, fontSize: 12),
      ));
    }
    return RichText(
        text: TextSpan(children: parts),
        overflow: TextOverflow.ellipsis);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OperatorRow
// ─────────────────────────────────────────────────────────────────────────────
class _OperatorRow extends StatelessWidget {
  final void Function(String) onInsert;

  const _OperatorRow({required this.onInsert});

  static const _ops = [
    ('+', 'Add'),
    ('-', 'Sub'),
    ('*', 'Mul'),
    ('/', 'Div'),
    ('(', 'Open'),
    (')', 'Close'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _ops.map((op) {
        return Expanded(
          child: GestureDetector(
            onTap: () => onInsert(op.$1),
            child: Container(
              margin: EdgeInsets.only(right: op == _ops.last ? 0 : 6),
              height: 44,
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(op.$1,
                          style: GoogleFonts.sourceCodePro(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _kAutoFill)),
                      Text(op.$2,
                          style: const TextStyle(
                              fontSize: 8, color: _kSub)),
                    ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Numpad
// ─────────────────────────────────────────────────────────────────────────────
class _Numpad extends StatelessWidget {
  final void Function(String) onInsert;
  final VoidCallback onDelete;

  const _Numpad({required this.onInsert, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', 'DEL'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: row.map((key) {
              final isDel = key == 'DEL';
              return Expanded(
                child: GestureDetector(
                  onTap: isDel ? onDelete : () => onInsert(key),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: key == row.last ? 0 : 6),
                    height: 46,
                    decoration: BoxDecoration(
                      color: isDel
                          ? _kDanger.withOpacity(0.1)
                          : _kSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isDel
                              ? _kDanger.withOpacity(0.3)
                              : _kBorder),
                    ),
                    child: Center(
                      child: isDel
                          ? const Icon(Icons.backspace_outlined,
                              size: 18, color: _kDanger)
                          : Text(key,
                              style: GoogleFonts.sourceCodePro(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: _kText)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TypeChip
// ─────────────────────────────────────────────────────────────────────────────
class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  Color get _color => const {
        'number': _kAccent,
        'text': _kSuccess,
        'dropdown': Color(0xFFBB86FC),
        'dual_text': _kWarn,
        'slider': Color(0xFF03DAC6),
        'multiline': Color(0xFF7986CB),
      }[type] ??
      _kSub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: _color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _color.withOpacity(0.3))),
      child: Text(type,
          style: TextStyle(
              fontSize: 10,
              color: _color,
              fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SideButton
// ─────────────────────────────────────────────────────────────────────────────
class _SideButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SideButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unchanged small helpers
// ─────────────────────────────────────────────────────────────────────────────
class _ConstraintFlag {
  final IconData icon;
  final Color color;
  final String label;
  const _ConstraintFlag(this.icon, this.color, this.label);
}

class _ExpectedRangeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _ExpectedRangeCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141618),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252830)),
      ),
      padding: const EdgeInsets.all(14),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withOpacity(0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.straighten_outlined,
                size: 15, color: Color(0xFF22C55E)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF0EEE9))),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF8A8F9C))),
              ])),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }
}

class _RangeRow extends StatelessWidget {
  final TextEditingController minCtrl;
  final TextEditingController avgCtrl;
  final TextEditingController maxCtrl;
  final TextInputType keyboardType;

  const _RangeRow({
    required this.minCtrl,
    required this.avgCtrl,
    required this.maxCtrl,
    required this.keyboardType,
  });

  InputDecoration _dec(String label) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF252830)));
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: Color(0xFF8A8F9C), fontSize: 11),
      hintStyle:
          const TextStyle(color: Color(0xFF8A8F9C), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0C0D0F),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
              color: Color(0xFF1ABCBD), width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: TextField(
        controller: minCtrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFF0EEE9), fontSize: 13),
        cursorColor: const Color(0xFF1ABCBD),
        decoration: _dec('Min'),
      )),
      const SizedBox(width: 8),
      Expanded(
          child: TextField(
        controller: avgCtrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFF0EEE9), fontSize: 13),
        cursorColor: const Color(0xFF1ABCBD),
        decoration: _dec('Avg'),
      )),
      const SizedBox(width: 8),
      Expanded(
          child: TextField(
        controller: maxCtrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFFF0EEE9), fontSize: 13),
        cursorColor: const Color(0xFF1ABCBD),
        decoration: _dec('Max'),
      )),
    ]);
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;

  const _DarkTextField({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder));
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: _kText, fontSize: 14),
      cursorColor: _kAccent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kSub, fontSize: 13),
        prefixIcon: maxLines == 1
            ? Icon(icon, size: 17, color: _kSub)
            : null,
        filled: true,
        fillColor: _kSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: _kAccent, width: 1.5)),
      ),
    );
  }
}