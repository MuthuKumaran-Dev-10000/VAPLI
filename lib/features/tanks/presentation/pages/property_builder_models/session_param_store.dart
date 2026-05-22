part of '../property_builder_page.dart';

class SessionParamStore {
  static Database? _db;

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
    return _db!;
  }

  static Future<void> upsert(String scopeId, Map<String, dynamic> param) async {
    final db = await _open();
    await db.insert(
      'session_params_v2',
      {
        'id': param['id']?.toString() ?? '',
        'scope_id': scopeId,
        'label': param['label']?.toString() ?? '',
        'type': param['type']?.toString() ?? '',
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
    final db = await _open();
    return db.query(
      'session_params_v2',
      where: 'scope_id = ? AND id != ?',
      whereArgs: [scopeId, excludeId],
    );
  }

  static Future<void> clearScope(String scopeId) async {
    final db = await _open();
    await db.delete('session_params_v2',
        where: 'scope_id = ?', whereArgs: [scopeId]);
  }

  static Future<void> removeParam(String scopeId, String paramId) async {
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
