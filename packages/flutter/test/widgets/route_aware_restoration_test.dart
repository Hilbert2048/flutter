// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: non_constant_identifier_names
class TestRestorableRoute extends MaterialPageRoute<void> with RestorableRouteMixin<void> {
  TestRestorableRoute({required super.builder, this.restoreOnPop = false});

  final bool restoreOnPop;

  @override
  bool get shouldRestoreOnPop => restoreOnPop;
}

class CheckRouteAware extends StatefulWidget {
  const CheckRouteAware({
    super.key,
    required this.child,
    required this.observer,
    required this.log,
  });
  final Widget child;
  final RouteObserver observer;
  final List<String> log;
  @override
  State<CheckRouteAware> createState() => CheckRouteAwareState();
}

class CheckRouteAwareState extends State<CheckRouteAware> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.observer.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    widget.observer.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    widget.log.add('didPush');
  }

  @override
  void didPop() {
    widget.log.add('didPop');
  }

  @override
  void didPushNext() {
    widget.log.add('didPushNext');
  }

  @override
  void didPopNext() {
    widget.log.add('didPopNext');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  testWidgets('RouteAware receives didPush on restoration', (WidgetTester tester) async {
    final RouteObserver<ModalRoute<void>> observer = RouteObserver<ModalRoute<void>>();
    final List<String> log = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: const Scaffold(body: Text('Page 1')),
      ),
    );

    final NavigatorState navigator = tester.state(find.byType(Navigator));

    // 1. Push Page 2 (Restorable) with RouteAware
    log.clear();
    navigator.push(
      TestRestorableRoute(
        restoreOnPop: true,
        builder: (context) => Scaffold(
          body: CheckRouteAware(observer: observer, log: log, child: const Text('Page 2')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initial push should trigger didPush
    expect(log, contains('didPush'));
    log.clear();

    // 2. Pop Page 2 (Cache)
    navigator.pop();
    await tester.pumpAndSettle();

    // Pop should trigger didPop
    expect(log, contains('didPop'));
    // And widget should NOT be disposed?
    // We can't easily check dispose here without another log, but if didPush fires later, it proves it wasn't destroyed (or was re-subscribed).
    log.clear();

    // 3. Restore Page 2
    // Swipe from right edge to left
    await tester.flingFrom(const Offset(799, 300), const Offset(-300, 0), 1000.0);
    await tester.pumpAndSettle();

    // Restoration should trigger didPush
    expect(find.text('Page 2'), findsOneWidget);
    expect(log, contains('didPush'));
  });
}
