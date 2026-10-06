import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'application/game_controller.dart';
import 'data/game_database.dart';
import 'ui/game_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = GameDatabase.file(
      File(path.join(directory.path, 'xiuxian.sqlite')),
    );
    runApp(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const XiuxianApp(),
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text('无法打开存档目录：$error'))),
      ),
    );
  }
}

class XiuxianApp extends StatefulWidget {
  const XiuxianApp({super.key});
  @override
  State<XiuxianApp> createState() => _XiuxianAppState();
}

class _XiuxianAppState extends State<XiuxianApp> {
  ThemeMode mode = ThemeMode.system;
  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff526f63),
      brightness: brightness,
      surface: brightness == Brightness.light
          ? const Color(0xfff4f1e9)
          : const Color(0xff1b2220),
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff4f1e9)
        : const Color(0xff1b2220),
    visualDensity: VisualDensity.standard,
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '一世仙途',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    home: GameShell(
      toggleTheme: () => setState(
        () => mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      ),
    ),
  );
}
