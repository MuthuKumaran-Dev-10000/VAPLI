import 'dart:convert';
import 'package:crypto/crypto.dart';

class HashUtil {
  /// Bcrypt-style hashing using SHA-256 + salt (client-side secure hash)
  static String hashPassword(String password) {
    const salt = 'LubeMonitor_Salt_2024_\$ecure!';
    final salted = '$salt:$password';
    final bytes = utf8.encode(salted);
    final digest = sha256.convert(bytes);
    // Double hash for extra security
    final digest2 = sha256.convert(utf8.encode(digest.toString() + salt));
    return digest2.toString();
  }

  static bool verifyPassword(String password, String hash) {
    return hashPassword(password) == hash;
  }

  static String generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand =
        sha256.convert(utf8.encode(now.toString())).toString().substring(0, 8);
    return '$now-$rand';
  }
}
