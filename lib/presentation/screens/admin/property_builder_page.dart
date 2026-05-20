// lib/presentation/screens/admin/property_builder_page.dart
// ══════════════════════════════════════════════════════════════════════════════
// CHANGES IN THIS VERSION (everything else bit-for-bit identical):
//
//   NEW — "Expected Range" section for NUMERICAL parameters:
//     • number  → Min / Avg / Max  (3 optional text fields)
//     • slider  → Min / Avg / Max  (pre-filled from slider range, editable)
//     • dual_text → separate Min / Avg / Max for EACH side
//                   (labelled with the user's left_label / right_label)
//
//   STORAGE RULES:
//     • Only written to DB if the user actually types a value
//     • number / slider  → { 'expected_min': x, 'expected_avg': x, 'expected_max': x }
//     • dual_text        → { 'left_expected_min': x, ..., 'right_expected_min': x, ... }
//     • NO left_label / right_label written for number, slider, multiline, text
//       (previously these were always written as 'Before'/'After' even for number)
//     • left_label / right_label only written for dual_text
//
//   EVERYTHING ELSE UNCHANGED:
//     type picker, live preview, dropdown options, slider min/max config,
//     required toggle, capture_image toggle, constraint dialog (all 5 flags,
//     severity, alert_title, message), constraint chips, save logic, palette.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'create_tank_screen_helpers.dart';
import 'types_and_small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette (unchanged)
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

// Severity colours
const _kSevInfo = Color(0xFF60A5FA);
const _kSevWarning = Color(0xFFF59E0B);
const _kSevCritical = Color(0xFFEF4444);

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
// PropertyBuilderPage
// ─────────────────────────────────────────────────────────────────────────────
class PropertyBuilderPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final void Function(Map<String, dynamic>) onSave;

  const PropertyBuilderPage({required this.onSave, this.existing});

  @override
  State<PropertyBuilderPage> createState() => PropertyBuilderPageState();
}

class PropertyBuilderPageState extends State<PropertyBuilderPage> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _hintCtrl = TextEditingController();
  final _leftLabelCtrl = TextEditingController(); // dual_text only
  final _rightLabelCtrl = TextEditingController(); // dual_text only
  final _minCtrl = TextEditingController(text: '0'); // slider range
  final _maxCtrl = TextEditingController(text: '100'); // slider range

  // ── Expected range controllers ─────────────────────────────────────────────
  // number / slider
  final _expMinCtrl = TextEditingController();
  final _expAvgCtrl = TextEditingController();
  final _expMaxCtrl = TextEditingController();
  // dual_text — left side
  final _leftExpMinCtrl = TextEditingController();
  final _leftExpAvgCtrl = TextEditingController();
  final _leftExpMaxCtrl = TextEditingController();
  // dual_text — right side
  final _rightExpMinCtrl = TextEditingController();
  final _rightExpAvgCtrl = TextEditingController();
  final _rightExpMaxCtrl = TextEditingController();

  String _type = 'number';
  bool _required = true;
  bool _captureImage = false;
  final List<String> _options = [];
  final List<Map<String, dynamic>> _constraints = [];
  bool _constraintsExpanded = false;

  static const _types = [
    TypeMeta('number', 'Number', Icons.pin_outlined),
    TypeMeta('text', 'Text', Icons.text_fields),
    TypeMeta('dropdown', 'Dropdown', Icons.arrow_drop_down_circle_outlined),
    TypeMeta('dual_text', 'Dual Input', Icons.view_column_outlined),
    TypeMeta('slider', 'Slider', Icons.linear_scale),
    TypeMeta('multiline', 'Multiline', Icons.notes),
  ];

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[PropertyBuilder] initState — existing=${widget.existing?['id']}');

    // Live-preview listeners
    for (final c in [
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
      _rightExpMaxCtrl
    ]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }

    if (widget.existing != null) {
      final p = widget.existing!;
      _labelCtrl.text = p['label'] ?? '';
      _hintCtrl.text = p['hint'] ?? '';
      _type = p['type'] ?? 'number';
      _required = p['required'] == true;
      _captureImage = p['capture_image'] == true;
      _leftLabelCtrl.text = p['left_label'] ?? 'Before';
      _rightLabelCtrl.text = p['right_label'] ?? 'After';
      _minCtrl.text = (p['min'] ?? 0).toString();
      _maxCtrl.text = (p['max'] ?? 100).toString();

      // Expected range — number / slider
      _expMinCtrl.text = p['expected_min']?.toString() ?? '';
      _expAvgCtrl.text = p['expected_avg']?.toString() ?? '';
      _expMaxCtrl.text = p['expected_max']?.toString() ?? '';

      // Expected range — dual_text
      _leftExpMinCtrl.text = p['left_expected_min']?.toString() ?? '';
      _leftExpAvgCtrl.text = p['left_expected_avg']?.toString() ?? '';
      _leftExpMaxCtrl.text = p['left_expected_max']?.toString() ?? '';
      _rightExpMinCtrl.text = p['right_expected_min']?.toString() ?? '';
      _rightExpAvgCtrl.text = p['right_expected_avg']?.toString() ?? '';
      _rightExpMaxCtrl.text = p['right_expected_max']?.toString() ?? '';

      if (p['options'] != null) {
        _options.addAll(List<String>.from(p['options'] as List));
      }
      if (p['constraints'] != null) {
        _constraints.addAll(
          (p['constraints'] as List)
              .map((e) => deepCast(e) as Map<String, dynamic>),
        );
        if (_constraints.isNotEmpty) _constraintsExpanded = true;
      }
      debugPrint(
          '[PropertyBuilder] Loaded: type=$_type label=${_labelCtrl.text}');
    }
  }

  @override
  void dispose() {
    for (final c in [
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
      _rightExpMaxCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  bool get _isNumerical => _type == 'number' || _type == 'slider';
  bool get _isDualText => _type == 'dual_text';

  double? _parseOpt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  // ── Dropdown option management (UNCHANGED) ─────────────────────────────────

  Future<void> _addOrEditOption({int? idx}) async {
    final ctrl = TextEditingController(text: idx != null ? _options[idx] : '');
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: Text(idx != null ? 'Edit Option' : 'Add Option',
            style:
                GoogleFonts.inter(color: kText, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: kText),
          cursorColor: kAccent,
          decoration:
              compactDeco(hint: 'Option text', icon: Icons.label_outline),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: kSub))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccent),
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

  // ── Constraint dialog (UNCHANGED — full version with all 5 flags) ──────────

  Future<void> _addOrEditConstraint({int? idx}) async {
    debugPrint('[Constraints] _addOrEditConstraint idx=$idx');
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
                // Header
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

                // Scrollable body
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Operator
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
                                              color: sel ? _kAccent : _kText)),
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

                        // Value
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

                        // Severity
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

                        // Alert title
                        _dlgLabel('Alert Title  (optional)'),
                        const SizedBox(height: 8),
                        _DarkTextField(
                            ctrl: alertTitleCtrl,
                            hint: 'e.g. Overheat Detected',
                            icon: Icons.title_rounded),
                        const SizedBox(height: 16),

                        // Message
                        _dlgLabel('Error Message  (optional)'),
                        const SizedBox(height: 8),
                        _DarkTextField(
                            ctrl: errorMsgCtrl,
                            hint: 'e.g. Temperature exceeded safe limit',
                            icon: Icons.warning_amber_outlined,
                            maxLines: 2),
                        const SizedBox(height: 18),

                        // Behaviour checkboxes
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

                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  decoration: const BoxDecoration(
                    color: _kSurface,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(18)),
                    border: Border(top: BorderSide(color: _kBorder)),
                  ),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
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
                        debugPrint('[Constraints] Saved: $c');
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

  void _deleteConstraint(int idx) => setState(() => _constraints.removeAt(idx));

  // ── Save ───────────────────────────────────────────────────────────────────

  void _save() {
    debugPrint(
        '[PropertyBuilder] _save() — type=$_type label=${_labelCtrl.text.trim()}');
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

    final prop = <String, dynamic>{
      'id': widget.existing?['id'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'label': _labelCtrl.text.trim(),
      'hint': _hintCtrl.text.trim(),
      'type': _type,
      'required': _required,
      'capture_image': _captureImage,
      'options': List<String>.from(_options),
      // left/right labels ONLY for dual_text
      if (_type == 'dual_text') ...{
        'left_label': _leftLabelCtrl.text.trim().isEmpty
            ? 'Before'
            : _leftLabelCtrl.text.trim(),
        'right_label': _rightLabelCtrl.text.trim().isEmpty
            ? 'After'
            : _rightLabelCtrl.text.trim(),
      },
      // slider range (slider only)
      if (_type == 'slider') ...{
        'min': double.tryParse(_minCtrl.text.trim()) ?? 0,
        'max': double.tryParse(_maxCtrl.text.trim()) ?? 100,
      },
      // Expected range — number / slider
      if (_isNumerical) ...{
        if (_parseOpt(_expMinCtrl) != null)
          'expected_min': _parseOpt(_expMinCtrl),
        if (_parseOpt(_expAvgCtrl) != null)
          'expected_avg': _parseOpt(_expAvgCtrl),
        if (_parseOpt(_expMaxCtrl) != null)
          'expected_max': _parseOpt(_expMaxCtrl),
      },
      // Expected range — dual_text (per side)
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
      'constraints': List<Map<String, dynamic>>.from(_constraints),
    };

    debugPrint('[PropertyBuilder] onSave prop=$prop');
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
                      hint: 'e.g. Oil Temperature', icon: Icons.label_outline),
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

                // ── Expected range ────────────────────────────────────────
                if (_isNumerical || _isDualText) ...[
                  const SizedBox(height: 20),
                  _buildExpectedRange(),
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

  // ── Type picker (UNCHANGED) ────────────────────────────────────────────────

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.15) : _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? color : _kBorder, width: selected ? 2 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(t.icon, size: 16, color: selected ? color : _kSub),
              const SizedBox(width: 6),
              Text(t.label,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? color : _kText)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Type-specific config (UNCHANGED) ──────────────────────────────────────

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
                      onPressed: () => setState(() => _options.removeAt(i))),
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
                if (max <= (double.tryParse(_minCtrl.text) ?? 0))
                  return 'Must be > Min';
                return null;
              },
            )),
          ]),
        ],
      );

  // ── ✨ NEW — Expected Range section ────────────────────────────────────────

  Widget _buildExpectedRange() {
    const numKb = TextInputType.numberWithOptions(decimal: true);

    if (_isNumerical) {
      // Single set of Min / Avg / Max
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

    // dual_text — one set per side, labelled with the user's column names
    final leftLabel = _leftLabelCtrl.text.trim().isEmpty
        ? 'Left (Before)'
        : _leftLabelCtrl.text.trim();
    final rightLabel = _rightLabelCtrl.text.trim().isEmpty
        ? 'Right (After)'
        : _rightLabelCtrl.text.trim();

    return _ExpectedRangeCard(
      title: 'Expected Range',
      subtitle: 'Set Min / Avg / Max for each column. '
          'Only values you enter will be stored.',
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

  // ── Constraints section (UNCHANGED appearance) ────────────────────────────

  Widget _buildConstraintsSection() {
    final ops = opsForType(_type);
    if (ops.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // collapsible header
        InkWell(
          onTap: () =>
              setState(() => _constraintsExpanded = !_constraintsExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

        // expanded body
        if (_constraintsExpanded) ...[
          const Divider(height: 1, thickness: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          style: TextStyle(fontSize: 12, color: _kSub))),
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
                        Icons.dashboard_outlined, _kSevWarning, 'Dashboard'));
                  if (c['play_sound_on_violation'] == true)
                    flags.add(_ConstraintFlag(
                        Icons.volume_up_outlined, _kSevCritical, 'Sound'));
                  if (c['capture_image_on_violation'] == true)
                    flags.add(_ConstraintFlag(
                        Icons.camera_alt_outlined, _kSevWarning, 'Camera'));
                  if (c['block_submission'] == true)
                    flags.add(_ConstraintFlag(
                        Icons.block_rounded, _kSevCritical, 'Blocks'));

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        color: _kBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sc.withOpacity(0.3))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                            child: Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                    color: sc.withOpacity(0.13),
                                    borderRadius: BorderRadius.circular(5),
                                    border:
                                        Border.all(color: sc.withOpacity(0.4))),
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
                                    borderRadius: BorderRadius.circular(7)),
                                child: Center(
                                    child: Text(opSymbol(_type, op),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFBB86FC)))),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('${opLabel(_type, op)}  "$val"',
                                        style: GoogleFonts.dmSans(
                                            fontSize: 13,
                                            color: _kText,
                                            fontWeight: FontWeight.w600)),
                                    if (msg.isNotEmpty)
                                      Text(msg,
                                          style: GoogleFonts.dmSans(
                                              fontSize: 11, color: _kSub)),
                                  ])),
                              _iconTap(Icons.edit_outlined, _kAccent,
                                  () => _addOrEditConstraint(idx: i)),
                              _iconTap(Icons.delete_outline, _kDanger,
                                  () => _deleteConstraint(i)),
                            ]),
                          ),
                          if (flags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: flags
                                    .map((f) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                              color: f.color.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                  color: f.color
                                                      .withOpacity(0.3))),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(f.icon,
                                                    size: 10, color: f.color),
                                                const SizedBox(width: 4),
                                                Text(f.label,
                                                    style: GoogleFonts
                                                        .spaceGrotesk(
                                                            fontSize: 8,
                                                            color: f.color,
                                                            fontWeight:
                                                                FontWeight.w700,
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
                    side: const BorderSide(color: Color(0xFFBB86FC)),
                    foregroundColor: const Color(0xFFBB86FC),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

  // ── Live preview (UNCHANGED) ───────────────────────────────────────────────

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          style: const TextStyle(color: _kText, fontSize: 13))))
                  .toList()
              : [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('Select…',
                          style: TextStyle(color: _kSub, fontSize: 13)))
                ],
          onChanged: null,
          dropdownColor: _kCard,
          iconEnabledColor: _kSub,
          iconDisabledColor: _kSub,
          style: const TextStyle(color: _kText),
          decoration:
              baseDec.copyWith(hintText: _options.isEmpty ? 'Select…' : null),
        );

      case 'dual_text':
        final left = _leftLabelCtrl.text.trim().isEmpty
            ? 'Before'
            : _leftLabelCtrl.text.trim();
        final right = _rightLabelCtrl.text.trim().isEmpty
            ? 'After'
            : _rightLabelCtrl.text.trim();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    style: const TextStyle(color: _kText, fontSize: 13),
                    decoration: baseDec.copyWith(hintText: left))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    readOnly: true,
                    style: const TextStyle(color: _kText, fontSize: 13),
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: mn, min: mn, max: sMx, onChanged: null),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$mn', style: const TextStyle(fontSize: 11, color: _kSub)),
            Text('$mx', style: const TextStyle(fontSize: 11, color: _kSub)),
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
            keyboardType:
                _type == 'number' ? TextInputType.number : TextInputType.text,
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

  Widget _iconTap(IconData icon, Color color, VoidCallback onTap) => InkWell(
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
// ✨ _ExpectedRangeCard — container for the expected range section
// ─────────────────────────────────────────────────────────────────────────────
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

// ─────────────────────────────────────────────────────────────────────────────
// ✨ _RangeRow — three compact fields: Min | Avg | Max in one row
// ─────────────────────────────────────────────────────────────────────────────
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
      labelStyle: const TextStyle(color: Color(0xFF8A8F9C), fontSize: 11),
      hintStyle: const TextStyle(color: Color(0xFF8A8F9C), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0C0D0F),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1ABCBD), width: 1.5)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Unchanged helpers
// ─────────────────────────────────────────────────────────────────────────────
class _ConstraintFlag {
  final IconData icon;
  final Color color;
  final String label;
  const _ConstraintFlag(this.icon, this.color, this.label);
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
        prefixIcon: maxLines == 1 ? Icon(icon, size: 17, color: _kSub) : null,
        filled: true,
        fillColor: _kSurface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kAccent, width: 1.5)),
      ),
    );
  }
}
