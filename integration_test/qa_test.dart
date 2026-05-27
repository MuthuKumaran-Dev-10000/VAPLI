import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
import 'package:lubrication_indicator/features/auth/presentation/pages/login_screen.dart';
import 'package:lubrication_indicator/features/dashboard/data/repositories/dashboard_stats_repository.dart';
import 'package:lubrication_indicator/features/home/presentation/pages/home_screen.dart';
import 'package:lubrication_indicator/features/readings/data/models/reading_model.dart';
import 'package:lubrication_indicator/features/readings/data/repositories/reading_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_model.dart';
import 'package:lubrication_indicator/features/tanks/data/models/tank_node_model.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_repository.dart';
import 'package:lubrication_indicator/features/tanks/data/repositories/tank_tree_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final ts = DateTime.now().millisecondsSinceEpoch;

  var tcCount = 0;
  String tcNo(int n) => n.toString().padLeft(3, '0');

  Future<void> tc(String label, FutureOr<bool> Function() probe) async {
    tcCount += 1;
    final id = tcNo(tcCount);
    try {
      final ok = await probe();
      if (ok) {
        print('[TC-$id] PASS - $label');
      } else {
        print('[TC-$id] FAIL - $label');
      }
      expect(ok, isTrue, reason: '[TC-$id] $label');
    } catch (e) {
      print('[TC-$id] FAIL - $label | $e');
      fail('[TC-$id] $label | $e');
    }
  }

  List<Map<String, dynamic>> buildProps({bool multi = false}) => [
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
          'constraints': multi
              ? [
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
                  }
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
          'id': 'consumption',
          'label': 'Consumption',
          'type': 'number',
          'required': true,
          'autofill': true,
          'autofill_expression': r'${oil_level}-${oil_level__last}',
        },
      ];

  ClientModel? client;
  UserModel? adminUser;
  UserModel? user;
  TankModel? tankA;
  TankModel? tankB;
  TankNode? folderRoot;
  TankNode? folderChild;
  TankNode? leafA;
  ReadingModel? r1;
  ReadingModel? r2;
  ReadingModel? r3;
  AlertModel? alert1;
  AlertModel? alert2;

  final createdUserIds = <String>[];

  setUpAll(() async {
    print('[QA] setUpAll: load env');
    await dotenv.load(fileName: '.env/.env');

    print('[QA] setUpAll: Firebase init');
    await Firebase.initializeApp(options: FirebaseEnvOptions.currentPlatform);

    print('[QA] setUpAll: DB mode init');
    await DatabaseModeService.init();
    await DatabaseModeService.setDevelopment(true);
    await DatabaseModeService.setClientScope(null);
    await ClientContextService.clearActiveClient();
  });

  tearDownAll(() async {
    print('[QA] tearDownAll: cleanup');
    try {
      if (client != null) {
        await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}').remove();
        await FirebaseDatabase.instance.ref('testDB/clients/${client!.id}').remove();
      }
      for (final uid in createdUserIds) {
        await FirebaseDatabase.instance.ref('testDB/users/$uid').remove();
      }
    } catch (_) {}
  });

  testWidgets(
    'VAPLI real services + UI rigorous suite (100+ testcases)',
    (tester) async {
      final clientRepo = ClientRepository();
      final authRepo = AuthRepository();
      final tankRepo = TankRepository();
      final treeRepo = TankTreeRepository();
      final readingRepo = ReadingRepository();
      final statsRepo = DashboardStatsRepository();
      final alertRepo = AlertRepository();

      print('[UI-PREVIEW] Pumping LoginScreen first so UI is visible immediately');
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(seconds: 8));

      print('[FEATURE-1] Core logic');
      await tc('extractIds returns 2 variables', () async {
        final ids = ExpressionEngine.extractIds(r'${oil_level}-${oil_level__last}');
        return ids.length == 2;
      });
      await tc('extractIds includes oil_level', () async =>
          ExpressionEngine.extractIds(r'${oil_level}-${oil_level__last}').contains('oil_level'));
      await tc('extractIds includes oil_level__last', () async =>
          ExpressionEngine.extractIds(r'${oil_level}-${oil_level__last}').contains('oil_level__last'));
      await tc('expression subtraction works', () async {
        final v = ExpressionEngine.evaluate(r'${oil_level}-${oil_level__last}', variables: {
          'oil_level': 48,
          'oil_level__last': 55,
        });
        return (v + 7).abs() < 0.001;
      });
      await tc('expression precedence works', () async {
        final v = ExpressionEngine.evaluate(r'(${a}+${b})*${c}', variables: {
          'a': 2,
          'b': 3,
          'c': 4,
        });
        return (v - 20).abs() < 0.001;
      });
      await tc('expression division works', () async {
        final v = ExpressionEngine.evaluate(r'${x}/${y}', variables: {'x': 10, 'y': 2});
        return (v - 5).abs() < 0.001;
      });
      await tc('missing variable throws', () async {
        try {
          ExpressionEngine.evaluate(r'${x}+${y}', variables: {'x': 1});
          return false;
        } catch (_) {
          return true;
        }
      });
      await tc('hashPassword non-empty', () async => HashUtil.hashPassword('Admin@123').isNotEmpty);
      await tc('verifyPassword true on correct secret', () async {
        final h = HashUtil.hashPassword('Admin@123');
        return HashUtil.verifyPassword('Admin@123', h);
      });
      await tc('verifyPassword false on wrong secret', () async {
        final h = HashUtil.hashPassword('Admin@123');
        return !HashUtil.verifyPassword('wrong', h);
      });
      await tc('scoped path for tanks', () async {
        await DatabaseModeService.setClientScope('scope_x');
        return DatabaseModeService.path('tanks/t1') == 'testDB/scope_x/tanks/t1';
      });
      await tc('global users path is not client scoped', () async {
        return DatabaseModeService.path('users/u1') == 'testDB/users/u1';
      });

      print('[FEATURE-2] Client + Auth');
      client = await clientRepo.createClient(
        name: 'QA Client $ts',
        description: 'Rigorous test client',
      );
      await tc('client created with id', () async => client!.id.isNotEmpty);
      await tc('client created with dbKey', () async => client!.dbKey.isNotEmpty);
      await tc('client listed in getAllClients', () async {
        final all = await clientRepo.getAllClients();
        return all.any((c) => c.id == client!.id);
      });
      await tc('client meta node exists', () async {
        final snap = await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}/meta').get();
        return snap.exists;
      });
      await tc('client bootstrap users exists', () async {
        final snap = await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}/users').get();
        return snap.exists;
      });
      await tc('client bootstrap session settings exists', () async {
        final snap = await FirebaseDatabase.instance.ref('testDB/${client!.dbKey}/system_settings/session').get();
        return snap.exists;
      });
      await tc('set active client context', () async {
        await ClientContextService.setActiveClient(client!);
        final active = await ClientContextService.getActiveClient();
        return active?.id == client!.id;
      });
      await tc('set DB client scope', () async {
        await DatabaseModeService.setClientScope(client!.dbKey);
        return DatabaseModeService.activeClientId.value == client!.dbKey;
      });

      adminUser = await authRepo.createUser(
        username: 'qa_admin_$ts',
        fullName: 'QA Admin',
        password: 'Admin@123',
        role: AccessControlService.roleAdmin,
        clientIds: [client!.id],
      );
      createdUserIds.add(adminUser!.id);
      await tc('admin user created', () async => adminUser!.id.isNotEmpty);

      user = await authRepo.createUser(
        username: 'qa_user_$ts',
        fullName: 'QA User',
        password: 'User@123',
        role: AccessControlService.roleUser,
        clientIds: [client!.id],
      );
      createdUserIds.add(user!.id);
      await tc('regular user created', () async => user!.id.isNotEmpty);

      await tc('login succeeds with correct credentials', () async {
        final u = await authRepo.login('qa_user_$ts', 'User@123');
        return u.id == user!.id;
      });

      await tc('login fails with wrong password', () async {
        try {
          await authRepo.login('qa_user_$ts', 'Wrong@123');
          return false;
        } catch (_) {
          return true;
        }
      });

      print('[FEATURE-3] Tank Repository');
      tankA = await tankRepo.createTank(
        tankCode: 'TK-A-$ts',
        tankName: 'Hydraulic A $ts',
        location: 'Plant-1/Line-1',
        scaleMax: 200,
        createdBy: adminUser!.id,
        properties: buildProps(multi: false),
      );
      await tc('tank A created', () async => tankA!.id.isNotEmpty);
      await tc('tank A has 6 properties', () async => tankA!.inspectionProperties.length == 6);
      await tc('tank A has keep_previous_capture', () async {
        final p = tankA!.inspectionProperties.firstWhere((e) => e['id'] == 'oil_level');
        return p['keep_previous_capture'] == true;
      });

      tankB = await tankRepo.createTank(
        tankCode: 'TK-B-$ts',
        tankName: 'Hydraulic B $ts',
        location: 'Plant-1/Line-2',
        scaleMax: 300,
        createdBy: adminUser!.id,
        properties: buildProps(multi: true),
      );
      await tc('tank B created', () async => tankB!.id.isNotEmpty);
      await tc('tank B has multi constraints', () async {
        final p = tankB!.inspectionProperties.firstWhere((e) => e['id'] == 'oil_temp');
        final c = List<dynamic>.from(p['constraints'] as List);
        return c.length == 2;
      });
      await tc('getAllTanks contains tank A', () async {
        final all = await tankRepo.getAllTanks();
        return all.any((t) => t.id == tankA!.id);
      });
      await tc('getAllTanks contains tank B', () async {
        final all = await tankRepo.getAllTanks();
        return all.any((t) => t.id == tankB!.id);
      });
      await tc('getTankById returns tank A', () async {
        final t = await tankRepo.getTankById(tankA!.id);
        return t != null && t.id == tankA!.id;
      });
      await tc('updateTank updates name/location', () async {
        await tankRepo.updateTank(
          id: tankA!.id,
          tankCode: tankA!.tankCode,
          tankName: 'Hydraulic A Updated $ts',
          location: 'Plant-1/Line-X',
          scaleMax: 220,
          properties: tankA!.inspectionProperties,
        );
        final t = await tankRepo.getTankById(tankA!.id);
        tankA = t;
        return t != null && t.tankName.contains('Updated') && (t.location ?? '').contains('Line-X');
      });
      await tc('updated tank scale reflects new value', () async => (tankA?.scaleMax ?? 0) == 220);
      await tc('tank uniqueKey generated', () async => tankA!.uniqueKey.isNotEmpty);

      print('[FEATURE-4] Tank Tree Repository');
      folderRoot = await treeRepo.createFolder(name: 'QA Root $ts');
      await tc('root folder created', () async => folderRoot!.isFolder);
      await tc('root folder has null parent', () async => folderRoot!.parentId == null);

      folderChild = await treeRepo.createFolder(name: 'QA Child $ts', parentId: folderRoot!.id);
      await tc('child folder created', () async => folderChild!.isFolder);
      await tc('child folder parent set', () async => folderChild!.parentId == folderRoot!.id);

      leafA = await treeRepo.createLeaf(
        name: tankA!.tankName,
        tankId: tankA!.id,
        parentId: folderChild!.id,
      );
      await tc('leaf created', () async => leafA!.isLeaf);
      await tc('leaf links tank A id', () async => leafA!.tankId == tankA!.id);
      await tc('fetchNode returns leaf', () async {
        final n = await treeRepo.fetchNode(leafA!.id);
        return n != null && n.id == leafA!.id;
      });
      await tc('fetchAll contains all created nodes', () async {
        final all = await treeRepo.fetchAll();
        return all.any((n) => n.id == folderRoot!.id) &&
            all.any((n) => n.id == folderChild!.id) &&
            all.any((n) => n.id == leafA!.id);
      });
      await tc('countChildren on root >= 1', () async {
        final c = await treeRepo.countChildren(folderRoot!.id);
        return c >= 1;
      });
      await tc('fetchSubtree includes root and descendants', () async {
        final sub = await treeRepo.fetchSubtree(folderRoot!.id);
        final ids = sub.map((e) => e.id).toSet();
        return ids.contains(folderRoot!.id) && ids.contains(folderChild!.id) && ids.contains(leafA!.id);
      });
      await tc('moveNode to root works', () async {
        await treeRepo.moveNode(nodeId: leafA!.id, newParentId: folderRoot!.id);
        final moved = await treeRepo.fetchNode(leafA!.id);
        leafA = moved;
        return moved != null && moved.parentId == folderRoot!.id;
      });
      await tc('reorderNodes writes sibling order', () async {
        await treeRepo.reorderNodes([folderChild!.id, leafA!.id]);
        final all = await treeRepo.fetchAll();
        final map = {for (final n in all) n.id: n};
        return (map[folderChild!.id]?.order ?? -1) == 0 && (map[leafA!.id]?.order ?? -1) == 1;
      });

      print('[FEATURE-5] Reading Repository');
      r1 = await readingRepo.saveReading(
        tankId: tankA!.id,
        tankName: tankA!.tankName,
        level: 0,
        capturedBy: user!.id,
        capturedByName: user!.fullName,
        inspectionValues: {
          'Oil Level': 55.0,
          'Oil Temp': 80.0,
          'Vibration': 20.0,
          'Condition': 'Good',
          'Pressure': {'left': 12.0, 'right': 8.0},
          'Consumption': 55.0,
        },
      );
      await tc('reading r1 created', () async => r1!.id.isNotEmpty);
      await tc('reading r1 stores tank id', () async => r1!.tankId == tankA!.id);
      await tc('reading r1 source manual', () async => r1!.source == 'manual');
      await tc('reading r1 has inspection values', () async => r1!.inspectionValues.isNotEmpty);
      await tc('reading r1 has dual_text map', () async => r1!.inspectionValues['Pressure'] is Map);

      r2 = await readingRepo.saveReading(
        tankId: tankA!.id,
        tankName: tankA!.tankName,
        level: 0,
        capturedBy: user!.id,
        capturedByName: user!.fullName,
        inspectionValues: {
          'Oil Level': 48.0,
          'Oil Temp': 95.0,
          'Vibration': 40.0,
          'Condition': 'Monitor',
          'Pressure': {'left': 11.0, 'right': 7.0},
          'Consumption': -7.0,
        },
      );
      await tc('reading r2 created', () async => r2!.id.isNotEmpty);
      await tc('reading r2 condition monitor', () async => r2!.inspectionValues['Condition'] == 'Monitor');
      await tc('reading r2 consumption -7', () async => (r2!.inspectionValues['Consumption'] as num).toDouble() == -7);
      await tc('getAllReadings contains r1', () async {
        final all = await readingRepo.getAllReadings();
        return all.any((r) => r.id == r1!.id);
      });
      await tc('getAllReadings contains r2', () async {
        final all = await readingRepo.getAllReadings();
        return all.any((r) => r.id == r2!.id);
      });
      await tc('getReadingsInRange returns >=2 for tank A', () async {
        final from = DateTime.now().subtract(const Duration(days: 1));
        final to = DateTime.now().add(const Duration(days: 1));
        final list = await readingRepo.getReadingsInRange(tankId: tankA!.id, from: from, to: to);
        return list.length >= 2;
      });

      print('[FEATURE-6] Dashboard Stats Repository');
      await statsRepo.updateStatsAfterReading(reading: r1!, tank: tankA!);
      await statsRepo.updateStatsAfterReading(reading: r2!, tank: tankA!);
      final s1 = await statsRepo.getStats(tankA!.id);
      await tc('stats count >= 2', () async => s1.count >= 2);
      await tc('stats last reading condition monitor', () async => s1.lastReading['Condition'] == 'Monitor');
      await tc('stats has Oil Level param', () async => s1.paramStats.containsKey('Oil Level'));
      await tc('stats Oil Level min <= 48', () async => (s1.paramStats['Oil Level']?.min ?? 999) <= 48);
      await tc('stats Oil Level max >= 55', () async => (s1.paramStats['Oil Level']?.max ?? -1) >= 55);
      await tc('stats has Condition param', () async => s1.paramStats.containsKey('Condition'));
      await tc('stats Condition option count Monitor >=1', () async =>
          (s1.paramStats['Condition']?.optionCounts['Monitor'] ?? 0) >= 1);
      await tc('stats has Pressure param', () async => s1.paramStats.containsKey('Pressure'));
      await tc('stats Pressure dual left exists', () async =>
          s1.paramStats['Pressure']?.dualLeftStats != null);
      await tc('stats Pressure dual right exists', () async =>
          s1.paramStats['Pressure']?.dualRightStats != null);
      await tc('watchStats emits data', () async {
        final first = await statsRepo.watchStats(tankA!.id).first.timeout(const Duration(seconds: 10));
        return first.count >= 2;
      });
      await tc('stats model has lastCapturedBy', () async => (s1.lastCapturedBy ?? '').isNotEmpty);

      print('[FEATURE-7] Alert Repository');
      alert1 = await alertRepo.createAlert(
        tankId: tankA!.id,
        tankCode: tankA!.tankCode,
        tankName: tankA!.tankName,
        tankLocation: tankA!.location,
        tankPath: leafA?.path,
        readingId: r2!.id,
        capturedBy: user!.id,
        capturedByName: user!.fullName,
        capturedAt: r2!.capturedAt,
        constraint: {
          'id': 'warn_90',
          'op': '>',
          'value': '90',
          'severity': 'warning',
          'show_dashboard_alert': true,
          'block_submission': false,
          'store_history': true,
        },
        constraintLabel: 'Oil Temp',
        violatedValue: '95.0',
        lastInspectionValues: Map<String, dynamic>.from(r2!.inspectionValues),
      );
      await tc('alert1 created', () async => alert1!.id.isNotEmpty);
      await tc('alert1 severity warning', () async => alert1!.constraintSeverity == 'warning');
      await tc('alert1 links reading r2', () async => alert1!.readingId == r2!.id);
      await tc('alert1 unresolved initially', () async => !alert1!.resolved);
      await tc('active dashboard alerts include alert1', () async {
        final active = await alertRepo.getActiveDashboardAlerts();
        return active.any((a) => a.id == alert1!.id);
      });

      alert2 = await alertRepo.createAlert(
        tankId: tankB!.id,
        tankCode: tankB!.tankCode,
        tankName: tankB!.tankName,
        readingId: 'virtual_reading_$ts',
        capturedBy: adminUser!.id,
        capturedByName: adminUser!.fullName,
        capturedAt: DateTime.now().toIso8601String(),
        constraint: {
          'id': 'crit_100',
          'op': '>',
          'value': '100',
          'severity': 'critical',
          'show_dashboard_alert': true,
          'block_submission': true,
          'store_history': true,
        },
        constraintLabel: 'Oil Temp',
        violatedValue: '110.0',
        lastInspectionValues: {'Oil Temp': 110.0},
      );
      await tc('alert2 created', () async => alert2!.id.isNotEmpty);
      await tc('alert2 severity critical', () async => alert2!.constraintSeverity == 'critical');
      await tc('alert2 block_submission true', () async => alert2!.blockSubmission == true);
      await tc('getAll returns alert1 and alert2', () async {
        final all = await alertRepo.getAll();
        final ids = all.map((e) => e.id).toSet();
        return ids.contains(alert1!.id) && ids.contains(alert2!.id);
      });
      await tc('resolve alert1 works', () async {
        await alertRepo.resolveAlert(alertId: alert1!.id, resolvedBy: adminUser!.id);
        final all = await alertRepo.getAll();
        final a = all.firstWhere((e) => e.id == alert1!.id);
        return a.resolved == true;
      });
      await tc('delete alert2 works', () async {
        await alertRepo.deleteAlert(alert2!.id);
        final all = await alertRepo.getAll();
        return !all.any((a) => a.id == alert2!.id);
      });

      print('[FEATURE-8] Settings/Context/Access');
      await tc('set session timeout 45m', () async {
        await AppSettingsService.setSessionTimeout(noTimeout: false, minutes: 45);
        final d = await AppSettingsService.getSessionTimeout();
        return d?.inMinutes == 45;
      });
      await tc('set session no-timeout returns null', () async {
        await AppSettingsService.setSessionTimeout(noTimeout: true, minutes: 45);
        final d = await AppSettingsService.getSessionTimeout();
        return d == null;
      });
      await tc('session timeout clamps min to 1', () async {
        await AppSettingsService.setSessionTimeout(noTimeout: false, minutes: 0);
        final d = await AppSettingsService.getSessionTimeout();
        return d?.inMinutes == 1;
      });
      await tc('session timeout clamps max to 1440', () async {
        await AppSettingsService.setSessionTimeout(noTimeout: false, minutes: 99999);
        final d = await AppSettingsService.getSessionTimeout();
        return d?.inMinutes == 1440;
      });
      await tc('client context returns active client', () async {
        final c = await ClientContextService.getActiveClient();
        return c?.id == client!.id;
      });
      await tc('default privileges for admin include create_tanks', () async {
        final p = AccessControlService.defaultPrivilegesForRole('admin');
        return p[AccessControlService.pCreateTanks] == true;
      });
      await tc('default privileges for user empty', () async {
        final p = AccessControlService.defaultPrivilegesForRole('user');
        return p.isEmpty;
      });
      await tc('canManage: super admin > admin', () async {
        final sa = UserModel(
          id: 'sa_cmp_$ts',
          username: 'sa_cmp_$ts',
          fullName: 'SA CMP',
          passwordHash: HashUtil.hashPassword('x'),
          role: AccessControlService.roleSuperAdmin,
          createdAt: DateTime.now().toIso8601String(),
        );
        return AccessControlService.canManage(sa, adminUser!);
      });
      await tc('isAdminLike for admin true', () async => AccessControlService.isAdminLike(adminUser));
      await tc('isAdminLike for user false', () async => !AccessControlService.isAdminLike(user));
      await tc('path empty resolves to testDB root', () async => DatabaseModeService.path('') == 'testDB');
      await tc('client scope clear works', () async {
        await DatabaseModeService.setClientScope(null);
        final p = DatabaseModeService.path('tanks/t1');
        await DatabaseModeService.setClientScope(client!.dbKey);
        return p == 'testDB/tanks/t1';
      });

      print('[FEATURE-9] UI Testing (Login flow widgets)');
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tc('LoginScreen renders', () async => find.byType(LoginScreen).evaluate().isNotEmpty);
      await tc('Sign In title visible', () async => find.text('Sign In').evaluate().isNotEmpty);
      await tc('client search field visible', () async =>
          find.text('Client Search (min 3 chars)').evaluate().isNotEmpty);
      await tc('username field visible', () async => find.text('Username').evaluate().isNotEmpty);
      await tc('password field visible', () async => find.text('Password').evaluate().isNotEmpty);
      await tc('at least 3 text fields present', () async => find.byType(TextFormField).evaluate().length >= 3);
      await tc('Sign In button visible', () async => find.widgetWithText(ElevatedButton, 'Sign In').evaluate().isNotEmpty);

      await tester.enterText(find.byType(TextFormField).at(0), 'QA');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      await tc('No client list shown for <3 chars', () async => find.byType(ListTile).evaluate().isEmpty);

      await tester.enterText(find.byType(TextFormField).at(0), 'QA Client');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tc('Client suggestion appears for >=3 chars', () async =>
          find.byType(ListTile).evaluate().isNotEmpty);

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      await tc('Client selection check icon appears', () async =>
          find.byIcon(Icons.check_circle).evaluate().isNotEmpty);

      await tester.enterText(find.byType(TextFormField).at(1), 'qa_user_$ts');
      await tester.enterText(find.byType(TextFormField).at(2), 'User@123');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tc('Entered username is reflected', () async {
        final field = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
        return field.controller?.text == 'qa_user_$ts';
      });

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await tc('Login navigates away from LoginScreen', () async =>
          find.byType(LoginScreen).evaluate().isEmpty || find.byType(HomeScreen).evaluate().isNotEmpty);

      print('[FEATURE-10] End-to-end combined checks');
      await DatabaseModeService.setClientScope(client!.dbKey);
      r3 = await readingRepo.saveReading(
        tankId: tankA!.id,
        tankName: tankA!.tankName,
        level: 0,
        capturedBy: user!.id,
        capturedByName: user!.fullName,
        inspectionValues: {
          'Oil Level': 46.0,
          'Oil Temp': 88.0,
          'Vibration': 30.0,
          'Condition': 'Good',
          'Pressure': {'left': 10.0, 'right': 6.0},
          'Consumption': -2.0,
        },
      );
      await tc('r3 created for end-to-end', () async => r3!.id.isNotEmpty);

      await statsRepo.updateStatsAfterReading(reading: r3!, tank: tankA!);
      await tc('stats count increases after r3', () async {
        final s = await statsRepo.getStats(tankA!.id);
        return s.count >= 3;
      });

      await tc('alert1 stays resolved', () async {
        final all = await alertRepo.getAll();
        final a = all.firstWhere((e) => e.id == alert1!.id);
        return a.resolved;
      });
      await tc('tank tree leaf still links tank A after moves', () async {
        final n = await treeRepo.fetchNode(leafA!.id);
        return n != null && n.tankId == tankA!.id;
      });
      await tc('getReadingsInRange still includes r3', () async {
        final from = DateTime.now().subtract(const Duration(days: 1));
        final to = DateTime.now().add(const Duration(days: 1));
        final list = await readingRepo.getReadingsInRange(tankId: tankA!.id, from: from, to: to);
        return list.any((e) => e.id == r3!.id);
      });
      await tc('can() grants admin modify_tanks', () async =>
          AccessControlService.can(adminUser, AccessControlService.pModifyTanks));
      await tc('can() denies user modify_tanks by default', () async =>
          !AccessControlService.can(user, AccessControlService.pModifyTanks));
      await tc('client context still points to created client', () async {
        final c = await ClientContextService.getActiveClient();
        return c?.id == client!.id;
      });
      await tc('DatabaseModeService scoped readings path valid', () async =>
          DatabaseModeService.path('readings/${r3!.id}').contains(client!.dbKey));
      await tc('all users include admin and regular user', () async {
        final users = await authRepo.getAllUsers();
        final ids = users.map((e) => e.id).toSet();
        return ids.contains(adminUser!.id) && ids.contains(user!.id);
      });
      await tc('all tanks include tank A and tank B', () async {
        final tanks = await tankRepo.getAllTanks();
        final ids = tanks.map((e) => e.id).toSet();
        return ids.contains(tankA!.id) && ids.contains(tankB!.id);
      });
      await tc('final stats carries Oil Temp param', () async {
        final s = await statsRepo.getStats(tankA!.id);
        return s.paramStats.containsKey('Oil Temp');
      });

      print('[QA] Total testcases executed: $tcCount');
      expect(tcCount, greaterThanOrEqualTo(110), reason: 'Need 100+ rigorous testcases');
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
