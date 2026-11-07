// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_VIEW_SURFACE_COORDINATOR_H_
#define FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_VIEW_SURFACE_COORDINATOR_H_

#include <cstdint>
#include <optional>

namespace flutter {

// Per-view eligibility for recreating a surface. A prepared surface is not
// proof of a rendered or displayed frame. All calls are made on the platform
// thread.
class ViewSurfaceCoordinator {
 public:
  struct Readiness {
    bool owns_engine = false;
    bool attached = false;
    bool foreground = false;
    bool gpu_available = false;
    bool metrics_valid = false;

    bool IsReady() const {
      return owns_engine && attached && foreground && gpu_available &&
             metrics_valid;
    }
  };

  void WillEnterForeground() {
    if (phase_ == Phase::kPreparing) {
      return;
    }
    ++epoch_;
    phase_ = Phase::kPreparing;
    layout_observed_ = false;
    metrics_committed_ = false;
    creating_ = false;
    created_ = false;
  }

  void DidLayout() {
    if (phase_ == Phase::kPreparing) {
      layout_observed_ = true;
    }
  }

  void DidCommitMetrics() {
    if (phase_ == Phase::kPreparing && layout_observed_) {
      metrics_committed_ = true;
    }
  }

  void DidBecomeActive() { phase_ = Phase::kActive; }

  // Reserve at most one creation. The token also protects against destruction
  // or backgrounding reentered while the embedder synchronously creates it.
  std::optional<uint64_t> BeginPreparation(const Readiness& readiness) {
    if (created_ || creating_ || !readiness.IsReady()) {
      return std::nullopt;
    }
    if (phase_ != Phase::kActive &&
        !(phase_ == Phase::kPreparing && metrics_committed_)) {
      return std::nullopt;
    }
    creating_ = true;
    return epoch_;
  }

  void DidCreateSurface(uint64_t epoch) {
    if (epoch != epoch_) {
      return;
    }
    creating_ = false;
    created_ = true;
  }

  void DidDestroySurface() {
    ++epoch_;
    phase_ = Phase::kDetached;
    creating_ = false;
    created_ = false;
    layout_observed_ = false;
    metrics_committed_ = false;
  }

  uint64_t epoch() const { return epoch_; }
  bool has_surface() const { return created_ || creating_; }

 private:
  enum class Phase { kDetached, kPreparing, kActive };
  Phase phase_ = Phase::kDetached;
  uint64_t epoch_ = 0;
  bool layout_observed_ = false;
  bool metrics_committed_ = false;
  bool creating_ = false;
  bool created_ = false;
};

}  // namespace flutter

#endif  // FLUTTER_SHELL_PLATFORM_DARWIN_IOS_FRAMEWORK_SOURCE_VIEW_SURFACE_COORDINATOR_H_
