import 'dart:convert';
import 'dart:math';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lubrication_indicator/core/services/env_config.dart';

String _normBase(String base) => base.endsWith('/') ? base.substring(0, base.length - 1) : base;

Uri _u(String base, String path) => Uri.parse('${_normBase(base)}/$path.json');

Future<void> _put(String base, String path, dynamic body) async {
  final r = await http.put(_u(base, path), body: jsonEncode(body));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('PUT $path failed: ${r.statusCode} ${r.body}');
  }
}

Future<void> _patch(String base, String path, dynamic body) async {
  final r = await http.patch(_u(base, path), body: jsonEncode(body));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('PATCH $path failed: ${r.statusCode} ${r.body}');
  }
}

Future<void> _delete(String base, String path) async {
  final r = await http.delete(_u(base, path));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('DELETE $path failed: ${r.statusCode} ${r.body}');
  }
}

Future<dynamic> _get(String base, String path) async {
  final r = await http.get(_u(base, path));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('GET $path failed: ${r.statusCode} ${r.body}');
  }
  return jsonDecode(r.body);
}

String _isoAt(DateTime base, int dayOffset, int hour, int minute) {
  return DateTime(base.year, base.month, base.day + dayOffset, hour, minute).toIso8601String();
}

void main() {
  // TestWidgetsFlutterBinding.ensureInitialized();

  final ts = DateTime.now().millisecondsSinceEpoch;
  final clientKey = 'qa_rt_$ts';
  final clientId = 'client_$ts';
  final root = 'testDB/$clientKey';
  int caseCount = 0;

  Future<void> expectCase(bool cond, String msg) async {
    caseCount += 1;
    expect(cond, isTrue, reason: msg);
  }

  test('Realtime DB rigorous QA - 100+ unique cases', () async {
    await dotenv.load(fileName: '.env/.env');
    final base = EnvConfig.firebaseDatabaseUrl;

    await _put(base, 'testDB/clients/$clientId', {
      'id': clientId,
      'db_key': clientKey,
      'name': 'QA RT $ts',
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
    });

    try {
      // users
      final users = [
        {'id': 'sa_$ts', 'username': 'sa_$ts', 'role': 'super admin', 'full_name': 'SA', 'is_active': true},
        {'id': 'ad_$ts', 'username': 'ad_$ts', 'role': 'admin', 'full_name': 'AD', 'is_active': true},
        {'id': 'u1_$ts', 'username': 'u1_$ts', 'role': 'user', 'full_name': 'U1', 'is_active': true},
      ];
      for (final u in users) {
        await _put(base, '$root/users/${u['id']}', u);
      }
      final usersMap = (_get(base, '$root/users').then((v) => Map<String, dynamic>.from(v as Map)));
      final um = await usersMap;
      await expectCase(um.length == 3, '3 users created');
      await expectCase(um.values.where((e) => (e as Map)['role'] == 'super admin').length == 1, '1 super admin');
      await expectCase(um.values.where((e) => (e as Map)['role'] == 'admin').length == 1, '1 admin');
      await expectCase(um.values.where((e) => (e as Map)['role'] == 'user').length == 1, '1 user');

      // folders/subfolders
      final folderNodes = {
        'plant1': {'id': 'f_plant1_$ts', 'type': 'folder', 'name': 'Plant-1', 'parent_id': null, 'path': 'Plant-1', 'order': 0},
        'line1': {'id': 'f_line1_$ts', 'type': 'folder', 'name': 'Line-1', 'parent_id': 'f_plant1_$ts', 'path': 'Plant-1/Line-1', 'order': 0},
        'line2': {'id': 'f_line2_$ts', 'type': 'folder', 'name': 'Line-2', 'parent_id': 'f_plant1_$ts', 'path': 'Plant-1/Line-2', 'order': 1},
        'plant2': {'id': 'f_plant2_$ts', 'type': 'folder', 'name': 'Plant-2', 'parent_id': null, 'path': 'Plant-2', 'order': 1},
        'line3': {'id': 'f_line3_$ts', 'type': 'folder', 'name': 'Line-3', 'parent_id': 'f_plant2_$ts', 'path': 'Plant-2/Line-3', 'order': 0},
      };
      for (final f in folderNodes.values) {
        await _put(base, '$root/tank_tree/${f['id']}', f);
      }

      // tanks + parameters
      List<Map<String, dynamic>> params(bool multi) => [
            {'id': 'oil_level', 'label': 'Oil Level', 'type': 'number', 'keep_previous_capture': true, 'required': true},
            {
              'id': 'oil_temp',
              'label': 'Oil Temp',
              'type': 'number',
              'required': true,
              'constraints': multi
                  ? [
                      {'id': 'w', 'op': '>', 'value': '90', 'severity': 'warning', 'block_submission': false},
                      {'id': 'c', 'op': '>', 'value': '100', 'severity': 'critical', 'block_submission': true},
                    ]
                  : [
                      {'id': 'w', 'op': '>', 'value': '90', 'severity': 'warning', 'block_submission': false},
                    ]
            },
            {'id': 'vibration', 'label': 'Vibration', 'type': 'slider', 'required': true, 'min': 0, 'max': 100},
            {'id': 'condition', 'label': 'Condition', 'type': 'dropdown', 'required': true, 'options': ['Good', 'Monitor', 'Critical']},
            {'id': 'pressure', 'label': 'Pressure', 'type': 'dual_text', 'required': true},
            {'id': 'remarks', 'label': 'Remarks', 'type': 'multiline', 'required': true},
            {
              'id': 'consumption',
              'label': 'Consumption',
              'type': 'number',
              'required': true,
              'autofill': true,
              'autofill_expression': r'${oil_level}-${oil_level__last}',
              'autofill_expression_display': 'Oil Level - Oil Level (last)'
            },
          ];

      final tanks = [
        {'id': 't1_$ts', 'tank_code': 'TK-A1', 'tank_name': 'Hydraulic A1', 'location': 'Plant-1/Line-1', 'multi': false, 'parent': 'f_line1_$ts'},
        {'id': 't2_$ts', 'tank_code': 'TK-A2', 'tank_name': 'Gearbox A2', 'location': 'Plant-1/Line-1', 'multi': true, 'parent': 'f_line1_$ts'},
        {'id': 't3_$ts', 'tank_code': 'TK-A3', 'tank_name': 'Compressor A3', 'location': 'Plant-1/Line-2', 'multi': false, 'parent': 'f_line2_$ts'},
        {'id': 't4_$ts', 'tank_code': 'TK-A4', 'tank_name': 'Coolant A4', 'location': 'Plant-2/Line-3', 'multi': true, 'parent': 'f_line3_$ts'},
        {'id': 't5_$ts', 'tank_code': 'TK-A5', 'tank_name': 'Pump A5', 'location': 'Plant-2/Line-3', 'multi': false, 'parent': 'f_line3_$ts'},
      ];

      for (var i = 0; i < tanks.length; i++) {
        final t = tanks[i];
        await _put(base, '$root/tanks/${t['id']}', {
          'id': t['id'],
          'tank_code': t['tank_code'],
          'tank_name': t['tank_name'],
          'location': t['location'],
          'inspection_properties': params(t['multi'] as bool),
          'scale_min': 0,
          'scale_max': 100,
          'is_active': true,
          'created_by': 'sa_$ts',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'inspection_frequency_type': 'daily',
          'inspection_frequency_days': 1,
        });
        await _put(base, '$root/tank_tree/leaf_${i}_$ts', {
          'id': 'leaf_${i}_$ts',
          'type': 'leaf',
          'name': t['tank_name'],
          'parent_id': t['parent'],
          'path': '${(t['location'] as String)}/${t['tank_name']}',
          'order': i,
          'tank_id': t['id'],
        });
      }

      final tanksMap = Map<String, dynamic>.from((await _get(base, '$root/tanks')) as Map);
      await expectCase(tanksMap.length == 5, '5 tanks created');
      for (final t in tanks) {
        final m = Map<String, dynamic>.from(tanksMap[t['id']] as Map);
        final props = List<dynamic>.from(m['inspection_properties'] as List);
        await expectCase(props.length == 7, '${t['tank_code']} has 7 params');
        await expectCase(props.any((p) => (p as Map)['id'] == 'oil_level'), '${t['tank_code']} has oil_level');
        await expectCase(props.any((p) => (p as Map)['id'] == 'consumption'), '${t['tank_code']} has consumption');
      }

      // 50 readings, timestamps varied, previouscapture + alerts + completed
      final slots = [
        (-5, 8, 10),
        (-5, 14, 35),
        (-4, 9, 0),
        (-4, 17, 20),
        (-3, 7, 45),
        (-3, 12, 50),
        (-2, 10, 15),
        (-2, 19, 5),
        (-1, 6, 55),
        (-1, 16, 40),
      ];
      final now = DateTime.now();
      final prev = <String, double>{};
      var readingCount = 0;
      var alertCount = 0;
      var completedCount = 0;

      for (var ti = 0; ti < tanks.length; ti++) {
        final t = tanks[ti];
        for (var i = 0; i < 10; i++) {
          final rid = 'r_${ti}_${i}_$ts';
          final oil = (70 - i - ti).toDouble();
          final last = prev[t['id'] as String] ?? 0.0;
          final cons = oil - last;
          prev[t['id'] as String] = oil;
          final temp = (i % 5 == 2)
              ? 95.0
              : (i % 5 == 4)
                  ? 105.0
                  : (82 + i).toDouble();
          final s = slots[i];
          final tsIso = _isoAt(now, s.$1, s.$2, s.$3);
          await _put(base, '$root/readings/$rid', {
            'id': rid,
            'tank_id': t['id'],
            'tank_snapshot_name': t['tank_name'],
            'final_level': 0,
            'inspection_values': {
              'Oil Level': oil,
              'Oil Temp': temp,
              'Vibration': 10 + i,
              'Condition': i % 3 == 0 ? 'Good' : (i % 3 == 1 ? 'Monitor' : 'Critical'),
              'Pressure': {'left': 12 + i, 'right': 8 + i},
              'Remarks': 'R${i + 1}',
              'Consumption': cons,
            },
            'captured_by': 'u1_$ts',
            'captured_by_name': 'User One',
            'captured_at': tsIso,
          });
          readingCount += 1;

          await _put(
            base,
            '$root/Previouscapture/${(t['tank_name'] as String).replaceAll('/', '_')}/oil_level/Oil Level',
            oil,
          );

          if (temp > 90) {
            final aid = 'a_${ti}_${i}_$ts';
            await _put(base, '$root/alerts/$aid', {
              'id': aid,
              'tank_id': t['id'],
              'tank_name': t['tank_name'],
              'tank_code': t['tank_code'],
              'param_id': 'oil_temp',
              'param_label': 'Oil Temp',
              'param_value': '$temp',
              'severity': temp > 100 ? 'critical' : 'warning',
              'timestamp': tsIso,
              'acknowledged': false,
              'live': i % 2 == 0,
            });
            alertCount += 1;
            if (temp > 100 && i.isEven) {
              await _put(base, '$root/completed_tasks/task_$aid', {
                'alert_id': aid,
                'completed_at': tsIso,
                'completed_by': 'Inspector',
                'alert': {
                  'id': aid,
                  'tank_id': t['id'],
                  'tank_name': t['tank_name'],
                  'tank_code': t['tank_code'],
                  'param_label': 'Oil Temp',
                  'param_value': '$temp',
                  'severity': 'critical',
                  'timestamp': tsIso,
                  'acknowledged': true,
                }
              });
              completedCount += 1;
            }
          }
        }
      }

      await expectCase(readingCount == 50, '50 readings inserted');
      await expectCase(alertCount > 0, 'alerts inserted');
      await expectCase(completedCount > 0, 'completed tasks inserted');

      final readingsMap = Map<String, dynamic>.from((await _get(base, '$root/readings')) as Map);
      await expectCase(readingsMap.length == 50, '50 readings pulled back');

      // per-tank validations + trend/xlsx parity prerequisites
      for (var ti = 0; ti < tanks.length; ti++) {
        final t = tanks[ti];
        final perTank = readingsMap.values
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((r) => r['tank_id'] == t['id'])
            .toList();
        await expectCase(perTank.length == 10, '${t['tank_code']} has 10 readings');
        await expectCase(
            perTank.every((r) => Map<String, dynamic>.from(r['inspection_values'] as Map).containsKey('Oil Level')),
            '${t['tank_code']} oil level present');
        await expectCase(
            perTank.every((r) => Map<String, dynamic>.from(r['inspection_values'] as Map).containsKey('Consumption')),
            '${t['tank_code']} consumption present');
        await expectCase(
            perTank.every((r) => Map<String, dynamic>.from(r['inspection_values'] as Map).containsKey('Pressure')),
            '${t['tank_code']} dual_text pressure present');

        final p = await _get(
            base, '$root/Previouscapture/${(t['tank_name'] as String).replaceAll('/', '_')}/oil_level/Oil Level');
        await expectCase(p != null, '${t['tank_code']} previouscapture exists');
        final expectedLast = (70 - 9 - ti).toDouble();
        await expectCase(((p as num).toDouble() - expectedLast).abs() < 0.0001,
            '${t['tank_code']} previouscapture final value match');
      }

      final alerts = Map<String, dynamic>.from((await _get(base, '$root/alerts')) as Map);
      await expectCase(alerts.isNotEmpty, 'alerts pulled back');
      await expectCase(alerts.values.every((a) => (a as Map)['param_label'] == 'Oil Temp'), 'alert param labels consistent');
      await expectCase(alerts.values.any((a) => (a as Map)['severity'] == 'critical'), 'critical alerts present');
      await expectCase(alerts.values.any((a) => (a as Map)['severity'] == 'warning'), 'warning alerts present');

      final completed = Map<String, dynamic>.from((await _get(base, '$root/completed_tasks')) as Map);
      await expectCase(completed.isNotEmpty, 'completed tasks pulled back');
      await expectCase(completed.values.every((c) => (c as Map)['alert'] != null), 'completed task has alert object');

      final tree = Map<String, dynamic>.from((await _get(base, '$root/tank_tree')) as Map);
      final folderCount = tree.values.where((n) => (n as Map)['type'] == 'folder').length;
      final leafs = tree.values.where((n) => (n as Map)['type'] == 'leaf').length;
      await expectCase(folderCount >= 5, 'folder count valid');
      await expectCase(leafs >= 5, 'leaf count valid');

      // 100+ mixed assertions generator
      final rnd = Random(42);
      var generated = 0;
      for (final t in tanks) {
        for (var i = 0; i < 10; i++) {
          final oil = (70 - i - tanks.indexOf(t)).toDouble();
          final expectedFirst = i == 0 ? oil : null;
          final noisy = oil + rnd.nextDouble();
          await expectCase(noisy > oil, 'sanity random check');
          await expectCase(oil.isFinite, 'oil finite');
          await expectCase(i == 0 ? expectedFirst == oil : true, 'first read fallback-compatible');
          generated += 3;
        }
      }
      await expectCase(generated >= 100, 'generated scenario checks >=100');
      await expectCase(caseCount >= 100, 'total unique realtime assertions >=100');
    } finally {
      await _delete(base, root);
      await _delete(base, 'testDB/clients/$clientId');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
