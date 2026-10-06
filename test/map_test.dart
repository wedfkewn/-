import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/domain/map_repository.dart';

World fresh() =>
    WorldGenerator.generate(seed: 'shanhe', worldId: 'map', npcCount: 20);
void main() {
  test(
    '288 seeded locations are connected, preserve anchors, resources and RNG isolation',
    () {
      final a = fresh(), b = fresh();
      expect(a.mapPlaces.length, 288);
      expect(a.mapPlaces.values.map((p) => p.region).toSet().length, 12);
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      final reachable = <String>{a.player.location};
      var count = 0;
      while (count != reachable.length) {
        count = reachable.length;
        for (final road in a.mapRoads.values) {
          if (reachable.contains(road.a)) reachable.add(road.b);
          if (reachable.contains(road.b)) reachable.add(road.a);
        }
      }
      expect(reachable.length, 288);
      for (final material in MapRules.materials) {
        expect(
          a.mapPlaces.values.any(
            (p) => p.kind != PlaceKind.secret && p.resources.contains(material),
          ),
          isTrue,
        );
      }
      final legacy = WorldGenerator.generate(
        seed: 'shanhe',
        worldId: 'map',
        npcCount: 20,
        version: 1,
      );
      final rng = legacy.random.state;
      final before = legacy.events.length;
      MapRules.generate(legacy);
      expect(legacy.random.state, rng);
      expect(legacy.events.length, before);
      expect(legacy.entities['map:location:0']!.name, '青溪镇');
      expect(legacy.player.location, 'map:location:0');
    },
  );
  test(
    'queries, search and routing exclude unknown and unconfirmed destinations',
    () {
      final w = fresh();
      const hidden = 'map:location:200';
      final name = w.entities[hidden]!.name;
      expect(MapRepository(w).query(search: name).places, isEmpty);
      expect(MapRepository(w).route(hidden), isNull);
      w.discover(
        w.playerId,
        hidden,
        InformationChannel.rumor,
        confirmed: false,
      );
      final view = MapRepository(w).query(search: name);
      expect(view.places.single.confirmed, isFalse);
      expect(view.places.single.place.resources, isEmpty);
      expect(view.places.single.place.terrain, '待查证');
      expect(view.roads.any((r) => r.a == hidden || r.b == hidden), isFalse);
      expect(MapRepository(w).route(hidden), isNull);
    },
  );
  test(
    'planning costs no time, movement charges one segment and preserves state on restore',
    () {
      var w = fresh();
      final c = GameCommandService();
      final cursor = w.simulationCursor;
      final random = w.random.state;
      w = c.execute(
        w,
        const GameCommand('planRoute', target: 'map:location:4'),
      );
      expect(w.day, 0);
      expect(w.simulationCursor, cursor);
      expect(w.random.state, random);
      final path = MapRepository(w).route('map:location:4')!;
      final first = path.first;
      final coins = w.player.coins;
      w = c.execute(w, const GameCommand('moveStep'));
      expect(w.day, first.travelDays(0));
      expect(w.player.coins, coins - first.fee);
      expect(w.player.location, first.other('map:location:0'));
      final restored = World.fromJson(jsonDecode(jsonEncode(w.toJson())));
      expect(jsonEncode(restored.toJson()), jsonEncode(w.toJson()));
      if (w.encounter != null) {
        expect(
          () => c.execute(w, const GameCommand('moveStep')),
          throwsA(isA<RuleViolation>()),
        );
        w = c.execute(w, const GameCommand('chooseEncounter', item: 'leave'));
      }
      final day = w.day;
      w = c.execute(w, const GameCommand('cancelRoute'));
      expect(w.day, day);
      expect(w.journey, isNull);
    },
  );
  test(
    'map purchases reveal local region and a cross-region boundary only',
    () {
      var w = fresh();
      w = GameCommandService().execute(w, const GameCommand('buyMap'));
      expect(w.player.coins, 70);
      expect(w.knows(w.playerId, 'map:location:23'), isTrue);
      expect(w.knows(w.playerId, 'map:location:24'), isTrue);
      expect(w.knows(w.playerId, 'map:location:200'), isFalse);
      expect(MapRepository(w).route('map:location:24'), isNotNull);
    },
  );
  test(
    'travel multiplier, opening calendar and failed commands are deterministic',
    () {
      final road = fresh().mapRoads.values.first;
      expect(road.travelDays(2), (road.days * .7).ceil());
      expect(road.travelDays(3), (road.days * .5).ceil());
      final secret = fresh().mapPlaces.values.firstWhere(
        (p) => p.kind == PlaceKind.secret,
      );
      expect(secret.open(19), isTrue);
      expect(secret.open(20), isFalse);
      expect(secret.nextOpening(20), 90);
      final w = fresh();
      final before = jsonEncode(w.toJson());
      expect(
        () => GameCommandService().execute(w, const GameCommand('moveStep')),
        throwsA(isA<RuleViolation>()),
      );
      expect(jsonEncode(w.toJson()), before);
    },
  );
  test('default and stress-size maps keep public query sizes bounded', () {
    for (final count in [1200, 5000]) {
      final w = WorldGenerator.generate(
        seed: 'scale-map',
        worldId: 'large-map',
        npcCount: count,
      );
      final view = MapRepository(w).query();
      expect(w.mapPlaces.length, 288);
      expect(view.places.length, lessThan(40));
      expect(view.roads.length, lessThan(80));
      expect(MapRepository(w).query(search: '天渊').places, isEmpty);
    }
  });
}
