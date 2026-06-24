// lib/features/tanks/presentation/pages/then_parameters_manager_page.dart
// ══════════════════════════════════════════════════════════════════════════════
// Reuses the existing PropertyBuilderPage to build parameters inside THEN.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/features/tanks/presentation/pages/property_builder_page.dart';

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
const _kPurple = Color(0xFF9B7FE0);

class ThenParametersManagerPage extends StatefulWidget {
  final List<Map<String, dynamic>> initialParameters;
  final String scopeId;
  final List<String> ancestorScopeIds;

  const ThenParametersManagerPage({
    required this.initialParameters,
    required this.scopeId,
    required this.ancestorScopeIds,
    super.key,
  });

  @override
  State<ThenParametersManagerPage> createState() => _ThenParametersManagerPageState();
}

class _ThenParametersManagerPageState extends State<ThenParametersManagerPage> {
  final List<Map<String, dynamic>> _parameters = [];

  @override
  void initState() {
    super.initState();
    _parameters.addAll(
      widget.initialParameters.map((p) => Map<String, dynamic>.from(p)),
    );
    _syncScopeParams();
  }

  Future<void> _syncScopeParams() async {
    await SessionParamStore.clearScope(widget.scopeId);
    await SessionParamStore.upsertMany(
      widget.scopeId,
      _parameters
          .where((e) => e['type'] != 'group')
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  Future<void> _openPropertyBuilder({Map<String, dynamic>? existing}) async {
    await _syncScopeParams();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyBuilderPage(
          existing: existing,
          scopeId: widget.scopeId,
          ancestorScopeIds: [...widget.ancestorScopeIds, widget.scopeId],
          onSave: (prop) {
            setState(() {
              final idx = _parameters.indexWhere((e) => e['id'] == prop['id']);
              if (idx == -1) {
                _parameters.add(prop);
              } else {
                _parameters[idx] = prop;
              }
            });
            _syncScopeParams();
          },
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> p) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Delete Parameter',
            style: GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600)),
        content: Text('Delete "${p['label']}"? This cannot be undone.',
            style: const TextStyle(color: _kSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _kSub)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _parameters.removeWhere((e) => e['id'] == p['id']);
              });
              SessionParamStore.removeParam(widget.scopeId, p['id']?.toString() ?? '');
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );
  }

  void _save() {
    Navigator.pop(context, _parameters);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(
          'THEN Parameters',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w700, fontSize: 17, color: _kText),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: _kAccent, fontSize: 15),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THEN SECTION PARAMETERS',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kSub,
                  letterSpacing: 1.1),
            ),
            const SizedBox(height: 4),
            Text(
              'Define the additional inspection parameters that appear when this condition triggers.',
              style: GoogleFonts.inter(fontSize: 12, color: _kSub),
            ),
            const SizedBox(height: 20),
            if (_parameters.isEmpty)
              _buildEmptyState()
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _parameters.length,
                onReorder: (o, n) {
                  setState(() {
                    if (n > o) n--;
                    final item = _parameters.removeAt(o);
                    _parameters.insert(n, item);
                  });
                },
                itemBuilder: (_, i) => _buildParameterCard(_parameters[i]),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, color: _kAccent),
                label: Text(
                  'Add THEN Parameter',
                  style: GoogleFonts.inter(
                      color: _kAccent, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _openPropertyBuilder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder)),
      child: Column(
        children: [
          const Icon(Icons.list_alt_outlined, size: 38, color: _kSub),
          const SizedBox(height: 10),
          Text('No parameters defined',
              style: GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Tap "Add THEN Parameter" to configure workflow.',
              style: TextStyle(fontSize: 12, color: _kSub)),
        ],
      ),
    );
  }

  Widget _buildParameterCard(Map<String, dynamic> p) {
    final type = p['type'] as String? ?? 'text';
    final label = p['label'] as String? ?? 'Untitled';
    final hint = p['hint'] as String? ?? '';
    final isRequired = p['required'] == true;
    final captureImage = p['capture_image'] == true;
    final constraints = (p['constraints'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final hasThenWorkflow = constraints.any((c) => c['then_workflow_enabled'] == true);

    return Card(
      key: ValueKey('then-param-${p['id']}'),
      margin: const EdgeInsets.only(bottom: 10),
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _typeColor(type).withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 18, color: _kSub),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _kText)),
                ),
                _typeBadge(type, _typeColor(type)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: _kAccent),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openPropertyBuilder(existing: p),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: _kDanger),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _confirmDelete(p),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (hint.isNotEmpty) ...[
                      const Icon(Icons.info_outline, size: 13, color: _kSub),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(hint,
                              style: const TextStyle(fontSize: 12, color: _kSub))),
                    ] else
                      const Spacer(),
                    if (isRequired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: _kWarn.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('Required',
                            style: TextStyle(
                                fontSize: 10,
                                color: _kWarn,
                                fontWeight: FontWeight.w600)),
                      ),
                    if (captureImage) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: _kAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('Photo',
                            style: TextStyle(
                                fontSize: 10,
                                color: _kAccent,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (hasThenWorkflow) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: _kPurple.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('IF-THEN Nested',
                            style: TextStyle(
                                fontSize: 10,
                                color: _kPurple,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
                if (constraints.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: constraints.map((c) {
                      final op = c['op'] as String? ?? '';
                      final val = c['value'] as String? ?? '';
                      final condWorkflow = c['then_workflow_enabled'] == true;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: condWorkflow
                                ? _kPurple.withOpacity(0.13)
                                : const Color(0xFFBB86FC).withOpacity(0.13),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: condWorkflow
                                    ? _kPurple.withOpacity(0.4)
                                    : const Color(0xFFBB86FC).withOpacity(0.4))),
                        child: Text(
                          '${_opSymbol(type, op)} $val${condWorkflow ? " [IF-THEN]" : ""}',
                          style: TextStyle(
                              fontSize: 11,
                              color: condWorkflow ? _kPurple : const Color(0xFFBB86FC),
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

  Widget _typeBadge(String type, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(_typeLabel(type),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Color _typeColor(String t) {
    return const {
          'number': _kAccent,
          'text': _kSuccess,
          'dropdown': Color(0xFFBB86FC),
          'dual_text': _kWarn,
          'slider': Color(0xFF03DAC6),
          'multiline': Color(0xFF7986CB),
          'group': Color(0xFFF06292),
        }[t] ??
        _kSub;
  }

  String _typeLabel(String t) {
    return const {
          'number': 'Number',
          'text': 'Text',
          'dropdown': 'Dropdown',
          'dual_text': 'Dual Input',
          'slider': 'Slider',
          'multiline': 'Multiline',
          'group': 'Group',
        }[t] ??
        t;
  }

  String _opSymbol(String type, String op) {
    if (type == 'dropdown') {
      return op == '==' ? 'is' : 'is not';
    }
    return op;
  }
}
