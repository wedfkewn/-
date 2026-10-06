import 'content.dart';
import 'models.dart';

class RuleViolation implements Exception {
  const RuleViolation(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The only writer of relationship and event facts.
class FactWriter {
  FactWriter(this.world) {
    for (final r in world.relations.values) {
      byPair[_key(r.source, r.target, r.type)] = r;
      adjacency.putIfAbsent(r.source, () => []).add(r);
      adjacency.putIfAbsent(r.target, () => []).add(r);
      for (final id in r.events) {
        eventRelations.putIfAbsent(id, () => []).add(r);
      }
    }
    for (final e in world.events.values) {
      for (final participant in e.participants) {
        latest['$participant:${e.kind}'] = e;
      }
    }
  }
  final World world;
  final Map<String, Relation> byPair = {};
  final Map<String, List<Relation>> adjacency = {};
  final Map<String, List<Relation>> eventRelations = {};
  final Map<String, GameEvent> latest = {};
  String _key(String a, String b, KarmaRelationType type) =>
      '$a|$b|${type.name}';
  GameEvent? last(String entity, String kind) => latest['$entity:$kind'];
  GameEvent event(
    String kind,
    String title,
    String description,
    List<String> participants, {
    String? location,
    List<Cause> causes = const [],
    int importance = 1,
    bool witnessed = true,
  }) {
    for (final c in causes) {
      if (!world.events.containsKey(c.eventId)) {
        throw const RuleViolation('因果来源不存在');
      }
    }
    final e = GameEvent(
      id: world.nextId('event'),
      time: world.day,
      kind: kind,
      title: title,
      description: description,
      location: location ?? world.player.location,
      participants: List.unmodifiable(participants),
      causes: List.unmodifiable(causes),
      importance: importance,
    );
    world.events[e.id] = e;
    for (final p in participants) {
      latest['$p:$kind'] = e;
      final observer = world.entities[p];
      if (observer != null &&
          (observer.location == e.location ||
              ![
                KarmaNodeType.player,
                KarmaNodeType.npc,
              ].contains(observer.type))) {
        world.discover(p, e.id, InformationChannel.witness);
      }
    }
    if (witnessed) {
      for (final observer in world.entities.values.where(
        (n) =>
            n.alive &&
            (n.type == KarmaNodeType.npc || n.type == KarmaNodeType.player) &&
            n.location == e.location,
      )) {
        reveal(e, observer.id, InformationChannel.witness);
      }
    }
    if (importance >= 3) {
      world.entities[e.id] = Entity(
        id: e.id,
        type: kind == 'war'
            ? KarmaNodeType.worldEvent
            : KarmaNodeType.historicalEvent,
        name: title,
        created: world.day,
        updated: world.day,
        importance: importance,
        location: e.location,
      );
      for (final p in participants) {
        relation(
          p,
          e.id,
          KarmaRelationType.eventParticipation,
          e,
          strength: importance * 10,
        );
      }
    }
    return e;
  }

  void reveal(
    GameEvent event,
    String observer,
    InformationChannel channel, {
    bool confirmed = true,
    String? source,
  }) {
    world.discover(
      observer,
      event.id,
      channel,
      confirmed: confirmed,
      source: source,
    );
    if (!confirmed) {
      return;
    }
    for (final p in event.participants) {
      world.discover(observer, p, channel, source: event.id);
    }
    if (world.entities.containsKey(event.location)) {
      world.discover(observer, event.location, channel, source: event.id);
    }
    for (final r in eventRelations[event.id] ?? <Relation>[]) {
      world.discover(observer, r.id, channel, source: event.id);
    }
  }

  Relation relation(
    String source,
    String target,
    KarmaRelationType type,
    GameEvent? e, {
    int strength = 20,
    bool bidirectional = false,
    String? inheritedFrom,
    bool public = false,
  }) {
    if (!world.entities.containsKey(source) ||
        !world.entities.containsKey(target)) {
      throw const RuleViolation('关系实体不存在');
    }
    var r = byPair[_key(source, target, type)];
    if (r == null && bidirectional) {
      r = byPair[_key(target, source, type)];
    }
    if (r == null) {
      r = Relation(
        id: world.nextId('relation'),
        source: source,
        target: target,
        type: type,
        strength: strength.clamp(1, 100),
        bidirectional: bidirectional,
        created: world.day,
        updated: world.day,
        inheritedFrom: inheritedFrom,
      );
      world.relations[r.id] = r;
      byPair[_key(source, target, type)] = r;
      adjacency.putIfAbsent(source, () => []).add(r);
      adjacency.putIfAbsent(target, () => []).add(r);
    } else {
      r.strength = (r.strength + strength).clamp(1, 100);
      r.updated = world.day;
      r.status = RelationStatus.active;
    }
    if (e != null && !r.events.contains(e.id)) {
      r.events.add(e.id);
      eventRelations.putIfAbsent(e.id, () => []).add(r);
    }
    for (final observer in [source, target]) {
      if (e != null && !world.knows(observer, e.id)) {
        continue;
      }
      world.discover(observer, source, InformationChannel.witness);
      world.discover(observer, target, InformationChannel.witness);
      world.discover(observer, r.id, InformationChannel.witness);
    }
    if (public) {
      world.discover(
        world.playerId,
        source,
        InformationChannel.sectIntelligence,
      );
      world.discover(
        world.playerId,
        target,
        InformationChannel.sectIntelligence,
      );
      world.discover(world.playerId, r.id, InformationChannel.sectIntelligence);
    }
    if (e != null) {
      for (final k
          in world.knowledge.values
              .where((k) => k.subject == e.id && k.confirmed)
              .toList()) {
        world.discover(k.observer, r.id, k.channel, source: e.id);
      }
    }
    return r;
  }

  void die(Entity victim, GameEvent cause) {
    victim.alive = false;
    victim.hp = 0;
    victim.updated = world.day;
    final death = event(
      'death',
      '${victim.name}陨落',
      '${victim.name}的生命终结，曾经的关系留在历史中。',
      [victim.id],
      location: victim.location,
      causes: [Cause(cause.id, CausalKind.direct)],
      importance: 3,
      witnessed: cause.kind != 'secretKill',
    );
    for (final r in List<Relation>.from(adjacency[victim.id] ?? [])) {
      if (r.type == KarmaRelationType.eventParticipation) {
        continue;
      }
      r.status = RelationStatus.historical;
      r.updated = world.day;
      r.events.add(death.id);
      eventRelations.putIfAbsent(death.id, () => []).add(r);
      for (final k
          in world.knowledge.values
              .where((k) => k.subject == death.id && k.confirmed)
              .toList()) {
        world.discover(k.observer, r.id, k.channel, source: death.id);
      }
      // Only known heirs can inherit a financial obligation. Their knowledge is
      // established by notification later, not by death itself.
    }
    if (victim.id == world.playerId) {
      world.frozen = true;
    }
  }
}

class WorldGenerator {
  static World generate({
    required String seed,
    required String worldId,
    String name = '李长生',
    int npcCount = 120,
    int version = 1,
  }) {
    if (version != Content.version || npcCount < 1 || npcCount > 10000) {
      throw const RuleViolation('不支持的世界生成配置');
    }
    final rng = SeedRandom(SeedRandom.hash('$seed|$version|$npcCount'));
    final w = World(
      id: worldId,
      seed: seed,
      playerId: '$worldId:player',
      random: rng,
      generationVersion: version,
      npcCount: npcCount,
    );
    for (var i = 0; i < Content.places.length; i++) {
      final id = '$worldId:location:$i';
      w.entities[id] = Entity(
        id: id,
        type: KarmaNodeType.location,
        name: Content.places[i],
        importance: 2,
      );
    }
    for (var i = 0; i < Content.sects.length; i++) {
      final id = '$worldId:sect:$i';
      w.entities[id] = Entity(
        id: id,
        type: KarmaNodeType.sect,
        name: Content.sects[i],
        importance: 4,
        location: '$worldId:location:${i + 1}',
      );
    }
    for (var i = 0; i < Content.families.length; i++) {
      final id = '$worldId:family:$i';
      w.entities[id] = Entity(
        id: id,
        type: KarmaNodeType.family,
        name: Content.families[i],
        importance: 2,
      );
    }
    w.entities[w.playerId] = Entity(
      id: w.playerId,
      type: KarmaNodeType.player,
      name: name.trim().isEmpty ? '李长生' : name.trim(),
      importance: 5,
      location: '$worldId:location:0',
      coins: 80,
    );
    const firstNames = [
      '长风',
      '清雪',
      '无涯',
      '烬',
      '云',
      '玄真',
      '明月',
      '青山',
      '如玉',
      '知秋',
    ];
    for (var i = 0; i < npcCount; i++) {
      final familyIndex = rng.next(Content.families.length);
      final id = '$worldId:npc:$i';
      w.entities[id] = Entity(
        id: id,
        type: KarmaNodeType.npc,
        name:
            '${Content.families[familyIndex][0]}${firstNames[rng.next(firstNames.length)]}${i < 10 ? '' : '·$i'}',
        location:
            '$worldId:location:${i < 4 ? 0 : rng.next(Content.places.length)}',
        family: '$worldId:family:$familyIndex',
        realm: i < 4 ? 0 : rng.next(4),
        hp: i < 2 ? 35 : 100,
        spirit: rng.next(30),
        ageDays: (18 + rng.next(40)) * 360,
        personality: ['重义', '谨慎', '好战'][rng.next(3)],
      );
    }
    final f = FactWriter(w);
    for (final npc
        in w.entities.values
            .where((e) => e.type == KarmaNodeType.npc)
            .toList()) {
      f.relation(
        npc.id,
        npc.family!,
        KarmaRelationType.kinship,
        null,
        strength: 40,
      );
      if (npc.realm > 0) {
        npc.sect = '$worldId:sect:${rng.next(3)}';
        f.relation(
          npc.id,
          npc.sect!,
          KarmaRelationType.sectAffiliation,
          null,
          strength: 30,
        );
      }
      final index = int.parse(npc.id.split(':').last);
      if (index > 0) {
        final elder = w.entities['$worldId:npc:${index - 1}']!;
        if (elder.family == npc.family) {
          f.relation(
            elder.id,
            npc.id,
            KarmaRelationType.kinship,
            null,
            bidirectional: true,
            strength: 40,
          );
        }
        if (elder.realm > npc.realm) {
          f.relation(
            elder.id,
            npc.id,
            KarmaRelationType.masterDisciple,
            null,
            strength: 25,
          );
        }
      }
    }
    f.relation(
      '$worldId:sect:1',
      '$worldId:sect:2',
      KarmaRelationType.rivalry,
      null,
      strength: 60,
      bidirectional: true,
    );
    for (final e in w.entities.values.where(
      (e) =>
          e.type == KarmaNodeType.location ||
          e.type == KarmaNodeType.sect ||
          e.id == w.playerId ||
          (e.type == KarmaNodeType.npc && e.location == w.player.location),
    )) {
      w.discover(w.playerId, e.id, InformationChannel.witness);
    }
    f.event('birth', '踏入仙途', '${w.player.name}在青溪镇踏上修行之路。', [w.playerId]);
    return w;
  }
}

class GameCommand {
  const GameCommand(
    this.kind, {
    this.target,
    this.item,
    this.amount = 1,
    this.secret = false,
  });
  final String kind;
  final String? target, item;
  final int amount;
  final bool secret;
}

class GameCommandService {
  final simulation = WorldSimulationService();
  World execute(World original, GameCommand command) {
    if (original.frozen || !original.player.alive) {
      throw const RuleViolation('这一世已经结束，历史只能查看');
    }
    if (!Content.durations.containsKey(command.kind)) {
      throw const RuleViolation('未知行动');
    }
    if (original.battleTarget != null &&
        !['attack', 'skill', 'useItem', 'flee'].contains(command.kind)) {
      throw const RuleViolation('战斗中只能攻击、施法、用药或逃跑');
    }
    final w = original.copy();
    final f = FactWriter(w);
    final p = w.player;
    Entity target({bool nearby = true}) {
      final t = w.entities[command.target];
      if (t == null || t.type != KarmaNodeType.npc || !w.knows(p.id, t.id)) {
        throw const RuleViolation('没有可交互的已知人物');
      }
      if (!t.alive) {
        throw const RuleViolation('此人已陨落');
      }
      if (nearby && t.location != p.location) {
        throw const RuleViolation('此人不在当前地点');
      }
      return t;
    }

    void spend(int coins) {
      if (p.coins < coins) {
        throw const RuleViolation('灵石不足');
      }
      p.coins -= coins;
    }

    void consume(String item, int count) {
      if ((w.inventory[item] ?? 0) < count) {
        throw RuleViolation('$item不足');
      }
      w.inventory[item] = w.inventory[item]! - count;
    }

    GameEvent action(
      String title,
      String description, {
      String? kind,
      List<String>? participants,
      int importance = 1,
      List<Cause> causes = const [],
    }) => f.event(
      kind ?? command.kind,
      title,
      description,
      participants ?? [p.id],
      importance: importance,
      causes: causes,
    );
    final cost = Content.durations[command.kind]!;
    w.day += cost;
    p.ageDays += cost;
    switch (command.kind) {
      case 'cultivate':
        final gain =
            25 +
            w.techniques.fold<int>(0, (sum, t) => sum + Content.techniques[t]!);
        p.spirit += gain;
        p.hp = (p.hp + 15).clamp(0, maxHp(p));
        action('闭关修炼', '运转功法，修为增加 $gain。');
      case 'breakthrough':
        if (p.realm >= Content.realms.length - 1) {
          throw const RuleViolation('已至渡劫巅峰');
        }
        final threshold = (p.realm + 1) * 80;
        if (p.spirit < threshold) {
          throw RuleViolation('突破需要 $threshold 修为');
        }
        p.spirit -= threshold;
        final protection = w.techniques.contains('长春诀') ? 10 : 0;
        if (w.random.next(100) < 75 + protection) {
          p.realm++;
          p.hp = maxHp(p);
          action(
            '突破${Content.realms[p.realm]}',
            '经历天劫洗礼，寿元与神识提升。',
            importance: 3,
          );
        } else {
          p.hp -= 35 + p.realm * 10;
          final e = action('突破受挫', '经脉受损，突破失败。');
          if (p.hp <= 0) {
            f.die(p, e);
          }
        }
      case 'travel':
        final place = w.entities[command.target];
        if (place?.type != KarmaNodeType.location ||
            !w.knows(p.id, place!.id)) {
          throw const RuleViolation('未知地点');
        }
        p.location = place.id;
        action('行至${place.name}', '沿山路抵达${place.name}。');
        for (final n in w.entities.values.where(
          (n) =>
              n.type == KarmaNodeType.npc &&
              n.alive &&
              n.location == p.location,
        )) {
          w.discover(p.id, n.id, InformationChannel.witness);
        }
      case 'explore':
        final outcome = w.random.next(4);
        if (outcome == 0) {
          w.inventory['灵草'] = (w.inventory['灵草'] ?? 0) + 3;
          action('采得灵草', '发现三株可炼丹的灵草。');
        } else if (outcome == 1) {
          p.coins += 15;
          action('古道遗宝', '寻得十五枚灵石。');
        } else if (outcome == 2) {
          final nearby = w.entities.values
              .where(
                (n) =>
                    n.type == KarmaNodeType.npc &&
                    n.alive &&
                    n.location == p.location,
              )
              .toList();
          if (nearby.isNotEmpty) {
            final n = nearby[w.random.next(nearby.length)];
            n.hp = (n.hp - 30).clamp(1, maxHp(n));
            action(
              '发现负伤修士',
              '${n.name}遇险受伤，可出手救助。',
              participants: [p.id, n.id],
            );
          } else {
            action('山野寻访', '此处未遇修士，记录沿途山川。');
          }
        } else {
          w.quests.putIfAbsent('古碑', () => 0);
          action('发现古碑', '古碑记载丹方线索，可在奇遇中继续调查。');
        }
      case 'rescue':
        final n = target();
        if (n.hp >= maxHp(n)) {
          throw const RuleViolation('此人无需救助');
        }
        consume('回春丹', 1);
        n.hp = maxHp(n);
        final e = action(
          '救下${n.name}',
          '${p.name}以回春丹救助${n.name}。',
          participants: [p.id, n.id],
          importance: 3,
        );
        f.relation(n.id, p.id, KarmaRelationType.gratitude, e, strength: 70);
        for (final promise in f.adjacency[p.id] ?? <Relation>[]) {
          if (promise.source == p.id &&
              promise.target == n.id &&
              promise.type == KarmaRelationType.promise &&
              promise.status == RelationStatus.active) {
            promise
              ..status = RelationStatus.settled
              ..updated = w.day
              ..events.add(e.id);
          }
        }
      case 'befriend':
        final n = target();
        final e = action(
          '结交${n.name}',
          '论道相契，结为朋友。',
          participants: [p.id, n.id],
        );
        f.relation(
          p.id,
          n.id,
          KarmaRelationType.friendship,
          e,
          bidirectional: true,
        );
      case 'apprentice':
        final n = target();
        if (n.realm <= p.realm) {
          throw const RuleViolation('师父境界须高于自己');
        }
        spend(20);
        final e = action(
          '拜${n.name}为师',
          '奉上拜师礼，受传道之恩。',
          participants: [p.id, n.id],
          importance: 3,
        );
        f.relation(
          n.id,
          p.id,
          KarmaRelationType.masterDisciple,
          e,
          strength: 50,
        );
      case 'joinSect':
        final sect = w.entities[command.target];
        if (sect?.type != KarmaNodeType.sect ||
            !sect!.alive ||
            !w.knows(p.id, sect.id)) {
          throw const RuleViolation('无法加入该宗门');
        }
        if (p.sect == sect.id) {
          throw const RuleViolation('已是本宗弟子');
        }
        spend(20);
        if (p.sect != null) {
          for (final r in f.adjacency[p.id] ?? <Relation>[]) {
            if (r.type == KarmaRelationType.sectAffiliation &&
                r.status == RelationStatus.active) {
              r.status = RelationStatus.historical;
              r.updated = w.day;
            }
          }
        }
        p.sect = sect.id;
        final e = action(
          '加入${sect.name}',
          '正式拜入宗门，获得情报与委托。',
          participants: [p.id, sect.id],
          importance: 3,
        );
        f.relation(
          p.id,
          sect.id,
          KarmaRelationType.sectAffiliation,
          e,
          strength: 40,
        );
        w.quests.putIfAbsent('宗门委托', () => 0);
      case 'trade':
        final item = command.item;
        final price = Content.prices[item];
        if (price == null || command.amount == 0 || command.amount.abs() > 99) {
          throw const RuleViolation('交易数量或物品无效');
        }
        if (command.amount > 0) {
          spend(price * command.amount);
          w.inventory[item!] = (w.inventory[item] ?? 0) + command.amount;
        } else {
          consume(item!, -command.amount);
          p.coins += price * -command.amount ~/ 2;
        }
        final merchant = command.target == null ? null : target();
        final e = action(
          '坊市交易',
          '${command.amount > 0 ? '购入' : '售出'}$item × ${command.amount.abs()}。',
          participants: [p.id, if (merchant != null) merchant.id],
        );
        if (merchant != null) {
          f.relation(
            p.id,
            merchant.id,
            KarmaRelationType.friendship,
            e,
            strength: 2,
            bidirectional: true,
          );
        }
      case 'craft':
        final item = command.item;
        final herbs = Content.recipes[item];
        if (herbs == null) {
          throw const RuleViolation('未知丹方');
        }
        consume('灵草', herbs);
        spend(3);
        w.inventory[item!] = (w.inventory[item] ?? 0) + 1;
        action('炼成$item', '消耗 $herbs 株灵草，丹成一枚。');
      case 'learn':
        final item = command.item;
        if (!Content.techniques.containsKey(item) ||
            w.techniques.contains(item)) {
          throw const RuleViolation('功法无效或已经掌握');
        }
        consume(item!, 1);
        w.techniques.add(item);
        action('参悟$item', '功法融会贯通，修炼与神识增强。');
      case 'equip':
        final item = command.item;
        if (!['青锋剑', '玄铁甲'].contains(item) || (w.inventory[item] ?? 0) < 1) {
          throw const RuleViolation('未持有此装备');
        }
        if (item == '青锋剑') {
          w.weapon = item;
        } else {
          w.armor = item;
        }
        action('装备$item', '装备效果已生效。');
      case 'useItem':
        final item = command.item;
        if (!['回春丹', '聚灵丹'].contains(item)) {
          throw const RuleViolation('不能使用此物品');
        }
        consume(item!, 1);
        if (item == '回春丹') {
          p.hp = (p.hp + 65).clamp(0, maxHp(p));
        } else {
          p.spirit += 40;
        }
        action('服用$item', '丹药灵力化入经脉。');
        if (w.battleTarget != null) {
          _counterattack(w, f);
        }
      case 'quest':
        final key = command.item;
        final stage = w.quests[key];
        if (stage == null || stage >= 3) {
          throw const RuleViolation('没有可推进的奇遇');
        }
        if (key == '宗门委托') {
          if (p.sect == null) {
            throw const RuleViolation('需先加入宗门');
          }
          if (stage == 0) {
            consume('灵草', 2);
          } else if (stage == 1) {
            consume('回春丹', 1);
          }
          if (stage == 2) {
            p.coins += 70;
            p.spirit += 30;
          }
        } else if (key == '古碑') {
          if (stage == 1 && command.target == 'leave') {
            w.quests[key!] = 3;
            action('放下古碑之缘', '选择离去，奇遇就此了结。');
            break;
          }
          if (stage == 1) {
            spend(10);
          }
          if (stage == 2) {
            w.inventory['天机诀'] = (w.inventory['天机诀'] ?? 0) + 1;
          }
        }
        final previous = f.last(p.id, 'quest');
        w.quests[key!] = stage + 1;
        action(
          '$key · 第${stage + 1}阶段',
          stage == 2 ? '完成奇遇，取得报酬。' : '线索得到验证，下一阶段开启。',
          causes: previous?.title.startsWith(key) == true
              ? [Cause(previous!.id, CausalKind.direct)]
              : [],
          importance: stage == 2 ? 3 : 1,
        );
      case 'promise':
        final n = target();
        final e = action(
          '向${n.name}立下承诺',
          '答应在危难时援手。',
          participants: [p.id, n.id],
        );
        f.relation(p.id, n.id, KarmaRelationType.promise, e, strength: 35);
      case 'borrow':
        final n = target();
        if (n.coins < 20 ||
            (f.adjacency[p.id] ?? []).any(
              (r) =>
                  r.type == KarmaRelationType.debt &&
                  r.target == n.id &&
                  r.status == RelationStatus.active,
            )) {
          throw const RuleViolation('无法借款或尚有债务');
        }
        n.coins -= 20;
        p.coins += 20;
        final e = action(
          '向${n.name}借款',
          '借得二十灵石，负有偿还义务。',
          participants: [p.id, n.id],
        );
        f.relation(p.id, n.id, KarmaRelationType.debt, e, strength: 20);
      case 'repay':
        final n = target();
        final debts = (f.adjacency[p.id] ?? [])
            .where(
              (r) =>
                  r.type == KarmaRelationType.debt &&
                  r.source == p.id &&
                  r.target == n.id &&
                  r.status == RelationStatus.active,
            )
            .toList();
        if (debts.isEmpty) {
          throw const RuleViolation('没有需要偿还的债务');
        }
        spend(20);
        n.coins += 20;
        final e = action(
          '偿还${n.name}的债务',
          '债务已清，旧事仍可追溯。',
          participants: [p.id, n.id],
          causes: [
            Cause(
              debts.first.events.reversed.firstWhere(
                (id) => ['borrow', 'news'].contains(w.events[id]!.kind),
              ),
              CausalKind.direct,
            ),
          ],
        );
        debts.first
          ..status = RelationStatus.settled
          ..updated = w.day
          ..events.add(e.id);
      case 'companion':
        final n = target();
        final friends = (f.adjacency[p.id] ?? []).where(
          (r) =>
              r.type == KarmaRelationType.friendship &&
              (r.source == n.id || r.target == n.id) &&
              r.strength >= 60,
        );
        if (friends.isEmpty) {
          throw const RuleViolation('需先建立深厚友谊（强度60）');
        }
        final e = action(
          '与${n.name}结为道侣',
          '携手修行，共历仙途。',
          participants: [p.id, n.id],
          importance: 3,
        );
        f.relation(
          p.id,
          n.id,
          KarmaRelationType.daoCompanion,
          e,
          strength: 60,
          bidirectional: true,
        );
      case 'investigate':
        final n = target(nearby: false);
        spend(5);
        final subjects = (f.adjacency[n.id] ?? [])
            .where((r) => w.knows(n.id, r.id) && !w.knows(p.id, r.id))
            .take(4)
            .toList();
        for (final r in subjects) {
          w.discover(p.id, r.source, InformationChannel.investigation);
          w.discover(p.id, r.target, InformationChannel.investigation);
          w.discover(p.id, r.id, InformationChannel.investigation);
          for (final id in r.events) {
            final e = w.events[id];
            if (e != null && w.knows(n.id, id)) {
              f.reveal(e, p.id, InformationChannel.told, source: n.id);
            }
          }
        }
        action(
          '调查${n.name}',
          '通过走访与本人告知，获得 ${subjects.length} 条已确认关系。',
          participants: [p.id, n.id],
        );
      case 'divine':
        if (p.realm < 2) {
          throw const RuleViolation('金丹境方可感知天机');
        }
        spend(12);
        final awareness = Content.awareness(
          p.realm,
          p.spirit,
          w.techniques.contains('天机诀'),
        );
        final depth =
            (p.realm -
                    1 +
                    (w.techniques.contains('天机诀') ? 1 : 0) +
                    awareness ~/ 100)
                .clamp(1, 5);
        final known = w.knowledge.values
            .where(
              (k) =>
                  k.observer == p.id &&
                  k.confirmed &&
                  w.entities.containsKey(k.subject),
            )
            .map((k) => k.subject)
            .toSet();
        final candidates = <Relation>[];
        for (final id in known) {
          for (final r in f.adjacency[id] ?? <Relation>[]) {
            if (!w.knows(p.id, r.id) && !candidates.contains(r)) {
              candidates.add(r);
            }
          }
        }
        if (candidates.isNotEmpty &&
            w.random.next(100) <
                (45 + depth * 8 + awareness ~/ 20).clamp(0, 95)) {
          final r = candidates[w.random.next(candidates.length)];
          w.discover(
            p.id,
            r.source,
            InformationChannel.divination,
            depth: depth,
          );
          w.discover(
            p.id,
            r.target,
            InformationChannel.divination,
            depth: depth,
          );
          w.discover(p.id, r.id, InformationChannel.divination, depth: depth);
          for (final id in r.events.take(depth)) {
            f.reveal(w.events[id]!, p.id, InformationChannel.divination);
          }
          action('天机显现', '推演确认了一条深层关系。');
        } else {
          action('天机未明', '推演未得确证，未显露未知对象。');
        }
      case 'startBattle':
        final n = target();
        w.battleTarget = n.id;
        w.battleHp = n.hp;
        final e = f.event(
          command.secret ? 'secretKill' : 'challenge',
          '与${n.name}交战',
          '${p.name}向${n.name}发起战斗。',
          [p.id, n.id],
          witnessed: !command.secret,
        );
        w.battleOrigin = e.id;
      case 'attack':
      case 'skill':
        if (w.battleTarget == null) {
          throw const RuleViolation('当前没有战斗');
        }
        if (command.kind == 'skill') {
          if (p.spirit < 5) {
            throw const RuleViolation('施法需要五点修为');
          }
          p.spirit -= 5;
        }
        final n = w.entities[w.battleTarget]!;
        final damage =
            18 +
            p.realm * 14 +
            (w.weapon != null ? 12 : 0) +
            (command.kind == 'skill'
                ? 18 + (w.techniques.contains('御剑诀') ? 15 : 0)
                : 0);
        n.hp -= damage;
        w.battleHp = n.hp;
        final origin = w.events[w.battleOrigin]!;
        if (n.hp <= 0) {
          final e = f.event(
            origin.kind == 'secretKill' ? 'secretKill' : 'victory',
            '击败${n.name}',
            '${n.name}在战斗中身亡。',
            [p.id, n.id],
            causes: [Cause(origin.id, CausalKind.direct)],
            importance: 3,
            witnessed: origin.kind != 'secretKill',
          );
          f.die(n, e);
          p.coins += n.coins;
          n.coins = 0;
          w.battleTarget = null;
          w.battleOrigin = null;
        } else {
          f.event(
            'battleRound',
            '交战一合',
            '对${n.name}造成 $damage 伤害。',
            [p.id, n.id],
            causes: [Cause(origin.id, CausalKind.direct)],
            witnessed: origin.kind != 'secretKill',
          );
          _counterattack(w, f);
        }
      case 'flee':
        if (w.battleTarget == null) {
          throw const RuleViolation('当前没有战斗');
        }
        final n = w.entities[w.battleTarget]!;
        if (p.realm >= n.realm || w.random.next(100) < 65) {
          action('脱离战斗', '成功退走，交战的因果仍然存在。');
          w.battleTarget = null;
          w.battleOrigin = null;
        } else {
          action('逃跑失败', '被对手追上。');
          _counterattack(w, f);
        }
      case 'wait':
        action('静观世变', '三十日流转，世间修士各行其道。');
      default:
        throw const RuleViolation('未知行动');
    }
    if (!w.frozen && p.ageDays >= Content.lifespans[p.realm] * 360) {
      final e = action('寿元耗尽', '此世寿元已尽。', importance: 3);
      f.die(p, e);
    }
    if (!w.frozen) {
      simulation.advance(w, f, original.day);
    }
    if (w.frozen) {
      w.battleTarget = null;
      w.battleOrigin = null;
    }
    // Refresh facts that changed in a player-observed action, preserving all
    // remote knowledge snapshots otherwise.
    for (final r in w.relations.values.where(
      (r) => r.updated == w.day && w.knows(p.id, r.id),
    )) {
      if (r.events.any(
        (id) => w.events[id]?.time == w.day && w.knows(p.id, id),
      )) {
        w.discover(p.id, r.id, InformationChannel.witness);
      }
    }
    p.updated = w.day;
    if (w.frozen) {
      w.assessment = LifeAssessment.calculate(w);
    }
    w.revision++;
    return w;
  }

  static int maxHp(Entity e) => 100 + e.realm * 40;
  void _counterattack(World w, FactWriter f) {
    final n = w.entities[w.battleTarget]!;
    final p = w.player;
    final damage = (12 + n.realm * 12 - (w.armor != null ? 9 : 0)).clamp(
      3,
      150,
    );
    p.hp -= damage;
    final e = f.event(
      'counterattack',
      '${n.name}反击',
      '${p.name}受到 $damage 伤害。',
      [n.id, p.id],
      causes: [Cause(w.battleOrigin!, CausalKind.direct)],
      witnessed: w.events[w.battleOrigin]?.kind != 'secretKill',
    );
    if (p.hp <= 0) {
      f.die(p, e);
    }
  }
}

class WorldSimulationService {
  void advance(World w, FactWriter f, int fromDay) {
    // Relevant actors are always processed; the rest are a rotating batch.
    final priority = (f.adjacency[w.playerId] ?? [])
        .expand((r) => [r.source, r.target])
        .where((id) => id != w.playerId)
        .toSet();
    final npcs = w.entities.values
        .where(
          (e) =>
              e.type == KarmaNodeType.npc && e.alive && e.id != w.battleTarget,
        )
        .toList();
    final actors = <String, Entity>{};
    for (final id in priority) {
      final e = w.entities[id];
      if (e?.type == KarmaNodeType.npc && e!.alive && e.id != w.battleTarget) {
        actors[id] = e;
      }
    }
    for (var i = 0; i < 32 && i < npcs.length; i++) {
      final n = npcs[(w.simulationCursor + i) % npcs.length];
      actors[n.id] = n;
    }
    if (npcs.isNotEmpty) {
      w.simulationCursor = (w.simulationCursor + 32) % npcs.length;
    }
    for (final n in actors.values) {
      final elapsed = w.day - n.lastActed;
      if (elapsed < 30) {
        continue;
      }
      n.ageDays += elapsed;
      n.lastActed = w.day;
      if (n.ageDays >= Content.lifespans[n.realm] * 360) {
        final e = f.event('oldAge', '${n.name}寿尽', '寿元耗尽。', [
          n.id,
        ], location: n.location);
        f.die(n, e);
        continue;
      }
      n.spirit += elapsed ~/ 30 * (18 + (n.personality == '重义' ? 4 : 0));
      n.updated = w.day;
      final rescue = f.last(n.id, 'rescue');
      if (n.realm < 8 && n.spirit >= (n.realm + 1) * 60) {
        n.spirit -= (n.realm + 1) * 60;
        n.realm++;
        n.hp = GameCommandService.maxHp(n);
        f.event(
          'npcBreakthrough',
          '${n.name}突破${Content.realms[n.realm]}',
          '经长期修炼，境界获得突破。',
          [n.id],
          location: n.location,
          importance: 3,
          causes: rescue == null
              ? []
              : [Cause(rescue.id, CausalKind.influence)],
        );
      }
      if (n.realm >= 1 && n.sect == null) {
        final sects = w.entities.values
            .where((s) => s.type == KarmaNodeType.sect && s.alive)
            .toList();
        if (sects.isNotEmpty) {
          n.sect = sects[w.random.next(sects.length)].id;
          final breakthrough = f.last(n.id, 'npcBreakthrough');
          final e = f.event(
            'npcJoin',
            '${n.name}加入${w.entities[n.sect]!.name}',
            '达到入门条件，自主拜入宗门。',
            [n.id, n.sect!],
            location: n.location,
            importance: 3,
            causes: breakthrough == null
                ? []
                : [Cause(breakthrough.id, CausalKind.direct)],
          );
          f.relation(
            n.id,
            n.sect!,
            KarmaRelationType.sectAffiliation,
            e,
            strength: 35,
          );
        }
      }
      _learnNews(w, f, n);
      final debts = (f.adjacency[n.id] ?? [])
          .where(
            (r) =>
                r.source == n.id &&
                r.target == w.playerId &&
                r.type == KarmaRelationType.gratitude &&
                r.status == RelationStatus.active,
          )
          .toList();
      if (debts.isNotEmpty &&
          n.realm >= 1 &&
          w.day - debts.first.created >= 90 &&
          w.player.alive) {
        final r = debts.first;
        // Return to the last witnessed location, never track the player through
        // objective world state.
        final remembered =
            w.knowledge['${n.id}|${w.playerId}']?.snapshot['location']
                as String?;
        if (remembered != null) {
          n.location = remembered;
        }
        if (n.location != w.player.location) {
          continue;
        }
        for (final kind in ['npcBreakthrough', 'npcJoin']) {
          final report = f.last(n.id, kind);
          if (report != null && w.knows(n.id, report.id)) {
            f.reveal(report, w.playerId, InformationChannel.told, source: n.id);
          }
        }
        final crisis = f.event('crisis', '妖潮侵袭', '旅途中遇到妖潮，修士需合力抵御。', [
          w.playerId,
          n.id,
        ], importance: 4);
        final help = f.event(
          'repayment',
          '${n.name}报恩',
          '记起昔日救命之恩，${n.name}出手护持${w.player.name}。',
          [n.id, w.playerId],
          importance: 4,
          causes: [
            Cause(
              r.events.reversed.firstWhere(
                (id) => w.events[id]!.kind == 'rescue',
              ),
              CausalKind.direct,
            ),
            Cause(crisis.id, CausalKind.direct),
            if (f.last(n.id, 'npcJoin') != null)
              Cause(f.last(n.id, 'npcJoin')!.id, CausalKind.influence),
          ],
        );
        r
          ..status = RelationStatus.settled
          ..updated = w.day
          ..events.add(help.id);
        w.discover(
          w.playerId,
          r.id,
          InformationChannel.witness,
          source: help.id,
        );
        w.discover(n.id, r.id, InformationChannel.witness, source: help.id);
        w.player.coins += 35;
        w.player.hp = (w.player.hp + 30).clamp(
          0,
          GameCommandService.maxHp(w.player),
        );
        for (final promise in f.adjacency[w.playerId] ?? <Relation>[]) {
          if (promise.type == KarmaRelationType.promise &&
              promise.source == n.id &&
              promise.target == w.playerId &&
              promise.status == RelationStatus.active) {
            promise
              ..status = RelationStatus.settled
              ..updated = w.day
              ..events.add(help.id);
          }
        }
      }
      final choice = w.random.next(4);
      if (choice == 0) {
        n.location = '${w.id}:location:${w.random.next(Content.places.length)}';
        f.event(
          'migration',
          '${n.name}迁行',
          '离开旧地，前往${w.entities[n.location]!.name}。',
          [n.id],
          location: n.location,
        );
      } else if (choice == 1) {
        n.coins += 8;
        f.event('npcTrade', '${n.name}经商', '出售采集所得，积累修行资源。', [
          n.id,
        ], location: n.location);
      } else if (choice == 2) {
        final local = npcs
            .where(
              (other) =>
                  other.id != n.id &&
                  other.location == n.location &&
                  w.knows(n.id, other.id),
            )
            .toList();
        if (local.isNotEmpty) {
          final other = local[w.random.next(local.length)];
          final e = f.event(
            'npcFriendship',
            '${n.name}与${other.name}论道',
            '结识友人，社会关系发生变化。',
            [n.id, other.id],
            location: n.location,
          );
          f.relation(
            n.id,
            other.id,
            KarmaRelationType.friendship,
            e,
            bidirectional: true,
            strength: 10,
          );
        }
      }
      // Direct meetings reveal people, but not their private relationships.
      if (n.location == w.player.location) {
        w.discover(w.playerId, n.id, InformationChannel.witness);
      }
    }
    if (w.day ~/ 360 > fromDay ~/ 360) {
      _war(w, f);
    }
  }

  void _learnNews(World w, FactWriter f, Entity n) {
    for (final relation in List<Relation>.from(f.adjacency[n.id] ?? [])) {
      final relativeId = relation.source == n.id
          ? relation.target
          : relation.source;
      final relative = w.entities[relativeId];
      if (relative?.type != KarmaNodeType.npc ||
          relative!.alive ||
          !w.knows(n.id, relativeId)) {
        continue;
      }
      final death = f.last(relativeId, 'death');
      if (death == null || w.processedDeaths.contains('${n.id}|${death.id}')) {
        continue;
      }
      final witnesses = w.knowledge.values
          .where(
            (k) =>
                k.subject == death.id &&
                k.confirmed &&
                k.observer != w.playerId &&
                k.observer != relativeId &&
                k.observer != n.id,
          )
          .toList();
      final ownEvidence = w.knowledge['${n.id}|${death.id}'];
      final source =
          ownEvidence?.confirmed == true &&
              w.knows(n.id, death.causes.first.eventId)
          ? ownEvidence
          : witnesses
                .where(
                  (k) =>
                      w.entities[k.observer]?.location == n.location ||
                      w.entities[k.observer]?.sect == n.sect && n.sect != null,
                )
                .firstOrNull;
      if (source == null && n.location != relative.location) {
        if (w.day - death.time >= 60) {
          w.discover(
            n.id,
            death.id,
            InformationChannel.rumor,
            confirmed: false,
          );
        }
        continue;
      }
      final channel = source == null
          ? InformationChannel.investigation
          : InformationChannel.told;
      f.reveal(death, n.id, channel, source: source?.observer);
      w.processedDeaths.add('${n.id}|${death.id}');
      final news = f.event(
        'news',
        '${n.name}得知亲友陨落',
        '通过${source == null ? '现场调查' : '知情人告知'}确认死讯。',
        [n.id, relativeId],
        location: n.location,
        causes: [Cause(death.id, CausalKind.direct)],
      );
      // Corpse discovery does not establish the killer's identity.
      final killerId = w.events[death.causes.first.eventId]!.participants
          .where(
            (id) =>
                id != relativeId &&
                w.entities[id]?.type == KarmaNodeType.player,
          )
          .firstOrNull;
      final identified =
          source != null &&
          killerId != null &&
          w.knows(source.observer, death.causes.first.eventId);
      if (identified && relation.type == KarmaRelationType.kinship) {
        final revenge = f.event(
          'revenge',
          '${n.name}立下复仇目标',
          '得知凶手身份，立誓报仇。',
          [n.id, killerId],
          location: n.location,
          causes: [Cause(news.id, CausalKind.direct)],
          importance: 3,
        );
        f.relation(
          n.id,
          killerId,
          KarmaRelationType.hatred,
          revenge,
          strength: 80,
        );
        if (n.sect != null) {
          final bounty = f.event(
            'bounty',
            '${w.entities[n.sect]!.name}发布悬赏',
            '宗门收到可信情报后追缉凶手。',
            [n.sect!, n.id, killerId],
            location: n.location,
            causes: [Cause(revenge.id, CausalKind.direct)],
            importance: 4,
          );
          w.discover(
            w.playerId,
            bounty.id,
            InformationChannel.sectIntelligence,
          );
          f.reveal(bounty, w.playerId, InformationChannel.sectIntelligence);
        }
      }
      for (final debt in List<Relation>.from(f.adjacency[relativeId] ?? [])) {
        if (relation.type == KarmaRelationType.kinship &&
            debt.type == KarmaRelationType.debt &&
            !debt.resolved &&
            w.knows(n.id, debt.id) &&
            debt.target == relativeId &&
            debt.status == RelationStatus.historical &&
            debt.inheritedFrom == null) {
          debt.status = RelationStatus.inherited;
          f.relation(
            debt.source,
            n.id,
            KarmaRelationType.debt,
            news,
            strength: debt.strength,
            inheritedFrom: debt.id,
          );
        }
      }
    }
    final hate = (f.adjacency[n.id] ?? [])
        .where(
          (r) =>
              r.source == n.id &&
              r.target == w.playerId &&
              r.type == KarmaRelationType.hatred &&
              r.status == RelationStatus.active,
        )
        .firstOrNull;
    if (hate != null &&
        w.knows(n.id, hate.id) &&
        n.location == w.player.location &&
        w.battleTarget == null &&
        w.player.alive) {
      final e = f.event(
        'pursuit',
        '${n.name}追杀来袭',
        '根据已确认情报追来。',
        [n.id, w.playerId],
        causes: [Cause(hate.events.first, CausalKind.direct)],
        importance: 3,
      );
      w.battleTarget = n.id;
      w.battleOrigin = e.id;
      w.battleHp = n.hp;
    }
  }

  void _war(World w, FactWriter f) {
    final rival = w.relations.values
        .where(
          (r) =>
              r.type == KarmaRelationType.rivalry &&
              r.status == RelationStatus.active &&
              r.strength >= 60,
        )
        .firstOrNull;
    if (rival == null ||
        !w.entities[rival.source]!.alive ||
        !w.entities[rival.target]!.alive) {
      return;
    }
    final participants = <String>[rival.source, rival.target];
    for (final n
        in w.entities.values
            .where(
              (n) =>
                  n.alive && (n.sect == rival.source || n.sect == rival.target),
            )
            .take(12)) {
      participants.add(n.id);
    }
    final previous = f.last(rival.source, 'war');
    final e = f.event(
      'war',
      '北荒宗门之战',
      '长期势力竞争引发冲突，参与者的命运受到影响。',
      participants,
      location: '${w.id}:location:4',
      importance: 5,
      causes: previous == null
          ? []
          : [Cause(previous.id, CausalKind.influence)],
    );
    rival.events.add(e.id);
    rival.updated = w.day;
    if (w.player.sect != null) {
      f.reveal(e, w.playerId, InformationChannel.sectIntelligence);
    }
    if (previous != null &&
        w.day - previous.time >= 360 &&
        w.random.next(4) == 0) {
      final sect = w.entities[rival.target]!;
      sect.alive = false;
      sect.updated = w.day;
      final fall = f.event(
        'sectFall',
        '${sect.name}覆灭',
        '战争损耗使宗门覆灭，旧身份保留在历史中。',
        [sect.id, rival.source],
        location: '${w.id}:location:4',
        importance: 5,
        causes: [Cause(e.id, CausalKind.direct)],
      );
      for (final r in f.adjacency[sect.id] ?? <Relation>[]) {
        if (r.type != KarmaRelationType.eventParticipation) {
          r
            ..status = RelationStatus.historical
            ..updated = w.day
            ..events.add(fall.id);
        }
      }
      for (final n in w.entities.values.where((n) => n.sect == sect.id)) {
        n.sect = null;
      }
    }
  }
}

abstract final class LifeAssessment {
  static Map<String, Object?> calculate(World w) {
    final known = w.relations.values
        .where(
          (r) =>
              w.knows(w.playerId, r.id) &&
              (r.source == w.playerId || r.target == w.playerId),
        )
        .map((r) {
          final snapshot = w.knowledge['${w.playerId}|${r.id}']!.snapshot;
          return Relation.fromJson({
            ...r.toJson(),
            'strength': snapshot['strength'] ?? 0,
            'status': snapshot['status'] ?? 'active',
            'resolved': snapshot['resolved'] ?? false,
          });
        })
        .toList();
    final good =
        known
            .where(
              (r) => [
                KarmaRelationType.gratitude,
                KarmaRelationType.friendship,
                KarmaRelationType.daoCompanion,
              ].contains(r.type),
            )
            .toList()
          ..sort((a, b) => b.strength.compareTo(a.strength));
    final bad = known.where((r) => r.type == KarmaRelationType.hatred).toList()
      ..sort((a, b) => b.strength.compareTo(a.strength));
    final major = known
        .where(
          (r) =>
              r.strength >= 60 &&
              r.type != KarmaRelationType.eventParticipation,
        )
        .toList();
    final impact =
        w.events.values
            .where(
              (e) =>
                  e.importance >= 4 &&
                  e.participants.contains(w.playerId) &&
                  w.knows(w.playerId, e.id),
            )
            .toList()
          ..sort((a, b) => b.importance.compareTo(a.importance));
    var score = 0;
    for (final r in major) {
      final result = r.resolved ? 2 : 1;
      score += r.strength * result;
      if (r.type == KarmaRelationType.debt && !r.resolved) {
        score -= r.strength;
      }
    }
    score += impact.fold<int>(0, (sum, e) => sum + e.importance * 20);
    String? description(Relation? r) => r == null
        ? null
        : '${w.entities[r.source == w.playerId ? r.target : r.source]!.name} · ${relationLabel(r.type)}';
    return {
      'ruleVersion': 1,
      'knownCultivators': w.entities.values
          .where(
            (n) => n.type == KarmaNodeType.npc && w.knows(w.playerId, n.id),
          )
          .length,
      'good': good.length,
      'bad': bad.length,
      'major': major.length,
      'settled': major.where((r) => r.resolved).length,
      'unsettled': major.where((r) => !r.resolved).length,
      'deepestGood': description(good.firstOrNull),
      'deepestBad': description(bad.firstOrNull),
      'worldImpact': impact.firstOrNull?.title,
      'score': score,
    };
  }
}
