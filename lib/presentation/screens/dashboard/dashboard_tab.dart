// lib/presentation/screens/dashboard/dashboard_tab.dart
// ══════════════════════════════════════════════════════════════════════════════
// DashboardTab — drop this widget into your MainScreen / HomeScreen TabBarView.
//
// DISPLAYS PER TANK:
//   • Total readings count + last inspector + last timestamp
//   • Numeric params  → avg / min / max chip row
//   • Dropdown params → horizontal percentage bar per option
//   • Text/multiline/dual_text → last captured value only
//   • "Last Inspection" expandable panel — all param values of the latest reading
//
// DATA FLOW:
//   TankRepository.watchTanks()          → list of tanks (live)
//   DashboardStatsRepository.watchStats(tankId) → aggregated stats (live)
//   No recalculation — stats are pre-aggregated by ReadingEntryScreen on save.
//
// USAGE (inside your MainScreen build):
//   TabBarView(children: [
//     DashboardTab(currentUser: _user),
//     ...
//   ])
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../data/models/dashboard_stats_model.dart';
import '../../../data/models/tank_model.dart';
import '../../../data/repositories/dashboard_stats_repository.dart';
import '../../../data/repositories/tank_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette — "Obsidian Industrial" theme matching ReadingEntryScreen
// ─────────────────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0C0D0F);
const _kSurface = Color(0xFF141618);
const _kCard = Color(0xFF1A1C20);
const _kCardHi = Color(0xFF1F2228);
const _kBorder = Color(0xFF252830);
const _kBorderH = Color(0xFF38404F);
const _kCopper = Color(0xFFCB8C3E);
const _kCopperL = Color(0xFFE8A84E);
const _kCopperD = Color(0xFF8A5A1E);
const _kTeal = Color(0xFF1ABCBD);
const _kText = Color(0xFFF0EEE9);
const _kSub = Color(0xFF8A8F9C);
const _kSubL = Color(0xFF6B7280);
const _kSuccess = Color(0xFF22C55E);
const _kWarn = Color(0xFFF59E0B);
const _kDanger = Color(0xFFEF4444);
const _kPurple = Color(0xFFAB8FF0);
const _kBlue = Color(0xFF60A5FA);

// ─────────────────────────────────────────────────────────────────────────────
// DashboardTab
// ─────────────────────────────────────────────────────────────────────────────

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<TankModel> _tanks = [];
  StreamSubscription<List<TankModel>>? _tankSub;

  @override
  void initState() {
    super.initState();
    debugPrint('[DashboardTab] initState — subscribing to tank stream');
    _tankSub = TankRepository().watchTanks().listen((tanks) {
      debugPrint('[DashboardTab] Tanks updated: ${tanks.length}');
      if (mounted) setState(() => _tanks = tanks);
    });
  }

  @override
  void dispose() {
    _tankSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: _tanks.isEmpty
          ? _buildEmpty()
          : CustomScrollView(
              slivers: [
                // ── Header ───────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildHeader()),

                // ── Summary strip ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _SummaryStrip(tankCount: _tanks.length),
                ),

                // ── Tank cards ────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _TankStatsCard(tank: _tanks[i]),
                      childCount: _tanks.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Row(children: [
          // Copper accent bar
          Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                  color: _kCopper, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dashboard',
                  style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kText)),
              Text('Live aggregated readings per tank',
                  style: GoogleFonts.dmSans(fontSize: 12, color: _kSub)),
            ]),
          ),
          // Live dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kSuccess.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kSuccess.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: _kSuccess, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('LIVE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: _kSuccess,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ]),
          ),
        ]),
      );

  Widget _buildEmpty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.analytics_outlined, size: 52, color: _kSubL),
          const SizedBox(height: 14),
          Text('No tanks configured',
              style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w600, color: _kText)),
          const SizedBox(height: 6),
          Text('Add tanks in the Admin panel to see stats here',
              style: GoogleFonts.dmSans(fontSize: 13, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryStrip — top-level KPI row (total tanks / total readings)
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStrip extends StatefulWidget {
  final int tankCount;
  const _SummaryStrip({required this.tankCount});

  @override
  State<_SummaryStrip> createState() => _SummaryStripState();
}

class _SummaryStripState extends State<_SummaryStrip> {
  int _totalReadings = 0;
  int _activeToday = 0;
  final _repo = DashboardStatsRepository();
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    // Watch all tanks to sum readings; re-subscribe when tank count changes
    _subscribeTanks();
  }

  @override
  void didUpdateWidget(_SummaryStrip old) {
    super.didUpdateWidget(old);
    if (old.tankCount != widget.tankCount) _subscribeTanks();
  }

  void _subscribeTanks() {
    _sub?.cancel();
    // Listen to each tank's stats and sum counts
    TankRepository().watchTanks().listen((tanks) async {
      int total = 0, today = 0;
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final t in tanks) {
        final stats = await _repo.getStats(t.id);
        total += stats.count;
        if (stats.lastCapturedAt != null &&
            stats.lastCapturedAt!.startsWith(todayStr)) {
          today++;
        }
      }
      if (mounted)
        setState(() {
          _totalReadings = total;
          _activeToday = today;
        });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        Expanded(
            child: _KpiChip(
                icon: Icons.storage_outlined,
                label: 'Tanks',
                value: '${widget.tankCount}',
                color: _kTeal)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiChip(
                icon: Icons.receipt_long_outlined,
                label: 'Total Readings',
                value: '$_totalReadings',
                color: _kCopper)),
        const SizedBox(width: 10),
        Expanded(
            child: _KpiChip(
                icon: Icons.today_outlined,
                label: 'Active Today',
                value: '$_activeToday',
                color: _kSuccess)),
      ]),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _KpiChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _kText)),
          Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: _kSub)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _TankStatsCard — the main card per tank
// ─────────────────────────────────────────────────────────────────────────────

class _TankStatsCard extends StatefulWidget {
  final TankModel tank;
  const _TankStatsCard({required this.tank});

  @override
  State<_TankStatsCard> createState() => _TankStatsCardState();
}

class _TankStatsCardState extends State<_TankStatsCard> {
  DashboardStatsModel? _stats;
  bool _lastExpanded = false;
  StreamSubscription<DashboardStatsModel>? _sub;

  @override
  void initState() {
    super.initState();
    debugPrint('[TankStatsCard] Subscribing to stats for ${widget.tank.id}');
    _sub =
        DashboardStatsRepository().watchStats(widget.tank.id).listen((stats) {
      debugPrint(
          '[TankStatsCard] Stats update for ${widget.tank.tankCode}: count=${stats.count}');
      if (mounted) setState(() => _stats = stats);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  String _fmtNum(double? v) {
    if (v == null) return '—';
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(2);
  }

  String _fmtTs(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  String _fmtLastVal(dynamic v) {
    if (v == null) return '—';
    if (v is Map) {
      final l = v['left']?.toString() ?? '';
      final r = v['right']?.toString() ?? '';
      return '$l / $r';
    }
    return v.toString();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final tank = widget.tank;
    final props = List<Map<String, dynamic>>.from(tank.inspectionProperties);
    final hasData = stats != null && stats.count > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ────────────────────────────────────────────────
          _buildCardHeader(tank, stats),

          if (stats == null)
            // Loading shimmer placeholder
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
            // ── Meta row ─────────────────────────────────────────────────
            _buildMetaRow(stats),

            const _Divider(),

            // ── Parameter stat blocks ─────────────────────────────────────
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

            // ── Last inspection expandable ────────────────────────────────
            _buildLastInspection(props, stats),
          ],
        ],
      ),
    );
  }

  // ── Card header ──────────────────────────────────────────────────────────

  Widget _buildCardHeader(TankModel tank, DashboardStatsModel? stats) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(children: [
        // Copper circle with initial
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
                Text('  •  ', style: TextStyle(color: _kBorderH)),
                Icon(Icons.location_on_outlined, size: 11, color: _kSub),
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
        // Reading count badge
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
      ]),
    );
  }

  // ── No data state ──────────────────────────────────────────────────────────

  Widget _buildNoData() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.hourglass_empty_rounded, size: 18, color: _kSubL),
          const SizedBox(width: 8),
          Text('No readings yet for this tank',
              style: GoogleFonts.dmSans(fontSize: 13, color: _kSub)),
        ]),
      );

  // ── Meta row (last inspector + timestamp) ─────────────────────────────────

  Widget _buildMetaRow(
    DashboardStatsModel stats,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          8,
        ),
        child: Row(
          children: [
            Expanded(
              child: _MetaPill(
                icon: Icons.person_outline_rounded,
                label: 'Captured By',
                value: stats.lastCapturedBy ?? '—',
                color: _kTeal,
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: _MetaPill(
                icon: Icons.schedule_outlined,
                label: 'Last Inspection',
                value: _fmtTs(
                  stats.lastCapturedAt,
                ),
                color: _kBlue,
              ),
            ),
          ],
        ),
      );

  // ── Parameter stat block dispatcher ──────────────────────────────────────

  Widget _buildParamBlock(Map<String, dynamic> p, DashboardStatsModel stats) {
    final label = (p['label'] as String?) ?? '';
    final type = (p['type'] as String?) ?? 'text';
    if (label.isEmpty) return const SizedBox.shrink();

    final stat = stats.paramStats[label];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Param label + type badge
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
          _NumericStatRow(stat: stat, fmtNum: _fmtNum)
        else if (type == 'dropdown')
          _DropdownStatBlock(stat: stat, totalCount: stats.count)
        else if (type == 'dual_text') 
          _DualStatBlock( stat: stat, fmtNum: _fmtNum, prop: p, )
        else
          // text / multiline — show last value
          _TextLastValue(value: _fmtLastVal(stat.lastValue)),
      ]),
    );
  }

  // ── Last inspection expandable panel ─────────────────────────────────────

  Widget _buildLastInspection(
      List<Map<String, dynamic>> props, DashboardStatsModel stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle row
        InkWell(
          onTap: () => setState(() => _lastExpanded = !_lastExpanded),
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
                _lastExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _kSub,
                size: 20,
              ),
            ]),
          ),
        ),
        // Expanded content
        if (_lastExpanded)
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
                    children: props.asMap().entries.map((entry) {
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
                            // 35% label
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.28,
                              child: Text(lbl,
                                  style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: _kSub,
                                      fontWeight: FontWeight.w500)),
                            ),
                            const SizedBox(width: 8),
                            // 65% value
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
                  ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NumericStatRow — avg / min / max for number + slider params
// ─────────────────────────────────────────────────────────────────────────────

class _NumericStatRow extends StatelessWidget {
  final ParamStat stat;
  final String Function(double?) fmtNum;
  const _NumericStatRow({required this.stat, required this.fmtNum});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child:
              _NumChip(label: 'AVG', value: fmtNum(stat.avg), color: _kCopper)),
      const SizedBox(width: 8),
      Expanded(
          child:
              _NumChip(label: 'MIN', value: fmtNum(stat.min), color: _kTeal)),
      const SizedBox(width: 8),
      Expanded(
          child:
              _NumChip(label: 'MAX', value: fmtNum(stat.max), color: _kWarn)),
    ]);
  }
}


class _DualStatBlock extends StatelessWidget {

  final ParamStat stat;

  final String Function(double?) fmtNum;

  final Map<String, dynamic> prop;


  const _DualStatBlock({
    required this.stat,
    required this.fmtNum,
    required this.prop,
  });


  @override
  Widget build(BuildContext context) {

    final leftLabel =
        prop["left_label"] ??
            "Before";

    final rightLabel =
        prop["right_label"] ??
            "After";


    final leftStats =
        stat.dualLeftStats;

    final rightStats =
        stat.dualRightStats;


    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        _buildRow(
          leftLabel,
          leftStats,
        ),

        const SizedBox(
          height: 12,
        ),

        _buildRow(
          rightLabel,
          rightStats,
        ),
      ],
    );
  }


  Widget _buildRow(
    String title,
    dynamic s,
  ) {

    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [

        Text(
          title.toUpperCase(),

          style:
              GoogleFonts.spaceGrotesk(

            fontSize: 10,

            color: _kSub,

            fontWeight:
                FontWeight.w700,

            letterSpacing: 1,
          ),
        ),

        const SizedBox(
          height: 6,
        ),

        Row(
          children: [

            Expanded(
              child: _NumChip(

                label: "AVG",

                value: fmtNum(
                  s.avg,
                ),

                color: _kCopper,
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            Expanded(
              child: _NumChip(

                label: "MIN",

                value: fmtNum(
                  s.min,
                ),

                color: _kTeal,
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            Expanded(
              child: _NumChip(

                label: "MAX",

                value: fmtNum(
                  s.max,
                ),

                color: _kWarn,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


class _NumChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _NumChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(children: [
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _kText)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DropdownStatBlock — horizontal bar per option with %
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownStatBlock extends StatelessWidget {
  final ParamStat stat;
  final int totalCount;
  const _DropdownStatBlock({required this.stat, required this.totalCount});

  // Assign a consistent colour per option index
  static const _palette = [
    _kTeal,
    _kCopper,
    _kSuccess,
    _kWarn,
    _kPurple,
    _kBlue,
    _kDanger,
  ];

  @override
  Widget build(BuildContext context) {
    final counts = stat.optionCounts;
    if (counts.isEmpty) {
      return Text('No selections yet',
          style: GoogleFonts.dmSans(fontSize: 12, color: _kSub));
    }

    // Sort by count descending
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = counts.values.fold(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.asMap().entries.map((e) {
        final idx = e.key;
        final opt = e.value.key;
        final count = e.value.value;
        final pct = total > 0 ? (count / total) : 0.0;
        final color = _palette[idx % _palette.length];
        final pctLabel = '${(pct * 100).toStringAsFixed(1)}%';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Option label + count
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(opt,
                      style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: _kText,
                          fontWeight: FontWeight.w500)),
                ),
                Text('$count',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: _kSub,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  child: Text(pctLabel,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 4),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TextLastValue — for text / multiline / dual_text
// ─────────────────────────────────────────────────────────────────────────────

class _TextLastValue extends StatelessWidget {
  final String value;
  const _TextLastValue({required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.format_quote_rounded, size: 14, color: _kSubL),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: _kText, fontStyle: FontStyle.italic)),
          ),
          Text('last',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, color: _kSubL, letterSpacing: 0.5)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable helpers
// ─────────────────────────────────────────────────────────────────────────────

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MetaPill(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.dmSans(fontSize: 9, color: _kSub)),
              Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: _kText,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  static const _colors = <String, Color>{
    'number': _kTeal,
    'slider': Color(0xFF03DAC6),
    'dropdown': _kPurple,
    'text': _kSuccess,
    'multiline': Color(0xFF7986CB),
    'dual_text': _kWarn,
  };
  static const _labels = <String, String>{
    'number': 'NUM',
    'slider': 'SLIDE',
    'dropdown': 'DROP',
    'text': 'TEXT',
    'multiline': 'MULTI',
    'dual_text': 'DUAL',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? _kSub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5)),
      child: Text(
        _labels[type] ?? type.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: _kSubL,
          letterSpacing: 1.5));
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: _kBorder);
}
