// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
part of dart.ui;

/// The observed phase of a platform window geometry transaction.
enum WindowTransitionPhase { stable, began, changing, ended, cancelled }

/// Experimental window geometry sampled by the embedder.
///
/// All sizes are physical pixels. These observations do not promise that the
/// compositor will display a subsequently generated scene at this same instant.
/// The engine must independently validate scene-to-surface presentation.
class WindowTransitionMetrics {
  const WindowTransitionMetrics({
    required this.revision,
    required this.sampleId,
    required this.phase,
    required this.fromSize,
    required this.targetSize,
    required this.presentationSize,
  });
  final int revision;
  final int sampleId;
  final WindowTransitionPhase phase;
  final Size fromSize;
  final Size targetSize;
  final Size presentationSize;
}
