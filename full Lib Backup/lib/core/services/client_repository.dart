import 'package:lubrication_indicator/core/models/client_model.dart';
import 'package:lubrication_indicator/core/services/access_control_service.dart';
import 'package:lubrication_indicator/core/services/database_mode_service.dart';
import 'package:lubrication_indicator/core/utils/hash_util.dart';
import 'package:firebase_database/firebase_database.dart';

class ClientRepository {
  final _db = DatabaseModeService.ref();
  static const _path = 'clients';
  String _toDbKey(String name) {
    final s = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return s.replaceAll(RegExp(r'^_+|_+$'), '');
  }

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

  Stream<List<ClientModel>> watchClients() {
    return _db.child(_path).onValue.map((event) {
      final map = _safeMap(event.snapshot.value);
      if (map == null) return <ClientModel>[];
      return map.values
          .where((e) => e is Map)
          .map((e) => ClientModel.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((c) => c.isActive)
          .toList();
    });
  }

  Future<List<ClientModel>> getAllClients() async {
    final snap = await _db.child(_path).get();
    final map = _safeMap(snap.value);
    if (map == null) return <ClientModel>[];
    return map.values
        .where((e) => e is Map)
        .map((e) => ClientModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((c) => c.isActive)
        .toList();
  }

  Future<ClientModel> createClient({
    required String name,
    String description = '',
  }) async {
    final id = HashUtil.generateId();
    final dbKey = _toDbKey(name);
    final client = ClientModel(
      id: id,
      name: name.trim(),
      dbKey: dbKey,
      description: description.trim(),
      rootFolderId: null,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _db.child('$_path/$id').set(client.toMap());
    await _db.child('$dbKey/meta').set({
      'client_id': id,
      'name': client.name,
      'description': client.description,
      'created_at': client.createdAt,
    });
    await ensureClientBootstrap(client);
    return client;
  }

  Future<void> ensureClientBootstrap(ClientModel client) async {
    final rootPrefix = DatabaseModeService.isDevelopment.value ? 'testDB/' : '';
    final root = FirebaseDatabase.instance.ref();
    final usersRef = root.child('${rootPrefix}${client.dbKey}/users');
    final usersSnap = await usersRef.get();
    if (!usersSnap.exists || usersSnap.value == null) {
      final uid = HashUtil.generateId();
      await usersRef.child(uid).set({
        'id': uid,
        'username': 'admin',
        'full_name': 'System Administrator',
        'password_hash': HashUtil.hashPassword('Admin@123'),
        'role': AccessControlService.roleSuperAdmin,
        'privileges': AccessControlService.defaultPrivilegesForRole(
            AccessControlService.roleSuperAdmin),
        'client_ids': [client.id],
        'is_active': true,
        'failed_login_attempts': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    final settingsRef =
        root.child('${rootPrefix}${client.dbKey}/system_settings/session');
    final settingsSnap = await settingsRef.get();
    if (!settingsSnap.exists || settingsSnap.value == null) {
      await settingsRef.set({
        'mode': 'minutes',
        'minutes': 60,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
}
