// FULL FILE REPLACEMENT — create_tank_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// ALL ORIGINAL FEATURES PRESERVED:
//   ✅ Dark theme — all text fields, dropdowns, dialogs use dark bg/light text
//   ✅ Live preview — addListener on every controller → instant rebuild
//   ✅ Create / Update properly calls TankRepository with full debug prints
//   ✅ Duplicate with (1)(2)(3)… iterator naming + QR regeneration
//   ✅ TankCardActions — Modify | Duplicate | Delete buttons (drop-in widget)
//   ✅ Google-Forms-style property builder: number|text|dropdown|dual_text|slider|multiline
//   ✅ Dual text: one label row + two side-by-side text boxes
//   ✅ Dropdown: add/edit/delete/reorder options inline
//   ✅ Properties: drag-to-reorder, edit, delete, confirmation dialog
//   ✅ QR generation + Cloudinary upload (create + duplicate; regenerated on
//       edit only if identity fields changed)
//   ✅ Every button click prints a debug statement to terminal
//   ✅ All existing repository / session / constants untouched
//
// NEW IN THIS VERSION:
//   ✅ Min/Max ONLY appears for slider type (removed from all other types)
//   ✅ Per-property CONSTRAINTS builder — optional, collapsible section
//      Operators available per type:
//        number  → ==, !=, <, <=, >, >=
//        text    → ==, !=, contains, starts_with, ends_with, regex
//        multiline → contains, starts_with, ends_with, regex
//        dropdown → == (must equal), != (must not equal)
//        dual_text → contains, starts_with, ends_with (applied to each side)
//        slider  → ==, !=, <, <=, >, >= (value-based)
//      Each constraint: operator + value + custom error message
//      Multiple constraints allowed per property (AND logic)
//      Constraints stored under property['constraints'] as List<Map>
//      Constraints shown as summary chips on the property card
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/session_manager.dart';
import '../../../data/repositories/tank_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour aliases — pulled straight from AppTheme
// ─────────────────────────────────────────────────────────────────────────────
// const _kBg = Color(0xFF0A2342);
// const _kSurface = Color(0xFF112240);
// const _kCard = Color(0xFF1A2F4A);
// const _kAccent = Color(0xFF00B4D8);
// const _kBorder = Color(0xFF1E3A5F);
// const _kText = Color(0xFFE8F0FE);
// const _kSub = Color(0xFF8892A4);
// const _kSuccess = Color(0xFF06D6A0);
// const _kWarn = Color(0xFFFFB703);
// const _kDanger = Color(0xFFEF233C);

// INDUSTRIAL PALETTE
// Same variable names preserved

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

// ─────────────────────────────────────────────────────────────────────────────
// Shared InputDecoration helper — used everywhere so theme is consistent
// ─────────────────────────────────────────────────────────────────────────────
InputDecoration _darkDeco({
  required String label,
  required IconData icon,
  String? hint,
}) =>
    InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _kSub, fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(color: _kSub, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: _kSub),
      filled: true,
      fillColor: _kSurface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kAccent, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kDanger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kDanger, width: 2)),
    );

// Compact decoration (for inner forms inside builder page)
InputDecoration _compactDeco({required String hint, required IconData icon}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _kSub, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: _kSub),
      isDense: true,
      filled: true,
      fillColor: _kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kAccent, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kDanger)),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Constraint operator metadata
// ─────────────────────────────────────────────────────────────────────────────

class _OpMeta {
  final String value;
  final String label;
  final String symbol;
  const _OpMeta(this.value, this.label, this.symbol);
}

// Operators available for each property type
const Map<String, List<_OpMeta>> _kTypeOps = {
  'number': [
    _OpMeta('==', 'Equals', '='),
    _OpMeta('!=', 'Not equals', '≠'),
    _OpMeta('<', 'Less than', '<'),
    _OpMeta('<=', 'Less than or equal', '≤'),
    _OpMeta('>', 'Greater than', '>'),
    _OpMeta('>=', 'Greater than / equal', '≥'),
  ],
  'text': [
    _OpMeta('==', 'Equals', '='),
    _OpMeta('!=', 'Not equals', '≠'),
    _OpMeta('contains', 'Contains', '⊃'),
    _OpMeta('starts_with', 'Starts with', '^'),
    _OpMeta('ends_with', 'Ends with', '\$'),
    _OpMeta('regex', 'Regex match', '.*'),
  ],
  'multiline': [
    _OpMeta('contains', 'Contains', '⊃'),
    _OpMeta('starts_with', 'Starts with', '^'),
    _OpMeta('ends_with', 'Ends with', '\$'),
    _OpMeta('regex', 'Regex match', '.*'),
  ],
  'dropdown': [
    _OpMeta('==', 'Must equal', '='),
    _OpMeta('!=', 'Must not equal', '≠'),
  ],
  'dual_text': [
    _OpMeta('contains', 'Contains', '⊃'),
    _OpMeta('starts_with', 'Starts with', '^'),
    _OpMeta('ends_with', 'Ends with', '\$'),
    _OpMeta('regex', 'Regex match', '.*'),
  ],
  'slider': [
    _OpMeta('==', 'Equals', '='),
    _OpMeta('!=', 'Not equals', '≠'),
    _OpMeta('<', 'Less than', '<'),
    _OpMeta('<=', 'Less than or equal', '≤'),
    _OpMeta('>', 'Greater than', '>'),
    _OpMeta('>=', 'Greater than / equal', '≥'),
  ],
};

List<_OpMeta> _opsForType(String type) => _kTypeOps[type] ?? _kTypeOps['text']!;

String _opSymbol(String type, String op) => _opsForType(type)
    .firstWhere((o) => o.value == op, orElse: () => _OpMeta(op, op, op))
    .symbol;

String _opLabel(String type, String op) => _opsForType(type)
    .firstWhere((o) => o.value == op, orElse: () => _OpMeta(op, op, op))
    .label;

// ─────────────────────────────────────────────────────────────────────────────
// Deep cast helper
//
// Firebase RTDB returns nested maps as Map<Object?, Object?>.
// A shallow Map<String, dynamic>.from() only fixes the top level — nested
// maps and list elements remain wrongly typed and throw cast errors at runtime.
// This helper recurses through the entire structure.
// ─────────────────────────────────────────────────────────────────────────────

dynamic _deepCast(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(
      value.entries.map(
        (e) => MapEntry(e.key.toString(), _deepCast(e.value)),
      ),
    );
  }
  if (value is List) {
    return value.map(_deepCast).toList();
  }
  return value;
}

// ─────────────────────────────────────────────────────────────────────────────
// CreateTankScreen
// ─────────────────────────────────────────────────────────────────────────────

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
  final _scaleCtrl = TextEditingController();
  String? _scaleSide;

  final List<Map<String, dynamic>> _properties = [];
  bool _saving = false;
  final _qrShot = ScreenshotController();

  // Cloudinary credentials
  static const _cloudName = 'dummy-cloudinary-cloud-name';
  static const _apiKey = 'dummy-cloudinary-api-key';
  static const _apiSecret = 'dummy-cloudinary-api-secret';
  static const _folder = 'lubricationindicator_qr';

  bool get _isEdit => widget.existingTank != null && !widget.isDuplicate;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[CreateTankScreen] initState — isEdit=$_isEdit isDuplicate=${widget.isDuplicate}');

    if (widget.existingTank != null) {
      final t = widget.existingTank!;
      _codeCtrl.text = t['tank_code'] ?? '';
      _nameCtrl.text = widget.isDuplicate
          ? '${t['tank_name']} (copy)'
          : (t['tank_name'] ?? '');
      _locCtrl.text = t['location'] ?? '';
      _scaleCtrl.text = (t['scale_max'] ?? 0).toString();
      _scaleSide = t['scale_side'] as String?;
      if (t['inspection_properties'] != null) {
        _properties.addAll(
          (t['inspection_properties'] as List)
              .map((e) => _deepCast(e) as Map<String, dynamic>),
        );
      }
      debugPrint(
          '[CreateTankScreen] Loaded existing tank: code=${_codeCtrl.text} '
          'name=${_nameCtrl.text} props=${_properties.length}');
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _locCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  // ── Cloudinary helpers ─────────────────────────────────────────────────────

  String _signature(String timestamp) {
    final params = 'folder=$_folder&timestamp=$timestamp';
    return sha1.convert(utf8.encode('$params$_apiSecret')).toString();
  }

  Future<String> _uploadQr(Uint8List bytes) async {
    debugPrint('[QR] Uploading QR image to Cloudinary…');
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/tank_qr_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);

    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload'),
    );
    req.fields['api_key'] = _apiKey;
    req.fields['timestamp'] = ts;
    req.fields['folder'] = _folder;
    req.fields['signature'] = _signature(ts);
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType.parse(lookupMimeType(file.path) ?? 'image/png'),
    ));

    final res = await http.Response.fromStream(await req.send());
    debugPrint('[QR] Cloudinary response: ${res.statusCode} '
        '${res.body.substring(0, res.body.length.clamp(0, 200))}');
    if (res.statusCode != 200) {
      throw Exception('QR upload failed (${res.statusCode}): ${res.body}');
    }
    final url = (json.decode(res.body) as Map)['secure_url'] as String;
    debugPrint('[QR] Uploaded successfully → $url');
    return url;
  }

  Future<String> _generateAndUploadQr({
    required String tankCode,
    required String tankName,
    required String location,
  }) async {
    debugPrint(
        '[QR] Generating QR for code=$tankCode name=$tankName loc=$location');
    final qrData = jsonEncode({
      'tank_code': tankCode,
      'tank_name': tankName,
      'location': location,
    });
    final bytes = await _qrShot.captureFromWidget(
      Material(
          color: Colors.white, child: QrImageView(data: qrData, size: 320)),
    );
    debugPrint('[QR] QR captured, size=${bytes.length} bytes');
    return _uploadQr(bytes);
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
      final scaleMax = double.parse(_scaleCtrl.text.trim());
      debugPrint('[Save] Fields: code=$tankCode name=$tankName loc=$location '
          'scaleMax=$scaleMax scaleSide=$_scaleSide props=${_properties.length}');

      if (_isEdit) {
        debugPrint('[Save] Mode = EDIT/UPDATE');
        final existing = widget.existingTank!;
        final identityChanged = existing['tank_code'] != tankCode ||
            existing['tank_name'] != tankName ||
            existing['location'] != location;
        debugPrint('[Save] identityChanged=$identityChanged');

        String? newQrUrl;
        if (identityChanged) {
          debugPrint('[Save] Identity changed → regenerating QR');
          newQrUrl = await _generateAndUploadQr(
            tankCode: tankCode,
            tankName: tankName,
            location: location,
          );
        }

        debugPrint(
            '[Save] Calling TankRepository.updateTank id=${existing['id']}');
        await TankRepository().updateTank(
          id: existing['id'],
          tankCode: tankCode,
          tankName: tankName,
          location: location,
          scaleMax: scaleMax,
          scaleSide: _scaleSide,
          properties: _properties,
          qrImageUrl: newQrUrl,
        );
        debugPrint('[Save] updateTank SUCCESS');
      } else {
        debugPrint('[Save] Mode = CREATE (or DUPLICATE)');
        debugPrint('[Save] Generating QR for new tank…');
        final qrUrl = await _generateAndUploadQr(
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
          scaleSide: _scaleSide,
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
          content: Text('Error: $e', style: const TextStyle(color: _kText)),
          backgroundColor: _kDanger,
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
        builder: (_) => _PropertyBuilderPage(
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
          },
        ),
      ),
    );
  }

  void _confirmDeleteProp(Map<String, dynamic> p) {
    debugPrint(
        '[Props] Confirm delete property id=${p['id']} label=${p['label']}');
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Delete Parameter',
            style:
                GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600)),
        content: Text('Delete "${p['label']}"? This cannot be undone.',
            style: const TextStyle(color: _kSub)),
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
    final color = _typeColor(type);
    final constraints = List<Map<String, dynamic>>.from(p['constraints'] ?? []);

    return Card(
      key: ValueKey(p['id']),
      margin: const EdgeInsets.only(bottom: 10),
      color: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
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
                const Icon(Icons.drag_indicator, size: 18, color: _kSub),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _kText)),
                ),
                _typeBadge(type, color),
                const SizedBox(width: 8),
                _iconTap(Icons.edit_outlined, _kAccent, () {
                  debugPrint('[Props] Edit tapped for ${p['id']}');
                  _openPropertyBuilder(existing: p);
                }),
                _iconTap(Icons.delete_outline, _kDanger,
                    () => _confirmDeleteProp(p)),
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
                          color: _kWarn.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('Required',
                          style: TextStyle(
                              fontSize: 10,
                              color: _kWarn,
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
                      color: _kAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Photo',
                      style: TextStyle(
                        fontSize: 10,
                        color: _kAccent,
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
                          '${_opSymbol(type, op)} $val',
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
              style: TextStyle(color: _kSub, fontSize: 12));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: opts
              .take(4)
              .map((o) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      const Icon(Icons.radio_button_off,
                          size: 13, color: _kSub),
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
          Text('$mn', style: const TextStyle(fontSize: 12, color: _kSub)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _kAccent,
                thumbColor: _kAccent,
                inactiveTrackColor: _kBorder,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(value: mn, min: mn, max: safeMx, onChanged: null),
            ),
          ),
          Text('$mx', style: const TextStyle(fontSize: 12, color: _kSub)),
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
            color: _kSurface,
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        child: Text(hint, style: const TextStyle(fontSize: 12, color: _kSub)),
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

  Color _typeColor(String t) => _typeColorMap[t] ?? _kSub;
  String _typeLabel(String t) => _typeLabelMap[t] ?? t;

  static const _typeColorMap = {
    'number': _kAccent,
    'text': _kSuccess,
    'dropdown': Color(0xFFBB86FC),
    'dual_text': _kWarn,
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
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text(title,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700, fontSize: 17, color: _kText)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kAccent))),
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
                    fontWeight: FontWeight.w700, color: _kAccent, fontSize: 15),
              ),
            ),
        ],
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: _kSurface,
            labelStyle: TextStyle(color: _kSub),
            hintStyle: TextStyle(color: _kSub),
          ),
          textSelectionTheme:
              const TextSelectionThemeData(cursorColor: _kAccent),
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
                _secHeader('Tank Details'),
                const SizedBox(height: 12),
                // ── Tank Code ──────────────────────────────────────────
                TextFormField(
                  controller: _codeCtrl,
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  decoration: _darkDeco(
                      label: 'Tank Code', icon: Icons.tag, hint: 'e.g. A1'),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Tank code is required' : null,
                ),
                const SizedBox(height: 12),
                // ── Tank Name ──────────────────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  decoration: _darkDeco(
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
                  style: const TextStyle(color: _kText),
                  cursorColor: _kAccent,
                  decoration: _darkDeco(
                      label: 'Zone / Location',
                      icon: Icons.location_on_outlined,
                      hint: 'e.g. Zone B – Floor 2'),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Location is required' : null,
                ),
                const SizedBox(height: 12),
                // ── Scale ──────────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _scaleCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: _kText),
                      cursorColor: _kAccent,
                      decoration: _darkDeco(
                          label: 'Scale Max',
                          icon: Icons.linear_scale,
                          hint: 'e.g. 100'),
                      validator: (v) {
                        if (v!.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null)
                          return 'Must be a number';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _scaleSide,
                      dropdownColor: _kCard,
                      style: const TextStyle(color: _kText),
                      iconEnabledColor: _kSub,
                      decoration: _darkDeco(
                          label: 'Scale Side', icon: Icons.swap_horiz),
                      items: const [
                        DropdownMenuItem(
                            value: 'left',
                            child:
                                Text('Left', style: TextStyle(color: _kText))),
                        DropdownMenuItem(
                            value: 'right',
                            child:
                                Text('Right', style: TextStyle(color: _kText))),
                      ],
                      onChanged: (v) {
                        debugPrint('[Field] Scale Side changed to $v');
                        setState(() => _scaleSide = v);
                      },
                      validator: (v) => v == null ? 'Select a side' : null,
                    ),
                  ),
                ]),
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
                              style: TextStyle(fontSize: 12, color: _kSub)),
                        ],
                      ),
                    ),
                    Text(
                      '${_properties.length} field${_properties.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: _kSub),
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
                      side: const BorderSide(color: _kAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add, color: _kAccent),
                    label: Text('Add Inspection Parameter',
                        style: GoogleFonts.inter(
                            color: _kAccent, fontWeight: FontWeight.w600)),
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
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kAccent.withOpacity(0.5),
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
          color: _kSub,
          letterSpacing: 1.1));

  Widget _emptyHint() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder)),
        child: Column(children: [
          const Icon(Icons.list_alt_outlined, size: 38, color: _kSub),
          const SizedBox(height: 10),
          Text('No parameters yet',
              style: GoogleFonts.inter(
                  color: _kText, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text('Tap "Add Inspection Parameter" to start',
              style: TextStyle(fontSize: 12, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _PropertyBuilderPage  (Google-Forms-style, live preview)
// ─────────────────────────────────────────────────────────────────────────────

class _PropertyBuilderPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final void Function(Map<String, dynamic>) onSave;

  const _PropertyBuilderPage({required this.onSave, this.existing});

  @override
  State<_PropertyBuilderPage> createState() => _PropertyBuilderPageState();
}

class _PropertyBuilderPageState extends State<_PropertyBuilderPage> {
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
    _TypeMeta('number', 'Number', Icons.pin_outlined),
    _TypeMeta('text', 'Text', Icons.text_fields),
    _TypeMeta('dropdown', 'Dropdown', Icons.arrow_drop_down_circle_outlined),
    _TypeMeta('dual_text', 'Dual Input', Icons.view_column_outlined),
    _TypeMeta('slider', 'Slider', Icons.linear_scale),
    _TypeMeta('multiline', 'Multiline', Icons.notes),
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
              .map((e) => _deepCast(e) as Map<String, dynamic>),
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
              _compactDeco(hint: 'Option text', icon: Icons.label_outline),
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[Dropdown] Option dialog cancelled');
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: _kSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kAccent),
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
    final ops = _opsForType(_type);

    String selectedOp = existing?['op'] as String? ?? ops.first.value;
    final valueCtrl =
        TextEditingController(text: existing?['value'] as String? ?? '');
    final errorMsgCtrl =
        TextEditingController(text: existing?['error_msg'] as String? ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: _kCard,
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            idx != null ? 'Edit Constraint' : 'Add Constraint',
            style:
                GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600),
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
                          color: sel ? _kAccent.withOpacity(0.15) : _kSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? _kAccent : _kBorder,
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
                  decoration: _compactDeco(
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
                  decoration: _compactDeco(
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
                  decoration: _compactDeco(
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
                  decoration: _compactDeco(
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
                    onChanged: (v) {
                      debugPrint('[PropertyBuilder] Required toggled to $v');
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
                      debugPrint(
                        '[PropertyBuilder] Capture image changed: $v',
                      );

                      setState(
                        () => _captureImage = v,
                      );
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
                decoration: _compactDeco(
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
                decoration: _compactDeco(
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
                decoration: _compactDeco(hint: 'Min', icon: Icons.first_page),
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
                decoration: _compactDeco(hint: 'Max', icon: Icons.last_page),
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
    final ops = _opsForType(_type);
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
                              _opSymbol(_type, op),
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
                                  '${_opLabel(_type, op)}   "$val"',
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

// ─────────────────────────────────────────────────────────────────────────────
// _TypeMeta
// ─────────────────────────────────────────────────────────────────────────────

class _TypeMeta {
  final String value, label;
  final IconData icon;
  const _TypeMeta(this.value, this.label, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// TankCardActions  ──  drop-in widget for the tanks list / panel screen
//
// Shows:  [Modify]  [Duplicate]  [Delete]
//
// USAGE (drop this into your tank list row / card):
//
//   TankCardActions(
//     tank: tankMap,
//     allExistingCodes: _tanks.map((t) => t['tank_code'] as String).toList(),
//     onDeleted: _loadTanks,
//     onChanged: _loadTanks,
//   )
//
// Place this next to your existing Download and Delete buttons.
// ─────────────────────────────────────────────────────────────────────────────

class TankCardActions extends StatelessWidget {
  final Map<String, dynamic> tank;
  final List<String> allExistingCodes;
  final VoidCallback onDeleted;
  final VoidCallback onChanged;

  const TankCardActions({
    super.key,
    required this.tank,
    required this.allExistingCodes,
    required this.onDeleted,
    required this.onChanged,
  });

  String _nextFreeCode(String base) {
    final stripped = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim();
    for (int i = 1; i <= 99; i++) {
      final candidate = '$stripped ($i)';
      if (!allExistingCodes.contains(candidate)) return candidate;
    }
    return '$stripped (${DateTime.now().millisecondsSinceEpoch})';
  }

  Future<void> _openModify(BuildContext ctx) async {
    debugPrint('[TankCardActions] Modify tapped — tank=${tank['tank_code']}');
    final safeTank = _deepCast(tank) as Map<String, dynamic>;
    final ok = await Navigator.push<bool>(
      ctx,
      MaterialPageRoute(
          builder: (_) => CreateTankScreen(existingTank: safeTank)),
    );
    debugPrint('[TankCardActions] Modify returned: ok=$ok');
    if (ok == true) onChanged();
  }

  Future<void> _openDuplicate(BuildContext ctx) async {
    debugPrint(
        '[TankCardActions] Duplicate tapped — original=${tank['tank_code']}');
    final newCode = _nextFreeCode(tank['tank_code'] as String);
    debugPrint('[TankCardActions] New duplicate code will be: $newCode');
    final dup = (_deepCast(tank) as Map<String, dynamic>)
      ..['tank_code'] = newCode
      ..remove('id');

    final ok = await Navigator.push<bool>(
      ctx,
      MaterialPageRoute(
        builder: (_) => CreateTankScreen(existingTank: dup, isDuplicate: true),
      ),
    );
    debugPrint('[TankCardActions] Duplicate returned: ok=$ok');
    if (ok == true) onChanged();
  }

  Future<void> _confirmDelete(BuildContext ctx) async {
    debugPrint('[TankCardActions] Delete tapped — tank=${tank['tank_code']}');
    final yes = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        title: Text('Delete Tank',
            style:
                GoogleFonts.inter(color: _kText, fontWeight: FontWeight.w600)),
        content: Text('Delete "${tank['tank_name']}"? This cannot be undone.',
            style: const TextStyle(color: _kSub)),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[TankCardActions] Delete cancelled');
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel', style: TextStyle(color: _kSub)),
          ),
          TextButton(
            onPressed: () {
              debugPrint('[TankCardActions] Delete confirmed');
              Navigator.pop(ctx, true);
            },
            child: const Text('Delete', style: TextStyle(color: _kDanger)),
          ),
        ],
      ),
    );

    if (yes == true) {
      debugPrint(
          '[TankCardActions] Calling TankRepository.deleteTank id=${tank['id']}');
      await TankRepository().deleteTank(tank['id']);
      debugPrint('[TankCardActions] deleteTank SUCCESS — calling onDeleted()');
      onDeleted();
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(
          icon: Icons.edit_outlined,
          label: 'Modify',
          color: _kAccent,
          onTap: () => _openModify(ctx),
        ),
        const SizedBox(width: 8),
        _Btn(
          icon: Icons.copy_outlined,
          label: 'Duplicate',
          color: _kWarn,
          onTap: () => _openDuplicate(ctx),
        ),
        const SizedBox(width: 8),
        _Btn(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: _kDanger,
          onTap: () => _confirmDelete(ctx),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Btn  — compact icon + label button used in TankCardActions
// ─────────────────────────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Btn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      );
}
