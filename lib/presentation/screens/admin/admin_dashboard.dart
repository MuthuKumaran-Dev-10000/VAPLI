import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../../data/models/tank_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/tank_repository.dart';

import 'admin_tank_card.dart';
import 'create_tank_screen_main.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  final String adminName;
  const AdminDashboard({super.key, required this.adminName});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TankModel> _tanks = [];
  List<Map> _users = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  void _load() {
    debugPrint('[Dashboard] _load() — subscribing to tanks + users streams');

    TankRepository().watchTanks().listen((data) {
      debugPrint('[Dashboard] Tanks stream update: ${data.length} tanks');
      if (mounted) setState(() => _tanks = data);
    });

    FirebaseDatabase.instance.ref('users').onValue.listen((event) {
      final users = <Map>[];
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        for (final e in data.entries) {
          users.add({'id': e.key, ...Map<String, dynamic>.from(e.value)});
        }
      }
      debugPrint('[Dashboard] Users stream update: ${users.length} users');
      if (mounted) setState(() => _users = users);
    });
  }

  // ── helpers for duplicate naming ──────────────────────────────────────────

  /// Returns the lowest free "Base (n)" code among existing tanks.
  String _nextFreeCode(String base) {
    final existing = _tanks.map((t) => t.tankCode).toList();
    final stripped = base.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim();
    for (int i = 1; i <= 99; i++) {
      final candidate = '$stripped ($i)';
      if (!existing.contains(candidate)) return candidate;
    }
    return '$stripped (${DateTime.now().millisecondsSinceEpoch})';
  }

  // ── tank actions ──────────────────────────────────────────────────────────

  Future<void> _openCreateTank() async {
    debugPrint('[Dashboard] FAB: open CreateTankScreen (new)');
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateTankScreen()),
    );
    debugPrint('[Dashboard] CreateTankScreen returned ok=$ok');
  }

  Future<void> _deleteTank(String id, String name) async {
    debugPrint('[Dashboard] Deleting tank id=$id name=$name');
    await FirebaseDatabase.instance.ref('tanks/$id').remove();
    debugPrint('[Dashboard] Tank deleted: $id');
  }

  // ── user actions (unchanged) ──────────────────────────────────────────────

  Future<void> _createUser() async {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true, loading = false;
    String? error;
    String role = 'user';

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Create User'),
          content: SizedBox(
            width: 350,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 14),
              TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 14),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    onPressed: () => setDialog(() => obscure = !obscure),
                    icon:
                        Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'user', child: Text('User')),
                ],
                onChanged: (v) => setDialog(() => role = v!),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
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
                  final data = Map<String, dynamic>.from(snapshot.value as Map);
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
                if (mounted) Navigator.pop(context);
              },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(String id) async {
    final snapshot = await FirebaseDatabase.instance.ref('users/$id').get();
    if (!snapshot.exists) return;
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final isRoot = data['username'] == 'admin' &&
        data['full_name'] == 'System Administrator';
    if (isRoot) return;
    await FirebaseDatabase.instance.ref('users/$id').remove();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Tanks'), Tab(text: 'Users')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (_tabController.index == 0) {
            await _openCreateTank();
          } else {
            await _createUser();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── TANKS TAB ─────────────────────────────────────────────────────
          _tanks.isEmpty
              ? const Center(child: Text('No tanks yet. Tap + to create one.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _tanks.length,
                  itemBuilder: (_, i) {
                    final tank = _tanks[i];
                    return TankAdminCard(
                      tank: tank,
                      allTankCodes: _tanks.map((t) => t.tankCode).toList(),
                      nextFreeCode: _nextFreeCode,
                      onDelete: () {
                        debugPrint(
                            '[Dashboard] onDelete callback for ${tank.id}');
                        _deleteTank(tank.id, tank.tankName);
                      },
                    );
                  },
                ),

          // ── USERS TAB (unchanged) ─────────────────────────────────────────
          ListView.builder(
            itemCount: _users.length,
            itemBuilder: (_, i) {
              final user = _users[i];
              final isRoot = user['username'] == 'admin' &&
                  user['full_name'] == 'System Administrator';
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(user['full_name']),
                subtitle: Text('${user['username']} • ${user['role']}'),
                trailing: isRoot
                    ? null
                    : IconButton(
                        onPressed: () => _deleteUser(user['id']),
                        icon: const Icon(Icons.delete, color: Colors.red),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
