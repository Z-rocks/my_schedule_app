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
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 作业提醒通知：App 在前台时也弹横幅（与 Android 行为一致）。
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

// MARK: - 前台也显示通知横幅

extension AppDelegate: UNUserNotificationCenterDelegate {
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
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      result(true)
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

  /// 全量替换排期：先清掉全部待发通知，再把排期逐条转成
  /// UNCalendarNotificationTrigger 本地通知。排期在 Dart 侧已按触发时刻
  /// 升序排好，超出系统上限时**保留最早的**（截掉最远的）。
  private func syncPlan(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let json = args["json"] as? String,
      let data = json.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = root["items"] as? [[String: Any]]
    else {
      NSLog("[Reminder] syncPlan 参数解析失败")
      result(false)
      return
    }

    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()

    let now = Date()
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
    PHPhotoLibrary.shared().performChanges(
      {
        let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
        if let name = args["name"] as? String {
          request.placeholderForCreatedAsset?.localizedFileName = name
        }
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
