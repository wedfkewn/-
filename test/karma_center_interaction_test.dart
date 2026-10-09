import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';
import 'package:xiuxian_app/ui/karma_page.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final db = GameDatabase.memory();
  addTearDown(db.close);
  final world = WorldGenerator.generate(
    seed: 'karma-center-interaction',
    worldId: 'karma-center-interaction',
    name: '中心玩家',
    npcCount: 8,
  );
  final npc = world.entities.values.firstWhere(
    (n) => n.type == KarmaNodeType.npc,
  );
  world.entities[npc.id] = Entity.fromJson({...npc.toJson(), 'name': '已知甲'});
  world.discover(world.playerId, npc.id, InformationChannel.witness);
  await tester.runAsync(() => db.save(world, makeActive: true));
  final container = ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(gameProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: InkTheme.build(Brightness.light),
        home: const Scaffold(body: KarmaPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Set<int> _scope(WidgetTester tester) => tester
    .widget<SegmentedButton<int>>(
      find.byWidgetPredicate(
        (w) => w is SegmentedButton<int> && w.segments.length == 3,
      ),
    )
    .selected;

Future<void> _cancelWithAnimation(WidgetTester tester) async {
  await tester.tap(find.byTooltip('关闭弹窗'));
  await tester.pump();
  tester.view.viewInsets = const FakeViewPadding(bottom: 240);
  await tester.pump(const Duration(milliseconds: 30));
  expect(tester.takeException(), isNull);
  tester.view.viewInsets = const FakeViewPadding();
  await tester.pump(const Duration(milliseconds: 30));
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle();
  expect(find.text('搜索已知实体'), findsNothing);
}

void main() {
  testWidgets('cancel NPC selection retains my center and world scope', (
    tester,
  ) async {
    await _open(tester);
    for (final scope in [0, 2]) {
      if (scope == 2) {
        await tester.tap(find.text('天下'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('人物'));
      await tester.pumpAndSettle();
      expect(_scope(tester), {scope});
      expect(find.text('已知甲'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '中心玩家'), findsNothing);
      await _cancelWithAnimation(tester);
      expect(_scope(tester), {scope});
      expect(find.textContaining('中心：'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('select known NPC commits center after dialog exit', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('人物'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '已知甲'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(_scope(tester), {1});
    expect(find.text('中心：已知甲'), findsOneWidget);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await _cancelWithAnimation(tester);
    expect(_scope(tester), {1});
    expect(find.text('中心：已知甲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary search can still select a non NPC entity', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '中心玩家');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '中心玩家'));
    await tester.pumpAndSettle();
    expect(_scope(tester), {0});
    expect(find.text('中心：中心玩家'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
