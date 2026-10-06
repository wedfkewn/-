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
import 'package:xiuxian_app/ui/creation_page.dart';
import 'package:xiuxian_app/ui/battle_stage.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';
import 'package:xiuxian_app/main.dart';

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
  Future<void> settleDb(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String file) async {
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(const Key('capture')))
          .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File('build/qa/$file.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'equipment details compare and confirm the precise instance sale',
    (tester) async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'gear-ui',
        worldId: 'gear-ui',
        npcCount: 12,
        regionCount: 1,
        placesPerRegion: 10,
      );
      const first = Equipment('gear-a', '青锋剑', 'weapon', base: 12, version: 1);
      const second = Equipment(
        'gear-b',
        '青锋剑',
        'weapon',
        base: 18,
        quality: 2,
        bonuses: {'锋锐': 4},
        version: 1,
      );
      w.equipment[first.id] = first;
      w.equipment[second.id] = second;
      w.weaponId = first.id;
      w.weapon = first.name;
      await tester.runAsync(() => db.save(w, makeActive: true));
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(gameProvider.future));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const XiuxianApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续这一世'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 10 && find.text('行囊 · 功法').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('行囊 · 功法').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('青锋剑 · 炼气 · 上品'));
      await tester.pumpAndSettle();
      expect(find.textContaining('普通出手 +10'), findsOneWidget);
      await tester.tap(find.text('出售 · 30灵石'));
      await tester.pumpAndSettle();
      expect(find.text('确认出售'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(FilledButton, '确认出售'));
      await settleDb(tester);
      final saved = await tester.runAsync(db.load);
      expect(saved!.equipment.containsKey(second.id), isFalse);
      expect(saved.equipment.containsKey(first.id), isTrue);
      expect(saved.player.coins, w.player.coins + 30);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'creation allocation persists, seed change resets and large text scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      await tester.runAsync(() async {
        await db.save(
          WorldGenerator.generate(
              seed: 'old',
              worldId: 'old',
              npcCount: 12,
              regionCount: 1,
              placesPerRegion: 10,
            )
            ..frozen = true
            ..assessment = {'score': 350},
          makeActive: true,
        );
        await db.creationDraft(seed: 'new-attributes');
      });
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      Widget app({double scale = 1}) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: InkTheme.build(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: const RepaintBoundary(
              key: Key('capture'),
              child: CreationPage(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await settleDb(tester);
      expect(find.text('天资一 · 已选择'), findsOneWidget);
      await capture(tester, 'birth-candidates');
      await tester.scrollUntilVisible(
        find.byTooltip('增加根骨'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('增加根骨'));
        await tester.pump();
      }
      await settleDb(tester);
      expect(
        (await tester.runAsync(() => db.appRecord('birthChoice')))!['points'],
        [0, 4, 0, 0],
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(scale: 1.5));
      await settleDb(tester);
      await tester.scrollUntilVisible(
        find.text('开始修行'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始修行'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('world-seed-input')),
        'changed-seed',
      );
      await tester.tap(find.text('应用种子与资质'));
      await settleDb(tester);
      expect(
        (await tester.runAsync(() => db.creationDraft()))!.seed,
        'changed-seed',
      );
      expect(
        (await tester.runAsync(() => db.appRecord('birthChoice')))!['points'],
        [0, 0, 0, 0],
      );
    },
  );
  testWidgets('ink combat stage renders light and dark styles', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: InkTheme.build(brightness),
          home: RepaintBoundary(
            key: const Key('capture'),
            child: Scaffold(
              appBar: AppBar(title: const Text('交锋')),
              body: PaperSurface(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: BattleStage(
                    view: const GameView(
                      battleName: '黑风谷修士',
                      hp: 88,
                      maxHp: 100,
                      battleHp: 76,
                      battleMaxHp: 100,
                      battleQi: 8,
                      maxQi: 13,
                      style: '御剑诀',
                      omen: '凝气蓄力，下一合将施展猛击',
                      combatFeedback: CombatFeedback(
                        actionId: 'preview',
                        kind: '御剑诀',
                        damage: 24,
                        received: 12,
                        healing: 0,
                        absorbed: 0,
                      ),
                    ),
                    busy: false,
                    onCommand: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'battle-${brightness.name}');
      expect(tester.takeException(), isNull);
    }
  });
}
