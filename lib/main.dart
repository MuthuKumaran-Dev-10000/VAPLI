import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/services/database_mode_service.dart';
import 'core/services/firebase_env_options.dart';
import 'core/utils/session_manager.dart';
import 'features/auth/presentation/pages/login_screen.dart';
import 'features/home/presentation/pages/home_screen.dart';


import 'package:firebase_database/firebase_database.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env/.env');
  await DatabaseModeService.init();
  await Firebase.initializeApp(options: FirebaseEnvOptions.currentPlatform);
  await createTestAdmin();
  runApp(const LubeMonitorApp());
}

Future<void> createTestAdmin() async {
  final db = FirebaseDatabase.instance.ref();

  const userId = '1778303550928-4e2cb223';

  final userData = {
    'created_at': '2026-05-09T05:12:30.942719',
    'failed_login_attempts': 0,
    'full_name': 'System Administrator',
    'id': userId,
    'is_active': true,
    'last_login_at': '2026-05-22T14:28:27.636841',
    'password_hash':
        '7d20f317b9e34c36747cf8275645ab8fe145e29b70f3722a6fcd7d0cff2cd0c8',
    'role': 'admin',
    'username': 'admin',
  };

  await db.child('testDB/users/$userId').set(userData);

  print('✅ Admin user copied to testDB/users');
}

class LubeMonitorApp extends StatelessWidget {
  const LubeMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lube Monitor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});
  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final valid = await SessionManager.isSessionValid();
    if (!valid && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SessionManager.isSessionValid(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
            ),
          );
        }
        if (snap.data == true) return const HomeScreen();
        return const LoginScreen();
      },
    );
  }
}
