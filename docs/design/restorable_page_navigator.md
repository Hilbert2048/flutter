# Feature Design: Restorable Page Navigator

This document outlines the design and implementation of the "Restorable Page Navigator" feature for Flutter. This feature allows a popped page to be cached and restored via a swipe gesture, enhancing the user experience by enabling quick backtracking.

## 1. Goal

Customize the Flutter `Navigator` to support restoring the last popped page using a right-to-left swipe gesture (reverse back swipe).

## 2. Requirements

1.  **Pop Retention**: When a page is popped, it should not be strictly destroyed immediately if it is marked as restorable. Instead, it should be cached.
2.  **Restoration Gesture**: Support a right-to-left swipe gesture (starting from the right edge) to restore the cached page.
3.  **Single Page Limit**: Only the most recently popped page can be cached. The cache capacity is **1**.
4.  **Opt-in Protocol**: Pages must explicitly declare their support for restoration. The default behavior is **non-restorable**.
5.  **Strict LIFO Restoration**:
    *   Restoration must respect the natural stack order.
    *   If the stack is `[A, B (Standard Page), C (Restorable)]`:
        *   Pop C -> C is cached.
        *   Pop B -> **C's cache MUST be cleared** (B is an opaque `PageRoute`).
    *   Restoration is strictly valid only for the *immediately preceding* popped route.
    *   **Exception**: Popping non-fullscreen overlays (`PopupRoute` such as BottomSheet/Dialog, or non-opaque `PageRoute` such as smooth_sheets) does **NOT** invalidate the cache.

## 3. Architecture & Design

### 3.1. API Protocol: `RestorableRouteMixin`

To support restoration, a route must mix in `RestorableRouteMixin`. The `shouldRestoreOnPop` property is mutable and can be changed dynamically at any time before the route is popped.

```dart
// Defined in packages/flutter/lib/src/widgets/routes.dart

mixin RestorableRouteMixin<T> on Route<T> {
  bool _shouldRestoreOnPop = false;

  /// Whether this route should be cached by the Navigator when popped.
  /// Mutable — can be changed dynamically before the route is popped.
  bool get shouldRestoreOnPop => _shouldRestoreOnPop;
  set shouldRestoreOnPop(bool value) {
    _shouldRestoreOnPop = value;
  }

  /// Convenience: set shouldRestoreOnPop from a page's BuildContext.
  static bool setRestoreOnPop(BuildContext context, bool value) {
    final route = ModalRoute.of(context);
    if (route is RestorableRouteMixin) {
      (route as RestorableRouteMixin<Object?>).shouldRestoreOnPop = value;
      return true;
    }
    return false;
  }
}
```

**Important**: Subclasses should set the initial value in the constructor rather than overriding the getter, to preserve dynamic mutability:

```dart
// GOOD — preserves setter
class MyRoute extends MaterialPageRoute<void> with RestorableRouteMixin<void> {
  MyRoute({required super.builder}) {
    shouldRestoreOnPop = true;
  }
}

// BAD — shadows setter, dynamic changes won't work
class MyRoute extends MaterialPageRoute<void> with RestorableRouteMixin<void> {
  @override
  bool get shouldRestoreOnPop => true; // always true, setter ignored!
}
```

### 3.2. Navigator Modification (`NavigatorState`)

The core logic resides in `packages/flutter/lib/src/widgets/navigator.dart`.

#### State Management
*   `_RouteEntry? _cachedRestoredEntry`: Stores the single cached popped route entry.

#### Lifecycle modifications (`_flushHistoryUpdates`)
When a route is popped (processed in `_flushHistoryUpdates`):
1.  **If Restorable**:
    *   Check `route is RestorableRouteMixin && route.shouldRestoreOnPop`.
    *   If true:
        *   Remove from `_history` but **do not** add to `toBeDisposed`.
        *   Store in `_cachedRestoredEntry`.
        *   **CRITICAL**: Do **not** remove overlay entries. Instead, set `route.offstage = true`.
          ```dart
          route.offstage = true;
          ```
        *   This hides the route but keeps the widget tree mounted, preserving state.
2.  **If Standard (Non-Restorable)**:
    *   **CRITICAL**: Invalidate the cache, but **only** if the disposed route is an **opaque `PageRoute`**.
        *   **Why both checks?** `PageRoute` alone is insufficient — some third-party packages (e.g. `smooth_sheets`) use `PageRoute` subclasses for non-fullscreen overlays with `opaque: false`. Only opaque page routes represent a true navigation stack level change that should invalidate the cache.
        *   `PopupRoute` (BottomSheet, Dialog, Menu) and non-opaque `PageRoute` are transient overlays that do not alter the page-level navigation order.
        ```dart
        if (_cachedRestoredEntry != null && route is PageRoute && route.opaque) {
          if (_cachedRestoredEntry!.route.overlayEntries.isNotEmpty) {
            for (final OverlayEntry entry in _cachedRestoredEntry!.route.overlayEntries) {
              entry.remove();
              entry.dispose();
            }
            _cachedRestoredEntry!.route.overlayEntries.clear();
          }
          _disposeRouteEntry(_cachedRestoredEntry!, graceful: true);
          _cachedRestoredEntry = null;
        }
        ```
    *   Proceed with standard disposal.

### 3.3. Gesture Handling

A `GestureDetector` is conditionally added to the `Navigator`'s build method.

*   **Condition**: `if (_cachedRestoredEntry != null || _restorationGestureController != null)`
*   **Controller**: `_RestorationGestureController` handles the drag updates.
    *   **onDragStart**:
        *   Set `route.offstage = false` to make it visible.
        *   Setup animation.
    *   **onDragUpdate**: Drives the animation controller.
    *   **onDragEnd**:
        *   **Restoration Confirmed**: Completes animation, route is fully restored to `_history`.
        *   **Restoration Cancelled**:
            *   Reverses animation.
            *   Upon completion, calls `_cancelRestoration`.

#### Cancellation Logic (`_cancelRestoration`)
If the user starts a swipe but cancels it (swipes back):
1.  The route is marked for disposal (`_RouteLifecycle.dispose`).
2.  `_flushHistoryUpdates` is triggered.
3.  **Locking**: The call to `_flushHistoryUpdates` must be wrapped in `assert(() { _debugLocked = true; return true; }())`.
4.  The route is turned back into a cached entry (re-cached).
    *   **CRITICAL**: Set `route.offstage = true` again to hide it.

## 4. Critical Implementation Details & Future Upgrade Considerations

These implementation details are subtle and critical. **If the Navigator architecture is refactored or upgraded, these invariants must be preserved.** (Updated 2026-01-29)

### 4.1. Overlay Entry Management (`_allRouteOverlayEntries`)
The `Navigator` uses `_allRouteOverlayEntries` to determine which overlay entries to render in the `Overlay` widget.
*   **Invariant**: This getter must explicitly include `_cachedRestoredEntry.route.overlayEntries`.
*   **Reason**: Standard `_history` iteration omits the cached route (since it's removed from history). If omitted from this getter, `Overlay.rearrange` will detach the views from the widget tree, causing state loss and "Found 0 widgets" errors in tests.
*   **Code Reference**:
    ```dart
    Iterable<OverlayEntry> get _allRouteOverlayEntries {
      return <OverlayEntry>[
        for (final _RouteEntry entry in _history) ...entry.route.overlayEntries,
        // MUST INCLUDED CACHED ENTRIES
        if (_cachedRestoredEntry != null) ..._cachedRestoredEntry!.route.overlayEntries,
      ];
    }
    ```

### 4.2. Route Installation (`Route.install`)
When a cached route is restored, `handlePush` calls `install()`.
*   **Invariant**: `Route.install` must prevent creating *duplicate* overlay entries if they already exist, BUT it must still call `super.install()`.
*   **Reason**: `ModalRoute` (and `TransitionRoute`) rely on `super.install()` to initialize animation proxies (`_animationProxy`). If skipped, animations fail, and the route may not render/transition correctly.
*   **Code Reference**: (`packages/flutter/lib/src/widgets/routes.dart`)
    ```dart
    void install() {
      // Only create new entries if we don't have them (e.g. first install)
      if (_overlayEntries.isEmpty) {
        _overlayEntries.addAll(createOverlayEntries());
      }
      // ALWAYS call super to initialize mixins/subclasses (e.g. AnimationProxies)
      super.install();
    }
    ```

### 4.3. State Preservation via `Offstage`
*   **Invariant**: Cached routes are hidden using `(route as ModalRoute).offstage = true`, **not** by removing them from the overlay.
*   **Reason**: Removing them triggers disposal logic or detachments that destroy State objects (`StatefulWidget` states). Toggling `offstage` keeps the Element/RenderObject tree alive but skips painting/hitting, which is exactly what "caching" requires.

### 4.4. ModalBarrier Interaction (`ModalRoute._buildModalBarrier`)
*   **Invariant**: The `ModalBarrier` (if present) must ALSO be wrapped in `Offstage(offstage: offstage, ...)`.
### 4.5. RouteObserver Notification Fix (`RouteObserver.didPush`)
*   **Problem**: Standard `RouteObserver.didPush` assumes a pushed route is new and has no subscribers. It only notifies the `previousRoute`.
*   **Fix**: Modified `didPush` to also iterate over `_listeners[route]` and notify existing subscribers (`didPush()`).
*   **Reason**: Restored routes reuse the same Route instance. Their `RouteAware` widgets (subscribers) are preserved. Without this fix, they never receive the `didPush` event upon restoration.

### 4.6. RouteObserver & RouteAware Compatibility
*   **Behavior**: The caching and restoration mechanism is fully compatible with `RouteObserver` and `RouteAware` widgets.
*   **Lifecycle Mapping**:
    1.  **Cache (Pop)**:
        *   **Target Page**: Receives `didPop`. (Treated as exiting).
        *   **Previous Page**: Receives `didPopNext`. (Treated as regaining focus).
    2.  **Restore (Push)**:
        *   **Target Page**: Receives `didPush`. (Treated as re-entering).
        *   **Previous Page**: Receives `didPushNext`. (Treated as losing focus).
    3.  **Re-Pop**: Standard behavior (`didPop` / `didPopNext`).
*   **Why**: Since the cached route's Widget/State is **preserved** (not disposed), it remains subscribed to the `RouteObserver`. When `Navigator` triggers a `push` event during restoration, `RouteObserver` correctly notifies the existing subscriber, ensuring `Hero`, video players, or analytics trackers behave exactly as if the user navigated to a new instance of the page.

## 5. Verification

### 5.1. Test Suites
*   **Main Logic**: `packages/flutter/test/widgets/navigator_page_restoration_test.dart`
*   **Observer Compatibility**: `packages/flutter/test/widgets/route_aware_restoration_test.dart` (Crucial for verifying `didPush` on restoration)

### 5.2. Test Infrastructure
For regression testing, a helper route class `TestRestorableRoute` is used. This class sets the initial value via the constructor (not by overriding the getter) to preserve dynamic mutability.

```dart
// Defined in packages/flutter/test/widgets/navigator_page_restoration_test.dart
class TestRestorableRoute extends MaterialPageRoute<void> with RestorableRouteMixin<void> {
  TestRestorableRoute({required super.builder, bool restoreOnPop = false}) {
    shouldRestoreOnPop = restoreOnPop;
  }
}
```

### 5.3. Key Scenarios
1.  **Basic Restoration**: Push Restorable -> Pop -> Swipe -> Restored.
2.  **Non-Restorable**: Push Standard -> Pop -> Swipe -> No action.
3.  **Cancellation**: Push Restorable -> Pop -> Swipe half -> Cancel -> Route remains cached, Navigator responsive.
4.  **Strict LIFO (Page)**: Push A -> Push B (Standard Page) -> Push C (Restorable) -> Pop C -> Pop B -> Swipe -> C is **NOT** restored (cache was cleared by opaque PageRoute B).
5.  **State Persistence**: `initState` must not be called upon restoration.
6.  **PopupRoute Preserves Cache**: Push Restorable -> Pop (cached) -> Push BottomSheet -> Pop BottomSheet -> Swipe -> Restorable is still restored (PopupRoute does not invalidate cache).
7.  **Dynamic restoreOnPop**: Push Restorable (restoreOnPop=true) -> set `shouldRestoreOnPop = false` -> Pop -> Swipe -> NOT restored.
8.  **setRestoreOnPop from BuildContext**: Same as above but using `RestorableRouteMixin.setRestoreOnPop(context, false)`.
