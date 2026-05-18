import 'package:flutter/material.dart';

import '../../../data/repositories/auth_repository.dart';

import 'admin_dashboard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminLoginScreen  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user =
          await AuthRepository().login(_userCtrl.text.trim(), _passCtrl.text);
      if (user.role != 'admin') throw Exception('Not an admin account');
      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => AdminDashboard(adminName: user.fullName)));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 16),
          TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password')),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _login,
            child: Text(_loading ? 'Loading…' : 'Login'),
          ),
        ]),
      ),
    );
  }
}
