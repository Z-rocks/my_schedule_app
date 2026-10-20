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
    // 兜底：个别情况下父类是异步挂 rootViewController 的，
    // 等一帧再试一次；还不行就放弃（Dart 侧所有调用都有 try/catch）。
    DispatchQueue.main.async { [weak self] in
      SceneDelegate.registerChannels(in: self?.window)
    }
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    SceneDelegate.registerChannels(in: window)
  }

  private static func registerChannels(in window: UIWindow?) {
    guard !channelsRegistered else { return }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    channelsRegistered = true
    ReminderChannelHandler.register(with: controller.binaryMessenger)
    LoginQrChannelHandler.register(with: controller.binaryMessenger)
    SystemChannelHandler.register(with: controller.binaryMessenger)
    NSLog("[SceneDelegate] 原生通道已注册（reminder / login_qr / system）")
  }
}
