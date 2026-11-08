// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <UIKit/UIKit.h>
#include "flutter/lib/ui/window/viewport_metrics.h"

// Embedder-owned observation of one view's window transaction. Does not own
// application layout, and does not claim that sampled geometry is already shown.
@interface FlutterWindowTransition : NSObject
- (instancetype)initWithView:(UIView*)view onUpdate:(void (^)(void))onUpdate;
- (void)beginToSize:(CGSize)size coordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
- (void)updateMetrics:(flutter::ViewportMetrics*)metrics scale:(CGFloat)scale;
- (void)cancel;
@end
