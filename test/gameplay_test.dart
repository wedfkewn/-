import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/domain/models.dart';

World fresh() =>
    WorldGenerator.generate(seed: 'gameplay', worldId: 'game', npcCount: 20);
World walk(World w, String target) {
  final c = GameCommandService();
  w = c.execute(w, GameCommand('planRoute', target: target));
  while (w.journey != null) {
    w = c.execute(w, const GameCommand('moveStep'));
    if (w.encounter != null) {
      w = c.execute(w, const GameCommand('chooseEncounter', item: 'leave'));
    }
  }
  return w;
}

void main() {
  test(
    'cultivation, breakthrough, pills, crafting, trade, equipment and techniques have real effects',
    () {
      var w = fresh();
      final c = GameCommandService();
      final p = w.player;
      expect(
        () => c.execute(w, const GameCommand('breakthrough')),
        throwsA(isA<RuleViolation>()),
      );
      w = c.execute(w, const GameCommand('cultivate'));
      expect(w.day, 30);
      expect(w.player.spirit, greaterThan(p.spirit));
      w = c.execute(w, const GameCommand('craft', item: '聚灵丹'));
      expect(w.inventory['灵草'], 3);
      w = c.execute(w, const GameCommand('useItem', item: '聚灵丹'));
      expect(w.player.spirit, greaterThanOrEqualTo(68));
      w = c.execute(w, const GameCommand('trade', item: '青锋剑'));
      w = c.execute(w, const GameCommand('equip', item: '青锋剑'));
      expect(w.weapon, '青锋剑');
      for (var i = 0; i < 3; i++) {
        w = c.execute(w, const GameCommand('cultivate'));
      }
      while (w.player.stage < 3) {
        while (w.player.foundation < GrowthRules.rootRequired(w.player)) {
          w = c.execute(w, const GameCommand('stabilize'));
        }
        while (w.player.spirit <
            Content.threshold(w.player.realm, w.player.stage)) {
          w = c.execute(w, const GameCommand('cultivate'));
        }
        w = c.execute(w, const GameCommand('advanceStage'));
      }
      w = walk(w, 'game:location:1');
      w = c.execute(w, const GameCommand('contemplate'));
      w = c.execute(w, const GameCommand('gather', item: '筑基丹'));
      w = walk(w, 'game:location:0');
      for (var attempt = 0; attempt < 10 && w.player.realm == 0; attempt++) {
        while (w.player.foundation < 100 || GrowthRules.injured(w, w.player)) {
          w = c.execute(w, const GameCommand('stabilize'));
        }
        while (w.player.spirit <
            Content.threshold(w.player.realm, w.player.stage)) {
          w = c.execute(w, const GameCommand('cultivate'));
        }
        if ((w.inventory['筑基丹'] ?? 0) == 0) {
          w = walk(w, 'game:location:1');
          w = c.execute(w, const GameCommand('gather', item: '筑基丹'));
          w = walk(w, 'game:location:0');
        }
        w = c.execute(w, const GameCommand('breakthrough'));
        while (w.tribulation != null && !w.frozen) {
          w = c.execute(w, const GameCommand('defend'));
        }
      }
      expect(w.player.realm, 1);
      expect(Content.lifespans[w.player.realm], greaterThan(120));
      w.inventory['御剑诀'] = 1;
      w = c.execute(w, const GameCommand('learn', item: '御剑诀'));
      expect(w.techniques, contains('御剑诀'));
    },
  );
  test(
    'sect quest stages consume resources and reward completion; ancient tablet has a leave branch',
    () {
      var w = fresh();
      final c = GameCommandService();
      w = c.execute(w, const GameCommand('joinSect', target: 'game:sect:0'));
      expect(w.player.sect, 'game:sect:0');
      final coins = w.player.coins;
      for (var i = 0; i < 3; i++) {
        w = c.execute(w, const GameCommand('quest', item: '宗门委托'));
      }
      expect(w.quests['宗门委托'], 3);
      expect(w.player.coins, coins + 70);
      expect(
        () => c.execute(w, const GameCommand('quest', item: '宗门委托')),
        throwsA(isA<RuleViolation>()),
      );
      // Exploration, not a UI demo, discovers the tablet.
      for (var i = 0; i < 60 && !w.quests.containsKey('古碑'); i++) {
        w = c.execute(w, const GameCommand('explore'));
        final choice = w.encounter!.options.any((o) => o.id == 'tablet')
            ? 'tablet'
            : 'leave';
        w = c.execute(w, GameCommand('chooseEncounter', item: choice));
      }
      expect(w.quests, contains('古碑'));
      w = c.execute(w, const GameCommand('quest', item: '古碑'));
      w = c.execute(w, const GameCommand('quest', item: '古碑', target: 'leave'));
      expect(w.quests['古碑'], 3);
    },
  );
  test('same commands replay exactly including NPC autonomous actions', () {
    var a = fresh(), b = fresh();
    final c = GameCommandService();
    const sequence = [
      GameCommand('rescue', target: 'game:npc:0'),
      GameCommand('wait'),
      GameCommand('cultivate'),
      GameCommand('explore'),
      GameCommand('chooseEncounter', item: 'leave'),
      GameCommand('wait'),
    ];
    for (final command in sequence) {
      a = c.execute(a, command);
      b = c.execute(b, command);
    }
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect(a.events.values.any((e) => e.kind == 'npcCultivate'), true);
    expect(a.events.values.any((e) => e.kind == 'npcContemplate'), true);
    expect(
      a.events.values.any(
        (e) =>
            e.kind == 'npcTrade' ||
            e.kind == 'migration' ||
            e.kind == 'npcFriendship',
      ),
      true,
    );
  });
  test('secret killing does not immediately identify killer to remote kin', () {
    var w = fresh();
    final victim = w.entities['game:npc:0']!,
        relative = w.entities['game:npc:1']!;
    relative.location = 'game:location:4';
    final f = FactWriter(w);
    f.relation(
      relative.id,
      victim.id,
      KarmaRelationType.kinship,
      null,
      bidirectional: true,
      strength: 60,
    );
    final c = GameCommandService();
    w = c.execute(
      w,
      GameCommand('startBattle', target: victim.id, secret: true),
    );
    while (w.battleTarget != null && !w.frozen) {
      w = c.execute(w, const GameCommand('attack'));
    }
    expect(w.entities[victim.id]!.alive, false);
    final death = w.events.values.lastWhere((e) => e.kind == 'death');
    expect(w.knows(relative.id, death.id), false);
    expect(
      w.relations.values.any(
        (r) =>
            r.source == relative.id &&
            r.target == w.playerId &&
            r.type == KarmaRelationType.hatred,
      ),
      false,
    );
  });
  test(
    'corpse investigation confirms death but not a secretly unknown killer',
    () {
      final w = fresh();
      final f = FactWriter(w);
      final victim = w.entities['game:npc:0']!,
          relative = w.entities['game:npc:1']!;
      f.relation(
        relative.id,
        victim.id,
        KarmaRelationType.kinship,
        null,
        bidirectional: true,
      );
      final secret = f.event('secretKill', '秘密击杀', '秘密行动', [
        w.playerId,
        victim.id,
      ], witnessed: false);
      f.die(victim, secret);
      w.day = 90;
      WorldSimulationService().advance(w, FactWriter(w), 0);
      expect(
        w.events.values.any(
          (e) => e.kind == 'news' && e.participants.contains(relative.id),
        ),
        true,
      );
      expect(
        w.relations.values.any(
          (r) => r.source == relative.id && r.type == KarmaRelationType.hatred,
        ),
        false,
      );
    },
  );
  test(
    'witnesses propagate revenge then bounty then pursuit with explicit causes',
    () {
      final w = fresh();
      final f = FactWriter(w);
      final victim = w.entities['game:npc:0']!,
          relative = w.entities['game:npc:1']!,
          witness = w.entities['game:npc:2']!;
      f.relation(
        relative.id,
        victim.id,
        KarmaRelationType.kinship,
        null,
        bidirectional: true,
      );
      relative.sect = 'game:sect:0';
      witness.sect = relative.sect;
      final cause = f.event('victory', '击杀', '目击行凶', [w.playerId, victim.id]);
      f.die(victim, cause);
      // Relative hears after the action via a living witness rather than
      // becoming omniscient at the moment of death.
      w.knowledge.remove(
        '${relative.id}|${w.events.values.lastWhere((e) => e.kind == 'death').id}',
      );
      w.day = 30;
      WorldSimulationService().advance(w, FactWriter(w), 0);
      final revenge = w.events.values.firstWhere(
        (e) => e.kind == 'revenge' && e.participants.contains(relative.id),
      );
      final bounty = w.events.values.firstWhere(
        (e) => e.kind == 'bounty' && e.participants.contains(relative.id),
      );
      expect(bounty.causes.first.eventId, revenge.id);
      expect(w.events.values.any((e) => e.kind == 'pursuit'), true);
    },
  );
  test('unpaid obligations inherit through confirmed family news', () {
    var w = fresh();
    w = GameCommandService().execute(
      w,
      const GameCommand('borrow', target: 'game:npc:0'),
    );
    final f = FactWriter(w);
    final relative = w.entities['game:npc:1']!,
        victim = w.entities['game:npc:0']!;
    f.relation(
      relative.id,
      victim.id,
      KarmaRelationType.kinship,
      null,
      bidirectional: true,
    );
    final cause = f.event('accident', '意外', '意外陨落', [
      victim.id,
    ], witnessed: false);
    f.die(victim, cause);
    w.day = 40;
    WorldSimulationService().advance(w, FactWriter(w), 0);
    expect(
      w.relations.values.any(
        (r) =>
            r.type == KarmaRelationType.debt &&
            r.target == relative.id &&
            r.inheritedFrom != null,
      ),
      true,
    );
  });
  test(
    'end-to-end rescue, autonomous breakthrough, sect, repayment, timeline, permanent death',
    () {
      var w = fresh();
      final c = GameCommandService();
      w = c.execute(w, const GameCommand('rescue', target: 'game:npc:0'));
      final rescue = w.events.values.singleWhere((e) => e.kind == 'rescue');
      for (
        var i = 0;
        i < 180 && !w.events.values.any((e) => e.kind == 'repayment');
        i++
      ) {
        w = c.execute(w, const GameCommand('wait'));
      }
      final repayment = w.events.values.firstWhere(
        (e) => e.kind == 'repayment',
      );
      expect(
        repayment.causes.any(
          (cause) =>
              cause.eventId == rescue.id && cause.kind == CausalKind.direct,
        ),
        true,
      );
      final repo = KarmaRepository(w);
      final chain = repo.causalChain(rescue.id);
      expect(
        chain.map((e) => e.title),
        containsAll(['救下${w.entities['game:npc:0']!.name}', repayment.title]),
      );
      expect(chain.any((e) => w.events[e.id]!.kind == 'npcBreakthrough'), true);
      expect(chain.any((e) => w.events[e.id]!.kind == 'npcJoin'), true);
      expect(
        repo
            .query(const GraphQuery())
            .edges
            .firstWhere((e) => e.relationType == KarmaRelationType.gratitude)
            .status,
        RelationStatus.settled,
      );
      // Die to an actual stronger opponent; no injected death or demo record.
      final enemy = w.entities.values.firstWhere(
        (e) =>
            e.type == KarmaNodeType.npc &&
            e.alive &&
            e.realm > w.player.realm &&
            e.location == w.player.location &&
            w.knows(w.playerId, e.id),
      );
      w = c.execute(w, GameCommand('startBattle', target: enemy.id));
      for (var i = 0; i < 30 && !w.frozen; i++) {
        if (w.battleTarget == null) {
          final next = w.entities.values.firstWhere(
            (e) =>
                e.type == KarmaNodeType.npc &&
                e.alive &&
                e.realm > w.player.realm &&
                e.location == w.player.location &&
                w.knows(w.playerId, e.id),
          );
          w = c.execute(w, GameCommand('startBattle', target: next.id));
        }
        w = c.execute(w, const GameCommand('attack'));
      }
      expect(w.frozen, true);
      expect(w.assessment, isNotNull);
      expect(KarmaRepository(w).causalChain(rescue.id), isNotEmpty);
      expect(
        () => c.execute(w, const GameCommand('cultivate')),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
}
