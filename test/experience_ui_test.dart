import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/ai_service.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/main.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/commission_page.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';
import 'package:xiuxian_app/ui/location_activities.dart';

class _Secrets implements SecretStore {
  @override
  Future<String?> read() async => 'fixture';
  @override
  Future<void> delete() async {}
  @override
  Future<void> write(String value) async {}
}

const _capture = Key('experience-capture');

void main() {
  setUpAll(() async {
    for (final font in {
      'MaShan': 'MaShanZheng-Regular.ttf',
      'WenKai': 'LXGWWenKai-Regular.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(
            File(
              'assets/fonts/${font.value}',
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
    Widget page, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    World? world,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final db = GameDatabase.memory();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(_Secrets()),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await db.save(
        world ??
            WorldGenerator.generate(
              seed: 'experience',
              worldId: 'experience',
              npcCount: 8,
            ),
        makeActive: true,
      );
      await db.saveSettings(
        const AiSettings(
          base: 'https://example.test/v1',
          model: 'fixture',
        ).toJson(),
      );
      await container.read(gameProvider.future);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: InkTheme.build(brightness),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(
              ctx,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(key: _capture, child: page),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final picture = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(_capture))
          .toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File(
        'build/qa/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  Future<void> scroll(WidgetTester tester, Finder target) async {
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

  testWidgets('commission can be accepted, completed, traced and paid once', (
    tester,
  ) async {
    final container = await show(tester, const CommissionPage());
    await capture(tester, 'commission-board-light');
    await scroll(tester, find.byKey(const Key('accept-commission-foundation')));
    await tester.tap(find.byKey(const Key('accept-commission-foundation')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    final controller = container.read(gameProvider.notifier);
    expect(
      container.read(gameProvider).requireValue.commission.active!.kind,
      'foundation',
    );
    await tester.runAsync(() async {
      await controller.command(const GameCommand('stabilize'));
      await controller.command(const GameCommand('practice'));
    });
    await tester.pumpAndSettle();
    expect(
      container.read(gameProvider).requireValue.commission.canClaim,
      isTrue,
    );
    final coins = container.read(gameProvider).requireValue.coins;
    await tester.drag(find.byType(ListView).first, const Offset(0, 2500));
    await tester.pumpAndSettle();
    await scroll(tester, find.text('交付并领取报酬'));
    await capture(tester, 'commission-ready');
    await tester.tap(find.text('交付并领取报酬'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(gameProvider).requireValue.coins,
      coins + Content.commissions['foundation']!.coins,
    );
    expect(container.read(gameProvider).requireValue.commission.active, isNull);
    expect(
      controller.repository!.recent(limit: 20).any((e) => e.title == '交付固本培元'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'commission board supports dark theme and large text without overflow',
    (tester) async {
      await show(
        tester,
        const CommissionPage(),
        brightness: Brightness.dark,
        scale: 1.6,
      );
      await capture(tester, 'commission-board-dark-large');
      await scroll(tester, find.text('查看山河，安排历练'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'world activity cards use filtered scenery and open actual facilities',
    (tester) async {
      final container = await show(tester, const XiuxianApp());
      await tester.tap(find.text('继续这一世'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('世界').last);
      await tester.pumpAndSettle();
      await scroll(tester, find.byType(LocationActivities));
      await capture(tester, 'world-activity-cards');
      await scroll(tester, find.text('山河委托'));
      await tester.tap(find.text('山河委托'));
      await tester.pumpAndSettle();
      expect(find.byType(CommissionPage), findsOneWidget);
      expect(container.read(gameProvider).requireValue.day, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrative preferences persist without generation or key changes',
    (tester) async {
      final container = await show(tester, const AiSettingsPage());
      await scroll(tester, find.text('叙事风格'));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('诗意山水').last);
      await tester.pumpAndSettle();
      await capture(tester, 'ai-narrative-preferences');
      await scroll(tester, find.text('简短叙事'));
      await tester.tap(find.text('简短叙事'));
      await scroll(tester, find.text('保存设置'));
      await tester.tap(find.text('保存设置'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      final db = container.read(databaseProvider);
      final settings = await tester.runAsync(db.settings);
      expect(settings!['narrativeStyle'], '诗意山水');
      expect(settings['detail'], 'standard');
      expect(await tester.runAsync(db.usage), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large activity cards block advancement during an encounter', (
    tester,
  ) async {
    final world = GameCommandService().execute(
      WorldGenerator.generate(
        seed: 'activity-lock',
        worldId: 'activity-lock',
        npcCount: 8,
      ),
      const GameCommand('explore'),
    );
    final actions = <String>[];
    await show(
      tester,
      Consumer(
        builder: (context, ref, child) => Scaffold(
          body: PaperSurface(
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                LocationActivities(
                  view: ref.watch(gameProvider).requireValue,
                  busy: false,
                  onAction: actions.add,
                ),
              ],
            ),
          ),
        ),
      ),
      brightness: Brightness.dark,
      scale: 1.6,
      world: world,
    );
    await capture(tester, 'activity-cards-dark-large');
    await tester.tap(find.text('探索 · 3日'));
    expect(actions, isEmpty);
    await scroll(tester, find.text('山河委托'));
    await tester.tap(find.text('山河委托'));
    expect(actions, ['commission']);
    await scroll(tester, find.text('修行准备'));
    await tester.tap(find.text('修行准备'));
    expect(actions, ['commission']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent dialogue is brief but can reveal the complete saying', (
    tester,
  ) async {
    final world = WorldGenerator.generate(
      seed: 'brief-dialogue',
      worldId: 'brief-dialogue',
      npcCount: 8,
    );
    final npc = world.entities.values.firstWhere(
      (e) => e.type == KarmaNodeType.npc,
    );
    npc.location = world.player.location;
    world.discover(world.playerId, npc.id, InformationChannel.witness);
    final reply = List.filled(14, '道友，山河行旅需稳固根基，未知传闻还当亲自查证。').join();
    world.dialogue.add(DialogueTurn(npc.id, '请指点行旅', reply, world.day));
    final container = await show(
      tester,
      DialoguePage(npc: npc.id, name: npc.name),
      world: world,
    );
    final saying = find.text('${npc.name}：$reply');
    expect(tester.widget<Text>(saying).maxLines, 3);
    await capture(tester, 'dialogue-recent-brief');
    await scroll(tester, find.text('展开言论'));
    await tester.tap(find.text('展开言论'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(saying).maxLines, isNull);
    final restored = await tester.runAsync(
      container.read(databaseProvider).load,
    );
    expect(restored!.dialogue.single.reply, reply);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local short encounter shows its illustration and all costs', (
    tester,
  ) async {
    final original = WorldGenerator.generate(
      seed: 'short-encounter',
      worldId: 'short-encounter',
      npcCount: 4,
    );
    World? world;
    for (var seed = 1; seed < 200; seed++) {
      final candidate = original.copy()..adventureRandom.state = seed;
      final discovered = GameCommandService().execute(
        candidate,
        const GameCommand('explore'),
      );
      if (discovered.encounter!.title == '雨亭借宿') {
        world = discovered;
        break;
      }
    }
    expect(world, isNotNull);
    await show(tester, const EncounterPage(), world: world!);
    expect(find.text('雨亭借宿'), findsOneWidget);
    expect(find.text('1日 · 4灵石 · 安全'), findsOneWidget);
    expect(find.text('1日 · 8灵石 · 安全'), findsOneWidget);
    expect(find.text('0日 · 安全'), findsOneWidget);
    await capture(tester, 'local-rain-encounter');
    expect(tester.takeException(), isNull);
  });
}
