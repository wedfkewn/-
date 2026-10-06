import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/ui/map_page.dart';
import 'package:xiuxian_app/ui/growth_page.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

void main() {
  setUpAll(() async {
    for (final entry in {
      'MaShan': 'MaShanZheng-Regular.ttf',
      'WenKai': 'LXGWWenKai-Regular.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(
            File(
              'assets/fonts/${entry.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<ProviderContainer> show(
    WidgetTester tester,
    World world,
    Widget page, {
    double textScale = 1,
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
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const Key('capture-map-growth'),
            child: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture-map-growth')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File(
        'build/qa/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'map uses known regions, supports real pan/pinch, locating and route details',
    (tester) async {
      final world = WorldGenerator.generate(
        seed: 'map-ui',
        worldId: 'ui',
        npcCount: 12,
      );
      await show(tester, world, const MapPage());
      expect(find.text('天下概览'), findsOneWidget);
      expect(find.text('天渊州'), findsNothing);
      await tester.tap(find.text('青岚州'));
      await tester.pumpAndSettle();
      final viewer = find.byKey(const Key('shanhe-viewer'));
      await tester.ensureVisible(viewer);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final before = controller.value.clone();
      await tester.drag(viewer, const Offset(-80, -30));
      await tester.pumpAndSettle();
      expect(controller.value, isNot(before));
      final center = tester.getCenter(viewer);
      final first = await tester.createGesture(pointer: 1),
          second = await tester.createGesture(pointer: 2);
      await first.down(center - const Offset(35, 0));
      await second.down(center + const Offset(35, 0));
      await first.moveTo(center - const Offset(75, 0));
      await second.moveTo(center + const Offset(75, 0));
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('回到当前位置'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: viewer, matching: find.text('青溪镇')));
      await tester.pumpAndSettle();
      expect(find.text('返回地图'), findsOneWidget);
      await tester.tap(find.text('返回地图'));
      await tester.pumpAndSettle();
      await capture(tester, 'shanhe-map');
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('荒野'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '黑风谷');
      await tester.pumpAndSettle();
      final tile = find.byType(ListTile).first;
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text('规划逐段行旅'), findsOneWidget);
      expect(find.textContaining('青溪古道'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'growth conditions, real guard and pill preview remain usable with large text',
    (tester) async {
      final w = WorldGenerator.generate(
        seed: 'growth-ui',
        worldId: 'ui',
        npcCount: 12,
      );
      w.player.stage = 3;
      w.player.foundation = 100;
      w.player.insight = 10;
      w.player.spirit = 1000;
      w.player.hp = GameCommandService.maxHp(w.player);
      w.inventory.addAll({'筑基丹': 1, '护脉丹': 1});
      final guardian = w.entities['ui:npc:0']!..realm = 1;
      FactWriter(w).relation(
        w.playerId,
        guardian.id,
        KarmaRelationType.friendship,
        null,
        bidirectional: true,
      );
      await show(tester, w, const GrowthPage(), textScale: 1.4);
      expect(find.text('炼气圆满'), findsOneWidget);
      await capture(tester, 'growth-preparation');
      await tester.ensureVisible(find.text('使用护脉丹'));
      await tester.tap(find.text('使用护脉丹'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(guardian.name));
      await tester.tap(find.text(guardian.name));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('本次成功率 90%'));
      expect(find.text('本次成功率 90%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'active legacy save migration preserves identity, history and random streams',
    (tester) async {
      final w = WorldGenerator.generate(
        seed: 'legacy-active',
        worldId: 'legacy',
        version: 1,
        npcCount: 8,
      );
      w.player.realm = 3;
      w.player.spirit = 987;
      final history = w.events.keys.toList();
      final random = w.random.state;
      final container = await show(tester, w, const MapPage());
      final restored = (await tester.runAsync(
        container.read(databaseProvider).load,
      ))!;
      expect(restored.id, w.id);
      expect(restored.player.location, w.player.location);
      expect(restored.player.realm, 3);
      expect(restored.player.spirit, 987);
      expect(restored.player.foundation, 30);
      expect(restored.player.insight, 0);
      expect(restored.events.keys.toList(), history);
      expect(restored.random.state, random);
      expect(restored.mapPlaces.length, 288);
      expect(restored.knows(restored.playerId, 'legacy:location:200'), isFalse);
      expect(restored.revision, w.revision + 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy archive map stays absent and legacy preparation is never invented',
    (tester) async {
      final w = WorldGenerator.generate(
        seed: 'old-life',
        worldId: 'old',
        version: 1,
        npcCount: 8,
      )..frozen = true;
      final container = await show(tester, w, const MapPage());
      expect(find.textContaining('旧人生档案没有山河地图'), findsOneWidget);
      final db = container.read(databaseProvider);
      expect((await tester.runAsync(db.load))!.mapVersion, 0);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: const GrowthPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('未记录小阶段'), findsOneWidget);
      expect((await tester.runAsync(db.load))!.mapVersion, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
