import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/main.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/battle_stage.dart';
import 'package:xiuxian_app/ui/cultivation_page.dart';

World _world(String id) => WorldGenerator.generate(
  seed: 'navigation-$id',
  worldId: id,
  name: id,
  npcCount: 8,
);

Future<ProviderContainer> _show(WidgetTester tester, GameDatabase db) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(gameProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XiuxianApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('继续这一世'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _scroll(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('encounter combat closes child routes and exposes attack', (
    tester,
  ) async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    var w = _world('escort');
    final enemy = w.entities.values.firstWhere(
      (n) => n.type == KarmaNodeType.npc,
    );
    enemy.location = w.player.location;
    enemy.realm = 0;
    enemy.personality = '好战';
    enemy.lastActed = 10000;
    w.discover(w.playerId, enemy.id, InformationChannel.witness);
    w = GameCommandService().execute(
      w,
      const GameCommand(
        'explore',
        proposal: {
          'title': '商旅求援',
          'text': '商旅请求护送，沿途可能遭遇阻拦。',
          'options': [
            {'label': '护送商旅', 'effect': 'escort'},
            {'label': '安然离去', 'effect': 'leave'},
          ],
        },
      ),
    );
    await tester.runAsync(() => db.save(w, makeActive: true));
    final container = await _show(tester, db);
    await tester.tap(find.text('世界').last);
    await tester.pumpAndSettle();
    await _scroll(tester, find.textContaining('待处理奇遇'));
    await tester.tap(find.textContaining('待处理奇遇'));
    await tester.pumpAndSettle();
    await _scroll(tester, find.text('护送商旅'));
    await tester.tap(find.text('护送商旅'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EncounterPage), findsNothing);
    expect(find.byType(CultivationPage), findsOneWidget);
    expect(container.read(gameProvider).requireValue.battleName, isNotNull);
    await _scroll(tester, find.text('出手攻击'));
    expect(find.text('出手攻击'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resumed encounter has a direct resolution entry on cultivation',
    (tester) async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = GameCommandService().execute(
        _world('encounter'),
        const GameCommand('explore'),
      );
      await tester.runAsync(() => db.save(w, makeActive: true));
      final container = await _show(tester, db);
      await _scroll(tester, find.text('处理奇遇'));
      await tester.tap(find.text('处理奇遇'));
      await tester.pumpAndSettle();
      expect(find.byType(EncounterPage), findsOneWidget);
      final leave = w.encounter!.options.singleWhere((o) => o.id == 'leave');
      await _scroll(tester, find.text(leave.label));
      await tester.tap(find.text(leave.label));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(container.read(gameProvider).asData!.value.encounter, isNull);
      expect(find.byType(CultivationPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('starting battle in world brings combat controls into view', (
    tester,
  ) async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    final w = _world('battle');
    final npc = w.entities.values.firstWhere(
      (n) => n.type == KarmaNodeType.npc,
    );
    npc.location = w.player.location;
    w.discover(w.playerId, npc.id, InformationChannel.witness);
    await tester.runAsync(() => db.save(w, makeActive: true));
    final container = await _show(tester, db);
    await tester.tap(find.text('世界').last);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => container
          .read(gameProvider.notifier)
          .command(GameCommand('startBattle', target: npc.id)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CultivationPage), findsOneWidget);
    await _scroll(tester, find.byType(BattleStage));
    expect(container.read(gameProvider).asData!.value.battleName, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return from old archive goes to current cultivation', (
    tester,
  ) async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    final old = _world('old');
    old.player.ageDays = Content.lifespans[0] * 360 - 1;
    final dead = GameCommandService().execute(old, const GameCommand('wait'));
    final current = _world('current');
    await tester.runAsync(() async {
      await db.save(old, makeActive: true);
      await db.save(dead, previous: old);
      await db.save(current, makeActive: true);
    });
    final container = await _show(tester, db);
    await tester.tap(find.text('万世碑').last);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => container.read(gameProvider.notifier).openArchive(dead.id),
    );
    await tester.pumpAndSettle();
    expect(container.read(gameProvider.notifier).canCreateLife, isFalse);
    await _scroll(tester, find.text('回到当前人生'));
    expect(find.text('开启新一世'), findsNothing);
    await tester.tap(find.text('回到当前人生'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CultivationPage), findsOneWidget);
    expect(container.read(gameProvider).asData!.value.name, 'current');
    expect(container.read(gameProvider).asData!.value.readOnly, isFalse);
    expect(tester.takeException(), isNull);
  });
}
