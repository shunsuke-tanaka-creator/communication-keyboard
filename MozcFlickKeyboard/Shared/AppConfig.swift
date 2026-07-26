import Foundation

/// 利用者固有の値（App Group ID / Bundle ID）を1箇所へ集約する。
/// Info.plist の "AppGroupID" キー経由で xcconfig の値を読み、後から差し替え可能にする。
public enum AppConfig {
    /// App Group ID。Info.plist に無ければコンパイル時定数へフォールバック。
    public static var appGroupID: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String, !v.isEmpty {
            return v
        }
        // フォールバック（Config/Project.xcconfig と一致させること）
        return "group.com.tanaka05.MozcFlickKeyboard"
    }

    /// App Group の共有コンテナ URL。
    public static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}
