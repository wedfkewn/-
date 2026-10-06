import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/map_repository.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/ui/illustrations.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

void main() {
  test('32 distinct bundled WebP illustrations fit the offline budget', () {
    expect(IllustrationCatalog.keys.toSet().length, 32);
    var size = 0;
    for (final key in IllustrationCatalog.keys) {
      final bytes = File(IllustrationCatalog.path(key)).readAsBytesSync();
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(bytes.sublist(8, 12)), 'WEBP');
      size += bytes.length;
    }
    expect(size, lessThanOrEqualTo(8 * 1024 * 1024));
  });
  test('every known terrain maps stably; rumors never reveal its type', () {
    for (final kind in PlaceKind.values) {
      final p = MapPlace('w:$kind', 0, '州', kind, 0, 0, '地形', 1, 0, []);
      final known = KnownPlace(p, '已知地点', true, 0, InformationChannel.witness);
      final art = IllustrationResolver.place(known);
      expect(art, startsWith('${kind.name}_'));
      expect(IllustrationCatalog.keys, contains(art));
      expect(IllustrationResolver.place(known), art);
      expect(
        IllustrationResolver.place(
          KnownPlace(p, '传闻', false, 0, InformationChannel.rumor),
        ),
        'wild_a',
      );
    }
    expect(IllustrationResolver.place(null), 'wild_a');
  });
  test(
    'AI prose cannot select hidden art; rendering does not consume random streams',
    () {
      final w = WorldGenerator.generate(
        seed: 'art-isolation',
        worldId: 'art',
        npcCount: 12,
        regionCount: 1,
        placesPerRegion: 10,
      );
      final before = jsonEncode(w.toJson());
      final map = MapRepository(w).query();
      const ai = Encounter(
        'ai',
        '天机秘境',
        '隐藏的渡劫台与宝剑',
        [
          EncounterOption('weapon', '获取', ['equipment']),
        ],
        'event',
        source: 'ai',
      );
      expect(
        IllustrationResolver.encounter(ai, map),
        IllustrationResolver.current(map),
      );
      for (var i = 0; i < 100; i++) {
        IllustrationResolver.current(map);
        IllustrationResolver.portrait('known-npc');
      }
      expect(jsonEncode(w.toJson()), before);
      expect(IllustrationResolver.encounter(ai, const MapView()), 'wild_a');
      const local = Encounter('local', '遗宝', '经过', [
        EncounterOption('treasure', '拾取', ['coins']),
      ], 'event');
      expect(IllustrationResolver.encounter(local, map), 'encounter_treasure');
    },
  );
  testWidgets('narrative expands, collapses and resets for a new event', (
    tester,
  ) async {
    final text = List.filled(20, '山河风雨，道途悠悠。').join();
    Widget app(String value) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 260, child: ExpandableNarrative(value)),
      ),
    );
    await tester.pumpWidget(app(text));
    expect(tester.widget<Text>(find.text(text)).maxLines, 4);
    await tester.tap(find.text('展开经过'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
    await tester.tap(find.text('收起经过'));
    await tester.pump();
    expect(tester.widget<Text>(find.text(text)).maxLines, 4);
    await tester.tap(find.text('展开经过'));
    await tester.pumpWidget(app('$text 新缘'));
    expect(tester.widget<Text>(find.text('$text 新缘')).maxLines, 4);
    await tester.pumpWidget(app('一段短文'));
    expect(find.byType(TextButton), findsNothing);
  });
  testWidgets('large text is expandable without folding risk or options', (
    tester,
  ) async {
    final text = List.filled(30, '山中遇见一位旅人。').join();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ListView(
              children: [
                ExpandableNarrative(text),
                const Text('危险 · 可能永久死亡'),
                FilledButton(onPressed: () {}, child: const Text('安全离开')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('展开经过'), findsOneWidget);
    expect(tester.widget<Text>(find.text('危险 · 可能永久死亡')).maxLines, isNull);
    expect(find.text('安全离开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('illustrations have bounded decoding and dark presentation', (
    tester,
  ) async {
    for (final mode in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: InkTheme.build(mode),
          home: const Scaffold(
            body: SizedBox(width: 320, child: InkIllustration(art: 'wild_a')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resize =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(resize.width, lessThanOrEqualTo(1024));
      expect(find.byType(ExcludeSemantics), findsWidgets);
      expect(
        find.byType(ColorFiltered),
        mode == Brightness.dark ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('missing image fallback leaves adjacent content usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const InkIllustration(art: 'wild_a'),
              const Text('完整行动说明'),
              FilledButton(onPressed: () {}, child: const Text('继续')),
            ],
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final fallback = image.errorBuilder!(
      tester.element(find.byType(Image)),
      StateError('missing'),
      StackTrace.current,
    );
    expect(fallback, isA<SizedBox>());
    expect(find.text('完整行动说明'), findsOneWidget);
    await tester.tap(find.text('继续'));
    expect(tester.takeException(), isNull);
  });
}
