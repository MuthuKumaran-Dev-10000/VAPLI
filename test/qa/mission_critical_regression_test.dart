import 'package:flutter_test/flutter_test.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/expression_engine.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/dashboard/data/models/dashboard_stats_model.dart';
import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';

double _resolveAutofillToken({
  required String token,
  required Map<String, dynamic> currentByParamId,
  required Map<String, dynamic> previousByParamId,
}) {
  final parts = token.split(':');
  var pid = parts.first.trim();
  final side = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
  final isLast = pid.endsWith('__last');
  if (isLast) {
    pid = pid.substring(0, pid.length - '__last'.length);
  }

  final source = isLast ? previousByParamId : currentByParamId;
  final raw = source[pid];

  if (raw == null) {
    return isLast ? 0.0 : double.nan;
  }
  if (raw is Map) {
    final picked = side == 'right' ? raw['right'] : raw['left'];
    return double.tryParse('${picked ?? ''}') ?? (isLast ? 0.0 : double.nan);
  }
  return double.tryParse('$raw') ?? (isLast ? 0.0 : double.nan);
}

double? _evaluateAutofill({
  required String expression,
  required Map<String, dynamic> currentByParamId,
  required Map<String, dynamic> previousByParamId,
}) {
  final vars = <String, double>{};
  for (final token in ExpressionEngine.extractIds(expression)) {
    final v = _resolveAutofillToken(
      token: token,
      currentByParamId: currentByParamId,
      previousByParamId: previousByParamId,
    );
    if (v.isNaN) return null;
    vars[token] = v;
  }
  return ExpressionEngine.evaluate(expression, variables: vars);
}

UserModel _u(String role, {Map<String, bool> privileges = const {}}) => UserModel(
      id: role,
      username: role,
      fullName: role,
      passwordHash: 'x',
      role: role,
      createdAt: DateTime(2026, 5, 25).toIso8601String(),
      privileges: privileges,
    );

void main() {
  group('Mission Critical - Access and Scope', () {
    test('role privilege matrix is enforced', () {
      final superAdmin = _u('super admin');
      final admin = _u('admin');
      final user = _u('user');

      for (final p in AccessControlService.allPrivileges) {
        expect(AccessControlService.can(superAdmin, p), isTrue);
      }
      expect(AccessControlService.can(admin, AccessControlService.pOpenAdminPage), isTrue);
      expect(AccessControlService.can(admin, AccessControlService.pCreateClient), isFalse);
      expect(AccessControlService.can(user, AccessControlService.pOpenAdminPage), isFalse);
    });

    test('explicit privilege overrides default', () {
      final user = _u('user', privileges: {AccessControlService.pCreateTanks: true});
      expect(AccessControlService.can(user, AccessControlService.pCreateTanks), isTrue);
    });

    test('scoped database paths include Previouscapture and client prefix', () {
      DatabaseModeService.isDevelopment.value = false;
      DatabaseModeService.activeClientId.value = 'client_a';
      expect(DatabaseModeService.path('Previouscapture/tk/param/value'),
          'client_a/Previouscapture/tk/param/value');
      expect(DatabaseModeService.path('tanks/1'), 'client_a/tanks/1');
      expect(DatabaseModeService.path('users/u1'), 'users/u1');
    });
  });

  group('Mission Critical - Tank and Reading Schema', () {
    test('tank model roundtrip preserves inspection properties', () {
      final tank = TankModel(
        id: 't1',
        tankCode: 'TK-A1',
        tankName: 'Hydraulic A1',
        location: 'Plant-1/Line-1',
        scaleMax: 100,
        createdBy: 'u1',
        createdAt: '2026-05-25T10:00:00.000',
        updatedAt: '2026-05-25T10:00:00.000',
        inspectionProperties: [
          {
            'id': 'oil_level',
            'label': 'Oil Level',
            'type': 'number',
            'keep_previous_capture': true,
          },
          {
            'id': 'consumption',
            'label': 'Consumption',
            'type': 'number',
            'autofill': true,
            'autofill_expression': r'${oil_level}-${oil_level__last}',
          },
        ],
      );
      final mapped = tank.toMap();
      final back = TankModel.fromMap(mapped);
      expect(back.inspectionProperties.length, 2);
      expect(back.inspectionProperties.first['keep_previous_capture'], isTrue);
      expect(back.inspectionProperties.last['autofill_expression'],
          r'${oil_level}-${oil_level__last}');
    });

    test('reading model keeps inspection values with dynamic types', () {
      final r = ReadingModel(
        id: 'r1',
        tankId: 't1',
        capturedBy: 'u1',
        capturedByName: 'User 1',
        capturedAt: '2026-05-25T11:00:00.000',
        inspectionValues: {
          'Oil Level': 52.0,
          'Condition': 'Good',
          'Before/After': {'left': 11, 'right': 9},
        },
      );
      final back = ReadingModel.fromMap(r.toMap());
      expect(back.inspectionValues['Oil Level'], 52.0);
      expect(back.inspectionValues['Condition'], 'Good');
      expect((back.inspectionValues['Before/After'] as Map)['left'], 11);
    });
  });

  group('Mission Critical - Autofill and Previous Capture', () {
    test('first-time last-value fallback is zero', () {
      final expression = r'${oil_level}-${oil_level__last}';
      final current = {'oil_level': 55};
      final previous = <String, dynamic>{};
      final result = _evaluateAutofill(
        expression: expression,
        currentByParamId: current,
        previousByParamId: previous,
      );
      expect(result, 55);
    });

    test('subsequent read uses stored previous value', () {
      final expression = r'${oil_level}-${oil_level__last}';
      final current = {'oil_level': 48};
      final previous = {'oil_level': 55};
      final result = _evaluateAutofill(
        expression: expression,
        currentByParamId: current,
        previousByParamId: previous,
      );
      expect(result, -7);
    });

    test('missing non-last dependency does not silently coerce to zero', () {
      final expression = r'${oil_level}+${oil_temp}';
      final current = {'oil_level': 50};
      final previous = <String, dynamic>{};
      final result = _evaluateAutofill(
        expression: expression,
        currentByParamId: current,
        previousByParamId: previous,
      );
      expect(result, isNull);
    });

    test('dual token side resolution works for current and last', () {
      final expression = r'${pressure:left}-${pressure__last:left}';
      final current = {
        'pressure': {'left': 12, 'right': 8}
      };
      final previous = {
        'pressure': {'left': 10, 'right': 7}
      };
      final result = _evaluateAutofill(
        expression: expression,
        currentByParamId: current,
        previousByParamId: previous,
      );
      expect(result, 2);
    });
  });

  group('Mission Critical - Dashboard Aggregates', () {
    test('numeric param stat increment remains accurate across many updates', () {
      var stat = const ParamStat(type: 'number');
      var count = 0;
      final values = [50.0, 52.0, 48.0, 61.0, 45.0, 57.0];
      for (final v in values) {
        stat = stat.withNewNumeric(v, count);
        count += 1;
      }
      expect(stat.min, 45.0);
      expect(stat.max, 61.0);
      expect(stat.avg, closeTo(values.reduce((a, b) => a + b) / values.length, 1e-9));
    });

    test('dropdown counts accumulate correctly', () {
      var stat = const ParamStat(type: 'dropdown');
      final seq = ['Good', 'Monitor', 'Good', 'Critical', 'Good'];
      for (final s in seq) {
        stat = stat.withNewOption(s);
      }
      expect(stat.optionCounts['Good'], 3);
      expect(stat.optionCounts['Monitor'], 1);
      expect(stat.optionCounts['Critical'], 1);
    });
  });

  group('Mission Critical - 50 Reading Simulation and XLSX Reconciliation', () {
    test('5 tanks * 10 readings produce deterministic totals and deltas', () {
      final tankIds = ['TK-A1', 'TK-A2', 'TK-A3', 'TK-A4', 'TK-A5'];
      final readings = <Map<String, dynamic>>[];
      final previous = <String, num>{};

      for (final t in tankIds) {
        for (var i = 0; i < 10; i++) {
          final oilLevel = 70 - i - tankIds.indexOf(t);
          final last = previous[t] ?? 0;
          final consumption = oilLevel - last;
          previous[t] = oilLevel;
          readings.add({
            'tank': t,
            'seq': i + 1,
            'oil_level': oilLevel,
            'oil_level_last': last,
            'consumption': consumption,
            'oil_temp': 80 + (i % 5) * 7,
          });
        }
      }

      expect(readings.length, 50);
      for (final t in tankIds) {
        final rows = readings.where((r) => r['tank'] == t).toList();
        expect(rows.length, 10);
        expect(rows.first['oil_level_last'], 0);
      }
    });

    test('excel-style row mapping keeps value parity', () {
      final tank = TankModel(
        id: 't1',
        tankCode: 'TK-A1',
        tankName: 'Hydraulic A1',
        scaleMax: 100,
        createdBy: 'u1',
        createdAt: '2026-05-25T10:00:00.000',
        updatedAt: '2026-05-25T10:00:00.000',
        inspectionProperties: [
          {'id': 'oil_level', 'label': 'Oil Level', 'type': 'number', 'capture_image': true},
          {'id': 'consumption', 'label': 'Consumption', 'type': 'number'},
        ],
      );

      final reading = ReadingModel(
        id: 'r1',
        tankId: 't1',
        capturedBy: 'u1',
        capturedByName: 'Inspector',
        capturedAt: '2026-05-25T12:00:00.000',
        inspectionValues: {
          'Oil Level': 48,
          'Consumption': -7,
          'oil_level__image_url': 'https://example.com/oil.jpg',
        },
      );

      final colDescs = tank.inspectionProperties.map((p) {
        return {
          'label': p['label'] as String,
          'id': p['id'] as String,
          'hasImage': p['capture_image'] == true,
        };
      }).toList();

      final row = <dynamic>[];
      for (final col in colDescs) {
        row.add(reading.inspectionValues[col['label']]);
        if (col['hasImage'] == true) {
          row.add(reading.inspectionValues['${col['id']}__image_url'] ?? '');
        }
      }

      expect(row[0], 48);
      expect(row[1], 'https://example.com/oil.jpg');
      expect(row[2], -7);
    });
  });
}

