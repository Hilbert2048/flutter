// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('publishes window samples without remounting its child', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    WindowTransitionContext? observed;
    await tester.pumpWidget(WindowTransition(
        child: Builder(
      key: key,
      builder: (BuildContext context) {
        observed = WindowTransition.maybeOf(context);
        return const SizedBox();
      },
    )));
    final Element original = key.currentContext! as Element;
    expect(observed, isNull);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.view.windowTransition = const ui.WindowTransitionMetrics(
      revision: 7,
      sampleId: 2,
      phase: ui.WindowTransitionPhase.changing,
      fromSize: Size(800, 1600),
      targetSize: Size(1600, 800),
      presentationSize: Size(1200, 1200),
    );
    await tester.pump();
    expect(observed!.targetSize, const Size(800, 400));
    expect(observed!.layoutProgress, .5);
    expect(observed!.revision, 7);
    expect(key.currentContext, same(original));
    tester.view.resetWindowTransition();
    await tester.pump();
    expect(observed, isNull);
  });

  test('degenerate geometry never invents an animation progress', () {
    const WindowTransitionContext context = WindowTransitionContext(
      revision: 1,
      sampleId: 1,
      phase: ui.WindowTransitionPhase.changing,
      fromSize: Size(400, 400),
      targetSize: Size(400, 400),
      presentationSize: Size(400, 400),
    );
    expect(context.layoutProgress, isNull);
  });
}
