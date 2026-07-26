// SessionLogger.swift
// MozcFlickKeyboard — キーボード拡張の入力イベントをセッション単位で記録するロガー。
//
// 1 セッション = キーボード表示(viewWillAppear)〜非表示(viewDidDisappear)。
// App Group 共有コンテナの Library/Caches/SessionLogs/ 配下へ
// "session_yyyyMMdd_HHmmss_SSS.jsonl" を生成し、イベントを1行ずつ(JSON Lines)追記する。
// 親アプリはこのディレクトリを読み取り、ログ一覧・中身を閲覧できる。
//
// 前提: App Group への書き込みには Keyboard Extension の Full Access が必要。
// プライバシー: プライベートモード ON のときは enable しない = 何も記録しない。

import Foundation

/// セッション中に記録する1イベント。JSON Lines の1行に対応する。
public struct SessionEvent: Codable {
    public let time: String   // ISO8601(ミリ秒付き)の記録時刻
    public let type: String   // イベント種別（key/kana/delete/conversion/candidate/commit/context 等）
    public let data: [String: String] // 種別ごとの詳細（キーID・かな・確定文字列・前後文脈など）

    public init(time: String, type: String, data: [String: String]) {
        self.time = time
        self.type = type
        self.data = data
    }
}

/// セッション単位で JSONL ファイルへイベントを追記するロガー。
public final class SessionLogger {

    /// App Group 共有コンテナ内のログ保存ディレクトリ URL。親アプリ・拡張ともここを参照する。
    public static var logsDirectoryURL: URL? {
        guard let base = AppConfig.sharedContainerURL else { return nil }
        return base.appendingPathComponent("Library/Caches/SessionLogs", isDirectory: true)
    }

    /// 追記用ファイルハンドル。
    private var handle: FileHandle?

    /// ファイル名用（yyyyMMdd_HHmmss_SSS）。
    private let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f
    }()

    /// イベント時刻用 ISO8601（ミリ秒付き）。
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    public init() {}

    /// セッション開始。日付時刻秒ミリ秒のファイルを生成する。
    /// プライベートモード時はこれを呼ばない = 何も記録しない。
    public func enable() {
        guard handle == nil, let dir = Self.logsDirectoryURL else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session_\(fileNameFormatter.string(from: Date())).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        NSLog("[MFK-Log] enable file=\(url.path) ok=\(handle != nil)") // デバッグ: セッション開始
    }

    /// 1イベントを JSONL の1行として追記する。
    public func log(type: String, data: [String: String]) {
        guard let handle else { return }
        let event = SessionEvent(time: timeFormatter.string(from: Date()), type: type, data: data)
        guard var line = try? JSONEncoder().encode(event) else { return }
        line.append(0x0A) // 改行(LF)
        handle.write(line)
    }

    /// セッション終了。ファイルを閉じる。
    public func stop() {
        try? handle?.close()
        handle = nil
        NSLog("[MFK-Log] stop") // デバッグ: セッション終了
    }
}
