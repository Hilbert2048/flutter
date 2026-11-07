# Shared Flutter and engine fork

This branch contains the accepted Navigator retention changes, the iOS foreground
surface restoration fix, and separate Xcode 27 build compatibility patches.
Flutter launchers, Xcode backend and GN/Ninja remain upstream code.

The genuine upstream engine artifact pin is retained for SDK tools/unchanged
platforms. A fork checkout alone does not compile or install a custom engine.
Use Flutter's standard --local-engine-src-path, --local-engine and
--local-engine-host arguments to select compiled engines. See app launch.json.

Build the target with the official entry point from engine/src, for example:

```sh
python3 flutter/tools/gn --ios --runtime-mode=release --no-goma --no-rbe --no-lto
ninja -C out/ios_release -j4 flutter_framework flutter/lib/snapshot:generate_snapshot_bins flutter_patched_sdk/platform_strong.dill
```

Check out/ios_release/args.gn: flutter_runtime_mode and dart_runtime_mode must both
be release. An output directory name or matching UUID does not prove runtime mode.
Never call GN's internal argument parser through a custom wrapper.

The current known-good phone Release is built from 0b22c1d3196 with real Release
VM/host SDK f6c31f4c3a. Debug and simulator use 2177fa22019 with b1402eb178 and a
matching host SDK. Both build commits are published on codex/build branches.
Profile must not be configured until a real Profile build is available.

For fresh Dart builds apply dart-xcode27.patch at the DEPS base f6c31f4c3a:

```sh
git -c user.name=Hilbert2048 -c user.email=125776109+Hilbert2048@users.noreply.github.com -c commit.gpgsign=false am --committer-date-is-author-date /absolute/flutter/docs/hilbert/dart-xcode27.patch
```

This reproduces b1402eb178. Build a matching host SDK instead of mixing hashes.
The old candidate.1/candidate.2 toolchain releases are withdrawn: their new
Profile/Release directory names incorrectly concealed Debug runtimes.
