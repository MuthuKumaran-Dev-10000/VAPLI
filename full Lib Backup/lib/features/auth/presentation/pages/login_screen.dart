import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/app_settings_service.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/core/services/client_repository.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/utils/session_manager.dart';
import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/auth/presentation/controllers/auth_controller.dart';
import 'package:lubrication_indicator/features/auth/presentation/widgets/auth_brand_header.dart';
import 'package:lubrication_indicator/features/auth/presentation/widgets/login_error_banner.dart';
import 'package:lubrication_indicator/features/home/presentation/pages/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _clientSearchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authController = AuthController();
  final _clientRepo = ClientRepository();

  bool _loading = false;
  bool _loadingClients = true;
  bool _obscure = true;
  String? _error;
  String _sessionLabel = 'Session timeout loading...';
  List<ClientModel> _clients = [];
  ClientModel? _selectedClient;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
    _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final all = await _clientRepo.getAllClients();
      final lastUsed = await ClientContextService.getLastUsedClient();
      ClientModel? selected;
      if (lastUsed != null) {
        for (final c in all) {
          if (c.id == lastUsed.id || c.dbKey == lastUsed.dbKey) {
            selected = c;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _clients = all;
        _selectedClient = selected;
        if (selected != null) {
          _clientSearchCtrl.text = selected.name;
        }
        _loadingClients = false;
      });
      await _loadSessionLabel();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingClients = false);
      await _loadSessionLabel();
    }
  }

  Future<void> _loadSessionLabel() async {
    try {
      if (_selectedClient != null) {
        await DatabaseModeService.setClientScope(_selectedClient!.dbKey);
      } else if (_clients.isEmpty) {
        await DatabaseModeService.setClientScope(null);
      }

      final timeout = await AppSettingsService.getSessionTimeout();
      if (!mounted) return;
      setState(() {
        if (timeout == null) {
          _sessionLabel = 'No session timeout';
          return;
        }
        final mins = timeout.inMinutes;
        if (mins >= 1440) {
          _sessionLabel = 'Session expires after 1 day of inactivity';
        } else {
          _sessionLabel = 'Session expires after $mins minutes of inactivity';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sessionLabel = 'Session timeout based on settings';
      });
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _clientSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_clients.isEmpty) {
        final u = _usernameCtrl.text.trim().toLowerCase();
        final p = _passwordCtrl.text.trim();
        if (u != 'admin' || p != 'Admin@123') {
          throw Exception('Only root admin can login before clients are created');
        }
        await DatabaseModeService.setClientScope(null);
        await ClientContextService.clearActiveClient();
        final rootUser = UserModel(
          id: 'root-admin',
          username: 'admin',
          fullName: 'System Administrator',
          passwordHash: '',
          role: 'super admin',
          privileges: const {
            'create_client': true,
            'create_users': true,
            'grant_users': true,
            'create_tanks': true,
            'delete_tanks': true,
            'modify_tanks': true,
            'allocate_users_to_clients': true,
            'open_admin_page': true,
          },
          clientIds: const [],
          createdAt: DateTime.now().toIso8601String(),
        );
        await SessionManager.saveSession(rootUser);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
        return;
      }

      if (_selectedClient == null) {
        throw Exception('Select a client first');
      }

      await _clientRepo.ensureClientBootstrap(_selectedClient!);
      await ClientContextService.setActiveClient(_selectedClient!);
      await DatabaseModeService.setClientScope(_selectedClient!.dbKey);

      await _authController.loginUser(
        username: _usernameCtrl.text,
        password: _passwordCtrl.text,
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _error = _authController.toDisplayError(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _clientSearchCtrl.text.trim().toLowerCase();
    final matched = q.length < 3
        ? const <ClientModel>[]
        : _clients.where((c) => c.name.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AuthBrandHeader(),
                    const SizedBox(height: 48),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sign In',
                              style: GoogleFonts.inter(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20)),
                          const SizedBox(height: 12),
                          if (_loadingClients) const LinearProgressIndicator(),
                          if (!_loadingClients && _clients.isNotEmpty) ...[
                            TextFormField(
                              controller: _clientSearchCtrl,
                              style:
                                  const TextStyle(color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Client Search (min 3 chars)',
                                prefixIcon: Icon(Icons.search,
                                    color: AppColors.textSecondary),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (q.length >= 3) ...[
                              const SizedBox(height: 8),
                              ...matched.map((c) => ListTile(
                                    dense: true,
                                    title: Text(c.name),
                                    subtitle: Text(c.description),
                                    trailing: _selectedClient?.id == c.id
                                        ? const Icon(Icons.check_circle,
                                            color: Colors.green)
                                        : null,
                                    onTap: () async {
                                      setState(() {
                                        _selectedClient = c;
                                        _clientSearchCtrl.text = c.name;
                                      });
                                      await ClientContextService.setLastUsedClient(c);
                                      await _loadSessionLabel();
                                    },
                                  )),
                            ],
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _usernameCtrl,
                            style:
                                const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline,
                                  color: AppColors.textSecondary),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Enter username' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            style:
                                const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline,
                                  color: AppColors.textSecondary),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.textSecondary,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Enter password' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            LoginErrorBanner(message: _error!),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text('Sign In',
                                      style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _clients.isEmpty
                          ? 'No clients yet. Use root admin: admin / Admin@123'
                          : _sessionLabel,
                      style: GoogleFonts.inter(
                        color: AppColors.disabled,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
