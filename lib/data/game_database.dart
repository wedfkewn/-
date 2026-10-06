import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import '../domain/models.dart';

/// SQL is explicit so persisted facts and indexes remain easy to audit; no
/// generated second set of domain entities is required.
class GameDatabase extends GeneratedDatabase {
  GameDatabase(super.executor);
  factory GameDatabase.file(File file) =>
      GameDatabase(NativeDatabase.createInBackground(file));
  factory GameDatabase.memory() => GameDatabase(NativeDatabase.memory());
  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE worlds (id TEXT PRIMARY KEY, payload TEXT NOT NULL, frozen INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 0)',
      );
      await customStatement(
        'CREATE TABLE entities (id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id), payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE relations (id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id), source TEXT NOT NULL, target TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE events (id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id), game_time INTEGER NOT NULL, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE knowledge (id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id), observer TEXT NOT NULL, subject TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      await _indexes();
      await _aiTables();
    },
    onUpgrade: (_, from, to) async {
      if (from == 1) {
        await customStatement(
          'ALTER TABLE worlds ADD COLUMN active INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'UPDATE worlds SET active = 1 WHERE id = (SELECT id FROM worlds ORDER BY rowid DESC LIMIT 1)',
        );
        await _indexes();
      }
      if (from < 3) await _aiTables();
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
  Future<void> _aiTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS app_settings (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS ai_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)',
    );
  }

  Future<Map<String, dynamic>> settings() async {
    final rows = await customSelect(
      "SELECT payload FROM app_settings WHERE id = 'ai'",
    ).get();
    return rows.isEmpty
        ? {}
        : jsonDecode(rows.single.read<String>('payload'))
              as Map<String, dynamic>;
  }

  Future<void> saveSettings(Map<String, dynamic> values) => customStatement(
    "INSERT INTO app_settings VALUES ('ai', ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
    [jsonEncode(values)],
  );
  Future<void> logUsage(Map<String, dynamic> values) => customStatement(
    'INSERT INTO ai_usage(payload) VALUES (?)',
    [jsonEncode(values)],
  );
  Future<Map<String, int>> usageTotals() async {
    final row = (await customSelect(
      r"SELECT COUNT(*) AS requests, COALESCE(SUM(json_extract(payload, '$.input')),0) AS input, COALESCE(SUM(json_extract(payload, '$.output')),0) AS output, SUM(CASE WHEN json_extract(payload,'$.input') IS NULL OR json_extract(payload,'$.output') IS NULL THEN 1 ELSE 0 END) AS unknown FROM ai_usage",
    ).get()).single;
    return {
      for (final name in ['requests', 'input', 'output', 'unknown'])
        name: row.read<int?>(name) ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> usage() async =>
      (await customSelect(
            'SELECT payload FROM ai_usage ORDER BY id DESC LIMIT 500',
          ).get())
          .map(
            (r) =>
                jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
          )
          .toList();
  Future<void> _indexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS relation_source ON relations(world_id, source)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS relation_target ON relations(world_id, target)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS event_time ON events(world_id, game_time, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS observer_subject ON knowledge(world_id, observer, subject)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS single_active_world ON worlds(active) WHERE active = 1',
    );
  }

  Future<List<Map<String, dynamic>>> archives() async {
    final rows = await customSelect(
      "SELECT w.payload, e.payload AS player FROM worlds w LEFT JOIN entities e ON e.id = json_extract(w.payload, '\$.playerId') WHERE w.frozen = 1 ORDER BY w.rowid DESC",
    ).get();
    return rows
        .map(
          (r) => {
            ...jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
            'player': r.readNullable<String>('player') == null
                ? null
                : jsonDecode(r.read<String>('player')),
          },
        )
        .toList();
  }

  Future<World?> load({String? id}) async {
    final rows = await customSelect(
      id == null
          ? 'SELECT id, payload FROM worlds WHERE active = 1'
          : 'SELECT id, payload FROM worlds WHERE id = ?',
      variables: id == null ? [] : [Variable<String>(id)],
    ).get();
    if (rows.isEmpty) {
      return null;
    }
    final worldId = rows.single.read<String>('id');
    final data =
        jsonDecode(rows.single.read<String>('payload')) as Map<String, dynamic>;
    for (final table in ['entities', 'relations', 'events', 'knowledge']) {
      final facts = await customSelect(
        'SELECT payload FROM $table WHERE world_id = ? ORDER BY rowid',
        variables: [Variable<String>(worldId)],
      ).get();
      data[table] = facts
          .map((r) => jsonDecode(r.read<String>('payload')))
          .toList();
    }
    return World.fromJson(data);
  }

  /// Atomically commit only changed rows. Frozen worlds cannot be overwritten.
  Future<void> save(
    World next, {
    World? previous,
    bool makeActive = false,
    bool failBeforeCommit = false,
  }) async {
    await transaction(() async {
      final existing = await customSelect(
        'SELECT frozen, payload FROM worlds WHERE id = ?',
        variables: [Variable<String>(next.id)],
      ).get();
      if (existing.isNotEmpty && existing.single.read<int>('frozen') == 1) {
        throw StateError('只读人生档案不可覆盖');
      }
      if (previous != null && existing.isNotEmpty) {
        final saved =
            jsonDecode(existing.single.read<String>('payload')) as Map;
        if (saved['revision'] != previous.revision) {
          throw StateError('存档版本已变化，拒绝过期结果');
        }
      }
      if (makeActive) {
        await customStatement('UPDATE worlds SET active = 0 WHERE active = 1');
      }
      await customStatement(
        'INSERT INTO worlds(id, payload, frozen, active) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, frozen=excluded.frozen',
        [
          next.id,
          jsonEncode(next.metadata()),
          next.frozen ? 1 : 0,
          makeActive || existing.isEmpty ? 1 : 0,
        ],
      );
      if (makeActive) {
        await customStatement('UPDATE worlds SET active = 1 WHERE id = ?', [
          next.id,
        ]);
      }
      for (final e in next.entities.values) {
        if (previous != null &&
            jsonEncode(previous.entities[e.id]?.toJson()) ==
                jsonEncode(e.toJson())) {
          continue;
        }
        await customStatement(
          'INSERT INTO entities VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
          [e.id, next.id, jsonEncode(e.toJson())],
        );
      }
      for (final r in next.relations.values) {
        if (previous != null &&
            jsonEncode(previous.relations[r.id]?.toJson()) ==
                jsonEncode(r.toJson())) {
          continue;
        }
        await customStatement(
          'INSERT INTO relations VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET source=excluded.source, target=excluded.target, payload=excluded.payload',
          [r.id, next.id, r.source, r.target, jsonEncode(r.toJson())],
        );
      }
      for (final e in next.events.values) {
        if (previous?.events.containsKey(e.id) == true) {
          continue;
        }
        await customStatement('INSERT INTO events VALUES (?, ?, ?, ?)', [
          e.id,
          next.id,
          e.time,
          jsonEncode(e.toJson()),
        ]);
      }
      for (final k in next.knowledge.values) {
        if (previous != null &&
            jsonEncode(previous.knowledge[k.key]?.toJson()) ==
                jsonEncode(k.toJson())) {
          continue;
        }
        await customStatement(
          'INSERT INTO knowledge VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
          [k.key, next.id, k.observer, k.subject, jsonEncode(k.toJson())],
        );
      }
      if (failBeforeCommit) {
        throw StateError('injected transaction failure');
      }
    });
  }
}
