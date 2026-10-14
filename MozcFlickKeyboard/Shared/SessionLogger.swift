// SessionLogger.swift
// MozcFlickKeyboard — キーボード拡張の入力イベントをセッション単位で記録するロガー。
//
// 1セッションは最大60秒。非表示または無入力60秒でも確定する。周期・無入力の確定後は次の入力で再開。
// App Group 共有コンテナの Library/Caches/SessionLogs/ 配下へ
// "session_yyyyMMdd_HHmmss_SSS_<UUID先頭8桁>.jsonl" を生成し、イベントを1行ずつ(JSON Lines)追記する。
// 親アプリはこのディレクトリを読み取り、ログ一覧・中身を閲覧できる。
// 追加: セッション終了時に onSessionClosed で LoggedSession を通知し、Keyboard 側がサーバー送信キューへ積む。
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

/// 追加: 終了した入力セッション。サーバー送信用のpayloadへ変換する前の生ログを保持する。
public struct LoggedSession {
    public let sessionID: String
    public let startedAt: Date
    public let endedAt: Date
    public let closeReason: String
    public let events: [SessionEvent]

    public init(sessionID: String,
                startedAt: Date,
                endedAt: Date,
                closeReason: String,
                events: [SessionEvent]) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.closeReason = closeReason
        self.events = events
    }
}

/// セッション単位で JSONL ファイルへイベントを追記するロガー。
public final class SessionLogger {

    /// 追加: 最終イベントからこの秒数が経過したらセッションを閉じる。
    public let idleTimeout: TimeInterval
    private let maximumDuration: TimeInterval
    private let directory: URL?

    /// 追加: セッション終了時の通知。Keyboard側が特徴量と端末Contextを足して送信する。
    public var onSessionClosed: ((LoggedSession) -> Void)?

    /// App Group 共有コンテナ内のログ保存ディレクトリ URL。親アプリ・拡張ともここを参照する。
    public static var logsDirectoryURL: URL? {
        guard let base = AppConfig.sharedContainerURL else { return nil }
        return base.appendingPathComponent("Library/Caches/SessionLogs", isDirectory: true)
    }

    /// 追記用ファイルハンドル。
    private var handle: FileHandle?
    /// 追加: 現セッションの ID / 開始時刻 / メモリ上のイベント（送信用）。
    private var sessionID: String?
    private var startedAt: Date?
    private var events: [SessionEvent] = []
    /// 追加: 60秒無入力で閉じるためのタイマー。
    private var idleWorkItem: DispatchWorkItem?
    private var rotationWorkItem: DispatchWorkItem?
    /// 追加: キーボード表示中かつ研究記録が許可されている間だけtrue。
    private var acceptsEvents = false

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

    /// 変更: idleTimeout を注入可能にした（既定60秒）。
    public init(idleTimeout: TimeInterval = 60, maximumDuration: TimeInterval = 60, directory: URL? = nil) {
        self.idleTimeout = idleTimeout
        self.maximumDuration = maximumDuration
        self.directory = directory ?? Self.logsDirectoryURL
    }

    deinit {
        idleWorkItem?.cancel()
        rotationWorkItem?.cancel()
        try? handle?.close()
    }

    /// セッション開始。日付時刻秒ミリ秒のファイルを生成する。
    /// プライベートモード時はこれを呼ばない = 何も記録しない。
    public func enable() {
        acceptsEvents = true // 追加: 記録受付を開始
        openSessionIfNeeded()
    }

    /// 追加: 許可中なら新しいセッションファイルを開く。idle終了後の次打鍵でも使う。
    private func openSessionIfNeeded() {
        guard acceptsEvents else { return }
        guard handle == nil, let dir = directory else { return }
        let now = Date()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let url = dir.appendingPathComponent("session_\(fileNameFormatter.string(from: now))_\(id.prefix(8)).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        guard handle != nil else { return }
        sessionID = id
        startedAt = now
        events.removeAll(keepingCapacity: true)
        // Publish long typing sessions at least every minute, without waiting for keyboard dismissal.
        let rotation = DispatchWorkItem { [weak self] in self?.stop(reason: "interval") }
        rotationWorkItem = rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumDuration, execute: rotation)
        NSLog("[MFK-Log] enable file=\(url.path) ok=\(handle != nil)") // デバッグ: セッション開始
    }

    /// 1イベントを JSONL の1行として追記する。
    public func log(type: String, data: [String: String]) {
        guard acceptsEvents else { return } // 追加: 非表示・停止中は記録しない
        if handle == nil { openSessionIfNeeded() } // 追加: idle終了後の次イベントで新セッション
        guard let handle else { return }
        let event = SessionEvent(time: timeFormatter.string(from: Date()), type: type, data: data)
        events.append(event) // 追加: 送信用にメモリにも保持
        guard var line = try? JSONEncoder().encode(event) else { return }
        line.append(0x0A) // 改行(LF)
        handle.write(line)
        scheduleIdleClose() // 追加: 無入力タイマーを張り直す
    }

    /// 変更: セッション終了。ファイルを閉じ、送信用コールバックへ渡す。
    public func stop(reason: String = "manual") {
        idleWorkItem?.cancel()
        idleWorkItem = nil
        rotationWorkItem?.cancel()
        rotationWorkItem = nil
        // 追加: idle終了後は次の打鍵を新セッションとして受け付ける。非表示・手動停止時は停止を維持する。
        if reason != "idle_timeout" && reason != "interval" { acceptsEvents = false }
        guard let sessionID, let startedAt else {
            try? handle?.close()
            handle = nil
            return
        }
        let endedAt = Date()
        try? handle?.close()
        handle = nil
        let closed = LoggedSession(sessionID: sessionID,
                                   startedAt: startedAt,
                                   endedAt: endedAt,
                                   closeReason: reason,
                                   events: events)
        self.sessionID = nil
        self.startedAt = nil
        events.removeAll(keepingCapacity: true)
        NSLog("[MFK-Log] stop reason=\(reason) events=\(closed.events.count)") // デバッグ: セッション終了
        if !closed.events.isEmpty { onSessionClosed?(closed) } // 追加: 空セッションは送らない
    }

    /// 追加: ログが続くたびに idleTimeout のタイマーを張り直す。
    private func scheduleIdleClose() {
        idleWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.stop(reason: "idle_timeout")
        }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: item)
    }
}
