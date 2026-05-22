part of '../dashboard_tab.dart';


class _AlertCardState extends State<_AlertCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final color = _sevColor(a.severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // ── Collapsed row ────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(14),
                    bottom:
                        _expanded ? Radius.zero : const Radius.circular(14)),
              ),
              child: Row(children: [
                Icon(_sevIcon(a.severity), color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(a.alertTitle,
                                style: GoogleFonts.dmSans(
                                    color: _kText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                          if (a.isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kDanger.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                    color: _kDanger.withOpacity(0.4)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 5,
                                        height: 5,
                                        decoration: const BoxDecoration(
                                            color: _kDanger,
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 3),
                                    Text('LIVE',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 8,
                                            color: _kDanger,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8)),
                                  ]),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          '${a.tankName} · ${a.paramLabel}: ${a.paramValue}',
                          style: GoogleFonts.dmSans(color: _kSub, fontSize: 11),
                        ),
                      ]),
                ),
                const SizedBox(width: 6),
                Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SevBadge(a.severity),
                      const SizedBox(height: 4),
                      Text(_fmtTsShort(a.timestamp),
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, color: _kSubL)),
                    ]),
                const SizedBox(width: 6),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _kSubL,
                    size: 18),
              ]),
            ),
          ),

          // ── Expanded body ─────────────────────────────────────────
          if (_expanded) ...[
            Container(height: 1, color: color.withOpacity(0.2)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // All DB fields
                  _DetailRow('Message', a.message),
                  _DetailRow('Tank', '${a.tankName} (${a.tankCode})'),
                  _DetailRow('Parameter', a.paramLabel),
                  _DetailRow('Value', a.paramValue),
                  _DetailRow('Captured By', a.capturedByName),
                  _DetailRow('Timestamp', _fmtTs(a.timestamp)),
                  // _DetailRow('Constraint ', a.constraintId),
                  _DetailRow(
  'Constraint',
  '${a.paramLabel} ${a.op} ${a.paramValue} then ${a.message}',
),
                  if (a.imageUrl.isNotEmpty) _DetailRow('Image', a.imageUrl),
                  _DetailRow('Alert ID', a.id),

                  const SizedBox(height: 14),

                  // Complete button
                  GestureDetector(
                    onTap: widget.onComplete,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _kSuccess.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kSuccess.withOpacity(0.4)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                color: _kSuccess, size: 16),
                            const SizedBox(width: 7),
                            Text('Complete Task',
                                style: GoogleFonts.dmSans(
                                    color: _kSuccess,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
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
}
