import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/ai_service.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';

class _Secrets implements SecretStore {
  String? value = 'fixture-secret';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.proposal);
  final Map<String, dynamic> proposal;
  RequestOptions? captured;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(proposal)},
          },
        ],
        'usage': {'prompt_tokens': 30, 'completion_tokens': 15},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

World _world() => WorldGenerator.generate(
  seed: 'narrative-gameplay',
  worldId: 'narrative-gameplay',
  npcCount: 8,
);

AiContentService _service(GameDatabase db, {_Adapter? adapter}) =>
    AiContentService(
      db,
      AiClient(dio: Dio()..httpClientAdapter = adapter ?? _Adapter({})),
      _Secrets(),
    );

const _proposal = {
  'title': '溪边药香',
  'text': '浅滩留着一缕药香。行旅停步，望见石间的灵草。',
  'options': [
    {'label': '采集灵草', 'effect': 'herbs'},
    {'label': '安全离开', 'effect': 'leave'},
  ],
};

void main() {
  test(
    'old and invalid narrative preferences migrate without changing API',
    () {
      final old = AiSettings.fromJson({
        'base': 'https://example.test/v1',
        'model': 'fixture-model',
        'enabled': true,
        'consent': true,
      });
      expect(old.narrativeStyle, '江湖纪实');
      expect(old.detail, 'brief');
      expect(old.enabled, isTrue);
      final invalid = AiSettings.fromJson({
        ...old.toJson(),
        'narrativeStyle': ['inject arbitrary prompt'],
        'detail': 'unlimited',
      });
      expect(invalid.narrativeStyle, '江湖纪实');
      expect(invalid.detail, 'brief');
      for (final style in AiSettings.narrativeStyles) {
        final restored = AiSettings.fromJson(
          AiSettings(narrativeStyle: style, detail: 'standard').toJson(),
        );
        expect(restored.narrativeStyle, style);
        expect(restored.detail, 'standard');
      }
    },
  );

  for (final detail in AiSettings.details) {
    test(
      'saved $detail preference reaches one compatible completion',
      () async {
        final db = GameDatabase.memory();
        addTearDown(db.close);
        final adapter = _Adapter(_proposal);
        final service = _service(db, adapter: adapter);
        final settings = AiSettings(
          base: 'https://example.test/v1',
          model: 'fixture-model',
          enabled: true,
          consent: true,
          narrativeStyle: '诗意山水',
          detail: detail,
        );
        await service.saveSettings(settings, 'fixture-secret');
        expect((await service.settings()).detail, detail);
        expect((await service.settings()).narrativeStyle, '诗意山水');
        final world = _world();
        final before = jsonEncode(world.toJson());
        final generated = await service.generate(world, 'explore', settings);
        expect(generated['proposal'], _proposal);
        expect(generated['promptVersion'], 2);
        expect(adapter.calls, 1);
        final payload = adapter.captured!.data as Map;
        expect(payload.keys.toSet(), {'model', 'messages', 'stream'});
        final messages = payload['messages'] as List;
        final prompt = messages.first['content'] as String;
        expect(prompt, contains('叙事风格：诗意山水'));
        expect(prompt, contains(detail == 'brief' ? '60至110中文字' : '150至220字'));
        final context = jsonDecode(messages.last['content'] as String) as Map;
        expect(context['preferences'], {
          'narrativeStyle': '诗意山水',
          'detail': detail,
        });
        expect(jsonEncode(world.toJson()), before);
        final usage = await db.usage();
        expect(usage.length, 1);
        expect(usage.single['input'], 30);
        expect(usage.single['output'], 15);
        expect(
          jsonEncode(await db.settings()),
          isNot(contains('fixture-secret')),
        );
        expect(jsonEncode(usage), isNot(contains('fixture-secret')));
      },
    );
  }

  test(
    'recent choices include at most three explicit known outcome chains',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final service = _service(db);
      final world = _world();
      final writer = FactWriter(world);
      for (var i = 0; i < 4; i++) {
        world.day = i;
        final choice = writer.event(
          'encounterChoice',
          '真实选择$i',
          '选择一条已校验的奇遇分支。',
          [world.playerId],
        );
        final battle = writer.event(
          'challenge',
          '迎战$i',
          '因为选择承担危险，进入战斗。',
          [world.playerId],
          causes: [Cause(choice.id, CausalKind.direct)],
        );
        writer.event(
          'equipmentReward',
          '实际装备结果$i',
          '战斗完成后获得已结算装备。',
          [world.playerId],
          causes: [Cause(battle.id, CausalKind.direct)],
        );
        writer.event('unrelated', '时间相邻但没有因果$i', '这件事独立发生。', [world.playerId]);
        writer.event(
          'secretOutcome',
          '秘密后果$i',
          '不可知结果。',
          [],
          causes: [Cause(choice.id, CausalKind.direct)],
          witnessed: false,
        );
      }
      final context = service.context(world, 'explore');
      final choices = context['recentChoices'] as List;
      expect(choices.length, 3);
      expect(choices.map((c) => c['choice']), ['真实选择3', '真实选择2', '真实选择1']);
      expect((choices.first['outcomes'] as List).map((e) => e['title']), [
        '迎战3',
        '实际装备结果3',
      ]);
      expect(jsonEncode(choices), isNot(contains('时间相邻')));
      expect(jsonEncode(context), isNot(contains('秘密后果')));
      expect(jsonEncode(context), isNot(contains('秘密后果0')));
    },
  );

  test(
    'NPC context and topics require shared confirmed relationships',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final service = _service(db);
      final world = _world();
      final npc = world.entities.values.firstWhere(
        (n) => n.type == KarmaNodeType.npc,
      );
      npc.location = world.player.location;
      world.discover(world.playerId, npc.id, InformationChannel.witness);
      world.discover(npc.id, npc.id, InformationChannel.witness);
      world.discover(npc.id, world.playerId, InformationChannel.witness);
      final writer = FactWriter(world);
      final shared = writer.relation(
        npc.id,
        world.playerId,
        KarmaRelationType.friendship,
        null,
        strength: 40,
      );
      world.discover(world.playerId, shared.id, InformationChannel.witness);
      world.discover(npc.id, shared.id, InformationChannel.witness);
      final rumor = writer.relation(
        npc.id,
        world.playerId,
        KarmaRelationType.gratitude,
        null,
      );
      world.knowledge['${npc.id}|${rumor.id}'] = Knowledge(
        npc.id,
        rumor.id,
        InformationChannel.rumor,
        world.day,
        confirmed: false,
      );
      shared.strength = 95;
      shared.status = RelationStatus.settled;
      final secret = Entity(
        id: world.nextId('npc'),
        type: KarmaNodeType.npc,
        name: '秘密关系人物',
        location: world.player.location,
      );
      world.entities[secret.id] = secret;
      world.discover(npc.id, secret.id, InformationChannel.witness);
      final hiddenRelation = writer.relation(
        npc.id,
        secret.id,
        KarmaRelationType.hatred,
        null,
      );
      world.discover(npc.id, hiddenRelation.id, InformationChannel.witness);
      final hiddenPlace = Entity(
        id: world.nextId('location'),
        type: KarmaNodeType.location,
        name: '隐藏山门',
      );
      world.entities[hiddenPlace.id] = hiddenPlace;
      world.discover(npc.id, hiddenPlace.id, InformationChannel.witness);
      final place = world.mapPlaces.values.firstWhere(
        (p) => p.id != world.player.location,
      );
      world.discover(npc.id, place.id, InformationChannel.witness);
      world.discover(world.playerId, place.id, InformationChannel.witness);
      for (var i = 0; i < 7; i++) {
        world.dialogue.add(DialogueTurn(npc.id, '最近交谈$i', '人物说法$i', i));
      }
      world.dialogue.add(DialogueTurn(secret.id, '别人的秘密交谈', '未知说法', 10));
      final before = jsonEncode(world.toJson());
      final context = service.context(
        world,
        'talk',
        target: npc.id,
        input: '问路',
      );
      final relations = context['relationships'] as List;
      expect(relations.length, 1);
      expect(relations.single['strength'], 40);
      expect(relations.single['status'], statusLabel(RelationStatus.active));
      final history = context['history'] as List;
      expect(history.length, 6);
      expect(history.first['player'], '最近交谈1');
      expect(history.last['player'], '最近交谈6');
      expect(jsonEncode(context), isNot(contains('秘密关系人物')));
      expect(jsonEncode(context), isNot(contains('隐藏山门')));
      expect(jsonEncode(context), isNot(contains('别人的秘密交谈')));
      final topics = service.suggestedTopics(world, npc.id);
      expect(topics.length, 3);
      expect(topics.first, contains(world.entities[place.id]!.name));
      expect(topics[1], contains('根基'));
      expect(
        topics.last,
        contains(relationLabel(KarmaRelationType.friendship)),
      );
      expect(jsonEncode(topics), isNot(contains('秘密关系人物')));
      expect(jsonEncode(topics), isNot(contains('隐藏山门')));
      expect(jsonEncode(world.toJson()), before);
      world.knowledge.remove('${npc.id}|${shared.id}');
      expect(service.suggestedTopics(world, npc.id).last, '你最近遇到了哪些值得记住的人与事？');
      expect(service.suggestedTopics(world, secret.id), isEmpty);
    },
  );

  test(
    'long combat keeps victory and equipment in bounded recent outcomes',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final service = _service(db);
      final world = _world();
      final writer = FactWriter(world);
      final choice = writer.event('encounterChoice', '选择护送', '承担风险。', [
        world.playerId,
      ]);
      final challenge = writer.event(
        'challenge',
        '遭遇战斗',
        '迎战。',
        [world.playerId],
        causes: [Cause(choice.id, CausalKind.direct)],
      );
      for (var i = 0; i < 20; i++) {
        writer.event(
          'attack',
          '交锋第$i合',
          '实际战斗记录。',
          [world.playerId],
          causes: [Cause(challenge.id, CausalKind.direct)],
        );
      }
      final victory = writer.event(
        'victory',
        '战斗获胜',
        '实际战斗结算。',
        [world.playerId],
        causes: [Cause(challenge.id, CausalKind.direct)],
      );
      writer.event(
        'equipmentReward',
        '获得词条装备',
        '实际装备结算。',
        [world.playerId],
        causes: [Cause(victory.id, CausalKind.direct)],
      );
      final choices =
          service.context(world, 'explore')['recentChoices'] as List;
      final outcomes = choices.single['outcomes'] as List;
      expect(outcomes.length, 3);
      expect(outcomes.map((e) => e['title']), ['交锋第19合', '战斗获胜', '获得词条装备']);
    },
  );

  test(
    'exploration carries only accepted and confirmed commission progress',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final service = _service(db);
      var world = GameCommandService().execute(
        _world(),
        const GameCommand('acceptCommission', item: 'foundation'),
      );
      world = GameCommandService().execute(
        world,
        const GameCommand('stabilize'),
      );
      final state = CommissionRules.active(world)!;
      final hiddenEvidence = FactWriter(
        world,
      ).event('practice', '秘密练功证据', '玩家并不知情。', [], witnessed: false);
      state.evidence['practice'] = {'unknown': hiddenEvidence.id};
      final before = jsonEncode(world.toJson());
      final context = service.context(world, 'explore');
      final commission = context['commission'] as Map;
      expect(commission['title'], '固本培元');
      expect(commission['rewardGranted'], false);
      expect(commission['canDeliver'], false);
      expect((commission['objectives'] as List).map((o) => o['current']), [
        1,
        0,
      ]);
      expect(jsonEncode(commission), isNot(contains(state.id)));
      expect(jsonEncode(context), isNot(contains('秘密练功证据')));
      expect(jsonEncode(world.toJson()), before);
      world.knowledge.remove('${world.playerId}|${state.origin}');
      expect(service.context(world, 'explore')['commission'], isNull);
    },
  );

  test(
    'AI can compose novel local options while rules settle their fixed effects',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final world = _world();
      final inspirations = AdventureRules.inspirations(world);
      expect(inspirations, isNotEmpty);
      final optionIdeas = (inspirations.first['options'] as List)
          .where((o) => (o as Map)['effect'] != 'leave')
          .take(2)
          .toList();
      expect(optionIdeas.length, 2);
      final effects = optionIdeas
          .map((o) => (o as Map)['effect'] as String)
          .toList();
      final proposal = {
        'title': '檐下听雨',
        'text': '雨丝擦过屋檐，你把行囊移进避雨处，闻见浅淡药香。眼前线索可有不同取舍。',
        'options': [
          {'label': '静听雨声', 'effect': effects[0]},
          {'label': '整理行囊', 'effect': effects[1]},
          {'label': '安全离开', 'effect': 'leave'},
        ],
      };
      final adapter = _Adapter(proposal);
      final service = _service(db, adapter: adapter);
      const settings = AiSettings(
        base: 'https://example.test/v1',
        model: 'fixture-model',
        enabled: true,
        consent: true,
      );
      await service.saveSettings(settings, 'fixture-secret');
      final generated = await service.generate(world, 'explore', settings);
      final messages = (adapter.captured!.data as Map)['messages'] as List;
      final context = jsonDecode(messages.last['content'] as String) as Map;
      expect(context['localInspirations'], inspirations);
      expect(messages.first['content'], contains('不必照抄旧名称'));
      expect(messages.first['content'], contains('不得虚构委托完成'));
      expect(messages.first['content'], contains('不超过14字'));
      final discovered = GameCommandService().execute(
        world,
        GameCommand('explore', proposal: generated['proposal']),
      );
      expect(discovered.encounter!.title, '檐下听雨');
      expect(discovered.encounter!.options.map((o) => o.id), [
        ...effects,
        'leave',
      ]);
      final selected = discovered.encounter!.options.first;
      final catalog = AdventureRules.catalog(
        discovered,
      ).singleWhere((o) => o.id == selected.id);
      expect(selected.effects, catalog.effects);
      expect(selected.cost, catalog.cost);
      final settled = GameCommandService().execute(
        discovered,
        GameCommand('chooseEncounter', item: selected.id),
      );
      expect(settled.encounter, isNull);
      expect(
        settled.events.values.where((e) => e.kind == 'encounterChoice'),
        isNotEmpty,
      );
      expect(adapter.calls, 1);
    },
  );

  test('preferences never weaken validation or trigger paid retries', () async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    final adapter = _Adapter({
      ..._proposal,
      'options': [
        {'label': '任意奖励', 'effect': 'unbounded-reward'},
        {'label': '安全离开', 'effect': 'leave'},
      ],
    });
    final service = _service(db, adapter: adapter);
    const settings = AiSettings(
      base: 'https://example.test/v1',
      model: 'fixture-model',
      enabled: true,
      consent: true,
      narrativeStyle: '轻快对白',
      detail: 'standard',
    );
    await service.saveSettings(settings, 'fixture-secret');
    final world = _world();
    final before = jsonEncode(world.toJson());
    await expectLater(
      service.generate(world, 'explore', settings),
      throwsA(isA<AiFailure>()),
    );
    expect(adapter.calls, 1);
    expect(jsonEncode(world.toJson()), before);
    expect((await db.usage()).length, 1);
  });
}
