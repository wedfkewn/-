import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';

void main() {
  test(
    'facts, knowledge, inventory and RNG round trip; action resumes identically',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      var w = WorldGenerator.generate(
        seed: 'save',
        worldId: 'save',
        npcCount: 12,
      );
      w = GameCommandService().execute(
        w,
        const GameCommand('rescue', target: 'save:npc:0'),
      );
      await db.save(w, makeActive: true);
      final restored = (await db.load())!;
      expect(jsonEncode(restored.toJson()), jsonEncode(w.toJson()));
      expect(
        jsonEncode(
          GameCommandService()
              .execute(restored, const GameCommand('wait'))
              .toJson(),
        ),
        jsonEncode(
          GameCommandService().execute(w, const GameCommand('wait')).toJson(),
        ),
      );
    },
  );
  test(
    'transaction failure rolls back all facts and active-world selection',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'rollback',
        worldId: 'rollback',
        npcCount: 5,
      );
      await db.save(w, makeActive: true);
      final next = GameCommandService().execute(
        w,
        const GameCommand('explore'),
      );
      await expectLater(
        db.save(next, previous: w, failBeforeCommit: true),
        throwsStateError,
      );
      expect(jsonEncode((await db.load())!.toJson()), jsonEncode(w.toJson()));
      final fresh = WorldGenerator.generate(
        seed: 'new',
        worldId: 'new',
        npcCount: 5,
      );
      await expectLater(
        db.save(fresh, makeActive: true, failBeforeCommit: true),
        throwsStateError,
      );
      expect((await db.load())!.id, w.id);
      expect(await db.load(id: 'new'), isNull);
    },
  );
  test(
    'permanent death seals archive and new life does not overwrite history',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'life',
        worldId: 'old',
        npcCount: 5,
      );
      final f = FactWriter(w);
      final e = f.event('accident', '劫数', '意外', [w.playerId]);
      f.die(w.player, e);
      w.assessment = LifeAssessment.calculate(w);
      await db.save(w, makeActive: true);
      expect(
        () => GameCommandService().execute(w, const GameCommand('wait')),
        throwsA(isA<RuleViolation>()),
      );
      await expectLater(db.save(w), throwsStateError);
      final old = (await db.load())!;
      expect(KarmaRepository(old).timeline(), isNotEmpty);
      expect(old.frozen, true);
      final fresh = WorldGenerator.generate(
        seed: 'life',
        worldId: 'new',
        npcCount: 5,
      );
      await db.save(fresh, makeActive: true);
      expect((await db.load())!.id, 'new');
      expect((await db.load(id: 'old'))!.frozen, true);
      expect((await db.archives()).length, 1);
      expect(
        fresh.entities.keys.toSet().intersection(old.entities.keys.toSet()),
        isEmpty,
      );
    },
  );
  test(
    'v1 schema migrates to v3 with active selection, AI settings and indexes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karma-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.sqlite');
      final native = sql.sqlite3.open(file.path);
      native.execute(
        'CREATE TABLE worlds (id TEXT PRIMARY KEY, payload TEXT NOT NULL, frozen INTEGER NOT NULL)',
      );
      native.execute(
        'CREATE TABLE entities (id TEXT PRIMARY KEY, world_id TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      native.execute(
        'CREATE TABLE relations (id TEXT PRIMARY KEY, world_id TEXT NOT NULL, source TEXT NOT NULL, target TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      native.execute(
        'CREATE TABLE events (id TEXT PRIMARY KEY, world_id TEXT NOT NULL, game_time INTEGER NOT NULL, payload TEXT NOT NULL)',
      );
      native.execute(
        'CREATE TABLE knowledge (id TEXT PRIMARY KEY, world_id TEXT NOT NULL, observer TEXT NOT NULL, subject TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      native.execute('PRAGMA user_version=1');
      final w = WorldGenerator.generate(
        seed: 'legacy',
        worldId: 'legacy',
        npcCount: 2,
      );
      native.execute('INSERT INTO worlds VALUES (?, ?, ?)', [
        w.id,
        jsonEncode(w.metadata()),
        0,
      ]);
      for (final e in w.entities.values) {
        native.execute('INSERT INTO entities VALUES (?, ?, ?)', [
          e.id,
          w.id,
          jsonEncode(e.toJson()),
        ]);
      }
      native.close();
      final db = GameDatabase(NativeDatabase(file));
      try {
        expect((await db.load())!.id, 'legacy');
        expect(await db.settings(), isEmpty);
        expect((await db.usageTotals())['requests'], 0);
        expect(db.schemaVersion, 3);
        final indexes = await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .get();
        expect(
          indexes.map((r) => r.read<String>('name')),
          containsAll([
            'relation_source',
            'relation_target',
            'event_time',
            'observer_subject',
          ]),
        );
      } finally {
        await db.close();
      }
    },
  );
}
