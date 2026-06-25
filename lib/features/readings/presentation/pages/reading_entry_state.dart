part of 'reading_entry_screen.dart';

class _ReadingEntryScreenState extends State<ReadingEntryScreen> {
  final _picker = ImagePicker();
  DatabaseReference _ref(String path) => DatabaseModeService.ref(path);

  // ── Audio ──────────────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingSound = false;

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

  // ── Track grouped parameters to skip flat rendering ──────────────────
  final Set<String> _groupedParamIds = {};

  // ── Active alerts for this tank ──────────────────────────────────────────
  List<AlertModel> _activeAlerts = []; // 🔖 Added for Alert Lifecycle Bug Fix
  Map<String, String> _activeAlertImages = {}; // 🔖 Alert image URL mapping from raw DB
  bool _hasShownInitialAlertPopup = false; // 🔖 Track if initial warning popup was shown
  StreamSubscription? _activeAlertsSub; // 🔖 Added for Alert Lifecycle Bug Fix

  // ── Deep copy of inspection properties ────────────────────────────────
  late final List<Map<String, dynamic>> _props;
  late String _capturedAtStart;
  late String _capturedAtCustom; // 🔖 Added for Historical Upload Permission
  String _duplicateReason = ''; // 🔖 Added for Duplicate Reading Validation

  // ── Which autofill params depend on which param ids ───────────────────
  // autofillParamId → Set<dependencyParamId>
  final Map<String, Set<String>> _autofillDeps = {};

  String get _nowLabel =>
      DateFormat('dd MMM yyyy, HH:mm:ss').format(
        DateTime.parse(_capturedAtStart),
      );

  String get _endLabel =>
      DateFormat('dd MMM yyyy, HH:mm:ss').format(
        DateTime.parse(_capturedAtCustom),
      ); // 🔖 Added for Historical Upload Permission

  // ── lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _capturedAtStart = DateTime.now().toIso8601String();
    _capturedAtCustom = _capturedAtStart; // 🔖 Added for Historical Upload Permission
    _duplicateReason = widget.duplicateReason ?? ''; // 🔖 Added for Duplicate Reading Validation

    _props = widget.tank.inspectionProperties.map((p) {
      return Map<String, dynamic>.from(p.map((k, v) {
        if (v is List) return MapEntry(k, List<dynamic>.from(v));
        if (v is Map) return MapEntry(k, Map<String, dynamic>.from(v as Map));
        return MapEntry(k, v);
      }));
    }).toList();

    // Identify all parameter IDs that belong to any group
    for (final p in _props) {
      if (p['type'] == 'group') {
        final grid = p['grid_params'] as List?;
        if (grid != null) {
          for (final cell in grid) {
            if (cell != null && cell.toString().isNotEmpty) {
              _groupedParamIds.add(cell.toString());
            }
          }
        }
      }
    }

    for (final p in _props) {
      _initParamRecursively(p);
    }

    _manualCaptures.add(_ManualCaptureEntry());

    // 🔖 Subscribe to active alerts for this tank in Firebase (Alert Lifecycle Bug Fix)
    _activeAlertsSub = _ref('alerts')
        .orderByChild('tank_id')
        .equalTo(widget.tank.id)
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists || event.snapshot.value == null) {
        setState(() {
          _activeAlerts = [];
          _activeAlertImages = {};
        });
        return;
      }
      final raw = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final list = <AlertModel>[];
      final images = <String, String>{};

      for (final e in raw.entries) {
        final alertId = e.key.toString();
        final alertMap = Map<dynamic, dynamic>.from(e.value as Map);
        final alert = AlertModel.fromMap(alertId, alertMap);

        if (!alert.resolved && alert.status.toLowerCase() != 'completed') {
          list.add(alert);
          final imgUrl = alertMap['image_url']?.toString() ?? '';
          if (imgUrl.isNotEmpty) {
            images[alertId] = imgUrl;
          }
        }
      }

      list.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      setState(() {
        _activeAlerts = list;
        _activeAlertImages = images;
      });

      // 🔖 Popup warnings disabled here; moved to Leaf Details panel in tank_input_browser.dart
      _hasShownInitialAlertPopup = true;
    });
  }

  @override
  void dispose() {
    _activeAlertsSub?.cancel(); // 🔖 Cancel active alerts sub (Alert Lifecycle Bug Fix)
    _textCtrl.values.forEach((c) => c.dispose());
    _dualLeft.values.forEach((c) => c.dispose());
    _dualRight.values.forEach((c) => c.dispose());
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Active Alert Warning Dialog ───────────────────────────────────────

  Future<void> _showActiveAlertsWarningDialog(List<AlertModel> alerts) async {
    if (alerts.isEmpty || !mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: _kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kBorder, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _kDanger, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Active Asset Alerts!',
                  style: GoogleFonts.spaceGrotesk(
                    color: _kText,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: math.min(MediaQuery.of(context).size.width * 0.9, 450.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This tank has ${alerts.length} active alert${alerts.length > 1 ? "s" : ""}. Please review the details below:',
                    style: GoogleFonts.dmSans(
                      color: _kSub,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...alerts.map((a) {
                    final isCritical = a.constraintSeverity.toLowerCase() == 'critical';
                    final isWarning = a.constraintSeverity.toLowerCase() == 'warning';
                    final sevColor = isCritical ? _kDanger : (isWarning ? _kWarn : _kInfo);
                    final timeStr = DateFormat('dd MMM yyyy, HH:mm').format(
                      DateTime.tryParse(a.capturedAt) ?? DateTime.now(),
                    );
                    final alertImgUrl = _activeAlertImages[a.id];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sevColor.withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: sevColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: sevColor.withOpacity(0.35)),
                                ),
                                child: Text(
                                  a.constraintSeverity.toUpperCase(),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: sevColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              Text(
                                timeStr,
                                style: GoogleFonts.spaceGrotesk(
                                  color: _kSub,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            a.alertTitle,
                            style: GoogleFonts.dmSans(
                              color: _kText,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.message,
                            style: GoogleFonts.dmSans(
                              color: _kSub,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: _kBorder, height: 1),
                          const SizedBox(height: 10),
                          _popupDetailRow('Asset Name', '${a.tankName} (${a.tankCode})'),
                          _popupDetailRow('Captured By', a.capturedByName),

                          // If there's an image, show thumbnail
                          if (alertImgUrl != null && alertImgUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                              Text(
                                'Image Captured:',
                                style: GoogleFonts.dmSans(
                                  color: _kSub,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => Scaffold(
                                        backgroundColor: Colors.black,
                                        appBar: AppBar(
                                          backgroundColor: Colors.black,
                                          iconTheme: const IconThemeData(color: Colors.white),
                                          title: Text(
                                            a.alertTitle,
                                            style: GoogleFonts.dmSans(color: Colors.white),
                                          ),
                                        ),
                                        body: Center(
                                          child: InteractiveViewer(
                                            minScale: 0.5,
                                            maxScale: 4.0,
                                            child: CachedNetworkImage(
                                              imageUrl: alertImgUrl,
                                              fit: BoxFit.contain,
                                              placeholder: (_, __) => const Center(
                                                child: CircularProgressIndicator(color: Colors.white),
                                              ),
                                              errorWidget: (_, __, ___) => const Icon(
                                                Icons.broken_image_outlined,
                                                color: Colors.white54,
                                                size: 40,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _kBorderH),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: CachedNetworkImage(
                                    imageUrl: alertImgUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                      color: _kSurface,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _kCopper,
                                          ),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, __, ___) => Container(
                                      color: _kSurface,
                                      child: const Icon(
                                        Icons.broken_image_outlined,
                                        color: _kSub,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  Text(
                    'Do you want to continue recording reading for this tank?',
                    style: GoogleFonts.dmSans(
                      color: _kText,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _kBorder,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop(false); // NO
                    },
                    child: Text(
                      'No, Go to Dashboard',
                      style: GoogleFonts.dmSans(
                        color: _kText,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _kCopper,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop(true); // YES
                    },
                    child: Text(
                      'Yes, Continue',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (proceed == false) {
      if (mounted) {
        Navigator.pop(context, {
          'action': 'go_to_dashboard',
        });
      }
    }
  }

  Widget _popupDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                color: _kSub,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                color: _kText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showViolationBottomSheet(_Violation violation) {
    final color = _severityColor(violation.severity);
    final icon = _severityIcon(violation.severity);

    showModalBottomSheet(
      context: context,
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        violation.alertTitle,
                        style: GoogleFonts.spaceGrotesk(
                          color: _kText,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        violation.severity.toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  violation.message,
                  style: GoogleFonts.dmSans(
                    color: _kText.withOpacity(0.9),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(
                      'Acknowledge',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Sound + Vibration (fixed) ──────────────────────────────────────────

  Future<void> _playViolationSound() async {
    if (_isPlayingSound) return;
    _isPlayingSound = true;
    try {
      // Try to play a built-in alert sound via AudioPlayer
      // Uses the default system alert sound asset — add 'assets/sounds/alert.mp3'
      // to your pubspec.yaml under flutter > assets if you have a custom sound.
      // Fallback: SystemSound + vibration
      await _audioPlayer.stop();
      try {
        await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
      } catch (e) {
        debugPrint('[AudioPlayer] Play failed: $e. Falling back to system sound.');
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (e) {
      debugPrint('[AudioPlayer] Stop failed: $e. Falling back to system sound.');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    } finally {
      // Allow re-triggering sound only after a 500ms debounce window
      await Future.delayed(const Duration(milliseconds: 500));
      _isPlayingSound = false;
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
  // Expression format: ${paramId} / ${paramId:left} / ${paramId:right}
  Set<String> _parseDependencyIds(String expression) {
    return ExpressionEngine.extractIds(expression)
        .map((e) => e.split(':').first.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  bool _isLastTokenId(String id) => id.endsWith('__last');

  String _tankPrevKey() =>
      widget.tank.tankName.trim().replaceAll('/', '_').replaceAll('\\', '_');

  String _previousCapturePath({
    required String baseParamId,
    required String baseParamLabel,
  }) {
    return 'Previouscapture/${_tankPrevKey()}/$baseParamId/$baseParamLabel';
  }

  // ── Autofill: get the value of a dependency token ─────────────────────
  // Token format from expression: ${paramId} / ${paramId:left} / ${paramId:right}
  Future<double?> _resolveToken(String token) async {
    final parts = token.split(':');
    var pid = parts.first.trim();
    final side = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
    final isLast = _isLastTokenId(pid);
    if (isLast) {
      pid = pid.substring(0, pid.length - '__last'.length);
    }

    final p = _getPropById(pid);
    if (p.isEmpty) return null;
    final type = p['type'] as String? ?? 'text';

    if (isLast) {
      // "__last" must come only from persisted previous-capture values.
      // If this parameter is not configured to track previous capture,
      // treat previous as zero.
      if (p['keep_previous_capture'] != true) return 0.0;
      final label = p['label']?.toString() ?? pid;
      final path = _previousCapturePath(baseParamId: pid, baseParamLabel: label);
      try {
        final snap = await _ref(path).get();
        if (!snap.exists || snap.value == null) return 0.0;
        final stored = snap.value;
        if (type == 'dual_text') {
          if (stored is Map) {
            final m = Map<dynamic, dynamic>.from(stored as Map);
            final sideValue = side == 'right' ? m['right'] : m['left'];
            return double.tryParse(sideValue?.toString() ?? '') ?? 0.0;
          }
          return 0.0;
        }
        return double.tryParse(stored.toString()) ?? 0.0;
      } catch (_) {
        return 0.0;
      }
    }

    if (type == 'dual_text') {
      if (side == 'right') {
        return double.tryParse(_dualRight[pid]?.text.trim() ?? '');
      }
      return double.tryParse(_dualLeft[pid]?.text.trim() ?? '');
    }
    if (type == 'number') return double.tryParse(_textCtrl[pid]?.text.trim() ?? '');
    if (type == 'slider') return _sliderVal[pid];
    if (type == 'dropdown') {
      final raw = _dropdownVal[pid]?.trim() ?? '';
      if (raw.isEmpty) return null;
      final numeric = double.tryParse(raw);
      if (numeric != null) return numeric;
      throw _MathException(
        'Expected a numerical value but got string. Please enter it manually.',
        'DropdownValueTypeException',
      );
    }
    return null;
  }

  Future<bool> _hasPreviousCaptureForToken(String token) async {
    final parts = token.split(':');
    var pid = parts.first.trim();
    final side = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
    if (!_isLastTokenId(pid)) return true;

    pid = pid.substring(0, pid.length - '__last'.length);
    final p = _getPropById(pid);
    if (p.isEmpty) return false;
    if (p['keep_previous_capture'] != true) return false;

    final type = p['type'] as String? ?? 'text';
    final label = p['label']?.toString() ?? pid;
    final path = _previousCapturePath(baseParamId: pid, baseParamLabel: label);

    try {
      final snap = await _ref(path).get();
      if (!snap.exists || snap.value == null) return false;
      if (type == 'dual_text') {
        if (snap.value is! Map) return false;
        final m = Map<dynamic, dynamic>.from(snap.value as Map);
        final sideValue = side == 'right' ? m['right'] : m['left'];
        return sideValue != null && sideValue.toString().trim().isNotEmpty;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Autofill: evaluate the expression ────────────────────────────────
  Future<_AutofillResult> _evaluateExpression(String expression) async {
    try {
      final tokens = ExpressionEngine.extractIds(expression);

      // If any "__last" dependency has no previous-capture object,
      // force autofill to 0 and skip formula evaluation entirely.
      for (final token in tokens) {
        if (!_isLastTokenId(token.split(':').first.trim())) continue;
        final hasPrev = await _hasPreviousCaptureForToken(token);
        if (!hasPrev) return _AutofillResult.value(0.0);
      }

      final vars = <String, double>{};
      for (final token in tokens) {
        final val = await _resolveToken(token);
        if (val == null) {
          return const _AutofillResult.error(
            'Some required values are not filled in yet.',
            'NullValueException',
          );
        }
        vars[token] = val;
      }
      final result = ExpressionEngine.evaluate(expression, variables: vars);
      return _AutofillResult.value(result);
    } on ExpressionEngineException catch (e) {
      if (e.message.toLowerCase().contains('zero')) {
        return _AutofillResult.error(
          'You\'re trying to divide by zero - that\'s not mathematically possible. Please check the divisor value.',
          'DivisionByZeroException',
        );
      }
      return _AutofillResult.error(e.message, 'ExpressionEngineException');
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
      final p = _getPropById(depId);
      if (_isLastTokenId(depId)) {
        status[depId] = true;
        continue;
      }
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
  Future<void> _reevaluateAutofillDependents(String changedParamId) async {
    for (final entry in _autofillDeps.entries) {
      final autofillId = entry.key;
      final deps = entry.value;
      if (!deps.contains(changedParamId)) continue;

      // Only re-evaluate if autofill mode is active
      if (_autofillEnabled[autofillId] != true) continue;

      final p = _getPropById(autofillId);
      if (p.isEmpty) continue;

      final expression = p['autofill_expression'] as String? ?? '';
      final depsStatus = _getDepsFillStatus(autofillId);
      final allFilled = depsStatus.values.every((v) => v);

      if (allFilled) {
        final result = await _evaluateExpression(expression);
        setState(() {
          if (result.hasError &&
              result.exceptionName == 'DropdownValueTypeException') {
            _autofillEnabled[autofillId] = false;
          }
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
      .convert(
        utf8.encode(
          'folder=$_folder&timestamp=$ts${EnvConfig.cloudinaryApiSecret}',
        ),
      )
      .toString();

  Future<String> _uploadFile(File file) async {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final req = http.MultipartRequest('POST',
        Uri.parse(
          'https://api.cloudinary.com/v1_1/${EnvConfig.cloudinaryCloudName}/image/upload',
        ));
    req.fields['api_key'] = EnvConfig.cloudinaryApiKey;
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

    final p = _getPropById(paramId);
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
      'status': 'active', // 🔖 Added for Alert Lifecycle Bug Fix
    };

    try {
      if (v.showDashboardAlert) {
        await _ref('alerts/$alertId').set(record);
      }
      if (v.storeHistory) {
        await _ref('violations/$alertId').set(record);
      }
      await _ref('alerts_full/$alertId').set({
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
      await _ref('alerts/$alertId').remove();
      await _ref('violations/$alertId').remove();
      await _ref('alerts_full/$alertId').remove();
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

    if (value == null || value.toString().trim() == 'null' || value.toString().trim().isEmpty) {
      return fired;
    }

    final actual = value.toString().trim();


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

  Future<void> _onValueChanged(String id) async {
    final p = _getPropById(id);
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
      _deactivateChildParametersRecursively(id, clearedId);
    }

    setState(() => _violations[id] = newViolations);

    // Newly fired constraints
    for (final v in newViolations) {
      final constraintsSet = _alreadyFiredConstraints.putIfAbsent(id, () => <String>{});
      final alreadyFired = constraintsSet.contains(v.constraintId);

      if (!alreadyFired) {
        constraintsSet.add(v.constraintId);
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
    await _reevaluateAutofillDependents(id);
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

    // Show Bottom Sheet violation popup from below based on alert severity
    _showViolationBottomSheet(violation);

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
      await _ref('alerts/$alertId').update(update);
      await _ref('alerts_full/$alertId').update(update);
    } catch (e) {
      debugPrint('[LiveAlert] Update failed: $e');
    }
  }

  // ── Required / block checks ────────────────────────────────────────────

  String? _requiredError() {
    for (final p in _allActiveProps()) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';
      if (type == 'group') continue;
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
      _violations.keys.any((id) => _isParamActive(id) && (_violations[id]?.any((v) => v.blockSubmission) ?? false));

  bool get _hasMissingViolationPhoto {
    for (final p in _allActiveProps()) {
      if (p['type'] == 'group') continue;
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
    for (final p in _allActiveProps()) {
      if (p['type'] == 'group') continue;
      if (p['capture_image'] == true) {
        if (_paramPhoto[p['id'] as String] == null) return false;
      }
    }
    return true;
  }

  // ── Collect values for the reading record ──────────────────────────────

  Map<String, dynamic> _collectValues() {
    final out = <String, dynamic>{};
    for (final p in _allActiveProps()) {
      final id = p['id'] as String;
      final type = p['type'] as String? ?? 'text';
      if (type == 'group') continue;
      final label = p['label'] as String? ?? id;
      final isReq = p['required'] == true;

      switch (type) {
        case 'number':
          final rawText = _textCtrl[id]?.text.trim() ?? '';
          if (rawText.isEmpty) {
            out[label] = isReq ? 0.0 : null;
          } else {
            out[label] = double.tryParse(rawText) ?? 0.0;
          }
          break;
        case 'text':
        case 'multiline':
          final rawText = _textCtrl[id]?.text.trim() ?? '';
          if (rawText.isEmpty) {
            out[label] = isReq ? '' : null;
          } else {
            out[label] = rawText;
          }
          break;
        case 'dropdown':
          final rawVal = _dropdownVal[id];
          if (rawVal == null || rawVal.trim().isEmpty) {
            out[label] = isReq ? '' : null;
          } else {
            out[label] = rawVal;
          }
          break;
        case 'slider':
          out[label] = _sliderVal[id] ?? ((p['min'] ?? 0) as num).toDouble();
          break;
        case 'dual_text':
          final leftRaw = _dualLeft[id]?.text.trim() ?? '';
          final rightRaw = _dualRight[id]?.text.trim() ?? '';
          if (leftRaw.isEmpty && rightRaw.isEmpty) {
            out[label] = isReq ? {'left': '', 'right': ''} : null;
          } else {
            out[label] = {
              'left': double.tryParse(leftRaw) ?? leftRaw,
              'right': double.tryParse(rightRaw) ?? rightRaw,
            };
          }
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
      if (_duplicateReason.isNotEmpty) {
        inspVals['duplicate_reason'] = _duplicateReason;
      } // 🔖 Added for Duplicate Reading Validation

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
          final pSearch = _getPropById(entry.selectedParamId!);
          final paramLabel = (pSearch.isNotEmpty ? pSearch['label'] : null) as String? ?? entry.selectedParamId!;
          final key = 'manual_${paramLabel}_captured_image';
          if (inspVals.containsKey(key)) {
            inspVals['manual_${paramLabel}_captured_image_$i'] =
                entry.uploadedUrl!;
          } else {
            inspVals[key] = entry.uploadedUrl!;
          }
        }
      }

      for (final p in _allActiveProps()) {
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
        capturedAtStart: _capturedAtStart,
        capturedAt: _capturedAtCustom, // 🔖 Added for Historical Upload Permission
        imageUrl: primaryImageUrl,
        inspectionValues: inspVals,
      );

      await DashboardStatsRepository().updateStatsAfterReading(
        reading: reading,
        tank: widget.tank,
      );

      await _auditReadingSave(reading, inspVals);

      for (final p in _allActiveProps()) {
        if (p['keep_previous_capture'] != true) continue;
        final id = p['id'] as String;
        final type = p['type'] as String? ?? 'text';
        final label = p['label'] as String? ?? id;
        final val = _currentValue(id, type, p);
        try {
          await _ref(_previousCapturePath(
            baseParamId: id,
            baseParamLabel: label,
          )).set(val);
        } catch (_) {}
      }

      for (final paramMap in _liveAlertIds.values) {
        for (final alertId in paramMap.values) {
          try {
            await _ref('alerts/$alertId').update({
              'live': false,
              'reading_id': reading.id ?? '',
            });
            await _ref('alerts_full/$alertId').update({
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

      // 🔖 Navigation Sequence & Delay (Reading Capture Flow Refactor)
      final siblings = widget.siblingTanks;
      final currentIndex = widget.currentTankIndex;

      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (siblings != null && currentIndex != null && currentIndex < siblings.length - 1) {
          // There are more tanks in the folder sequence! Pop back and request to select the next tank.
          final nextIndex = currentIndex + 1;
          final nextTank = siblings[nextIndex];
          Navigator.pop(context, {
            'action': 'select_tank',
            'tank_id': nextTank.id,
          });
        } else {
          // No more tanks, or not part of a folder sequence. Return to the previous screen.
          Navigator.pop(context, {
            'action': 'clear_selection',
          });
        }
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _failed = true;
        _uploadError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _auditReadingSave(
    dynamic reading,
    Map<String, dynamic> values,
  ) async {
    try {
      await AuditLogService.record(
        operation: 'save_reading',
        entityType: 'reading',
        entityId: reading.id?.toString(),
        entityName: widget.tank.tankName,
        actorId: widget.currentUser.id,
        actorUsername: widget.currentUser.username,
        actorName: widget.currentUser.fullName,
        actorRole: widget.currentUser.role,
        tab: 'readings',
        clientName: widget.tank.location,
        details: {
          'tank_id': widget.tank.id,
          'tank_code': widget.tank.tankCode,
          'tank_name': widget.tank.tankName,
          'inspection_value_count': values.length,
          'summary': 'Saved reading for ${widget.tank.tankName}',
        },
        summary: 'Saved reading for ${widget.tank.tankName}',
      );
    } catch (_) {}
  }



  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _kCopper,
              onPrimary: _kBg,
              surface: _kCard,
              onSurface: _kText,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null || !mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _kCopper,
              onPrimary: _kBg,
              surface: _kCard,
              onSurface: _kText,
            ),
          ),
          child: child!,
        );
      },
    );
    if (time == null || !mounted) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _editStartDate() async {
    final parsed = DateTime.tryParse(_capturedAtStart) ?? DateTime.now();
    final chosen = await _pickDateTime(parsed);
    if (chosen != null && mounted) {
      setState(() {
        _capturedAtStart = chosen.toIso8601String();
      });
    }
  }

  Future<void> _editEndDate() async {
    final parsed = DateTime.tryParse(_capturedAtCustom) ?? DateTime.now();
    final chosen = await _pickDateTime(parsed);
    if (chosen != null && mounted) {
      setState(() {
        _capturedAtCustom = chosen.toIso8601String();
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
              endLabel: _endLabel,
              onStartTap: AccessControlService.can(widget.currentUser, AccessControlService.pHistoricalUpload)
                  ? _editStartDate
                  : null,
              onEndTap: AccessControlService.can(widget.currentUser, AccessControlService.pHistoricalUpload)
                  ? _editEndDate
                  : null,
            ),

            if (_activeAlerts.isNotEmpty) ...[
              const SizedBox(height: 16),
              (() {
                // Determine highest severity
                String highestSeverity = 'info';
                for (final alert in _activeAlerts) {
                  final sev = alert.constraintSeverity.toLowerCase();
                  if (sev == 'critical') {
                    highestSeverity = 'critical';
                    break;
                  } else if (sev == 'warning') {
                    highestSeverity = 'warning';
                  }
                }
                final sevColor = _severityColor(highestSeverity);
                final sevIcon = _severityIcon(highestSeverity);

                return Container(
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sevColor.withOpacity(0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: sevColor.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(sevIcon, color: sevColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'ACTIVE ALERTS FOR THIS ASSET',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: sevColor,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._activeAlerts.map((alert) {
                        final timeStr = DateFormat('dd MMM yyyy, HH:mm').format(
                          DateTime.tryParse(alert.capturedAt) ?? DateTime.now(),
                        );
                        final individualColor = _severityColor(alert.constraintSeverity);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: individualColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            alert.alertTitle,
                                            style: GoogleFonts.dmSans(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _kText,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          timeStr,
                                          style: GoogleFonts.dmSans(
                                            fontSize: 11,
                                            color: _kSub,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      alert.message,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: _kSub,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                );
              }()),
            ], // 🔖 Added for Alert Lifecycle Bug Fix

            if (_props.isNotEmpty) ...[
              const SizedBox(height: 28),
              _SecLabel('INSPECTION PARAMETERS'),
              const SizedBox(height: 4),
              Text('Fields marked * are required',
                  style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
              const SizedBox(height: 16),
              ..._props.map((p) => _buildPropField(p, isNested: false)),
            ],

            if (_showManualCaptures) ...[
              const SizedBox(height: 28),
              _buildManualCaptureSection(),
            ],

            const SizedBox(height: 28),

            if (_hasBlockingViolation) ...[
              _BlockBanner(violations: _violations, props: _allPropsFlat()),
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
    final paramOptions = _allActiveProps()
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



  Widget _buildPropField(Map<String, dynamic> p, {bool isNested = false}) {
    final id = p['id'] as String;
    final type = p['type'] as String? ?? 'text';

    if (!isNested && _groupedParamIds.contains(id)) {
      return const SizedBox.shrink();
    }

    if (type == 'group') {
      final label = p['label'] as String? ?? 'Group';
      final hint = p['hint'] as String? ?? '';
        final int rows = p['rows'] is int
          ? p['rows'] as int
          : int.tryParse(p['rows']?.toString() ?? '1') ?? 1;
      final int cols = p['cols'] is int
          ? p['cols'] as int
          : int.tryParse(p['cols']?.toString() ?? '1') ?? 1;
      final int displayCols = cols > 2 ? 2 : cols;
      final rawGrid = List<String>.from(p['grid_params'] ?? const []);
      final totalCells = rows * cols;
      final gridParams = rawGrid.length < totalCells
          ? [
              ...rawGrid,
              ...List.generate(totalCells - rawGrid.length, (_) => ''),
            ]
          : rawGrid.take(totalCells).toList();

      Widget buildGridCell(int index) {
        final cellParamId = gridParams[index];
        final cellParam = _getPropById(cellParamId);
        final isEmpty = cellParamId.trim().isEmpty;
        final isMissing = !isEmpty && cellParam == null;

        if (cellParam == null) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kSurface.withOpacity(0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isMissing ? _kWarn : _kBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Slot ${index + 1}',
                  style: GoogleFonts.dmSans(
                    color: _kSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  isMissing
                      ? Icons.error_outline_rounded
                      : Icons.grid_view_rounded,
                  size: 18,
                  color: isMissing ? _kWarn : _kSub,
                ),
                const SizedBox(height: 4),
                Text(
                  isMissing ? 'Missing param: $cellParamId' : 'Empty slot',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    color: isMissing ? _kWarn : _kSub,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPropField(cellParam, isNested: true),
            ],
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _kTeal,
                letterSpacing: 1.2,
              ),
            ),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: _kSub,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Column(
              children: List.generate(rows, (r) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(displayCols, (c) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: buildGridCell(r * cols + c),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ],
        ),
      );
    }

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
      padding: EdgeInsets.only(bottom: isNested ? 0 : 20),
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
              onToggle: (enabled) async {
                setState(() => _autofillEnabled[id] = enabled);
                if (enabled) {
                  final expr = p['autofill_expression'] as String? ?? '';
                  final depsStatus = _getDepsFillStatus(id);
                  final allFilled = depsStatus.values.every((v) => v);
                  if (allFilled && expr.isNotEmpty) {
                    final result = await _evaluateExpression(expr);
                    if (!mounted) return;
                    setState(() {
                      if (result.hasError &&
                          result.exceptionName ==
                              'DropdownValueTypeException') {
                        _autofillEnabled[id] = false;
                      }
                      _autofillResult[id] = result;
                      if (!result.hasError && result.value != null) {
                        final formatted =
                            result.value! == result.value!.truncateToDouble()
                                ? result.value!.toInt().toString()
                                : result.value!.toStringAsFixed(4);
                        _textCtrl[id]?.text = formatted;
                      }
                    });
                  } else {
                    setState(() {
                      _autofillResult[id] = null;
                      _textCtrl[id]?.text = '';
                    });
                  }
                } else {
                  setState(() => _autofillResult[id] = null);
                }
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
              props: _allPropsFlat(),
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

          // ── THEN Nested Parameters ───────────────────────────────
          ...p['constraints']?.map<Widget>((c) {
            final cMap = _deepCast(c) as Map<String, dynamic>;
            final constraintId = cMap['id']?.toString() ?? '';
            final isViolated = vList.any((v) => v.constraintId == constraintId);
            final condWorkflow = cMap['then_workflow_enabled'] == true;
            final thenProps = cMap['then_properties'] as List?;
            if (isViolated && condWorkflow && thenProps != null && thenProps.isNotEmpty) {
              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF9B7FE0).withOpacity(0.35), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.subdirectory_arrow_right, size: 14, color: Color(0xFF9B7FE0)),
                        const SizedBox(width: 6),
                        Text(
                          'CONDITIONAL FORM (WHEN ${cMap['op']} ${cMap['value']})',
                          style: GoogleFonts.dmSans(
                            color: const Color(0xFF9B7FE0),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...thenProps.map((childProp) {
                      return _buildPropField(_deepCast(childProp) as Map<String, dynamic>, isNested: true);
                    }),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }) ?? const [],
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

  // ── IF-THEN conditional fields and helpers ──────────────────────────────
  final Map<String, Map<String, String>> _paramParents = {};

  void _initParamRecursively(Map<String, dynamic> p, {String? parentId, String? parentConstraintId}) {
    final id = p['id'] as String;
    final type = p['type'] as String? ?? 'text';
    final isAutofill = p['autofill'] == true;

    if (parentId != null && parentConstraintId != null) {
      _paramParents[id] = {
        'parentParamId': parentId,
        'constraintId': parentConstraintId,
      };
    }

    if (isAutofill) {
      _autofillEnabled[id] = true;
      _autofillResult[id] = null;
      _autofillDeps[id] = _parseDependencyIds(p['autofill_expression'] as String? ?? '');
    }

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

    // Recursively initialize THEN parameters
    final constraints = p['constraints'] as List?;
    if (constraints != null) {
      for (final c in constraints) {
        final cMap = _deepCast(c) as Map<String, dynamic>;
        if (cMap['then_workflow_enabled'] == true) {
          final thenProps = cMap['then_properties'] as List?;
          if (thenProps != null) {
            for (final childProp in thenProps) {
              final childMap = _deepCast(childProp) as Map<String, dynamic>;
              _initParamRecursively(childMap, parentId: id, parentConstraintId: cMap['id']?.toString());
            }
          }
        }
      }
    }
  }

  dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((k, v) => MapEntry(k.toString(), _deepCast(v)))
      );
    }
    if (value is List) {
      return value.map(_deepCast).toList();
    }
    return value;
  }

  Map<String, dynamic> _getPropById(String id) {
    Map<String, dynamic>? search(List<dynamic> list) {
      for (final p in list) {
        final pMap = _deepCast(p) as Map<String, dynamic>;
        if (pMap['id'] == id) return pMap;
        final constraints = pMap['constraints'] as List?;
        if (constraints != null) {
          for (final c in constraints) {
            final cMap = _deepCast(c) as Map<String, dynamic>;
            if (cMap['then_workflow_enabled'] == true) {
              final thenProps = cMap['then_properties'] as List?;
              if (thenProps != null) {
                final found = search(thenProps);
                if (found != null) return found;
              }
            }
          }
        }
      }
      return null;
    }
    return search(_props) ?? <String, dynamic>{};
  }

  bool _isParamActive(String id) {
    final parentInfo = _paramParents[id];
    if (parentInfo == null) {
      return !_groupedParamIds.contains(id);
    }
    final parentId = parentInfo['parentParamId']!;
    final constraintId = parentInfo['constraintId']!;
    if (!_isParamActive(parentId)) return false;
    final parentViolations = _violations[parentId] ?? [];
    return parentViolations.any((v) => v.constraintId == constraintId);
  }

  List<Map<String, dynamic>> _allActiveProps() {
    final activeList = <Map<String, dynamic>>[];
    void collect(List<dynamic> list) {
      for (final p in list) {
        final pMap = _deepCast(p) as Map<String, dynamic>;
        final id = pMap['id'] as String;
        if (_isParamActive(id)) {
          activeList.add(pMap);
          final constraints = pMap['constraints'] as List?;
          if (constraints != null) {
            for (final c in constraints) {
              final cMap = _deepCast(c) as Map<String, dynamic>;
              if (cMap['then_workflow_enabled'] == true) {
                final thenProps = cMap['then_properties'] as List?;
                if (thenProps != null) {
                  collect(thenProps);
                }
              }
            }
          }
        }
      }
    }
    collect(_props);
    return activeList;
  }

  List<Map<String, dynamic>> _allPropsFlat() {
    final list = <Map<String, dynamic>>[];
    void collect(List<dynamic> src) {
      for (final p in src) {
        final pMap = _deepCast(p) as Map<String, dynamic>;
        list.add(pMap);
        final constraints = pMap['constraints'] as List?;
        if (constraints != null) {
          for (final c in constraints) {
            final cMap = _deepCast(c) as Map<String, dynamic>;
            if (cMap['then_workflow_enabled'] == true) {
              final thenProps = cMap['then_properties'] as List?;
              if (thenProps != null) {
                collect(thenProps);
              }
            }
          }
        }
      }
    }
    collect(_props);
    return list;
  }

  void _deactivateChildParametersRecursively(String parentId, String constraintId) {
    final children = _paramParents.entries
        .where((e) => e.value['parentParamId'] == parentId && e.value['constraintId'] == constraintId)
        .map((e) => e.key)
        .toList();

    for (final childId in children) {
      _violations[childId]?.clear();
      _alreadyFiredConstraints[childId]?.clear();

      _paramPhoto[childId] = null;
      _paramPhotoUrl[childId] = null;
      _paramUploading[childId] = false;

      final childAlerts = Map<String, String>.from(_liveAlertIds[childId] ?? {});
      for (final cid in childAlerts.keys) {
        _deleteLiveAlert(paramId: childId, constraintId: cid);
      }
      _liveAlertIds[childId]?.clear();

      final childProp = _getPropById(childId);
      final constraints = childProp['constraints'] as List?;
      if (constraints != null) {
        for (final c in constraints) {
          final cMap = _deepCast(c) as Map<String, dynamic>;
          if (cMap['then_workflow_enabled'] == true) {
            _deactivateChildParametersRecursively(childId, cMap['id']?.toString() ?? '');
          }
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTOFILL TOGGLE ROW — radio button to switch autofill on/off
// ─────────────────────────────────────────────────────────────────────────────