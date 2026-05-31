import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/core/services/expression_engine.dart';
import 'package:lubrication_indicator/core/utils/session_manager.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';

import 'package:lubrication_indicator/features/tanks/presentation/widgets/create_tank_qr.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/create_tank_screen_helpers.dart';
import 'package:lubrication_indicator/features/tanks/presentation/pages/property_builder_page.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/tank_card_actions.dart';
import 'package:lubrication_indicator/features/tanks/presentation/widgets/types_and_small_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CreateTankScreen
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

class CreateTankScreen extends StatefulWidget {
  final Map<String, dynamic>? existingTank;
  final bool isDuplicate;

  const CreateTankScreen({
    super.key,
    this.existingTank,
    this.isDuplicate = false,
  });

  @override
  State<CreateTankScreen> createState() => _CreateTankScreenState();
}

class _CreateTankScreenState extends State<CreateTankScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _locCtrl = TextEditingController();

  final List<Map<String, dynamic>> _properties = [];
  bool _saving = false;
  late final String _paramScopeId;

  bool get _isEdit => widget.existingTank != null && !widget.isDuplicate;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final seed = widget.existingTank?['id']?.toString();
    _paramScopeId = (seed != null && seed.trim().isNotEmpty)
        ? 'tank_$seed'
        : 'draft_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint(
        '[CreateTankScreen] initState — isEdit=$_isEdit isDuplicate=${widget.isDuplicate}');

    if (widget.existingTank != null) {
      final t = widget.existingTank!;
      _codeCtrl.text = t['tank_code'] ?? '';
      _nameCtrl.text = widget.isDuplicate
          ? '${t['tank_name']} (copy)'
          : (t['tank_name'] ?? '');
      _locCtrl.text = t['location'] ?? '';
      if (_locCtrl.text.trim().isEmpty) _locCtrl.text = '';
      if (t['inspection_properties'] != null) {
        _properties.addAll(
          (t['inspection_properties'] as List)
              .map((e) => deepCast(e) as Map<String, dynamic>),
        );
      }
      debugPrint(
          '[CreateTankScreen] Loaded existing tank: code=${_codeCtrl.text} '
          'name=${_nameCtrl.text} props=${_properties.length}');
    }
    if (_locCtrl.text.trim().isEmpty) _locCtrl.text = '';
    _syncScopeParams();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    debugPrint(
        '[Save] _save() called — isEdit=$_isEdit isDuplicate=${widget.isDuplicate}');

    if (!_formKey.currentState!.validate()) {
      debugPrint('[Save] Form validation FAILED — aborting');
      return;
    }
    debugPrint('[Save] Form validation passed');

    setState(() => _saving = true);
    try {
      final user = await SessionManager.getCurrentUser();
      if (user == null) {
        debugPrint('[Save] ERROR: No session found');
        throw Exception('Session expired. Please log in again.');
      }
      debugPrint('[Save] Session OK — userId=${user.id}');

      final tankCode = _codeCtrl.text.trim();
      final tankName = _nameCtrl.text.trim();
      final location = _locCtrl.text.trim();
      const scaleMax = 100.0;
      debugPrint('[Save] Fields: code=$tankCode name=$tankName loc=$location '
          'scaleMax=$scaleMax scaleSide=left props=${_properties.length}');

      if (_isEdit) {
        debugPrint('[Save] Mode = EDIT/UPDATE');
        final existing = widget.existingTank!;
        final identityChanged = existing['tank_code'] != tankCode ||
            existing['tank_name'] != tankName ||
            existing['location'] != location;
        debugPrint('[Save] identityChanged=$identityChanged');

        debugPrint('[Save] Tank changed -> regenerating QR');
        final newQrUrl = await generateAndUploadQr(
          tankCode: tankCode,
          tankName: tankName,
          location: location,
        );

        debugPrint(
            '[Save] Calling TankRepository.updateTank id=${existing['id']}');
        await TankRepository().updateTank(
          id: existing['id'],
          tankCode: tankCode,
          tankName: tankName,
          location: location,
          scaleMax: scaleMax,
          scaleSide: 'left',
          properties: _properties,
          qrImageUrl: newQrUrl,
        );
        debugPrint('[Save] updateTank SUCCESS');
      } else {
        debugPrint('[Save] Mode = CREATE (or DUPLICATE)');
        debugPrint('[Save] Generating QR for new tank…');
        final qrUrl = await generateAndUploadQr(
          tankCode: tankCode,
          tankName: tankName,
          location: location,
        );
        debugPrint('[Save] Calling TankRepository.createTank');
        await TankRepository().createTank(
          tankCode: tankCode,
          tankName: tankName,
          location: location,
          scaleMax: scaleMax,
          scaleSide: 'left',
          createdBy: user.id,
          qrImageUrl: qrUrl,
          properties: _properties,
        );
        debugPrint('[Save] createTank SUCCESS');
      }

      if (mounted) {
        debugPrint('[Save] Popping with result=true');
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      debugPrint('[Save] EXCEPTION: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: kText)),
          backgroundColor: kDanger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── property builder navigation ────────────────────────────────────────────

  Future<void> _openPropertyBuilder({Map<String, dynamic>? existing}) async {
    debugPrint(
        '[Props] Opening property builder — existing=${existing?['id']}');
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyBuilderPage(
          existing: existing,
          onSave: (prop) {
            debugPrint('[Props] onSave called — id=${prop['id']} '
                'label=${prop['label']} type=${prop['type']}');
            setState(() {
              final idx = _properties.indexWhere((e) => e['id'] == prop['id']);
              if (idx == -1) {
                _properties.add(prop);
                debugPrint(
                    '[Props] Added new property. Total=${_properties.length}');
              } else {
                _properties[idx] = prop;
                debugPrint('[Props] Updated existing property at index=$idx');
              }
            });
            _syncScopeParams();
          },
          scopeId: _paramScopeId,
        ),
      ),
    );
  }

  Future<void> _syncScopeParams() async {
    await SessionParamStore.clearScope(_paramScopeId);
    await SessionParamStore.upsertMany(
      _paramScopeId,
      _properties.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  Set<String> _extractDependencyIds(Map<String, dynamic> param) {
    final expr = (param['autofill_expression'] ?? '').toString();
    if (expr.trim().isEmpty) return {};
    return ExpressionEngine.extractIds(expr)
        .map((e) => e.split(':').first.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  List<Map<String, dynamic>> _findReferencingParams(String targetParamId) {
    return _properties.where((param) {
      final id = (param['id'] ?? '').toString();
      if (id == targetParamId) return false;
      return _extractDependencyIds(param).contains(targetParamId);
    }).toList();
  }

  void _confirmDeleteProp(Map<String, dynamic> p) {
    debugPrint(
        '[Props] Confirm delete property id=${p['id']} label=${p['label']}');
    final targetId = (p['id'] ?? '').toString();
    final refs = _findReferencingParams(targetId);
    if (refs.isNotEmpty) {
      final labels = refs
          .map((e) => (e['label'] ?? e['id'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete "${p['label']}". It is referenced by: ${labels.join(', ')}. Update those autofill expressions first.',
            style: const TextStyle(color: kText),
          ),
          backgroundColor: kDanger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Delete Parameter',
            style:
                GoogleFonts.inter(color: kText, fontWeight: FontWeight.w600)),
        content: Text('Delete "${p['label']}"? This cannot be undone.',
            style: const TextStyle(color: kSub)),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[Props] Delete cancelled');
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: _kSub)),
          ),
          TextButton(
            onPressed: () {
              debugPrint('[Props] Property deleted: id=${p['id']}');
              setState(() => _properties.remove(p));
              SessionParamStore.removeParam(_paramScopeId, targetId);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );
  }

  // ── property card ──────────────────────────────────────────────────────────

  Widget _buildPropertyCard(Map<String, dynamic> p) {
    final type = p['type'] as String? ?? 'text';
    final label = p['label'] as String? ?? 'Untitled';
    final hint = p['hint'] as String? ?? '';
    final isRequired = p['required'] == true;
    final captureImage = p['capture_image'] == true;
    final keepPrevious = p['keep_previous_capture'] == true;
    final color = _typeColor(type);
    final constraints = List<Map<String, dynamic>>.from(p['constraints'] ?? []);

    return Card(
      key: ValueKey(p['id']),
      margin: const EdgeInsets.only(bottom: 10),
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── header bar ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 18, color: kSub),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: kText)),
                ),
                _typeBadge(type, color),
                const SizedBox(width: 8),
                _iconTap(Icons.edit_outlined, kAccent, () {
                  debugPrint('[Props] Edit tapped for ${p['id']}');
                  _openPropertyBuilder(existing: p);
                }),
                _iconTap(
                    Icons.delete_outline, kDanger, () => _confirmDeleteProp(p)),
              ],
            ),
          ),
          // ── body ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (hint.isNotEmpty) ...[
                    const Icon(Icons.info_outline, size: 13, color: _kSub),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(hint,
                            style:
                                const TextStyle(fontSize: 12, color: _kSub))),
                  ] else
                    const Spacer(),
                  if (isRequired)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: kWarn.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('Required',
                          style: TextStyle(
                              fontSize: 10,
                              color: kWarn,
                              fontWeight: FontWeight.w600)),
                    ),
                ]),
                if (captureImage) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Photo',
                      style: TextStyle(
                        fontSize: 10,
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (keepPrevious) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kWarn.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Last',
                      style: TextStyle(
                        fontSize: 10,
                        color: kWarn,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _cardPreview(p, type, hint),
                // ── constraint chips ─────────────────────────────────
                if (constraints.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: constraints.map((c) {
                      final op = c['op'] as String? ?? '';
                      final val = c['value'] as String? ?? '';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0xFFBB86FC).withOpacity(0.13),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    const Color(0xFFBB86FC).withOpacity(0.4))),
                        child: Text(
                          '${opSymbol(type, op)} $val',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFBB86FC),
                              fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardPreview(Map<String, dynamic> p, String type, String hint) {
    switch (type) {
      case 'dropdown':
        final opts = List<String>.from(p['options'] ?? []);
        if (opts.isEmpty) {
          return const Text('No options defined',
              style: TextStyle(color: kSub, fontSize: 12));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: opts
              .take(4)
              .map((o) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      const Icon(Icons.radio_button_off, size: 13, color: kSub),
                      const SizedBox(width: 6),
                      Text(o,
                          style: const TextStyle(fontSize: 13, color: _kText)),
                    ]),
                  ))
              .toList(),
        );

      case 'dual_text':
        return Row(children: [
          Expanded(child: _darkBox(p['left_label'] ?? 'Left')),
          const SizedBox(width: 8),
          Expanded(child: _darkBox(p['right_label'] ?? 'Right')),
        ]);

      case 'slider':
        final mn = ((p['min'] ?? 0) as num).toDouble();
        final mx = ((p['max'] ?? 100) as num).toDouble();
        final safeMx = mx > mn ? mx : mn + 1;
        return Row(children: [
          Text('$mn', style: const TextStyle(fontSize: 12, color: kSub)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: kAccent,
                thumbColor: kAccent,
                inactiveTrackColor: kBorder,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: mn, min: mn, max: safeMx, onChanged: null),
            ),
          ),
          Text('$mx', style: const TextStyle(fontSize: 12, color: kSub)),
        ]);

      case 'multiline':
        return _darkBox(hint.isNotEmpty ? hint : 'Multiline comment…',
            height: 52);

      default:
        return _darkBox(hint.isNotEmpty ? hint : type);
    }
  }

  Widget _darkBox(String hint, {double height = 34}) => Container(
        height: height,
        decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        child: Text(hint, style: const TextStyle(fontSize: 12, color: kSub)),
      );

  Widget _typeBadge(String type, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(_typeLabel(type),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _iconTap(IconData icon, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color)),
      );

  Color _typeColor(String t) => _typeColorMap[t] ?? kSub;
  String _typeLabel(String t) => _typeLabelMap[t] ?? t;

  static const _typeColorMap = {
    'number': kAccent,
    'text': kSuccess,
    'dropdown': Color(0xFFBB86FC),
    'dual_text': kWarn,
    'slider': Color(0xFF03DAC6),
    'multiline': Color(0xFF7986CB),
  };
  static const _typeLabelMap = {
    'number': 'Number',
    'text': 'Text',
    'dropdown': 'Dropdown',
    'dual_text': 'Dual Input',
    'slider': 'Slider',
    'multiline': 'Multiline',
  };

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.isDuplicate
        ? 'Duplicate Tank'
        : _isEdit
            ? 'Modify Tank'
            : 'Create Tank';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: kText),
        title: Text(title,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700, fontSize: 17, color: kText)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kAccent))),
            )
          else
            TextButton(
              onPressed: () {
                debugPrint(
                    '[AppBar] ${_isEdit ? "Update" : "Create"} button tapped');
                _save();
              },
              child: Text(
                _isEdit ? 'Update' : 'Create',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: kAccent, fontSize: 15),
              ),
            ),
        ],
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: kSurface,
            labelStyle: TextStyle(color: kSub),
            hintStyle: TextStyle(color: kSub),
          ),
          textSelectionTheme:
              const TextSelectionThemeData(cursorColor: kAccent),
          colorScheme: const ColorScheme.dark(
            primary: kAccent,
            surface: kSurface,
            onSurface: kText,
          ),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _secHeader('Tank Details'),
                const SizedBox(height: 12),
                // ── Tank Code ──────────────────────────────────────────
                TextFormField(
                  controller: _codeCtrl,
                  style: const TextStyle(color: kText),
                  cursorColor: kAccent,
                  decoration: darkDeco(
                      label: 'Tank Code', icon: Icons.tag, hint: 'e.g. A1'),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Tank code is required' : null,
                ),
                const SizedBox(height: 12),
                // ── Tank Name ──────────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: kText),
                  cursorColor: kAccent,
                  decoration: darkDeco(
                      label: 'Tank Name',
                      icon: Icons.inventory_2_outlined,
                      hint: 'e.g. Gear Box'),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Tank name is required' : null,
                ),
                const SizedBox(height: 12),
                // ── Location ───────────────────────────────────────────
                TextFormField(
                  controller: _locCtrl,
                  readOnly: true,
                  style: const TextStyle(color: kText),
                  decoration: darkDeco(
                      label: 'Client',
                      icon: Icons.business_outlined,
                      hint: 'Root'),
                ),
                const SizedBox(height: 28),
                // ── Inspection Parameters ──────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _secHeader('Inspection Parameters'),
                          const SizedBox(height: 2),
                          const Text(
                              'Define fields inspectors fill in. Drag to reorder.',
                              style: TextStyle(fontSize: 12, color: kSub)),
                        ],
                      ),
                    ),
                    Text(
                      '${_properties.length} field${_properties.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: kSub),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_properties.isEmpty)
                  _emptyHint()
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _properties.length,
                    onReorder: (o, n) {
                      debugPrint('[Props] Reorder from $o to $n');
                      setState(() {
                        if (n > o) n--;
                        final item = _properties.removeAt(o);
                        _properties.insert(n, item);
                      });
                    },
                    itemBuilder: (_, i) => _buildPropertyCard(_properties[i]),
                  ),
                const SizedBox(height: 12),
                // ── Add Parameter button ───────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add, color: kAccent),
                    label: Text('Add Inspection Parameter',
                        style: GoogleFonts.inter(
                            color: kAccent, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      debugPrint('[Props] Add Inspection Parameter tapped');
                      _openPropertyBuilder();
                    },
                  ),
                ),
                const SizedBox(height: 28),
                // ── Primary CTA button ─────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kAccent.withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving
                        ? null
                        : () {
                            debugPrint(
                                '[CTA] Primary button tapped — isEdit=$_isEdit '
                                'isDuplicate=${widget.isDuplicate}');
                            _save();
                          },
                    child: Text(
                      _saving
                          ? 'Saving…'
                          : widget.isDuplicate
                              ? 'Create Duplicate'
                              : _isEdit
                                  ? 'Update Tank'
                                  : 'Create Tank',
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

  // ─── UI helpers ────────────────────────────────────────────────────────────

  Widget _secHeader(String t) => Text(t,
      style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: kSub,
          letterSpacing: 1.1));

  Widget _emptyHint() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder)),
        child: Column(children: [
          const Icon(Icons.list_alt_outlined, size: 38, color: kSub),
          const SizedBox(height: 10),
          Text('No parameters yet',
              style:
                  GoogleFonts.inter(color: kText, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Tap "Add Inspection Parameter" to start',
              style: TextStyle(fontSize: 12, color: kSub)),
        ]),
      );
}
