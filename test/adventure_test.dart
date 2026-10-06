import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/data/game_database.dart';

World fresh() => WorldGenerator.generate(
  seed: 'adventure',
  worldId: 'adventure',
  npcCount: 20,
);
Map<String, dynamic> proposal(String effect) => {
  'title': '山河有约',
  'text': '山路上有人求援，你可以承担风险，或安全离开。',
  'options': [
    {'label': '接受此缘', 'effect': effect},
    {'label': '离开', 'effect': 'leave'},
  ],
};
void main() {
  test(
    'eight local encounter templates are reachable and stored choices are stable',
    () {
      final titles = <String>{};
      for (var seed = 1; seed < 160; seed++) {
        final w = fresh();
        w.adventureRandom.state = seed;
        w.player.coins = 100;
        final n = w.entities.values.firstWhere(
          (e) => e.type == KarmaNodeType.npc,
        );
        n.location = w.player.location;
        n.realm = 0;
        n.personality = '好战';
        n.hp = 50;
        w.discover(w.playerId, n.id, InformationChannel.witness);
        final e = AdventureRules.discover(w, FactWriter(w), null);
        titles.add(e.title);
        w.encounter = e;
        expect(
          World.fromJson(
            jsonDecode(jsonEncode(w.toJson())),
          ).encounter!.toJson(),
          e.toJson(),
        );
      }
      expect(
        titles,
        containsAll([
          '灵草秘地',
          '古道遗宝',
          '负伤修士',
          '残碑遗刻',
          '商旅求援',
          '遗落兵器',
          '山谷伏击',
          '灵泉试炼',
        ]),
      );
    },
  );
  test(
    'pending encounter blocks time actions; exit costs zero and cannot settle twice',
    () {
      final rules = GameCommandService();
      var w = rules.execute(fresh(), const GameCommand('explore'));
      final day = w.day;
      expect(
        () => rules.execute(w, const GameCommand('cultivate')),
        throwsA(isA<RuleViolation>()),
      );
      w = rules.execute(
        w,
        const GameCommand('chooseEncounter', item: 'leave', actionId: 'once'),
      );
      expect(w.day, day);
      expect(w.encounter, isNull);
      expect(
        () => rules.execute(
          w,
          const GameCommand('chooseEncounter', item: 'leave', actionId: 'once'),
        ),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
  test(
    'AI choices reject missing exit, fabricated objects and arbitrary reward amounts',
    () {
      final w = fresh();
      for (final p in [
        proposal('not-an-effect'),
        {...proposal('herbs'), 'coins': 9999},
        {
          ...proposal('herbs'),
          'options': [
            {'label': '采集', 'effect': 'herbs'},
          ],
        },
        {...proposal('herbs'), 'text': 'life-123:npc:999'},
      ]) {
        expect(
          () => AiProposalValidator.validate(w, 'explore', p),
          throwsA(isA<RuleViolation>()),
        );
      }
      AiProposalValidator.validate(w, 'explore', proposal('herbs'));
      final rng = w.adventureRandom.state;
      final next = GameCommandService().execute(
        w,
        GameCommand('explore', proposal: proposal('herbs')),
      );
      expect(next.adventureRandom.state, rng);
      final chosen = GameCommandService().execute(
        next,
        const GameCommand('chooseEncounter', item: 'herbs'),
      );
      expect(chosen.inventory['灵草'], 9);
      expect(
        chosen.events.values
            .lastWhere((e) => e.kind == 'encounterChoice')
            .causes
            .single
            .eventId,
        next.encounter!.origin,
      );
    },
  );
  test('resource rejection leaves original world intact', () {
    var w = fresh();
    w.player.coins = 0;
    w = GameCommandService().execute(
      w,
      GameCommand('explore', proposal: proposal('weapon')),
    );
    final before = jsonEncode(w.toJson());
    expect(
      () => GameCommandService().execute(
        w,
        const GameCommand('chooseEncounter', item: 'weapon'),
      ),
      throwsA(isA<RuleViolation>()),
    );
    expect(jsonEncode(w.toJson()), before);
  });
  test(
    'escort causes battle, equipment reward and explicit historical chain',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      var w = fresh();
      w.player.realm = 2;
      w.player.hp = 180;
      final n = w.entities.values.firstWhere(
        (e) => e.type == KarmaNodeType.npc,
      );
      n.location = w.player.location;
      n.realm = 0;
      n.personality = '好战';
      n.hp = 18;
      n.lastActed = 10000;
      w.discover(w.playerId, n.id, InformationChannel.witness);
      final rules = GameCommandService();
      w = rules.execute(
        w,
        GameCommand(
          'explore',
          proposal: proposal('escort'),
          generation: {'model': 'fixture', 'proposal': proposal('escort')},
        ),
      );
      final origin = w.encounter!.origin;
      await db.save(w);
      w = (await db.load())!;
      final previous = w.copy();
      w = rules.execute(
        w,
        const GameCommand('chooseEncounter', item: 'escort'),
      );
      final battle = w.battleOrigin!;
      expect(
        w.events[battle]!.causes.single.eventId,
        w.events.values.lastWhere((e) => e.kind == 'encounterChoice').id,
      );
      w = rules.execute(w, const GameCommand('attack'));
      expect(n.alive, isTrue);
      expect(w.entities[n.id]!.alive, isFalse);
      expect(w.equipment.length, 1);
      expect(w.equipment.values.single.affix, isNotNull);
      w = rules.execute(w, GameCommand('equip', item: w.equipment.keys.single));
      await db.save(w, previous: previous);
      final restored = (await db.load())!;
      expect(restored.equipment.length, 1);
      expect(KarmaRepository(restored).event(origin), isNotNull);
      expect(
        restored.events.values
            .singleWhere((e) => e.kind == 'equipmentReward')
            .causes
            .single
            .eventId,
        restored.events.values.singleWhere((e) => e.kind == 'victory').id,
      );
    },
  );
  test(
    'equipment instances and legacy items migrate without resetting history',
    () {
      final w = fresh();
      final j = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
      j.remove('equipment');
      j.remove('weaponId');
      j.remove('adventureRandom');
      j['inventory']['青锋剑'] = 2;
      j['weapon'] = '青锋剑';
      final restored = World.fromJson(j);
      expect(restored.equipment.length, 2);
      expect(restored.weaponId, isNotNull);
      expect(restored.inventory.containsKey('青锋剑'), isFalse);
      expect(restored.events.length, w.events.length);
      final rules = GameCommandService();
      var next = rules.execute(
        restored,
        const GameCommand('trade', item: '青锋剑', amount: -1),
      );
      expect(next.equipment.length, 1);
      expect(
        () => rules.execute(
          next,
          const GameCommand('trade', item: '青锋剑', amount: -1),
        ),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
  test(
    'battle qi, healing, sword strike, disruption, defense and four enemy patterns',
    () {
      for (var kind = 0; kind < 4; kind++) {
        var w = fresh();
        w.player.realm = 2;
        w.player.hp = 80;
        w.techniques.addAll(['御剑诀', '天机诀']);
        final n = w.entities.values.firstWhere(
          (e) => e.type == KarmaNodeType.npc,
        );
        n.location = w.player.location;
        n.realm = 0;
        n.personality = '好战';
        n.hp = 100;
        n.lastActed = 10000;
        w.discover(w.playerId, n.id, InformationChannel.witness);
        w.battleTarget = n.id;
        w.battleOrigin = FactWriter(
          w,
        ).event('challenge', '试招', '真实交锋', [w.playerId, n.id]).id;
        AdventureRules.start(w);
        w.battleRound = 1;
        final hp = w.player.hp;
        final heal = AdventureRules.attack(w, '长春诀');
        expect(heal, 0);
        expect(w.player.hp, greaterThan(hp));
        expect(w.battleQi, 11);
        w.style = '御剑诀';
        expect(AdventureRules.attack(w, '御剑诀'), greaterThan(18));
        w.style = '天机诀';
        AdventureRules.attack(w, '天机诀');
        AdventureRules.counter(w, FactWriter(w), disrupt: true);
        expect(w.battleRound, 2);
        expect(w.battleQi, 4);
        final next = GameCommandService().execute(
          w,
          const GameCommand('defend'),
        );
        expect(next.battleQi, 6);
        w.battleQi = 0;
        expect(
          () => AdventureRules.attack(w, '天机诀'),
          throwsA(isA<RuleViolation>()),
        );
        // Choose IDs producing each deterministic enemy pattern.
        final id = List.generate(
          100,
          (i) => 'enemy$i',
        ).firstWhere((id) => SeedRandom.hash(id) % 4 == kind);
        w.entities[id] = Entity(
          id: id,
          type: KarmaNodeType.npc,
          name: '试招修士',
          hp: 50,
          location: w.player.location,
        );
        w.battleTarget = id;
        w.battleRound = 1;
        w.player.hp = 180;
        AdventureRules.counter(w, FactWriter(w));
        expect(
          w.events.values.last.title,
          contains(['猛击', '守势', '连击', '恢复'][kind]),
        );
      }
    },
  );
  test(
    'dialogue news cannot bypass NPC knowledge; rumors stay unconfirmed',
    () {
      final w = fresh();
      final n = w.entities.values.firstWhere(
        (e) => e.type == KarmaNodeType.npc,
      );
      n.location = w.player.location;
      w.discover(w.playerId, n.id, InformationChannel.witness);
      final e = FactWriter(
        w,
      ).event('secret', '未确认传闻', '只是传闻', [n.id], witnessed: false);
      w.knowledge.remove('${w.playerId}|${e.id}');
      w.knowledge.remove('${n.id}|${e.id}');
      w.discover(n.id, n.id, InformationChannel.witness);
      w.discover(n.id, e.id, InformationChannel.rumor, confirmed: false);
      expect(
        () => AiProposalValidator.validate(w, 'talk', {
          'reply': '未知',
          'news': ['missing'],
        }, target: n.id),
        throwsA(isA<RuleViolation>()),
      );
      var next = GameCommandService().execute(
        w,
        GameCommand(
          'talk',
          target: n.id,
          item: '说说见闻',
          proposal: {
            'reply': '我只听说过此事，未能确认。',
            'news': [e.id],
          },
        ),
      );
      expect(next.knows(w.playerId, e.id), isFalse);
      expect(next.knowledge['${w.playerId}|${e.id}']!.source, n.id);
      expect(next.dialogue.length, 1);
    },
  );
  test(
    'world proposals require legal knowledge and a real gratitude cause',
    () {
      final w = fresh();
      w.day = 120;
      final n = w.entities.values.firstWhere(
        (e) => e.type == KarmaNodeType.npc,
      );
      n.location = w.player.location;
      n.realm = 1;
      n.coins = 100;
      n.lastActed = 0;
      w.discover(w.playerId, n.id, InformationChannel.witness);
      expect(
        () => AiProposalValidator.validate(w, 'world', {
          'action': 'fake-revenge',
          'text': '凭空报仇',
        }),
        throwsA(isA<RuleViolation>()),
      );
      w.day = 0;
      final f = FactWriter(w);
      final rescue = f.event('rescue', '救助', '曾经救助', [w.playerId, n.id]);
      final r = f.relation(
        n.id,
        w.playerId,
        KarmaRelationType.gratitude,
        rescue,
      );
      w.day = 120;
      final option = AdventureRules.worldCatalog(
        w,
      ).singleWhere((e) => e['kind'] == 'repayment');
      final coins = w.player.coins;
      AdventureRules.worldProposal(w, {
        'action': option['id'],
        'text': '偿还真实救命之恩。',
      });
      expect(w.player.coins, coins + 35);
      expect(r.resolved, isTrue);
      expect(w.events.values.last.causes.single.eventId, rescue.id);
      expect(
        AdventureRules.worldCatalog(w).where((e) => e['kind'] == 'repayment'),
        isEmpty,
      );
    },
  );
}
