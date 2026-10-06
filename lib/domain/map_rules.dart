part of 'engine.dart';

abstract final class MapRules {
  static const materials = [
    '筑基丹',
    '凝丹灵液',
    '结婴丹',
    '化神香',
    '虚空晶',
    '合道石',
    '大乘道果',
    '渡劫符',
  ];
  static void generate(World w) {
    if (w.mapVersion != 0 || w.frozen) return;
    final terrain = SeedRandom(
      SeedRandom.hash(
        '${w.seed}:map:2:terrain:${w.regionCount}:${w.placesPerRegion}',
      ),
    );
    final roads = SeedRandom(
      SeedRandom.hash(
        '${w.seed}:map:2:roads:${w.regionCount}:${w.placesPerRegion}',
      ),
    );
    final resources = SeedRandom(
      SeedRandom.hash(
        '${w.seed}:map:2:resources:${w.regionCount}:${w.placesPerRegion}',
      ),
    );
    const prefixes = [
      '青岚',
      '云泽',
      '丹霞',
      '苍玄',
      '雪原',
      '赤岭',
      '玄海',
      '北荒',
      '星陨',
      '昆墟',
      '太虚',
      '天渊',
    ];
    for (var region = 0; region < w.regionCount; region++) {
      final name =
          '${prefixes[region % prefixes.length]}${region >= prefixes.length ? region + 1 : ''}州';
      for (var i = 0; i < w.placesPerRegion; i++) {
        final index = region * w.placesPerRegion + i;
        final id = '${w.id}:location:$index';
        final kind = region == 0 && i < 5
            ? [
                PlaceKind.town,
                PlaceKind.wild,
                PlaceKind.sect,
                PlaceKind.market,
                PlaceKind.wild,
              ][i]
            : PlaceKind.values[(i + 3) % PlaceKind.values.length];
        final danger = (region * 8 ~/ (w.regionCount - 1).clamp(1, 24)).clamp(
          0,
          8,
        );
        final material = materials[danger.clamp(0, 7)];
        final goods = <String>[
          if ([PlaceKind.wild, PlaceKind.ruin, PlaceKind.secret].contains(kind))
            '灵草',
          if ([
            PlaceKind.wild,
            PlaceKind.ruin,
            PlaceKind.secret,
            PlaceKind.sect,
          ].contains(kind))
            material,
          if ([PlaceKind.town, PlaceKind.market].contains(kind)) ...[
            '回春丹',
            '聚灵丹',
            '护脉丹',
            ...materials.take((danger + 1).clamp(1, 3)),
          ],
        ];
        if (!w.entities.containsKey(id)) {
          w.entities[id] = Entity(
            id: id,
            type: KarmaNodeType.location,
            name: '${name.substring(0, name.length - 1)}${kind.label}·${i + 1}',
            importance: 2,
            created: w.day,
            updated: w.day,
          );
        }
        w.mapPlaces[id] = MapPlace(
          id,
          region,
          name,
          kind,
          80 + (i % 6) * 140 + terrain.next(45).toDouble(),
          80 + (i ~/ 6) * 155 + terrain.next(45).toDouble(),
          ['平原', '山地', '河谷', '林地'][terrain.next(4)],
          (kind == PlaceKind.vein ? 3 : 1) + resources.next(3),
          danger,
          goods,
        );
      }
    }
    void connect(int a, int b, {bool cross = false}) {
      final id = '${w.id}:road:$a:$b';
      if (w.mapRoads.containsKey(id)) return;
      final ferry = roads.next(5) == 0;
      w.mapRoads[id] = MapRoad(
        id,
        '${w.id}:location:$a',
        '${w.id}:location:$b',
        cross ? 12 + roads.next(9) : 3 + roads.next(6),
        ferry || cross ? 3 + roads.next(5) : 0,
        cross
            ? '跨州古道'
            : ferry
            ? '渡口'
            : '山路',
      );
    }

    for (var region = 0; region < w.regionCount; region++) {
      final base = region * w.placesPerRegion;
      for (var i = 1; i < w.placesPerRegion; i++) {
        connect(base + i - 1, base + i);
      }
      for (var i = 0; i + 6 < w.placesPerRegion; i++) {
        if (roads.next(3) == 0) connect(base + i, base + i + 6);
      }
      if (region + 1 < w.regionCount) {
        connect(
          base + w.placesPerRegion - 1,
          base + w.placesPerRegion,
          cross: true,
        );
      }
    }
    // A guaranteed free, safe starter route, independent of random ferries.
    for (var i = 0; i < 4; i++) {
      final id = '${w.id}:road:$i:${i + 1}';
      w.mapRoads[id] = MapRoad(
        id,
        '${w.id}:location:$i',
        '${w.id}:location:${i + 1}',
        3,
        0,
        '青溪古道',
      );
    }
    w.mapVersion = 2;
  }

  static void revealNearby(
    World w,
    String observer,
    InformationChannel channel, {
    String? source,
  }) {
    final location = w.entities[observer]!.location;
    w.discover(observer, location, channel, source: source, geography: true);
    for (final sect in w.entities.values.where(
      (e) => e.type == KarmaNodeType.sect && e.location == location,
    )) {
      w.discover(observer, sect.id, channel, source: source);
    }
    for (final road in w.mapRoads.values.where(
      (r) => r.a == location || r.b == location,
    )) {
      w.discover(
        observer,
        road.other(location),
        channel,
        source: source,
        geography: true,
      );
    }
  }

  static void plan(World w, FactWriter f, String? target) {
    if (target == null || target == w.player.location) {
      throw const RuleViolation('请选择其他已知地点');
    }
    final path = MapRepository(w).route(target);
    if (path == null || path.isEmpty) {
      throw const RuleViolation('没有已知可通行路线，请先调查或获取地图');
    }
    final e = f.event(
      'planRoute',
      '规划行旅',
      '沿已知道路前往${w.entities[target]!.name}。',
      [w.playerId],
    );
    w.journey = Journey(target, path.map((r) => r.id).toList(), origin: e.id);
  }

  static MapRoad nextRoad(World w) {
    final j = w.journey;
    if (j == null || j.complete) throw const RuleViolation('请先规划路线');
    final road = w.mapRoads[j.roads[j.index]]!;
    if (road.a != w.player.location && road.b != w.player.location) {
      throw const RuleViolation('路线已变化，请重新规划');
    }
    if (!w.knows(w.playerId, road.other(w.player.location))) {
      throw const RuleViolation('未知道路');
    }
    if (w.player.coins < road.fee) throw const RuleViolation('路费不足');
    return road;
  }

  static void move(World w, FactWriter f) {
    final road = nextRoad(w);
    w.player.coins -= road.fee;
    w.player.location = road.other(w.player.location);
    final j = w.journey!;
    final e = f.event(
      'travel',
      '行至${w.entities[w.player.location]!.name}',
      '${road.kind}行旅${road.travelDays(w.player.realm)}日，路费${road.fee}灵石。',
      [w.playerId],
      causes: j.origin == null ? [] : [Cause(j.origin!, CausalKind.direct)],
    );
    j.index++;
    j.origin = e.id;
    revealNearby(w, w.playerId, InformationChannel.witness, source: e.id);
    for (final n in w.entities.values.where(
      (n) =>
          n.type == KarmaNodeType.npc &&
          n.alive &&
          n.location == w.player.location,
    )) {
      w.discover(w.playerId, n.id, InformationChannel.witness, source: e.id);
    }
    if (j.complete) w.journey = null;
    if (w.adventureRandom.next(100) < 18) {
      w.encounter = AdventureRules.discover(w, f, null);
      final discovery = w.events[w.encounter!.origin]!;
      w.events[discovery.id] = GameEvent(
        id: discovery.id,
        time: discovery.time,
        kind: discovery.kind,
        title: discovery.title,
        description: discovery.description,
        location: discovery.location,
        participants: discovery.participants,
        causes: [Cause(e.id, CausalKind.direct)],
      );
    }
  }

  static void buyMap(World w, FactWriter f) {
    final p = w.mapPlaces[w.player.location]!;
    if (![PlaceKind.town, PlaceKind.market].contains(p.kind)) {
      throw const RuleViolation('请在城镇或坊市购买地图');
    }
    if (w.player.coins < 10) throw const RuleViolation('购买地图需要10灵石');
    w.player.coins -= 10;
    final e = f.event('buyMap', '购得州域地图', '获得本州地理与相邻州界的确认情报。', [w.playerId]);
    for (final point in w.mapPlaces.values.where((v) => v.region == p.region)) {
      w.discover(
        w.playerId,
        point.id,
        InformationChannel.investigation,
        geography: true,
        source: e.id,
      );
    }
    for (final road in w.mapRoads.values) {
      if (w.mapPlaces[road.a]!.region == p.region ||
          w.mapPlaces[road.b]!.region == p.region) {
        w.discover(
          w.playerId,
          road.a,
          InformationChannel.investigation,
          geography: true,
          source: e.id,
        );
        w.discover(
          w.playerId,
          road.b,
          InformationChannel.investigation,
          geography: true,
          source: e.id,
        );
      }
    }
  }

  static void sectMap(World w, FactWriter f) {
    if (w.player.sect == null ||
        w.entities[w.player.sect]!.location != w.player.location) {
      throw const RuleViolation('请在本宗驻地领取情报');
    }
    final e = f.event('sectMap', '宗门山河情报', '领取本宗所知的驻地与邻路信息。', [
      w.playerId,
      w.player.sect!,
    ]);
    revealNearby(
      w,
      w.playerId,
      InformationChannel.sectIntelligence,
      source: e.id,
    );
  }

  static void ask(World w, FactWriter f, Entity npc) {
    final candidates =
        w.knowledge.values
            .where(
              (k) =>
                  k.observer == npc.id &&
                  w.mapPlaces.containsKey(k.subject) &&
                  !w.knows(w.playerId, k.subject),
            )
            .toList()
          ..sort((a, b) => a.subject.compareTo(b.subject));
    if (candidates.isEmpty) throw const RuleViolation('此人暂时没有新的地理情报');
    final k = candidates.first;
    final e = f.event(
      'directions',
      '${npc.name}指路',
      '告知${w.entities[k.subject]!.name}的所知情况。',
      [w.playerId, npc.id],
    );
    w.discover(
      w.playerId,
      k.subject,
      InformationChannel.told,
      confirmed: k.confirmed,
      geography: true,
      source: e.id,
    );
  }
}
