part of '../dashboard_tab.dart';


class _CompletedCardState extends State<_CompletedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.task.alert;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSuccess.withOpacity(0.2)),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _kSuccess.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kSuccess.withOpacity(0.3)),
                ),
                child:
                    const Icon(Icons.check_rounded, size: 14, color: _kSuccess),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.alertTitle,
                          style: GoogleFonts.dmSans(
                              color: _kText,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                      Text(
                        '${a.tankName} · completed ${_fmtTs(widget.task.completedAt)}',
                        style: GoogleFonts.dmSans(color: _kSub, fontSize: 10),
                      ),
                    ]),
              ),
              _SevBadge(a.severity),
              const SizedBox(width: 6),
              Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _kSubL,
                  size: 16),
            ]),
          ),
        ),
        if (_expanded) ...[
          Container(height: 1, color: _kBorder),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Message', a.message),
                _DetailRow('Asset', '${a.tankName} (${a.tankCode})'),
                _DetailRow('Parameter', a.paramLabel),
                _DetailRow('Value', a.paramValue),
                _DetailRow('Captured By', a.capturedByName),
                _DetailRow('Alert Time', _fmtTs(a.timestamp)),
                _DetailRow('Completed By', widget.task.completedBy),
                _DetailRow('Completed At', _fmtTs(widget.task.completedAt)),
                _DetailRow('Alert ID', a.id),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}
