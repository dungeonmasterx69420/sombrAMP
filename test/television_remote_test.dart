import 'package:finamp/components/Shortcuts/television_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TelevisionRemote', () {
    late int presses;
    late int longPresses;

    setUp(() {
      presses = 0;
      longPresses = 0;
    });

    Widget remote(Widget child) => MaterialApp(
      builder: (context, navigator) => TelevisionRemote(child: navigator!),
      home: Scaffold(body: child),
    );

    Widget button({bool withLongPress = true}) => RemoteLongPress(
      onLongPress: withLongPress ? () => longPresses++ : null,
      child: TextButton(autofocus: true, onPressed: () => presses++, child: const Text('Album')),
    );

    testWidgets('select activates when it is released', (tester) async {
      await tester.pumpWidget(remote(button()));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(presses, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect((presses, longPresses), (1, 0));
    });

    testWidgets('holding select does the long press once, and nothing on release', (tester) async {
      await tester.pumpWidget(remote(button()));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      }
      expect((presses, longPresses), (0, 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect((presses, longPresses), (0, 1));
    });

    testWidgets('holding select on a widget without a long press activates it once', (tester) async {
      await tester.pumpWidget(remote(button(withLongPress: false)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect((presses, longPresses), (1, 0));
    });

    testWidgets('a disabled long press keeps an ancestor\'s from running', (tester) async {
      await tester.pumpWidget(
        remote(RemoteLongPress(onLongPress: () => longPresses += 10, child: button(withLongPress: false))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(longPresses, 0);
    });

    testWidgets('the menu key does the long press', (tester) async {
      await tester.pumpWidget(remote(button()));
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect((presses, longPresses), (0, 1));
    });

    testWidgets('text fields keep enter', (tester) async {
      await tester.pumpWidget(
        remote(RemoteLongPress(onLongPress: () => longPresses++, child: const TextField(autofocus: true))),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(longPresses, 0);
    });

    testWidgets('up and down leave a one-line text field', (tester) async {
      final username = FocusNode();
      final password = FocusNode();
      addTearDown(username.dispose);
      addTearDown(password.dispose);
      await tester.pumpWidget(
        remote(
          Column(
            children: [
              TextField(focusNode: username, autofocus: true),
              TextField(focusNode: password),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(username.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(password.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(username.hasFocus, isTrue);
    });

    testWidgets('navigation is directional', (tester) async {
      late NavigationMode mode;
      await tester.pumpWidget(
        remote(
          Builder(
            builder: (context) {
              mode = MediaQuery.navigationModeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(mode, NavigationMode.directional);
    });
  });
}
