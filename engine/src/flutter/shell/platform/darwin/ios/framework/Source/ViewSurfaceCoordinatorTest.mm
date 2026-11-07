// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <XCTest/XCTest.h>

#include "view_surface_coordinator.h"

using Coordinator = flutter::ViewSurfaceCoordinator;

static Coordinator::Readiness Ready() {
  return {true, true, true, true, true};
}

static void CommitLayout(Coordinator& coordinator) {
  coordinator.DidLayout();
  coordinator.DidCommitMetrics();
}

@interface ViewSurfaceCoordinatorTest : XCTestCase
@end

@implementation ViewSurfaceCoordinatorTest

- (void)testForegroundWaitsForNewLayoutAndCommittedMetrics {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.DidCommitMetrics();  // Old metrics alone do not qualify.
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.DidLayout();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.DidCommitMetrics();
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testGpuMayBecomeAvailableAfterLayout {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  auto readiness = Ready();
  readiness.gpu_available = false;
  XCTAssertFalse(coordinator.BeginPreparation(readiness).has_value());
  readiness.gpu_available = true;
  XCTAssertTrue(coordinator.BeginPreparation(readiness).has_value());
}

- (void)testGpuMayBeAvailableBeforeForeground {
  Coordinator coordinator;
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testCreationIsReservedOnlyOnce {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  auto token = coordinator.BeginPreparation(Ready());
  XCTAssertTrue(token.has_value());
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.DidCreateSurface(*token);
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.DidBecomeActive();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testActiveFallbackWhenNoLayoutWasDelivered {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  coordinator.DidBecomeActive();
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testActiveFallbackStillWaitsForGpuAndWindow {
  Coordinator coordinator;
  coordinator.DidBecomeActive();
  auto readiness = Ready();
  readiness.gpu_available = false;
  XCTAssertFalse(coordinator.BeginPreparation(readiness).has_value());
  readiness.gpu_available = true;
  readiness.attached = false;
  XCTAssertFalse(coordinator.BeginPreparation(readiness).has_value());
  readiness.attached = true;
  XCTAssertTrue(coordinator.BeginPreparation(readiness).has_value());
}

- (void)testEveryReadinessConditionIsRequired {
  for (int field = 0; field < 5; ++field) {
    Coordinator coordinator;
    coordinator.WillEnterForeground();
    CommitLayout(coordinator);
    auto readiness = Ready();
    switch (field) {
      case 0:
        readiness.owns_engine = false;
        break;
      case 1:
        readiness.attached = false;
        break;
      case 2:
        readiness.foreground = false;
        break;
      case 3:
        readiness.gpu_available = false;
        break;
      case 4:
        readiness.metrics_valid = false;
        break;
    }
    XCTAssertFalse(coordinator.BeginPreparation(readiness).has_value());
  }
}

- (void)testBackgroundOrDetachCancelsPreparedMetrics {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  coordinator.DidDestroySurface();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  coordinator.WillEnterForeground();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  CommitLayout(coordinator);
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testLateCreationCannotReviveDestroyedSurface {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  auto token = coordinator.BeginPreparation(Ready());
  coordinator.DidDestroySurface();
  coordinator.DidCreateSurface(*token);
  XCTAssertFalse(coordinator.has_surface());
}

- (void)testLateCreationCannotSatisfyNextForegroundEpoch {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  auto old_token = coordinator.BeginPreparation(Ready());
  coordinator.DidDestroySurface();
  coordinator.WillEnterForeground();
  coordinator.DidCreateSurface(*old_token);
  XCTAssertFalse(coordinator.has_surface());
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  CommitLayout(coordinator);
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testDuplicateForegroundDoesNotDiscardCurrentLayout {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  const auto epoch = coordinator.epoch();
  coordinator.WillEnterForeground();
  XCTAssertEqual(coordinator.epoch(), epoch);
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testExistingColdStartSurfaceIsNotCreatedAgainAtActive {
  Coordinator coordinator;
  coordinator.DidCreateSurface(coordinator.epoch());
  coordinator.DidBecomeActive();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
}

- (void)testSameSizeNextForegroundRequiresFreshCommit {
  Coordinator coordinator;
  coordinator.WillEnterForeground();
  CommitLayout(coordinator);
  coordinator.DidCreateSurface(*coordinator.BeginPreparation(Ready()));
  coordinator.DidDestroySurface();
  coordinator.WillEnterForeground();
  XCTAssertFalse(coordinator.BeginPreparation(Ready()).has_value());
  CommitLayout(coordinator);
  XCTAssertTrue(coordinator.BeginPreparation(Ready()).has_value());
}

@end
