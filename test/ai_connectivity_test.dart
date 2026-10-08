import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/ai_service.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

class _Secrets implements SecretStore {
  String? value = 'fixture-key';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

class _WaitingSecrets extends _Secrets {
  final started = Completer<void>();
  final result = Completer<String?>();
  @override
  Future<String?> read() async {
    started.complete();
    return result.future;
  }
}

class _Adapter implements HttpClientAdapter {
  RequestOptions? request;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'content': '连接成功'},
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _LateClient extends AiClient {
  final started = Completer<void>();
  final reply = Completer<AiReply>();
  CancelToken? activeToken;
  @override
  Future<AiReply> request(
    AiSettings settings,
    String key,
    List<Map<String, String>> messages,
    CancelToken token,
  ) async {
    activeToken = token;
    started.complete();
    return reply.future;
  }
}

const _saved = AiSettings(base: 'https://example.test/v1', model: 'old-model');

void main() {
  for (final detection in [false, true]) {
    test(
      'cancel during key retrieval prevents ${detection ? 'model' : 'chat'} request',
      () async {
        final db = GameDatabase.memory();
        addTearDown(db.close);
        await db.saveSettings(_saved.toJson());
        final secrets = _WaitingSecrets();
        final adapter = _Adapter();
        final service = AiContentService(
          db,
          AiClient(dio: Dio()..httpClientAdapter = adapter),
          secrets,
        );
        final pending = detection
            ? service.detectModels(_saved, '')
            : service.test(_saved, '');
        final assertion = expectLater(
          pending,
          throwsA(isA<AiFailure>().having((e) => e.message, 'cancel', '请求已取消')),
        );
        await secrets.started.future;
        service.cancel();
        secrets.result.complete('fixture-key');
        await assertion;
        expect(adapter.calls, 0);
        expect(await db.usage(), isEmpty);
      },
    );
  }

  testWidgets(
    'leaving settings cancels connection test and ignores late reply',
    (tester) async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = _LateClient();
      final secrets = _Secrets();
      await db.saveSettings(_saved.toJson());
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(secrets),
            aiClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: InkTheme.build(Brightness.light),
            home: const AiSettingsPage(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'API 密钥',
        ),
        'fixture-key',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (w) => w is TextField && w.decoration?.labelText == '模型名称',
              ),
            )
            .controller!
            .text,
        'old-model',
      );
      await tester.scrollUntilVisible(
        find.text('测试连接'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试连接'));
      await tester.pump();
      await tester.runAsync(
        () => client.started.future.timeout(const Duration(seconds: 5)),
      );
      await tester.pump();
      navigator.currentState!.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('已返回')),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.activeToken!.isCancelled, isTrue);
      client.reply.complete(const AiReply('迟到回复', input: 2, output: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('已返回'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final usage = await tester.runAsync(db.usage);
      expect(usage!.single['status'], 'failed');
    },
  );

  test('chat trims model and key consistently with model detection', () async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    await AiClient(dio: dio).request(
      const AiSettings(base: 'https://example.test/v1/', model: ' model '),
      ' fixture-key ',
      [],
      CancelToken(),
    );
    expect(adapter.request!.uri.path, '/v1/chat/completions');
    expect(adapter.request!.headers['Authorization'], 'Bearer fixture-key');
    expect((adapter.request!.data as Map)['model'], 'model');
    expect(adapter.calls, 1);
  });

  test(
    'saved key can test newly selected model without saving or retyping',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      await db.saveSettings(_saved.toJson());
      final adapter = _Adapter();
      final service = AiContentService(
        db,
        AiClient(dio: Dio()..httpClientAdapter = adapter),
        _Secrets(),
      );
      await service.test(
        const AiSettings(base: 'https://example.test/v1/', model: 'new-model'),
        '  ',
      );
      expect(adapter.calls, 1);
      expect(await db.settings(), _saved.toJson());
      final usage = await db.usage();
      expect(usage.single['status'], 'received');
      expect(jsonEncode(usage), isNot(contains('fixture-key')));
      expect((await db.usageTotals())['unknown'], 1);
    },
  );

  test(
    'port change requires credential confirmation before mutation',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      await db.saveSettings(_saved.toJson());
      final secrets = _Secrets();
      final service = AiContentService(db, AiClient(), secrets);
      const other = AiSettings(
        base: 'https://example.test:8443/v1',
        model: 'm',
      );
      await expectLater(
        service.saveSettings(other, 'replacement'),
        throwsA(isA<AiFailure>()),
      );
      expect(secrets.value, 'fixture-key');
      expect(await db.settings(), _saved.toJson());
      await service.saveSettings(other, 'replacement', hostConfirmed: true);
      expect(secrets.value, 'replacement');
    },
  );

  test(
    'cancelled request discards a late successful client response',
    () async {
      final db = GameDatabase.memory();
      addTearDown(db.close);
      final client = _LateClient();
      final service = AiContentService(db, client, _Secrets());
      final request = service.test(_saved, 'fixture-key');
      final assertion = expectLater(
        request,
        throwsA(isA<AiFailure>().having((e) => e.message, 'cancel', '请求已取消')),
      );
      await client.started.future;
      service.cancel();
      client.reply.complete(const AiReply('连接成功', input: 3, output: 1));
      await assertion;
      expect((await db.usage()).single['status'], 'failed');
      expect((await db.usageTotals())['input'], 3);
    },
  );
}
