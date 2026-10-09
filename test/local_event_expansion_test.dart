import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/domain/models.dart';

const scenes = {
  'rain_pavilion': ('雨亭借宿', PlaceKind.town, ['rain_rest', 'rain_brew']),
  'old_kiln': ('废窑寻材', PlaceKind.ruin, ['kiln_gather', 'kiln_sort']),
  'river_garden': ('溪畔药圃', PlaceKind.wild, ['garden_gather', 'garden_cleanse']),
  'sword_marks': ('剑痕参悟', PlaceKind.ruin, ['sword_study', 'sword_trace']),
};

World fresh(PlaceKind kind, {String terrain = '河谷', bool herbs = true}) {
  final w = WorldGenerator.generate(
    seed: 'local-scenes',
    worldId: 'local-scenes',
    npcCount: 4,
  );
  final p = w.mapPlaces[w.player.location]!;
  w.mapPlaces[p.id] = MapPlace(
    p.id,
    p.region,
    p.regionName,
    kind,
    p.x,
    p.y,
    terrain,
    p.aura,
    p.danger,
    herbs ? ['灵草'] : [],
  );
  w.player.coins = 100;
  w.player.hp = GameCommandService.maxHp(w.player) - 50;
  for (final npc in w.entities.values.where(
    (e) => e.type == KarmaNodeType.npc,
  )) {
    npc.lastActed = 10000;
  }
  return w;
}

/// Select a persisted PRNG state, then let the real exploration command discover
/// the scene. No pending encounter, facts or rewards are injected into play.
World discover(String title, PlaceKind kind) {
  final w = fresh(kind);
  int? chosenState;
  for (var state = 1; state < 200; state++) {
    final candidate = w.copy()..adventureRandom.state = state;
    if (AdventureRules.discover(candidate, FactWriter(candidate), null).title ==
        title) {
      chosenState = state;
      break;
    }
  }
  expect(chosenState, isNotNull, reason: '$title must be locally reachable');
  w.adventureRandom.state = chosenState!;
  final result = GameCommandService().execute(w, const GameCommand('explore'));
  expect(result.encounter!.title, title);
  expect(result.encounter!.source, 'local');
  expect(result.day, 3);
  return result;
}

World choose(World w, String id, {String? actionId}) => GameCommandService()
    .execute(w, GameCommand('chooseEncounter', item: id, actionId: actionId));

Map<String, dynamic> proposal(String effect) => {
  'title': '溪风入亭',
  'text': '借一盏药茶，在雨声中调息。',
  'options': [
    {'label': '调息', 'effect': effect},
    {'label': '离开', 'effect': 'leave'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scene in scenes.entries) {
    test(
      '${scene.value.$1}: two distinct choices settle bounded costs and actual effects',
      () {
        final pending = discover(scene.value.$1, scene.value.$2);
        expect(pending.encounter!.text.runes.length, lessThanOrEqualTo(100));
        expect(pending.encounter!.options.map((o) => o.id), [
          ...scene.value.$3,
          'leave',
        ]);
        final choices = pending.encounter!.options
            .where((o) => !o.leaves)
            .toList();
        expect(choices[0].toJson(), isNot(choices[1].toJson()));
        for (final option in choices) {
          final result = choose(
            pending,
            option.id,
            actionId: 'pick-${option.id}',
          );
          expect(result.encounter, isNull);
          expect(result.day, pending.day + 1);
          expect(
            result.player.coins,
            pending.player.coins -
                option.cost +
                (option.effects.contains('coins')
                    ? 15 + pending.player.realm * 5
                    : 0),
          );
          expect(
            result.inventory['灵草'],
            pending.inventory['灵草']! +
                (option.effects.contains('herbs') ? 3 : 0),
          );
          expect(
            result.player.spirit,
            pending.player.spirit +
                (option.effects.contains('spirit')
                    ? 20 + pending.player.realm * 5
                    : 0),
          );
          expect(
            result.player.hp,
            pending.player.hp + (option.effects.contains('heal') ? 30 : 0),
          );
          expect(result.relations.keys, pending.relations.keys);
          expect(
            () => choose(result, option.id, actionId: 'pick-${option.id}'),
            throwsA(isA<RuleViolation>()),
          );
          final event = result.events.values.lastWhere(
            (e) => e.kind == 'encounterResult',
          );
          final selected = result.events.values.lastWhere(
            (e) => e.kind == 'encounterChoice',
          );
          expect(event.causes.single.eventId, selected.id);
          expect(event.causes.single.kind, CausalKind.direct);
          expect(selected.causes.single.eventId, pending.encounter!.origin);
          expect(result.knows(result.playerId, event.id), isTrue);
        }
        expect(
          pending.encounter,
          isNotNull,
          reason: 'commands must not mutate original',
        );
      },
    );
    test('${scene.value.$1}: safe exit costs zero and keeps resources', () {
      final pending = discover(scene.value.$1, scene.value.$2);
      final result = choose(pending, 'leave');
      expect(result.day, pending.day);
      expect(result.player.ageDays, pending.player.ageDays);
      expect(result.player.coins, pending.player.coins);
      expect(result.player.hp, pending.player.hp);
      expect(result.player.spirit, pending.player.spirit);
      expect(result.inventory, pending.inventory);
      expect(
        result.events.values
            .lastWhere((e) => e.kind == 'encounterResult')
            .title,
        '此缘暂别',
      );
    });
  }

  test(
    'scene eligibility follows confirmed terrain, resources and place type',
    () {
      Set<String> ideas(World w) =>
          AdventureRules.inspirations(w).map((i) => i['id'] as String).toSet();
      expect(ideas(fresh(PlaceKind.town)), {'rain_pavilion'});
      expect(ideas(fresh(PlaceKind.wild)), {
        'rain_pavilion',
        'old_kiln',
        'river_garden',
      });
      expect(ideas(fresh(PlaceKind.wild, terrain: '山地')), {
        'rain_pavilion',
        'old_kiln',
      });
      expect(ideas(fresh(PlaceKind.wild, herbs: false)), {'rain_pavilion'});
      expect(ideas(fresh(PlaceKind.ruin)), {'old_kiln', 'sword_marks'});
      expect(ideas(fresh(PlaceKind.sect)), {'rain_pavilion', 'sword_marks'});
      expect(ideas(fresh(PlaceKind.vein)), isEmpty);
      final hidden = fresh(PlaceKind.wild);
      hidden.knowledge.remove('${hidden.playerId}|${hidden.player.location}');
      expect(ideas(hidden), isEmpty);
      expect(
        AdventureRules.catalog(hidden).map((o) => o.id),
        isNot(contains('garden_cleanse')),
      );
      hidden.discover(
        hidden.playerId,
        hidden.player.location,
        InformationChannel.rumor,
        confirmed: false,
      );
      expect(ideas(hidden), isEmpty);
      hidden.discover(
        hidden.playerId,
        hidden.player.location,
        InformationChannel.witness,
      );
      final serialized = jsonEncode(AdventureRules.inspirations(hidden));
      expect(serialized, isNot(contains(hidden.player.location)));
      expect(serialized, isNot(contains(':npc:')));
    },
  );

  test(
    'insufficient funds reject atomically without day, reward or fact changes',
    () {
      for (final scene in scenes.values) {
        final pending = discover(scene.$1, scene.$2);
        final paid = pending.encounter!.options.lastWhere((o) => o.cost > 0);
        pending.player.coins = paid.cost - 1;
        final snapshot = jsonEncode(pending.toJson());
        expect(() => choose(pending, paid.id), throwsA(isA<RuleViolation>()));
        expect(jsonEncode(pending.toJson()), snapshot);
      }
    },
  );

  test(
    'local discovery draws only adventure stream, persisted choice needs no new RNG draw',
    () {
      final w = fresh(PlaceKind.wild);
      final streams = [w.random.state, w.equipmentRandom.state];
      final adventure = w.adventureRandom.state;
      w.encounter = AdventureRules.discover(w, FactWriter(w), null);
      expect([w.random.state, w.equipmentRandom.state], streams);
      expect(w.adventureRandom.state, isNot(adventure));
      final pending = discover('溪畔药圃', PlaceKind.wild);
      final saved = pending.adventureRandom.state;
      expect(choose(pending, 'garden_cleanse').adventureRandom.state, saved);
    },
  );

  test(
    'SQLite restores saved branches and explicit cause chain; failed commit preserves pending scene',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final pending = discover('废窑寻材', PlaceKind.ruin);
      await db.save(pending);
      final restored = (await db.load())!;
      expect(restored.encounter!.toJson(), pending.encounter!.toJson());
      final result = choose(restored, 'kiln_sort');
      expect(result.toJson(), choose(pending, 'kiln_sort').toJson());
      await expectLater(
        db.save(result, previous: restored, failBeforeCommit: true),
        throwsStateError,
      );
      expect((await db.load())!.toJson(), pending.toJson());
      await db.save(result, previous: restored);
      final saved = (await db.load())!;
      expect(saved.toJson(), result.toJson());
      final output = saved.events.values.lastWhere(
        (e) => e.kind == 'encounterResult',
      );
      final repo = KarmaRepository(saved);
      expect(
        repo.event(output.id)!.causes.single.eventId,
        saved.events.values.lastWhere((e) => e.kind == 'encounterChoice').id,
      );
      expect(saved.encounter, isNull);
    },
  );

  test(
    'AI may compose newly legal options, but cannot bypass location or reward caps',
    () {
      final w = fresh(PlaceKind.town);
      final before = w.adventureRandom.state;
      final pending = GameCommandService().execute(
        w,
        GameCommand('explore', proposal: proposal('rain_brew')),
      );
      expect(pending.encounter!.source, 'ai');
      expect(pending.adventureRandom.state, before);
      final result = choose(pending, 'rain_brew');
      expect(result.player.coins, pending.player.coins - 8);
      expect(result.player.spirit, pending.player.spirit + 20);
      for (final invalid in [
        proposal('garden_cleanse'),
        {...proposal('rain_brew'), 'coins': 999999},
        {...proposal('rain_brew'), 'target': 'fabricated'},
        {
          ...proposal('rain_brew'),
          'options': [
            {'label': '茶', 'effect': 'rain_brew', 'cost': 0},
            {'label': '离开', 'effect': 'leave'},
          ],
        },
      ]) {
        final snapshot = jsonEncode(w.toJson());
        expect(
          () => GameCommandService().execute(
            w,
            GameCommand('explore', proposal: invalid),
          ),
          throwsA(isA<RuleViolation>()),
        );
        expect(jsonEncode(w.toJson()), snapshot);
      }
    },
  );
}
