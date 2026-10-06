import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/domain/models.dart';

void main() {
  test(
    'full acceptance chain survives disk reopen and remains read-only after next life',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karma-acceptance-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/world.sqlite');
      var db = GameDatabase.file(file);
      var w = WorldGenerator.generate(
        seed: 'gameplay',
        worldId: 'acceptance',
        npcCount: 20,
      );
      await db.save(w, makeActive: true);
      final commands = GameCommandService();
      Future<void> act(GameCommand command) async {
        final next = commands.execute(w, command);
        await db.save(next, previous: w);
        w = next;
      }

      await act(const GameCommand('rescue', target: 'acceptance:npc:0'));
      final rescue = w.events.values.singleWhere((e) => e.kind == 'rescue');
      for (
        var i = 0;
        i < 12 && !w.events.values.any((e) => e.kind == 'repayment');
        i++
      ) {
        await act(const GameCommand('wait'));
      }
      expect(w.events.values.any((e) => e.kind == 'repayment'), true);
      await db.close();
      db = GameDatabase.file(file);
      w = (await db.load())!;
      expect(
        KarmaRepository(
          w,
        ).causalChain(rescue.id).any((e) => w.events[e.id]!.kind == 'npcJoin'),
        true,
      );
      final enemy = w.entities.values.firstWhere(
        (n) => n.type == KarmaNodeType.npc && n.alive && n.realm >= 2,
      );
      await act(GameCommand('travel', target: enemy.location));
      await act(GameCommand('startBattle', target: enemy.id));
      for (var i = 0; i < 30 && !w.frozen; i++) {
        if (w.battleTarget == null) {
          final next = w.entities.values.firstWhere(
            (n) => n.type == KarmaNodeType.npc && n.alive && n.realm >= 2,
          );
          await act(GameCommand('travel', target: next.location));
          await act(GameCommand('startBattle', target: next.id));
        }
        await act(const GameCommand('attack'));
      }
      expect(w.frozen, true);
      final archived = jsonEncode(w.toJson());
      final fresh = WorldGenerator.generate(
        seed: 'new-world',
        worldId: 'next-life',
        npcCount: 20,
      );
      await db.save(fresh, makeActive: true);
      await db.close();
      db = GameDatabase.file(file);
      try {
        final historical = (await db.load(id: w.id))!;
        expect(jsonEncode(historical.toJson()), archived);
        expect((await db.load())!.id, fresh.id);
        expect(KarmaRepository(historical).causalChain(rescue.id), isNotEmpty);
        await expectLater(db.save(historical), throwsStateError);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'application runs rules off-thread, commits before publishing, and preserves state after rejection',
    () async {
      final db = GameDatabase.memory();
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      try {
        await container.read(gameProvider.future);
        final controller = container.read(gameProvider.notifier);
        await controller.create('测试修士', 'controller');
        final before = container.read(gameProvider).asData!.value;
        await controller.command(const GameCommand('cultivate'));
        expect(
          container.read(gameProvider).asData!.value.spirit,
          greaterThan(before.spirit),
        );
        expect(
          (await db.load())!.player.spirit,
          container.read(gameProvider).asData!.value.spirit,
        );
        final day = (await db.load())!.day;
        await expectLater(
          controller.command(const GameCommand('trade', item: '不存在')),
          throwsA(isA<RuleViolation>()),
        );
        expect((await db.load())!.day, day);
        expect(
          container.read(gameProvider).asData!.value.date,
          contains('玄元历'),
        );
      } finally {
        container.dispose();
        await db.close();
      }
    },
  );
}
