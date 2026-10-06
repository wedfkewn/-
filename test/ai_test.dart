import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/ai_service.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/domain/engine.dart';
import 'package:xiuxian_app/domain/models.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';
import 'package:xiuxian_app/main.dart';

class MemorySecrets implements SecretStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String key) async {
    value = key;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FailingSettingsDb extends GameDatabase {
  FailingSettingsDb() : super(NativeDatabase.memory());
  bool fail = false;
  int writes = 0;
  @override
  Future<void> saveSettings(Map<String, dynamic> values) async {
    if (fail && ++writes == 2) throw StateError('injected settings failure');
    await super.saveSettings(values);
  }
}

class Adapter implements HttpClientAdapter {
  Adapter(this.body, {this.status = 200, this.error});
  final DioExceptionType? error;
  final dynamic body;
  final int status;
  RequestOptions? options;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    if (error != null) {
      throw DioException(requestOptions: options, type: error!);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FixtureClient extends AiClient {
  int calls = 0;
  bool wait = false;
  bool malformed = false;
  Completer<void>? started;
  @override
  Future<AiReply> request(
    AiSettings settings,
    String key,
    List<Map<String, String>> messages,
    CancelToken token,
  ) async {
    calls++;
    started?.complete();
    if (wait) {
      await token.whenCancel;
      throw const AiFailure('请求已取消');
    }
    if (malformed) return const AiReply('not json', input: 10, output: 2);
    final context = jsonDecode(messages.last['content']!);
    if (context['actions'] != null) {
      return AiReply(
        jsonEncode({
          'action': context['actions'][0]['action'],
          'text': '依自身所知，继续修行与行旅。',
        }),
        input: 30,
        output: 15,
      );
    }
    if (context['input'] != null) {
      return const AiReply(
        '{"reply":"修行须循本心。","news":[]}',
        input: 20,
        output: 10,
      );
    }
    return const AiReply(
      '{"title":"灵草有缘","text":"在山路边，你发现一片灵草，可采集或离开。","options":[{"label":"采集","effect":"herbs"},{"label":"离开","effect":"leave"}]}',
      input: 30,
      output: 15,
    );
  }
}

const settings = AiSettings(
  base: 'https://example.test/v1',
  model: 'player-model',
  enabled: true,
  consent: true,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'model discovery uses GET without a selected model and deduplicates IDs',
    () async {
      final adapter = Adapter({
        'data': [
          {'id': 'z-model'},
          {'id': 'a-model'},
          {'id': 'z-model'},
        ],
      });
      final dio = Dio()..httpClientAdapter = adapter;
      expect(
        await AiClient(dio: dio).listModels(
          const AiSettings(base: 'https://example.test/v1/'),
          'fake-key',
          CancelToken(),
        ),
        ['a-model', 'z-model'],
      );
      expect(adapter.options!.method, 'GET');
      expect(adapter.options!.uri.toString(), 'https://example.test/v1/models');
      expect(adapter.options!.headers['Authorization'], 'Bearer fake-key');
      expect(adapter.options!.followRedirects, isFalse);
      expect(adapter.options!.data, isNull);
    },
  );
  test(
    'model discovery rejects malformed lists and classifies unsupported/auth/timeout',
    () async {
      for (final body in [
        {'data': []},
        {
          'data': [
            {'id': 3},
          ],
        },
        {
          'data': [
            {'id': 'bad\nname'},
          ],
        },
        {'choices': []},
      ]) {
        final dio = Dio()..httpClientAdapter = Adapter(body);
        await expectLater(
          AiClient(dio: dio).listModels(settings, 'fake', CancelToken()),
          throwsA(isA<AiFailure>()),
        );
      }
      for (final code in [401, 404, 429]) {
        final dio = Dio()..httpClientAdapter = Adapter({}, status: code);
        await expectLater(
          AiClient(dio: dio).listModels(settings, 'fake', CancelToken()),
          throwsA(
            isA<AiFailure>().having(
              (e) => e.message,
              'safe classification',
              contains(
                code == 401
                    ? '配置错误'
                    : code == 404
                    ? '不支持'
                    : '限流',
              ),
            ),
          ),
        );
      }
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          {},
          error: DioExceptionType.receiveTimeout,
        );
      await expectLater(
        AiClient(dio: dio).listModels(settings, 'fake', CancelToken()),
        throwsA(isA<AiFailure>().having((e) => e.message, 'timeout', '请求超时')),
      );
      final cancelled = CancelToken()..cancel();
      await expectLater(
        AiClient().listModels(settings, 'fake', cancelled),
        throwsA(isA<AiFailure>().having((e) => e.message, 'cancel', '请求已取消')),
      );
    },
  );
  test(
    'discovery reuses a key only at saved URL and does not save settings or generation usage',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final secrets = MemorySecrets()..value = 'saved-secret';
      await db.saveSettings(settings.toJson());
      final adapter = Adapter({
        'data': [
          {'id': 'found-model'},
        ],
      });
      final service = AiContentService(
        db,
        AiClient(dio: Dio()..httpClientAdapter = adapter),
        secrets,
      );
      expect(await service.detectModels(AiSettings(base: settings.base), ''), [
        'found-model',
      ]);
      expect(adapter.options!.headers['Authorization'], 'Bearer saved-secret');
      adapter.options = null;
      await expectLater(
        service.detectModels(
          const AiSettings(base: 'https://other.test/v1'),
          '',
        ),
        throwsA(isA<AiFailure>()),
      );
      expect(adapter.options, isNull);
      expect(
        await service.detectModels(
          const AiSettings(base: 'https://other.test/v1'),
          'new-key',
        ),
        ['found-model'],
      );
      expect(adapter.options!.headers['Authorization'], 'Bearer new-key');
      expect(secrets.value, 'saved-secret');
      expect(await db.settings(), settings.toJson());
      expect(await db.usage(), isEmpty);
    },
  );
  testWidgets(
    'URL and key can detect and select a model before settings are saved',
    (tester) async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final adapter = Adapter({
        'data': [
          {'id': 'dialogue-model'},
          {'id': 'other-model'},
        ],
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(MemorySecrets()),
            aiClientProvider.overrideWithValue(
              AiClient(dio: Dio()..httpClientAdapter = adapter),
            ),
          ],
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
      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(field('API 基础地址'), settings.base);
      await tester.enterText(field('API 密钥'), 'temporary-secret');
      await tester.runAsync(() async {
        await tester.tap(find.text('检测模型'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(find.text('选择模型 · 2 个'), findsOneWidget);
      await tester.enterText(field('搜索模型'), 'dialogue');
      await tester.pumpAndSettle();
      expect(find.text('other-model'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('dialogue-model'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('模型名称')).controller!.text,
        'dialogue-model',
      );
      expect(adapter.options!.method, 'GET');
      expect(await tester.runAsync(db.settings), isEmpty);
      expect(await tester.runAsync(db.usage), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    for (final e in {
      'MaShan': 'MaShanZheng-Regular.ttf',
      'WenKai': 'LXGWWenKai-Regular.ttf',
    }.entries) {
      await (FontLoader(e.key)..addFont(
            File(
              'assets/fonts/${e.value}',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'HTTPS API adapter sends compatible payload, parses usage and disables redirects',
    () async {
      final adapter = Adapter({
        'choices': [
          {
            'message': {'content': '{"ok":true}'},
          },
        ],
        'usage': {'prompt_tokens': 12, 'completion_tokens': 5},
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final reply = await AiClient(dio: dio).request(
        settings,
        'test-only',
        const [
          {'role': 'user', 'content': 'hello'},
        ],
        CancelToken(),
      );
      expect(reply.input, 12);
      expect(reply.output, 5);
      expect(
        adapter.options!.uri.toString(),
        'https://example.test/v1/chat/completions',
      );
      expect(adapter.options!.followRedirects, isFalse);
      expect(adapter.options!.data['stream'], isFalse);
      for (final base in [
        'http://example.test/v1',
        'https://user:pass@example.test/v1',
        'https://example.test/v1?key=secret',
      ]) {
        expect(
          () => AiSettings(base: base, model: 'm').endpoint,
          throwsA(isA<AiFailure>()),
        );
      }
    },
  );
  test(
    'adapter classifies configuration, throttling, refusal, malformed and missing usage',
    () async {
      for (final code in [401, 404, 429, 500]) {
        final dio = Dio()..httpClientAdapter = Adapter({}, status: code);
        await expectLater(
          AiClient(dio: dio).request(settings, 'fake', [], CancelToken()),
          throwsA(
            isA<AiFailure>().having(
              (e) => e.message,
              'safe error',
              code == 429
                  ? contains('限流')
                  : code == 500
                  ? contains('不可用')
                  : contains('配置错误'),
            ),
          ),
        );
      }
      for (final body in [
        {},
        {
          'choices': [
            {
              'message': {'refusal': 'refused', 'content': null},
            },
          ],
        },
      ]) {
        final dio = Dio()..httpClientAdapter = Adapter(body);
        await expectLater(
          AiClient(dio: dio).request(settings, 'fake', [], CancelToken()),
          throwsA(isA<AiFailure>()),
        );
      }
      final dio = Dio()
        ..httpClientAdapter = Adapter({
          'choices': [
            {
              'message': {'content': 'hello'},
            },
          ],
        });
      expect(
        (await AiClient(
          dio: dio,
        ).request(settings, 'fake', [], CancelToken())).input,
        isNull,
      );
    },
  );
  test(
    'transport timeout is classified without leaking network details',
    () async {
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          {},
          error: DioExceptionType.receiveTimeout,
        );
      await expectLater(
        AiClient(dio: dio).request(settings, 'fake', [], CancelToken()),
        throwsA(
          isA<AiFailure>().having((e) => e.message, 'timeout', contains('超时')),
        ),
      );
    },
  );
  test(
    'key is outside settings and world snapshots; host change needs explicit confirmation',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final secrets = MemorySecrets();
      final service = AiContentService(db, FixtureClient(), secrets);
      await service.saveSettings(settings, 'local-secret');
      expect(jsonEncode(await db.settings()), isNot(contains('local-secret')));
      final other = AiSettings(
        base: 'https://other.test/v1',
        model: 'm',
        enabled: true,
        consent: true,
      );
      await expectLater(
        service.saveSettings(other, 'replacement'),
        throwsA(isA<AiFailure>()),
      );
      expect(secrets.value, 'local-secret');
      await service.saveSettings(other, 'replacement', hostConfirmed: true);
      expect(secrets.value, 'replacement');
      await db.logUsage({'input': null, 'output': null});
      await db.logUsage({'input': 12, 'output': 5});
      expect(await db.usageTotals(), {
        'requests': 2,
        'input': 12,
        'output': 5,
        'unknown': 1,
      });
    },
  );
  test(
    'invalid proposal fallback spends action once and never retries API',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = FixtureClient()..malformed = true;
      final secrets = MemorySecrets()..value = 'fake';
      await db.saveSettings(settings.toJson());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiClientProvider.overrideWithValue(client),
          secretStoreProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gameProvider.future);
      await container.read(gameProvider.notifier).create('测试', 'ai');
      await container
          .read(gameProvider.notifier)
          .command(const GameCommand('explore'));
      final w = (await db.load())!;
      expect(w.day, 3);
      expect(w.encounter!.source, 'local');
      expect(w.pendingAi, isNull);
      expect(client.calls, 1);
      expect((await db.usage()).length, 1);
    },
  );
  test(
    'cancellation blocks concurrent actions and restores local result once',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = FixtureClient()
        ..wait = true
        ..started = Completer<void>();
      final secrets = MemorySecrets()..value = 'fake';
      await db.saveSettings(settings.toJson());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiClientProvider.overrideWithValue(client),
          secretStoreProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gameProvider.future);
      final controller = container.read(gameProvider.notifier);
      await controller.create('测试', 'ai');
      final action = controller.command(const GameCommand('explore'));
      await client.started!.future;
      expect((await db.load())!.day, 0);
      expect((await db.load())!.pendingAi, isNotNull);
      await expectLater(
        controller.command(const GameCommand('wait')),
        throwsA(isA<RuleViolation>()),
      );
      controller.cancelAi();
      await action;
      expect((await db.load())!.day, 3);
      expect(client.calls, 1);
    },
  );
  test(
    'reopen reserved request uses local fallback with zero API calls',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = FixtureClient();
      final w = WorldGenerator.generate(
        seed: 'resume',
        worldId: 'resume',
        npcCount: 5,
      );
      w.pendingAi = {'kind': 'explore', 'id': 'resume:action:0'};
      await db.save(w);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      final view = await container.read(gameProvider.future);
      expect(view.day, 3);
      expect(view.encounter, isNotNull);
      expect(client.calls, 0);
      expect((await db.load())!.pendingAi, isNull);
    },
  );
  test(
    'accepted AI result survives restore and can replay without another request',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = FixtureClient();
      final secrets = MemorySecrets()..value = 'fake';
      await db.saveSettings(settings.toJson());
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiClientProvider.overrideWithValue(client),
          secretStoreProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gameProvider.future);
      await container.read(gameProvider.notifier).create('测试', 'ai');
      final before = (await db.load())!;
      await container
          .read(gameProvider.notifier)
          .command(const GameCommand('explore'));
      final next = (await db.load())!;
      final record = next.generations.single;
      final replay = GameCommandService().execute(
        before,
        GameCommand(
          'explore',
          proposal: Map<String, dynamic>.from(record['proposal']),
          generation: record,
          actionId: record['actionId'],
        ),
      );
      expect(jsonEncode(replay.toJson()), jsonEncode(next.toJson()));
      expect(client.calls, 1);
      expect(
        () => GameCommandService().execute(
          next,
          GameCommand('explore', actionId: record['actionId']),
        ),
        throwsA(isA<RuleViolation>()),
      );
    },
  );
  testWidgets(
    'settings and encounter layouts show consent, cost and missing resources at large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final secrets = MemorySecrets();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(secrets),
          ],
          child: MaterialApp(
            theme: InkTheme.build(Brightness.light),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const AiSettingsPage(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('天机设置'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('AI 世界事件'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('会消耗更多 token'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      var w = WorldGenerator.generate(
        seed: 'ui-ai',
        worldId: 'ui-ai',
        npcCount: 5,
      );
      w.player.coins = 0;
      w = GameCommandService().execute(
        w,
        GameCommand(
          'explore',
          proposal: {
            'title': '残剑',
            'text': '修复需消耗灵石。',
            'options': [
              {'label': '修复', 'effect': 'weapon'},
              {'label': '离开', 'effect': 'leave'},
            ],
          },
        ),
      );
      await db.save(w);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: InkTheme.build(Brightness.light),
            home: const EncounterPage(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('灵石不足'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '修复'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native AI pages, free dialogue and battle render with real fonts',
    (tester) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final secrets = MemorySecrets()..value = 'fixture-only';
      final client = FixtureClient();
      await db.saveSettings(settings.toJson());
      var w = WorldGenerator.generate(
        seed: 'ai-ui',
        worldId: 'ai-ui',
        npcCount: 20,
      );
      final n = w.entities['ai-ui:npc:0']!;
      n.location = w.player.location;
      n.lastActed = 10000;
      w.discover(w.playerId, n.id, InformationChannel.witness);
      await db.save(w);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
          aiClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(gameProvider.future));
      final key = GlobalKey();
      Future<void> show(Widget page) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: InkTheme.build(Brightness.light),
                home: page,
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/images/rice-paper.png'),
            tester.element(find.byType(PaperSurface).first),
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/qa').create(recursive: true);
          await File(
            'build/qa/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }

      await show(const AiSettingsPage());
      await capture('ai-settings');
      await show(DialoguePage(npc: n.id, name: n.name));
      await tester.enterText(find.byType(TextField), '此地有何见闻？');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '交谈 · 1日'));
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (container.read(gameProvider).asData?.value.day == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('修行须循本心'), findsOneWidget);
      expect(client.calls, 1);
      await capture('ai-dialogue');
      await tester.runAsync(
        () => container
            .read(gameProvider.notifier)
            .command(const GameCommand('explore')),
      );
      await show(const EncounterPage());
      await capture('ai-encounter');
      await tester.runAsync(
        () => container
            .read(gameProvider.notifier)
            .command(const GameCommand('chooseEncounter', item: 'leave')),
      );
      await tester.runAsync(
        () => container
            .read(gameProvider.notifier)
            .command(GameCommand('startBattle', target: n.id)),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const XiuxianApp()),
        ),
      );
      await tester.runAsync(() async {
        for (final asset in [
          'rice-paper.png',
          'cultivation-landscape.png',
          'ink-action.png',
          'crimson-mark.png',
          'navigation-ink.png',
        ]) {
          await precacheImage(
            AssetImage('assets/images/$asset'),
            tester.element(find.byType(PaperSurface).first),
          );
        }
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续这一世'));
      await tester.pumpAndSettle();
      expect(find.textContaining('战斗灵力'), findsOneWidget);
      await capture('battle-growth');
      w = (await tester.runAsync(() async => (await db.load())!))!;
      expect(w.dialogue.single.reply, '修行须循本心。');
      expect(w.battleTarget, n.id);
    },
  );

  test(
    'world AI calls at most once per crossed interval and never in background',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = FixtureClient();
      final secrets = MemorySecrets()..value = 'fake';
      await db.saveSettings({...settings.toJson(), 'world': true});
      var w = WorldGenerator.generate(
        seed: 'world-ai',
        worldId: 'world-ai',
        npcCount: 120,
      );
      for (final n in w.entities.values.where(
        (n) => n.type == KarmaNodeType.npc,
      )) {
        w.discover(w.playerId, n.id, InformationChannel.witness);
      }
      await db.save(w);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiClientProvider.overrideWithValue(client),
          secretStoreProvider.overrideWithValue(secrets),
        ],
      );
      addTearDown(container.dispose);
      await container.read(gameProvider.future);
      final controller = container.read(gameProvider.notifier);
      await controller.command(const GameCommand('wait'));
      expect(client.calls, 1);
      await expectLater(
        controller.command(const GameCommand('equip', item: 'missing')),
        throwsA(isA<RuleViolation>()),
      );
      expect(client.calls, 1);
      await controller.command(const GameCommand('setStyle', item: '长春诀'));
      expect(client.calls, 1);
      container.read(aiServiceProvider).setForeground(false);
      await controller.command(const GameCommand('wait'));
      expect(client.calls, 1);
      w = (await db.load())!;
      expect(w.generations.where((e) => e['kind'] == 'world').length, 1);
    },
  );

  test(
    'transaction rollback and stale revisions reject generated content atomically',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final w = WorldGenerator.generate(
        seed: 'atomic-ai',
        worldId: 'atomic-ai',
        npcCount: 5,
      );
      await db.save(w);
      final generated = GameCommandService().execute(
        w,
        GameCommand(
          'explore',
          proposal: {
            'title': '灵草',
            'text': '山间灵草可采集。',
            'options': [
              {'label': '采集', 'effect': 'herbs'},
              {'label': '离开', 'effect': 'leave'},
            ],
          },
          generation: {'model': 'fixture', 'source': 'ai', 'promptVersion': 1},
        ),
      );
      await expectLater(
        db.save(generated, previous: w, failBeforeCommit: true),
        throwsStateError,
      );
      expect((await db.load())!.generations, isEmpty);
      expect((await db.load())!.encounter, isNull);
      final advanced = GameCommandService().execute(
        w,
        const GameCommand('wait'),
      );
      await db.save(advanced, previous: w);
      await expectLater(db.save(generated, previous: w), throwsStateError);
      expect((await db.load())!.day, 30);
    },
  );
  test(
    'interrupted host change stays disabled and never sends replacement key to old host',
    () async {
      final db = FailingSettingsDb();
      addTearDown(db.close);
      final secrets = MemorySecrets();
      final client = FixtureClient();
      final service = AiContentService(db, client, secrets);
      await service.saveSettings(settings, 'original');
      db.fail = true;
      const next = AiSettings(
        base: 'https://replacement.test/v1',
        model: 'other',
        enabled: true,
        consent: true,
      );
      await expectLater(
        service.saveSettings(next, 'replacement', hostConfirmed: true),
        throwsStateError,
      );
      expect((await service.settings()).enabled, isFalse);
      expect((await service.settings()).base, next.base);
      final w = WorldGenerator.generate(
        seed: 'host',
        worldId: 'host',
        npcCount: 5,
      );
      await expectLater(
        service.generate(w, 'explore', settings),
        throwsA(isA<AiFailure>()),
      );
      expect(client.calls, 0);
    },
  );
}
