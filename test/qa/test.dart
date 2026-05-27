import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/app_settings_service.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/core/services/client_repository.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/services/expression_engine.dart';
import 'package:lubrication_indicator/core/services/firebase_env_options.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';

import 'package:lubrication_indicator/features/alerts/data/models/alert_model.dart';
import 'package:lubrication_indicator/features/alerts/data/repositories/alert_reposiotry.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/auth/data/repositories/auth_repository.dart';
import 'package:lubrication_indicator/features/dashboard/data/repositories/dashboard_stats_repository.dart';
import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ts = DateTime.now().millisecondsSinceEpoch;
  var caseCount = 0;

  ClientModel? client;
  UserModel? adminUser;
  UserModel? inspectorUser;
  TankModel? tank;
  TankNode? rootFolder;
  TankNode? tankLeaf;
  ReadingModel? reading1;
  ReadingModel? reading2;
  AlertModel? alert;

  final createdUserIds = <String>[];

  Future<void> qa(bool ok, String label) async {
    caseCount += 1;
    expect(ok, isTrue, reason: '[${caseCount}] $label');
    print('[PASS][${caseCount}] $label');
  }

  List<Map<String, dynamic>> buildProps() => [
        {
          'id': 'oil_level',
          'label': 'Oil Level',
          'type': 'number',
          'required': true,
          'keep_previous_capture': true,
        },
        {
          'id': 'oil_temp',
          'label': 'Oil Temp',
          'type': 'number',
          'required': true,
          'constraints': [
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
            }
          ]
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
      ];

  setUpAll(() async {
    print('[QA] setUpAll: loading env');
    await dotenv.load(fileName: '.env/.env');

    print('[QA] setUpAll: initializing firebase');
    await Firebase.initializeApp(options: FirebaseEnvOptions.currentPlatform);

    print('[QA] setUpAll: initializing DB mode service');
    await DatabaseModeService.init();
    await DatabaseModeService.setDevelopment(true);
    await DatabaseModeService.setClientScope(null);
    await ClientContextService.clearActiveClient();

    print('[QA] setUpAll complete');
  });

  tearDownAll(() async {
    print('[QA] tearDownAll: cleanup start');
    try {
      if (client != null) {
        await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}').remove();
        await FirebaseDatabase.instance.ref('testDB/clients/${client!.id}').remove();
      }
      for (final uid in createdUserIds) {
        await FirebaseDatabase.instance.ref('testDB/users/$uid').remove();
      }
    } catch (_) {}
    print('[QA] tearDownAll: cleanup done');
  });

  group('A: Core logic services', () {
    test('A-01..A-09 expression/hash/access/path logic', () async {
      final ids = ExpressionEngine.extractIds(r'${oil_level}-${oil_level__last}');
      await qa(ids.contains('oil_level'), 'extractIds includes oil_level');
      await qa(ids.contains('oil_level__last'), 'extractIds includes oil_level__last');

      final val = ExpressionEngine.evaluate(
        r'${oil_level}-${oil_level__last}',
        variables: {'oil_level': 48, 'oil_level__last': 55},
      );
      await qa((val + 7).abs() < 0.001, 'autofill expression evaluates to -7');

      final hash = HashUtil.hashPassword('Admin@123');
      await qa(hash.isNotEmpty, 'hashPassword returns non-empty hash');
      await qa(HashUtil.verifyPassword('Admin@123', hash), 'verifyPassword accepts correct password');
      await qa(!HashUtil.verifyPassword('WrongPass', hash), 'verifyPassword rejects wrong password');

      final superAdmin = UserModel(
        id: 'sa_$ts',
        username: 'sa_$ts',
        fullName: 'Super Admin',
        passwordHash: hash,
        role: AccessControlService.roleSuperAdmin,
        createdAt: DateTime.now().toIso8601String(),
      );
      await qa(AccessControlService.can(superAdmin, AccessControlService.pCreateClient),
          'super admin can create client');

      await DatabaseModeService.setClientScope('demo_client');
      final scopedPath = DatabaseModeService.path('tanks/t1');
      await qa(scopedPath == 'testDB/demo_client/tanks/t1', 'DatabaseModeService scopes tanks path');

      final globalPath = DatabaseModeService.path('users/u1');
      await qa(globalPath == 'testDB/users/u1', 'DatabaseModeService keeps users global');
    });
  });

  group('B: Real repository/service integration', () {
    test('B-01..B-06 client bootstrap + auth flow', () async {
      final clientRepo = ClientRepository();
      final authRepo = AuthRepository();

      client = await clientRepo.createClient(
        name: 'QA Client $ts',
        description: 'Real service integration test',
      );
      await qa(client!.id.isNotEmpty, 'client created');
      await qa(client!.dbKey.isNotEmpty, 'client dbKey generated');

      final metaSnap = await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}/meta').get();
      await qa(metaSnap.exists, 'client meta node exists');

      final bootstrapAdmin = await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}/users').get();
      await qa(bootstrapAdmin.exists, 'client bootstrap admin exists');

      await DatabaseModeService.setClientScope(client!.dbKey);
      await ClientContextService.setActiveClient(client!);

      adminUser = await authRepo.createUser(
        username: 'qa_admin_$ts',
        fullName: 'QA Admin',
        password: 'Admin@123',
        role: AccessControlService.roleAdmin,
        clientIds: [client!.id],
      );
      createdUserIds.add(adminUser!.id);

      inspectorUser = await authRepo.createUser(
        username: 'qa_user_$ts',
        fullName: 'QA User',
        password: 'User@123',
        role: AccessControlService.roleUser,
        clientIds: [client!.id],
      );
      createdUserIds.add(inspectorUser!.id);

      final login = await authRepo.login('qa_user_$ts', 'User@123');
      await qa(login.id == inspectorUser!.id, 'auth login returns created user');
      await qa(login.lastLoginAt != null, 'login updates last_login_at');
    });

    test('B-07..B-13 tank + tree repositories', () async {
      final tankRepo = TankRepository();
      final treeRepo = TankTreeRepository();

      tank = await tankRepo.createTank(
        tankCode: 'TK-$ts',
        tankName: 'Hydraulic QA $ts',
        location: 'Plant-1/Line-1',
        scaleMax: 200,
        createdBy: adminUser!.id,
        properties: buildProps(),
      );

      await qa(tank!.id.isNotEmpty, 'tank created');
      await qa(tank!.inspectionProperties.isNotEmpty, 'tank inspection properties saved');

      final tanks = await tankRepo.getAllTanks();
      await qa(tanks.any((t) => t.id == tank!.id), 'tank visible in getAllTanks');

      rootFolder = await treeRepo.createFolder(name: 'Plant QA Root');
      await qa(rootFolder!.id.isNotEmpty, 'tree root folder created');

      tankLeaf = await treeRepo.createLeaf(
        name: tank!.tankName,
        tankId: tank!.id,
        parentId: rootFolder!.id,
      );
      await qa(tankLeaf!.tankId == tank!.id, 'tree leaf linked to tank id');

      final allNodes = await treeRepo.fetchAll();
      await qa(allNodes.any((n) => n.id == rootFolder!.id), 'tree fetchAll contains root folder');
      await qa(allNodes.any((n) => n.id == tankLeaf!.id), 'tree fetchAll contains tank leaf');
    });

    test('B-14..B-22 readings + stats + alerts + settings', () async {
      final readingRepo = ReadingRepository();
      final statsRepo = DashboardStatsRepository();
      final alertRepo = AlertRepository();

      reading1 = await readingRepo.saveReading(
        tankId: tank!.id,
        tankName: tank!.tankName,
        level: 0,
        capturedBy: inspectorUser!.id,
        capturedByName: inspectorUser!.fullName,
        inspectionValues: {
          'Oil Level': 55.0,
          'Oil Temp': 85.0,
          'Condition': 'Good',
          'Pressure': {'left': 12.0, 'right': 8.0},
        },
      );

      reading2 = await readingRepo.saveReading(
        tankId: tank!.id,
        tankName: tank!.tankName,
        level: 0,
        capturedBy: inspectorUser!.id,
        capturedByName: inspectorUser!.fullName,
        inspectionValues: {
          'Oil Level': 48.0,
          'Oil Temp': 95.0,
          'Condition': 'Monitor',
          'Pressure': {'left': 11.0, 'right': 7.0},
        },
      );

      await qa(reading1!.id.isNotEmpty && reading2!.id.isNotEmpty, 'two readings saved');

      final from = DateTime.now().subtract(const Duration(days: 1));
      final to = DateTime.now().add(const Duration(days: 1));
      final inRange = await readingRepo.getReadingsInRange(tankId: tank!.id, from: from, to: to);
      await qa(inRange.length >= 2, 'getReadingsInRange returns new readings');

      await statsRepo.updateStatsAfterReading(reading: reading1!, tank: tank!);
      await statsRepo.updateStatsAfterReading(reading: reading2!, tank: tank!);
      final stats = await statsRepo.getStats(tank!.id);
      await qa(stats.count >= 2, 'dashboard stats count incremented');
      await qa(stats.lastReading['Condition'] == 'Monitor', 'dashboard stats last reading updated');

      alert = await alertRepo.createAlert(
        tankId: tank!.id,
        tankCode: tank!.tankCode,
        tankName: tank!.tankName,
        tankLocation: tank!.location,
        tankPath: tankLeaf?.path,
        readingId: reading2!.id,
        capturedBy: inspectorUser!.id,
        capturedByName: inspectorUser!.fullName,
        capturedAt: reading2!.capturedAt,
        constraint: {
          'id': 'warn_90',
          'op': '>',
          'value': '90',
          'severity': 'warning',
          'block_submission': false,
          'show_dashboard_alert': true,
          'store_history': true,
        },
        constraintLabel: 'Oil Temp',
        violatedValue: '95.0',
        lastInspectionValues: Map<String, dynamic>.from(reading2!.inspectionValues),
      );
      await qa(alert!.id.isNotEmpty, 'alert created from violated reading');

      final active = await alertRepo.getActiveDashboardAlerts();
      await qa(active.any((a) => a.id == alert!.id), 'active dashboard alerts include new alert');

      await alertRepo.resolveAlert(alertId: alert!.id, resolvedBy: adminUser!.id);
      final allAlerts = await alertRepo.getAll();
      final resolved = allAlerts.firstWhere((a) => a.id == alert!.id);
      await qa(resolved.resolved, 'alert resolves correctly');

      await AppSettingsService.setSessionTimeout(noTimeout: false, minutes: 45);
      final sessionTimeout = await AppSettingsService.getSessionTimeout();
      await qa(sessionTimeout?.inMinutes == 45, 'session timeout setting round-trips via service');
    });
  });

  test('TOTAL: at least 20 assertions executed', () {
    print('[QA] Total assertions executed: $caseCount');
    expect(caseCount, greaterThanOrEqualTo(20));
  });
}
