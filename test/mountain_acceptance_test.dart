import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/data/game_database.dart';

void main() {
  test(
    'fixed default world: discover next province, gather, grow four stages, befriend a real guard and reach foundation',
    () async {
      var w = WorldGenerator.generate(seed: 'mountain-life', worldId: 'loop');
      expect(w.npcCount, 1200);
      expect(w.mapPlaces.length, 288);
      final c = GameCommandService();
      void act(GameCommand command) {
        w = c.execute(w, command);
      }

      void walk(String target) {
        act(GameCommand('planRoute', target: target));
        while (w.journey != null) {
          act(const GameCommand('moveStep'));
          if (w.encounter != null) {
            act(const GameCommand('chooseEncounter', item: 'leave'));
          }
        }
      }

      act(const GameCommand('buyMap'));
      walk('loop:location:24');
      expect(w.mapPlaces[w.player.location]!.region, 1);
      act(const GameCommand('gather', item: '筑基丹'));
      final material = w.events.values.lastWhere((e) => e.kind == 'gather');
      expect(w.events[material.causes.single.eventId]!.kind, 'travel');
      while (w.player.stage < 3) {
        while (w.player.foundation < GrowthRules.rootRequired(w.player)) {
          act(const GameCommand('stabilize'));
        }
        while (w.player.spirit <
            Content.threshold(w.player.realm, w.player.stage)) {
          act(const GameCommand('cultivate'));
        }
        act(const GameCommand('advanceStage'));
      }
      walk('loop:location:0');
      while (w.player.foundation < 100) {
        act(const GameCommand('stabilize'));
      }
      while (w.player.spirit <
          Content.threshold(w.player.realm, w.player.stage)) {
        act(const GameCommand('cultivate'));
      }
      final candidates = w.entities.values
          .where(
            (n) =>
                n.type == KarmaNodeType.npc &&
                n.alive &&
                n.realm >= 1 &&
                n.location == w.player.location &&
                w.knows(w.playerId, n.id),
          )
          .map((n) => n.id)
          .toList();
      String? guardian;
      for (final id in candidates) {
        act(GameCommand('befriend', target: id));
        if (GrowthRules.view(w).guards.contains(id)) {
          guardian = id;
          break;
        }
      }
      expect(guardian, 'loop:npc:97');
      act(GameCommand('breakthrough', target: guardian));
      expect(w.player.realm, 0);
      while (w.tribulation != null && !w.frozen) {
        act(const GameCommand('defend'));
      }
      expect(w.player.realm, 1);
      expect(w.player.stage, 0);
      expect(w.events.values.where((e) => e.kind == 'advanceStage').length, 3);
      final preparation = w.events.values.lastWhere(
        (e) => e.kind == 'breakthroughPreparation',
      );
      expect(preparation.participants, contains(guardian));
      final chain = KarmaRepository(w).causalChain(material.id);
      expect(chain.any((e) => w.events[e.id]!.kind == 'breakthrough'), isTrue);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      await db.save(w, makeActive: true);
      final restored = (await db.load())!;
      expect(jsonEncode(restored.toJson()), jsonEncode(w.toJson()));
      expect(
        KarmaRepository(restored).causalChain(material.id).map((e) => e.id),
        chain.map((e) => e.id),
      );
    },
  );
}
