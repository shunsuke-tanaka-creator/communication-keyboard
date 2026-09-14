// NarrativeRepository.swift
// MozcFlickKeyboard — 追加: NarrativeEvent / ContextEvent の保存先を抽象化する。
//
// LocalRepository … 常に JSONL へ保存（Phase1 の本体）
// RemoteRepository … URLSession で POST。baseURL 未設定 or URL 不正なら何もしない。
//                    narrative の送信失敗時は unsent_narrative.jsonl へ退避する。
// NarrativeRepositoryHub … local(必ず) + remote(best-effort) へ同時に流す唯一の入口。
// 呼び出し側に completion を要求せず、throw もしない（キーボード拡張から安全に呼べるようにする）。

import Foundation

/// 保存先の共通インターフェース。
public protocol NarrativeRepository {
    /// 回答済み micro-diary を保存する。
    func save(_ event: NarrativeEvent)
    /// 質問を伴わない文脈イベントを保存する。
    func saveContext(_ event: ContextEvent)
}

/// App Group の JSONL へ保存するローカル実装。
public final class LocalRepository: NarrativeRepository {

    /// 実際の書き込みを担うストア。
    private let store: NarrativeStore

    public init(store: NarrativeStore = NarrativeStore()) {
        self.store = store
    }

    public func save(_ event: NarrativeEvent) {
        store.appendNarrative(event)
    }

    public func saveContext(_ event: ContextEvent) {
        store.appendContext(event)
    }
}

/// バックエンドへ POST するリモート実装。Phase1 では baseURL 未設定のため実質 no-op。
public final class RemoteRepository {

    /// 送信先ベース URL 文字列（空なら送信しない）。
    private let baseURL: String
    /// 送信失敗分の退避に使うストア。
    private let store: NarrativeStore
    /// 送信に使うセッション。
    private let session: URLSession

    public init(baseURL: String, store: NarrativeStore) {
        self.baseURL = baseURL
        self.store = store
        self.session = URLSession(configuration: .default)
    }

    /// baseURL + path から URL を作る。空 / 不正なら nil。
    private func endpoint(_ path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.hasSuffix("/") ? trimmed + path : trimmed + "/" + path)
    }

    /// 回答済みイベントを送信する。URL 未設定・送信失敗のいずれでも退避キューへ回す。
    public func save(_ event: NarrativeEvent) {
        guard let url = endpoint("api/narrative-events"),
              let body = try? NarrativeJSON.encoder.encode(event) else {
            store.appendUnsent(event) // URL 未設定なら送らずに退避
            return
        }
        post(url: url, body: body) { [store] success in
            guard !success else { return }
            store.appendUnsent(event) // 通信失敗も退避
        }
    }

    /// 文脈イベントを送信する。失敗しても退避せず捨てる（ローカル JSONL に残っているため）。
    public func saveContext(_ event: ContextEvent) {
        guard let url = endpoint("api/context-events"),
              let body = try? NarrativeJSON.encoder.encode(event) else { return }
        post(url: url, body: body) { _ in }
    }

    /// 退避キューを再送する。全件成功したらキューを空にする。
    public func flushUnsent() {
        let pending = store.loadUnsent()
        guard !pending.isEmpty,
              let url = endpoint("api/narrative-events"),
              let body = try? NarrativeJSON.encoder.encode(pending) else { return }
        post(url: url, body: body) { [store] success in
            guard success else { return }
            store.clearUnsent()
        }
        NSLog("[MFK-Narrative] flushUnsent count=\(pending.count)") // デバッグ: 再送試行
    }

    /// JSON を POST する共通処理。結果は Bool で返すだけで、失敗しても throw しない。
    private func post(url: URL, body: Data, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = error == nil && (200..<300).contains(code)
            NSLog("[MFK-Narrative] post \(url.lastPathComponent) status=\(code) ok=\(success)") // デバッグ: 送信結果
            completion(success)
        }.resume()
    }
}

/// ローカル（必ず）+ リモート（best-effort）へ流す集約入口。呼び出し側はこれだけ使えばよい。
public final class NarrativeRepositoryHub: NarrativeRepository {

    /// ローカル保存。
    private let local: LocalRepository
    /// リモート送信（URL 未設定なら実質 no-op）。
    private let remote: RemoteRepository

    /// backendBaseURL は NarrativeState.backendBaseURL を渡す想定。
    public init(baseURL: String, store: NarrativeStore = NarrativeStore()) {
        self.local = LocalRepository(store: store)
        self.remote = RemoteRepository(baseURL: baseURL, store: store)
    }

    public func save(_ event: NarrativeEvent) {
        local.save(event)
        remote.save(event)
    }

    public func saveContext(_ event: ContextEvent) {
        local.saveContext(event)
        remote.saveContext(event)
    }

    /// 退避キューの再送（キーボード表示時などに呼ぶ）。
    public func flushUnsent() {
        remote.flushUnsent()
    }
}
