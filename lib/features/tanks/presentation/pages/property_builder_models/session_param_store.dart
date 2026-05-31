part of '../property_builder_page.dart';

class SessionParamStore {
  static Database? _db;
  static const _webPrefsKey = 'session_params_v1';

  static Map<String, dynamic> _deepMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(entry.key.toString(), _deepValue(entry.value)),
        ),
      );
    }
    return <String, dynamic>{};
  }

  static dynamic _deepValue(dynamic value) {
    if (value is Map) return _deepMap(value);
    if (value is List) return value.map(_deepValue).toList();
    return value;
  }

  static Future<Map<String, dynamic>> _readWebStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_webPrefsKey);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _deepMap(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> _writeWebStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webPrefsKey, jsonEncode(store));
  }

  static List<Map<String, dynamic>> _rowsFromScope(
    Map<String, dynamic> store,
    String scopeId,
  ) {
    final raw = store[scopeId];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
  }

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'session_params.db'),
      version: 2,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE session_params (
          id          TEXT PRIMARY KEY,
          scope_id    TEXT NOT NULL,
          label       TEXT NOT NULL,
          type        TEXT NOT NULL,
          track_previous_capture INTEGER NOT NULL DEFAULT 0,
          left_label  TEXT,
          right_label TEXT
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE session_params ADD COLUMN scope_id TEXT');
          await db.execute("UPDATE session_params SET scope_id = session_id WHERE scope_id IS NULL");
        }
      },
    );
    await _db!.execute(
      '''
      CREATE TABLE IF NOT EXISTS session_params_v2 (
        row_id      INTEGER PRIMARY KEY AUTOINCREMENT,
        id          TEXT NOT NULL,
        scope_id    TEXT NOT NULL,
        label       TEXT NOT NULL,
        type        TEXT NOT NULL,
        track_previous_capture INTEGER NOT NULL DEFAULT 0,
        left_label  TEXT,
        right_label TEXT,
        UNIQUE(id, scope_id)
      )
      ''',
    );
    await _db!.execute(
      '''
      INSERT OR IGNORE INTO session_params_v2 (id, scope_id, label, type, left_label, right_label)
      SELECT id, COALESCE(scope_id, 'legacy'), label, type, left_label, right_label
      FROM session_params
      ''',
    );
    try {
      await _db!.execute(
          'ALTER TABLE session_params_v2 ADD COLUMN track_previous_capture INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
    return _db!;
  }

  static Future<void> upsert(String scopeId, Map<String, dynamic> param) async {
    if (kIsWeb) {
      final store = await _readWebStore();
      final rows = _rowsFromScope(store, scopeId);
      final id = param['id']?.toString() ?? '';
      rows.removeWhere((row) => row['id']?.toString() == id);
      rows.add({
        'id': id,
        'scope_id': scopeId,
        'label': param['label']?.toString() ?? '',
        'type': param['type']?.toString() ?? '',
        'track_previous_capture':
            param['keep_previous_capture'] == true ? 1 : 0,
        'left_label': param['left_label']?.toString(),
        'right_label': param['right_label']?.toString(),
      });
      store[scopeId] = rows;
      await _writeWebStore(store);
      return;
    }

    final db = await _open();
    await db.insert(
      'session_params_v2',
      {
        'id': param['id']?.toString() ?? '',
        'scope_id': scopeId,
        'label': param['label']?.toString() ?? '',
        'type': param['type']?.toString() ?? '',
        'track_previous_capture':
            param['keep_previous_capture'] == true ? 1 : 0,
        'left_label': param['left_label']?.toString(),
        'right_label': param['right_label']?.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> upsertMany(
    String scopeId,
    List<Map<String, dynamic>> params,
  ) async {
    if (kIsWeb) {
      final store = await _readWebStore();
      final rows = _rowsFromScope(store, scopeId);
      final existingById = {
        for (final row in rows) row['id']?.toString() ?? '': row,
      };
      for (final param in params) {
        final id = param['id']?.toString() ?? '';
        existingById[id] = {
          'id': id,
          'scope_id': scopeId,
          'label': param['label']?.toString() ?? '',
          'type': param['type']?.toString() ?? '',
          'track_previous_capture':
              param['keep_previous_capture'] == true ? 1 : 0,
          'left_label': param['left_label']?.toString(),
          'right_label': param['right_label']?.toString(),
        };
      }
      store[scopeId] = existingById.values.toList();
      await _writeWebStore(store);
      return;
    }

    final db = await _open();
    final batch = db.batch();
    for (final param in params) {
      batch.insert(
        'session_params_v2',
        {
          'id': param['id']?.toString() ?? '',
          'scope_id': scopeId,
          'label': param['label']?.toString() ?? '',
          'type': param['type']?.toString() ?? '',
          'track_previous_capture':
              param['keep_previous_capture'] == true ? 1 : 0,
          'left_label': param['left_label']?.toString(),
          'right_label': param['right_label']?.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getAll(
      String scopeId, String excludeId) async {
    if (kIsWeb) {
      final store = await _readWebStore();
      return _rowsFromScope(store, scopeId)
          .where((row) => row['id']?.toString() != excludeId)
          .toList();
    }

    final db = await _open();
    return db.query(
      'session_params_v2',
      where: 'scope_id = ? AND id != ?',
      whereArgs: [scopeId, excludeId],
    );
  }

  static Future<void> clearScope(String scopeId) async {
    if (kIsWeb) {
      final store = await _readWebStore();
      store.remove(scopeId);
      await _writeWebStore(store);
      return;
    }

    final db = await _open();
    await db.delete('session_params_v2',
        where: 'scope_id = ?', whereArgs: [scopeId]);
  }

  static Future<void> removeParam(String scopeId, String paramId) async {
    if (kIsWeb) {
      final store = await _readWebStore();
      final rows = _rowsFromScope(store, scopeId)
        ..removeWhere((row) => row['id']?.toString() == paramId);
      store[scopeId] = rows;
      await _writeWebStore(store);
      return;
    }

    final db = await _open();
    await db.delete(
      'session_params_v2',
      where: 'scope_id = ? AND id = ?',
      whereArgs: [scopeId, paramId],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PropertyBuilderPage
// ─────────────────────────────────────────────────────────────────────────────
