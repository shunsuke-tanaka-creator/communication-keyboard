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
    @discardableResult
    public func upload(_ payload: ResearchSessionUpload) -> Bool {
        guard queue.enqueue(payload) else { return false }
        flushPendingSessions()
        return true
    }

    /// 追加: キューの未送信セッションを古い順に送る。一時エラーで停止、恒久エラーは原本を隔離して後続へ進む。
    public func flushPendingSessions(completion: @escaping (Bool) -> Void = { _ in }) {
        guard let url = endpoint("api/sessions") else { completion(false); return }
        let pending = queue.pendingFiles
        sendSequentially(pending, index: 0, url: url, completion: completion)
    }

    private func sendSequentially(_ files: [URL], index: Int, url: URL, completion: @escaping (Bool) -> Void) {
        guard index < files.count else { completion(true); return }
        let file = files[index]
        guard let body = try? Data(contentsOf: file),
              (try? NarrativeJSON.decoder.decode(ResearchSessionUpload.self, from: body)) != nil else {
            guard ResearchPersistence.quarantine(file, reason: "decode") else { completion(false); return }
            sendSequentially(files, index: index + 1, url: url, completion: completion)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { [self] _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil else { completion(false); return }
            if ResearchPersistence.isPermanentHTTPFailure(code) {
                guard ResearchPersistence.quarantine(file, reason: String(code), expected: body) else { completion(false); return }
            } else {
                guard (200..<300).contains(code) else { completion(false); return }
                if (try? Data(contentsOf: file)) == body { try? FileManager.default.removeItem(at: file) }
            }
            sendSequentially(files, index: index + 1, url: url, completion: completion)
        }.resume()
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

    /// 追加: 設定に応じて実質問またはサーバー評価済みプレビュー候補を取得する。
    public func fetchProposal(participantID: String,
                              source: ProposalDataSource,
                              completion: @escaping (ProposalCandidate?) -> Void) {
        switch ProposalFetchRoute.route(for: source) {
        case .pending:
            fetchPendingQuestion(participantID: participantID) { question in
                completion(question.map { ProposalCandidate(question: $0, isPreview: false) })
            }
        case .preview(let dataMode):
            fetchPreview(participantID: participantID, dataMode: dataMode) { response in
                completion(response?.question.map { ProposalCandidate(question: $0, isPreview: true) })
            }
        }
    }

    /// 追加: サーバー評価済みの read-only 提案プレビューを取得する。
    public func fetchPreview(participantID: String,
                             dataMode: String,
                             completion: @escaping (PreviewResponse?) -> Void) {
        let encoded = participantID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? participantID
        guard let base = endpoint("api/research/\(encoded)/proposal-preview"),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            completion(nil)
            return
        }
        components.queryItems = [URLQueryItem(name: "data_mode", value: dataMode)]
        guard let url = components.url else { completion(nil); return }
        session.dataTask(with: url) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[MFK-Research] proposal preview mode=\(dataMode) status=\(code) error=\(String(describing: error))") // 追加: デバッグ
            guard error == nil, code == 200, let data,
                  let preview = try? NarrativeJSON.decoder.decode(PreviewResponse.self, from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(preview) }
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
