# iOS 发行版说明（2026-10）

> 本文档是 iOS 发行版的**唯一真相来源**：范围、构建步骤、已知限制都在这里。

## 1. 发行范围

### 保留（核心功能）

| 功能 | iOS 实现方式 |
|------|--------------|
| 教务系统登录（WebView + Cookie 提取） | `webview_flutter` → WKWebView，`WebViewCookieManager` 走 WKHTTPCookieStore（与 Android 等价） |
| 校外登录（CAS 二维码 + 微信确认） | `ios/Runner/AppDelegate.swift` 的 `LoginQrChannelHandler`：PHPhotoLibrary 存相册（只加不读）+ `weixin://dl/scan` 拉起微信 |
| 学习通（课程 / 作业 / 考试） | `assets/plugins/chaoxing.js` 插件，`flutter_js` iOS 侧走 JavaScriptCore，与平台无关 |
| 课表 / 作业 / 考试 / 消息 / 皮肤 / 插件管理 | 纯 Dart，无平台差异 |
| 作业提醒（消息通知） | `ReminderChannelHandler`：UNUserNotificationCenter 本地通知，到点直接提醒 |
| 明文 http 教务站 | Info.plist `NSAllowsArbitraryLoadsInWebContent`（仅放行 WebView；Dart dio 走 socket 本就不受 ATS 约束） |

### 暂时阉割（iOS 第一版不做）

| 功能 | 原因 | 现状 |
|------|------|------|
| 桌面小组件 | WidgetKit 是另一套体系（SwiftUI + TimelineProvider），工作量大 | 设置页整个"桌面小组件"分组已隐藏 |
| 到点前查作业状态 | iOS 不允许后台起 Flutter 引擎调接口 | 提醒文案改为"以排期时快照为准"；设置页相关开关/按钮已隐藏 |
| 精确闹钟授权 | iOS 无此概念（本地通知本来就准时） | 设置页该行已隐藏 |
| 检查更新 | 远端 Release 只有 APK | iOS 上提示"请通过 TestFlight 更新" |
| 二维码登录后自动删相册 | iOS 删相册资源要弹系统确认框 | `deleteImage` 为 no-op，面板文案改为"请手动删除" |

## 2. 构建（必须在 macOS 上，Windows 无法打包 iOS）

```bash
# 前置：macOS + Xcode 16+（含 iOS SDK）+ Flutter 3.47 stable
flutter doctor            # 确认 [✓] Xcode 行
flutter pub get

# ① 模拟器先跑通（等同真机前的验收）
flutter run               # 选择 iPhone 模拟器；依次验证：登录教务 → 同步 → 课表；
                          # 设置 → 作业提醒 → 开开关（弹通知授权）→ 发测试通知

# ② 打 ipa
flutter build ipa --release
# 产物：build/ios/ipa/*.ipa（Xcode 会自动 Archive + 导出）

# 只想要未签名包（自签 / 侧载工具用）：
flutter build ios --release --no-codesign
```

### 签名

- **模拟器 / 免费体验**：个人 Apple ID（免费 Team）即可 `flutter run` 到模拟器；
  免费账号也能装真机，但描述文件 7 天过期。
- **正式分发**：需要 Apple Developer Program（688 元/年）。
  Xcode 打开 `ios/Runner.xcworkspace` → Runner target → Signing & Capabilities →
  勾 Automatically manage signing + 选 Team。
- Bundle ID 已改为 `com.zys.myschedule`（与 Android 包名一致）；上架前若撞名再改。
- **TestFlight**：`flutter build ipa` 后用 Transporter App 或
  `xcrun altool --upload-app -f build/ios/ipa/xxx.ipa -t ios` 上传，
  App Store Connect 里加测试员即可（这是给同学装的最顺路径）。

## 3. 与 Android 的实现差异（代码层面）

- 通道 `com.zys.myschedule/reminder`：Android = Kotlin 闹钟 + 后台校验引擎；
  iOS = UNUserNotificationCenter 哑执行。Dart 契约见 `lib/services/reminder_bridge.dart`
  （`isBackgroundCheckSupported` / `isExactAlarmSupported` 区分平台能力）。
- 通道 `com.zys.myschedule/login_qr`：iOS 端在 `AppDelegate.swift`，
  通道注册在 `SceneDelegate.swift`（scene 生命周期里才有 FlutterViewController）。
- 小组件三条通道（`widget` / `nav` / `system`）iOS 不实现，Dart 侧经
  `isWidgetPlatformSupported` 统一短路，不会空打通道。

## 4. 已知限制 / 风险（真机首验清单）

1. **Swift 代码未上过编译器**：iOS 侧改动是在 Windows 上写的，语法/API 需要
   Xcode 编译验证。风险点集中在 `SceneDelegate`（rootViewController 时机，已加
   `sceneDidBecomeActive` 兜底重试）和 `PHPhotoLibrary`；全部失败路径都有
   NSLog + Dart 侧 try/catch 兜底，最坏情况是"该功能不可用"，不会崩 App。
2. **自签证书的教务站**：WKWebView 没有 SSL 错误放行 API，`onSslAuthError`
   在 iOS 不生效。当前 NCST 教务证书正常（Android 真机也未触发过），换学校
   若遇自签证书只能换域名或挂前置代理。
3. **通知数量上限**：iOS 每个App 最多 64 条待发通知，`syncPlan` 截断到 60 条
   （排期本身按触发时刻升序，保留的是最早的）。
4. **通知不查状态**：已提前交的作业仍会收到提醒（文案已说明）。
5. **App 图标**：目前是 Flutter 默认图标（`ios/Runner/Assets.xcassets`），
   上架前需替换 1024×1024 及各尺寸。

## 5. 变更清单（本次 commit）

- `ios/Runner/Info.plist`：ATS WebView 放行、相册写入权限、微信 scheme 白名单
- `ios/Runner.xcodeproj/project.pbxproj`：Bundle ID → `com.zys.myschedule`
- `ios/Runner/AppDelegate.swift`：新增 ReminderChannelHandler + LoginQrChannelHandler
- `ios/Runner/SceneDelegate.swift`：注册上述两条通道
- `lib/services/reminder_bridge.dart`：iOS 支持开关 + 平台能力区分
- `lib/services/qr_login_bridge.dart`：iOS 支持 + `canDeleteAfterLogin`
- `lib/services/widget_bridge.dart`：`isWidgetPlatformSupported` 短路
- `lib/services/homework_reminder_service.dart`：iOS 不登记后台校验句柄
- `lib/pages/settings/homework_reminder_page.dart` / `settings_page.dart`：
  按平台隐藏小组件 / 精确闹钟 / 完整校验，文案区分
- `lib/pages/login/webview_login_page.dart`：二维码面板文案按平台区分

## 6. 没有 Mac 怎么出 ipa

**结论先说：Windows 本机出不了 ipa，虚拟机/模拟器也不解决"发行"。**

- `.ipa` 必须由 Xcode 的工具链（`xcodebuild` + codesign）产出，Xcode 只跑在 macOS 上；
- iOS **模拟器**只能跑 `.app`（模拟器架构），装不到真机，而且它本身也要 macOS；
- 在 Windows/Linux 上装 macOS 虚拟机（VMware/QEMU 打补丁）技术上能起来，但：
  违反 Apple 许可（macOS 只能装在 Apple 硬件上）、Xcode 16 在无 Metal 加速的虚拟显卡下
  编译极慢、模拟器基本不可用、AMD 平台几乎没戏。**不建议走**。

### 三条可行路线

| 路线 | 成本 | 能拿到什么 | 适合 |
|---|---|---|---|
| **A. GitHub Actions（已配好）** | 公开仓库免费；私有仓库 2000 分钟/月（macOS 按 10× 折算 ≈ 200 分钟） | 未签名 ipa | 自己/同学小范围装 |
| B. Codemagic / Bitrise 等移动 CI | Codemagic 有免费额度，超出按分钟计费 | 未签名或签名 ipa | 不想依赖 GitHub |
| C. 云 Mac（MacinCloud / AWS EC2 mac）或二手 Mac mini | 云按小时；M1 mini 二手约 2–3k | 完整 Xcode，能跑模拟器 | 长期要做 iOS |

**路线 A 已就绪**：`.github/workflows/ios.yml`
- 手动触发（Actions → iOS Build → Run workflow）或打 `v*` tag 自动跑；
- 产物在 Artifacts：`ios-unsigned-ipa`；
- 想同时出签名包：Run workflow 时勾 `signed`，并在仓库 Secrets 配
  `BUILD_CERTIFICATE_BASE64` / `P12_PASSWORD` / `PROVISIONING_PROFILE_BASE64` /
  `KEYCHAIN_PASSWORD` / `APPLE_TEAM_ID`。

**工作流怎么上到 GitHub**：本机 `git push` 到 github.com 不通（见 README 网络说明）。
两条路：① 在能上 GitHub 的机器上 push；② Gitee 仓库 → 设置 → 镜像管理 → 添加
GitHub 的 **push 镜像**（填 GitHub PAT），之后 Gitee 每次提交自动同步过去。

### 拿到 ipa 之后怎么装到 iPhone（Windows 侧）

1. 下载 **Sideloadly**（Windows 版）或 AltStore；
2. iPhone 用数据线连电脑，Sideloadly 里填自己的 Apple ID（免费账号即可，
   会自动申请免费证书并重签 ipa）；
3. 装完在 iPhone「设置 → 通用 → VPN与设备管理」里信任该开发者证书；
   iOS 16+ 还要在「隐私与安全性」里打开**开发者模式**并重启；
4. **免费账号的限制**：证书 7 天过期、最多 3 个 App、需要每周重新签名一次。

### 想正式分发（同学扫码就装、不用每周重签）

只有一条路：Apple Developer Program（**688 元/年**）。
拿到账号后，用上面的 `signed` 任务出正式包 → Transporter 或
`xcrun altool --upload-app` 传到 App Store Connect → **TestFlight** 分发
（每个构建 90 天有效，最多 10000 名外部测试员）。这一步不需要你有 Mac。

