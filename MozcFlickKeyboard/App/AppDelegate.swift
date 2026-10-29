// AppDelegate.swift
// MozcFlickKeyboard — ホストアプリのアプリケーションライフサイクル。
// Scene ベース構成のため、UI 生成は SceneDelegate が担当する。

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        ResearchNotificationCoordinator.shared.register()
        LocationContextCollector.shared.restore()
        ResearchContextCollector.shared.startBackgroundDelivery() // 追加: HealthKit のバックグラウンド更新を開始（起動のたびに Observer を張り直す）
        return true
    }

    // MARK: - Scene 構成

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
