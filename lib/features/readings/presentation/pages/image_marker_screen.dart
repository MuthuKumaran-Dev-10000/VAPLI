// lib/features/readings/presentation/pages/image_marker_screen.dart
// ══════════════════════════════════════════════════════════════════════════════
// ARCHITECTURE — two-layer, no pixel manipulation:
//
//   Layer 1 (bottom): original photo — NEVER modified
//   Layer 2 (top):    marker strokes only — drawn in CustomPainter
//
//   Eraser = removes strokes from the list whose path passes near the
//            eraser contact point. ZERO pixel clearing. Zero black squares.
//
//   Undo   = pop last action from history stack
//   Redo   = re-apply action from redo stack
//
//   Export = photo rendered at full res + strokes replayed on top via
//            ui.PictureRecorder → merged into one PNG → returned as File
//
// MARKER COLOR: #00E5FF (electric cyan)
//   Max contrast vs white-bg + red graduation lines on lubrication scales.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

// ── palette ───────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kCopper = Color(0xFFCB8C3E);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kDanger = Color(0xFFEF4444);
const _kMarker = Color(0xFF00E5FF); // electric cyan

// ─────────────────────────────────────────────────────────────────────────────
// DATA
// ─────────────────────────────────────────────────────────────────────────────

enum _Tool { pen, text, eraser }

/// A single drawn stroke — a list of canvas-space points + metadata.
class _Stroke {
  final List<Offset> pts;
  final double width;
  _Stroke({required List<Offset> pts, required this.width})
      : pts = List<Offset>.unmodifiable(pts);
}

/// One undoable action.
sealed class _Action {}

class _AddAction extends _Action {
  final _Stroke stroke;
  _AddAction(this.stroke);
}

class _EraseAction extends _Action {
  /// Indices (into the stroke list *before* this erase) that were removed.
  final List<int> removedIndices;
  final List<_Stroke> removedStrokes;
  _EraseAction(this.removedIndices, this.removedStrokes);
}

class _TextSticker {
  final int id;
  final String text;
  final Offset position;
  final double fontSize;

  const _TextSticker({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 22,
  });

  _TextSticker copyWith({String? text, Offset? position, double? fontSize}) {
    return _TextSticker(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ImageMarkerScreen extends StatefulWidget {
  final File imageFile;
  const ImageMarkerScreen({super.key, required this.imageFile});

  @override
  State<ImageMarkerScreen> createState() => _ImageMarkerScreenState();
}

class _ImageMarkerScreenState extends State<ImageMarkerScreen> {
  // ── image ──────────────────────────────────────────────────────────────────
  ui.Image? _uiImage;
  bool _loaded = false;

  // ── stroke state ───────────────────────────────────────────────────────────
  // _strokes is the live list that the painter renders.
  final List<_Stroke> _strokes = [];

  // History stacks
  final List<_Action> _history = []; // undo stack
  final List<_Action> _redoStack = []; // redo stack

  // In-progress stroke (not yet committed)
  List<Offset> _livePoints = [];
  bool _drawing = false;

  // Eraser contact tracking: we collect which strokes the eraser touches
  // across the entire pan gesture, then commit one _EraseAction on pan-end.
  final Set<int> _erasedThisPan = {};

  // ── tool ───────────────────────────────────────────────────────────────────
  _Tool _tool = _Tool.pen;
  double _width = 5.0;
  final List<_TextSticker> _textStickers = [];
  int _nextTextId = 1;
  bool _showDeleteZone = false;
  int? _draggingTextId;

  // ── export ─────────────────────────────────────────────────────────────────
  final GlobalKey _canvasKey = GlobalKey();
  bool _saving = false;

  // ── canvas layout (set once image loads) ──────────────────────────────────
  // We need this to map widget-space coords to image-space for export.
  Rect _imageRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── load ───────────────────────────────────────────────────────────────────

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted)
      setState(() {
        _uiImage = frame.image;
        _loaded = true;
      });
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  double get _eraserHitRadius => (_width * 3.5).clamp(12.0, 80.0);
  double get _drawWidth => _width;

  /// Does the eraser circle at [touch] overlap stroke [s]?
  bool _eraserHits(_Stroke s, Offset touch) {
    final r = _eraserHitRadius;
    for (final p in s.pts) {
      if ((p - touch).distance <= r) return true;
    }
    return false;
  }

  // ── gesture handlers ───────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    _redoStack.clear(); // new gesture invalidates redo
    if (_tool == _Tool.pen) {
      setState(() {
        _livePoints = [d.localPosition];
        _drawing = true;
      });
    } else {
      // eraser: start collecting hits
      _erasedThisPan.clear();
      _eraseAt(d.localPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_tool == _Tool.pen) {
      setState(() {
        _livePoints = [..._livePoints, d.localPosition];
      });
    } else {
      _eraseAt(d.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (_tool == _Tool.pen) {
      if (_livePoints.length >= 1) {
        final stroke = _Stroke(pts: _livePoints, width: _drawWidth);
        setState(() {
          _strokes.add(stroke);
          _history.add(_AddAction(stroke));
          _livePoints = [];
          _drawing = false;
        });
      }
    } else {
      // Commit erase action if anything was erased
      if (_erasedThisPan.isNotEmpty) {
        // Build action for undo
        final indices = _erasedThisPan.toList()..sort();
        // We already removed them in _eraseAt; store them so undo can re-insert
        // (stored in _EraseAction.removedStrokes — we captured them during removal)
        // Nothing extra needed; _erasedThisPan strokes are already gone from _strokes.
        // The undo action was recorded stroke-by-stroke in _eraseAt.
      }
      _erasedThisPan.clear();
    }
  }

  void _eraseAt(Offset touch) {
    // Find all strokes that the eraser circle touches
    final toRemove = <int>[];
    for (int i = 0; i < _strokes.length; i++) {
      if (!_erasedThisPan.contains(i) && _eraserHits(_strokes[i], touch)) {
        toRemove.add(i);
      }
    }
    if (toRemove.isEmpty) return;

    // Record for undo — each stroke removal is its own undoable unit
    // grouped under this pan gesture. We commit them individually so undo
    // is fine-grained (one undo = one pen stroke restored).
    setState(() {
      // Remove in reverse order so indices stay valid
      for (final i in toRemove.reversed.toList()) {
        final removed = _strokes.removeAt(i);
        _history.add(_EraseAction([i], [removed]));
        _erasedThisPan.add(i);
      }
    });
  }

  // ── undo / redo ────────────────────────────────────────────────────────────

  void _undo() {
    if (_history.isEmpty) return;
    HapticFeedback.lightImpact();
    final action = _history.removeLast();
    setState(() {
      if (action is _AddAction) {
        // Remove the last-added stroke
        _strokes.remove(action.stroke);
        _redoStack.add(action);
      } else if (action is _EraseAction) {
        // Re-insert the erased strokes at their original indices
        for (int k = 0; k < action.removedIndices.length; k++) {
          final idx = action.removedIndices[k].clamp(0, _strokes.length);
          _strokes.insert(idx, action.removedStrokes[k]);
        }
        _redoStack.add(action);
      }
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    HapticFeedback.lightImpact();
    final action = _redoStack.removeLast();
    setState(() {
      if (action is _AddAction) {
        _strokes.add(action.stroke);
        _history.add(action);
      } else if (action is _EraseAction) {
        for (final i in action.removedIndices.reversed) {
          if (i < _strokes.length) _strokes.removeAt(i);
        }
        _history.add(action);
      }
    });
  }

  void _clear() {
    if (_strokes.isEmpty && _livePoints.isEmpty && _textStickers.isEmpty) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      // Save each stroke as an erase action so undo can restore them
      for (int i = _strokes.length - 1; i >= 0; i--) {
        _history.add(_EraseAction([i], [_strokes[i]]));
      }
      _strokes.clear();
      _textStickers.clear();
      _livePoints = [];
      _drawing = false;
    });
  }

  Future<void> _addOrEditText({int? stickerId}) async {
    final existing = stickerId == null
        ? null
        : _textStickers.firstWhere((e) => e.id == stickerId);
    final ctrl = TextEditingController(text: existing?.text ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add Text' : 'Edit Text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Type text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;

    setState(() {
      if (existing == null) {
        _textStickers.add(
          _TextSticker(
            id: _nextTextId++,
            text: value,
            position: const Offset(80, 180),
          ),
        );
      } else {
        final idx = _textStickers.indexWhere((e) => e.id == existing.id);
        if (idx >= 0) {
          _textStickers[idx] = _textStickers[idx].copyWith(text: value);
        }
      }
    });
  }

  void _moveSticker(int id, Offset delta) {
    final idx = _textStickers.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final current = _textStickers[idx];
    _textStickers[idx] = current.copyWith(position: current.position + delta);
    setState(() {});
  }

  // ── discard ────────────────────────────────────────────────────────────────

  void _discard() => Navigator.of(context).pop<File>(null);

  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving || !_loaded) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      final img = _uiImage!;
      final imgW = img.width.toDouble();
      final imgH = img.height.toDouble();

      // Capture the RepaintBoundary at 3× for high-res export
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final canvasImg = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await canvasImg.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/marked_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path)..writeAsBytesSync(pngBytes);

      if (mounted) Navigator.of(context).pop<File>(file);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _kDanger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _discard();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          // ── Photo + stroke canvas ────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onPanStart: _tool == _Tool.text ? null : _onPanStart,
              onPanUpdate: _tool == _Tool.text ? null : _onPanUpdate,
              onPanEnd: _tool == _Tool.text ? null : _onPanEnd,
              child: RepaintBoundary(
                key: _canvasKey,
                child: _loaded
                    ? LayoutBuilder(builder: (ctx, constraints) {
                        // Compute fitted rect so we can store it
                        final size =
                            Size(constraints.maxWidth, constraints.maxHeight);
                        _imageRect = _fittedRect(_uiImage!.width.toDouble(),
                            _uiImage!.height.toDouble(), size);
                        return Stack(
                          children: [
                            CustomPaint(
                              painter: _MarkerPainter(
                                image: _uiImage!,
                                strokes: List<_Stroke>.from(_strokes),
                                livePoints: _livePoints,
                                liveWidth: _drawWidth,
                                isDrawing: _drawing,
                              ),
                              child: const SizedBox.expand(),
                            ),
                            ..._textStickers.map((s) => Positioned(
                                  left: s.position.dx,
                                  top: s.position.dy,
                                  child: GestureDetector(
                                    onDoubleTap: () => _addOrEditText(stickerId: s.id),
                                    onPanStart: (_) => setState(() {
                                      _draggingTextId = s.id;
                                      _showDeleteZone = true;
                                    }),
                                    onPanUpdate: (d) => _moveSticker(s.id, d.delta),
                                    onPanEnd: (_) {
                                      final pos = _textStickers
                                          .firstWhere((e) => e.id == s.id)
                                          .position;
                                      if (pos.dx <= 90 && pos.dy <= 120) {
                                        _textStickers.removeWhere((e) => e.id == s.id);
                                      }
                                      setState(() {
                                        _draggingTextId = null;
                                        _showDeleteZone = false;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        s.text,
                                        style: GoogleFonts.dmSans(
                                          color: Colors.black,
                                          fontSize: s.fontSize,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                          ],
                        );
                      })
                    : const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kMarker)),
              ),
            ),
          ),

          // ── Eraser cursor ring ────────────────────────────────────────────
          if (_tool == _Tool.eraser && _livePoints.isNotEmpty)
            _EraserCursor(
              center: _livePoints.last,
              radius: _eraserHitRadius,
            ),

          // ── Pen cursor ring (shows stroke width) ──────────────────────────
          if (_tool == _Tool.pen && _drawing && _livePoints.isNotEmpty)
            _PenCursor(
              center: _livePoints.last,
              radius: _drawWidth / 2,
            ),
          if (_showDeleteZone)
            Positioned(
              top: 74,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _kDanger.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.delete_forever, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _draggingTextId == null ? 'Delete' : 'Drag here to delete',
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Top bar ───────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              canUndo: _history.isNotEmpty,
              canRedo: _redoStack.isNotEmpty,
              canClear: _strokes.isNotEmpty,
              saving: _saving,
              onDiscard: _discard,
              onUndo: _undo,
              onRedo: _redo,
              onClear: _clear,
              onSave: _save,
            ),
          ),

          // ── Bottom toolbar ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomBar(
              tool: _tool,
              width: _width,
              onAddText: _addOrEditText,
              onTool: (t) => setState(() => _tool = t),
              onWidth: (w) => setState(() => _width = w),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER
// Two-layer: photo always at the bottom, strokes on top.
// No BlendMode.clear, no saveLayer, no pixel deletion.
// Eraser works by removing strokes from the list — the painter just redraws.
// ─────────────────────────────────────────────────────────────────────────────
class _MarkerPainter extends CustomPainter {
  final ui.Image image;
  final List<_Stroke> strokes; // immutable snapshot passed in
  final List<Offset> livePoints;
  final double liveWidth;
  final bool isDrawing;

  const _MarkerPainter({
    required this.image,
    required this.strokes,
    required this.livePoints,
    required this.liveWidth,
    required this.isDrawing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Layer 1: photo ────────────────────────────────────────────────────
    final dst =
        _fittedRect(image.width.toDouble(), image.height.toDouble(), size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );

    // ── Layer 2: committed strokes ────────────────────────────────────────
    canvas.save();
    canvas.clipRect(dst); // keep strokes inside photo bounds
    for (final s in strokes) {
      _drawStroke(canvas, s.pts, s.width);
    }
    // ── Layer 2b: live (in-progress) stroke ───────────────────────────────
    if (isDrawing && livePoints.isNotEmpty) {
      _drawStroke(canvas, livePoints, liveWidth);
    }
    canvas.restore();
  }

  void _drawStroke(Canvas canvas, List<Offset> pts, double width) {
    if (pts.isEmpty) return;
    final paint = Paint()
      ..color = _kMarker
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (pts.length == 1) {
      canvas.drawCircle(
          pts.first,
          width / 2,
          Paint()
            ..color = _kMarker
            ..isAntiAlias = true);
      return;
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      if (i < pts.length - 1) {
        final mid = Offset(
          (pts[i].dx + pts[i + 1].dx) / 2,
          (pts[i].dy + pts[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => true;
  // Always repaint — cheap because we're only drawing lines, not pixels.
}

// ── helper ────────────────────────────────────────────────────────────────────
Rect _fittedRect(double imgW, double imgH, Size canvas) {
  final sx = canvas.width / imgW;
  final sy = canvas.height / imgH;
  final s = sx < sy ? sx : sy;
  final w = imgW * s;
  final h = imgH * s;
  return Rect.fromLTWH(
    (canvas.width - w) / 2,
    (canvas.height - h) / 2,
    w,
    h,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CURSORS
// ─────────────────────────────────────────────────────────────────────────────
class _EraserCursor extends StatelessWidget {
  final Offset center;
  final double radius;
  const _EraserCursor({required this.center, required this.radius});

  @override
  Widget build(BuildContext context) {
    final r = radius.clamp(10.0, 80.0);
    return Positioned(
      left: center.dx - r,
      top: center.dy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kDanger.withOpacity(0.15),
            border: Border.all(color: _kDanger, width: 2),
          ),
          child: const Center(
            child:
                Icon(Icons.auto_fix_normal_rounded, color: _kDanger, size: 14),
          ),
        ),
      ),
    );
  }
}

class _PenCursor extends StatelessWidget {
  final Offset center;
  final double radius;
  const _PenCursor({required this.center, required this.radius});

  @override
  Widget build(BuildContext context) {
    final r = radius.clamp(3.0, 24.0);
    return Positioned(
      left: center.dx - r,
      top: center.dy - r,
      child: IgnorePointer(
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kMarker.withOpacity(0.35),
            border: Border.all(color: _kMarker, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final bool canUndo, canRedo, canClear, saving;
  final VoidCallback onDiscard, onUndo, onRedo, onClear, onSave;

  const _TopBar({
    required this.canUndo,
    required this.canRedo,
    required this.canClear,
    required this.saving,
    required this.onDiscard,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(12, topPad + 10, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.85), Colors.transparent],
        ),
      ),
      child: Row(children: [
        // ── Left: Discard ────────────────────────────────────────────────
        _IconBtn(
          icon: Icons.close_rounded,
          label: 'Discard',
          color: Colors.white70,
          enabled: true,
          onTap: onDiscard,
        ),
        const SizedBox(width: 8),
        // ── Centre: Undo / Redo / Clear ───────────────────────────────────
        _IconBtn(
          icon: Icons.undo_rounded,
          label: 'Undo',
          color: Colors.white,
          enabled: canUndo,
          onTap: onUndo,
        ),
        const SizedBox(width: 6),
        _IconBtn(
          icon: Icons.redo_rounded,
          label: 'Redo',
          color: Colors.white,
          enabled: canRedo,
          onTap: onRedo,
        ),
        const SizedBox(width: 6),
        _IconBtn(
          icon: Icons.layers_clear_rounded,
          label: 'Clear',
          color: _kDanger,
          enabled: canClear,
          onTap: onClear,
        ),
        const Spacer(),
        // ── Right: Save ───────────────────────────────────────────────────
        GestureDetector(
          onTap: saving ? null : onSave,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: saving ? _kCopper.withOpacity(0.55) : _kCopper,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                    color: _kCopper.withOpacity(0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text('Use Photo',
                        style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : color.withOpacity(0.25);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: Colors.white.withOpacity(enabled ? 0.14 : 0.05)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 21),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.dmSans(
                  color: c, fontSize: 9, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM TOOLBAR
// ─────────────────────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final _Tool tool;
  final double width;
  final VoidCallback onAddText;
  final ValueChanged<_Tool> onTool;
  final ValueChanged<double> onWidth;

  const _BottomBar({
    required this.tool,
    required this.width,
    required this.onAddText,
    required this.onTool,
    required this.onWidth,
  });

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;
    final isPen = tool == _Tool.pen;
    final isText = tool == _Tool.text;
    final accent = isPen ? _kMarker : (isText ? _kCopper : _kDanger);

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.90)],
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Instruction banner ─────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _kMarker.withOpacity(0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _kMarker.withOpacity(0.28)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.info_outline_rounded, size: 12, color: _kMarker),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Draw a horizontal line at the oil level on the scale',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _kMarker, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Tool selector ──────────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _ToolChip(
            icon: Icons.brush_rounded,
            label: 'Draw',
            active: isPen,
            activeColor: _kMarker,
            onTap: () => onTool(_Tool.pen),
          ),
          const SizedBox(width: 12),
          _ToolChip(
            icon: Icons.text_fields_rounded,
            label: 'Text',
            active: isText,
            activeColor: _kCopper,
            onTap: () => onTool(_Tool.text),
          ),
          const SizedBox(width: 12),
          _ToolChip(
            icon: Icons.auto_fix_normal_rounded,
            label: 'Erase',
            active: tool == _Tool.eraser,
            activeColor: _kDanger,
            onTap: () => onTool(_Tool.eraser),
          ),
        ]),
        if (isText) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAddText,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Add Text'),
          ),
        ],
        const SizedBox(height: 16),

        // ── Width slider ───────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Thin line preview
          Container(
            width: 20,
            height: 2,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                thumbColor: accent,
                inactiveTrackColor: Colors.white.withOpacity(0.14),
                overlayColor: accent.withOpacity(0.14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                trackHeight: 3,
              ),
              child: Slider(
                value: width,
                min: 2,
                max: 24,
                divisions: 22,
                onChanged: onWidth,
              ),
            ),
          ),
          // Thick line preview
          Container(
            width: 24,
            height: 8,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          // Live dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: width.clamp(4, 24),
            height: width.clamp(4, 24),
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text('${width.round()}',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: _kSub, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
          decoration: BoxDecoration(
            color: active
                ? activeColor.withOpacity(0.14)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? activeColor.withOpacity(0.80)
                  : Colors.white.withOpacity(0.10),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: active ? activeColor : _kSub, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.dmSans(
                    color: active ? activeColor : _kSub,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13)),
          ]),
        ),
      );
}
