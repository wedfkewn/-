import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/main.dart';
import 'package:xiuxian_app/ui/details.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';
import 'package:xiuxian_app/ui/ink_overlays.dart';
import 'package:xiuxian_app/ui/map_page.dart';

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
  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(WidgetTester tester, String file) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('save-capture')),
          )
          .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File('build/qa/$file.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'death on a child route closes it, reports once, returns to saves and archive can return',
    (tester) async {
      phone(tester);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'death-save',
        worldId: 'death-save',
        npcCount: 8,
      );
      w.player.ageDays = Content.lifespans[0] * 360 - 1;
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await db.save(w, makeActive: true);
        await container.read(gameProvider.future);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(
            key: Key('save-capture'),
            child: XiuxianApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'save-alive');
      await tester.tap(find.text('继续这一世'));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Scaffold).first);
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute<void>(builder: (_) => const MapPage()));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container
            .read(gameProvider.notifier)
            .command(const GameCommand('wait')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MapPage), findsNothing);
      expect(find.text('此世已终'), findsOneWidget);
      expect((await tester.runAsync(db.load))!.frozen, isTrue);
      await capture(tester, 'death-notice');
      await tester.tap(find.text('返回存档'));
      await tester.pumpAndSettle();
      expect(find.text('继续这一世'), findsNothing);
      expect(find.text('当前没有在世角色。'), findsOneWidget);
      await capture(tester, 'save-sealed');
      await tester.scrollUntilVisible(find.byType(ListTile), 180);
      await tester.tap(find.byType(ListTile).first);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('一世因果'), findsOneWidget);
      await capture(tester, 'illustrated-archive');
      await tester.tap(find.byTooltip('返回存档'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('仙途存档'), findsOneWidget);
      expect(find.text('此世已终'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all sheets fill phone width, close explicitly and long dialogs survive keyboard and large text',
    (tester) async {
      phone(tester);
      final w = WorldGenerator.generate(
        seed: 'sheet',
        worldId: 'sheet',
        npcCount: 8,
      );
      final repo = KarmaRepository(w);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('save-capture'),
            child: MaterialApp(
              theme: InkTheme.build(brightness),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Column(
                    children: [
                      TextButton(
                        onPressed: () =>
                            showNodeDetails(ctx, repo.node(w.playerId)!),
                        child: const Text('人物详情'),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: ctx,
                          builder: (c) => const InkDialog(
                            title: Text('搜索与选择'),
                            content: SizedBox(
                              height: 360,
                              child: Column(
                                children: [
                                  TextField(),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Text('长期内容与人物情报'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: [Text('确认')],
                          ),
                        ),
                        child: const Text('搜索弹窗'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('人物详情'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('ink-sheet-surface'))).width,
          390,
        );
        expect(
          tester.getSize(find.byKey(const Key('ink-sheet-surface'))).height,
          greaterThan(300),
        );
        await capture(
          tester,
          brightness == Brightness.light ? 'sheet-paper' : 'sheet-dark',
        );
        await tester.tap(find.byTooltip('关闭弹窗'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        await tester.tap(find.text('搜索弹窗'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭弹窗'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      }
      expect(tester.takeException(), isNull);
    },
  );
}
