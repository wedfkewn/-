import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/domain/map_repository.dart';

World fresh() =>
    WorldGenerator.generate(seed: 'growth', worldId: 'growth', npcCount: 12);
World prepared({int realm = 0}) {
  final w = fresh();
  final p = w.player;
  p.realm = realm;
  p.stage = 3;
  p.foundation = 60 + realm * 4;
  p.insight = 10 + realm * 10;
  p.spirit = 100000;
  p.hp = GameCommandService.maxHp(p);
  w.inventory[MapRules.materials[realm]] = 2;
  if (realm >= 6) {
    p.location = w.mapPlaces.values
        .firstWhere((p) => p.kind == PlaceKind.tribulation)
        .id;
    MapRules.revealNearby(w, p.id, InformationChannel.witness);
  }
  return w;
}

void main() {
  test('lifespan expires before a late breakthrough can extend it', () {
    final w = prepared();
    w.player.ageDays = Content.lifespans[0] * 360 - 1;
    final result = GameCommandService().execute(
      w,
      const GameCommand('breakthrough'),
    );
    expect(result.frozen, isTrue);
    expect(result.player.realm, 0);
    expect(result.inventory['筑基丹'], 2);
  });
  test(
    'three and five round lightning survives defense, restores, and never permits escape',
    () {
      for (final realm in [6, 7]) {
        var w = prepared(realm: realm);
        final c = GameCommandService();
        final before = w.random.state;
        w = c.execute(w, const GameCommand('breakthrough'));
        expect(w.tribulation!.rounds, realm == 6 ? 3 : 5);
        expect(
          w.random.state,
          before,
        ); // start has no probabilistic breakthrough roll
        expect(
          () => c.execute(w, const GameCommand('flee')),
          throwsA(isA<RuleViolation>()),
        );
        w = World.fromJson(jsonDecode(jsonEncode(w.toJson())));
        while (w.tribulation != null && !w.frozen) {
          expect(GrowthRules.omen(w), contains('不能逃跑'));
          w = c.execute(w, const GameCommand('defend'));
        }
        expect(w.frozen, isFalse);
        expect(w.player.realm, realm + 1);
        expect(
          w.events.values.where((e) => e.kind == 'tribulationRound').length,
          realm == 6 ? 3 : 5,
        );
      }
    },
  );
  test(
    'reckless lightning can permanently kill and freezes all subsequent commands',
    () {
      var w = prepared(realm: 7);
      final c = GameCommandService();
      w = c.execute(w, const GameCommand('breakthrough'));
      while (!w.frozen && w.tribulation != null) {
        w = c.execute(w, const GameCommand('attack'));
      }
      expect(w.frozen, isTrue);
      expect(w.player.alive, isFalse);
      expect(w.assessment, isNotNull);
      expect(
        () => c.execute(w, const GameCommand('cultivate')),
        throwsA(isA<RuleViolation>()),
      );
      final death = w.events.values.lastWhere((e) => e.kind == 'death');
      expect(w.events[death.causes.single.eventId]!.kind, 'tribulationRound');
    },
  );
  test(
    'secret expedition is dated, staged, resumable, sourced and safely exit-able',
    () {
      var w = fresh();
      final point = w.mapPlaces.values.firstWhere(
        (p) => p.kind == PlaceKind.secret && p.danger == 0,
      );
      w.player.location = point.id;
      MapRules.revealNearby(w, w.playerId, InformationChannel.witness);
      final c = GameCommandService();
      w = c.execute(w, const GameCommand('enterSecret'));
      expect(w.player.coins, 70);
      expect(
        () => c.execute(w, const GameCommand('cultivate')),
        throwsA(isA<RuleViolation>()),
      );
      w = c.execute(w, const GameCommand('secretStep'));
      w = World.fromJson(jsonDecode(jsonEncode(w.toJson())));
      expect(w.secretRun!.stage, 1);
      w = c.execute(w, const GameCommand('secretStep'));
      expect(w.player.hp, 70);
      w = c.execute(w, const GameCommand('secretStep'));
      expect(w.secretRun, isNull);
      expect(w.inventory['筑基丹'], 1);
      expect(w.equipment, isNotEmpty);
      expect(w.player.insight, 10);
      final events = w.events.values
          .where((e) => e.kind == 'secretStep')
          .toList();
      expect(events[1].causes.single.eventId, events[0].id);
      w.day = 30;
      expect(
        () => c.execute(w, const GameCommand('enterSecret')),
        throwsA(isA<RuleViolation>()),
      );
      w.day = 90;
      w = c.execute(w, const GameCommand('enterSecret'));
      final day = w.day;
      w = c.execute(w, const GameCommand('leaveSecret'));
      expect(w.day, day);
      expect(w.secretRun, isNull);
    },
  );
  test(
    'NPC cannot bypass materials and uses only reachable observed geography',
    () {
      final w = fresh();
      final n = w.entities['growth:npc:0']!;
      n.stage = 3;
      n.spirit = 1000;
      n.foundation = 100;
      n.insight = 10;
      n.coins = 0;
      n.supplies.clear();
      final remembered = MapRepository(
        w,
        observer: n.id,
      ).query().places.map((p) => p.place.id).toSet();
      w.day = 30;
      WorldSimulationService().advance(w, FactWriter(w), 0);
      expect(n.realm, 0);
      expect(n.supplies['筑基丹'] ?? 0, 0);
      expect(remembered.contains(n.location), isTrue);
    },
  );
  test(
    'four stages require root and cultivation, advance once and preserve lifespan',
    () {
      var w = fresh();
      w.player.spirit = 1000;
      final c = GameCommandService();
      w = c.execute(w, const GameCommand('advanceStage'));
      expect(w.player.stage, 1);
      expect(w.player.realm, 0);
      expect(w.player.spirit, 920);
      expect(GameCommandService.maxHp(w.player), 105);
      expect(
        () => c.execute(w, const GameCommand('advanceStage')),
        throwsA(isA<RuleViolation>()),
      );
      w = c.execute(w, const GameCommand('stabilize'));
      w = c.execute(w, const GameCommand('advanceStage'));
      expect(w.player.stage, 2);
      expect(w.player.spirit, 820);
      w = c.execute(w, const GameCommand('stabilize'));
      w = c.execute(w, const GameCommand('advanceStage'));
      expect(w.player.stage, 3);
      expect(w.player.realm, 0);
      expect(Content.lifespans[w.player.realm], 120);
      expect(
        () => c.execute(w, const GameCommand('breakthrough')),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
  test(
    'stacking learned techniques does not stack cultivation; selected style does',
    () {
      final a = fresh(), b = fresh();
      b.techniques.addAll(['御剑诀', '天机诀']);
      final c = GameCommandService();
      expect(
        c.execute(a, const GameCommand('cultivate')).player.spirit,
        c.execute(b, const GameCommand('cultivate')).player.spirit,
      );
      b.style = '御剑诀';
      expect(
        c.execute(b, const GameCommand('cultivate')).player.spirit,
        greaterThan(c.execute(a, const GameCommand('cultivate')).player.spirit),
      );
    },
  );
  test(
    'contemplation has an explicit source and cannot repeat at this realm/place',
    () {
      var w = fresh();
      w = GameCommandService().execute(w, const GameCommand('contemplate'));
      expect(w.player.insight, 5);
      final event = w.events.values.lastWhere((e) => e.kind == 'insight');
      expect(w.events[event.causes.single.eventId]!.kind, 'contemplate');
      expect(
        () => GameCommandService().execute(w, const GameCommand('contemplate')),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
  test(
    'failure charges 20 percent, injures without killing, and requires all recovery conditions',
    () {
      var w = prepared();
      w.random.state = 1; // first sample is 71, above the prepared 50% chance
      final spirit = w.player.spirit, threshold = Content.threshold(0, 3);
      final c = GameCommandService();
      w = c.execute(w, const GameCommand('breakthrough'));
      expect(w.player.realm, 0);
      expect(w.player.spirit, spirit - (threshold * .2).ceil());
      expect(w.inventory['筑基丹'], 1);
      expect(w.player.alive, isTrue);
      expect(GrowthRules.injured(w, w.player), isTrue);
      w = c.execute(w, const GameCommand('stabilize'));
      expect(GrowthRules.injured(w, w.player), isTrue);
      w = c.execute(w, const GameCommand('cultivate'));
      expect(GrowthRules.injured(w, w.player), isFalse);
      final stabilized = w.events.values.lastWhere(
        (e) => e.kind == 'stabilize',
      );
      expect(
        w.events[stabilized.causes.single.eventId]!.kind,
        'breakthroughFailed',
      );
    },
  );
  test(
    'success consumes exact preparation, resets growth and extends lifespan',
    () {
      var w = prepared();
      w.random.state = 2; // first sample 42
      final before = w.player.spirit;
      w = GameCommandService().execute(w, const GameCommand('breakthrough'));
      expect(w.player.realm, 1);
      expect(w.player.stage, 0);
      expect(w.player.foundation, 30);
      expect(w.player.insight, 0);
      expect(w.player.spirit, before - Content.threshold(0, 3));
      expect(Content.lifespans[w.player.realm], 240);
      final success = w.events.values.lastWhere(
        (e) => e.kind == 'breakthrough',
      );
      expect(
        w.events[success.causes.single.eventId]!.kind,
        'breakthroughPreparation',
      );
    },
  );
  test(
    'guard requires actual known social relation, presence, life and sufficient realm',
    () {
      final w = prepared();
      final guard = w.entities['growth:npc:0']!..realm = 1;
      expect(GrowthRules.view(w, guard: guard.id).missing, contains('护法条件不满足'));
      FactWriter(w).relation(
        w.playerId,
        guard.id,
        KarmaRelationType.friendship,
        null,
        bidirectional: true,
      );
      w.inventory['护脉丹'] = 1;
      expect(GrowthRules.view(w, guard: guard.id, pill: true).chance, 70);
      guard.location = 'growth:location:10';
      expect(GrowthRules.view(w).guards, isNot(contains(guard.id)));
    },
  );
  test(
    'bad preparation is rejected before resources, days, or random state change',
    () {
      final w = prepared();
      w.inventory['筑基丹'] = 0;
      final before = jsonEncode(w.toJson());
      expect(
        () =>
            GameCommandService().execute(w, const GameCommand('breakthrough')),
        throwsA(isA<RuleViolation>()),
      );
      expect(jsonEncode(w.toJson()), before);
    },
  );
  test(
    'legacy character growth fields default without resetting realm or spirit',
    () {
      final json = prepared(realm: 3).toJson();
      for (final value in json['entities'] as List) {
        (value as Map).remove('stage');
        value.remove('foundation');
        value.remove('insight');
        value.remove('growthSources');
      }
      final restored = World.fromJson(Map<String, dynamic>.from(json));
      expect(restored.player.realm, 3);
      expect(restored.player.stage, 0);
      expect(restored.player.foundation, 30);
      expect(restored.player.insight, 0);
      expect(restored.player.spirit, 100000);
    },
  );
}
