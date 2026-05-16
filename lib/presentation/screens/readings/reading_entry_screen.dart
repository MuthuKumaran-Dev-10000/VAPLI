// lib/presentation/screens/readings/reading_entry_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// WHAT'S NEW (v2):
//   ✅ Global "Reference Photo" section REMOVED
//   ✅ Per-parameter capture_image support:
//        capture_image: true  → camera button + thumbnail inside param card
//                               capturing is REQUIRED (blocks save)
//        capture_image: false → no camera UI for that param
//        key absent           → no camera UI (treated as false)
//   ✅ Number hint shown TWO ways:
//        (i)  above the field as hint text label
//        (ii) as placeholder text inside the input box ("inaf")
//   ✅ Deep copy of inspectionProperties → fixes cross-tank param bleed bug
//   ✅ All dynamic property types: number | text | multiline | dropdown |
//      dual_text | slider
//   ✅ Required-field enforcement blocks save button
//   ✅ Industrial luxury UI (copper accents, obsidian background) unchanged
//   ✅ On successful save → DashboardStatsRepository.updateStatsAfterReading()
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
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

// ── Palette (matches app_theme.dart AppColors) ────────────────────────────────
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

// ── Cloudinary ────────────────────────────────────────────────────────────────
const _cloudName = 'dummy-cloudinary-cloud-name';
const _apiKey = 'dummy-cloudinary-api-key';
const _apiSecret = 'dummy-cloudinary-api-secret';
const _folder = 'lubricationindicator';

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

  // ── save state ────────────────────────────────────────────────────────────
  bool _saving = false;
  bool _saved = false;
  bool _failed = false;
  String? _uploadError;

  // ── dynamic property controllers ──────────────────────────────────────────
  final Map<String, TextEditingController> _textCtrl = {};
  final Map<String, TextEditingController> _dualLeft = {};
  final Map<String, TextEditingController> _dualRight = {};
  final Map<String, String?> _dropdownVal = {};
  final Map<String, double> _sliderVal = {};

  /// Per-parameter photo (only for params where capture_image == true)
  final Map<String, File?> _paramPhoto = {};

  // ── DEEP COPY of inspection properties ───────────────────────────────────
  // FIX: shallow copy caused cross-tank parameter bleed when Flutter reused
  // widget state across tank navigations. Deep-copy every map so mutations
  // (e.g. controller attachment) never bleed into the TankModel's original list.
  late final List<Map<String, dynamic>> _props;

  String get _nowLabel =>
      DateFormat('dd MMM yyyy, HH:mm:ss').format(DateTime.now());

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // ── Deep copy to prevent cross-tank bleed ──────────────────────────────
    _props = widget.tank.inspectionProperties
        .map((p) => Map<String, dynamic>.from(
              // Also deep-copy any nested lists (e.g. options, constraints)
              p.map((k, v) {
                if (v is List) return MapEntry(k, List<dynamic>.from(v));
                if (v is Map)
                  return MapEntry(k, Map<String, dynamic>.from(v as Map));
                return MapEntry(k, v);
              }),
            ))
        .toList();

    // ── Initialise input controllers ───────────────────────────────────────
    for (final p in _props) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';

      switch (type) {
        case 'number':
        case 'text':
        case 'multiline':
          _textCtrl[id] = TextEditingController();
          break;
        case 'dropdown':
          _dropdownVal[id] = null;
          break;
        case 'slider':
          _sliderVal[id] = ((p['min'] ?? 0) as num).toDouble();
          break;
        case 'dual_text':
          _dualLeft[id] = TextEditingController();
          _dualRight[id] = TextEditingController();
          break;
      }

      // Initialise per-param photo slot if capture_image == true
      if (p['capture_image'] == true) {
        _paramPhoto[id] = null;
      }
    }
  }

  @override
  void dispose() {
    _textCtrl.values.forEach((c) => c.dispose());
    _dualLeft.values.forEach((c) => c.dispose());
    _dualRight.values.forEach((c) => c.dispose());
    super.dispose();
  }

  // ── validation ────────────────────────────────────────────────────────────

  String? _validateConstraints(Map<String, dynamic> prop, dynamic value) {
    final constraints =
        List<Map<String, dynamic>>.from(prop['constraints'] ?? []);

    for (final c in constraints) {
      final op = c['op']?.toString() ?? '';
      final expected = c['value']?.toString() ?? '';
      final msg = c['error_msg']?.toString() ?? 'Invalid value';
      final actual = value.toString();

      switch (op) {
        case '<':
          if ((double.tryParse(actual) ?? 0) >=
              (double.tryParse(expected) ?? 0)) return msg;
          break;
        case '<=':
          if ((double.tryParse(actual) ?? 0) > (double.tryParse(expected) ?? 0))
            return msg;
          break;
        case '>':
          if ((double.tryParse(actual) ?? 0) <=
              (double.tryParse(expected) ?? 0)) return msg;
          break;
        case '>=':
          if ((double.tryParse(actual) ?? 0) < (double.tryParse(expected) ?? 0))
            return msg;
          break;
        case '==':
          if (actual != expected) return msg;
          break;
        case '!=':
          if (actual == expected) return msg;
          break;
        case 'contains':
          if (!actual.contains(expected)) return msg;
          break;
      }
    }
    return null;
  }

  String? _requiredError() {
    for (final p in _props) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';
      final label = p['label'] as String? ?? 'Parameter';
      final isReq = p['required'] == true;
      final hasCam = p['capture_image'] == true;

      // Per-parameter photo required check
      if (hasCam && (_paramPhoto[id] == null)) {
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
          break; // always has value
      }
    }
    return null;
  }

  /// canSave: at least one param has capture_image==true → its photo must exist.
  /// No global photo requirement anymore.
  bool get _canSave {
    if (_saving || _saved) return false;
    // Check all per-param photos that are required
    for (final p in _props) {
      if (p['capture_image'] == true) {
        final id = p['id'] as String;
        if (_paramPhoto[id] == null) return false;
      }
    }
    return true;
  }

  // ── collect values ────────────────────────────────────────────────────────

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

  // ── camera ────────────────────────────────────────────────────────────────

  Future<void> _captureParamImage(String paramId) async {
    final img =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null) return;
    setState(() {
      _paramPhoto[paramId] = File(img.path);
      _uploadError = null;
    });
  }

  // ── Cloudinary ────────────────────────────────────────────────────────────

  String _sig(String ts) => sha1
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

  // ── save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final propErr = _requiredError();
    if (propErr != null) {
      _snack(propErr, _kDanger);
      return;
    }

    setState(() {
      _saving = true;
      _saved = false;
      _failed = false;
      _uploadError = null;
    });

    try {
      // Upload all per-parameter photos and collect their URLs
      final paramImageUrls = <String, String>{};
      for (final p in _props) {
        final id = p['id'] as String;
        if (p['capture_image'] == true && _paramPhoto[id] != null) {
          final url = await _uploadFile(_paramPhoto[id]!);
          paramImageUrls[id] = url;
        }
      }

      // Collect inspection values
      final inspVals = _collectValues();

      // Merge param image URLs into inspection values so they persist
      // Key convention: "<param_id>__image_url"
      for (final entry in paramImageUrls.entries) {
        inspVals['${entry.key}__image_url'] = entry.value;
      }

      // Validate constraints
      for (final p in _props) {
        final label = p['label'];
        final value = inspVals[label];
        final err = _validateConstraints(p, value);
        if (err != null) {
          _snack(err, _kDanger);
          setState(() => _saving = false);
          return;
        }
      }

      // Use first param image URL as the primary reading imageUrl,
      // or empty string if none (no global photo anymore)
      final primaryImageUrl =
          paramImageUrls.values.isNotEmpty ? paramImageUrls.values.first : '';

      // 1 ── Save reading
      final reading = await ReadingRepository().saveReading(
        tankId: widget.tank.id,
        tankName: widget.tank.tankName,
        level: 0, // vestigial field, kept for schema compat
        capturedBy: widget.currentUser.id,
        capturedByName: widget.currentUser.fullName,
        imageUrl: primaryImageUrl,
        inspectionValues: inspVals,
      );

      // 2 ── Incrementally update dashboard stats
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

  // ── BUILD ─────────────────────────────────────────────────────────────────

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
            // ── Meta card ─────────────────────────────────────────────────
            _MetaCard(
              tank: widget.tank,
              currentUser: widget.currentUser,
              nowLabel: _nowLabel,
            ),

            // ── Inspection parameters ─────────────────────────────────────
            if (_props.isNotEmpty) ...[
              const SizedBox(height: 28),
              _SecLabel('INSPECTION PARAMETERS'),
              const SizedBox(height: 4),
              Text(
                'Fields marked * are required',
                style: GoogleFonts.dmSans(fontSize: 11, color: _kSub),
              ),
              const SizedBox(height: 16),
              ..._props.map(_buildPropField),
            ],

            const SizedBox(height: 28),

            // ── Save button ───────────────────────────────────────────────
            _SaveButton(
              saving: _saving,
              saved: _saved,
              failed: _failed,
              canSave: _canSave,
              onTap: _canSave ? _save : null,
            ),

            if (_uploadError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kDanger.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: _kDanger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_uploadError!,
                        style:
                            GoogleFonts.dmSans(color: _kDanger, fontSize: 12)),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Dynamic property builder ──────────────────────────────────────────────

  Widget _buildPropField(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final type = p['type'] as String? ?? 'text';
    final label = p['label'] as String? ?? 'Parameter';
    final hint = p['hint'] as String? ?? '';
    final isReq = p['required'] == true;
    final hasCam = p['capture_image'] == true;

    // A param with capture_image:true is implicitly required
    final isEffectivelyRequired = isReq || hasCam;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label row ────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Text(
                isEffectivelyRequired ? '$label *' : label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _kText),
              ),
            ),
            if (isEffectivelyRequired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _kDanger.withOpacity(0.3)),
                ),
                child: Text('REQUIRED',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        color: _kDanger,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
          ]),

          // ── Hint text above field (for number type) ───────────────────
          // For number: show hint BOTH above the field AND as placeholder
          // For others: show hint above only when present
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(hint, style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
          ],

          const SizedBox(height: 8),

          // ── Input widget ──────────────────────────────────────────────
          _buildInput(p, id, type, hint, isReq),

          // ── Per-parameter camera section ──────────────────────────────
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

  InputDecoration _dec(String hintText, {String? placeholder}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _kBorder),
    );
    return InputDecoration(
      // placeholder shown inside box (used for number type)
      hintText: placeholder ?? (hintText.isNotEmpty ? hintText : null),
      hintStyle: GoogleFonts.dmSans(color: _kSub, fontSize: 13),
      filled: true,
      fillColor: _kSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kCopper, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kDanger)),
    );
  }

  Widget _buildInput(
      Map<String, dynamic> p, String id, String type, String hint, bool isReq) {
    switch (type) {
      // ── Number ────────────────────────────────────────────────────────
      // hint shown above the field (already done in _buildPropField)
      // AND as placeholder text inside the box
      case 'number':
        return TextFormField(
          controller: _textCtrl[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.spaceGrotesk(color: _kText, fontSize: 15),
          cursorColor: _kCopper,
          // placeholder inside box = hint text (shows "inaf" or whatever hint says)
          decoration: _dec(hint, placeholder: hint.isNotEmpty ? hint : null),
          onChanged: (_) => setState(() {}),
          validator: isReq
              ? (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null)
                    return 'Must be a number';
                  return null;
                }
              : null,
        );

      // ── Text ──────────────────────────────────────────────────────────
      case 'text':
        return TextFormField(
          controller: _textCtrl[id],
          style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
          cursorColor: _kCopper,
          decoration: _dec(hint),
          onChanged: (_) => setState(() {}),
          validator: isReq
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        );

      // ── Multiline ─────────────────────────────────────────────────────
      case 'multiline':
        return TextFormField(
          controller: _textCtrl[id],
          maxLines: 4,
          style: GoogleFonts.dmSans(color: _kText, fontSize: 14),
          cursorColor: _kCopper,
          decoration: _dec(hint),
          onChanged: (_) => setState(() {}),
          validator: isReq
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        );

      // ── Dropdown ──────────────────────────────────────────────────────
      case 'dropdown':
        final options = List<String>.from(p['options'] ?? []);
        return Container(
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
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
              onChanged: (v) => setState(() => _dropdownVal[id] = v),
            ),
          ),
        );

      // ── Dual text ─────────────────────────────────────────────────────
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
                  decoration: _dec(lbl),
                  onChanged: (_) => setState(() {}),
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
                  decoration: _dec(rbl),
                  onChanged: (_) => setState(() {}),
                  validator: isReq
                      ? (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null
                      : null,
                ),
              ),
            ]),
          ],
        );

      // ── Slider ────────────────────────────────────────────────────────
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
            color: _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
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
                        color: _kCopper)),
                Text('${mx.toInt()}',
                    style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _kCopper,
                thumbColor: _kCopper,
                inactiveTrackColor: _kBorder,
                overlayColor: _kCopper.withOpacity(0.15),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                trackHeight: 3,
              ),
              child: Slider(
                value: cur,
                min: mn,
                max: safeMx,
                divisions: (safeMx - mn).round().clamp(1, 9999),
                onChanged: (v) => setState(() => _sliderVal[id] = v),
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
// PER-PARAMETER PHOTO ROW
// Same look-and-feel as the old global photo row.
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

// ── Meta card (no photo status row — photo is now per-param) ──────────────────
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
      child: Column(
        children: [
          // Header strip
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
                    color: _kCopper, shape: BoxShape.circle),
              ),
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
          // Meta rows
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _MetaRow(label: 'Zone', value: tank.location ?? '—'),
              _MetaRow(label: 'Inspector', value: currentUser.fullName),
              _MetaRow(label: 'Timestamp', value: nowLabel),
            ]),
          ),
        ],
      ),
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
      child = Text(
        'Save Reading',
        style: GoogleFonts.dmSans(
          color: canSave ? Colors.white : _kDisable,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      );
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
                    offset: const Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Center(child: child),
      ),
    );
  }
}
