import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/main.dart';
import 'package:xiuxian_app/ui/karma_page.dart';

void main() {
  setUpAll(() async {
    final fontFile = File('C:/Windows/Fonts/simhei.ttf');
    if (await fontFile.exists()) {
      final loader = FontLoader('QAChinese')
        ..addFont(
          fontFile.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  testWidgets(
    'canvas taps nodes and curved edges, drags, zooms, resets and reuses layout',
    (tester) async {
      final w = WorldGenerator.generate(seed: 'ui', worldId: 'ui', npcCount: 5);
      final f = FactWriter(w);
      final e = f.event('meeting', '相识', '结识', [w.playerId, 'ui:npc:0']);
      f.relation(
        w.playerId,
        'ui:npc:0',
        KarmaRelationType.friendship,
        e,
        bidirectional: true,
      );
      final graph = KarmaRepository(w).query(const GraphQuery());
      final key = GlobalKey<GraphCanvasState>();
      String? tappedNode, tappedEdge;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphCanvas(
              key: key,
              graph: graph,
              center: w.playerId,
              onNode: (n) => tappedNode = n.id,
              onEdge: (e) => tappedEdge = e.id,
            ),
          ),
        ),
      );
      await tester.pump();
      final state = key.currentState!;
      final original = state.transform.value.clone();
      await tester.tapAt(tester.getCenter(find.byType(GraphCanvas)));
      expect(tappedNode, w.playerId);
      final geometry = state.geometries.first;
      final point = geometry.point(.5);
      final matrix = state.transform.value;
      final viewPoint = Offset(
        point.dx * matrix.entry(0, 0) + matrix.entry(0, 3),
        point.dy * matrix.entry(1, 1) + matrix.entry(1, 3),
      );
      await tester.tapAt(viewPoint);
      expect(tappedEdge, geometry.edge.id);
      await tester.drag(find.byType(GraphCanvas), const Offset(50, 30));
      await tester.pump();
      expect(state.transform.value, isNot(original));
      state.zoom(1.25);
      await tester.pump();
      expect(state.transform.value.getMaxScaleOnAxis(), closeTo(1.25, .01));
      // Exercise actual two-pointer scaling, not only the zoom buttons.
      final center = tester.getCenter(find.byType(GraphCanvas));
      final first = await tester.createGesture(pointer: 1),
          second = await tester.createGesture(pointer: 2);
      await first.down(center - const Offset(40, 0));
      await second.down(center + const Offset(40, 0));
      await first.moveTo(center - const Offset(80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await tester.pump();
      expect(state.transform.value.getMaxScaleOnAxis(), greaterThan(1.25));
      await first.up();
      await second.up();
      state.reset();
      await tester.pump();
      expect(state.transform.value, original);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '360px phone game screens, theme, search, filters and timeline render without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = GameCommandService().execute(
        WorldGenerator.generate(
          seed: 'screen',
          worldId: 'screen',
          npcCount: 12,
        ),
        const GameCommand('rescue', target: 'screen:npc:0'),
      );
      await db.save(w, makeActive: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const XiuxianApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('李长生 · 炼气'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('切换深浅主题'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('世界').last);
      await tester.pumpAndSettle();
      expect(find.text('附近修士'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('因果').last);
      await tester.pumpAndSettle();
      expect(find.text('天机因果图'), findsOneWidget);
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '不存在的名字');
      await tester.pump();
      expect(find.text('没有已知结果'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('救命之恩').last);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('因果长河'));
      await tester.pumpAndSettle();
      expect(find.textContaining('救下'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('万世碑').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'death page and archive history forbid commands; fresh life is isolated',
    (tester) async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'death-ui',
        worldId: 'death-ui',
        npcCount: 5,
      );
      final f = FactWriter(w);
      final e = f.event('accident', '劫数', '意外', [w.playerId]);
      f.die(w.player, e);
      w.assessment = LifeAssessment.calculate(w);
      await db.save(w, makeActive: true);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const XiuxianApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '闭关30日'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('万世碑').last);
      await tester.pumpAndSettle();
      expect(find.text('一世因果'), findsOneWidget);
      final controller = container.read(gameProvider.notifier);
      await expectLater(
        controller.command(const GameCommand('wait')),
        throwsA(isA<RuleViolation>()),
      );
      await tester.runAsync(() => controller.create('新修士', 'death-ui'));
      await tester.pumpAndSettle();
      expect(
        container.read(gameProvider).asData!.value.playerId,
        isNot(w.playerId),
      );
      await tester.runAsync(() => controller.openArchive(w.id));
      await tester.pumpAndSettle();
      expect(container.read(gameProvider).asData!.value.readOnly, true);
      await tester.runAsync(
        () => expectLater(
          controller.create('第三世', 'x'),
          throwsA(isA<RuleViolation>()),
        ),
      );
      expect((await tester.runAsync(() => db.load()))!.player.name, '新修士');
    },
  );
  testWidgets('render graph artifact for visual inspection', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var w = WorldGenerator.generate(
      seed: 'visual',
      worldId: 'visual',
      npcCount: 12,
    );
    final commands = GameCommandService();
    w = commands.execute(
      w,
      const GameCommand('rescue', target: 'visual:npc:0'),
    );
    for (var i = 0; i < 4; i++) {
      w = commands.execute(w, GameCommand('befriend', target: 'visual:npc:$i'));
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'QAChinese',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff526f63),
            surface: const Color(0xfff4f1e9),
          ),
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            appBar: AppBar(title: const Text('天机因果图')),
            body: GraphCanvas(
              graph: KarmaRepository(w).query(const GraphQuery(hops: 2)),
              center: w.playerId,
              onNode: (_) {},
              onEdge: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/qa/karma-phone.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
