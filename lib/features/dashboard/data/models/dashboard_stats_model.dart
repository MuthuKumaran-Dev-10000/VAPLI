// lib/features/dashboard/data/models/dashboard_stats_model.dart
// ══════════════════════════════════════════════════════════════════════════════
// Stores per-tank aggregated stats in Firebase RTDB at:
//   /dashboard_stats/{tankId}
//
// Structure:
//   count          : int       — total readings submitted
//   last_reading   : Map       — full inspection_values of the most recent reading
//   last_captured_at : String  — ISO timestamp of the last reading
//   last_captured_by : String  — full name of the last inspector
//   param_stats    : Map<label, ParamStat>
//
// ParamStat (stored inline as a map):
//   type  : "number" | "dropdown" | "slider" | "text" | "multiline" | "dual_text"
//   --- for numeric (number / slider) ---
//   avg   : double
//   min   : double
//   max   : double
//   --- for dropdown ---
//   option_counts : Map<option, int>
//   --- for text / multiline / dual_text ---
//   last_value : dynamic   (just carry latest value, no avg)
// ══════════════════════════════════════════════════════════════════════════════

class DashboardStatsModel {
  final String tankId;
  final int count;
  final String? lastCapturedAt;
  final String? lastCapturedBy;
  final String? lastDuplicateReason;
  final Map<String, dynamic> lastReading; // inspection_values snapshot
  final Map<String, ParamStat> paramStats;

  const DashboardStatsModel({
    required this.tankId,
    required this.count,
    this.lastCapturedAt,
    this.lastCapturedBy,
    this.lastDuplicateReason,
    required this.lastReading,
    required this.paramStats,
  });

  static DashboardStatsModel empty(String tankId) => DashboardStatsModel(
        tankId: tankId,
        count: 0,
        lastReading: {},
        paramStats: {},
      );

  Map<String, dynamic> toMap() => {
        'tank_id': tankId,
        'count': count,
        'last_captured_at': lastCapturedAt,
        'last_captured_by': lastCapturedBy,
        'last_duplicate_reason': lastDuplicateReason,
        'last_reading': lastReading,
        'param_stats': {
          for (final e in paramStats.entries) e.key: e.value.toMap(),
        },
      };

  factory DashboardStatsModel.fromMap(String tankId, Map<dynamic, dynamic> m) {
    final rawParams = m['param_stats'];
    final Map<String, ParamStat> stats = {};
    if (rawParams is Map) {
      for (final e in rawParams.entries) {
        final key = e.key.toString();
        final val = e.value;
        if (val is Map) {
          stats[key] = ParamStat.fromMap(Map<String, dynamic>.from(val));
        }
      }
    }

    Map<String, dynamic> lastReading = {};
    if (m['last_reading'] is Map) {
      lastReading = Map<String, dynamic>.from(m['last_reading'] as Map);
    }

    return DashboardStatsModel(
      tankId: tankId,
      count: (m['count'] ?? 0) as int,
      lastCapturedAt: m['last_captured_at'] as String?,
      lastCapturedBy: m['last_captured_by'] as String?,
      lastDuplicateReason: m['last_duplicate_reason'] as String?,
      lastReading: lastReading,
      paramStats: stats,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ParamStat — one entry per inspection property
// ─────────────────────────────────────────────────────────────────────────────
class ParamStat {
  final String type; // "number" | "slider" | "dropdown" | "text" | ...

  // numeric aggregates (number / slider)
  final double? avg;
  final double? min;
  final double? max;

  // dropdown: {option → count}
  final Map<String, int> optionCounts;

  // text / multiline / dual_text: last seen value (dynamic)
  final dynamic lastValue;

  final ParamStat? dualLeftStats;

  final ParamStat? dualRightStats;

  const ParamStat({
    required this.type,
    this.avg,
    this.min,
    this.max,
    this.optionCounts = const {},
    this.lastValue,
    this.dualLeftStats,
    this.dualRightStats,
  });

  bool get isNumeric => type == 'number' || type == 'slider';
  bool get isDropdown => type == 'dropdown';
  bool get isText =>
      type == 'text' || type == 'multiline' || type == 'dual_text';

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'type': type};
    if (isNumeric) {
      m['avg'] = avg ?? 0.0;
      m['min'] = min ?? 0.0;
      m['max'] = max ?? 0.0;
    } else if (isDropdown) {
      m['option_counts'] = optionCounts;
      m['last_value'] = lastValue;
    } else if (type == 'dual_text') {
      m['last_value'] = lastValue;

      m['dual_left_stats'] = dualLeftStats?.toMap();

      m['dual_right_stats'] = dualRightStats?.toMap();
    } else {
      m['last_value'] = lastValue;
    }
    return m;
  }

  factory ParamStat.fromMap(Map<String, dynamic> m) {
    final type = m['type'] as String? ?? 'text';
    if (type == 'number' || type == 'slider') {
      return ParamStat(
        type: type,
        avg: (m['avg'] as num?)?.toDouble(),
        min: (m['min'] as num?)?.toDouble(),
        max: (m['max'] as num?)?.toDouble(),
      );
    } else if (type == 'dropdown') {
      final raw = m['option_counts'];
      final counts = <String, int>{};
      if (raw is Map) {
        for (final e in raw.entries) {
          counts[e.key.toString()] = (e.value as num).toInt();
        }
      }
      return ParamStat(
        type: type,
        optionCounts: counts,
        lastValue: m['last_value'],
      );
    } else if (type == 'dual_text') {
      return ParamStat(
        type: type,
        lastValue: m['last_value'],
        dualLeftStats: m['dual_left_stats'] != null
            ? ParamStat.fromMap(
                Map<String, dynamic>.from(
                  m['dual_left_stats'],
                ),
              )
            : null,
        dualRightStats: m['dual_right_stats'] != null
            ? ParamStat.fromMap(
                Map<String, dynamic>.from(
                  m['dual_right_stats'],
                ),
              )
            : null,
      );
    } else {
      return ParamStat(type: type, lastValue: m['last_value']);
    }
  }

  // ── Incremental update helpers ────────────────────────────────────────────

  /// Returns an updated ParamStat after adding one new numeric value.
  ParamStat withNewNumeric(double newVal, int prevCount) {
    final prevAvg = avg ?? newVal;
    final newCount = prevCount + 1;
    final newAvg = (prevAvg * prevCount + newVal) / newCount;
    final newMin = min == null ? newVal : (newVal < min! ? newVal : min!);
    final newMax = max == null ? newVal : (newVal > max! ? newVal : max!);
    return ParamStat(type: type, avg: newAvg, min: newMin, max: newMax);
  }

  /// Returns an updated ParamStat after adding one new dropdown option.
  ParamStat withNewOption(String option) {
    final updated = Map<String, int>.from(optionCounts);
    updated[option] = (updated[option] ?? 0) + 1;
    return ParamStat(type: type, optionCounts: updated, lastValue: option);
  }

  /// Returns a ParamStat with updated last text value.
  ParamStat withLastValue(dynamic value) =>
      ParamStat(type: type, lastValue: value);
}
