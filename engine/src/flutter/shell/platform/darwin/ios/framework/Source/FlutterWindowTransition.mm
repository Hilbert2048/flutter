// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterWindowTransition.h"

@class FlutterWindowTransition;
@interface FlutterWindowTransitionRelay : NSObject
@property(nonatomic, weak) FlutterWindowTransition* owner;
- (void)tick:(CADisplayLink*)link;
@end

@interface FlutterWindowTransition ()
- (void)tick;
@end

@implementation FlutterWindowTransition {
  __weak UIView* _view;
  void (^_onUpdate)(void);
  CADisplayLink* _link;
  CGSize _from;
  CGSize _target;
  int64_t _revision;
  int64_t _sample;
  int64_t _phase;
}

- (instancetype)initWithView:(UIView*)view onUpdate:(void (^)(void))onUpdate {
  self = [super init];
  if (self) {
    _view = view;
    _onUpdate = [onUpdate copy];
  }
  return self;
}

- (void)beginToSize:(CGSize)size coordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
  [_link invalidate];
  _link = nil;
  ++_revision;
  ++_sample;
  CALayer* presentation = _view.layer.presentationLayer;
  _from = presentation ? presentation.bounds.size : _view.bounds.size;
  _target = size;
  _phase = coordinator.transitionDuration > 0 ? 1 : 3;
  _onUpdate();
  const int64_t revision = _revision;
  __weak FlutterWindowTransition* weakSelf = self;
  [coordinator animateAlongsideTransition:nil
                              completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    FlutterWindowTransition* strongSelf = weakSelf;
    if (!strongSelf || strongSelf->_revision != revision) return;
    [strongSelf->_link invalidate];
    strongSelf->_link = nil;
    strongSelf->_phase = context.isCancelled ? 4 : 3;
    ++strongSelf->_sample;
    strongSelf->_onUpdate();
  }];
  if (_phase != 1) return;
  FlutterWindowTransitionRelay* relay = [[FlutterWindowTransitionRelay alloc] init];
  relay.owner = self;
  _link = [CADisplayLink displayLinkWithTarget:relay selector:@selector(tick:)];
  NSInteger fps = _view.window.windowScene.screen.maximumFramesPerSecond;
  if (fps > 0) _link.preferredFrameRateRange = CAFrameRateRangeMake(60, fps, fps);
  [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick {
  _phase = 2;
  ++_sample;
  _onUpdate();
}

- (void)updateMetrics:(flutter::ViewportMetrics*)metrics scale:(CGFloat)scale {
  if (_revision == 0) return;
  metrics->window_transition_id = _revision;
  metrics->window_transition_sample = _sample;
  metrics->window_transition_phase = _phase;
  metrics->window_from_width = _from.width * scale;
  metrics->window_from_height = _from.height * scale;
  metrics->window_target_width = _target.width * scale;
  metrics->window_target_height = _target.height * scale;
  if (_link) {
    CALayer* presentation = _view.layer.presentationLayer;
    CGSize size = presentation ? presentation.bounds.size : _from;
    if (size.width <= 0 || size.height <= 0) return;
    metrics->physical_width = round(size.width * scale);
    metrics->physical_height = round(size.height * scale);
    metrics->physical_min_width_constraint = metrics->physical_width;
    metrics->physical_max_width_constraint = metrics->physical_width;
    metrics->physical_min_height_constraint = metrics->physical_height;
    metrics->physical_max_height_constraint = metrics->physical_height;
  }
}

- (void)cancel {
  [_link invalidate];
  _link = nil;
  if (_phase == 1 || _phase == 2) {
    _phase = 4;
    ++_revision;
    ++_sample;
  }
}

- (void)dealloc {
  [_link invalidate];
}
@end

@implementation FlutterWindowTransitionRelay
- (void)tick:(CADisplayLink*)link { [self.owner tick]; }
@end
