import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/ui/battle_stage.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

World fresh([String id = 'life-test']) => WorldGenerator.generate(
  seed: 'attributes-test',
  worldId: id,
  npcCount: 12,
  regionCount: 1,
  placesPerRegion: 10,
);

void main() {
  test(
    'real rescue outcomes, gear, lifespan death and next birth preserve the sealed world',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final rules = GameCommandService();
      var w = fresh('real-life');
      w.player.coins = 200;
      final patients = w.entities.values
          .where(
            (n) =>
                n.type == KarmaNodeType.npc && n.location == w.player.location,
          )
          .take(2)
          .toList();
      expect(patients.length, 2);
      for (final n in patients) {
        n.hp = 1;
        n.realm = 0;
      }
      await db.save(w, makeActive: true);
      Future<void> act(GameCommand command) async {
        final previous = w;
        w = rules.execute(w, command);
        await db.save(w, previous: previous);
      }

      await act(const GameCommand('trade', item: '青锋剑'));
      await act(GameCommand('equip', item: w.equipment.values.single.id));
      for (final n in patients) {
        await act(GameCommand('rescue', target: n.id));
      }
      w.player.ageDays = Content.lifespans[0] * 360 - 1;
      await act(const GameCommand('wait'));
      expect(w.frozen, isTrue);
      final snapshot = jsonEncode(w.toJson());
      final draft = await db.creationDraft(seed: 'next-real');
      expect(draft.entitlement.points, greaterThan(0));
      final allocations = [0, draft.entitlement.points, 0, 0];
      final next = WorldGenerator.generate(
        seed: draft.seed,
        worldId: 'next-real',
        npcCount: 12,
        regionCount: 1,
        placesPerRegion: 10,
      );
      await db.createLife(next, draft, 0, allocations);
      expect((await db.load())!.birth!['source'], 'real-life');
      expect(next.equipment, isEmpty);
      expect(next.player.realm, 0);
      expect(jsonEncode((await db.load(id: w.id))!.toJson()), snapshot);
      await expectLater(db.save(w), throwsStateError);
    },
  );
  test(
    'armor and attributes apply to lightning feedback without extra settlement',
    () {
      final rules = GameCommandService();
      final bare = fresh();
      bare.player.realm = 6;
      bare.player.hp = 300;
      bare.tribulation = Tribulation(bare.events.values.first.id, 3, 30);
      final protected = bare.copy();
      const armor = Equipment(
        'armor',
        '玄铁甲',
        'armor',
        realm: 6,
        base: 40,
        bonuses: {'坚韧': 10},
        version: 1,
      );
      protected.equipment[armor.id] = armor;
      protected.armorId = armor.id;
      final a = rules.execute(bare, const GameCommand('defend'));
      final b = rules.execute(protected, const GameCommand('defend'));
      expect(b.feedback!.received, lessThan(a.feedback!.received));
      expect(b.feedback!.absorbed, 30);
      expect(b.feedback!.kind, '雷劫:defend');
      expect(b.tribulation!.turn, 1);
    },
  );
  test('three unique bounded equal-budget birth candidates reproduce', () {
    for (var seed = 0; seed < 100; seed++) {
      final a = BirthRules.candidates('$seed'),
          b = BirthRules.candidates('$seed');
      expect(a.map((x) => x.values).toList(), b.map((x) => x.values).toList());
      expect(a.map((x) => x.values.join(',')).toSet().length, 3);
      for (final x in a) {
        expect(x.values.reduce((a, b) => a + b), 20);
        expect(x.values.every((v) => v >= 2 && v <= 8), isTrue);
      }
    }
  });
  test('reward boundaries and allocation validation', () {
    expect(
      [
        0,
        99,
        100,
        299,
        300,
        599,
        600,
        999,
        1000,
        1499,
        1500,
        1999,
        2000,
        99999,
      ].map(RebirthEntitlement.reward).toList(),
      [0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 10, 10, 12, 12],
    );
    final d = CreationDraft(
      'd',
      's',
      BirthRules.candidates('s'),
      const RebirthEntitlement(points: 12),
    );
    for (final v in [
      [-1, 13, 0, 0],
      [0, 0, 0, 0],
      [12, 0, 0, 0],
      [1, 2, 3],
    ]) {
      expect(() => BirthRules.allocate(d, 0, v), throwsA(isA<RuleViolation>()));
    }
    expect(
      () => BirthRules.allocate(d, 3, [3, 3, 3, 3]),
      throwsA(isA<RuleViolation>()),
    );
    expect(
      BirthRules.allocate(d, 0, [3, 3, 3, 3]).values.reduce((a, b) => a + b),
      32,
    );
  });
  test(
    'attributes affect health attack cultivation insight and qi; old entities stay neutral',
    () {
      final base = fresh(), boosted = base.copy();
      boosted.player.attributes = const CharacterAttributes(8, 8, 8, 8);
      boosted.player.hp = GameCommandService.maxHp(boosted.player);
      expect(GameCommandService.maxHp(base.player), 100);
      expect(GameCommandService.maxHp(boosted.player), 112);
      expect(
        AdventureRules.attack(boosted, null),
        greaterThan(AdventureRules.attack(base, null)),
      );
      expect(EquipmentRules.maxQi(boosted), 13);
      final rules = GameCommandService();
      expect(
        rules.execute(boosted, const GameCommand('cultivate')).player.spirit,
        greaterThan(
          rules.execute(base, const GameCommand('cultivate')).player.spirit,
        ),
      );
      boosted.player.stage = 3;
      expect(GrowthRules.view(boosted).insightRequired, 10); // ceil(9.4)
      boosted.player.realm = 5;
      expect(GrowthRules.view(boosted).insightRequired, 57);
      final old = base.player.toJson()..remove('attributes');
      expect(Entity.fromJson(old).attributes.values, [5, 5, 5, 5]);
    },
  );
  test(
    'equipment uses isolated saved random stream and legal quality ranges',
    () {
      final w = fresh(), before = w.adventureRandom.state, map = w.random.state;
      for (var i = 0; i < 200; i++) {
        w.player.realm = i % 9;
        final e = AdventureRules.addEquipment(w, '青锋剑', affixed: true);
        expect(e.effects.length, e.quality);
        expect(e.quality, inInclusiveRange(1, 3));
        expect(e.realm, i % 9);
        expect(
          e.effects.values.every(
            (v) => v >= 2 + e.realm && v <= 4 + e.realm * 2,
          ),
          isTrue,
        );
      }
      expect(w.adventureRandom.state, before);
      expect(w.random.state, map);
      final restored = World.fromJson(jsonDecode(jsonEncode(w.toJson())));
      expect(
        AdventureRules.addEquipment(w, '玄铁甲', affixed: true).toJson(),
        AdventureRules.addEquipment(restored, '玄铁甲', affixed: true).toJson(),
      );
    },
  );
  test('legacy gear keeps fixed stats and its original affix', () {
    final w = fresh();
    final e = Equipment.fromJson({
      'id': 'old',
      'name': '青锋剑',
      'slot': 'weapon',
      'affix': '锋锐',
      'value': 7,
    });
    w.equipment[e.id] = e;
    w.weaponId = e.id;
    expect(EquipmentRules.stats(w).attack, 19);
    expect(e.realm, 0);
    expect(e.version, 0);
    expect(
      Equipment.fromJson(jsonDecode(jsonEncode(e.toJson()))).description,
      e.description,
    );
  });
  test('realm restriction, exact sale and equipped protection are atomic', () {
    final rules = GameCommandService(), w = fresh();
    const high = Equipment(
      'high',
      '青锋剑',
      'weapon',
      realm: 2,
      base: 40,
      version: 1,
    );
    const first = Equipment(
      'first',
      '青锋剑',
      'weapon',
      base: 14,
      quality: 1,
      version: 1,
    );
    const second = Equipment(
      'second',
      '青锋剑',
      'weapon',
      base: 18,
      quality: 2,
      version: 1,
    );
    for (final e in [high, first, second]) {
      w.equipment[e.id] = e;
    }
    final original = jsonEncode(w.toJson());
    expect(
      () => rules.execute(w, const GameCommand('equip', item: 'high')),
      throwsA(isA<RuleViolation>()),
    );
    expect(jsonEncode(w.toJson()), original);
    final equipped = rules.execute(
      w,
      const GameCommand('equip', item: 'first'),
    );
    expect(
      () => rules.execute(
        equipped,
        const GameCommand('sellEquipment', item: 'first'),
      ),
      throwsA(isA<RuleViolation>()),
    );
    final sold = rules.execute(
      equipped,
      const GameCommand('sellEquipment', item: 'second'),
    );
    expect(sold.equipment.containsKey('second'), isFalse);
    expect(sold.equipment.containsKey('first'), isTrue);
    expect(
      sold.player.coins,
      equipped.player.coins + EquipmentRules.sale(second),
    );
  });
  test(
    'draft, selection and reward survive restart; create rollback leaves them intact',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final dead = fresh('dead')
        ..frozen = true
        ..assessment = {'score': 700};
      await db.save(dead, makeActive: true);
      final d = await db.creationDraft(seed: 'birth');
      expect(d.entitlement.points, 6);
      await db.saveBirthChoice(d.id, 1, [2, 2, 1, 1]);
      expect((await db.creationDraft()).toJson(), d.toJson());
      expect((await db.appRecord('birthChoice'))!['points'], [2, 2, 1, 1]);
      final next = fresh('next'); // require the actual draft seed
      final valid = WorldGenerator.generate(
        seed: d.seed,
        worldId: next.id,
        npcCount: 12,
        regionCount: 1,
        placesPerRegion: 10,
      );
      await expectLater(
        db.createLife(valid, d, 1, [2, 2, 1, 1], failBeforeCommit: true),
        throwsStateError,
      );
      expect((await db.load())!.id, 'dead');
      expect((await db.rebirth()).points, 6);
      expect((await db.creationDraft()).id, d.id);
      await db.createLife(valid, d, 1, [2, 2, 1, 1]);
      final loaded = (await db.load())!;
      expect(
        loaded.player.attributes.values,
        BirthRules.allocate(d, 1, [2, 2, 1, 1]).values,
      );
      expect(loaded.player.hp, GameCommandService.maxHp(loaded.player));
      expect(loaded.birth!['source'], 'dead');
      expect((await db.rebirth()).points, 0);
      await expectLater(
        db.createLife(fresh('duplicate'), d, 1, [2, 2, 1, 1]),
        throwsA(isA<RuleViolation>()),
      );
      expect((await db.load(id: 'dead'))!.assessment!['score'], 700);
    },
  );
  test(
    'latest death determines points instead of historical maximum',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      await db.save(
        fresh('older')
          ..frozen = true
          ..assessment = {'score': 2500},
        makeActive: true,
      );
      await db.save(
        fresh('newer')
          ..frozen = true
          ..assessment = {'score': 120},
        makeActive: true,
      );
      expect((await db.rebirth()).points, 2);
      expect((await db.rebirth()).source, 'newer');
    },
  );
  test('feedback is actual combat output and never persisted or replayed', () {
    final w = fresh();
    final npc = w.entities.values.firstWhere(
      (n) => n.type == KarmaNodeType.npc && n.location == w.player.location,
    );
    npc.hp = 100;
    npc.realm = 0;
    w.player.hp = 100;
    var next = GameCommandService().execute(
      w,
      GameCommand('startBattle', target: npc.id),
    );
    final before = next.entities[npc.id]!.hp;
    next = GameCommandService().execute(next, const GameCommand('attack'));
    expect(next.feedback!.damage, before - next.entities[npc.id]!.hp);
    expect(next.feedback!.received, greaterThan(0));
    expect(
      World.fromJson(jsonDecode(jsonEncode(next.toJson()))).feedback,
      isNull,
    );
    expect(
      () => GameCommandService().execute(
        next,
        const GameCommand('equip', item: 'x'),
      ),
      throwsA(isA<RuleViolation>()),
    );
  });
  testWidgets(
    'animation locks buttons, completes, honors reduced motion and fits large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      Widget app(GameView v, {bool reduced = false}) => MaterialApp(
        theme: InkTheme.build(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 700),
            textScaler: TextScaler.linear(1.5),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: BattleStage(
                view: v,
                busy: false,
                onCommand: (_) => taps++,
              ),
            ),
          ),
        ),
      );
      const initial = GameView(
        battleName: '试炼修士',
        hp: 100,
        battleHp: 100,
        battleQi: 10,
      );
      const after = GameView(
        battleName: '试炼修士',
        hp: 88,
        battleHp: 82,
        battleQi: 10,
        combatFeedback: CombatFeedback(
          actionId: 'one',
          kind: 'attack',
          damage: 18,
          received: 12,
          healing: 0,
          absorbed: 0,
        ),
      );
      await tester.pumpWidget(app(initial));
      await tester.pumpWidget(app(after));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('出手攻击'));
      expect(taps, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('出手攻击'));
      expect(taps, 1);
      await tester.pumpWidget(
        app(
          const GameView(
            battleName: '试炼修士',
            hp: 88,
            battleHp: 70,
            combatFeedback: CombatFeedback(
              actionId: 'two',
              kind: 'defend',
              damage: 0,
              received: 5,
              healing: 0,
              absorbed: 0,
            ),
          ),
          reduced: true,
        ),
      );
      await tester.tap(find.text('出手攻击'));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
