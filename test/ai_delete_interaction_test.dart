import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiuxian_app/application/ai_service.dart';
import 'package:xiuxian_app/application/game_controller.dart';
import 'package:xiuxian_app/data/game_database.dart';
import 'package:xiuxian_app/ui/ai_pages.dart';
import 'package:xiuxian_app/ui/ink_theme.dart';

class _DeleteSecrets implements SecretStore {
  String? value = 'fixture-key';
  int deletes = 0;
  bool fail = false;
  final started = Completer<void>();
  Completer<void>? release;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String key) async => value = key;
  @override
  Future<void> delete() async {
    deletes++;
    if (!started.isCompleted) started.complete();
    if (release != null) await release!.future;
    if (fail) throw StateError('fixture secure store failure');
    value = null;
  }
}

class _DeleteDatabase extends GameDatabase {
  _DeleteDatabase() : super(NativeDatabase.memory());
  bool fail = false;
  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    if (fail) throw StateError('fixture database failure');
    await super.saveSettings(settings);
  }
}

const _settings = AiSettings(
  base: 'https://example.test/v1',
  model: 'fixture-model',
  enabled: true,
  consent: true,
);

Future<void> _open(
  WidgetTester tester,
  GameDatabase db,
  _DeleteSecrets secrets, {
  GlobalKey<NavigatorState>? navigator,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(secrets),
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
  await tester.scrollUntilVisible(
    find.text('删除密钥'),
    250,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('deletion disables AI first and serializes settings actions', (
    tester,
  ) async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    await db.saveSettings(_settings.toJson());
    final secrets = _DeleteSecrets()..release = Completer<void>();
    await _open(tester, db, secrets);
    final delete = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '删除密钥'))
        .onPressed!;
    delete();
    delete();
    await tester.runAsync(() => secrets.started.future);
    await tester.pump();
    expect(secrets.deletes, 1);
    expect((await tester.runAsync(db.settings))!['enabled'], false);
    expect(secrets.value, 'fixture-key');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '删除密钥'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '测试连接'))
          .onPressed,
      isNull,
    );
    secrets.release!.complete();
    await tester.pumpAndSettle();
    expect(secrets.value, isNull);
    expect(find.text('密钥已删除，AI已关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletion finishes safely after leaving the settings page', (
    tester,
  ) async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    await db.saveSettings(_settings.toJson());
    final secrets = _DeleteSecrets()..release = Completer<void>();
    final navigator = GlobalKey<NavigatorState>();
    await _open(tester, db, secrets, navigator: navigator);
    await tester.tap(find.text('删除密钥'));
    await tester.runAsync(() => secrets.started.future);
    navigator.currentState!.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('已返回')),
      ),
    );
    await tester.pumpAndSettle();
    secrets.release!.complete();
    await tester.pumpAndSettle();
    expect(find.text('已返回'), findsOneWidget);
    expect(secrets.value, isNull);
    expect((await tester.runAsync(db.settings))!['enabled'], false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secure deletion failure keeps AI disabled and permits retry', (
    tester,
  ) async {
    final db = GameDatabase.memory();
    addTearDown(db.close);
    await db.saveSettings(_settings.toJson());
    final secrets = _DeleteSecrets()..fail = true;
    await _open(tester, db, secrets);
    await tester.tap(find.text('删除密钥'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI已关闭，但密钥删除失败，请重试。'), findsOneWidget);
    expect((await tester.runAsync(db.settings))!['enabled'], false);
    expect(secrets.value, 'fixture-key');
    secrets.fail = false;
    await tester.tap(find.text('删除密钥'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('密钥已删除，AI已关闭'), findsOneWidget);
    expect(secrets.deletes, 2);
    expect(secrets.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('database failure preserves the key and reports a safe error', (
    tester,
  ) async {
    final db = _DeleteDatabase();
    addTearDown(db.close);
    await db.saveSettings(_settings.toJson());
    final secrets = _DeleteSecrets();
    await _open(tester, db, secrets);
    db.fail = true;
    await tester.tap(find.text('删除密钥'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法关闭AI，密钥未删除，请重试。'), findsOneWidget);
    expect(secrets.deletes, 0);
    expect(secrets.value, 'fixture-key');
    expect((await tester.runAsync(db.settings))!['enabled'], true);
    expect(tester.takeException(), isNull);
  });
}
