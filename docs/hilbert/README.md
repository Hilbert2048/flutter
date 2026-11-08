# 本机共享 Flutter SDK

X、Vyn 的统一入口是 `/Users/hilbert/coding/flutter`，使用官方 Flutter / Xcode / GN / Ninja 工具。
应用不增加 local-engine 配置、启动器或原生转场适配器。入口切换到本 checkout 后，原 SDK 目录保留用于回退。

## 2026-11-08 用户准入

用户已明确准入 engine / framework / Vyn page 联合候选，要求真机 Release 体验。
这是体验准入，不代表“媲美原生”的最终视觉验收通过。

- 官方基线：`e36b37012875b78fd8636d46b2ca68747d3b5800`。
- engine/framework 构建源：`1b49019811037d9db19513dd619f2be948c1286b`。
- engine content hash：`bb29b28a0a6b54aa27ef6c92a2f6d2db37f1c791`，由官方 GN 生成，固定在 `bin/internal/engine.version`。
- Dart revision：`3b174b7217fe09b21da836ea623932b5f041b091`，没有更换 Dart 编译器版本。
- 保留 Navigator 与后台恢复 surface 补丁；新增窗口几何通知、framework 上下文和 iOS 呈现帧顺序保护。
- 标准缓存包含配套 iOS device Debug / Profile / Release、arm64 Simulator Debug、dart:ui 源码、debug/product patched SDK 和匹配的 host flutter_tester。
- Dart SDK、gen_snapshot、frontend_server、font-subset 等未受这次修改影响的工具沿用相同源 revision 的既有产物。

本轮成套构建/验证范围是 iOS arm64 与 macOS 上的 Flutter widget 测试。Android、macOS 桌面及其他平台未编译新的原生运行时，不能把它们当作本轮已完成的制品；其平台缓存 stamp 保留旧值，不伪装已更新。Simulator 仅打包 arm64；不携带旧的 x86_64 snapshot 冒充配套运行时。新 dart:ui 类型使旧 Debug snapshot 不能当作配套运行时混用。

当前仍有页面标题／播控转场、呈现边缘覆盖、触摸／语义与 PlatformView 待验收项。
`WindowTransitionContext.layoutProgress` 是尺寸路径的投影，不是 UIKit 时间或角度的同步承诺。

## 构建与制品

```sh
cd engine/src
python3 flutter/tools/gn --ios --runtime-mode=release --mac-cpu=arm64 --no-rbe --no-goma --no-lto
ninja -C out/ios_release_arm64 flutter_framework
ninja -C out/ios_release_arm64 flutter/lib/snapshot:strong_platform flutter/sky/packages/sky_engine:sky_engine
```

Debug / Profile 分别使用对应 runtime-mode；模拟器增加 `--simulator --simulator-cpu=arm64`。
维护者将产物放入标准 SDK 缓存并记录真实来源。`bin/cache/hilbert-engine-artifacts.json` 仅记录来源，不参与构建选择。不要给 Debug 引擎改名冒充 Release，也不要只按 UUID 判断新机器代码是否装入。

官方工具按 engine stamp 判断缓存；同一 pin 下替换实验二进制时，独立验证 App 必须执行官方 clean 或确保相关缓存正确失效。正式准入使用新的真实 pin，因此日常项目仍是普通 `flutter run --release`。

这是本机带产物 SDK，Git 不携带编译缓存，也未新增私有下载服务。清空缓存或新机器克隆后需维护者构建配套产物，官方 CDN 不提供此私有 hash。

升级后在应用及独立子包执行官方 `flutter pub get`，更新 Flutter root 与 languageVersion，不能手改生成 JSON 或屏蔽不存在参数错误。

## 回退

原 SDK `/Users/hilbert/coding/hilbert-flutter-upstream-20261108` 原样保留。
回退需要同时撤回 Vyn 的窗口上下文接线和主体过渡两个提交，再将统一入口指回原 SDK，并重新 pub get；只切 SDK 而保留新页面 API 会产生编译错误。X 没有本次播放器页面改动。
