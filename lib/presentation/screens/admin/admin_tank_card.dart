import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/tank_model.dart';

import 'admin_action_bar.dart';
import 'admin_cloudinary.dart';
import 'create_tank_screen_main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TankAdminCard
// Actions: [Duplicate] [Modify] [Download QR] [Delete]
// ─────────────────────────────────────────────────────────────────────────────

class TankAdminCard extends StatefulWidget {
  final TankModel tank;
  final List<String> allTankCodes;
  final String Function(String base) nextFreeCode;
  final VoidCallback onDelete;

  const TankAdminCard({
    required this.tank,
    required this.allTankCodes,
    required this.nextFreeCode,
    required this.onDelete,
  });

  @override
  State<TankAdminCard> createState() => TankAdminCardState();
}

class TankAdminCardState extends State<TankAdminCard> {
  final _shotCtrl = ScreenshotController();
  bool _busy = false; // prevents double-tap during async ops

  // ── busy guard wrapper ─────────────────────────────────────────────────────

  Future<void> _run(String tag, Future<void> Function() fn) async {
    if (_busy) {
      debugPrint('[$tag] Ignored — card is busy');
      return;
    }
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e, s) {
      debugPrint('[$tag] ERROR: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── DUPLICATE ─────────────────────────────────────────────────────────────

  Future<void> _duplicate() => _run('Duplicate', () async {
        final t = widget.tank;
        debugPrint('[Duplicate] Tapped for tank: ${t.tankCode} id=${t.id}');

        final newCode = widget.nextFreeCode(t.tankCode);
        debugPrint('[Duplicate] New code will be: $newCode');

        // Build a map that mirrors the existing tank, then override code + remove id
        final dupMap = <String, dynamic>{
          'tank_code': newCode,
          'tank_name': t.tankName,
          'location': t.location ?? '',
          'scale_max': t.scaleMax,
          'scale_side': t.scaleSide,
          'inspection_properties': t.inspectionProperties
                  ?.map((p) => Map<String, dynamic>.from(p))
                  .toList() ??
              [],
        };
        debugPrint('[Duplicate] Dup map built (no id — repo will assign one)');

        // Open CreateTankScreen pre-filled as a duplicate
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => CreateTankScreen(
              existingTank: dupMap,
              isDuplicate: true,
            ),
          ),
        );
        debugPrint('[Duplicate] CreateTankScreen returned ok=$ok');
        // Stream listener on parent will auto-refresh the list
      });

  // ── MODIFY ────────────────────────────────────────────────────────────────

  Future<void> _modify() => _run('Modify', () async {
        final t = widget.tank;
        debugPrint('[Modify] Tapped for tank: ${t.tankCode} id=${t.id}');

        // Convert TankModel → Map for CreateTankScreen
        final tankMap = <String, dynamic>{
          'id': t.id,
          'tank_code': t.tankCode,
          'tank_name': t.tankName,
          'location': t.location ?? '',
          'scale_max': t.scaleMax,
          'scale_side': t.scaleSide,
          'qr_image_url': t.qrImageUrl,
          'qr_json': t.qrJson,
          'inspection_properties': t.inspectionProperties
                  ?.map((p) => Map<String, dynamic>.from(p))
                  .toList() ??
              [],
        };

        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => CreateTankScreen(existingTank: tankMap),
          ),
        );
        debugPrint('[Modify] CreateTankScreen returned ok=$ok');
        // Stream listener on parent will auto-refresh the list
      });

  // ── DOWNLOAD QR ───────────────────────────────────────────────────────────

  Future<void> _downloadQr() => _run('Download', () async {
        final t = widget.tank;
        debugPrint('[Download] Generating printable QR for ${t.tankCode}');

        final imageBytes = await _shotCtrl.captureFromWidget(
          Material(
            color: Colors.white,
            child: _buildPrintableQr(),
          ),
          pixelRatio: 3.0,
        );
        debugPrint('[Download] Captured ${imageBytes.length} bytes');

        // Upload to Cloudinary and persist URL
        final qrUrl =
            await uploadBytesToCloudinary(imageBytes, folder: folderMain);
        debugPrint('[Download] Updating qr_image_url in Firebase for ${t.id}');
        await FirebaseDatabase.instance
            .ref('tanks/${t.id}')
            .update({'qr_image_url': qrUrl});

        // Save locally and share
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/qr_${t.tankCode}.png');
        await file.writeAsBytes(imageBytes);
        debugPrint('[Download] Saved locally → ${file.path}');

        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'QR for ${t.tankName}',
        );
        debugPrint('[Download] Share sheet opened');
      });

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    debugPrint('[Delete] Confirm dialog opened for ${widget.tank.tankCode}');
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Tank'),
        content:
            Text('Delete "${widget.tank.tankName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('[Delete] Cancelled');
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              debugPrint('[Delete] Confirmed');
              Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (yes == true) {
      debugPrint('[Delete] Calling onDelete for ${widget.tank.id}');
      widget.onDelete();
    }
  }

  // ── printable QR widget (used by download) ─────────────────────────────────

  Widget _buildPrintableQr() {
    final t = widget.tank;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: t.qrJson ?? t.id,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 14),
          Text('Tank ID : ${t.tankCode}',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Name : ${t.tankName}',
              style: const TextStyle(color: Colors.black, fontSize: 15)),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = widget.tank;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── QR thumbnail ────────────────────────────────────────────────
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              padding: const EdgeInsets.all(4),
              child: t.qrImageUrl != null
                  ? Image.network(t.qrImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => QrImageView(
                          data: t.qrJson ?? t.id,
                          size: 52,
                          backgroundColor: Colors.white))
                  : QrImageView(
                      data: t.qrJson ?? t.id,
                      size: 52,
                      backgroundColor: Colors.white),
            ),
            const SizedBox(width: 12),

            // ── name + code + location ───────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.tankCode,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(t.tankName,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  if ((t.location ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 2),
                      Text(t.location!,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ]),
                  ],
                  if ((t.inspectionProperties ?? []).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${t.inspectionProperties!.length} param${t.inspectionProperties!.length == 1 ? '' : 's'}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.blue.shade400),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── action buttons ───────────────────────────────────────────────
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              ActionBar(
                onDuplicate: _duplicate,
                onModify: _modify,
                onDownloadQr: _downloadQr,
                onDelete: _confirmDelete,
              ),
          ],
        ),
      ),
    );
  }
}
