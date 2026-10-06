import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/ai_service.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/content.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/domain/karma_repository.dart';
import 'package:xiuxian_app/main.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/details.dart';
import 'package:xiuxian_app/ui/ink_overlays.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

class AuditDb extends GameDatabase {
  AuditDb() : super(NativeDatabase.memory());
  bool rejectNew = false, rejectDeath = false;
  @override
  Future<void> save(
    World next, {
    World? previous,
    bool makeActive = false,
    bool failBeforeCommit = false,
  }) async {
    if (rejectNew || (rejectDeath && next.frozen)) {
      rejectDeath = false;
      throw StateError('injected save failure');
    }
    await super.save(
      next,
      previous: previous,
      makeActive: makeActive,
      failBeforeCommit: failBeforeCommit,
    );
  }
}

class AuditSecrets implements SecretStore {
  bool fail = false;
  @override
  Future<String?> read() async {
    if (fail) throw StateError('secure store unavailable');
    return 'fixture';
  }

  @override
  Future<void> write(String key) async {}
  @override
  Future<void> delete() async {}
}

class AuditClient extends AiClient {
  @override
  Future<AiReply> request(
    AiSettings settings,
    String key,
    List<Map<String, String>> messages,
    CancelToken token,
  ) async => throw const AiFailure('fixture local fallback');
}

void main() {
  test(
    'invalid action at lifespan boundary never kills or mutates the player',
    () {
      final w = WorldGenerator.generate(
        seed: 'expiry-invalid',
        worldId: 'expiry-invalid',
        npcCount: 8,
      );
      w.player.ageDays = Content.lifespans[0] * 360 - 1;
      final before = jsonEncode(w.toJson());
      expect(
        () => GameCommandService().execute(
          w,
          const GameCommand('trade', item: 'invalid'),
        ),
        throwsA(isA<RuleViolation>()),
      );
      expect(jsonEncode(w.toJson()), before);
      expect(
        GameCommandService().execute(w, const GameCommand('wait')).frozen,
        isTrue,
      );
    },
  );
  test(
    'failed final AI save recovers death once and refreshes archives before notifying UI',
    () async {
      final db = AuditDb();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'recover-death',
        worldId: 'recover-death',
        npcCount: 8,
      );
      w.player.ageDays = Content.lifespans[0] * 360 - 1;
      await db.save(w, makeActive: true);
      await db.saveSettings(
        const AiSettings(
          base: 'https://example.test/v1',
          model: 'fixture',
          enabled: true,
          consent: true,
        ).toJson(),
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(AuditSecrets()),
          aiClientProvider.overrideWithValue(AuditClient()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gameProvider.future);
      db.rejectDeath = true;
      final controller = container.read(gameProvider.notifier);
      await expectLater(
        controller.command(const GameCommand('explore')),
        throwsStateError,
      );
      expect((await db.load())!.pendingAi, isNotNull);
      await expectLater(
        controller.command(const GameCommand('wait')),
        throwsA(isA<RuleViolation>()),
      );
      final view = container.read(gameProvider).asData!.value;
      expect(view.readOnly, isTrue);
      expect(view.archives.single.id, w.id);
      final saved = (await db.load())!;
      expect(saved.pendingAi, isNull);
      expect(saved.events.values.where((e) => e.kind == 'death').length, 1);
    },
  );
  testWidgets(
    'save creation failure keeps the save landing page and original database',
    (tester) async {
      final db = AuditDb()..rejectNew = true;
      addTearDown(db.close);
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
      await tester.tap(find.text('开启新一世'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始修行'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('仙途存档'), findsOneWidget);
      expect(find.text('开启新一世'), findsOneWidget);
      expect(await tester.runAsync(db.load), isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'secure storage read failure shows retry and prevents settings overwrite',
    (tester) async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final secrets = AuditSecrets()..fail = true;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: InkTheme.build(Brightness.light),
            home: const AiSettingsPage(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      secrets.fail = false;
      await tester.tap(find.text('重试'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'landscape keyboard and large fonts do not overflow sheets or dialogs',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 320);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = WorldGenerator.generate(
        seed: 'compact',
        worldId: 'compact',
        npcCount: 8,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: InkTheme.build(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Row(
                children: [
                  TextButton(
                    onPressed: () => showNodeDetails(
                      ctx,
                      KarmaRepository(w).node(w.playerId)!,
                    ),
                    child: const Text('详情'),
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: ctx,
                      builder: (c) => const InkDialog(
                        title: Text('需要确认的操作'),
                        content: SizedBox(height: 360, child: Text('长内容')),
                        actions: [Text('确认')],
                      ),
                    ),
                    child: const Text('确认弹窗'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      for (final label in ['详情', '确认弹窗']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Navigator.of(
          tester.element(
            find.byType(Dialog).evaluate().isNotEmpty
                ? find.byType(Dialog).first
                : find.byType(BottomSheet).first,
          ),
        ).pop();
        await tester.pumpAndSettle();
      }
    },
  );
}
