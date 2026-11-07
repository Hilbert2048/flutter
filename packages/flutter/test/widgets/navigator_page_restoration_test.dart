// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';

// ignore: non_constant_identifier_names
class TestRestorableRoute extends MaterialPageRoute<void> with RestorableRouteMixin<void> {
  TestRestorableRoute({required super.builder, bool restoreOnPop = false}) {
    shouldRestoreOnPop = restoreOnPop;
  }
}

void main() {
  testWidgets('Navigator supports opt-in page restoration', (WidgetTester tester) async {
    // 1. Setup Navigator with initial page
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));

    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // 2. Push Restorable Route
    final TestRestorableRoute route2 = TestRestorableRoute(
      restoreOnPop: true,
      builder: (context) => Scaffold(body: Text('Page 2')),
    );
    navigator.push(route2);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    // 3. Pop Page 2
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);

    // Verify Route is NOT disposed (we can't check internal state easily, but we can check if we can restore it)
    // Actually we can check if it was truly disposed later?
    // For now, let's try to restore it via gesture.

    // 4. Perform Swipe to Restore
    // Swipe from right edge to left with velocity
    await tester.flingFrom(
      Offset(799, 300), // Start from right edge
      Offset(-300, 0), // Drag left
      1000.0, // Velocity
    );
    await tester.pumpAndSettle();

    // 5. Verify Page 2 is restored
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('Navigator disposes restored route if another one is popped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Route 2 (Restorable)
    navigator.push(
      TestRestorableRoute(restoreOnPop: true, builder: (context) => Scaffold(body: Text('Page 2'))),
    );
    await tester.pumpAndSettle();

    // Pop Route 2 (Cached)
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsNothing);

    // Push Route 3 (Restorable)
    navigator.push(
      TestRestorableRoute(restoreOnPop: true, builder: (context) => Scaffold(body: Text('Page 3'))),
    );
    await tester.pumpAndSettle();

    // Pop Route 3 (New Cached, Route 2 should be disposed)
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsNothing);

    // Restore (should restore Page 3)
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);

    // Pop Page 3 again
    navigator.pop();
    await tester.pumpAndSettle();

    // Swipe again (should restore Page 3 again)
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);
  });

  testWidgets('Standard routes are not restored', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Standard Route
    navigator.push(MaterialPageRoute<void>(builder: (context) => Scaffold(body: Text('Page 2'))));
    await tester.pumpAndSettle();

    // Pop
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsNothing);

    // Swipe
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();

    // Should still be Page 1
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);
  });

  testWidgets('Navigator supports interactive restoration cancellation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Restorable Route
    navigator.push(
      TestRestorableRoute(restoreOnPop: true, builder: (context) => Scaffold(body: Text('Page 2'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    // Pop
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsNothing);

    // 1. Start Interactive Drag (Restore)
    final TestGesture gesture = await tester.startGesture(Offset(799, 300));
    await tester.pump(); // Trigger dragStart

    // Move left (bring page in)
    await gesture.moveBy(Offset(-400, 0));
    await tester.pump();
    // Page 2 should be mounted now
    expect(find.text('Page 2'), findsOneWidget);

    // 2. Cancel Drag (Move back right - fully offscreen)
    await gesture.moveTo(Offset(800, 300));
    await tester.pump();
    // Pause to ensure velocity is 0
    await tester.pump(const Duration(milliseconds: 500));

    // Release
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(Duration(milliseconds: 100)); // Ensure setState frame is processed

    // Verify Page 2 is gone (returned to cache)
    expect(find.text('Page 2'), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);

    // 3. Retry and Complete
    await tester.flingFrom(Offset(799, 300), Offset(-400, 0), 1000.0);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('Restorable route is NOT disposed when cached (preserved behavior)', (
    WidgetTester tester,
  ) async {
    final List<String> logs = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Text('Page 1')),
        onGenerateRoute: (settings) {
          if (settings.name == '/restorable') {
            return TestRestorableRoute(
              restoreOnPop: true,
              builder: (context) => _LifecycleObserver(logs: logs, name: 'Page 2'),
            );
          }
          return null;
        },
      ),
    );
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Restorable Route
    navigator.pushNamed('/restorable');
    await tester.pumpAndSettle();
    expect(logs, contains('Page 2: initState'));
    logs.clear();

    // Pop (should cache and hide via Offstage, NOT dispose)
    navigator.pop();
    await tester.pumpAndSettle();

    // Verify it was NOT disposed
    expect(logs, isNot(contains('Page 2: dispose')));

    // Restore via gesture
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();

    // Verify it was NOT re-initialized (state preserved)
    expect(logs, isNot(contains('Page 2: initState')));
    expect(find.text('Page 2'), findsOneWidget);
  });

  // Helper classes for the lifecycle test
  testWidgets('Popping a standard route clears the cached restorable route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page A'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push B (Standard)
    navigator.push(MaterialPageRoute<void>(builder: (context) => Scaffold(body: Text('Page B'))));
    await tester.pumpAndSettle();
    expect(find.text('Page B'), findsOneWidget);

    // Push C (Restorable)
    navigator.push(
      TestRestorableRoute(restoreOnPop: true, builder: (context) => Scaffold(body: Text('Page C'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page C'), findsOneWidget);

    // Pop C (Should be cached)
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page C'), findsNothing);
    expect(find.text('Page B'), findsOneWidget);

    // Verify C is restorable via gesture (sanity check)
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();
    expect(find.text('Page C'), findsOneWidget);

    // Reset (Pop C again)
    navigator.pop();
    await tester.pumpAndSettle();

    // Pop B (Standard)
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page B'), findsNothing);
    expect(find.text('Page A'), findsOneWidget);

    // Try to restore C (Should FAIL - i.e., show Page A, not C)
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();

    // MUST NOT find Page C
    expect(find.text('Page C'), findsNothing);
    // Should still be Page A
    expect(find.text('Page A'), findsOneWidget);
  });

  testWidgets('Dynamically disabling restoreOnPop prevents restoration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Restorable Route
    final TestRestorableRoute route2 = TestRestorableRoute(
      restoreOnPop: true,
      builder: (context) => Scaffold(body: Text('Page 2')),
    );
    navigator.push(route2);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    // Dynamically disable restoration before popping
    route2.shouldRestoreOnPop = false;

    // Pop
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);

    // Attempt to restore via swipe — should NOT restore
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();

    expect(find.text('Page 2'), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('RestorableRouteMixin.setRestoreOnPop works from page BuildContext', (
    WidgetTester tester,
  ) async {
    late BuildContext pageContext;

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Restorable Route that captures its BuildContext
    final TestRestorableRoute route2 = TestRestorableRoute(
      restoreOnPop: true,
      builder: (context) {
        pageContext = context;
        return Scaffold(
          body: Text('Page 2'),
        );
      },
    );
    navigator.push(route2);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    // Use the static convenience method to disable restoration from page context
    final bool result = RestorableRouteMixin.setRestoreOnPop(pageContext, false);
    expect(result, isTrue);
    expect(route2.shouldRestoreOnPop, isFalse);

    // Pop
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);

    // Attempt to restore — should NOT restore
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();

    expect(find.text('Page 2'), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('Popping a PopupRoute (BottomSheet) does NOT invalidate cached restorable page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text('Page 1'))));
    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // Push Restorable Page
    navigator.push(
      TestRestorableRoute(restoreOnPop: true, builder: (context) => Scaffold(body: Text('Page 2'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    // Pop Page 2 (should be cached)
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsNothing);

    // Push a BottomSheet (PopupRoute, non-fullscreen)
    navigator.push(ModalBottomSheetRoute<void>(
      builder: (context) => SizedBox(height: 200, child: Text('BottomSheet')),
      isScrollControlled: false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('BottomSheet'), findsOneWidget);

    // Pop the BottomSheet — should NOT destroy cached Page 2
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('BottomSheet'), findsNothing);

    // Swipe to restore — Page 2 should still be restorable
    await tester.flingFrom(Offset(799, 300), Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);
  });
}

class _LifecycleObserver extends StatefulWidget {
  const _LifecycleObserver({required this.logs, required this.name});
  final List<String> logs;
  final String name;

  @override
  State<_LifecycleObserver> createState() => _LifecycleObserverState();
}

class _LifecycleObserverState extends State<_LifecycleObserver> {
  @override
  void initState() {
    super.initState();
    widget.logs.add('${widget.name}: initState');
  }

  @override
  void dispose() {
    widget.logs.add('${widget.name}: dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text(widget.name));
  }
}
