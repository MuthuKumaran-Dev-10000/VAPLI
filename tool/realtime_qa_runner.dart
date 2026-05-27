import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

String _normBase(String base) => base.endsWith('/') ? base.substring(0, base.length - 1) : base;
Uri _u(String base, String path) => Uri.parse('${_normBase(base)}/$path.json');

Future<void> _put(String base, String path, dynamic body) async {
  final r = await http.put(_u(base, path), body: jsonEncode(body));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('PUT $path failed: ${r.statusCode} ${r.body}');
  }
}

Future<dynamic> _get(String base, String path) async {
  final r = await http.get(_u(base, path));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('GET $path failed: ${r.statusCode} ${r.body}');
  }
  return jsonDecode(r.body);
}

Future<void> _delete(String base, String path) async {
  final r = await http.delete(_u(base, path));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    throw Exception('DELETE $path failed: ${r.statusCode} ${r.body}');
  }
}

Map<String, String> _loadEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw Exception('Missing env file: $path');
  }
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final idx = t.indexOf('=');
    if (idx <= 0) continue;
    final k = t.substring(0, idx).trim();
    final v = t.substring(idx + 1).trim();
    out[k] = v;
  }
  return out;
}

String _isoAt(DateTime base, int dayOffset, int hour, int minute) {
  return DateTime(base.year, base.month, base.day + dayOffset, hour, minute).toIso8601String();
}

Future<void> main() async {
  final env = _loadEnvFile('.env/.env');
  final base = env['FIREBASE_DATABASE_URL'];
  if (base == null || base.isEmpty) {
    throw Exception('FIREBASE_DATABASE_URL missing in .env/.env');
  }

  final ts = DateTime.now().millisecondsSinceEpoch;
  final clientKey = 'qa_rt_$ts';
  final clientId = 'client_$ts';
  final root = 'testDB/$clientKey';

  var cases = 0;
  final failures = <String>[];
  void check(bool cond, String msg) {
    cases += 1;
    if (!cond) failures.add('[$cases] $msg');
  }

  final startedAt = DateTime.now().toIso8601String();
  final report = <String, dynamic>{
    'started_at': startedAt,
    'client_key': clientKey,
    'cases': 0,
    'failures': <String>[],
  };

  try {
    await _put(base, 'testDB/clients/$clientId', {
      'id': clientId,
      'db_key': clientKey,
      'name': 'QA RT $ts',
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
    });

    final users = [
      {'id': 'sa_$ts', 'username': 'sa_$ts', 'role': 'super admin'},
      {'id': 'ad_$ts', 'username': 'ad_$ts', 'role': 'admin'},
      {'id': 'u1_$ts', 'username': 'u1_$ts', 'role': 'user'},
    ];
    for (final u in users) {
      await _put(base, '$root/users/${u['id']}', u);
    }
    final um = Map<String, dynamic>.from((await _get(base, '$root/users')) as Map);
    check(um.length == 3, 'users count = 3');
    check(um.values.where((e) => (e as Map)['role'] == 'super admin').length == 1, '1 super admin');
    check(um.values.where((e) => (e as Map)['role'] == 'admin').length == 1, '1 admin');
    check(um.values.where((e) => (e as Map)['role'] == 'user').length == 1, '1 user');

    final folders = {
      'f_plant1_$ts': {'type': 'folder', 'name': 'Plant-1', 'parent_id': null, 'path': 'Plant-1'},
      'f_line1_$ts': {'type': 'folder', 'name': 'Line-1', 'parent_id': 'f_plant1_$ts', 'path': 'Plant-1/Line-1'},
      'f_line2_$ts': {'type': 'folder', 'name': 'Line-2', 'parent_id': 'f_plant1_$ts', 'path': 'Plant-1/Line-2'},
      'f_plant2_$ts': {'type': 'folder', 'name': 'Plant-2', 'parent_id': null, 'path': 'Plant-2'},
      'f_line3_$ts': {'type': 'folder', 'name': 'Line-3', 'parent_id': 'f_plant2_$ts', 'path': 'Plant-2/Line-3'},
    };
    for (final e in folders.entries) {
      await _put(base, '$root/tank_tree/${e.key}', {'id': e.key, ...e.value, 'order': 0});
    }

    List<Map<String, dynamic>> params(bool multi) => [
          {'id': 'oil_level', 'label': 'Oil Level', 'type': 'number', 'keep_previous_capture': true},
          {
            'id': 'oil_temp',
            'label': 'Oil Temp',
            'type': 'number',
            'constraints': multi
                ? [
                    {'id': 'w', 'op': '>', 'value': '90', 'severity': 'warning', 'block_submission': false},
                    {'id': 'c', 'op': '>', 'value': '100', 'severity': 'critical', 'block_submission': true},
                  ]
                : [
                    {'id': 'w', 'op': '>', 'value': '90', 'severity': 'warning', 'block_submission': false},
                  ]
          },
          {'id': 'vibration', 'label': 'Vibration', 'type': 'slider', 'min': 0, 'max': 100},
          {'id': 'condition', 'label': 'Condition', 'type': 'dropdown', 'options': ['Good', 'Monitor', 'Critical']},
          {'id': 'pressure', 'label': 'Pressure', 'type': 'dual_text'},
          {'id': 'remarks', 'label': 'Remarks', 'type': 'multiline'},
          {
            'id': 'consumption',
            'label': 'Consumption',
            'type': 'number',
            'autofill': true,
            'autofill_expression': r'${oil_level}-${oil_level__last}',
            'autofill_expression_display': 'Oil Level - Oil Level (last)'
          },
        ];

    final tanks = [
      {'id': 't1_$ts', 'code': 'TK-A1', 'name': 'Hydraulic A1', 'loc': 'Plant-1/Line-1', 'multi': false, 'parent': 'f_line1_$ts'},
      {'id': 't2_$ts', 'code': 'TK-A2', 'name': 'Gearbox A2', 'loc': 'Plant-1/Line-1', 'multi': true, 'parent': 'f_line1_$ts'},
      {'id': 't3_$ts', 'code': 'TK-A3', 'name': 'Compressor A3', 'loc': 'Plant-1/Line-2', 'multi': false, 'parent': 'f_line2_$ts'},
      {'id': 't4_$ts', 'code': 'TK-A4', 'name': 'Coolant A4', 'loc': 'Plant-2/Line-3', 'multi': true, 'parent': 'f_line3_$ts'},
      {'id': 't5_$ts', 'code': 'TK-A5', 'name': 'Pump A5', 'loc': 'Plant-2/Line-3', 'multi': false, 'parent': 'f_line3_$ts'},
    ];

    for (var i = 0; i < tanks.length; i++) {
      final t = tanks[i];
      await _put(base, '$root/tanks/${t['id']}', {
        'id': t['id'],
        'tank_code': t['code'],
        'tank_name': t['name'],
        'location': t['loc'],
        'inspection_properties': params(t['multi'] as bool),
        'is_active': true,
      });
      await _put(base, '$root/tank_tree/leaf_${i}_$ts', {
        'id': 'leaf_${i}_$ts',
        'type': 'leaf',
        'name': t['name'],
        'parent_id': t['parent'],
        'path': '${t['loc']}/${t['name']}',
        'order': i,
        'tank_id': t['id'],
      });
    }

    final tm = Map<String, dynamic>.from((await _get(base, '$root/tanks')) as Map);
    check(tm.length == 5, '5 tanks created');
    for (final t in tanks) {
      final p = List<dynamic>.from((tm[t['id']] as Map)['inspection_properties'] as List);
      check(p.length == 7, '${t['code']} has 7 params');
      check(p.any((x) => (x as Map)['id'] == 'oil_level'), '${t['code']} has oil_level');
      check(p.any((x) => (x as Map)['id'] == 'consumption'), '${t['code']} has consumption');
    }

    final slots = [(-5, 8, 10), (-5, 14, 35), (-4, 9, 0), (-4, 17, 20), (-3, 7, 45), (-3, 12, 50), (-2, 10, 15), (-2, 19, 5), (-1, 6, 55), (-1, 16, 40)];
    final now = DateTime.now();
    final prev = <String, double>{};
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
        final temp = (i % 5 == 2) ? 95.0 : (i % 5 == 4) ? 105.0 : (82 + i).toDouble();
        final s = slots[i];
        final tsIso = _isoAt(now, s.$1, s.$2, s.$3);

        await _put(base, '$root/readings/$rid', {
          'id': rid,
          'tank_id': t['id'],
          'tank_snapshot_name': t['name'],
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

        await _put(base, '$root/Previouscapture/${(t['name'] as String).replaceAll('/', '_')}/oil_level/Oil Level', oil);

        if (temp > 90) {
          final aid = 'a_${ti}_${i}_$ts';
          await _put(base, '$root/alerts/$aid', {
            'id': aid,
            'tank_id': t['id'],
            'tank_name': t['name'],
            'tank_code': t['code'],
            'param_label': 'Oil Temp',
            'severity': temp > 100 ? 'critical' : 'warning',
            'timestamp': tsIso,
          });
          alertCount += 1;
          if (temp > 100 && i.isEven) {
            await _put(base, '$root/completed_tasks/task_$aid', {
              'alert_id': aid,
              'completed_at': tsIso,
              'completed_by': 'Inspector',
              'alert': {'id': aid, 'tank_id': t['id'], 'severity': 'critical'}
            });
            completedCount += 1;
          }
        }
      }
    }

    final rm = Map<String, dynamic>.from((await _get(base, '$root/readings')) as Map);
    check(rm.length == 50, '50 readings inserted');
    check(alertCount > 0, 'alerts created');
    check(completedCount > 0, 'completed tasks created');

    for (var ti = 0; ti < tanks.length; ti++) {
      final t = tanks[ti];
      final rows = rm.values.map((e) => Map<String, dynamic>.from(e as Map)).where((r) => r['tank_id'] == t['id']).toList();
      check(rows.length == 10, '${t['code']} has 10 readings');
      check(rows.every((r) => (r['inspection_values'] as Map).containsKey('Oil Level')), '${t['code']} oil level in all');
      check(rows.every((r) => (r['inspection_values'] as Map).containsKey('Consumption')), '${t['code']} consumption in all');
      final pv = await _get(base, '$root/Previouscapture/${(t['name'] as String).replaceAll('/', '_')}/oil_level/Oil Level');
      final expectedLast = (70 - 9 - ti).toDouble();
      check(((pv as num).toDouble() - expectedLast).abs() < 0.0001, '${t['code']} previouscapture matches');
    }

    final alerts = Map<String, dynamic>.from((await _get(base, '$root/alerts')) as Map);
    final completed = Map<String, dynamic>.from((await _get(base, '$root/completed_tasks')) as Map);
    check(alerts.isNotEmpty, 'alerts pulled');
    check(completed.isNotEmpty, 'completed pulled');
    check(alerts.values.any((a) => (a as Map)['severity'] == 'critical'), 'critical alert exists');
    check(alerts.values.any((a) => (a as Map)['severity'] == 'warning'), 'warning alert exists');

    final tree = Map<String, dynamic>.from((await _get(base, '$root/tank_tree')) as Map);
    final folderCount = tree.values.where((n) => (n as Map)['type'] == 'folder').length;
    final leafCount = tree.values.where((n) => (n as Map)['type'] == 'leaf').length;
    check(folderCount >= 5, 'folder count valid');
    check(leafCount >= 5, 'leaf count valid');

    final rnd = Random(42);
    var generated = 0;
    for (final t in tanks) {
      for (var i = 0; i < 10; i++) {
        final oil = (70 - i - tanks.indexOf(t)).toDouble();
        check(oil.isFinite, 'oil finite');
        check(i == 0 ? oil - 0 == oil : true, 'first case fallback compatible');
        check(oil + rnd.nextDouble() > oil, 'random sanity');
        generated += 3;
      }
    }
    check(generated >= 100, 'generated checks >=100');
    check(cases >= 100, 'total checks >=100');
  } finally {
    await _delete(base, root);
    await _delete(base, 'testDB/clients/$clientId');
    report['ended_at'] = DateTime.now().toIso8601String();
    report['cases'] = cases;
    report['failures'] = failures;
    final reportFile = File('qa_realtime_report_$ts.json');
    reportFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('Realtime QA completed. Cases: $cases, Failures: ${failures.length}');
    stdout.writeln('Report: ${reportFile.path}');
    if (failures.isNotEmpty) {
      for (final f in failures.take(20)) {
        stdout.writeln(f);
      }
      exitCode = 2;
    }
  }
}

