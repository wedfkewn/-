part of 'engine.dart';

abstract final class GrowthRules {
  static Map<String, int> pack(World w, Entity actor) =>
      actor.id == w.playerId ? w.inventory : actor.supplies;
  static bool injured(World w, Entity p) =>
      p.injuryDay >= 0 &&
      !(w.day - p.injuryDay >= 30 &&
          p.hp * 5 >= GameCommandService.maxHp(p) * 4 &&
          p.stabilizedDay > p.injuryDay);
  static int rootRequired(Entity p) =>
      p.stage < 3 ? [20, 35, 50][p.stage] : 60 + p.realm * 4;
  static bool suitable(World w, Entity p) => p.realm >= 6
      ? w.mapPlaces[p.location]?.kind == PlaceKind.tribulation
      : (p.sect != null && w.entities[p.sect]?.location == p.location) ||
            [
              PlaceKind.town,
              PlaceKind.sect,
              PlaceKind.vein,
            ].contains(w.mapPlaces[p.location]?.kind);
  static bool guardEligible(World w, Entity p, Entity n) {
    if (n.id == p.id ||
        !n.alive ||
        n.type != KarmaNodeType.npc ||
        n.location != p.location ||
        n.realm < p.realm + 1 ||
        !w.knows(p.id, n.id)) {
      return false;
    }
    final social = w.relations.values.any(
      (r) =>
          r.status == RelationStatus.active &&
          ((r.source == p.id && r.target == n.id) ||
              (r.source == n.id && r.target == p.id)) &&
          (r.type == KarmaRelationType.masterDisciple ||
              (r.type == KarmaRelationType.friendship && r.bidirectional)),
    );
    bool membership(String actor, String sect) => w.relations.values.any(
      (r) =>
          r.source == actor &&
          r.target == sect &&
          r.type == KarmaRelationType.sectAffiliation &&
          r.status == RelationStatus.active,
    );
    final sect = p.sect;
    return social ||
        (sect != null &&
            sect == n.sect &&
            membership(p.id, sect) &&
            membership(n.id, sect));
  }

  static GrowthView view(World w, {String? guard, bool pill = false}) {
    final p = w.player;
    final terminal = p.realm == 8 && p.stage == 3;
    final material = p.stage == 3 && p.realm < 8
        ? MapRules.materials[p.realm]
        : '';
    final guards =
        w.entities.values
            .where((n) => guardEligible(w, p, n))
            .map((n) => n.id)
            .toList()
          ..sort();
    final chance =
        (50 +
                (p.foundation - rootRequired(p)).clamp(0, 20) +
                (pill ? 10 : 0) +
                (guards.contains(guard) ? 10 : 0) +
                (w.mapPlaces[p.location]?.kind == PlaceKind.vein ? 5 : 0))
            .clamp(0, 95);
    final missing = <String>[
      if (terminal) '已至渡劫圆满',
      if (p.spirit < Content.threshold(p.realm, p.stage)) '修为不足',
      if (p.foundation < rootRequired(p)) '根基不足',
      if (p.hp * 5 < GameCommandService.maxHp(p) * 4) '气血须达到80%',
      if (injured(w, p)) '突破伤势未愈：至少30日、稳固一次并恢复80%气血',
      if (w.battleTarget != null || w.tribulation != null) '正在交锋',
      if (w.encounter != null) '奇遇尚未处理',
      if (w.secretRun != null) '请先离开秘境',
      if (p.stage == 3 && p.realm < 8 && p.insight < 10 + p.realm * 10) '感悟不足',
      if (material.isNotEmpty && (w.inventory[material] ?? 0) < 1)
        '缺少$material',
      if (p.stage == 3 && !suitable(w, p))
        p.realm >= 6 ? '须在渡劫台进行' : '须在城镇、宗门驻地或灵脉突破',
      if (guard != null && !guards.contains(guard)) '护法条件不满足',
      if (pill && (w.inventory['护脉丹'] ?? 0) < 1) '护脉丹不足',
    ];
    return GrowthView(
      stage: p.stage,
      foundation: p.foundation,
      insight: p.insight,
      threshold: Content.threshold(p.realm, p.stage),
      rootRequired: rootRequired(p),
      insightRequired: p.stage == 3 ? 10 + p.realm * 10 : 0,
      material: material,
      chance: chance,
      injured: injured(w, p),
      highTrial: p.stage == 3 && p.realm >= 6,
      terminal: terminal,
      missing: missing,
      guards: guards,
      sourceCount: p.growthSources.keys
          .where((k) => k.startsWith('${p.realm}:'))
          .length,
    );
  }

  static List<Cause> sources(World w, Entity p) {
    final entries = p.growthSources.entries
        .where(
          (e) =>
              e.key.startsWith('${p.realm}:') && w.events.containsKey(e.value),
        )
        .toList()
        .reversed
        .toList();
    final material = p.realm < 8 ? MapRules.materials[p.realm] : '';
    final ids = <String>{
      ...entries
          .where((e) => e.key == '${p.realm}:material:$material')
          .map((e) => e.value),
      ...entries.map((e) => e.value),
    };
    return ids.take(24).map((id) => Cause(id, CausalKind.influence)).toList();
  }

  static List<Cause> guardSources(
    World w,
    FactWriter f,
    Entity p,
    String? guard,
  ) {
    if (guard == null) return [];
    return (f.adjacency[p.id] ?? <Relation>[])
        .where(
          (r) =>
              r.status == RelationStatus.active &&
              ((r.type == KarmaRelationType.friendship ||
                          r.type == KarmaRelationType.masterDisciple) &&
                      (r.source == guard || r.target == guard) ||
                  r.type == KarmaRelationType.sectAffiliation &&
                      r.target == p.sect),
        )
        .expand((r) => r.events.reversed)
        .where((id) => w.events.containsKey(id) && w.knows(p.id, id))
        .take(2)
        .map((id) => Cause(id, CausalKind.influence))
        .toList();
  }

  static void insight(
    World w,
    FactWriter f,
    Entity p,
    String key,
    int points,
    GameEvent source, {
    String? cap,
  }) {
    final tag = '${p.realm}:$key';
    if (p.growthSources.containsKey(tag)) return;
    final prior =
        p.growthSources.keys
            .where((k) => k.startsWith('${p.realm}:${cap ?? 'unused'}:'))
            .length *
        5;
    final gain = cap == null
        ? points
        : points.clamp(0, (20 - prior).clamp(0, 20));
    if (gain <= 0) return;
    p.growthSources[tag] = source.id;
    p.insight += gain;
    f.event(
      'insight',
      '${p.name}有所感悟',
      '此次历练获得$gain感悟，同类来源在本境界不重复领取。',
      [p.id],
      location: p.location,
      causes: [Cause(source.id, CausalKind.direct)],
      witnessed: p.id == w.playerId,
    );
  }

  static void cultivate(World w, FactWriter f) {
    final p = w.player;
    final point = w.mapPlaces[p.location]!;
    if (point.kind == PlaceKind.vein &&
        w.entities[p.sect]?.location != p.location) {
      if (p.coins < 5) throw const RuleViolation('灵脉闭关需要5灵石');
      p.coins -= 5;
    }
    final gain =
        ((25 + Content.techniques[w.style]!) *
                (1 + p.realm * .35) *
                (1 + (point.aura - 1) * .1))
            .floor();
    p.spirit += gain;
    p.hp = (p.hp + 15).clamp(0, GameCommandService.maxHp(p));
    f.event('cultivate', '闭关修炼', '主修${w.style}，借当地灵气积累$gain修为；根基与感悟需另行准备。', [
      p.id,
    ]);
  }

  static void stabilize(World w, FactWriter f, {bool practice = false}) {
    final p = w.player;
    p.foundation = (p.foundation + (practice ? 5 : 10)).clamp(0, 100);
    p.stabilizedDay = w.day;
    p.hp = (p.hp + 15).clamp(0, GameCommandService.maxHp(p));
    final source = f.last(p.id, 'breakthroughFailed');
    f.event(
      practice ? 'practice' : 'stabilize',
      practice ? '功法训练' : '稳固境界',
      '根基提升至${p.foundation}，调息恢复15气血。',
      [p.id],
      causes: source == null ? [] : [Cause(source.id, CausalKind.direct)],
    );
    if (!injured(w, p)) p.injuryDay = -1;
  }

  static void contemplate(World w, FactWriter f) {
    final p = w.player;
    final ruin = w.mapPlaces[p.location]!.kind == PlaceKind.ruin;
    final key = '${p.realm}:place:${p.location}';
    if (p.growthSources.containsKey(key)) {
      throw const RuleViolation('本境界已参悟此处，请寻找新的历练');
    }
    final e = f.event('contemplate', ruin ? '参悟遗迹' : '观山悟道', '参悟此处风物与遗刻。', [
      p.id,
    ]);
    insight(w, f, p, 'place:${p.location}', ruin ? 10 : 5, e);
  }

  static void instruction(World w, FactWriter f, Entity n) {
    final p = w.player;
    if (n.realm <= p.realm ||
        !w.relations.values.any(
          (r) =>
              r.source == n.id &&
              r.target == p.id &&
              r.type == KarmaRelationType.masterDisciple &&
              r.status == RelationStatus.active,
        )) {
      throw const RuleViolation('须向境界更高的真实师父请教');
    }
    final count = p.growthSources.keys
        .where((k) => k.startsWith('${p.realm}:mentor:'))
        .length;
    if (count >= 4) throw const RuleViolation('本境界师长指点已达到20感悟上限');
    final e = f.event('instruction', '${n.name}传道', '师长指点修行疑惑。', [p.id, n.id]);
    insight(w, f, p, 'mentor:${n.id}:$count', 5, e, cap: 'mentor');
  }

  static void promote(World w, FactWriter f, GameCommand command) {
    final p = w.player;
    final preview = view(w, guard: command.target, pill: command.item == '护脉丹');
    if (preview.missing.isNotEmpty) {
      throw RuleViolation(preview.missing.join('；'));
    }
    if (p.stage < 3) {
      p.spirit -= preview.threshold;
      p.stage++;
      p.hp = GameCommandService.maxHp(p);
      final e = f.event(
        'advanceStage',
        '晋入${Content.realms[p.realm]}${Content.stages[p.stage]}',
        '根基达标，小阶段确定性提升，寿元不变。',
        [p.id],
        causes: sources(w, p),
      );
      p.growthSources['${p.realm}:stage:${p.stage}'] = e.id;
      return;
    }
    if (command.item != null && command.item != '护脉丹') {
      throw const RuleViolation('无效突破准备');
    }
    w.inventory[preview.material] = w.inventory[preview.material]! - 1;
    if (command.item == '护脉丹') w.inventory['护脉丹'] = w.inventory['护脉丹']! - 1;
    final preparation = f.event(
      'breakthroughPreparation',
      '准备冲击${Content.realms[p.realm + 1]}',
      '消耗${preview.material}${command.item == null ? '' : '及护脉丹'}${command.target == null ? '' : '，${w.entities[command.target]!.name}护法'}。',
      [p.id, if (command.target != null) command.target!],
      causes: [...sources(w, p), ...guardSources(w, f, p, command.target)],
      importance: 3,
    );
    if (preview.highTrial) {
      p.spirit -= preview.threshold;
      w.tribulation = Tribulation(
        preparation.id,
        p.realm == 6 ? 3 : 5,
        20 +
            (p.foundation - preview.rootRequired).clamp(0, 20) * 2 +
            (command.item == null ? 0 : 50) +
            (command.target == null ? 0 : 50),
        guard: command.target,
      );
      w.battleQi = 10 + p.realm * 2 + AdventureRules.affix(w, '养气');
      return;
    }
    if (w.random.next(100) < preview.chance) {
      p.spirit -= preview.threshold;
      complete(w, f, p, preparation);
    } else {
      p.spirit -= (preview.threshold * .2).ceil();
      p.hp = (p.hp - (p.hp * .3).ceil()).clamp(1, GameCommandService.maxHp(p));
      p.injuryDay = w.day;
      p.stabilizedDay = -1;
      final e = f.event(
        'breakthroughFailed',
        '突破受挫',
        '损失门槛修为20%，气血损失30%；须经过30日、稳固并恢复80%气血。',
        [p.id],
        causes: [Cause(preparation.id, CausalKind.direct)],
      );
      p.growthSources['${p.realm}:failure:${e.id}'] = e.id;
    }
  }

  static void complete(World w, FactWriter f, Entity p, GameEvent origin) {
    p.realm++;
    p.stage = 0;
    p.foundation = 30;
    p.insight = 0;
    p.injuryDay = -1;
    p.hp = GameCommandService.maxHp(p);
    f.event(
      p.id == w.playerId ? 'breakthrough' : 'npcBreakthrough',
      '${p.name}突破${Content.realms[p.realm]}',
      '修为、根基、感悟与材料准备共同成就新境界，寿元提升。',
      [p.id],
      location: p.location,
      causes: [Cause(origin.id, CausalKind.direct)],
      importance: 3,
    );
  }

  static void gather(World w, FactWriter f, String? item) {
    final p = w.player, point = w.mapPlaces[w.player.location]!;
    if (item == null ||
        !point.resources.contains(item) ||
        ![PlaceKind.wild, PlaceKind.ruin].contains(point.kind)) {
      throw const RuleViolation('此地无法采集该资源');
    }
    if (p.realm < point.danger) throw const RuleViolation('当前境界不足以完成此地采集挑战');
    final discovered =
        w.knowledge['${p.id}|${p.location}']?.snapshot['geographySource']
            as String?;
    final e = f.event(
      'gather',
      '采得$item',
      '经十日寻访与当地考验，取得$item。',
      [p.id],
      causes: [
        if (discovered != null && w.events.containsKey(discovered))
          Cause(discovered, CausalKind.direct),
      ],
    );
    w.inventory[item] = (w.inventory[item] ?? 0) + (item == '灵草' ? 3 : 1);
    p.growthSources['${p.realm}:material:$item'] = e.id;
    insight(w, f, p, 'gather:${p.location}', 5, e);
  }

  static void materialQuest(World w, FactWriter f) {
    final p = w.player;
    if (p.realm >= 8 ||
        p.sect == null ||
        w.entities[p.sect]!.location != p.location) {
      throw const RuleViolation('须在本宗驻地接受突破材料委托');
    }
    if ((w.inventory['灵草'] ?? 0) < 5 || (w.inventory['回春丹'] ?? 0) < 1) {
      throw const RuleViolation('委托需5株灵草与1枚回春丹');
    }
    w.inventory['灵草'] = w.inventory['灵草']! - 5;
    w.inventory['回春丹'] = w.inventory['回春丹']! - 1;
    final material = MapRules.materials[p.realm];
    w.inventory[material] = (w.inventory[material] ?? 0) + 1;
    final e = f.event('materialQuest', '宗门材料委托完成', '交付灵草与丹药，换得$material。', [
      p.id,
      p.sect!,
    ], importance: 3);
    p.growthSources['${p.realm}:material:$material'] = e.id;
    insight(w, f, p, 'quest:material', 10, e);
  }

  static String omen(World w) {
    final t = w.tribulation;
    if (t == null) return '';
    return '第${t.turn + 1}/${t.rounds}道雷劫：${t.turn.isOdd ? '蓄势重雷，宜防御或天机破招' : '雷火临身，可运功抵御'} · 剩余护盾${t.shield} · 不能逃跑';
  }

  static void tribulationTurn(World w, FactWriter f, GameCommand command) {
    final t = w.tribulation!;
    final p = w.player;
    var defense = false, disrupt = false, strike = 0;
    if (command.kind == 'flee') throw const RuleViolation('雷劫开始后不能逃跑');
    if (command.kind == 'useItem') {
      if (command.item != '回春丹' || (w.inventory['回春丹'] ?? 0) < 1) {
        throw const RuleViolation('雷劫中可使用持有的回春丹');
      }
      w.inventory['回春丹'] = w.inventory['回春丹']! - 1;
      p.hp = (p.hp + 65).clamp(0, GameCommandService.maxHp(p));
    } else if (command.kind == 'defend') {
      defense = true;
      w.battleQi = (w.battleQi + 2).clamp(
        0,
        10 + p.realm * 2 + AdventureRules.affix(w, '养气'),
      );
    } else if (command.kind == 'skill' || command.kind == 'attack') {
      final skill = command.kind == 'skill' ? (command.item ?? w.style) : null;
      strike = AdventureRules.attack(w, skill);
      disrupt = skill == '天机诀';
    } else {
      throw const RuleViolation('雷劫中只能攻击、施法、防御或用药');
    }
    var damage = 70 + p.realm * 9 + (t.turn.isOdd ? 45 : 0);
    damage = (damage - strike ~/ 3 - AdventureRules.affix(w, '坚韧')).clamp(
      10,
      500,
    );
    if (defense || disrupt) damage = (damage * .5).ceil();
    final absorbed = damage.clamp(0, t.shield);
    t.shield -= absorbed;
    p.hp -= damage - absorbed;
    final e = f.event(
      'tribulationRound',
      '承受第${t.turn + 1}道雷劫',
      '护盾抵消$absorbed，气血损失${damage - absorbed}。',
      [p.id],
      causes: [Cause(t.origin, CausalKind.direct)],
    );
    t.turn++;
    if (p.hp <= 0) {
      f.die(p, e);
      w.tribulation = null;
    } else if (t.turn >= t.rounds) {
      complete(w, f, p, e);
      w.tribulation = null;
    }
  }

  static void secret(World w, FactWriter f, String command) {
    final p = w.player;
    final point = w.mapPlaces[p.location]!;
    if (command == 'leaveSecret') {
      w.secretRun = null;
      return;
    }
    if (command == 'enterSecret') {
      if (w.secretRun != null ||
          point.kind != PlaceKind.secret ||
          !point.open(w.day - 1)) {
        throw const RuleViolation('秘境尚未开放或已经进入');
      }
      if (p.realm < point.danger) throw const RuleViolation('境界不足，请先准备再入秘境');
      if (p.coins < 10) throw const RuleViolation('进入秘境需10灵石');
      p.coins -= 10;
      final e = f.event('secretEnter', '踏入秘境', '进入限时秘境，可逐阶段探索或安全离开；深处考验可能受伤。', [
        p.id,
      ]);
      w.secretRun = SecretRun(point.id, e.id);
      return;
    }
    final run = w.secretRun;
    if (run == null || run.place != p.location) {
      throw const RuleViolation('没有正在探索的秘境');
    }
    final last = f.last(p.id, 'secretStep');
    final source =
        last != null &&
            last.location == p.location &&
            last.time >= w.events[run.origin]!.time
        ? last.id
        : run.origin;
    final e = f.event(
      'secretStep',
      '秘境 · 第${run.stage + 1}阶段',
      ['调查入口，收集灵草', '承受遗阵考验，可能损失气血', '取得秘藏与突破材料'][run.stage],
      [p.id],
      causes: [Cause(source, CausalKind.direct)],
      importance: run.stage == 2 ? 3 : 1,
    );
    if (run.stage == 0) {
      w.inventory['灵草'] = (w.inventory['灵草'] ?? 0) + 3;
    } else if (run.stage == 1) {
      p.hp -= 30 + point.danger * 20;
      if (p.hp <= 0) {
        f.die(p, e);
        w.secretRun = null;
        return;
      }
    } else {
      final material = MapRules.materials[point.danger.clamp(0, 7)];
      w.inventory[material] = (w.inventory[material] ?? 0) + 1;
      p.growthSources['${p.realm}:material:$material'] = e.id;
      insight(w, f, p, 'secret:${point.id}', 10, e);
      AdventureRules.award(w, f, e.id);
      w.secretRun = null;
      return;
    }
    run.stage++;
  }

  /// Ordinary actors make one bounded decision per scheduled update. All
  /// candidate geography is drawn from their own confirmed knowledge.
  static void npc(World w, FactWriter f, Entity n, int elapsed) {
    if (w.mapVersion == 0) return;
    final units = elapsed ~/ 30;
    n.spirit +=
        ((18 + (n.personality == '重义' ? 4 : 0)) * units * (1 + n.realm * .35))
            .floor();
    n.foundation = (n.foundation + units * 5).clamp(0, 100);
    n.hp = (n.hp + units * 15).clamp(0, GameCommandService.maxHp(n));
    n.stabilizedDay = w.day;
    final rescue = f.last(n.id, 'rescue');
    final practice = f.event(
      'npcCultivate',
      '${n.name}修炼调息',
      '积累修为、稳固根基并恢复气血。',
      [n.id],
      location: n.location,
      causes: rescue == null ? [] : [Cause(rescue.id, CausalKind.influence)],
    );
    n.growthSources['${n.realm}:practice'] = practice.id;
    MapRules.revealNearby(
      w,
      n.id,
      InformationChannel.investigation,
      source: practice.id,
    );
    final point = w.mapPlaces[n.location]!;
    final inventory = n.supplies;
    final known = MapRepository(
      w,
      observer: n.id,
    ).query().places.where((p) => p.confirmed).toList();
    final material = n.realm < 8 ? MapRules.materials[n.realm] : null;
    final threshold = Content.threshold(n.realm, n.stage);
    if (n.stage < 3 &&
        n.spirit >= threshold &&
        n.foundation >= rootRequired(n) &&
        !injured(w, n)) {
      n.spirit -= threshold;
      n.stage++;
      n.hp = GameCommandService.maxHp(n);
      f.event(
        'npcStage',
        '${n.name}晋入${Content.stages[n.stage]}',
        '小阶段修为与根基条件满足。',
        [n.id],
        location: n.location,
        causes: [Cause(practice.id, CausalKind.direct)],
      );
      return;
    }
    if (n.stage == 3 &&
        material != null &&
        n.spirit >= threshold &&
        n.foundation >= rootRequired(n) &&
        n.insight >= 10 + n.realm * 10 &&
        (inventory[material] ?? 0) > 0 &&
        suitable(w, n) &&
        !injured(w, n) &&
        n.hp * 5 >= GameCommandService.maxHp(n) * 4) {
      final guards =
          w.entities.values
              .where((actor) => guardEligible(w, n, actor))
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      final guard = guards.firstOrNull;
      final pill = (inventory['护脉丹'] ?? 0) > 0;
      inventory[material] = inventory[material]! - 1;
      if (pill) inventory['护脉丹'] = inventory['护脉丹']! - 1;
      final origin = f.event(
        'npcPreparation',
        '${n.name}准备突破',
        '依自身情报备齐$material${guard == null ? '' : '，由${guard.name}护法'}。',
        [n.id, if (guard != null) guard.id],
        location: n.location,
        causes: sources(w, n),
      );
      if (n.realm >= 6) {
        n.spirit -= threshold;
        var shield =
            20 +
            (n.foundation - rootRequired(n)).clamp(0, 20) * 2 +
            (pill ? 50 : 0) +
            (guard == null ? 0 : 50);
        GameEvent result = origin;
        for (var turn = 0; turn < (n.realm == 6 ? 3 : 5); turn++) {
          // Same lightning coefficients and defense modifier as player trials.
          var damage = 70 + n.realm * 9 + (turn.isOdd ? 45 : 0);
          if (n.personality != '好战') {
            damage = (damage * .5).ceil();
          } else {
            damage -= ((18 + n.realm * 14) * (1 + n.stage * .05)).floor() ~/ 3;
          }
          if (n.hp < GameCommandService.maxHp(n) ~/ 2 &&
              (inventory['回春丹'] ?? 0) > 0) {
            inventory['回春丹'] = inventory['回春丹']! - 1;
            n.hp = (n.hp + 65).clamp(0, GameCommandService.maxHp(n));
          }
          final absorbed = damage.clamp(0, shield);
          shield -= absorbed;
          n.hp -= damage - absorbed;
          result = f.event(
            'npcTribulation',
            '${n.name}承受第${turn + 1}道雷劫',
            '依准备与行动承受雷劫。',
            [n.id],
            location: n.location,
            causes: [Cause(result.id, CausalKind.direct)],
          );
          if (n.hp <= 0) {
            f.die(n, result);
            return;
          }
        }
        complete(w, f, n, result);
      } else {
        final chance =
            (50 +
                    (n.foundation - rootRequired(n)).clamp(0, 20) +
                    (pill ? 10 : 0) +
                    (guard == null ? 0 : 10) +
                    (point.kind == PlaceKind.vein ? 5 : 0))
                .clamp(0, 95);
        if (w.random.next(100) < chance) {
          n.spirit -= threshold;
          complete(w, f, n, origin);
        } else {
          n.spirit -= (threshold * .2).ceil();
          n.hp = (n.hp * .7).floor().clamp(1, GameCommandService.maxHp(n));
          n.injuryDay = w.day;
          n.stabilizedDay = -1;
          f.event(
            'npcBreakthroughFailed',
            '${n.name}突破受挫',
            '材料消耗，修为损失20%，需调息恢复。',
            [n.id],
            location: n.location,
            causes: [Cause(origin.id, CausalKind.direct)],
          );
        }
      }
      return;
    }
    if (!n.growthSources.containsKey('${n.realm}:place:${n.location}')) {
      final e = f.event('npcContemplate', '${n.name}参悟山河', '参悟亲自抵达地点的风物。', [
        n.id,
      ], location: n.location);
      insight(
        w,
        f,
        n,
        'place:${n.location}',
        point.kind == PlaceKind.ruin ? 10 : 5,
        e,
      );
      return;
    }
    if ([PlaceKind.wild, PlaceKind.ruin].contains(point.kind) &&
        n.realm >= point.danger) {
      final item =
          material != null &&
              point.resources.contains(material) &&
              (inventory[material] ?? 0) == 0
          ? material
          : (inventory['灵草'] ?? 0) < 5
          ? '灵草'
          : null;
      if (item != null && point.resources.contains(item)) {
        inventory[item] = (inventory[item] ?? 0) + (item == '灵草' ? 3 : 1);
        final e = f.event('npcGather', '${n.name}采集$item', '依本地已知资源采集。', [
          n.id,
        ], location: n.location);
        n.growthSources['${n.realm}:material:$item'] = e.id;
        return;
      }
    }
    if ([PlaceKind.town, PlaceKind.market].contains(point.kind)) {
      if ((inventory['灵草'] ?? 0) > 0) {
        inventory['灵草'] = inventory['灵草']! - 1;
        n.coins += 4;
      }
      final item =
          material != null &&
              (inventory[material] ?? 0) == 0 &&
              point.resources.contains(material)
          ? material
          : (inventory['回春丹'] ?? 0) == 0
          ? '回春丹'
          : (inventory['护脉丹'] ?? 0) == 0
          ? '护脉丹'
          : null;
      final price = Content.prices[item];
      if (item != null && price != null && n.coins >= price) {
        n.coins -= price;
        inventory[item] = (inventory[item] ?? 0) + 1;
        final e = f.event('npcTrade', '${n.name}购得$item', '根据本地公开资源目录交易。', [
          n.id,
        ], location: n.location);
        n.growthSources['${n.realm}:material:$item'] = e.id;
        return;
      }
    }
    if (material != null &&
        n.sect != null &&
        w.entities[n.sect]!.location == n.location &&
        (inventory[material] ?? 0) == 0 &&
        (inventory['灵草'] ?? 0) >= 5) {
      // NPCs must also supply an actual healing pill, purchased locally earlier.
      if ((inventory['回春丹'] ?? 0) > 0) {
        inventory['灵草'] = inventory['灵草']! - 5;
        inventory['回春丹'] = inventory['回春丹']! - 1;
        inventory[material] = 1;
        final e = f.event(
          'npcMaterialQuest',
          '${n.name}完成材料委托',
          '交付灵草与丹药兑换$material。',
          [n.id, n.sect!],
          location: n.location,
        );
        n.growthSources['${n.realm}:material:$material'] = e.id;
        insight(w, f, n, 'quest:material', 10, e);
        return;
      }
    }
    final destinations = known.where((p) => p.place.id != n.location).toList();
    int score(KnownPlace p) {
      if (material != null &&
          (inventory[material] ?? 0) == 0 &&
          p.place.resources.contains(material) &&
          p.place.danger <= n.realm) {
        return 0;
      }
      if (n.stage == 3 &&
          n.insight >= 10 + n.realm * 10 &&
          (inventory[material] ?? 0) > 0 &&
          suitable(
            w,
            Entity(
              id: n.id,
              type: n.type,
              name: n.name,
              realm: n.realm,
              location: p.place.id,
              sect: n.sect,
            ),
          )) {
        return 1;
      }
      if (!n.growthSources.containsKey('${n.realm}:place:${p.place.id}')) {
        return 2;
      }
      if ([PlaceKind.wild, PlaceKind.ruin].contains(p.place.kind) &&
          (inventory['灵草'] ?? 0) < 5 &&
          p.place.danger <= n.realm) {
        return 3;
      }
      return 4;
    }

    destinations.sort((a, b) {
      final order = score(a).compareTo(score(b));
      return order != 0 ? order : a.place.id.compareTo(b.place.id);
    });
    for (final candidate in destinations) {
      final path = MapRepository(w, observer: n.id).route(candidate.place.id);
      if (path != null && path.isNotEmpty && n.coins >= path.first.fee) {
        moveNpc(w, f, n, path.first);
        return;
      }
    }
  }

  static void moveNpc(World w, FactWriter f, Entity n, MapRoad road) {
    if (n.coins < road.fee || !w.knows(n.id, road.other(n.location))) return;
    n.coins -= road.fee;
    n.location = road.other(n.location);
    final e = f.event('migration', '${n.name}行旅', '依据自身已知道路前进一段。', [
      n.id,
    ], location: n.location);
    MapRules.revealNearby(w, n.id, InformationChannel.witness, source: e.id);
  }
}
