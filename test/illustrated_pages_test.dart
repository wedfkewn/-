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
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/illustrations.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

void main() {
  setUpAll(() async {
    for (final e in {
      'MaShan': 'MaShanZheng-Regular.ttf',
      'WenKai': 'LXGWWenKai-Regular.ttf',
    }.entries) {
      await (FontLoader(e.key)..addFont(
            File(
              'assets/fonts/${e.value}',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump();
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('art-capture')),
          )
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File(
        'build/qa/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'encounter art keeps costs risk and safe exit visible in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'illustrated-encounter',
        worldId: 'art-encounter',
        npcCount: 12,
        regionCount: 1,
        placesPerRegion: 10,
      );
      w.encounter = Encounter(
        'art-encounter:pending',
        '商旅求援',
        List.filled(12, '山道远处传来铃声，一队商旅正等待护送。').join(),
        const [
          EncounterOption('escort', '护送商旅', ['battle'], cost: 3),
          EncounterOption('leave', '安全离开', []),
        ],
        'known-source',
      );
      await tester.runAsync(() => db.save(w, makeActive: true));
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(gameProvider.future));
      for (final mode in Brightness.values) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: InkTheme.build(mode),
              home: const RepaintBoundary(
                key: Key('art-capture'),
                child: EncounterPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<InkIllustration>(find.byType(InkIllustration)).art,
          'encounter_escort',
        );
        expect(find.text('展开经过'), findsOneWidget);
        expect(find.text('1日 · 3灵石 · 危险 · 可能永久死亡'), findsOneWidget);
        expect(find.text('安全离开'), findsOneWidget);
        await capture(tester, 'illustrated-encounter-${mode.name}');
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'dialogue collapses old turns while preserving all stored history',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'illustrated-dialogue',
        worldId: 'art-dialogue',
        npcCount: 12,
        regionCount: 1,
        placesPerRegion: 10,
      );
      final npc = w.entities.values.firstWhere(
        (e) => e.type == KarmaNodeType.npc,
      );
      npc.location = w.player.location;
      w.discover(w.playerId, npc.id, InformationChannel.witness);
      for (var i = 0; i < 6; i++) {
        w.dialogue.add(
          DialogueTurn(npc.id, '第${i + 1}轮问候', '道友，修行当循序渐进，第${i + 1}轮言论。', i),
        );
      }
      await tester.runAsync(() => db.save(w, makeActive: true));
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(gameProvider.future));
      Widget app(double scale) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: InkTheme.build(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(
              key: const Key('art-capture'),
              child: DialoguePage(npc: npc.id, name: npc.name),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(1));
      await tester.pumpAndSettle();
      expect(find.text('此前交谈 · 4轮'), findsOneWidget);
      expect(find.text('你：第1轮问候'), findsNothing);
      expect(find.text('你：第5轮问候'), findsOneWidget);
      expect(find.text('你：第6轮问候'), findsOneWidget);
      await capture(tester, 'illustrated-dialogue');
      await tester.tap(find.text('此前交谈 · 4轮'));
      await tester.pumpAndSettle();
      expect(find.text('你：第1轮问候'), findsOneWidget);
      await tester.pumpWidget(app(1.5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('交谈 · 1日'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '交谈 · 1日'))
            .onPressed,
        isNotNull,
      );
      expect((await tester.runAsync(db.load))!.dialogue.length, 6);
      expect(tester.takeException(), isNull);
    },
  );
}
