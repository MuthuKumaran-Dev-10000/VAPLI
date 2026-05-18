import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'create_tank_screen_helpers.dart';
import 'types_and_small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PropertyBuilderPage  (Google-Forms-style, live preview)
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);

const _kSurface = Color(0xFF141618);

const _kCard = Color(0xFF1A1C20);

// Accent (teal/live data)
const _kAccent = Color(0xFF1ABCBD);

// Border
const _kBorder = Color(0xFF252830);

// Text
const _kText = Color(0xFFF0EEE9);

const _kSub = Color(0xFF8A8F9C);

// States
const _kSuccess = Color(0xFF22C55E);

const _kWarn = Color(0xFFF59E0B);

const _kDanger = Color(0xFFEF4444);

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
  final _leftLabelCtrl = TextEditingController();
  final _rightLabelCtrl = TextEditingController();
  // min/max ONLY for slider
  final _minCtrl = TextEditingController(text: '0');
  final _maxCtrl = TextEditingController(text: '100');

  String _type = 'number';
  bool _required = true;
  bool _captureImage = false;
  final List<String> _options = [];
  final List<Map<String, dynamic>> _constraints = [];

  // tracks whether constraints panel is expanded
  bool _constraintsExpanded = false;

  static const _types = [
    TypeMeta('number', 'Number', Icons.pin_outlined),
    TypeMeta('text', 'Text', Icons.text_fields),
    TypeMeta('dropdown', 'Dropdown', Icons.arrow_drop_down_circle_outlined),
    TypeMeta('dual_text', 'Dual Input', Icons.view_column_outlined),
    TypeMeta('slider', 'Slider', Icons.linear_scale),
    TypeMeta('multiline', 'Multiline', Icons.notes),
  ];

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[PropertyBuilder] initState — existing=${widget.existing?['id']}');

    for (final c in [
      _labelCtrl,
      _hintCtrl,
      _leftLabelCtrl,
      _rightLabelCtrl,
      _minCtrl,
      _maxCtrl,
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
      // min/max only relevant for slider
      _minCtrl.text = (p['min'] ?? 0).toString();
      _maxCtrl.text = (p['max'] ?? 100).toString();
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
      debugPrint('[PropertyBuilder] Loaded existing: type=$_type '
          'label=${_labelCtrl.text} options=${_options.length} '
          'constraints=${_constraints.length}');
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _hintCtrl.dispose();
    _leftLabelCtrl.dispose();
    _rightLabelCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  // ── dropdown option management ─────────────────────────────────────────────

  Future<void> _addOrEditOption({int? idx}) async {
    debugPrint('[Dropdown] _addOrEditOption idx=$idx');
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
            onPressed: () {
              debugPrint('[Dropdown] Option dialog cancelled');
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: kSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccent),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isEmpty) return;
              setState(
                  () => idx != null ? _options[idx] = val : _options.add(val));
              debugPrint('[Dropdown] Option saved: $val at idx=$idx');
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── constraint management ──────────────────────────────────────────────────

  Future<void> _addOrEditConstraint({int? idx}) async {
    debugPrint('[Constraints] _addOrEditConstraint idx=$idx');
    final existing = idx != null ? _constraints[idx] : null;
    final ops = opsForType(_type);

    String selectedOp = existing?['op'] as String? ?? ops.first.value;
    final valueCtrl =
        TextEditingController(text: existing?['value'] as String? ?? '');
    final errorMsgCtrl =
        TextEditingController(text: existing?['error_msg'] as String? ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            idx != null ? 'Edit Constraint' : 'Add Constraint',
            style: GoogleFonts.inter(color: kText, fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Operator selector ──────────────────────────────
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
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel ? kAccent.withOpacity(0.15) : kSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? kAccent : kBorder,
                              width: sel ? 2 : 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(op.symbol,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: sel ? _kAccent : _kText)),
                            const SizedBox(height: 2),
                            Text(op.label,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: sel ? _kAccent : _kSub)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // ── Value ──────────────────────────────────────────
                _dlgLabel('Value'),
                const SizedBox(height: 8),
                TextField(
                  controller: valueCtrl,
                  autofocus: true,
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  keyboardType: (_type == 'number' || _type == 'slider')
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: compactDeco(
                    hint: (_type == 'number' || _type == 'slider')
                        ? 'e.g. 50'
                        : 'e.g. OK',
                    icon: Icons.edit_outlined,
                  ),
                ),
                const SizedBox(height: 16),
                // ── Custom error message ───────────────────────────
                _dlgLabel('Custom Error Message  (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: errorMsgCtrl,
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  decoration: compactDeco(
                    hint: 'e.g. Value must be at least 50',
                    icon: Icons.warning_amber_outlined,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint('[Constraints] Dialog cancelled');
                Navigator.pop(ctx);
              },
              child: const Text('Cancel', style: TextStyle(color: _kSub)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
              onPressed: () {
                final val = valueCtrl.text.trim();
                if (val.isEmpty) return;
                final c = {
                  'op': selectedOp,
                  'value': val,
                  'error_msg': errorMsgCtrl.text.trim(),
                };
                setState(() {
                  if (idx != null) {
                    _constraints[idx] = c;
                    debugPrint('[Constraints] Updated at idx=$idx: $c');
                  } else {
                    _constraints.add(c);
                    debugPrint(
                        '[Constraints] Added: $c total=${_constraints.length}');
                  }
                });
                Navigator.pop(ctx);
              },
              child: Text(idx != null ? 'Update' : 'Add',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteConstraint(int idx) {
    debugPrint('[Constraints] Delete at idx=$idx');
    setState(() => _constraints.removeAt(idx));
  }

  // ── save ───────────────────────────────────────────────────────────────────

  void _save() {
    debugPrint('[PropertyBuilder] _save() called — type=$_type '
        'label=${_labelCtrl.text.trim()}');

    if (!_formKey.currentState!.validate()) {
      debugPrint('[PropertyBuilder] Form validation FAILED');
      return;
    }

    if (_type == 'dropdown' && _options.isEmpty) {
      debugPrint('[PropertyBuilder] Dropdown has no options — blocking save');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add at least one dropdown option',
            style: TextStyle(color: _kText)),
        backgroundColor: _kWarn,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final prop = {
      'id': widget.existing?['id'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'label': _labelCtrl.text.trim(),
      'hint': _hintCtrl.text.trim(),
      'type': _type,
      'required': _required,
      'capture_image': _captureImage,
      'options': List<String>.from(_options),
      'left_label': _leftLabelCtrl.text.trim().isEmpty
          ? 'Before'
          : _leftLabelCtrl.text.trim(),
      'right_label': _rightLabelCtrl.text.trim().isEmpty
          ? 'After'
          : _rightLabelCtrl.text.trim(),
      // min/max ONLY stored for slider; ignored for all other types
      if (_type == 'slider') ...{
        'min': double.tryParse(_minCtrl.text.trim()) ?? 0,
        'max': double.tryParse(_maxCtrl.text.trim()) ?? 100,
      },
      'constraints': List<Map<String, dynamic>>.from(_constraints),
    };
    debugPrint('[PropertyBuilder] Calling onSave with prop=$prop');
    widget.onSave(prop);
    Navigator.pop(context);
  }

  // ── build ──────────────────────────────────────────────────────────────────

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
            onPressed: () {
              debugPrint('[PropertyBuilder] AppBar Save tapped');
              _save();
            },
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
            primary: _kAccent,
            surface: _kSurface,
            onSurface: _kText,
          ),
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
                // ── Required toggle ────────────────────────────────
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
                        ? null // locked when capture_image is on
                        : (v) {
                            debugPrint(
                                '[PropertyBuilder] Required toggled to $v');
                            setState(() => _required = v);
                          },
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: SwitchListTile(
                    value: _captureImage,
                    activeColor: _kAccent,
                    title: Text(
                      'Capture Image',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: _kText,
                      ),
                    ),
                    subtitle: Text(
                      _captureImage
                          ? 'Inspector must capture image for this parameter'
                          : 'No image required',
                      style: const TextStyle(
                        color: _kSub,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (v) {
                      debugPrint('[PropertyBuilder] Capture image changed: $v');
                      setState(() {
                        _captureImage = v;
                        if (v)
                          _required =
                              true; // capture_image=true → required must be true
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // ── Type-specific config ───────────────────────────
                _buildTypeConfig(),
                const SizedBox(height: 24),
                // ── Constraints section ────────────────────────────
                _buildConstraintsSection(),
                const SizedBox(height: 28),
                // ── Live preview ───────────────────────────────────
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
                    onPressed: () {
                      debugPrint('[PropertyBuilder] CTA button tapped');
                      _save();
                    },
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

  // ── type picker ────────────────────────────────────────────────────────────

  Widget _buildTypePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((t) {
        final selected = _type == t.value;
        final color = _typeColorFor(t.value);
        return GestureDetector(
          onTap: () {
            debugPrint('[PropertyBuilder] Type selected: ${t.value}');
            // When type changes, reset constraints (they're type-specific)
            setState(() {
              _type = t.value;
              _constraints.clear();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.15) : _kSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? color : _kBorder, width: selected ? 2 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: 16, color: selected ? color : _kSub),
                const SizedBox(width: 6),
                Text(t.label,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? color : _kText)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── type-specific config ───────────────────────────────────────────────────

  Widget _buildTypeConfig() {
    switch (_type) {
      case 'dropdown':
        return _dropdownConfig();
      case 'dual_text':
        return _dualTextConfig();
      case 'slider':
        return _sliderConfig(); // ONLY slider gets min/max
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
                debugPrint('[Dropdown] Reorder $o → $n');
                setState(() {
                  if (n > o) n--;
                  final item = _options.removeAt(o);
                  _options.insert(n, item);
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: _kAccent),
                        onPressed: () => _addOrEditOption(idx: i)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: _kDanger),
                        onPressed: () {
                          debugPrint(
                              '[Dropdown] Delete option at idx=$i: ${_options[i]}');
                          setState(() => _options.removeAt(i));
                        }),
                  ],
                ),
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
              onPressed: () => _addOrEditOption(),
            ),
          ),
        ],
      );

  Widget _dualTextConfig() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sl('Column Labels'),
          const SizedBox(height: 4),
          const Text(
              'One label row, two text boxes in a single row.\n'
              'Name each column so inspectors know what to enter.',
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
              ),
            ),
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
              ),
            ),
          ]),
        ],
      );

  // ONLY slider gets min/max fields
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
              ),
            ),
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
                  final min = double.tryParse(_minCtrl.text) ?? 0;
                  if (max <= min) return 'Must be > Min';
                  return null;
                },
              ),
            ),
          ]),
        ],
      );

  // ── Constraints section ────────────────────────────────────────────────────

  Widget _buildConstraintsSection() {
    final ops = opsForType(_type);
    if (ops.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── collapsible header ─────────────────────────────────
          InkWell(
            onTap: () {
              debugPrint(
                  '[Constraints] Toggle expanded: ${!_constraintsExpanded}');
              setState(() => _constraintsExpanded = !_constraintsExpanded);
            },
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
                    ],
                  ),
                ),
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
                  color: _kSub,
                ),
              ]),
            ),
          ),
          // ── expanded body ──────────────────────────────────────
          if (_constraintsExpanded) ...[
            Divider(height: 1, thickness: 1, color: _kBorder),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'All constraints must pass (AND logic). '
                    'Operators available for this type are shown when you add.',
                    style: TextStyle(fontSize: 11, color: _kSub),
                  ),
                  const SizedBox(height: 12),
                  // ── existing constraints list ────────────────
                  if (_constraints.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _kBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _kBorder, style: BorderStyle.solid)),
                      child: const Center(
                        child: Text('No constraints yet',
                            style: TextStyle(fontSize: 12, color: _kSub)),
                      ),
                    )
                  else
                    ...List.generate(_constraints.length, (i) {
                      final c = _constraints[i];
                      final op = c['op'] as String? ?? '';
                      final val = c['value'] as String? ?? '';
                      final msg = c['error_msg'] as String? ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _kBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(children: [
                          // operator symbol badge
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFFBB86FC).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              opSymbol(_type, op),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFBB86FC)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${opLabel(_type, op)}   "$val"',
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: _kText,
                                      fontWeight: FontWeight.w500),
                                ),
                                if (msg.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(msg,
                                      style: const TextStyle(
                                          fontSize: 11, color: _kSub)),
                                ],
                              ],
                            ),
                          ),
                          _iconTap(Icons.edit_outlined, _kAccent,
                              () => _addOrEditConstraint(idx: i)),
                          _iconTap(Icons.delete_outline, _kDanger,
                              () => _deleteConstraint(i)),
                        ]),
                      );
                    }),
                  const SizedBox(height: 10),
                  // ── Add constraint button ────────────────────
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
                      onPressed: () {
                        debugPrint('[Constraints] Add Constraint tapped');
                        _addOrEditConstraint();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── live preview ───────────────────────────────────────────────────────────

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      style: TextStyle(color: _kDanger, fontSize: 13)),
                ),
              Expanded(child: _liveInput(hint)),
            ],
          ),
          if (_hintCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_hintCtrl.text.trim(),
                style: const TextStyle(fontSize: 11, color: _kSub)),
          ],
        ],
      ),
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
        final previewValue = _options.isNotEmpty ? _options.first : null;
        return DropdownButtonFormField<String>(
          value: previewValue,
          items: _options.isNotEmpty
              ? _options
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style:
                                const TextStyle(color: _kText, fontSize: 13)),
                      ))
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(left,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kSub)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(right,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kSub)),
              ),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(
                child: TextField(
                    readOnly: true,
                    style: const TextStyle(color: _kText, fontSize: 13),
                    decoration: baseDec.copyWith(hintText: left)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    readOnly: true,
                    style: const TextStyle(color: _kText, fontSize: 13),
                    decoration: baseDec.copyWith(hintText: right)),
              ),
            ]),
          ],
        );

      case 'slider':
        final mn = double.tryParse(_minCtrl.text) ?? 0;
        final mx = double.tryParse(_maxCtrl.text) ?? 100;
        final safeMx = mx > mn ? mx : mn + 1;
        return Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _kAccent,
              thumbColor: _kAccent,
              inactiveTrackColor: _kBorder,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: mn, min: mn, max: safeMx, onChanged: null),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$mn', style: const TextStyle(fontSize: 11, color: _kSub)),
              Text('$mx', style: const TextStyle(fontSize: 11, color: _kSub)),
            ],
          ),
        ]);

      case 'multiline':
        return TextField(
          readOnly: true,
          maxLines: 3,
          style: const TextStyle(color: _kText, fontSize: 13),
          decoration: baseDec.copyWith(hintText: hint),
        );

      default: // number | text
        return TextField(
          readOnly: true,
          keyboardType:
              _type == 'number' ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: _kText, fontSize: 13),
          decoration: baseDec.copyWith(hintText: hint),
        );
    }
  }

  // ─── helpers ───────────────────────────────────────────────────────────────

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
            child: Icon(icon, size: 18, color: color)),
      );

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
