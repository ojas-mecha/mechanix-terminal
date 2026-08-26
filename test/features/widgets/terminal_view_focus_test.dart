import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mechanix_terminal/features/data/settings.dart';
import 'package:mechanix_terminal/features/widgets/terminal_view.dart';
import 'package:mechanix_terminal/main.dart';
import 'package:mechanix_terminal/src/rust/frb_generated.dart';
import 'package:mechanix_terminal/src/rust/terminal.dart';

class MockRustLibApi extends Fake implements RustLibApi {
  final List<String> inputsSent = [];
  int activeId = -1;

  @override
  int crateApiSimpleAddTerminal({
    required int rows,
    required int cols,
    String? cwd,
  }) => 1;

  @override
  void crateApiSimpleSetActiveTerminal({required int id}) {
    activeId = id;
  }

  @override
  TerminalFrame? crateApiSimpleGetTerminalFrame({required int id}) {
    return TerminalFrame(
      rows: 24,
      cols: 80,
      cursorX: 0,
      cursorY: 0,
      content: 'hello',
      attributes: Uint32List(5),
    );
  }

  @override
  void crateApiSimpleSendInput({required int id, required String input}) {
    inputsSent.add(input);
  }

  @override
  void crateApiSimpleResizeTerminal({
    required int id,
    required int rows,
    required int cols,
  }) {}
}

void main() {
  late MockRustLibApi mockApi;

  setUpAll(() {
    mockApi = MockRustLibApi();
    RustLib.initMock(api: mockApi);
  });

  setUp(() {
    mockApi.inputsSent.clear();
    mockApi.activeId = -1;
  });

  testWidgets('TerminalView requests focus and sets active terminal on init', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(mockApi.activeId, 1);
    final state = tester.state(find.byType(TerminalView)) as dynamic;
    expect(state.hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('Tapping on TerminalView requests focus and triggers text input', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap on the terminal view
    await tester.tap(find.byType(TerminalView));
    await tester.pump();

    final state = tester.state(find.byType(TerminalView)) as TextInputClient;
    expect(state.currentTextEditingValue?.text, isNotEmpty);
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('Software keyboard updateEditingValue sends input to terminal', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(TerminalView)) as TextInputClient;

    // Simulate software keyboard typing "ls"
    state.updateEditingValue(
      const TextEditingValue(
        text: ' ls',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(mockApi.inputsSent, contains('ls'));

    // Simulate software keyboard backspace (sentinel deleted)
    state.updateEditingValue(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    expect(mockApi.inputsSent, contains('\x7f'));

    // Simulate software keyboard Enter action
    state.performAction(TextInputAction.unspecified);
    expect(mockApi.inputsSent, contains('\r'));
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('Hardware key events are forwarded to terminal', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Send physical key
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(mockApi.inputsSent, contains('\x1b[A'));
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('Tab switching activates the newly selected terminal tab', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 2, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabBarView(
            controller: tabController,
            children: [
              TerminalView(
                key: const ValueKey(1),
                terminalId: 1,
                settings: settings,
                tabController: tabController,
                index: 0,
              ),
              TerminalView(
                key: const ValueKey(2),
                terminalId: 2,
                settings: settings,
                tabController: tabController,
                index: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mockApi.activeId, 1);

    // Switch to second tab
    tabController.animateTo(1);
    await tester.pumpAndSettle();

    expect(mockApi.activeId, 2);
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('Navigating to a new route unfocuses terminal, popping restores focus', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routeObserver],
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mockApi.activeId, 1);

    // Push a new route (Settings dialog)
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Settings Screen')),
      ),
    );
    await tester.pumpAndSettle();

    // Verify new route is displayed and terminal is offstage
    expect(find.text('Settings Screen'), findsOneWidget);

    // Pop the route to return to terminal
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Settings Screen'), findsNothing);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(mockApi.activeId, 1);
  });

  testWidgets('App switching to inactive unfocuses terminal and resumed restores focus', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mockApi.activeId, 1);

    final state = tester.state(find.byType(TerminalView)) as dynamic;
    expect(state.hasFocus, isTrue);

    // Simulate app becoming inactive / switching away
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(state.hasFocus, isFalse);

    // Simulate returning to the app / resumed
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(state.hasFocus, isTrue);
    expect(mockApi.activeId, 1);

    final inputClient = tester.state(find.byType(TerminalView)) as TextInputClient;
    expect(inputClient.currentTextEditingValue?.text, isNotEmpty);
  });

  testWidgets('App resume while behind another route does not prematurely focus terminal', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routeObserver],
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mockApi.activeId, 1);

    final state = tester.state(find.byType(TerminalView, skipOffstage: false)) as dynamic;
    expect(state.hasFocus, isTrue);

    // Push Settings route
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Settings Screen')),
      ),
    );
    await tester.pumpAndSettle();

    // App goes inactive then resumes while on Settings screen
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Verify terminal is not active and not focused while settings is open
    expect(state.hasFocus, isFalse);

    // Now pop Settings
    navigator.pop();
    await tester.pumpAndSettle();

    expect(state.hasFocus, isTrue);
    expect(mockApi.activeId, 1);
  });

  testWidgets('App resume restores only the active tab focus in multi-tab scenario', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 2, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabBarView(
            controller: tabController,
            children: [
              TerminalView(
                key: const ValueKey(1),
                terminalId: 1,
                settings: settings,
                tabController: tabController,
                index: 0,
              ),
              TerminalView(
                key: const ValueKey(2),
                terminalId: 2,
                settings: settings,
                tabController: tabController,
                index: 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to tab 2
    tabController.animateTo(1);
    await tester.pumpAndSettle();
    expect(mockApi.activeId, 2);

    // App goes inactive
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    // App resumes
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Active terminal must be tab 2 (terminal ID 2)
    expect(mockApi.activeId, 2);
  });

  testWidgets('App backgrounding for paused, hidden, detached unfocuses terminal', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(TerminalView)) as dynamic;
    expect(state.hasFocus, isTrue);

    // Test paused state
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(state.hasFocus, isFalse);

    // Resume
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.hasFocus, isTrue);

    // Test hidden state
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(state.hasFocus, isFalse);

    // Resume
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.hasFocus, isTrue);

    // Test detached state
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(state.hasFocus, isFalse);
  });

  testWidgets('Hardware and software input streams do not create duplicate inputs', (
    WidgetTester tester,
  ) async {
    final settings = AppSettings();
    final tabController = TabController(length: 1, vsync: const TestVSync());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminalId: 1,
            settings: settings,
            tabController: tabController,
            index: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    mockApi.inputsSent.clear();

    // 1. Hardware Enter key press
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(mockApi.inputsSent, equals(['\r']));

    mockApi.inputsSent.clear();

    // 2. Software keyboard Enter action
    final state = tester.state(find.byType(TerminalView)) as TextInputClient;
    state.performAction(TextInputAction.unspecified);
    expect(mockApi.inputsSent, equals(['\r']));

    mockApi.inputsSent.clear();

    // 3. Hardware Backspace
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(mockApi.inputsSent, equals(['\x7f']));

    mockApi.inputsSent.clear();

    // 4. Software Backspace (sentinel space deleted)
    state.updateEditingValue(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    expect(mockApi.inputsSent, equals(['\x7f']));
  });
}
