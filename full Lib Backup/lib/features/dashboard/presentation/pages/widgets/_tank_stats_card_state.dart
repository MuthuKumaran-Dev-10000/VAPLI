part of '../dashboard_tab.dart';


class _TankStatsCardState extends State<_TankStatsCard> {
  DashboardStatsModel? _stats;
  bool _lastExpanded = false;
  StreamSubscription<DashboardStatsModel>? _sub;

  @override
  void initState() {
    super.initState();
    _sub =
        DashboardStatsRepository().watchStats(widget.tank.id).listen((stats) {
      if (mounted) setState(() => _stats = stats);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _fmtNum(double? v) {
    if (v == null) return '—';
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
  }

  String _fmtTs(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('dd MMM yyyy, HH:mm')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  String _fmtLastVal(dynamic v) {
    if (v == null) return '—';
    if (v is Map) {
      return '${v['left'] ?? ''} / ${v['right'] ?? ''}';
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final tank = widget.tank;
    final props = List<Map<String, dynamic>>.from(tank.inspectionProperties);
    final hasData = stats != null && stats.count > 0;

    final showLastInspectionExpanded =
        _lastExpanded || widget.forceExpandLastInspection;

    return RepaintBoundary(
      key: widget.captureKey,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(tank, stats),
          if (stats == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kCopper)),
              ),
            )
          else if (!hasData)
            _buildNoData()
          else ...[
            _buildMetaRow(stats),
            const _Divider(),
            if (props.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('PARAMETER STATS'),
                    const SizedBox(height: 12),
                    ...props.map((p) => _buildParamBlock(p, stats)),
                  ],
                ),
              ),
            const _Divider(),
            _buildLastInspection(
              props,
              stats,
              forceExpanded: showLastInspectionExpanded,
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildCardHeader(TankModel tank, DashboardStatsModel? stats) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _kCopper.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: _kCopper.withOpacity(0.4)),
          ),
          child: Center(
            child: Text(
              tank.tankCode.isNotEmpty ? tank.tankCode[0].toUpperCase() : '?',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _kCopper),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tank.tankName,
                style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _kText)),
            const SizedBox(height: 2),
            Row(children: [
              Text(tank.tankCode,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: _kCopper,
                      fontWeight: FontWeight.w600)),
              if ((tank.location ?? '').isNotEmpty) ...[
                Text('  •  ', style: const TextStyle(color: _kBorderH)),
                const Icon(Icons.location_on_outlined, size: 11, color: _kSub),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(tank.location!,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 11, color: _kSub)),
                ),
              ],
            ]),
          ]),
        ),
        if (stats != null && stats.count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kCopper.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kCopper.withOpacity(0.3)),
            ),
            child: Column(children: [
              Text('${stats.count}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kCopper)),
              Text('readings',
                  style: GoogleFonts.dmSans(fontSize: 9, color: _kCopperD)),
            ]),
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Download tank as PNG',
          onPressed: widget.onDownloadPng,
          icon: const Icon(Icons.download_rounded, color: _kCopper),
        ),
      ]),
    );
  }

  Widget _buildNoData() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.hourglass_empty_rounded, size: 18, color: _kSubL),
          const SizedBox(width: 8),
          Text('No readings yet for this tank',
              style: GoogleFonts.dmSans(fontSize: 13, color: _kSub)),
        ]),
      );

  Widget _buildMetaRow(DashboardStatsModel stats) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
              child: _MetaPill(
                  icon: Icons.person_outline_rounded,
                  label: 'Captured By',
                  value: stats.lastCapturedBy ?? '—',
                  color: _kTeal)),
          const SizedBox(width: 10),
          Expanded(
              child: _MetaPill(
                  icon: Icons.schedule_outlined,
                  label: 'Last Inspection',
                  value: _fmtTs(stats.lastCapturedAt),
                  color: _kBlue)),
        ]),
      );

  Widget _buildParamBlock(Map<String, dynamic> p, DashboardStatsModel stats) {
    final label = (p['label'] as String?) ?? '';
    final type = (p['type'] as String?) ?? 'text';
    if (label.isEmpty) return const SizedBox.shrink();
    final stat = stats.paramStats[label];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.dmSans(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
          ),
          _TypeBadge(type),
        ]),
        const SizedBox(height: 8),
        if (stat == null)
          Text('No data', style: GoogleFonts.dmSans(fontSize: 12, color: _kSub))
        else if (type == 'number' || type == 'slider')
          _NumericStatRow(
  stat: stat,
  fmtNum: _fmtNum,
  expectedAvg: (p['expected_avg'] as num?)?.toDouble(),
  expectedMin: (p['expected_min'] as num?)?.toDouble(),
expectedMax: (p['expected_max'] as num?)?.toDouble(),
  // expectedMin: (p['min'] as num?)?.toDouble(),
  // expectedMax: (p['max'] as num?)?.toDouble(),
)
        else if (type == 'dropdown')
          _DropdownStatBlock(stat: stat, totalCount: stats.count)
        else if (type == 'dual_text')
          _DualStatBlock(stat: stat, fmtNum: _fmtNum, prop: p)
        else
          _TextLastValue(value: _fmtLastVal(stat.lastValue)),
      ]),
    );
  }

  Widget _buildLastInspection(
    List<Map<String, dynamic>> props,
    DashboardStatsModel stats, {
    required bool forceExpanded,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.forceExpandLastInspection
              ? null
              : () => setState(() => _lastExpanded = !_lastExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              const Icon(Icons.history_rounded, size: 16, color: _kCopper),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Last Inspection Values',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kText)),
              ),
              Icon(
                  forceExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _kSub,
                  size: 20),
            ]),
          ),
        ),
        if (forceExpanded)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: stats.lastReading.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No reading data',
                        style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
                  )
                : Column(
                    children: [
                      ...props.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      final lbl = (p['label'] as String?) ?? '';
                      final val = stats.lastReading[lbl];
                      final isLast = i == props.length - 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: isLast
                              ? null
                              : const Border(
                                  bottom: BorderSide(color: _kBorder)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.28,
                              child: Text(lbl,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: _kSub,
                                      fontWeight: FontWeight.w500)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _fmtLastVal(val),
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    color: _kText,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                      }).toList(),
                      ...stats.lastReading.entries
                          .where((e) =>
                              e.key.toString().contains('image_url') &&
                              (e.value?.toString().trim().isNotEmpty ?? false))
                          .map((e) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: const BoxDecoration(
                                  border: Border(top: BorderSide(color: _kBorder)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: MediaQuery.of(context).size.width * 0.28,
                                      child: Text(
                                        e.key,
                                        style: GoogleFonts.dmSans(
                                            fontSize: 12,
                                            color: _kSub,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _ImageThumb(
                                        url: e.value.toString(),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                    ],
                  ),
          ),
      ],
    );
  }
}
