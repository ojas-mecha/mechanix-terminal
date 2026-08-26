import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mechanix_terminal/core/utils/app_logger.dart';
import 'package:mechanix_terminal/core/utils/app_theme.dart';
import 'package:mechanix_terminal/features/data/settings.dart';
import 'package:mechanix_terminal/features/data/settings_repository.dart';
import 'package:mechanix_terminal/features/screen/terminal_tabs_screen.dart';
import 'package:mechanix_terminal/l10n/app_localizations.dart';
import 'package:mechanix_terminal/src/rust/api/simple.dart';
import 'package:mechanix_terminal/src/rust/frb_generated.dart';
import 'package:show_fps/show_fps.dart';

Stream<int>? _terminalStream;
late SettingsRepository settingsRepository;
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  _terminalStream = createTerminalStream().asBroadcastStream();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppSettings _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    try {
      settingsRepository = await SettingsRepository.create();

      if (!mounted) return;

      setState(() {
        _settings = settingsRepository.getSettings();
      });
    } catch (e) {
      AppLogger.i('Failed to initialize settings: $e');
    }
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    settingsRepository.saveSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final showFps = Platform.environment['SHOW_FPS'] == 'true';

    ThemeMode themeMode = ThemeMode.dark;
    if (_settings.colorBackground?.toUpperCase() == '#EFF1F5') {
      themeMode = ThemeMode.light;
    }

    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
      home: TerminalTabs(
        settings: _settings,
        onSettingsChanged: _updateSettings,
        terminalStream: _terminalStream,
      ),
      builder: showFps
          ? (context, child) {
              return ShowFPS(visible: showFps, showChart: false, child: child!);
            }
          : null,
    );
  }
}
