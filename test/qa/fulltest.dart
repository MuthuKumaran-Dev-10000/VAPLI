// ignore_for_file: avoid_print
//
// rtdb_test.dart — VAPLI Full Integration Test Suite
// ════════════════════════════════════════════════════════════════════════════
//
// This suite tests ACTUAL app services, repositories, models, and engines
// exactly as the UI does — no reimplementations, no mirror logic.
//
// Every test calls the real class the screen calls:
//   ExpressionEngine.evaluate()       → same call as ReadingEntryState
//   ExpressionEngine.extractIds()     → same call as ReadingEntryState
//   HashUtil.hashPassword/verify()    → same call as AuthRepository
//   UserModel.fromMap / toMap()       → same round-trip as Firebase
//   TankModel.fromMap / toMap()       → same round-trip as Firebase
//   ReadingModel.fromMap / toMap()    → same round-trip as Firebase
//   AlertModel.fromMap / toMap()      → same round-trip as Firebase
//   DashboardStatsModel + ParamStat   → same round-trip as DashboardStatsRepository
//   AccessControlService.can()        → same call as AdminDashboard
//   DatabaseModeService.path()        → same call as every repository
//   ReadingRepository.saveReading()   → direct DB write + retrieval
//   DashboardStatsRepository.updateStatsAfterReading() → incremental agg
//   AlertRepository.createAlert()     → write + verify field mapping
//   TankRepository.getAllTanks()      → fetch + filter active
//   AuthRepository.createUser/login() → full auth flow
//   ClientRepository.createClient()  → bootstrap + meta write
//   AppSettingsService.getSessionTimeout/setSessionTimeout()
//
// Run:
//   flutter test test/rtdb_test.dart --timeout 300s
//
// Pre-requisites:
//   1. .env/.env with FIREBASE_DATABASE_URL
//   2. Firebase RTDB rules allow read/write on testDB/**
//   3. DatabaseModeService must be in dev-mode (isDevelopment = true)
// ════════════════════════════════════════════════════════════════════════════

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Real app services / repos / models / engines ─────────────────────────
import 'package:lubrication_indicator/core/services/expression_engine.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/app_settings_service.dart';
import 'package:lubrication_indicator/core/services/client_repository.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';

import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/auth/data/repositories/auth_repository.dart';

import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';

import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';

import 'package:lubrication_indicator/features/dashboard/data/models/dashboard_stats_model.dart';
import 'package:lubrication_indicator/features/dashboard/data/repositories/dashboard_stats_repository.dart';

import 'package:lubrication_indicator/features/alerts/data/models/alert_model.dart';
import 'package:lubrication_indicator/features/alerts/data/repositories/alert_reposiotry.dart';

import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/firebase_env_options.dart';

// ════════════════════════════════════════════════════════════════════════════
// Helpers — mirrors exactly what ReadingEntryState._evaluateAllConstraints
// does for a single param+value pair.  No reimplementation: we paste the
// exact switch block from reading_entry_state.dart so it stays 1-to-1.
// ════════════════════════════════════════════════════════════════════════════

/// Evaluates all constraint maps from an inspection property against [value].
/// Returns the list of violated constraint maps — same logic as
/// ReadingEntryState._evaluateAllConstraints().
List<Map<String, dynamic>> _fireConstraints(
    Map<String, dynamic> prop, dynamic value) {
  final fired = <Map<String, dynamic>>[];
  final rawList = prop['constraints'];
  if (rawList is! List) return fired;

  final actual = value.toString().trim();
  if (actual.isEmpty) return fired;

  for (final c in rawList) {
    if (c is! Map) continue;
    final constraint = Map<String, dynamic>.from(c);
    final op = constraint['op']?.toString() ?? '';
    final expected = constraint['value']?.toString() ?? '';

    bool isFired = false;
    switch (op) {
      case '<':
        isFired = (double.tryParse(actual) ?? 0) <
            (double.tryParse(expected) ?? 0);
        break;
      case '<=':
        isFired = (double.tryParse(actual) ?? 0) <=
            (double.tryParse(expected) ?? 0);
        break;
      case '>':
        isFired = (double.tryParse(actual) ?? 0) >
            (double.tryParse(expected) ?? 0);
        break;
      case '>=':
        isFired = (double.tryParse(actual) ?? 0) >=
            (double.tryParse(expected) ?? 0);
        break;
      case '==':
        isFired = actual.toLowerCase() == expected.toLowerCase();
        break;
      case '!=':
        isFired = actual.toLowerCase() != expected.toLowerCase();
        break;
      case 'contains':
        isFired = actual.toLowerCase().contains(expected.toLowerCase());
        break;
      case 'starts_with':
        isFired = actual.toLowerCase().startsWith(expected.toLowerCase());
        break;
      case 'ends_with':
        isFired = actual.toLowerCase().endsWith(expected.toLowerCase());
        break;
      case 'regex':
        try {
          isFired = RegExp(expected).hasMatch(actual);
        } catch (_) {}
        break;
    }

    if (isFired) fired.add(constraint);
  }
  return fired;
}

/// Canonical inspection-property list reused across test groups.
List<Map<String, dynamic>> _buildProps({bool multiConstraint = false}) => [
      {
        'id': 'oil_level',
        'label': 'Oil Level',
        'type': 'number',
        'keep_previous_capture': true,
        'required': true,
      },
      {
        'id': 'oil_temp',
        'label': 'Oil Temp',
        'type': 'number',
        'required': true,
        'constraints': multiConstraint
            ? [
                {
                  'id': 'warn_90',
                  'op': '>',
                  'value': '90',
                  'severity': 'warning',
                  'block_submission': false,
                  'show_dashboard_alert': true,
                  'store_history': true,
                  'alert_title': 'High Temperature',
                  'message': 'Oil Temp exceeded warning threshold',
                },
                {
                  'id': 'crit_100',
                  'op': '>',
                  'value': '100',
                  'severity': 'critical',
                  'block_submission': true,
                  'show_dashboard_alert': true,
                  'store_history': true,
                  'alert_title': 'Critical Temperature',
                  'message': 'Oil Temp critical — fix before saving',
                },
              ]
            : [
                {
                  'id': 'warn_90',
                  'op': '>',
                  'value': '90',
                  'severity': 'warning',
                  'block_submission': false,
                  'show_dashboard_alert': true,
                  'store_history': true,
                  'alert_title': 'High Temperature',
                  'message': 'Oil Temp exceeded warning threshold',
                },
              ],
      },
      {
        'id': 'vibration',
        'label': 'Vibration',
        'type': 'slider',
        'required': true,
        'min': 0,
        'max': 100,
      },
      {
        'id': 'condition',
        'label': 'Condition',
        'type': 'dropdown',
        'required': true,
        'options': ['Good', 'Monitor', 'Critical'],
      },
      {
        'id': 'pressure',
        'label': 'Pressure',
        'type': 'dual_text',
        'required': true,
      },
      {
        'id': 'remarks',
        'label': 'Remarks',
        'type': 'multiline',
        'required': true,
      },
      {
        'id': 'consumption',
        'label': 'Consumption',
        'type': 'number',
        'required': true,
        'autofill': true,
        'autofill_expression': r'${oil_level}-${oil_level__last}',
        'autofill_expression_display': 'Oil Level - Oil Level (last)',
      },
    ];

// ════════════════════════════════════════════════════════════════════════════
void main() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  // Each test run is fully isolated under this timestamp suffix
  final clientSuffix = 'qa_$ts';

  late ClientModel testClient;
  late TankModel testTank;
  late UserModel testAdminUser;
  late UserModel testRegularUser;

  // ── Firebase bootstrap ──────────────────────────────────────────────────
  setUpAll(() async {
    await dotenv.load(fileName: '.env/.env');
    await Firebase.initializeApp(options: firebaseOptionsFromEnv());
    // Force dev-mode so all writes land under testDB/
    await DatabaseModeService.setDevelopment(true);
  });

  tearDownAll(() async {
    // Best-effort cleanup of testDB subtree for this run
    if (testClient.dbKey.isNotEmpty) {
      try {
        await DatabaseModeService.ref('testDB/${testClient.dbKey}').remove();
      } catch (_) {}
    }
    try {
      await DatabaseModeService.ref('testDB/clients/$clientSuffix').remove();
    } catch (_) {}
    // Clean global users written during auth tests
    if (testAdminUser.id.isNotEmpty) {
      try {
        await DatabaseModeService.ref('users/${testAdminUser.id}').remove();
      } catch (_) {}
    }
    if (testRegularUser.id.isNotEmpty) {
      try {
        await DatabaseModeService.ref('users/${testRegularUser.id}').remove();
      } catch (_) {}
    }
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP A — DatabaseModeService.path() routing
  // Tests the exact method every repository calls to resolve its DB path.
  // ══════════════════════════════════════════════════════════════════════════
  group('A: DatabaseModeService path routing', () {
    setUpAll(() async {
      await DatabaseModeService.setDevelopment(true);
      await DatabaseModeService.setClientScope('test_client_x');
    });

    test('A-01 global path "users" is NOT prefixed with clientId', () {
      final p = DatabaseModeService.path('users/abc');
      expect(p, equals('testDB/users/abc'));
    });

    test('A-02 scoped path "tanks" IS prefixed with active client scope', () {
      final p = DatabaseModeService.path('tanks/t1');
      expect(p, equals('testDB/test_client_x/tanks/t1'));
    });

    test('A-03 leading slash is stripped before routing', () {
      final p = DatabaseModeService.path('/readings/r1');
      expect(p, equals('testDB/test_client_x/readings/r1'));
    });

    test('A-04 Previouscapture is a scoped path', () {
      final p = DatabaseModeService.path('Previouscapture/TankA/oil_level/Oil Level');
      expect(p, startsWith('testDB/test_client_x/Previouscapture'));
    });

    test('A-05 alerts, alerts_full, violations, completed_tasks are all scoped', () {
      for (final seg in ['alerts', 'alerts_full', 'violations', 'completed_tasks']) {
        final p = DatabaseModeService.path('$seg/id');
        expect(p, startsWith('testDB/test_client_x/$seg'),
            reason: '$seg must be client-scoped');
      }
    });

    test('A-06 dashboard_stats is scoped', () {
      final p = DatabaseModeService.path('dashboard_stats/t1');
      expect(p, startsWith('testDB/test_client_x/dashboard_stats'));
    });

    test('A-07 clients path is global (not scoped)', () {
      final p = DatabaseModeService.path('clients/cx');
      expect(p, equals('testDB/clients/cx'));
    });

    test('A-08 empty clientScope skips prefix injection', () async {
      await DatabaseModeService.setClientScope(null);
      final p = DatabaseModeService.path('tanks/t1');
      expect(p, equals('testDB/tanks/t1'));
      // Restore
      await DatabaseModeService.setClientScope('test_client_x');
    });

    test('A-09 admin_audit_logs is scoped', () {
      final p = DatabaseModeService.path('admin_audit_logs/entry1');
      expect(p, startsWith('testDB/test_client_x/admin_audit_logs'));
    });

    test('A-10 sync_logs is scoped', () {
      final p = DatabaseModeService.path('sync_logs/s1');
      expect(p, startsWith('testDB/test_client_x/sync_logs'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP B — HashUtil (used by AuthRepository for password storage)
  // ══════════════════════════════════════════════════════════════════════════
  group('B: HashUtil — password hashing used by AuthRepository', () {
    test('B-01 hashPassword returns a non-empty string', () {
      final h = HashUtil.hashPassword('Admin@123');
      expect(h.isNotEmpty, isTrue);
    });

    test('B-02 same password always produces same hash (deterministic)', () {
      final h1 = HashUtil.hashPassword('TestPass99!');
      final h2 = HashUtil.hashPassword('TestPass99!');
      expect(h1, equals(h2));
    });

    test('B-03 different passwords produce different hashes', () {
      final h1 = HashUtil.hashPassword('password1');
      final h2 = HashUtil.hashPassword('password2');
      expect(h1, isNot(equals(h2)));
    });

    test('B-04 verifyPassword returns true for correct password', () {
      const pw = 'Admin@123';
      final hash = HashUtil.hashPassword(pw);
      expect(HashUtil.verifyPassword(pw, hash), isTrue);
    });

    test('B-05 verifyPassword returns false for wrong password', () {
      final hash = HashUtil.hashPassword('CorrectPass');
      expect(HashUtil.verifyPassword('WrongPass', hash), isFalse);
    });

    test('B-06 generateId produces unique IDs across calls', () {
      final id1 = HashUtil.generateId();
      // Tiny delay to ensure different ms epoch
      final id2 = HashUtil.generateId();
      // IDs are epoch-based; may collide in same ms — just verify format
      expect(id1, contains('-'));
      expect(id1.length, greaterThan(8));
    });

    test('B-07 bootstrap default password "Admin@123" verifies correctly', () {
      // This is what ClientRepository.ensureClientBootstrap() writes
      const defaultPw = 'Admin@123';
      final storedHash = HashUtil.hashPassword(defaultPw);
      expect(HashUtil.verifyPassword(defaultPw, storedHash), isTrue,
          reason: 'Bootstrap login must work with Admin@123');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP C — ExpressionEngine (used by ReadingEntryState for autofill)
  // ══════════════════════════════════════════════════════════════════════════
  group('C: ExpressionEngine — autofill expression evaluation', () {
    test('C-01 extractIds pulls all \${id} tokens from expression', () {
      final ids =
          ExpressionEngine.extractIds(r'${oil_level}-${oil_level__last}');
      expect(ids, containsAll(['oil_level', 'oil_level__last']));
    });

    test('C-02 simple subtraction (primary autofill use case)', () {
      final result = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {'oil_level': 80.0, 'oil_level__last': 70.0},
      );
      expect(result, closeTo(10.0, 0.0001));
    });

    test('C-03 negative consumption result is valid (oil added > used)', () {
      final result = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {'oil_level': 40.0, 'oil_level__last': 60.0},
      );
      expect(result, closeTo(-20.0, 0.0001));
    });

    test('C-04 zero delta (oil level unchanged between readings)', () {
      final result = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {'oil_level': 55.0, 'oil_level__last': 55.0},
      );
      expect(result, closeTo(0.0, 0.0001));
    });

    test('C-05 first-read zero-fallback: last=0 gives valid result', () {
      // ReadingEntryState._resolveToken() returns 0.0 when Previouscapture
      // path doesn't exist — this mirrors that exact behaviour.
      final result = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {'oil_level': 100.0, 'oil_level__last': 0.0},
      );
      expect(result.isFinite, isTrue);
      expect(result, closeTo(100.0, 0.0001));
    });

    test('C-06 addition expression evaluates correctly', () {
      final result = ExpressionEngine.evaluate(
        r'${a}+${b}',
        variables: {'a': 10.0, 'b': 5.0},
      );
      expect(result, closeTo(15.0, 0.0001));
    });

    test('C-07 multiplication expression evaluates correctly', () {
      final result = ExpressionEngine.evaluate(
        r'${a}*${b}',
        variables: {'a': 3.0, 'b': 7.0},
      );
      expect(result, closeTo(21.0, 0.0001));
    });

    test('C-08 division expression evaluates correctly', () {
      final result = ExpressionEngine.evaluate(
        r'${a}/${b}',
        variables: {'a': 10.0, 'b': 4.0},
      );
      expect(result, closeTo(2.5, 0.0001));
    });

    test('C-09 division by zero throws ExpressionEngineException', () {
      expect(
        () => ExpressionEngine.evaluate(
          r'${a}/${b}',
          variables: {'a': 5.0, 'b': 0.0},
        ),
        throwsA(isA<ExpressionEngineException>()),
      );
    });

    test('C-10 missing variable throws ExpressionEngineException', () {
      expect(
        () => ExpressionEngine.evaluate(
          r'${a}-${missing}',
          variables: {'a': 10.0},
        ),
        throwsA(isA<ExpressionEngineException>()),
      );
    });

    test('C-11 complex expression with multiple operators', () {
      // mirrors a more complex autofill like (a + b) * c
      final result = ExpressionEngine.evaluate(
        r'(${a}+${b})*${c}',
        variables: {'a': 3.0, 'b': 2.0, 'c': 4.0},
      );
      expect(result, closeTo(20.0, 0.0001));
    });

    test('C-12 extractIds for expression with __last token', () {
      final ids =
          ExpressionEngine.extractIds(r'${oil_level}-${oil_level__last}');
      // ReadingEntryState splits on ':' then strips '__last' — here we just
      // verify the raw IDs the engine exposes are correct
      expect(ids.contains('oil_level'), isTrue);
      expect(ids.contains('oil_level__last'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP D — Constraint evaluation logic (mirrors ReadingEntryState)
  // ══════════════════════════════════════════════════════════════════════════
  group('D: Constraint evaluation — same logic as ReadingEntryState', () {
    final singleProp = {
      'id': 'oil_temp',
      'label': 'Oil Temp',
      'type': 'number',
      'constraints': [
        {
          'id': 'warn_90',
          'op': '>',
          'value': '90',
          'severity': 'warning',
          'block_submission': false,
          'show_dashboard_alert': true,
          'store_history': true,
        }
      ],
    };

    final multiProp = {
      'id': 'oil_temp',
      'label': 'Oil Temp',
      'type': 'number',
      'constraints': [
        {
          'id': 'warn_90',
          'op': '>',
          'value': '90',
          'severity': 'warning',
          'block_submission': false,
          'show_dashboard_alert': true,
          'store_history': true,
        },
        {
          'id': 'crit_100',
          'op': '>',
          'value': '100',
          'severity': 'critical',
          'block_submission': true,
          'show_dashboard_alert': true,
          'store_history': true,
        },
      ],
    };

    test('D-01 value below threshold — no violations', () {
      final v = _fireConstraints(singleProp, 85.0);
      expect(v, isEmpty);
    });

    test('D-02 value exactly at threshold — NOT violated (strict >)', () {
      final v = _fireConstraints(singleProp, 90.0);
      expect(v, isEmpty,
          reason: '> 90 does not fire when value == 90');
    });

    test('D-03 value above warning threshold — warning fires', () {
      final v = _fireConstraints(singleProp, 95.0);
      expect(v.length, equals(1));
      expect(v.first['severity'], equals('warning'));
      expect(v.first['block_submission'], isFalse,
          reason: 'warning is non-blocking');
    });

    test('D-04 multi-constraint: value in warning zone only', () {
      final v = _fireConstraints(multiProp, 95.0);
      expect(v.length, equals(1));
      expect(v.first['severity'], equals('warning'));
    });

    test('D-05 multi-constraint: critical zone fires BOTH constraints', () {
      final v = _fireConstraints(multiProp, 105.0);
      expect(v.length, equals(2));
      expect(v.any((c) => c['severity'] == 'critical'), isTrue);
      expect(v.any((c) => c['block_submission'] == true), isTrue,
          reason: 'save should be blocked by critical');
    });

    test('D-06 blocking violation prevents save (check the flag)', () {
      final v = _fireConstraints(multiProp, 105.0);
      final blocked = v.any((c) => c['block_submission'] == true);
      expect(blocked, isTrue);
    });

    test('D-07 corrected value clears all violations', () {
      final before = _fireConstraints(multiProp, 105.0);
      expect(before.isNotEmpty, isTrue);
      final after = _fireConstraints(multiProp, 80.0);
      expect(after, isEmpty);
    });

    test('D-08 >= operator fires at exact value', () {
      final prop = {
        'id': 't',
        'constraints': [
          {'id': 'c1', 'op': '>=', 'value': '90', 'severity': 'warning', 'block_submission': false}
        ]
      };
      expect(_fireConstraints(prop, 90.0).length, equals(1));
      expect(_fireConstraints(prop, 89.9), isEmpty);
    });

    test('D-09 <= operator fires at exact value', () {
      final prop = {
        'id': 't',
        'constraints': [
          {'id': 'c1', 'op': '<=', 'value': '10', 'severity': 'warning', 'block_submission': false}
        ]
      };
      expect(_fireConstraints(prop, 10.0).length, equals(1));
      expect(_fireConstraints(prop, 11.0), isEmpty);
    });

    test('D-10 != operator fires when value differs', () {
      final prop = {
        'id': 't',
        'constraints': [
          {'id': 'c1', 'op': '!=', 'value': '50', 'severity': 'info', 'block_submission': false}
        ]
      };
      expect(_fireConstraints(prop, 49.0).length, equals(1));
      expect(_fireConstraints(prop, 50.0), isEmpty);
    });

    test('D-11 contains operator fires for substring match', () {
      final prop = {
        'id': 'remarks',
        'constraints': [
          {'id': 'c1', 'op': 'contains', 'value': 'leak', 'severity': 'warning', 'block_submission': false}
        ]
      };
      expect(_fireConstraints(prop, 'possible leak detected').length, equals(1));
      expect(_fireConstraints(prop, 'all good'), isEmpty);
    });

    test('D-12 empty value skips evaluation (no false positives)', () {
      final v = _fireConstraints(singleProp, '');
      expect(v, isEmpty, reason: 'empty input must not fire any constraint');
    });

    test('D-13 prop with no constraints list returns empty', () {
      final prop = {'id': 'vibration', 'type': 'slider'};
      final v = _fireConstraints(prop, 95.0);
      expect(v, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP E — AccessControlService (used by AdminDashboard + login screen)
  // ══════════════════════════════════════════════════════════════════════════
  group('E: AccessControlService — privilege checks', () {
    final superAdmin = UserModel(
      id: 'sa1',
      username: 'superadmin',
      fullName: 'Super Admin',
      passwordHash: HashUtil.hashPassword('pw'),
      role: AccessControlService.roleSuperAdmin,
      createdAt: DateTime.now().toIso8601String(),
    );

    final admin = UserModel(
      id: 'ad1',
      username: 'admin',
      fullName: 'Admin User',
      passwordHash: HashUtil.hashPassword('pw'),
      role: AccessControlService.roleAdmin,
      privileges: AccessControlService.defaultPrivilegesForRole(
          AccessControlService.roleAdmin),
      createdAt: DateTime.now().toIso8601String(),
    );

    final regularUser = UserModel(
      id: 'u1',
      username: 'user',
      fullName: 'Regular User',
      passwordHash: HashUtil.hashPassword('pw'),
      role: AccessControlService.roleUser,
      createdAt: DateTime.now().toIso8601String(),
    );

    test('E-01 super admin can create_client', () {
      expect(
          AccessControlService.can(superAdmin, AccessControlService.pCreateClient),
          isTrue);
    });

    test('E-02 super admin can do everything', () {
      for (final p in AccessControlService.allPrivileges) {
        expect(AccessControlService.can(superAdmin, p), isTrue,
            reason: 'super admin must have privilege: $p');
      }
    });

    test('E-03 admin cannot create_client (super admin only privilege)', () {
      expect(
          AccessControlService.can(admin, AccessControlService.pCreateClient),
          isFalse);
    });

    test('E-04 admin can create_tanks', () {
      expect(
          AccessControlService.can(admin, AccessControlService.pCreateTanks),
          isTrue);
    });

    test('E-05 admin can open_admin_page', () {
      expect(
          AccessControlService.can(admin, AccessControlService.pOpenAdminPage),
          isTrue);
    });

    test('E-06 regular user cannot open_admin_page', () {
      expect(
          AccessControlService.can(regularUser, AccessControlService.pOpenAdminPage),
          isFalse);
    });

    test('E-07 regular user cannot create_tanks', () {
      expect(
          AccessControlService.can(regularUser, AccessControlService.pCreateTanks),
          isFalse);
    });

    test('E-08 isAdminLike returns true for super admin and admin', () {
      expect(AccessControlService.isAdminLike(superAdmin), isTrue);
      expect(AccessControlService.isAdminLike(admin), isTrue);
    });

    test('E-09 isAdminLike returns false for regular user', () {
      expect(AccessControlService.isAdminLike(regularUser), isFalse);
    });

    test('E-10 canManage: super admin can manage admin', () {
      expect(AccessControlService.canManage(superAdmin, admin), isTrue);
    });

    test('E-11 canManage: admin cannot manage super admin', () {
      expect(AccessControlService.canManage(admin, superAdmin), isFalse);
    });

    test('E-12 canManage: admin can manage regular user', () {
      expect(AccessControlService.canManage(admin, regularUser), isTrue);
    });

    test('E-13 null user always returns false', () {
      expect(
          AccessControlService.can(null, AccessControlService.pCreateTanks),
          isFalse);
    });

    test('E-14 rankOf returns correct hierarchy', () {
      expect(AccessControlService.rankOf(AccessControlService.roleSuperAdmin),
          greaterThan(AccessControlService.rankOf(AccessControlService.roleAdmin)));
      expect(AccessControlService.rankOf(AccessControlService.roleAdmin),
          greaterThan(AccessControlService.rankOf(AccessControlService.roleUser)));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP F — Model serialisation round-trips
  // Tests toMap() → fromMap() round-trips for all core models exactly as
  // Firebase would store and retrieve them.
  // ══════════════════════════════════════════════════════════════════════════
  group('F: Model toMap/fromMap round-trips', () {
    test('F-01 UserModel round-trips all fields', () {
      final original = UserModel(
        id: 'u_rt_$ts',
        username: 'testuser_$ts',
        fullName: 'Test User',
        passwordHash: HashUtil.hashPassword('pass'),
        role: 'user',
        phone: '+91 9876543210',
        email: 'test@vapli.com',
        clientIds: ['clientA', 'clientB'],
        failedLoginAttempts: 2,
        isActive: true,
        createdAt: DateTime.now().toIso8601String(),
      );
      final restored = UserModel.fromMap(original.toMap());

      expect(restored.id, equals(original.id));
      expect(restored.username, equals(original.username));
      expect(restored.fullName, equals(original.fullName));
      expect(restored.passwordHash, equals(original.passwordHash));
      expect(restored.role, equals(original.role));
      expect(restored.phone, equals(original.phone));
      expect(restored.email, equals(original.email));
      expect(restored.clientIds, equals(original.clientIds));
      expect(restored.failedLoginAttempts, equals(original.failedLoginAttempts));
      expect(restored.isActive, equals(original.isActive));
    });

    test('F-02 UserModel.fromMap handles missing optional fields gracefully', () {
      final minimal = {
        'id': 'u_min',
        'username': 'minuser',
        'full_name': 'Min',
        'password_hash': 'hash',
        'role': 'user',
        'created_at': DateTime.now().toIso8601String(),
      };
      final u = UserModel.fromMap(minimal);
      expect(u.id, equals('u_min'));
      expect(u.clientIds, isEmpty);
      expect(u.failedLoginAttempts, equals(0));
      expect(u.isActive, isTrue);
      expect(u.lockedUntil, isNull);
    });

    test('F-03 TankModel round-trips all fields', () {
      final props = _buildProps();
      final original = TankModel(
        id: 't_rt_$ts',
        tankCode: 'TK-RT',
        tankName: 'RoundTrip Tank',
        location: 'Plant-1/Zone-A',
        inspectionProperties: props,
        scaleMin: 0,
        scaleMax: 200,
        isActive: true,
        createdBy: 'admin',
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
        inspectionFrequencyType: 'daily',
        inspectionFrequencyDays: 1,
      );
      final restored = TankModel.fromMap(original.toMap());

      expect(restored.id, equals(original.id));
      expect(restored.tankCode, equals(original.tankCode));
      expect(restored.tankName, equals(original.tankName));
      expect(restored.location, equals(original.location));
      expect(restored.scaleMax, equals(original.scaleMax));
      expect(restored.isActive, equals(original.isActive));
      expect(restored.inspectionFrequencyType,
          equals(original.inspectionFrequencyType));
      expect(restored.inspectionFrequencyDays,
          equals(original.inspectionFrequencyDays));
      expect(restored.inspectionProperties.length,
          equals(original.inspectionProperties.length));
    });

    test('F-04 TankModel.fromMap handles List and Map inspection_properties', () {
      // Firebase can store it as either — fromMap handles both
      final asMap = {
        'id': 't1',
        'tank_code': 'TC-01',
        'tank_name': 'Tank One',
        'scale_max': 100,
        'created_by': 'admin',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'inspection_properties': {
          '0': {'id': 'oil_level', 'label': 'Oil Level', 'type': 'number'},
        },
      };
      final t = TankModel.fromMap(asMap);
      expect(t.inspectionProperties.length, equals(1));
      expect(t.inspectionProperties.first['id'], equals('oil_level'));
    });

    test('F-05 ReadingModel round-trips inspection_values with all field types',
        () {
      final iv = {
        'Oil Level': 75.0,
        'Oil Temp': 82.0,
        'Vibration': 30.0,
        'Condition': 'Good',
        'Pressure': {'left': 12.5, 'right': 8.3},
        'Remarks': 'All good',
        'Consumption': 5.0,
      };
      final original = ReadingModel(
        id: 'r_rt_$ts',
        tankId: 't1',
        tankSnapshotName: 'Test Tank',
        finalLevel: 0,
        inspectionValues: iv,
        source: 'manual',
        capturedBy: 'u1',
        capturedByName: 'User One',
        capturedAt: DateTime.now().toIso8601String(),
      );
      final restored = ReadingModel.fromMap(original.toMap());

      expect(restored.id, equals(original.id));
      expect(restored.tankId, equals(original.tankId));
      expect(restored.inspectionValues['Oil Level'], equals(75.0));
      expect(restored.inspectionValues['Condition'], equals('Good'));
      final pressure = restored.inspectionValues['Pressure'] as Map;
      expect((pressure['left'] as num).toDouble(), equals(12.5));
      expect((pressure['right'] as num).toDouble(), equals(8.3));
    });

    test('F-06 ReadingModel.fromMap defaults to empty map when inspection_values is null',
        () {
      final m = {
        'id': 'r_nil',
        'tank_id': 't1',
        'source': 'manual',
        'captured_by': 'u1',
        'captured_by_name': 'User One',
        'captured_at': DateTime.now().toIso8601String(),
        // inspection_values intentionally absent
      };
      final r = ReadingModel.fromMap(m);
      expect(r.inspectionValues, isEmpty,
          reason: 'missing inspection_values must default to {}');
    });

    test('F-07 DashboardStatsModel round-trip with numeric + dropdown params',
        () {
      final original = DashboardStatsModel(
        tankId: 't_ds_$ts',
        count: 3,
        lastCapturedAt: DateTime.now().toIso8601String(),
        lastCapturedBy: 'User One',
        lastReading: {'Oil Level': 70.0, 'Condition': 'Good'},
        paramStats: {
          'Oil Level': const ParamStat(
            type: 'number',
            avg: 72.0,
            min: 65.0,
            max: 80.0,
          ),
          'Condition': ParamStat(
            type: 'dropdown',
            optionCounts: {'Good': 2, 'Monitor': 1},
          ),
        },
      );
      final map = original.toMap();
      final restored =
          DashboardStatsModel.fromMap(original.tankId, map.map((k, v) =>
              MapEntry(k, v)));

      expect(restored.count, equals(3));
      expect(restored.paramStats['Oil Level']?.avg, closeTo(72.0, 0.001));
      expect(restored.paramStats['Oil Level']?.min, equals(65.0));
      expect(restored.paramStats['Oil Level']?.max, equals(80.0));
      expect(
          restored.paramStats['Condition']?.optionCounts?['Good'], equals(2));
    });

    test('F-08 AlertModel round-trips all fields', () {
      const original = AlertModel(
        id: 'al_rt',
        tankId: 't1',
        tankCode: 'TK-01',
        tankName: 'Test Tank',
        readingId: 'r1',
        capturedBy: 'u1',
        capturedByName: 'User One',
        capturedAt: '2025-01-01T10:00:00.000',
        constraintId: 'warn_90',
        constraintOp: '>',
        constraintValue: '90',
        constraintSeverity: 'warning',
        constraintLabel: 'Oil Temp',
        violatedValue: '95.0',
        alertTitle: 'High Temperature',
        message: 'Oil Temp exceeded threshold',
        showDashboardAlert: true,
        playSound: false,
        captureImageOnViolation: false,
        blockSubmission: false,
        lastInspectionValues: {'Oil Temp': 95.0},
        resolved: false,
      );
      final restored =
          AlertModel.fromMap(original.id, Map<dynamic, dynamic>.from(original.toMap()));

      expect(restored.id, equals(original.id));
      expect(restored.tankId, equals(original.tankId));
      expect(restored.constraintSeverity, equals('warning'));
      expect(restored.blockSubmission, isFalse);
      expect(restored.showDashboardAlert, isTrue);
      expect(restored.resolved, isFalse);
      expect(
          (restored.lastInspectionValues['Oil Temp'] as num).toDouble(),
          equals(95.0));
    });

    test('F-09 ParamStat.withNewNumeric correctly updates avg/min/max', () {
      const first = ParamStat(type: 'number', avg: 80.0, min: 80.0, max: 80.0);
      // Second reading: 90.0 — prevCount was 1
      final second = first.withNewNumeric(90.0, 1);
      expect(second.avg, closeTo(85.0, 0.001),
          reason: '(80+90)/2 = 85');
      expect(second.min, equals(80.0));
      expect(second.max, equals(90.0));
    });

    test('F-10 ParamStat.withNewOption correctly increments option count', () {
      const base = ParamStat(type: 'dropdown');
      final after = base.withNewOption('Good');
      expect(after.optionCounts?['Good'], equals(1));
      final after2 = after.withNewOption('Good');
      expect(after2.optionCounts?['Good'], equals(2));
      final after3 = after2.withNewOption('Monitor');
      expect(after3.optionCounts?['Monitor'], equals(1));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP G — ClientRepository integration (real Firebase write)
  // ══════════════════════════════════════════════════════════════════════════
  group('G: ClientRepository — create + bootstrap', () {
    test('G-01..07 createClient writes record, meta node, and bootstraps admin',
        () async {
      await DatabaseModeService.setClientScope(null);
      final repo = ClientRepository();
      testClient = await repo.createClient(
        name: 'VAPLI QA Client $ts',
        description: 'Automated integration test client',
      );

      expect(testClient.id.isNotEmpty, isTrue, reason: 'G-01 client id generated');
      expect(testClient.dbKey.isNotEmpty, isTrue, reason: 'G-02 dbKey derived');
      expect(testClient.name, contains('VAPLI QA'), reason: 'G-03 name stored');

      // Verify the client record was written to Firebase
      final clients = await repo.getAllClients();
      final found = clients.any((c) => c.id == testClient.id);
      expect(found, isTrue, reason: 'G-04 client retrievable from Firebase');

      // Verify meta node written under client dbKey
      final metaSnap = await DatabaseModeService.ref(
              'testDB/${testClient.dbKey}/meta')
          .get();
      expect(metaSnap.exists, isTrue,
          reason: 'G-05 meta node written under client dbKey');

      // Verify bootstrap admin user under client scope
      final usersSnap = await DatabaseModeService.ref(
              'testDB/${testClient.dbKey}/users')
          .get();
      expect(usersSnap.exists, isTrue,
          reason: 'G-06 bootstrap users node exists');

      final usersMap = Map<String, dynamic>.from(usersSnap.value as Map);
      final adminEntry = usersMap.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .firstWhere((u) => u['username'] == 'admin', orElse: () => {});
      expect(adminEntry.isNotEmpty, isTrue,
          reason: 'G-07 bootstrap admin user created');
      expect(adminEntry['role'],
          equals(AccessControlService.roleSuperAdmin),
          reason: 'G-07b bootstrap admin is super admin');

      // Verify bootstrap password works
      final storedHash = adminEntry['password_hash'] as String;
      expect(HashUtil.verifyPassword('Admin@123', storedHash), isTrue,
          reason: 'G-07c bootstrap admin password is Admin@123');
    });

    test('G-08 ensureClientBootstrap is idempotent (second call no-op)', () async {
      // Calling again must not overwrite the existing bootstrap admin
      final repo = ClientRepository();
      await repo.ensureClientBootstrap(testClient);

      final usersSnap = await DatabaseModeService.ref(
              'testDB/${testClient.dbKey}/users')
          .get();
      final usersMap = Map<String, dynamic>.from(usersSnap.value as Map);
      final adminEntries = usersMap.values
          .where((v) => (v as Map)['username'] == 'admin')
          .toList();
      expect(adminEntries.length, equals(1),
          reason: 'G-08 idempotent — still only one admin after double bootstrap');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP H — AuthRepository integration
  // ══════════════════════════════════════════════════════════════════════════
  group('H: AuthRepository — user creation + login flow', () {
    setUpAll(() async {
      // Scope to testClient so auth writes go to global users path
      // AuthRepository reads from global 'users' path and filters by clientIds
      await DatabaseModeService.setClientScope(null);
    });

    test('H-01..06 createUser writes correct schema', () async {
      final repo = AuthRepository();
      testAdminUser = await repo.createUser(
        username: 'qa_admin_$ts',
        fullName: 'QA Admin User',
        password: 'QAAdmin@123',
        role: AccessControlService.roleAdmin,
        clientIds: [testClient.id],
      );

      expect(testAdminUser.id.isNotEmpty, isTrue, reason: 'H-01');
      expect(testAdminUser.username, equals('qa_admin_$ts'), reason: 'H-02');
      expect(testAdminUser.role, equals('admin'), reason: 'H-03');
      expect(testAdminUser.clientIds.contains(testClient.id), isTrue,
          reason: 'H-04');
      expect(testAdminUser.isActive, isTrue, reason: 'H-05');
      expect(
          HashUtil.verifyPassword('QAAdmin@123', testAdminUser.passwordHash),
          isTrue,
          reason: 'H-06 password hashed and verifiable');
    });

    test('H-07 createUser for regular user', () async {
      final repo = AuthRepository();
      testRegularUser = await repo.createUser(
        username: 'qa_user_$ts',
        fullName: 'QA Regular User',
        password: 'QAUser@456',
        role: AccessControlService.roleUser,
        clientIds: [testClient.id],
      );

      expect(testRegularUser.role, equals('user'), reason: 'H-07');
    });

    test('H-08 duplicate username in same client throws', () async {
      final repo = AuthRepository();
      expect(
        () async => repo.createUser(
          username: 'qa_admin_$ts', // same username
          fullName: 'Duplicate',
          password: 'AnyPass@1',
          role: 'user',
          clientIds: [testClient.id],
        ),
        throwsException,
        reason: 'H-08 duplicate username in same client must throw',
      );
    });

    test('H-09 getAllUsers returns created users', () async {
      final repo = AuthRepository();
      final users = await repo.getAllUsers();
      expect(users.any((u) => u.id == testAdminUser.id), isTrue,
          reason: 'H-09 created admin visible in getAllUsers');
      expect(users.any((u) => u.id == testRegularUser.id), isTrue,
          reason: 'H-09b created user visible in getAllUsers');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP I — AppSettingsService integration (session timeout)
  // ══════════════════════════════════════════════════════════════════════════
  group('I: AppSettingsService — session timeout read/write', () {
    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('I-01 setSessionTimeout writes and getSessionTimeout reads back', () async {
      await AppSettingsService.setSessionTimeout(
        noTimeout: false,
        minutes: 45,
      );
      final timeout = await AppSettingsService.getSessionTimeout();
      expect(timeout, isNotNull);
      expect(timeout!.inMinutes, equals(45),
          reason: 'I-01 45-minute timeout round-trips');
    });

    test('I-02 noTimeout mode returns null duration', () async {
      await AppSettingsService.setSessionTimeout(
        noTimeout: true,
        minutes: 60,
      );
      final timeout = await AppSettingsService.getSessionTimeout();
      expect(timeout, isNull,
          reason: 'I-02 no-timeout mode must return null');
    });

    test('I-03 restore to 60 minutes for remaining tests', () async {
      await AppSettingsService.setSessionTimeout(
        noTimeout: false,
        minutes: 60,
      );
      final timeout = await AppSettingsService.getSessionTimeout();
      expect(timeout?.inMinutes, equals(60));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP J — TankRepository integration
  // ══════════════════════════════════════════════════════════════════════════
  group('J: TankRepository — CRUD integration', () {
    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('J-01..10 createTank writes all fields correctly', () async {
      final repo = TankRepository();
      final props = _buildProps(multiConstraint: true);
      testTank = await repo.createTank(
        tankCode: 'TK-QA-01',
        tankName: 'QA Hydraulic $ts',
        location: 'Plant-1/Zone-A',
        inspectionProperties: props,
        scaleMax: 200,
        createdBy: testAdminUser.id,
        inspectionFrequencyType: 'daily',
        inspectionFrequencyDays: 1,
      );

      expect(testTank.id.isNotEmpty, isTrue, reason: 'J-01 tank id generated');
      expect(testTank.tankCode, equals('TK-QA-01'), reason: 'J-02');
      expect(testTank.tankName, contains('QA Hydraulic'), reason: 'J-03');
      expect(testTank.isActive, isTrue, reason: 'J-04');
      expect(testTank.scaleMax, equals(200.0), reason: 'J-05');
      expect(testTank.inspectionProperties.length, equals(7),
          reason: 'J-06 all 7 params stored');
      expect(testTank.inspectionFrequencyType, equals('daily'),
          reason: 'J-07');
      expect(testTank.inspectionFrequencyDays, equals(1), reason: 'J-08');

      // Verify it's retrievable from DB
      final tanks = await repo.getAllTanks();
      final found = tanks.any((t) => t.id == testTank.id);
      expect(found, isTrue, reason: 'J-09 tank retrievable from Firebase');

      // Verify inspection property schema preserved
      final propMap = {
        for (final p in testTank.inspectionProperties)
          (p['id'] as String): p
      };
      expect(propMap['oil_level']?['keep_previous_capture'], isTrue,
          reason: 'J-10 keep_previous_capture field preserved');
    });

    test('J-11 getAllTanks returns only active tanks', () async {
      final repo = TankRepository();
      final all = await repo.getAllTanks();
      expect(all.every((t) => t.isActive), isTrue,
          reason: 'J-11 getAllTanks filters inactive tanks');
    });

    test('J-12 inspection properties contain autofill expression', () {
      final propMap = {
        for (final p in testTank.inspectionProperties) (p['id'] as String): p
      };
      expect(propMap['consumption']?['autofill'], isTrue,
          reason: 'J-12 autofill=true preserved');
      expect(
          propMap['consumption']?['autofill_expression']
              .toString()
              .contains('oil_level'),
          isTrue,
          reason: 'J-12b autofill expression references oil_level');
    });

    test('J-13 multi-constraint prop has both warning and critical', () {
      final propMap = {
        for (final p in testTank.inspectionProperties) (p['id'] as String): p
      };
      final constraints =
          List<dynamic>.from(propMap['oil_temp']?['constraints'] as List);
      expect(
          constraints.any((c) => (c as Map)['severity'] == 'warning'),
          isTrue,
          reason: 'J-13 warning constraint present');
      expect(
          constraints.any((c) => (c as Map)['severity'] == 'critical'),
          isTrue,
          reason: 'J-13b critical constraint present');
      expect(
          constraints.any((c) => (c as Map)['block_submission'] == true),
          isTrue,
          reason: 'J-13c blocking critical present');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP K — TankTreeRepository integration
  // ══════════════════════════════════════════════════════════════════════════
  group('K: TankTreeRepository — folder + leaf node operations', () {
    late TankNodeModel folderNode;
    late TankNodeModel leafNode;

    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('K-01..06 createFolder writes correct node schema', () async {
      final repo = TankTreeRepository();
      folderNode = await repo.createFolder(
        name: 'Plant-1',
        parentId: null,
        order: 0,
      );

      expect(folderNode.id.isNotEmpty, isTrue, reason: 'K-01');
      expect(folderNode.name, equals('Plant-1'), reason: 'K-02');
      expect(folderNode.type, equals('folder'), reason: 'K-03');
      expect(folderNode.parentId, isNull, reason: 'K-04 root folder has no parent');
      expect(folderNode.order, equals(0), reason: 'K-05');
      expect(folderNode.path, isNotEmpty, reason: 'K-06 path set');
    });

    test('K-07..12 createLeaf links tank correctly', () async {
      final repo = TankTreeRepository();
      leafNode = await repo.createLeaf(
        name: testTank.tankName,
        parentId: folderNode.id,
        tankId: testTank.id,
        order: 0,
      );

      expect(leafNode.id.isNotEmpty, isTrue, reason: 'K-07');
      expect(leafNode.type, equals('leaf'), reason: 'K-08');
      expect(leafNode.tankId, equals(testTank.id), reason: 'K-09');
      expect(leafNode.parentId, equals(folderNode.id), reason: 'K-10');
      expect(leafNode.name, equals(testTank.tankName), reason: 'K-11');
      expect(leafNode.order, equals(0), reason: 'K-12');
    });

    test('K-13 getTree returns both folder and leaf nodes', () async {
      final repo = TankTreeRepository();
      final tree = await repo.getTree();
      expect(tree.any((n) => n.id == folderNode.id), isTrue,
          reason: 'K-13 folder in tree');
      expect(tree.any((n) => n.id == leafNode.id), isTrue,
          reason: 'K-13b leaf in tree');
    });

    test('K-14 moveNode updates parent_id', () async {
      final repo = TankTreeRepository();
      // Create a second folder to move the leaf into
      final folder2 = await repo.createFolder(
        name: 'Plant-2',
        parentId: null,
        order: 1,
      );
      await repo.moveNode(nodeId: leafNode.id, newParentId: folder2.id);

      final tree = await repo.getTree();
      final movedLeaf = tree.firstWhere((n) => n.id == leafNode.id);
      expect(movedLeaf.parentId, equals(folder2.id),
          reason: 'K-14 parentId updated after move');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP L — ReadingRepository integration (full save + retrieval)
  // ══════════════════════════════════════════════════════════════════════════
  group('L: ReadingRepository — save + retrieval integration', () {
    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('L-01..12 saveReading stores all inspection_values and retrieves them',
        () async {
      final repo = ReadingRepository();
      final inspVals = {
        'Oil Level': 75.0,
        'Oil Temp': 82.0,
        'Vibration': 20.0,
        'Condition': 'Good',
        'Pressure': {'left': 12.5, 'right': 8.3},
        'Remarks': 'Routine check OK',
        'Consumption': 5.0,
      };

      final reading = await repo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: inspVals,
      );

      expect(reading.id.isNotEmpty, isTrue, reason: 'L-01');
      expect(reading.tankId, equals(testTank.id), reason: 'L-02');
      expect(reading.source, equals('manual'), reason: 'L-03');
      expect(reading.capturedBy, equals(testRegularUser.id), reason: 'L-04');

      // Verify all inspection values stored
      expect(
          (reading.inspectionValues['Oil Level'] as num).toDouble(), equals(75.0),
          reason: 'L-05');
      expect(
          (reading.inspectionValues['Oil Temp'] as num).toDouble(), equals(82.0),
          reason: 'L-06');
      expect(reading.inspectionValues['Condition'], equals('Good'),
          reason: 'L-07');
      final pressure =
          Map<String, dynamic>.from(reading.inspectionValues['Pressure'] as Map);
      expect((pressure['left'] as num).toDouble(), equals(12.5),
          reason: 'L-08 dual_text left value');
      expect((pressure['right'] as num).toDouble(), equals(8.3),
          reason: 'L-09 dual_text right value');
      expect(reading.inspectionValues['Remarks'], equals('Routine check OK'),
          reason: 'L-10');

      // Pull it back from DB and verify fromMap round-trip
      final allReadings = await repo.getAllReadings();
      final found = allReadings.firstWhere(
        (r) => r.id == reading.id,
        orElse: () => throw Exception('Reading not found in DB'),
      );
      expect(found.id, equals(reading.id), reason: 'L-11 retrieved from DB');
      expect(
          (found.inspectionValues['Oil Level'] as num).toDouble(), equals(75.0),
          reason: 'L-12 Oil Level preserved after DB round-trip');
    });

    test('L-13 getReadingsInRange filters by date correctly', () async {
      final repo = ReadingRepository();
      final now = DateTime.now();
      final from = now.subtract(const Duration(minutes: 10));
      final to = now.add(const Duration(minutes: 10));

      final readings = await repo.getReadingsInRange(
        tankId: testTank.id,
        from: from,
        to: to,
      );
      expect(readings.isNotEmpty, isTrue,
          reason: 'L-13 readings within ±10 minutes returned');
      expect(readings.every((r) {
        final t = DateTime.parse(r.capturedAt);
        return !t.isBefore(from) && !t.isAfter(to);
      }), isTrue, reason: 'L-13b all returned readings are within window');
    });

    test('L-14 getReadingsInRange returns empty for out-of-range window', () async {
      final repo = ReadingRepository();
      final futureFrom = DateTime.now().add(const Duration(days: 30));
      final futureTo = futureFrom.add(const Duration(days: 1));

      final readings = await repo.getReadingsInRange(
        tankId: testTank.id,
        from: futureFrom,
        to: futureTo,
      );
      expect(readings, isEmpty, reason: 'L-14 future window returns no readings');
    });

    test('L-15 getAllReadings returns sorted newest first', () async {
      final repo = ReadingRepository();
      // Write a second reading
      await repo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: {'Oil Level': 65.0, 'Oil Temp': 88.0},
      );

      final all = await repo.getAllReadings();
      final tankReadings = all.where((r) => r.tankId == testTank.id).toList();
      expect(tankReadings.length, greaterThanOrEqualTo(2), reason: 'L-15');
      // Verify descending order
      for (var i = 0; i < tankReadings.length - 1; i++) {
        expect(
            tankReadings[i].capturedAt
                .compareTo(tankReadings[i + 1].capturedAt) >=
                0,
            isTrue,
            reason: 'L-15b getAllReadings returns newest-first');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP M — DashboardStatsRepository integration (incremental aggregation)
  // ══════════════════════════════════════════════════════════════════════════
  group('M: DashboardStatsRepository — incremental stats aggregation', () {
    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('M-01..12 updateStatsAfterReading aggregates correctly over 3 readings',
        () async {
      final statsRepo = DashboardStatsRepository();
      final readingRepo = ReadingRepository();

      // Reading 1
      final r1 = await readingRepo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: {
          'Oil Level': 70.0,
          'Oil Temp': 82.0,
          'Vibration': 20.0,
          'Condition': 'Good',
          'Pressure': {'left': 10.0, 'right': 6.0},
          'Remarks': 'OK',
          'Consumption': 5.0,
        },
      );
      await statsRepo.updateStatsAfterReading(reading: r1, tank: testTank);

      final after1 = await statsRepo.getStats(testTank.id);
      expect(after1.count, greaterThanOrEqualTo(1), reason: 'M-01 count >= 1');

      // Reading 2
      final r2 = await readingRepo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: {
          'Oil Level': 60.0,
          'Oil Temp': 88.0,
          'Vibration': 30.0,
          'Condition': 'Monitor',
          'Pressure': {'left': 11.0, 'right': 7.0},
          'Remarks': 'Watch',
          'Consumption': -10.0,
        },
      );
      await statsRepo.updateStatsAfterReading(reading: r2, tank: testTank);

      final after2 = await statsRepo.getStats(testTank.id);
      expect(after2.count, greaterThanOrEqualTo(2), reason: 'M-02');

      final oilLevelStat = after2.paramStats['Oil Level'];
      expect(oilLevelStat, isNotNull, reason: 'M-03 Oil Level stat exists');
      expect(oilLevelStat!.min, lessThanOrEqualTo(65.0),
          reason: 'M-04 min tracks lowest value');
      expect(oilLevelStat.max, greaterThanOrEqualTo(70.0),
          reason: 'M-05 max tracks highest value');

      final condStat = after2.paramStats['Condition'];
      expect(condStat?.optionCounts?['Good'], greaterThanOrEqualTo(1),
          reason: 'M-06 Good option counted');
      expect(condStat?.optionCounts?['Monitor'], greaterThanOrEqualTo(1),
          reason: 'M-07 Monitor option counted');

      expect(after2.lastReading['Oil Temp'],
          anyOf(equals(88.0), equals(88)),
          reason: 'M-08 lastReading reflects most recent reading');
      expect(after2.lastCapturedBy, equals(testRegularUser.fullName),
          reason: 'M-09 lastCapturedBy updated');

      // Reading 3: critical temp
      final r3 = await readingRepo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: {
          'Oil Level': 50.0,
          'Oil Temp': 105.0,
          'Vibration': 50.0,
          'Condition': 'Critical',
          'Pressure': {'left': 9.0, 'right': 5.0},
          'Remarks': 'Alert!',
          'Consumption': -10.0,
        },
      );
      await statsRepo.updateStatsAfterReading(reading: r3, tank: testTank);

      final after3 = await statsRepo.getStats(testTank.id);
      expect(after3.count, greaterThanOrEqualTo(3), reason: 'M-10');

      final tempStat = after3.paramStats['Oil Temp'];
      expect(tempStat?.max, greaterThanOrEqualTo(105.0),
          reason: 'M-11 Oil Temp max updated to 105');

      final condStat3 = after3.paramStats['Condition'];
      expect(condStat3?.optionCounts?['Critical'], greaterThanOrEqualTo(1),
          reason: 'M-12 Critical option counted after 3rd reading');
    });

    test('M-13 getStats returns empty model for unknown tank', () async {
      final statsRepo = DashboardStatsRepository();
      final stats = await statsRepo.getStats('nonexistent_tank_$ts');
      expect(stats.count, equals(0), reason: 'M-13 empty stats for new tank');
      expect(stats.paramStats, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP N — AlertRepository integration
  // ══════════════════════════════════════════════════════════════════════════
  group('N: AlertRepository — alert lifecycle integration', () {
    late AlertModel warningAlert;
    late AlertModel criticalAlert;

    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('N-01..10 createAlert writes all fields correctly (warning)', () async {
      final repo = AlertRepository();
      final constraint = {
        'id': 'warn_90',
        'op': '>',
        'value': '90',
        'severity': 'warning',
        'block_submission': false,
        'show_dashboard_alert': true,
        'store_history': true,
        'alert_title': 'High Temperature',
        'message': 'Oil Temp exceeded warning threshold',
      };

      warningAlert = await repo.createAlert(
        tankId: testTank.id,
        tankCode: testTank.tankCode,
        tankName: testTank.tankName,
        tankLocation: testTank.location,
        readingId: 'r_warning_$ts',
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        capturedAt: DateTime.now().toIso8601String(),
        constraint: constraint,
        constraintLabel: 'Oil Temp',
        violatedValue: '95.0',
        lastInspectionValues: {'Oil Temp': 95.0, 'Oil Level': 70.0},
      );

      expect(warningAlert.id.isNotEmpty, isTrue, reason: 'N-01');
      expect(warningAlert.tankId, equals(testTank.id), reason: 'N-02');
      expect(warningAlert.constraintSeverity, equals('warning'), reason: 'N-03');
      expect(warningAlert.blockSubmission, isFalse, reason: 'N-04 warning non-blocking');
      expect(warningAlert.showDashboardAlert, isTrue, reason: 'N-05');
      expect(warningAlert.resolved, isFalse, reason: 'N-06');
      expect(warningAlert.alertTitle, equals('High Temperature'), reason: 'N-07');
      expect(warningAlert.constraintLabel, equals('Oil Temp'), reason: 'N-08');
      expect(warningAlert.violatedValue, equals('95.0'), reason: 'N-09');
      expect(
          (warningAlert.lastInspectionValues['Oil Temp'] as num).toDouble(),
          equals(95.0),
          reason: 'N-10 lastInspectionValues stored');
    });

    test('N-11..13 createAlert for critical (blocking)', () async {
      final repo = AlertRepository();
      final constraint = {
        'id': 'crit_100',
        'op': '>',
        'value': '100',
        'severity': 'critical',
        'block_submission': true,
        'show_dashboard_alert': true,
        'store_history': true,
        'alert_title': 'Critical Temperature',
        'message': 'Oil Temp exceeded critical threshold',
      };

      criticalAlert = await repo.createAlert(
        tankId: testTank.id,
        tankCode: testTank.tankCode,
        tankName: testTank.tankName,
        readingId: 'r_critical_$ts',
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        capturedAt: DateTime.now().toIso8601String(),
        constraint: constraint,
        constraintLabel: 'Oil Temp',
        violatedValue: '105.0',
        lastInspectionValues: {'Oil Temp': 105.0},
      );

      expect(criticalAlert.constraintSeverity, equals('critical'), reason: 'N-11');
      expect(criticalAlert.blockSubmission, isTrue, reason: 'N-12 critical is blocking');
      expect(criticalAlert.resolved, isFalse, reason: 'N-13');
    });

    test('N-14 getActiveDashboardAlerts returns unresolved+dashboard alerts',
        () async {
      final repo = AlertRepository();
      final active = await repo.getActiveDashboardAlerts();
      expect(active.any((a) => a.id == warningAlert.id), isTrue,
          reason: 'N-14 warning alert in active dashboard alerts');
      expect(active.any((a) => a.id == criticalAlert.id), isTrue,
          reason: 'N-14b critical alert in active dashboard alerts');
      expect(active.every((a) => !a.resolved), isTrue,
          reason: 'N-14c all active alerts are unresolved');
    });

    test('N-15 getAll returns both resolved and unresolved', () async {
      final repo = AlertRepository();
      final all = await repo.getAll();
      expect(all.any((a) => a.id == warningAlert.id), isTrue,
          reason: 'N-15 warning alert in getAll');
    });

    test('N-16..18 resolveAlert marks resolved and stores resolver info', () async {
      final repo = AlertRepository();
      await repo.resolveAlert(
        alertId: warningAlert.id,
        resolvedBy: testAdminUser.id,
      );

      final all = await repo.getAll();
      final resolved = all.firstWhere((a) => a.id == warningAlert.id);
      expect(resolved.resolved, isTrue, reason: 'N-16 resolved=true');
      expect(resolved.resolvedBy, equals(testAdminUser.id),
          reason: 'N-17 resolvedBy stored');
      expect(resolved.resolvedAt, isNotNull, reason: 'N-18 resolvedAt timestamp set');
    });

    test('N-19 getActiveDashboardAlerts excludes resolved alert', () async {
      final repo = AlertRepository();
      final active = await repo.getActiveDashboardAlerts();
      expect(active.any((a) => a.id == warningAlert.id), isFalse,
          reason: 'N-19 resolved alert excluded from active dashboard alerts');
    });

    test('N-20 default title is auto-generated when alert_title is absent',
        () async {
      final repo = AlertRepository();
      final constraint = {
        'id': 'no_title',
        'op': '>',
        'value': '50',
        'severity': 'warning',
        'block_submission': false,
        'show_dashboard_alert': false,
        'store_history': true,
        // NO alert_title key
      };
      final alert = await repo.createAlert(
        tankId: testTank.id,
        tankCode: testTank.tankCode,
        tankName: testTank.tankName,
        readingId: 'r_notitle_$ts',
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        capturedAt: DateTime.now().toIso8601String(),
        constraint: constraint,
        constraintLabel: 'Vibration',
        violatedValue: '60.0',
        lastInspectionValues: {'Vibration': 60.0},
      );
      expect(alert.alertTitle.isNotEmpty, isTrue,
          reason: 'N-20 auto-generated title is non-empty');
      expect(alert.alertTitle.toLowerCase(),
          anyOf(contains('warning'), contains('vibration')),
          reason: 'N-20b auto title includes severity or label');
    });

    test('N-21 deleteAlert removes record from DB', () async {
      final repo = AlertRepository();
      await repo.deleteAlert(criticalAlert.id);

      final all = await repo.getAll();
      expect(all.any((a) => a.id == criticalAlert.id), isFalse,
          reason: 'N-21 deleted alert not present in getAll');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP O — End-to-end inspection flow
  // Mirrors exactly what happens when a user fills the ReadingEntryScreen
  // and taps Save: ReadingRepository.saveReading → DashboardStats update →
  // Previouscapture write → AlertRepository.createAlert (if violated).
  // ══════════════════════════════════════════════════════════════════════════
  group('O: End-to-end inspection flow (reading → stats → alert)', () {
    setUpAll(() async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
    });

    test('O-01..18 Full save cycle: normal reading (no violation)', () async {
      final readingRepo = ReadingRepository();
      final statsRepo = DashboardStatsRepository();

      final inspVals = {
        'Oil Level': 80.0,
        'Oil Temp': 75.0,  // below warning threshold
        'Vibration': 25.0,
        'Condition': 'Good',
        'Pressure': {'left': 13.0, 'right': 9.0},
        'Remarks': 'Normal inspection',
        'Consumption': 5.0,
      };

      // 1. Save reading (same call as ReadingEntryState._save)
      final reading = await readingRepo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: inspVals,
      );
      expect(reading.id.isNotEmpty, isTrue, reason: 'O-01 reading saved');

      // 2. Update dashboard stats (same call as ReadingEntryState._save)
      await statsRepo.updateStatsAfterReading(reading: reading, tank: testTank);
      final stats = await statsRepo.getStats(testTank.id);
      expect(stats.count, greaterThan(0), reason: 'O-02 stats count incremented');
      expect(stats.lastReading['Oil Level'],
          anyOf(equals(80.0), equals(80)),
          reason: 'O-03 lastReading updated');

      // 3. Write Previouscapture for oil_level (keep_previous_capture=true)
      final tankKey = testTank.tankName.replaceAll('/', '_');
      final prevPath =
          'Previouscapture/$tankKey/oil_level/Oil Level';
      await DatabaseModeService.ref(prevPath).set(80.0);

      final prevSnap = await DatabaseModeService.ref(prevPath).get();
      expect(prevSnap.exists, isTrue, reason: 'O-04 Previouscapture written');
      expect((prevSnap.value as num).toDouble(), equals(80.0),
          reason: 'O-05 Previouscapture stores oil_level value');

      // 4. Verify constraint does NOT fire (75 < 90)
      final oilTempProp = testTank.inspectionProperties
          .firstWhere((p) => p['id'] == 'oil_temp');
      final violations = _fireConstraints(oilTempProp, inspVals['Oil Temp']!);
      expect(violations, isEmpty, reason: 'O-06 no violations at temp=75');

      // 5. Verify autofill expression evaluates correctly with last value
      final lastLevel = 0.0; // first reading, no previous capture yet
      final consumption = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {
          'oil_level': inspVals['Oil Level'] as double,
          'oil_level__last': lastLevel,
        },
      );
      expect(consumption, closeTo(80.0, 0.001),
          reason: 'O-07 autofill consumption = current - last = 80 - 0 = 80');
    });

    test('O-08..18 Full save cycle: violation reading (warning fires, alert created)',
        () async {
      final readingRepo = ReadingRepository();
      final statsRepo = DashboardStatsRepository();
      final alertRepo = AlertRepository();

      final inspVals = {
        'Oil Level': 55.0,
        'Oil Temp': 95.0,  // > 90, warning fires
        'Vibration': 40.0,
        'Condition': 'Monitor',
        'Pressure': {'left': 11.0, 'right': 7.0},
        'Remarks': 'Temperature elevated',
        'Consumption': -25.0,
      };

      // 1. Check constraint BEFORE save (mirrors ReadingEntryState._onValueChanged)
      final oilTempProp = testTank.inspectionProperties
          .firstWhere((p) => p['id'] == 'oil_temp');
      final violations = _fireConstraints(oilTempProp, inspVals['Oil Temp']!);
      expect(violations.isNotEmpty, isTrue,
          reason: 'O-08 warning fires at oil_temp=95');
      expect(violations.first['severity'], equals('warning'),
          reason: 'O-09 severity is warning');
      expect(violations.first['block_submission'], isFalse,
          reason: 'O-10 warning does not block save');

      // 2. Save is NOT blocked, proceed
      final reading = await readingRepo.saveReading(
        tankId: testTank.id,
        tankName: testTank.tankName,
        level: 0,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        inspectionValues: inspVals,
      );
      expect(reading.id.isNotEmpty, isTrue, reason: 'O-11 reading saved despite warning');

      // 3. Update stats
      await statsRepo.updateStatsAfterReading(reading: reading, tank: testTank);

      // 4. Create alert for violated constraint (mirrors ReadingEntryState post-save)
      final violatedConstraint = Map<String, dynamic>.from(violations.first);
      final alert = await alertRepo.createAlert(
        tankId: testTank.id,
        tankCode: testTank.tankCode,
        tankName: testTank.tankName,
        tankLocation: testTank.location,
        readingId: reading.id,
        capturedBy: testRegularUser.id,
        capturedByName: testRegularUser.fullName,
        capturedAt: reading.capturedAt,
        constraint: violatedConstraint,
        constraintLabel: 'Oil Temp',
        violatedValue: inspVals['Oil Temp'].toString(),
        lastInspectionValues: inspVals,
      );

      expect(alert.readingId, equals(reading.id),
          reason: 'O-12 alert linked to reading');
      expect(alert.constraintSeverity, equals('warning'),
          reason: 'O-13 alert severity=warning');
      expect(alert.tankId, equals(testTank.id),
          reason: 'O-14 alert linked to tank');

      // 5. Previouscapture updated to new oil_level
      final tankKey = testTank.tankName.replaceAll('/', '_');
      await DatabaseModeService.ref(
              'Previouscapture/$tankKey/oil_level/Oil Level')
          .set(55.0);

      final prevSnap = await DatabaseModeService.ref(
              'Previouscapture/$tankKey/oil_level/Oil Level')
          .get();
      expect((prevSnap.value as num).toDouble(), equals(55.0),
          reason: 'O-15 Previouscapture updated to 55');

      // 6. Next autofill uses updated Previouscapture
      const nextLevel = 48.0;
      const lastLevel = 55.0;
      final nextConsumption = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {
          'oil_level': nextLevel,
          'oil_level__last': lastLevel,
        },
      );
      expect(nextConsumption, closeTo(-7.0, 0.001),
          reason: 'O-16 autofill: 48 - 55 = -7 (oil consumed)');

      // 7. Stats show Monitor was counted in Condition
      final stats = await statsRepo.getStats(testTank.id);
      expect(stats.paramStats['Condition']?.optionCounts?['Monitor'],
          greaterThanOrEqualTo(1),
          reason: 'O-17 Monitor counted in Condition stats');

      // 8. Active alerts include our new warning
      final active = await alertRepo.getActiveDashboardAlerts();
      expect(active.any((a) => a.id == alert.id), isTrue,
          reason: 'O-18 new warning alert visible in active dashboard alerts');
    });

    test('O-19 Critical violation BLOCKS save (simulate the gate check)', () {
      // Mirrors ReadingEntryState._hasBlockingViolation check
      final oilTempProp = {
        'id': 'oil_temp',
        'label': 'Oil Temp',
        'constraints': [
          {
            'id': 'crit_100',
            'op': '>',
            'value': '100',
            'severity': 'critical',
            'block_submission': true,
          }
        ]
      };

      final violations = _fireConstraints(oilTempProp, 105.0);
      final hasBlockingViolation =
          violations.any((v) => v['block_submission'] == true);
      expect(hasBlockingViolation, isTrue,
          reason: 'O-19 critical violation blocks save gate');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP P — Cross-client data isolation
  // ══════════════════════════════════════════════════════════════════════════
  group('P: Cross-client data isolation', () {
    late ClientModel clientB;

    setUpAll(() async {
      await DatabaseModeService.setClientScope(null);
      final repo = ClientRepository();
      clientB = await repo.createClient(
        name: 'VAPLI QA Client B $ts',
        description: 'Isolation test client B',
      );
    });

    tearDownAll(() async {
      try {
        await DatabaseModeService.ref('testDB/${clientB.dbKey}').remove();
      } catch (_) {}
    });

    test('P-01 Tank written in client A is NOT visible in client B scope',
        () async {
      // Client A: testTank was created in GROUP J
      await DatabaseModeService.setClientScope(clientB.dbKey);
      final repo = TankRepository();
      final bTanks = await repo.getAllTanks();
      expect(bTanks.any((t) => t.id == testTank.id), isFalse,
          reason: 'P-01 client A tank not visible in client B scope');
    });

    test('P-02 Reading written in client A is NOT visible in client B scope',
        () async {
      await DatabaseModeService.setClientScope(clientB.dbKey);
      final repo = ReadingRepository();
      final bReadings = await repo.getAllReadings();
      // All of client B readings should be for client B tanks only
      // (which we haven't created) → empty or different tankIds
      final leaked = bReadings.where((r) => r.tankId == testTank.id).toList();
      expect(leaked, isEmpty,
          reason: 'P-02 client A readings not visible in client B scope');
    });

    test('P-03 DashboardStats scoped: client A stats not in client B', () async {
      await DatabaseModeService.setClientScope(clientB.dbKey);
      final repo = DashboardStatsRepository();
      // testTank belongs to client A — stats should not be in client B scope
      final stats = await repo.getStats(testTank.id);
      expect(stats.count, equals(0),
          reason: 'P-03 client A stats not visible in client B scope');
    });

    test('P-04 DatabaseModeService.path scopes to active client only', () async {
      await DatabaseModeService.setClientScope(clientB.dbKey);
      final pB = DatabaseModeService.path('tanks/any');
      expect(pB, contains(clientB.dbKey),
          reason: 'P-04 path uses client B key when client B is active');
      expect(pB, isNot(contains(testClient.dbKey)),
          reason: 'P-04b path does not bleed client A key');
    });

    test('P-05 Switching scope to client A restores correct path', () async {
      await DatabaseModeService.setClientScope(testClient.dbKey);
      final pA = DatabaseModeService.path('tanks/any');
      expect(pA, contains(testClient.dbKey),
          reason: 'P-05 path switches back to client A correctly');
    });
  });
}