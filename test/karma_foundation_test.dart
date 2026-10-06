import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/domain/models.dart';

World world() => WorldGenerator.generate(
  seed: 'karma-acceptance',
  worldId: 'test',
  npcCount: 12,
);
void main() {
  test(
    'rescue fulfills the rescuers promise; renewed debt links latest loan',
    () {
      var w = world();
      final commands = GameCommandService();
      w = commands.execute(
        w,
        const GameCommand('promise', target: 'test:npc:0'),
      );
      w = commands.execute(
        w,
        const GameCommand('rescue', target: 'test:npc:0'),
      );
      final promise = KarmaRepository(w)
          .query(const GraphQuery())
          .edges
          .firstWhere((e) => e.relationType == KarmaRelationType.promise);
      expect(promise.resolved, true);
      for (var i = 0; i < 2; i++) {
        w = commands.execute(
          w,
          const GameCommand('borrow', target: 'test:npc:0'),
        );
        w = commands.execute(
          w,
          const GameCommand('repay', target: 'test:npc:0'),
        );
      }
      final repayments = w.events.values
          .where((e) => e.kind == 'repay')
          .toList();
      final loans = w.events.values.where((e) => e.kind == 'borrow').toList();
      expect(repayments.last.causes.single.eventId, loans.last.id);
      expect(repayments.first.causes.single.eventId, loans.first.id);
    },
  );
  test('remote revenge fact does not inform its target automatically', () {
    final w = world();
    final npc = w.entities['test:npc:0']!;
    npc.location = 'test:location:4';
    final f = FactWriter(w);
    final e = f.event(
      'revenge',
      '秘密复仇',
      '远方筹划',
      [npc.id, w.playerId],
      location: npc.location,
      witnessed: false,
    );
    final r = f.relation(
      npc.id,
      w.playerId,
      KarmaRelationType.hatred,
      e,
      strength: 90,
    );
    expect(w.knows(w.playerId, e.id), false);
    expect(KarmaRepository(w).edge(r.id), isNull);
    expect(KarmaRepository(w).event(e.id), isNull);
    expect(w.knows(npc.id, r.id), true);
  });
  test(
    'death preserves settled and outstanding obligations independently of lifecycle',
    () {
      final w = world();
      final f = FactWriter(w);
      final npc = w.entities['test:npc:0']!;
      final e = f.event('rescue', '救助', '救助', [w.playerId, npc.id]);
      final outstanding = f.relation(
        npc.id,
        w.playerId,
        KarmaRelationType.gratitude,
        e,
        strength: 80,
      );
      final settled = f.relation(
        w.playerId,
        npc.id,
        KarmaRelationType.promise,
        e,
        strength: 70,
      );
      settled.status = RelationStatus.settled;
      w.discover(w.playerId, settled.id, InformationChannel.witness);
      f.die(w.player, e);
      final result = LifeAssessment.calculate(w);
      expect(outstanding.status, RelationStatus.historical);
      expect(outstanding.resolved, false);
      expect(settled.resolved, true);
      expect(result['settled'], 1);
      expect(result['unsettled'], 1);
      expect(result['major'], 2);
    },
  );
  test('same seed + version + config generates identical facts and RNG', () {
    expect(jsonEncode(world().toJson()), jsonEncode(world().toJson()));
    expect(
      jsonEncode(
        WorldGenerator.generate(
          seed: 'other',
          worldId: 'test',
          npcCount: 12,
        ).toJson(),
      ),
      isNot(jsonEncode(world().toJson())),
    );
    expect(
      () => WorldGenerator.generate(seed: 'x', worldId: 'x', version: 99),
      throwsA(isA<RuleViolation>()),
    );
  });
  test('migration retains stable NPC identity and unique graph node', () {
    final w = world();
    final n = w.entities['test:npc:0']!;
    final f = FactWriter(w);
    final e = f.event('friendship', '结交', '友好会面', [w.playerId, n.id]);
    f.relation(
      w.playerId,
      n.id,
      KarmaRelationType.friendship,
      e,
      bidirectional: true,
    );
    n.location = 'test:location:4';
    n.updated = 20;
    final graph = KarmaRepository(w).query(const GraphQuery(hops: 5));
    expect(graph.nodes.where((node) => node.id == n.id).length, 1);
    expect(w.entities.values.where((node) => node.id == n.id).length, 1);
  });
  test('gratitude direction and multiple independent relations', () {
    var w = world();
    final commands = GameCommandService();
    w = commands.execute(w, const GameCommand('rescue', target: 'test:npc:0'));
    w = commands.execute(
      w,
      const GameCommand('befriend', target: 'test:npc:0'),
    );
    final graph = KarmaRepository(w).query(const GraphQuery());
    final edges = graph.edges
        .where(
          (e) => {
            e.sourceNodeId,
            e.targetNodeId,
          }.containsAll([w.playerId, 'test:npc:0']),
        )
        .toList();
    expect(
      edges.map((e) => e.relationType),
      containsAll([KarmaRelationType.gratitude, KarmaRelationType.friendship]),
    );
    final gratitude = edges.firstWhere(
      (e) => e.relationType == KarmaRelationType.gratitude,
    );
    expect(gratitude.sourceNodeId, 'test:npc:0');
    expect(gratitude.targetNodeId, w.playerId);
    expect(gratitude.bidirectional, false);
    expect(
      edges
          .firstWhere((e) => e.relationType == KarmaRelationType.friendship)
          .bidirectional,
      true,
    );
  });
  test('death preserves historical relations, terminated != nonexistent', () {
    final w = world();
    final f = FactWriter(w);
    final npc = w.entities['test:npc:0']!;
    final e = f.event('meeting', '结交', '相识', [w.playerId, npc.id]);
    final r = f.relation(
      w.playerId,
      npc.id,
      KarmaRelationType.friendship,
      e,
      bidirectional: true,
    );
    f.die(npc, e);
    final repository = KarmaRepository(w);
    expect(repository.edge(r.id)!.status, RelationStatus.historical);
    expect(repository.node(npc.id)!.alive, false);
    expect(repository.edge('never-existed'), isNull);
  });
  test('settled debt remains queryable with source events', () {
    var w = world();
    final c = GameCommandService();
    w = c.execute(w, const GameCommand('borrow', target: 'test:npc:0'));
    w = c.execute(w, const GameCommand('repay', target: 'test:npc:0'));
    final graph = KarmaRepository(
      w,
    ).query(const GraphQuery(statuses: {RelationStatus.settled}));
    expect(graph.edges.single.relationType, KarmaRelationType.debt);
    expect(graph.edges.single.relatedEventIds.length, 2);
  });
  test('hidden entity, relationship, event and search do not leak', () {
    final w = world();
    final f = FactWriter(w);
    final hidden = Entity(
      id: 'test:hidden',
      type: KarmaNodeType.npc,
      name: '秘密道人',
      location: 'test:location:4',
    );
    w.entities[hidden.id] = hidden;
    final secret = f.event(
      'secret',
      '秘密事件',
      '未知事实',
      [hidden.id],
      location: hidden.location,
      witnessed: false,
    );
    final edge = f.relation(
      hidden.id,
      'test:sect:1',
      KarmaRelationType.karmicEntanglement,
      secret,
    );
    final repository = KarmaRepository(w);
    expect(repository.node(hidden.id), isNull);
    expect(repository.edge(edge.id), isNull);
    expect(repository.event(secret.id), isNull);
    expect(repository.search('秘密'), isEmpty);
    expect(repository.query(GraphQuery(center: hidden.id)).nodes, isEmpty);
    expect(repository.timeline(entity: hidden.id), isEmpty);
    expect(
      repository
          .query(const GraphQuery(worldView: true, hops: 5))
          .nodes
          .any((n) => n.id == hidden.id),
      false,
    );
    w.discover(w.playerId, edge.id, InformationChannel.rumor, confirmed: false);
    expect(KarmaRepository(w).edge(edge.id), isNull);
  });
  test('remote changes do not leak through strength/status filters', () {
    final w = world();
    final f = FactWriter(w);
    final n = w.entities['test:npc:0']!;
    final meeting = f.event('meeting', '相识', '友好会面', [w.playerId, n.id]);
    final r = f.relation(
      w.playerId,
      n.id,
      KarmaRelationType.friendship,
      meeting,
      strength: 20,
      bidirectional: true,
    );
    w.day = 100;
    n.location = 'test:location:4';
    r.strength = 100;
    r.status = RelationStatus.historical;
    r.updated = 100;
    final repo = KarmaRepository(w);
    expect(repo.edge(r.id)!.strength, 20);
    expect(repo.edge(r.id)!.status, RelationStatus.active);
    expect(repo.query(const GraphQuery(minimumStrength: 80)).edges, isEmpty);
    expect(
      repo.query(const GraphQuery(statuses: {RelationStatus.historical})).edges,
      isEmpty,
    );
  });
  test('timeline is ordered, correlation does not create causation', () {
    final w = world();
    final f = FactWriter(w);
    w.day = 12;
    final a = f.event('a', '甲事件', '没有来源', [w.playerId]);
    w.day = 5;
    final b = f.event('b', '乙事件', '没有来源', [w.playerId]);
    w.day = 12;
    final c = f.event(
      'c',
      '丙事件',
      '明确影响',
      [w.playerId],
      causes: [Cause(a.id, CausalKind.influence)],
    );
    final repo = KarmaRepository(w);
    final list = repo.timeline();
    expect(list.map((e) => e.time), orderedEquals([0, 5, 12, 12]));
    expect(repo.event(b.id)!.causes, isEmpty);
    expect(
      repo.causalChain(a.id).map((e) => e.id),
      orderedEquals([a.id, c.id]),
    );
    expect(
      () => f.event(
        'x',
        'x',
        'x',
        [w.playerId],
        causes: [const Cause('missing', CausalKind.direct)],
      ),
      throwsA(isA<RuleViolation>()),
    );
  });
  test('invalid command leaves source world and RNG untouched', () {
    final w = world();
    final before = jsonEncode(w.toJson());
    expect(
      () => GameCommandService().execute(
        w,
        const GameCommand('trade', item: '青锋剑', amount: 99),
      ),
      throwsA(isA<RuleViolation>()),
    );
    expect(jsonEncode(w.toJson()), before);
  });
}
