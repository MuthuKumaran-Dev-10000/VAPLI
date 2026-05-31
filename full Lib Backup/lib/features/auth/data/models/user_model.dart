class UserModel {
  final String id;
  final String username;
  final String fullName;
  final String passwordHash;
  final String role; // 'super admin' | 'admin' | 'user'
  final String? phone;
  final String? email;
  final Map<String, bool> privileges;
  final List<String> clientIds;
  final int failedLoginAttempts;
  final String? lockedUntil;
  final bool isActive;
  final String? lastLoginAt;
  final String createdAt;

  UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.passwordHash,
    required this.role,
    this.phone,
    this.email,
    this.privileges = const {},
    this.clientIds = const [],
    this.failedLoginAttempts = 0,
    this.lockedUntil,
    this.isActive = true,
    this.lastLoginAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'password_hash': passwordHash,
        'role': role,
        'phone': phone,
        'email': email,
        'privileges': privileges,
        'client_ids': clientIds,
        'failed_login_attempts': failedLoginAttempts,
        'locked_until': lockedUntil,
        'is_active': isActive,
        'last_login_at': lastLoginAt,
        'created_at': createdAt,
      };

  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
        id: m['id'] ?? '',
        username: m['username'] ?? '',
        fullName: m['full_name'] ?? '',
        passwordHash: m['password_hash'] ?? '',
        role: m['role'] ?? 'user',
        phone: m['phone'],
        email: m['email'],
        privileges: ((m['privileges'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v == true)),
        clientIds: ((m['client_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(),
        failedLoginAttempts: m['failed_login_attempts'] ?? 0,
        lockedUntil: m['locked_until'],
        isActive: m['is_active'] ?? true,
        lastLoginAt: m['last_login_at'],
        createdAt: m['created_at'] ?? DateTime.now().toIso8601String(),
      );
}
