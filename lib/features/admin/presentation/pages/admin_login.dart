import 'package:flutter/material.dart';
import 'package:lubrication_indicator/features/admin/presentation/pages/admin_dashboard.dart';
import 'package:lubrication_indicator/features/auth/presentation/controllers/auth_controller.dart';
import 'package:lubrication_indicator/features/auth/presentation/widgets/login_error_banner.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authController = AuthController();

  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await _authController.loginAdmin(
        username: _userCtrl.text,
        password: _passCtrl.text,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboard(adminName: user.fullName),
        ),
      );
    } catch (e) {
      setState(() => _error = _authController.toDisplayError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _userCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter username' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter password' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                LoginErrorBanner(message: _error!),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading
                    ? null
                    : () {
                        if (_formKey.currentState?.validate() ?? false) {
                          _login();
                        }
                      },
                child: Text(_loading ? 'Loading...' : 'Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

