// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'binding.dart';
import 'framework.dart';
import 'view.dart';

/// Experimental window geometry available to adaptive compositions.
///
/// Sizes are logical pixels. [layoutProgress] is a projection onto the observed
/// size path, not a UIKit rotation angle or a promise of compositor synchronization.
class WindowTransitionContext {
  const WindowTransitionContext({
    required this.revision,
    required this.sampleId,
    required this.phase,
    required this.fromSize,
    required this.targetSize,
    required this.presentationSize,
  });

  factory WindowTransitionContext.fromMetrics(
      ui.WindowTransitionMetrics metrics, double pixelRatio) {
    return WindowTransitionContext(
      revision: metrics.revision,
      sampleId: metrics.sampleId,
      phase: metrics.phase,
      fromSize: metrics.fromSize / pixelRatio,
      targetSize: metrics.targetSize / pixelRatio,
      presentationSize: metrics.presentationSize / pixelRatio,
    );
  }

  final int revision;
  final int sampleId;
  final ui.WindowTransitionPhase phase;
  final ui.Size fromSize;
  final ui.Size targetSize;
  final ui.Size presentationSize;

  bool get isChanging =>
      phase == ui.WindowTransitionPhase.began || phase == ui.WindowTransitionPhase.changing;

  double? get layoutProgress {
    if (phase == ui.WindowTransitionPhase.ended) {
      return 1;
    }
    if (!isChanging) {
      return null;
    }
    final double dx = targetSize.width - fromSize.width;
    final double dy = targetSize.height - fromSize.height;
    final double lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return null;
    }
    return (((presentationSize.width - fromSize.width) * dx +
                (presentationSize.height - fromSize.height) * dy) /
            lengthSquared)
        .clamp(0.0, 1.0);
  }
}

/// Makes a view's observed window transaction available without application
/// platform channels. Unsupported platforms expose null and retain normal layout.
class WindowTransition extends StatefulWidget {
  const WindowTransition({super.key, required this.child});

  final Widget child;

  static WindowTransitionContext? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_WindowTransitionScope>()?.data;
  }

  @override
  State<WindowTransition> createState() => _WindowTransitionState();
}

class _WindowTransitionState extends State<WindowTransition> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ui.FlutterView view = View.of(context);
    final ui.WindowTransitionMetrics? metrics = view.windowTransition;
    return _WindowTransitionScope(
      data: metrics == null
          ? null
          : WindowTransitionContext.fromMetrics(metrics, view.devicePixelRatio),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _WindowTransitionScope extends InheritedWidget {
  const _WindowTransitionScope({required this.data, required super.child});
  final WindowTransitionContext? data;

  @override
  bool updateShouldNotify(_WindowTransitionScope oldWidget) =>
      data?.revision != oldWidget.data?.revision ||
      data?.sampleId != oldWidget.data?.sampleId ||
      data?.presentationSize != oldWidget.data?.presentationSize ||
      data?.phase != oldWidget.data?.phase;
}
