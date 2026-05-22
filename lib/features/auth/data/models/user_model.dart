class UserModel {
  final String id;
  final String username;
  final String fullName;
  final String passwordHash;
  final String role; // 'admin' | 'user'
  final String? phone;
  final String? email;
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
        failedLoginAttempts: m['failed_login_attempts'] ?? 0,
        lockedUntil: m['locked_until'],
        isActive: m['is_active'] ?? true,
        lastLoginAt: m['last_login_at'],
        createdAt: m['created_at'] ?? DateTime.now().toIso8601String(),
      );
}
