// Scene 生命周期里注册原生通道。
//
// 通道需要 FlutterViewController 的 binaryMessenger；scene 模板下
// 窗口由父类 FlutterSceneDelegate 在 willConnectTo 里创建，
// 所以这里调完 super 再取 rootViewController。
// 多场景（UIApplicationSupportsMultipleScenes=false）不支持，
// 用静态标志保证只注册一次。
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private static var channelsRegistered = false

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    SceneDelegate.registerChannels(in: window)
    // 兜底 1：等一帧再试（父类可能异步挂 rootViewController）。
    DispatchQueue.main.async { [weak self] in
      SceneDelegate.registerChannels(in: self?.window)
    }
    // 兜底 2：scene 激活时再试一次。不 override sceneDidBecomeActive——
    // 那是可选协议方法，父类不一定实现，写 super 调用会编译失败。
    NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification, object: scene, queue: .main
    ) { [weak self] _ in
      SceneDelegate.registerChannels(in: self?.window)
    }
  }

  private static func registerChannels(in window: UIWindow?) {
    guard !channelsRegistered else { return }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    channelsRegistered = true
    ReminderChannelHandler.register(with: controller.binaryMessenger)
    ClassReminderChannelHandler.register(with: controller.binaryMessenger)
    LoginQrChannelHandler.register(with: controller.binaryMessenger)
    SystemChannelHandler.register(with: controller.binaryMessenger)
    NSLog("[SceneDelegate] 原生通道已注册（reminder / class_reminder / login_qr / system）")
  }
}
