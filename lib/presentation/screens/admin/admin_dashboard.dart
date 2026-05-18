import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../../data/repositories/auth_repository.dart';

import 'tank_browser_screen.dart';

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
      length: 2,
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

    FirebaseDatabase.instance.ref('users').onValue.listen((event) {
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
                    await FirebaseDatabase.instance.ref('users').get();

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
    final snapshot = await FirebaseDatabase.instance.ref('users/$id').get();

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

    await FirebaseDatabase.instance.ref('users/$id').remove();
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
        ],
      ),
    );
  }
}
