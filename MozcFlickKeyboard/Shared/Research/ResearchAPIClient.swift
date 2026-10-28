// ResearchAPIClient.swift
// MozcFlickKeyboard — 変更: 研究サーバー（MacBook / Tailscale）への通信クライアント。
//
// - upload(_:)               … セッションをファイル再送キュー（App Group Library/Application Support/PendingResearchSessions）へ積み、古い順に POST /api/sessions
// - flushPendingSessions()   … キューに残った未送信セッションを再送（キーボード表示時・親アプリ同期時に呼ぶ）
// - fetchPendingQuestion(...) … GET /api/questions/pending/{participant_id}（サーバーの最新質問1件）
// - sendSensorEvent(_:)       … POST /api/sensor-events（1回だけ送る。失敗しても再送キューには積まない）
// baseURL が空なら何もしない（isConfigured = false）。

import Foundation

public final class ResearchAPIClient {
    private let baseURL: String
    private let session: URLSession
    private let queue = ResearchSessionQueue()

    public init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// 追加: Backend URL が設定済みか。
    public var isConfigured: Bool { endpoint("health") != nil }

    private func endpoint(_ path: String) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        let root = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        guard let url = URL(string: root + path), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    /// 追加: セッションをキューへ積んでから送信を試みる（失敗してもキューに残る）。
    public func upload(_ payload: ResearchSessionUpload) {
        queue.enqueue(payload)
        flushPendingSessions()
    }

    /// 追加: キューの未送信セッションを古い順に送る。1件失敗したらそこで止める。
    public func flushPendingSessions(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let url = endpoint("api/sessions") else { completion(false); return }
        let pending = queue.loadAll()
        sendSequentially(pending, index: 0, url: url, completion: completion)
    }

    private func sendSequentially(_ payloads: [ResearchSessionUpload], index: Int, url: URL, completion: @escaping (Bool) -> Void) {
        guard index < payloads.count else { completion(true); return }
        let payload = payloads[index]
        guard let body = try? NarrativeJSON.encoder.encode(payload) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { [self] _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = error == nil && (200..<300).contains(code)
            NSLog("[MFK-Research] session upload id=\(payload.sessionID) status=\(code) ok=\(success)") // 追加: デバッグ
            guard success else { completion(false); return }
            self.queue.remove(sessionID: payload.sessionID)
            self.sendSequentially(payloads, index: index + 1, url: url, completion: completion)
        }.resume()
    }

    /// Observation heartbeat reports only what this process knows; it does not claim all-day coverage.
    public func sendObservation(participantID: String, source: String, loggingEnabled: Bool?, questionsEnabled: Bool) {
        guard let url = endpoint("api/heartbeats") else { return }
        var body: [String: Any] = ["event_id": UUID().uuidString, "participant_id": participantID,
                                 "occurred_at": ISO8601DateFormatter().string(from: Date()), "source": source,
                                 "questions_enabled": questionsEnabled]
        if let enabled = loggingEnabled { body["logging_enabled"] = enabled }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
        session.dataTask(with: request) { [self] _, _, _ in _ = self.isConfigured }.resume()
    }

    /// 追加: サーバーの最新質問1件を取得する。無い・失敗は nil（main スレッドで返す）。
    public func fetchPendingQuestion(participantID: String,
                                     completion: @escaping (PendingQuestion?) -> Void) {
        let encoded = participantID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? participantID
        guard let url = endpoint("api/questions/pending/\(encoded)") else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[MFK-Research] pending question status=\(code) error=\(String(describing: error))") // 追加: デバッグ
            guard error == nil, code == 200, let data,
                  let question = try? NarrativeJSON.decoder.decode(PendingQuestion.self, from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(question) }
        }.resume()
    }

    /// 追加: センサーイベントをサーバーへ送る。
    public func sendSensorEvent(_ event: ResearchSensorEvent,
                                completion: ((Bool) -> Void)? = nil) {
        guard let url = endpoint("api/sensor-events"),
              let body = try? NarrativeJSON.encoder.encode(event) else {
            completion?(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = error == nil && (200..<300).contains(code)
            NSLog("[MFK-Research] sensor event type=\(event.type) status=\(code) ok=\(success)") // 追加: デバッグ
            DispatchQueue.main.async { completion?(success) }
        }.resume()
    }
}

/// 追加: 未送信セッションを App Group の1セッション1ファイルで保持する再送キュー。
public final class ResearchSessionQueue {
    public static var directoryURL: URL? {
        AppConfig.sharedContainerURL?.appendingPathComponent("Library/Application Support/PendingResearchSessions", isDirectory: true)
    }

    public init() {
        // Preserve queues written by previous app versions; pending uploads must not live in Caches.
        guard let old = AppConfig.sharedContainerURL?.appendingPathComponent("Library/Caches/PendingResearchSessions"),
              let directory = Self.directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.moveItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
        }
    }

    public func enqueue(_ payload: ResearchSessionUpload) {
        guard let directory = Self.directoryURL,
              let data = try? NarrativeJSON.encoder.encode(payload) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(payload.sessionID).appendingPathExtension("json")
        try? data.write(to: url, options: .atomic)
    }

    public func loadAll() -> [ResearchSessionUpload] {
        guard let directory = Self.directoryURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: [.contentModificationDateKey],
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        // 変更: ファイル名(UUID)順ではなく開始時刻の古い順に送る。
        return urls.compactMap { url -> ResearchSessionUpload? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? NarrativeJSON.decoder.decode(ResearchSessionUpload.self, from: data)
        }.sorted { $0.startedAt < $1.startedAt }
    }

    public func remove(sessionID: String) {
        guard let directory = Self.directoryURL else { return }
        let url = directory.appendingPathComponent(sessionID).appendingPathExtension("json")
        try? FileManager.default.removeItem(at: url)
    }
}
