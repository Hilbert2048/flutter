# Hilbert Flutter toolchain

Shared by X and Vyn. The repository owns framework and engine changes; apps pin an
exact source commit in schema-2 `toolchain.json`. Keep upstream `master` untouched.

## Commit and release policy

- `codex/topic/navigator-retention` preserves the user's accepted X Navigator
  retention implementation, its tests and design document byte-for-byte.
  Acceptance is inherited from the user; migration does not reopen feature review.
- `codex/integration` contains individually reviewable Navigator, iOS restoration,
  Xcode linker compatibility, and toolchain commits. Experimental continuous
  viewport is excluded. Do not rebase published release tags.
- Engine-build provenance records the exact build checkout revision and Dart DEPS
  revision separately from the framework revision. This first migration reuses
  existing candidate outputs and builds new modes from the restoration checkout;
  the new build checkout's engine subtree matches integration; the historical Release used an earlier linker-only compatibility revision. It is not legitimate to relabel an old
  binary with a new source revision. Future releases may build everything directly
  from the integrated checkout.
- The official artifact revision in `bin/internal/engine.version` is the genuine
  upstream base's artifact ID. It supplies standard tools and unchanged platforms;
  local iOS builds must explicitly use our engine. It is not a custom artifact ID.
- Dart's Xcode SDK warning compatibility patch is kept under `patches/` for the
  nested DEPS checkout. Apply it there with `git am`; do not silently modify DEPS.

## Local setup

Clone the pinned commit from `git@github.com:Hilbert2048/flutter.git` into a dedicated
SDK. Do not change the channel or working tree of a user's shared SDK.

Each app has a Git-ignored `.toolchains/flutter` symlink to that SDK and a
`.toolchains/local.json` registration of verified engine outputs. Paths are local;
source identities and mode selection are in the committed app lock. Register
existing builds with `prepare.py`, run it from the app root:

```sh
python3 .toolchains/flutter/dev/hilbert_toolchain/prepare.py --sdk /absolute/sdk
python3 .toolchains/flutter/dev/hilbert_toolchain/prepare.py --profile rotation-restore --variant ios-device-release --engine-src /absolute/build/engine/src
```

`tool/flutterw` and the SDK's `bin/flutter` share one launcher. Cursor/VS Code uses
the shared `/Users/hilbert/coding/flutter` entry through the project's `dart.flutterSdkPath`. Physical and
simulated iOS targets are resolved from Flutter's selected device ID. An ambiguous
target needs explicit `-d`. No automatic stock-engine fallback is allowed for iOS.
Other platforms retain the custom framework and use upstream engine artifacts.

Xcode's backend resolves the lock from the project directory and overrides stale
local-engine environment values for its actual platform/configuration. Generate
Xcode configuration through Flutter first; never hand-edit Generated.xcconfig.
An already-running Flutter daemon/debug session stays on its original SDK until
restarted by its owner. Switching project settings does not alter an active build.

## Fresh native builds

Use a full engine checkout at the pinned build revision, synchronized DEPS, and
apply the recorded Dart compatibility patch. `build_engine.py` uses upstream GN
argument generation with an explicit Python interpreter and refuses to overwrite
an existing output. For example:

```sh
python3 dev/hilbert_toolchain/build_engine.py --source /absolute/build/engine/src --output ios_debug_device_hilbert --mode debug
python3 dev/hilbert_toolchain/build_engine.py --source /absolute/build/engine/src --output ios_profile_device_hilbert --mode profile
python3 dev/hilbert_toolchain/build_engine.py --source /absolute/build/engine/src --output ios_release_device_hilbert --mode release
python3 dev/hilbert_toolchain/build_engine.py --source /absolute/build/engine/src --output host_release_hilbert --mode release --host
```

Host builds use Dart `create_most_sdk` with prebuilt SDK disabled. Host SDK, target
VM and platform dill must share the real SDK hash. Never spoof revisions or relax
hash checks to make a package launch. Build sequentially, respecting user jobs.
The present native linker patch is specific to Xcode 27.2; review/remove it on a
compiler upgrade. It is not part of the generic rotation fix.

## Validation and rollback

```sh
python3 -m unittest discover -s dev/hilbert_toolchain -p 'test_*.py'
python3 .toolchains/flutter/dev/hilbert_toolchain/verify.py --profile rotation-restore --variant ios-device-release --app /absolute/Runner.app
```

The launcher validates the exact clean SDK revision; engine verification checks
source/DEPS identities, artifact hashes, host/VM SDK pairing, and optionally the
embedded UUID. Toolchain tests prove selection and rejection paths, not UIKit
animation or device capability. Native rotation remains a candidate until its
own visual acceptance; adopted Navigator acceptance is independent.

Rollback both apps to their previous known-good lock and registered SDK. A pure
upstream rollback may require reverting app calls to custom Navigator APIs too.
Never uninstall an app, clear data, or overwrite published artifacts to roll back.

For an upstream upgrade: select a baseline on a new integration branch, replay
functional patches independently, drop fixes already supplied upstream, rebuild
all supported modes, then update app locks through dedicated commits. Artifacts
belong in immutable versioned releases/storage, not Git. Publishing binary assets
and enabling CI are separate from local source/toolchain migration.

## Exact Dart patch replay

The patch's author and committer metadata are intentionally identical. Starting
from the DEPS base `f6c31f4c3a63512dba17852a1aa761a1edac533d`, this command was
verified in an independent worktree to reproduce
`b1402eb178a229a0af2833263c572974bd5d3049` exactly:

```sh
git -c user.name=Hilbert2048 -c user.email=125776109+Hilbert2048@users.noreply.github.com -c commit.gpgsign=false am --committer-date-is-author-date /absolute/flutter/dev/hilbert_toolchain/patches/0003-dart-xcode27-signpost.patch
```

Ordinary `git am` uses a new committer timestamp and produces a different Dart
SDK hash. Preserve the metadata or publish/revalidate a new source and artifact
lock. Never relabel the old SDK.

The first complete local matrix is iOS device Debug/Profile/Release and arm64
Simulator Debug, all with the real `b1402eb178` VM/host SDK hash. App locks carry
per-file artifact hashes; registering different binaries requires a reviewed lock
update. Shared local registration symlinks are followed on atomic writes.
