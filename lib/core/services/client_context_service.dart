import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:lubrication_indicator/core/models/client_model.dart';

class ClientContextService {
  static const _key = 'active_client';
  static const _lastUsedKey = 'last_used_client';

  static Future<void> setActiveClient(ClientModel client) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(client.toMap());
    await prefs.setString(_key, raw);
    await prefs.setString(_lastUsedKey, raw);
  }

  static Future<ClientModel?> getActiveClient() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    return ClientModel.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  static Future<void> clearActiveClient() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> setLastUsedClient(ClientModel client) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsedKey, jsonEncode(client.toMap()));
  }

  static Future<ClientModel?> getLastUsedClient() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastUsedKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return ClientModel.fromMap(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }
}
