// SceneDelegate.swift
// MozcFlickKeyboard — ホストアプリの Scene ライフサイクル。
// RootViewController をナビゲーションに載せてウィンドウへ設定する。
// 追加: 疑似センサー受信サーバー（SensorHTTPServer）を前面時のみ稼働させる。
//       iOS の制約でバックグラウンドでは待ち受けできないため、active で start / 背面で stop する。

import UIKit
import MozcFlickShared // 追加: NarrativeState（受信ON/OFF・ポート設定）を参照

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// 追加: 受信設定（ON/OFF・ポート）を読むための状態ストア。
    private let narrativeState = NarrativeState()

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let dashboard = UINavigationController(rootViewController: LifeLogDashboardViewController())
        dashboard.tabBarItem = UITabBarItem(title: "くらしのログ", image: UIImage(systemName: "house"), tag: 0)
        let keyboard = UINavigationController(rootViewController: RootViewController())
        keyboard.tabBarItem = UITabBarItem(title: "キーボード", image: UIImage(systemName: "keyboard"), tag: 1)
        let tabs = UITabBarController()
        let research = UINavigationController(rootViewController: ResearchViewController())
        research.tabBarItem = UITabBarItem(title: "生活の気づき", image: UIImage(systemName: "cloud.sun"), tag: 2)
        tabs.viewControllers = [dashboard, keyboard, research]
        NotificationCenter.default.addObserver(forName: ResearchNotificationCoordinator.openQuestion, object: nil, queue: .main) { _ in tabs.selectedIndex = 2 }
        window.rootViewController = tabs
        self.window = window
        window.makeKeyAndVisible()
        if UserDefaults(suiteName: AppConfig.appGroupID)?.data(forKey: "research.notificationQuestion") != nil { tabs.selectedIndex = 2 }
    }

    /// 追加: 前面になったら（設定が ON のときだけ）疑似センサー受信を開始する。
    func sceneDidBecomeActive(_ scene: UIScene) {
        ResearchNotificationCoordinator.shared.foreground()
        LocationContextCollector.shared.restore()
        ResearchContextCollector.shared.refresh() // 追加: 前面になるたびに端末Context（歩数・予定・バッテリー）を更新
        guard narrativeState.sensorReceiveEnabled else {
            NSLog("[MFK-Sensor] receive disabled (settings OFF)") // 追加: OFF のときは待ち受けない
            return
        }
        SensorHTTPServer.shared.start(port: narrativeState.sensorPort)
    }

    /// 追加: 背面へ回るときは必ず停止する（iOS はバックグラウンド待ち受けを許さない）。
    func sceneWillResignActive(_ scene: UIScene) {
        SensorHTTPServer.shared.stop()
    }

    /// 追加: バックグラウンド遷移時も念のため停止しておく。
    func sceneDidEnterBackground(_ scene: UIScene) {
        ResearchNotificationCoordinator.shared.background()
        SensorHTTPServer.shared.stop()
    }
}
