import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/domain/models.dart';

void main() {
  test(
    '5000 NPC / 50000 relationships / 100000 events: bounded indexed public queries',
    () {
      final w = WorldGenerator.generate(
        seed: 'scale',
        worldId: 'large',
        npcCount: 5000,
      );
      var i = 0;
      while (w.relations.length < 50000) {
        final source = i < 300 ? w.playerId : 'large:npc:${i % 5000}';
        final target = 'large:npc:${(i + 1) % 5000}';
        final r = Relation(
          id: 'large:load-relation:$i',
          source: source,
          target: target,
          type: KarmaRelationType.values[i % KarmaRelationType.values.length],
          strength: 40,
        );
        w.relations[r.id] = r;
        if (i < 300) {
          w.discover(w.playerId, target, InformationChannel.witness);
          w.discover(w.playerId, r.id, InformationChannel.witness);
        }
        i++;
      }
      i = 0;
      while (w.events.length < 100000) {
        final e = GameEvent(
          id: 'large:load-event:$i',
          time: i ~/ 3,
          kind: 'scale',
          title: '性能事件 $i',
          description: '测试规模历史记录',
          location: 'large:location:4',
          participants: ['large:npc:${i % 5000}'],
        );
        w.events[e.id] = e;
        if (i < 1000) {
          w.discover(w.playerId, e.id, InformationChannel.witness);
        }
        i++;
      }
      final build = Stopwatch()..start();
      final repository = KarmaRepository(w);
      build.stop();
      final queries = Stopwatch()..start();
      for (var j = 0; j < 100; j++) {
        final graph = repository.query(const GraphQuery(hops: 5));
        expect(graph.nodes.length, lessThanOrEqualTo(80));
        expect(graph.edges.length, lessThanOrEqualTo(480));
        expect(graph.truncated, true);
        expect(graph.nodes.every((n) => w.knows(w.playerId, n.id)), true);
        final timeline = repository.timeline(offset: j * 5, limit: 30);
        expect(timeline.length, 30);
      }
      queries.stop();
      expect(repository.timeline(offset: 2000), isEmpty);
      expect(repository.search('性能'), isEmpty);
      // Loose CI bound catches accidental repeated world traversal, not an FPS
      // assertion. Real-device frame timing is a separate acceptance check.
      expect(queries.elapsedMilliseconds, lessThan(5000));
      // ignore: avoid_print
      print(
        'SCALE npc=5000 relations=${w.relations.length} events=${w.events.length} index=${build.elapsedMilliseconds}ms queries100=${queries.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
