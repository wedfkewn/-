import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';

World fresh() => WorldGenerator.generate(
  seed: 'commission',
  worldId: 'commission',
  npcCount: 12,
);
World act(World world, String kind, {String? item, String? target}) =>
    GameCommandService().execute(
      world,
      GameCommand(kind, item: item, target: target),
    );
World accept(World world, String kind) =>
    act(world, 'acceptCommission', item: kind);
World go(World world, String destination) {
  world = act(world, 'planRoute', target: destination);
  while (world.journey != null) {
    world.adventureRandom.state = 1;
    world = act(world, 'moveStep');
  }
  return world;
}

World foundationReady() {
  var world = accept(fresh(), 'foundation');
  world = act(world, 'stabilize');
  return act(world, 'practice');
}

void main() {
  test(
    'three configured commissions are accessible without time or RNG draws',
    () {
      final original = fresh();
      final rng = [
        original.random.state,
        original.adventureRandom.state,
        original.equipmentRandom.state,
      ];
      final world = accept(original, 'foundation');
      expect(Content.version, 6);
      expect(CommissionRules.view(original).offers.length, 3);
      expect(world.day, original.day);
      expect([
        world.random.state,
        world.adventureRandom.state,
        world.equipmentRandom.state,
      ], rng);
      expect(world.commissions.single.realm, original.player.realm);
      expect(original.commissions, isEmpty);
      expect(() => accept(world, 'travel'), throwsA(isA<RuleViolation>()));
    },
  );

  test(
    'old actions do not count; preparation needs both distinct real commands',
    () {
      var world = act(fresh(), 'stabilize');
      world = act(world, 'practice');
      world = accept(world, 'foundation');
      expect(
        CommissionRules.view(
          world,
        ).active!.objectives.every((o) => o.current == 0),
        isTrue,
      );
      world = act(world, 'stabilize');
      world = act(world, 'stabilize');
      expect(CommissionRules.view(world).active!.objectives.first.current, 1);
      expect(CommissionRules.view(world).canClaim, isFalse);
      world = act(world, 'practice');
      expect(world.commissions.single.progressEvents.length, 2);
      final coins = world.player.coins,
          root = world.player.foundation,
          day = world.day;
      final rng = [
        world.random.state,
        world.adventureRandom.state,
        world.equipmentRandom.state,
      ];
      world = act(world, 'claimCommission');
      expect(world.player.coins, coins + 16);
      expect(world.player.foundation, root + 5);
      expect(world.day, day);
      expect([
        world.random.state,
        world.adventureRandom.state,
        world.equipmentRandom.state,
      ], rng);
      expect(world.commissions.single.status, 'claimed');
      expect(
        () => act(world, 'claimCommission'),
        throwsA(isA<RuleViolation>()),
      );
      expect(() => accept(world, 'foundation'), throwsA(isA<RuleViolation>()));
      final claimed = world.events[world.commissions.single.result]!;
      expect(
        claimed.causes.map((c) => c.eventId),
        containsAll(world.commissions.single.progressEvents),
      );
      for (final id in world.commissions.single.progressEvents) {
        final progress = world.events[id]!;
        expect(progress.causes.length, 2);
        expect(progress.causes.first.eventId, world.commissions.single.origin);
        expect(world.knows(world.playerId, id), isTrue);
        expect(
          world.events[progress.causes.last.eventId]!.kind,
          anyOf('stabilize', 'practice'),
        );
      }
    },
  );

  test(
    'travel requires two distinct arrivals, preserves explicit travel sources',
    () {
      var world = accept(fresh(), 'travel');
      final start = world.player.location;
      final neighbor = world.mapRoads.values
          .firstWhere((r) => r.a == start || r.b == start)
          .other(start);
      world = go(world, neighbor);
      expect(CommissionRules.view(world).active!.objectives.single.current, 1);
      world = go(world, start);
      expect(CommissionRules.view(world).active!.objectives.single.current, 2);
      final evidence = world.commissions.single.evidence['visit']!;
      expect(evidence.keys.toSet(), {start, neighbor});
      expect(
        evidence.values.every((id) => world.events[id]!.kind == 'travel'),
        isTrue,
      );
      expect(CommissionRules.view(world).canClaim, isTrue);
      world = act(world, 'claimCommission');
      expect(world.commissions.single.status, 'claimed');
    },
  );

  test(
    'alchemy needs actual herbs and correct recipe plus a delivered pill',
    () {
      var world = accept(fresh(), 'alchemy');
      final start = world.player.location;
      final wild = world.mapPlaces.values.firstWhere(
        (p) =>
            p.kind == PlaceKind.wild &&
            p.danger == 0 &&
            world.knows(world.playerId, p.id),
      );
      world = go(world, wild.id);
      world = act(world, 'gather', item: '灵草');
      world = act(world, 'craft', item: '聚灵丹');
      expect(CommissionRules.view(world).active!.objectives.last.current, 0);
      world = act(world, 'craft', item: '回春丹');
      expect(
        CommissionRules.view(world).canClaim,
        isFalse,
        reason: 'must return to a board',
      );
      world = go(world, start);
      world.inventory['回春丹'] = 0;
      expect(CommissionRules.view(world).active!.notice, contains('回春丹'));
      expect(
        () => act(world, 'claimCommission'),
        throwsA(isA<RuleViolation>()),
      );
      world = act(world, 'trade', item: '回春丹');
      final pills = world.inventory['回春丹']!, coins = world.player.coins;
      world = act(world, 'claimCommission');
      expect(world.inventory['回春丹'], pills - 1);
      expect(world.player.coins, coins + 22);
    },
  );

  test(
    'accept and claim require confirmed board locations; rumors do not suffice',
    () {
      final world = fresh();
      final key = '${world.playerId}|${world.player.location}';
      world.knowledge.remove(key);
      world.discover(
        world.playerId,
        world.player.location,
        InformationChannel.rumor,
        confirmed: false,
      );
      expect(CommissionRules.view(world).canAccept, isFalse);
      expect(() => accept(world, 'travel'), throwsA(isA<RuleViolation>()));
      world.discover(
        world.playerId,
        world.player.location,
        InformationChannel.witness,
      );
      world.player.location = world.mapPlaces.values
          .firstWhere((p) => p.kind == PlaceKind.wild)
          .id;
      expect(() => accept(world, 'travel'), throwsA(isA<RuleViolation>()));
    },
  );

  test(
    'abandon preserves history and prevents accepting that kind in the same realm',
    () {
      var world = accept(fresh(), 'travel');
      world = act(world, 'abandonCommission');
      final state = world.commissions.single;
      expect(state.status, 'abandoned');
      expect(world.events[state.result]!.causes.single.eventId, state.origin);
      expect(() => accept(world, 'travel'), throwsA(isA<RuleViolation>()));
      expect(
        () => act(world, 'abandonCommission'),
        throwsA(isA<RuleViolation>()),
      );
      world = accept(world, 'foundation');
      expect(world.commissions.length, 2);
    },
  );

  test('realm changes preserve an old commission and fixed rewards', () {
    var world = accept(fresh(), 'foundation');
    world = act(world, 'stabilize');
    world.player
      ..stage = 3
      ..foundation = 100
      ..insight = 100
      ..spirit = 1000;
    world.player.hp = GameCommandService.maxHp(world.player);
    world.inventory['筑基丹'] = 1;
    world = act(world, 'breakthrough');
    while (world.tribulation != null) {
      world = act(world, 'defend');
    }
    expect(world.player.realm, 1);
    expect(world.frozen, isFalse);
    world = act(world, 'practice');
    expect(CommissionRules.view(world).active!.acceptedRealm, 0);
    expect(CommissionRules.view(world).canClaim, isTrue);
    final coins = world.player.coins;
    world = act(world, 'claimCommission');
    expect(world.player.coins, coins + 16);
    world = accept(world, 'foundation');
    expect(world.commissions.last.realm, 1);
    expect(world.commissions.last.evidence, isEmpty);
    expect(() => accept(world, 'foundation'), throwsA(isA<RuleViolation>()));
  });

  test(
    'commission projection filters unknown sources and never exposes geography tokens',
    () {
      var world = accept(fresh(), 'travel');
      final start = world.player.location;
      final neighbor = world.mapRoads.values
          .firstWhere((r) => r.a == start || r.b == start)
          .other(start);
      world = go(world, neighbor);
      final objective = CommissionRules.view(world).active!.objectives.single;
      expect(objective.current, 1);
      expect(objective.sourceEventIds.any((id) => id == neighbor), isFalse);
      for (final id in objective.sourceEventIds) {
        world.knowledge.remove('${world.playerId}|$id');
      }
      final filtered = CommissionRules.view(world).active!.objectives.single;
      expect(filtered.current, 0);
      expect(filtered.sourceEventIds, isEmpty);
    },
  );

  test('lifespan death prevents recording a new preparation objective', () {
    var world = accept(fresh(), 'foundation');
    world.player.ageDays = Content.lifespans[0] * 360 - 5;
    world = act(world, 'stabilize');
    expect(world.frozen, isTrue);
    expect(world.commissions.single.evidence, isEmpty);
    expect(world.commissions.single.progressEvents, isEmpty);
    expect(CommissionRules.view(world).canClaim, isFalse);
    expect(() => act(world, 'claimCommission'), throwsA(isA<RuleViolation>()));
    expect(
      () => act(world, 'abandonCommission'),
      throwsA(isA<RuleViolation>()),
    );
  });

  test(
    'old saves default to empty commissions without rewriting their history',
    () {
      final original = fresh();
      final json =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      json.remove('commissions');
      json['frozen'] = true;
      final loaded = World.fromJson(json);
      expect(loaded.commissions, isEmpty);
      expect(CommissionRules.view(loaded).offers, isEmpty);
      expect(CommissionRules.view(loaded).canAccept, isFalse);
      expect(loaded.events.keys, original.events.keys);
    },
  );

  test(
    'database restores progress and rolls back rewards, events and delivery atomically',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final original = foundationReady();
      await db.save(original, makeActive: true);
      final restored = (await db.load())!;
      expect(
        jsonEncode(restored.commissions.map((c) => c.toJson()).toList()),
        jsonEncode(original.commissions.map((c) => c.toJson()).toList()),
      );
      final next = act(restored, 'claimCommission');
      await expectLater(
        db.save(next, previous: restored, failBeforeCommit: true),
        throwsStateError,
      );
      final after = (await db.load())!;
      expect(after.player.coins, restored.player.coins);
      expect(after.player.foundation, restored.player.foundation);
      expect(after.commissions.single.status, 'active');
      expect(after.events.length, restored.events.length);
      await db.save(next, previous: after);
      final saved = (await db.load())!;
      expect(saved.commissions.single.status, 'claimed');
      expect(
        saved.events[saved.commissions.single.result]!.kind,
        'commissionClaimed',
      );
    },
  );

  test(
    'a failed progress transaction restores the action, objective and its source events',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final original = accept(fresh(), 'foundation');
      await db.save(original, makeActive: true);
      final next = act(original, 'stabilize');
      expect(next.commissions.single.progressEvents.length, 1);
      await expectLater(
        db.save(next, previous: original, failBeforeCommit: true),
        throwsStateError,
      );
      final after = (await db.load())!;
      expect(after.day, original.day);
      expect(after.player.foundation, original.player.foundation);
      expect(after.commissions.single.evidence, isEmpty);
      expect(after.commissions.single.progressEvents, isEmpty);
      expect(after.events.length, original.events.length);
    },
  );

  test(
    'failed alchemy delivery returns the pill and keeps the reward unclaimed',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      var world = accept(fresh(), 'alchemy');
      final start = world.player.location;
      final wild = world.mapPlaces.values.firstWhere(
        (p) =>
            p.kind == PlaceKind.wild &&
            p.danger == 0 &&
            world.knows(world.playerId, p.id),
      );
      world = go(world, wild.id);
      world = act(world, 'gather', item: '灵草');
      world = act(world, 'craft', item: '回春丹');
      world = go(world, start);
      await db.save(world, makeActive: true);
      final claimed = act(world, 'claimCommission');
      expect(claimed.inventory['回春丹'], world.inventory['回春丹']! - 1);
      await expectLater(
        db.save(claimed, previous: world, failBeforeCommit: true),
        throwsStateError,
      );
      final after = (await db.load())!;
      expect(after.inventory['回春丹'], world.inventory['回春丹']);
      expect(after.player.coins, world.player.coins);
      expect(after.commissions.single.status, 'active');
      expect(CommissionRules.view(after).canClaim, isTrue);
    },
  );

  test(
    'frozen archive refuses commission modifications and remains byte-stable',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      var world = foundationReady();
      world.player.ageDays = Content.lifespans[0] * 360 - 1;
      world = act(world, 'wait');
      expect(world.frozen, isTrue);
      await db.save(world, makeActive: true);
      final loaded = (await db.load())!;
      final before = jsonEncode(loaded.toJson());
      expect(
        () => act(loaded, 'claimCommission'),
        throwsA(isA<RuleViolation>()),
      );
      final tampered = loaded.copy()..commissions.clear();
      await expectLater(db.save(tampered, previous: loaded), throwsStateError);
      expect(jsonEncode((await db.load())!.toJson()), before);
    },
  );
}
