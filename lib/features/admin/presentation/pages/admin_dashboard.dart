import 'dart:convert';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lubrication_indicator/features/auth/data/repositories/auth_repository.dart';
import 'package:lubrication_indicator/features/admin/presentation/pages/admin_settings_page.dart';

import 'package:lubrication_indicator/features/tanks/presentation/pages/tank_browser_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  final String adminName;

  const AdminDashboard({
    super.key,
    required this.adminName,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map> _users = [];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 3,
      vsync: this,
    );

    // _tabController.addListener(() {
    //   if (mounted) setState(() {});
    // });

    _load();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Load users only
  // Tanks are handled completely by TankBrowserScreen
  // ───────────────────────────────────────────────────────────────────────────
  void _load() {
    debugPrint('[Dashboard] Loading users...');

    DatabaseModeService.ref('users').onValue.listen((event) {
      final users = <Map>[];

      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(
          event.snapshot.value as Map,
        );

        for (final e in data.entries) {
          users.add({
            'id': e.key,
            ...Map<String, dynamic>.from(e.value),
          });
        }
      }

      debugPrint(
        '[Dashboard] Users stream update: ${users.length}',
      );

      if (mounted) {
        setState(() {
          _users = users;
        });
      }
    });
  }

  Future<void> _exportStructure() async {
    try {
      final tanksSnap = await DatabaseModeService.ref('tanks').get();
      final treeSnap = await DatabaseModeService.ref('tank_tree').get();
      final payload = {
        'exported_at': DateTime.now().toIso8601String(),
        'mode': DatabaseModeService.isDevelopment.value ? 'development' : 'production',
        'tanks': tanksSnap.value ?? <String, dynamic>{},
        'tank_tree': treeSnap.value ?? <String, dynamic>{},
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/vapli_structure_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonStr, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'VAPLI structure export');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Structure exported successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _importStructureDialog() async {
    final ctrl = TextEditingController();
    final pathCtrl = TextEditingController();
    bool replace = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Import Structure JSON'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Paste exported JSON. This imports "tanks" and "tank_tree".',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Paste JSON here',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pathCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Or enter local file path to JSON',
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: replace,
                  onChanged: (v) => setStateDialog(() => replace = v),
                  title: const Text('Replace Existing Data'),
                  subtitle: const Text('If off, only updates imported keys'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  var raw = ctrl.text.trim();
                  if (raw.isEmpty && pathCtrl.text.trim().isNotEmpty) {
                    final file = File(pathCtrl.text.trim());
                    if (!await file.exists()) {
                      throw Exception('File not found');
                    }
                    raw = await file.readAsString();
                  }
                  if (raw.isEmpty) throw Exception('JSON is empty');
                  final decoded = jsonDecode(raw);
                  if (decoded is! Map) throw Exception('Invalid JSON root');
                  final tanks = decoded['tanks'] is Map
                      ? Map<String, dynamic>.from(decoded['tanks'] as Map)
                      : <String, dynamic>{};
                  final tree = decoded['tank_tree'] is Map
                      ? Map<String, dynamic>.from(decoded['tank_tree'] as Map)
                      : <String, dynamic>{};
                  final tanksRef = DatabaseModeService.ref('tanks');
                  final treeRef = DatabaseModeService.ref('tank_tree');
                  if (replace) {
                    await tanksRef.set(tanks);
                    await treeRef.set(tree);
                  } else {
                    await tanksRef.update(tanks);
                    await treeRef.update(tree);
                  }
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Structure imported successfully')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import failed: $e')),
                  );
                }
              },
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Create user (unchanged)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _createUser() async {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    bool obscure = true;
    bool loading = false;

    String role = 'user';
    String? error;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Create User'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialog(() {
                          obscure = !obscure;
                        });
                      },
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField(
                  value: role,
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Admin'),
                    ),
                    DropdownMenuItem(
                      value: 'user',
                      child: Text('User'),
                    ),
                  ],
                  onChanged: (v) {
                    setDialog(() {
                      role = v!;
                    });
                  },
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 12,
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                setDialog(() {
                  loading = true;
                  error = null;
                });

                final snapshot =
                    await DatabaseModeService.ref('users').get();

                if (snapshot.value != null) {
                  final data = Map<String, dynamic>.from(
                    snapshot.value as Map,
                  );

                  for (final u in data.values) {
                    if (u['username'].toString().toLowerCase() ==
                        userCtrl.text.trim().toLowerCase()) {
                      setDialog(() {
                        loading = false;
                        error = 'Username already exists';
                      });

                      return;
                    }
                  }
                }

                await AuthRepository().createUser(
                  username: userCtrl.text,
                  fullName: nameCtrl.text,
                  password: passCtrl.text,
                  role: role,
                );

                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Delete user (unchanged)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _deleteUser(String id) async {
    final snapshot = await DatabaseModeService.ref('users/$id').get();

    if (!snapshot.exists) {
      return;
    }

    final data = Map<String, dynamic>.from(
      snapshot.value as Map,
    );

    final isRoot = data['username'] == 'admin' &&
        data['full_name'] == 'System Administrator';

    if (isRoot) {
      return;
    }

    await DatabaseModeService.ref('users/$id').remove();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
        ),
        actions: _tabController.index == 0
            ? [
                IconButton(
                  tooltip: 'Export Structure',
                  onPressed: _exportStructure,
                  icon: const Icon(Icons.download_rounded),
                ),
                IconButton(
                  tooltip: 'Import Structure',
                  onPressed: _importStructureDialog,
                  icon: const Icon(Icons.upload_rounded),
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) {
            if (mounted) setState(() {});
          },
          tabs: const [
            Tab(
              text: 'Tanks',
            ),
            Tab(
              text: 'Users',
            ),
            Tab(
              text: 'Settings',
            ),
          ],
        ),
      ),

      // Browser has its own +
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () async {
      //     if (_tabController.index == 1) {
      //       await _createUser();
      //     }
      //   },
      //   child: Icon(
      //     _tabController.index == 0 ? Icons.folder : Icons.add,
      //   ),
      // ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: _createUser,
              child: const Icon(Icons.person_add_alt_1),
            )
          : null,

      body: TabBarView(
        controller: _tabController,
        children: [
          // ───────────────────────────────────────────────────────────────────
          // Infinite hierarchical tank browser
          // ───────────────────────────────────────────────────────────────────
          const TankBrowserScreen(),

          // ───────────────────────────────────────────────────────────────────
          // Users tab
          // ───────────────────────────────────────────────────────────────────
          ListView.builder(
            itemCount: _users.length,
            itemBuilder: (_, i) {
              final user = _users[i];

              final isRoot = user['username'] == 'admin' &&
                  user['full_name'] == 'System Administrator';

              return ListTile(
                leading: const Icon(
                  Icons.person,
                ),
                title: Text(
                  user['full_name'],
                ),
                subtitle: Text(
                  '${user['username']} • ${user['role']}',
                ),
                trailing: isRoot
                    ? null
                    : IconButton(
                        onPressed: () {
                          _deleteUser(
                            user['id'],
                          );
                        },
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.red,
                        ),
                      ),
              );
            },
          ),
          const AdminSettingsPage(),
        ],
      ),
    );
  }
}
