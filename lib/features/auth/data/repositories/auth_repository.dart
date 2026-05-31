import 'package:firebase_database/firebase_database.dart';
import 'package:lubrication_indicator/core/constants/app_constants.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/client_context_service.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';
import 'package:lubrication_indicator/core/utils/session_manager.dart';
import '../models/user_model.dart';

class AuthRepository {
  DatabaseReference get _db => DatabaseModeService.ref();
  Map<String, dynamic>? _safeMap(dynamic value) {
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(
        (value as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<UserModel> login(String username, String password) async {
    final snap = await _db
        .child(AppConstants.usersPath)
        .orderByChild('username')
        .equalTo(username)
        .get();

    if (!snap.exists) throw Exception('User not found');

    final root = _safeMap(snap.value);
    if (root == null || root.isEmpty) throw Exception('User not found');
    final selectedClient = await ClientContextService.getActiveClient();
    final selectedClientId = selectedClient?.id;
    final candidates = <UserModel>[];
    for (final raw in root.values) {
      final data = _safeMap(raw);
      if (data == null) continue;
      final user = UserModel.fromMap(data);
      candidates.add(user);
    }
    if (candidates.isEmpty) throw Exception('User not found');
    final user = (selectedClientId == null || selectedClientId.trim().isEmpty)
        ? candidates.first
        : candidates.firstWhere(
            (u) =>
                u.clientIds.contains(selectedClientId) ||
                u.role.toLowerCase() == AccessControlService.roleSuperAdmin,
            orElse: () => throw Exception('User not found for selected client'),
          );

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
    List<String> clientIds = const [],
    Map<String, bool>? privileges,
    String? phone,
    String? email,
  }) async {
    // Check duplicate username only within same client assignment scope.
    final existing = await _db
        .child(AppConstants.usersPath)
        .orderByChild('username')
        .equalTo(username)
        .get();
    if (existing.exists) {
      final data = Map<String, dynamic>.from(existing.value as Map);
      final target = clientIds.toSet();
      for (final raw in data.values) {
        final m = _safeMap(raw);
        if (m == null) continue;
        final existingIds = ((m['client_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();
        final overlap = target.intersection(existingIds).isNotEmpty;
        final bothGlobal = target.isEmpty && existingIds.isEmpty;
        if (overlap || bothGlobal) {
          throw Exception('Username already exists in this client');
        }
      }
    }

    final id = HashUtil.generateId();
    final user = UserModel(
      id: id,
      username: username,
      fullName: fullName,
      passwordHash: HashUtil.hashPassword(password),
      role: role,
      privileges: AccessControlService.sanitizePrivilegesForRole(
        role,
        privileges ?? AccessControlService.defaultPrivilegesForRole(role),
      ),
      clientIds: clientIds,
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
