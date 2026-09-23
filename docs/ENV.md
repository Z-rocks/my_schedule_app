# 环境说明（ENV）

## 1. flutter test 需要 quickjs_c_bridge.dll
`flutter test` 跑在 Windows 宿主 Dart VM 上，QuickJS 需要 `quickjs_c_bridge.dll` 在 DLL 搜索路径。
flutter_js 只为 Flutter Windows 应用构建拷贝该 DLL，不为 `flutter test` 拷贝。
- 报错：`error 126`，找不到 `quickjs_c_bridge.dll`
- 解决：把 `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flutter_js-<版本>\windows\shared\quickjs_c_bridge.dll`
  拷到项目根目录，或加进 `PATH`
- 影响：仅 Windows 宿主的 test；不影响 Android

## 2. flutter.bat 在本机 DSH 沙箱挂死
`flutter.bat` 检测到 PATH 里有 `pwsh` 后会 `call pwsh` 重起一个 shell，嵌套 shell 在沙箱里卡住，无输出直到超时。
- 绕开：`dart.exe <flutter>/bin/cache/flutter_tools.snapshot <args>`
- 后续所有阶段统一走这个方式

## 3. Flutter SDK 缓存 lock 残留
残留过零字节的 `flutter.bat.lock` / `lockfile`（无进程持有），会让后续 flutter 命令无限等待。
- 处理：确认无进程持有后删除

## 4. Android QuickJS 依赖 JitPack
插件 `android/build.gradle` 的 CMake 原生构建被注释（上游记录 ARM SEGV_MAPERR），实际走
JitPack 预编译库 `com.github.fast-development.android-js-runtimes:fastdev-jsruntimes-quickjs:0.3.6`。
- 首次 Android 构建约 275s（含拉 JitPack），之后约 10s
- APK 内含 `lib/arm64-v8a/libfastdev_quickjs_runtime.so`（另有 armeabi-v7a / x86_64）
- 风险：依赖 jitpack.io 可达性 + 第三方预编译 .so