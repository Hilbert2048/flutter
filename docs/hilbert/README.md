# 本机共享 Flutter SDK

X、Vyn 统一使用 `/Users/hilbert/coding/flutter`。应用只运行普通 `flutter run`、
`flutter build ios --release`，不配置 local-engine 参数，不增加启动器或 Xcode phase。
Flutter 工具、Xcode backend、GN、Ninja 保持官方实现。

本分支基于官方 master `e36b37012875`，保留已接受的 Navigator 修改和 iOS 前台恢复
surface 协调补丁。engine 源码提交 `e1f75d3c591`；`bin/internal/engine.version`
固定该源码的 engine content hash `790788f62fb8f23e384a7dae862724ccd7c8f721`。
所有 Dart 产物与 engine 使用同一 revision `3b174b7217f`。

本机标准 SDK 缓存已经安装自编译的 iOS device Debug／Profile／Release 和 arm64
Simulator Debug framework。普通 Flutter 工具按构建模式选择它们。
未修改的其他平台、编译工具、Dart SDK 和 patched Dart SDK 复用相同官方基线的产物；
Simulator x86_64 slice 保留官方实现，本轮自定义模拟器验证范围为 Apple Silicon。
缓存中的 `hilbert-engine-artifacts.json` 只记录来源和 UUID，不参与选择逻辑。

## 维护

源码更新和引擎编译由 SDK 维护者完成，不交给应用工程处理。使用官方命令，例如：

```sh
gclient sync
cd engine/src
python3 flutter/tools/gn --ios --runtime-mode=release --mac-cpu=arm64 --no-rbe --no-goma --no-lto
ninja -C out/ios_release_arm64 flutter_framework
```

编译后把对应 framework 装入本 SDK 的标准 `bin/cache/artifacts/engine` 目录，并一并
维护真实的 engine pin、来源记录和缓存版本。不能只改 revision 或给 Debug 产物改名。
这是本机带产物的 SDK；Git 不携带编译缓存，也未配置定制产物下载服务。清空缓存或
全新克隆后，由维护者恢复配套产物，不能依赖官方服务器下载私有 content hash。

本次没有发布连续 viewport、aspectFill、取消 bounds 动画等失败实验，也没有实现
尚待完成的 engine／framework／page 前台旋转协同方案。SDK 接入正确与旋转视觉验收
是不同结论。原共享 SDK 目录保留，不删除用户会话、应用或数据。
