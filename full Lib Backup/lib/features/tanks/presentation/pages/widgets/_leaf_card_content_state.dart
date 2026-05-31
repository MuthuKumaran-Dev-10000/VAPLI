part of '../tank_browser_screen.dart';


class _LeafCardContentState extends State<_LeafCardContent> {
  final _shotCtrl = ScreenshotController();
  bool _busy = false;

  String get _qrData {
    final t = widget.tank;
    return [
      'path:${widget.node.path}',
      'tank_id:${widget.node.tankId ?? ''}',
      'tank_code:${t?.tankCode ?? ''}',
      'tank_name:${t?.tankName ?? widget.node.name}',
      'zone:${widget.node.zone ?? t?.location ?? ''}',
    ].join('|');
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _kDanger,
          behavior: SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _modify() => _run(() async {
        final t = widget.tank;
        if (t == null) return;
        final tankMap = {
          'id': t.id,
          'tank_code': t.tankCode,
          'tank_name': t.tankName,
          'location': t.location ?? '',
          'scale_max': t.scaleMax,
          'scale_side': t.scaleSide,
          'qr_image_url': t.qrImageUrl,
          'qr_json': t.qrJson,
          'inspection_properties': t.inspectionProperties
              .map((p) => Map<String, dynamic>.from(p))
              .toList(),
        };
        final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => CreateTankScreen(existingTank: tankMap)));
        final tid = widget.node.tankId;
        if (ok == true && tid != null && mounted) {
          final updated = await widget.tankRepo.getTankById(tid);
          if (updated != null) widget.onTankCacheUpdate(tid, updated);
        }
      });

  Future<void> _duplicate() => _run(() async {
        final t = widget.tank;
        final tid = widget.node.tankId;
        if (t == null || tid == null) return;
        final base = t.tankName.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
        final newName = '$base (1)';
        final newTankId = await widget.tankRepo.duplicateTank(t);
        await widget.treeRepo.createLeaf(
          name: newName,
          tankId: newTankId,
          zone: widget.node.zone ?? t.location,
          parentId: widget.currentParentId,
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cloned as "$newName"',
                style: GoogleFonts.raleway(
                    color: _kText, fontWeight: FontWeight.w600)),
            backgroundColor: _kSuccess,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
      });

  Future<void> _downloadQr() => _run(() async {
        final bytes = await _shotCtrl.captureFromWidget(
          Material(
              color: Colors.white,
              child: _PrintableQr(node: widget.node, tank: widget.tank)),
          pixelRatio: 3.0,
        );
        final qrUrl = await uploadBytesToCloudinary(bytes, folder: folderMain);
        final tid = widget.node.tankId;
        if (tid != null) {
          await FirebaseDatabase.instance
              .ref('tanks/$tid')
              .update({'qr_image_url': qrUrl});
        }
        final dir = await getApplicationDocumentsDirectory();
        final file = File(
            '${dir.path}/qr_${widget.tank?.tankCode ?? widget.node.id}.png');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)],
            text: 'QR for ${widget.node.name}');
      });

  @override
  Widget build(BuildContext context) {
    final t = widget.tank;
    final name = t?.tankName ?? widget.node.name;
    final code = t?.tankCode ?? '—';
    final zone = widget.node.zone ?? t?.location ?? '';
    final paramCount = t?.inspectionProperties.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: widget.isGhost
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.12), blurRadius: 6)
                ],
              ),
              child: QrImageView(
                data: _qrData,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.raleway(
                            color: _kText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(code,
                        style: GoogleFonts.sourceCodePro(
                            color: _kCopper,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2)),
                    if (zone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 11, color: _kSub),
                        const SizedBox(width: 3),
                        Expanded(
                            child: Text(zone,
                                style: GoogleFonts.raleway(
                                    color: _kSub, fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                    if (paramCount > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 5, children: [
                        _Pill(
                            label:
                                '$paramCount param${paramCount == 1 ? '' : 's'}',
                            icon: Icons.tune_rounded,
                            color: _kTeal),
                        if (t?.scaleSide != null)
                          _Pill(
                              label: 'Scale ${t!.scaleSide}',
                              icon: Icons.straighten_rounded,
                              color: _kPurple),
                      ]),
                    ],
                  ]),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.drag_indicator_rounded, size: 18, color: _kSubL),
              if (_busy) ...[
                const SizedBox(height: 8),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: _kCopper, strokeWidth: 1.8)),
              ],
            ]),
          ]),
        ),
        if (!widget.isGhost)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              border: Border(top: BorderSide(color: _kBorder)),
            ),
            child: _busy
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: _kCopper, strokeWidth: 2)))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                        if (widget.canModify)
                        _ActionChip(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            color: _kTeal,
                            onTap: _modify),
                        if (widget.canDuplicate)
                        _ActionChip(
                            icon: Icons.copy_outlined,
                            label: 'Clone',
                            color: _kAmber,
                            onTap: _duplicate),
                        _ActionChip(
                            icon: Icons.qr_code_rounded,
                            label: 'QR',
                            color: _kCopper,
                            onTap: _downloadQr),
                        if (widget.canModify)
                        _ActionChip(
                            icon: Icons.drive_file_move_outline,
                            label: 'Move',
                            color: _kPurple,
                            onTap: widget.onMove),
                        if (widget.canDelete)
                        _ActionChip(
                            icon: Icons.delete_outline_rounded,
                            label: 'Del',
                            color: _kDanger,
                            onTap: widget.onDelete),
                      ]),
          ),
      ]),
    );
  }
}
