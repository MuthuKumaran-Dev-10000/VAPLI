import 'package:firebase_database/firebase_database.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/hash_util.dart';
import '../../core/utils/session_manager.dart';
import '../models/user_model.dart';

class AuthRepository {
  final _db = FirebaseDatabase.instance.ref();

  Future<UserModel> login(String username, String password) async {
    final snap = await _db
        .child(AppConstants.usersPath)
        .orderByChild('username')
        .equalTo(username)
        .get();

    if (!snap.exists) throw Exception('User not found');

    final data = Map<String, dynamic>.from(
      (snap.value as Map).values.first as Map,
    );
    final user = UserModel.fromMap(data);

    if (!user.isActive) throw Exception('Account is deactivated');

    // Check lock
    if (user.lockedUntil != null) {
      final lockTime = DateTime.parse(user.lockedUntil!);
      if (DateTime.now().isBefore(lockTime)) {
        throw Exception('Account locked until ${lockTime.toLocal()}');
      }
    }

    if (!HashUtil.verifyPassword(password, user.passwordHash)) {
      // Increment failed attempts
      final attempts = user.failedLoginAttempts + 1;
      String? lockUntil;
      if (attempts >= 5) {
        lockUntil =
            DateTime.now().add(const Duration(minutes: 30)).toIso8601String();
      }
      await _db.child('${AppConstants.usersPath}/${user.id}').update({
        'failed_login_attempts': attempts,
        if (lockUntil != null) 'locked_until': lockUntil,
      });
      throw Exception('Invalid password');
    }

    // Reset failed attempts & update last login
    final updatedUser = UserModel.fromMap({
      ...user.toMap(),
      'failed_login_attempts': 0,
      'locked_until': null,
      'last_login_at': DateTime.now().toIso8601String(),
    });

    await _db.child('${AppConstants.usersPath}/${user.id}').update({
      'failed_login_attempts': 0,
      'locked_until': null,
      'last_login_at': DateTime.now().toIso8601String(),
    });

    await SessionManager.saveSession(updatedUser);
    return updatedUser;
  }

  Future<void> logout() async {
    await SessionManager.clearSession();
  }

  Future<UserModel> createUser({
    required String username,
    required String fullName,
    required String password,
    String role = 'user',
    String? phone,
    String? email,
  }) async {
    // Check duplicate username
    final existing = await _db
        .child(AppConstants.usersPath)
        .orderByChild('username')
        .equalTo(username)
        .get();
    if (existing.exists) throw Exception('Username already exists');

    final id = HashUtil.generateId();
    final user = UserModel(
      id: id,
      username: username,
      fullName: fullName,
      passwordHash: HashUtil.hashPassword(password),
      role: role,
      phone: phone,
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );

    await _db.child('${AppConstants.usersPath}/$id').set(user.toMap());
    return user;
  }

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _db.child(AppConstants.usersPath).get();
    if (!snap.exists) return [];
    final map = Map<String, dynamic>.from(snap.value as Map);
    return map.values
        .map((v) => UserModel.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
  }
}
