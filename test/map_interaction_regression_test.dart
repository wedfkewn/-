import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/map_repository.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';
import 'package:xiuxian_app/ui/map_page.dart';

void main() {
  World fresh() => WorldGenerator.generate(
    seed: 'map-interaction',
    worldId: 'map-interaction',
    npcCount: 12,
  );

  Future<ProviderContainer> showMap(
    WidgetTester tester,
    World world, {
    bool nested = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = GameDatabase.memory();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await db.save(world, makeActive: true);
      await container.read(gameProvider.future);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: InkTheme.build(Brightness.light),
          home: nested
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const MapPage(),
                        ),
                      ),
                      child: const Text('修行首页'),
                    ),
                  ),
                )
              : const MapPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (nested) {
      await tester.tap(find.text('修行首页'));
      await tester.pumpAndSettle();
    }
    return container;
  }

  testWidgets('locating clears the visible search field and the filter', (
    tester,
  ) async {
    await showMap(tester, fresh());
    await tester.enterText(find.byType(TextField), '不存在的地点');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '青溪镇'), findsNothing);
    await tester.tap(find.byTooltip('回到当前位置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('青溪镇'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a final travel segment keeps its encounter entry after arrival',
    (tester) async {
      var world = fresh();
      final road = MapRepository(world).query().roads.firstWhere(
        (road) =>
            road.a == world.player.location || road.b == world.player.location,
      );
      final target = road.other(world.player.location);
      final commands = GameCommandService();
      world = commands.execute(world, GameCommand('planRoute', target: target));
      expect(world.journey!.roads.length, 1);
      world.adventureRandom.state = 100;
      world = commands.execute(world, const GameCommand('moveStep'));
      expect(world.player.location, target);
      expect(world.journey, isNull);
      expect(world.encounter, isNotNull);
      final container = await showMap(tester, world);
      final day = container.read(gameProvider).requireValue.day;
      expect(find.textContaining('有待处理奇遇'), findsOneWidget);
      expect(find.text('前进一段'), findsNothing);
      await tester.tap(find.text('处理奇遇'));
      await tester.pumpAndSettle();
      expect(find.byType(EncounterPage), findsOneWidget);
      expect(container.read(gameProvider).requireValue.day, day);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('secret exploration disables route planning in place details', (
    tester,
  ) async {
    var world = fresh();
    final place = world.mapPlaces.values.firstWhere(
      (place) => place.kind == PlaceKind.secret && place.danger == 0,
    );
    world.player.location = place.id;
    MapRules.revealNearby(world, world.playerId, InformationChannel.witness);
    world = GameCommandService().execute(
      world,
      const GameCommand('enterSecret'),
    );
    final target = MapRepository(world).query().places.firstWhere(
      (known) =>
          known.confirmed &&
          known.place.id != place.id &&
          MapRepository(world).route(known.place.id)?.isNotEmpty == true,
    );
    await showMap(tester, world);
    final tile = find.widgetWithText(ListTile, target.name);
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final plan = find.widgetWithText(FilledButton, '规划逐段行旅');
    expect(plan, findsOneWidget);
    expect(tester.widget<FilledButton>(plan).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from a map during tribulation goes to the root', (
    tester,
  ) async {
    var world = fresh();
    world.player
      ..stage = 3
      ..foundation = 100
      ..insight = 100
      ..spirit = 1000;
    world.inventory['筑基丹'] = 1;
    world = GameCommandService().execute(
      world,
      const GameCommand('breakthrough'),
    );
    expect(world.tribulation, isNotNull);
    final container = await showMap(tester, world, nested: true);
    final day = container.read(gameProvider).requireValue.day;
    expect(find.text('返回交锋'), findsOneWidget);
    await tester.tap(find.text('返回交锋'));
    await tester.pumpAndSettle();
    expect(find.byType(MapPage), findsNothing);
    expect(find.text('修行首页'), findsOneWidget);
    expect(container.read(gameProvider).requireValue.day, day);
    expect(tester.takeException(), isNull);
  });
}
