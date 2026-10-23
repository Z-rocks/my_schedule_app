// iOS 原生桥（2026-10 iOS 发行版）。
//
// 在默认模板之上新增两块，均与 Android 侧 Kotlin 一一对应（Dart 契约见
// lib/services/reminder_bridge.dart 与 qr_login_bridge.dart）：
//
// 1. 作业提醒：UNUserNotificationCenter 本地通知。
//    Dart 把算好的排期（含标题/正文文案所需的全部字段）整体下发，
//    原生只做"哑执行"——到点直接提醒。**不做到点前查作业状态**：
//    iOS 不允许 App 在后台起 Flutter 引擎调接口（Android 的做法）。
//
//    上课提醒（`com.zys.myschedule/class_reminder`）走另一条通道但共用同一个
//    notification center，因此两边的"取消"都按 identifier 前缀过滤（`hw_` /
//    `cls_`），绝不调 `removeAllPendingNotificationRequests()`。
//
// 2. 校外登录二维码：保存到相册（PHPhotoLibrary 只加不读）+
//    拉起微信扫一扫（weixin://dl/scan）。
//    「删除」是 no-op：iOS 删相册资源要弹系统确认框，不值得打扰登录流程。
//
// 通道注册放在 SceneDelegate（scene 生命周期里 rootViewController
// 才是 FlutterViewController），这里只挂通知代理。
import Flutter
import UIKit
import UserNotifications
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 前台展示通知用的代理。
  ///
  /// 为什么不用 AppDelegate 自己实现：`FlutterAppDelegate` 本身已经声明了
  /// `UNUserNotificationCenterDelegate` 一致性（用于把通知转发给插件），
  /// 再写 `extension AppDelegate: UNUserNotificationCenterDelegate` 会报
  /// "redundant conformance"。这里用一个独立对象，职责也更清楚。
  private let foregroundPresenter = ForegroundNotificationPresenter()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(
      application, didFinishLaunchingWithOptions: launchOptions)
    // 放在 super 之后：覆盖掉 FlutterAppDelegate 自己设的 delegate。
    UNUserNotificationCenter.current().delegate = foregroundPresenter
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// App 在前台时也弹横幅（与 Android 行为一致）。
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

// MARK: - 系统桥（com.zys.myschedule/system）

/// iOS 只实现跨平台的两个方法：openUrl（打开浏览器 / App Store）与
/// appVersion（版本号唯一真相，来自 Info.plist 的 bundle 版本）。
/// Android 专属的厂商名 / 电池优化 / 精确闹钟等页面在 Dart 侧已按平台隐藏。
final class SystemChannelHandler: NSObject {
  static let channelName = "com.zys.myschedule/system"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = SystemChannelHandler()
    channel.setMethodCallHandler { call, result in
      handler.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openUrl":
      guard
        let args = call.arguments as? [String: Any],
        let raw = args["url"] as? String,
        let url = URL(string: raw),
        url.scheme == "http" || url.scheme == "https"
      else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { ok in
        result(ok)
      }
    case "appVersion":
      let info = Bundle.main.infoDictionary ?? [:]
      let short = (info["CFBundleShortVersionString"] as? String) ?? ""
      let build = (info["CFBundleVersion"] as? String) ?? ""
      if short.isEmpty {
        result("")
      } else {
        result(build.isEmpty ? short : "\(short)+\(build)")
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - 作业提醒通道（com.zys.myschedule/reminder）

/// 处理 Dart 侧 ReminderBridge 的调用。
///
/// 方法契约（与 Android `ReminderContract` 一致；未列出的方法回
/// FlutterMethodNotImplemented，Dart 侧已兜底为 false）：
/// - syncPlan(json) / cancelAll()
/// - hasNotificationPermission / requestNotificationPermission
/// - openNotificationSettings
/// - showTestNotification(title, body)
final class ReminderChannelHandler: NSObject {
  static let channelName = "com.zys.myschedule/reminder"

  /// iOS 每个App 最多 64 条待发通知，留 4 条余量给测试通知等。
  static let maxPendingRequests = 60

  /// 本通道自己的通知 identifier 前缀。
  ///
  /// 上课提醒（`ClassReminderChannelHandler`）共用同一个 notification center，
  /// 用 `cls_` 前缀。两边的取消动作都必须按前缀过滤——早期这里直接调
  /// `removeAllPendingNotificationRequests()`，会把上课提醒一起清掉。
  static let identifierPrefix = "hw_"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = ReminderChannelHandler()
    channel.setMethodCallHandler { call, result in
      handler.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "syncPlan":
      syncPlan(call, result: result)
    case "cancelAll":
      removeOwnPending { result(true) }
    case "hasNotificationPermission":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let granted = settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
        result(granted)
      }
    case "requestNotificationPermission":
      // 只表示"弹窗已拉起"（与 Android 语义一致）；真实结果由 Dart 稍后查询。
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
        _, _ in
      }
      result(true)
    case "openNotificationSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
        result(true)
      } else {
        result(false)
      }
    case "showTestNotification":
      showTestNotification(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 只清本通道的待发通知，保留上课提醒的那批。
  private func removeOwnPending(completion: @escaping () -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let ids = requests
        .map { $0.identifier }
        .filter { $0.hasPrefix(ReminderChannelHandler.identifierPrefix) }
      if !ids.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: ids)
      }
      completion()
    }
  }

  /// 全量替换排期：先清掉全部待发通知，再把排期逐条转成
  /// UNCalendarNotificationTrigger 本地通知。排期在 Dart 侧已按触发时刻
  /// 升序排好，超出系统上限时**保留最早的**（截掉最远的）。
  private func syncPlan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let json = args["json"] as? String,
      let data = json.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data),
      let root = parsed as? [String: Any],
      let items = root["items"] as? [[String: Any]]
    else {
      NSLog("[Reminder] syncPlan 参数解析失败")
      result(false)
      return
    }

    let center = UNUserNotificationCenter.current()
    let now = Date()

    // 只清 `hw_` 前缀的旧排期，上课提醒（`cls_`）的不能动。
    removeOwnPending {
      var scheduled = 0
      for item in items {
        guard scheduled < ReminderChannelHandler.maxPendingRequests else { break }
        guard let fireAtMs = item["fireAtMillis"] as? Int else { continue }
        let fireAt = Date(timeIntervalSince1970: TimeInterval(fireAtMs) / 1000.0)
        // 已到点的不再排（Dart 侧有 45s 保护，这里再兜一层时钟漂移）。
        guard fireAt > now else { continue }

        let content = UNMutableNotificationContent()
        content.title = ReminderChannelHandler.notificationTitle(item)
        content.body = ReminderChannelHandler.notificationBody(item)
        content.sound = .default

        let components = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // identifier 带触发时刻，重复 syncPlan 也不会撞 id。
        let identifier = "hw_\(item["homeworkId"] ?? "")_\(item["slot"] ?? 0)_\(fireAtMs)"
        let request = UNNotificationRequest(
          identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
          if let error = error {
            NSLog("[Reminder] 排期失败 \(identifier): \(error.localizedDescription)")
          }
        }
        scheduled += 1
      }
      NSLog("[Reminder] syncPlan 完成：\(scheduled)/\(items.count) 条")
      result(true)
    }
  }

  private func showTestNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(false)
      return
    }
    let content = UNMutableNotificationContent()
    content.title = (args["title"] as? String) ?? "测试通知"
    content.body = (args["body"] as? String) ?? ""
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
      identifier: "hw_test_\(Int(Date().timeIntervalSince1970))",
      content: content,
      trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      result(error == nil)
    }
  }

  // MARK: 通知文案（与 Dart HomeworkReminderItem 的 getter 逐字对齐）

  private static func notificationTitle(_ item: [String: Any]) -> String {
    let courseName = (item["courseName"] as? String) ?? ""
    return courseName.isEmpty ? "作业快截止了" : "作业提醒 · \(courseName)"
  }

  private static func notificationBody(_ item: [String: Any]) -> String {
    let title = (item["title"] as? String) ?? ""
    let offsetMinutes = (item["offsetMinutes"] as? Int) ?? 0
    let slot = (item["slot"] as? Int) ?? 0
    let totalSlots = (item["totalSlots"] as? Int) ?? 0
    return "「\(title)」还有 \(remainingText(offsetMinutes))截止"
      + "（共 \(totalSlots) 次提醒的第 \(slot) 次）"
  }

  /// "还有多久"文案：与 Dart HomeworkReminderItem.remainingText 一致。
  private static func remainingText(_ minutes: Int) -> String {
    if minutes >= 60 && minutes % 60 == 0 {
      let hours = minutes / 60
      if hours >= 24 && hours % 24 == 0 {
        return "\(hours / 24) 天"
      }
      return "\(hours) 小时"
    }
    return "\(minutes) 分钟"
  }
}

// MARK: - 上课提醒通道（com.zys.myschedule/class_reminder）

/// 处理 Dart 侧 `ReminderBridge` 上课提醒那一组的调用。
///
/// 方法契约（与 Android `ClassReminderContract` 一致）：
/// - syncPlan(json) / cancelAll()
/// - hasNotificationPermission
/// - showTestNotification
///
/// ## 与作业提醒共用 UNUserNotificationCenter，但**不能互相清场**
///
/// 两条通道都往同一个 notification center 里塞本地通知，而
/// `removeAllPendingNotificationRequests()` 会连另一类一起清掉。
/// 所以这里所有"取消"动作都按 identifier 前缀过滤（`cls_`），
/// 只动自己的那批。作业提醒那边用 `hw_`，两边互不干扰。
///
/// 文案直接用排期里的 `title` / `body`——Dart 侧 `ClassReminderItem` 已经拼好，
/// 不在这里重写一遍（重写必然和 Dart 慢慢跑偏）。
final class ClassReminderChannelHandler: NSObject {
  static let channelName = "com.zys.myschedule/class_reminder"

  /// 本通道自己的通知 identifier 前缀。
  static let identifierPrefix = "cls_"

  /// 本通道最多排多少条。
  ///
  /// iOS 单个 App 的待发通知上限是 **64 条（两条通道共享）**，所以这里给
  /// 上课提醒留 40、作业提醒留 60 是不对的——必须让两者之和留出余量。
  /// 上课提醒只覆盖 7 天（通常几十条），40 条足够；作业提醒那边按自己的
  /// 60 条截断，实际同时打满的情况极少，且**先到先得**：谁后 sync 谁截断，
  /// 不会互相删除。
  static let maxPendingRequests = 40

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = ClassReminderChannelHandler()
    channel.setMethodCallHandler { call, result in
      handler.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "syncPlan":
      syncPlan(call, result: result)
    case "cancelAll":
      removeOwnPending { result(true) }
    case "hasNotificationPermission":
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        let granted = settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional
        result(granted)
      }
    case "showTestNotification":
      showTestNotification(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 只清本通道的待发通知，保留作业提醒的那批。
  private func removeOwnPending(completion: @escaping () -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let ids = requests
        .map { $0.identifier }
        .filter { $0.hasPrefix(ClassReminderChannelHandler.identifierPrefix) }
      if !ids.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: ids)
      }
      completion()
    }
  }

  /// 全量替换排期：先清掉自己的旧通知，再按 `fireAtMillis` 逐条排。
  private func syncPlan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let json = args["json"] as? String,
      let data = json.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data),
      let root = parsed as? [String: Any],
      let items = root["items"] as? [[String: Any]]
    else {
      NSLog("[ClassReminder] syncPlan 参数解析失败")
      result(false)
      return
    }

    let center = UNUserNotificationCenter.current()
    let now = Date()

    // 先取消旧的，再加新的。两步之间有极短的空窗期，但 Dart 侧每次重排
    // 都是全量下发，空窗期内不会有"本该响却没响"的排期（7 天窗口外的
    // 条目本来就不排）。
    removeOwnPending {
      var scheduled = 0
      for item in items {
        guard scheduled < ClassReminderChannelHandler.maxPendingRequests else { break }
        guard let fireAtMs = item["fireAtMillis"] as? Int else { continue }
        let fireAt = Date(timeIntervalSince1970: TimeInterval(fireAtMs) / 1000.0)
        guard fireAt > now else { continue }

        let content = UNMutableNotificationContent()
        content.title = (item["title"] as? String) ?? "上课提醒"
        content.body = (item["body"] as? String) ?? ""
        content.sound = .default

        let components = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        // identifier 用 requestCode（Dart 侧 FNV-1a，同一节课 + 同一提前量
        // 每次都是同一个值）+ 触发时刻，重复 sync 不会撞 id。
        let code = (item["requestCode"] as? Int) ?? 0
        let identifier = "\(ClassReminderChannelHandler.identifierPrefix)\(code)_\(fireAtMs)"
        let request = UNNotificationRequest(
          identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
          if let error = error {
            NSLog("[ClassReminder] 排期失败 \(identifier): \(error.localizedDescription)")
          }
        }
        scheduled += 1
      }
      NSLog("[ClassReminder] syncPlan 完成：\(scheduled)/\(items.count) 条")
      result(true)
    }
  }

  private func showTestNotification(result: @escaping FlutterResult) {
    let content = UNMutableNotificationContent()
    content.title = "上课提醒 · 测试"
    content.body = "通知能用，快到上课时间时就会这样提醒你。"
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
      identifier: "\(ClassReminderChannelHandler.identifierPrefix)test_\(Int(Date().timeIntervalSince1970))",
      content: content,
      trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      result(error == nil)
    }
  }
}

// MARK: - 校外登录二维码通道（com.zys.myschedule/login_qr）

/// 处理 Dart 侧 QrLoginBridge 的调用。
///
/// - saveImageToGallery(bytes, name) → 相册资产占位串（Dart 只拿它做删除，
///   iOS 删除是 no-op）；失败/拒绝授权返回 nil。
/// - isWeChatInstalled / openWeChatScanner → weixin:// scheme。
/// - deleteImage → no-op，返回 false（删相册要弹系统确认框，不做）。
final class LoginQrChannelHandler: NSObject {
  static let channelName = "com.zys.myschedule/login_qr"
  private static let weixinScheme = "weixin://"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = LoginQrChannelHandler()
    channel.setMethodCallHandler { call, result in
      handler.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isWeChatInstalled":
      if let url = URL(string: LoginQrChannelHandler.weixinScheme) {
        result(UIApplication.shared.canOpenURL(url))
      } else {
        result(false)
      }
    case "openWeChatScanner":
      if let url = URL(string: "weixin://dl/scan") {
        UIApplication.shared.open(url) { opened in
          result(opened)
        }
      } else {
        result(false)
      }
    case "saveImageToGallery":
      saveImageToGallery(call, result: result)
    case "deleteImage":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveImageToGallery(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let typedData = args["bytes"] as? FlutterStandardTypedData,
      let image = UIImage(data: typedData.data)
    else {
      NSLog("[LoginQr] 二维码数据解析失败")
      result(nil)
      return
    }

    // 只需要"添加"权限（Info.plist 的 NSPhotoLibraryAddUsageDescription）。
    // 相册里的文件名由系统生成，Dart 传的 `name` 在 iOS 用不上（那是 Android 侧的事）。
    PHPhotoLibrary.shared().performChanges(
      {
        _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
      },
      completionHandler: { success, error in
        if success {
          result("ios://gallery")
        } else {
          NSLog("[LoginQr] 保存到相册失败: \(error?.localizedDescription ?? "未知错误")")
          result(nil)
        }
      }
    )
  }
}
