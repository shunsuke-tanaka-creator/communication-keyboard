// NarrativeRepository.swift
// MozcFlickKeyboard — 追加: NarrativeEvent / ContextEvent の保存先を抽象化する。
//
// LocalRepository … 常に JSONL へ保存（Phase1 の本体）
// RemoteRepository … 回答・文脈を永続キューに保存し、MacBookへPOSTする。
//                    URL未設定・失敗時はキューに保持し、旧unsent_narrativeも移行する。
// NarrativeRepositoryHub … local + durable remote queue (both must succeed) へ同時に流す唯一の入口。
// 変更: 研究サーバー（MacBook / Tailscale）連携のため、一度削除した送信層を復活させた。
// 永続化の成否をBoolで返す。通信成功とは別の状態。

import Foundation

/// 保存先の共通インターフェース。
public protocol NarrativeRepository {
    /// 回答済み micro-diary を保存する。
    func save(_ event: NarrativeEvent) -> Bool
    /// 質問を伴わない文脈イベントを保存する。
    func saveContext(_ event: ContextEvent) -> Bool
}

/// App Group の JSONL へ保存するローカル実装。
public final class LocalRepository: NarrativeRepository {

    /// 実際の書き込みを担うストア。
    private let store: NarrativeStore

    public init(store: NarrativeStore = NarrativeStore()) {
        self.store = store
    }

    @discardableResult
    public func save(_ event: NarrativeEvent) -> Bool {
        return store.appendNarrative(event)
    }

    @discardableResult
    public func saveContext(_ event: ContextEvent) -> Bool {
        return store.appendContext(event)
    }
}

/// イベントを永続キュー経由でバックエンドへ送る。URL未設定時は端末で保持する。
public final class RemoteRepository {
    private let baseURL: String
    private let store: NarrativeStore
    private let outbox = ResearchEventOutbox()

    public init(baseURL: String, store: NarrativeStore) {
        self.baseURL = baseURL
        self.store = store
    }

    @discardableResult
    public func save(_ event: NarrativeEvent) -> Bool {
        guard outbox.enqueue(event, route: "api/narrative-events", id: event.eventID) else { return false }
        flushUnsent()
        return true
    }

    @discardableResult
    public func saveContext(_ event: ContextEvent) -> Bool {
        guard outbox.enqueue(event, route: "api/context-events", id: event.eventID) else { return false }
        flushUnsent()
        return true
    }

    public func flushUnsent(completion: @escaping (Bool) -> Void = { _ in }) {
        // Migrate legacy failed answers before sending; new writes only use the durable outbox.
        let legacy = store.loadUnsent()
        if !legacy.isEmpty {
            let saved = legacy.map { outbox.enqueue($0, route: "api/narrative-events", id: $0.eventID) }
            if saved.allSatisfy({ $0 }) { store.clearUnsent() }
        }
        outbox.flush(baseURL: baseURL, completion: completion)
    }
}

/// ローカルと永続送信キュー（両方成功が必要）へ流す集約入口。呼び出し側はこれだけ使えばよい。
public final class NarrativeRepositoryHub: NarrativeRepository {

    /// ローカル保存。
    private let local: LocalRepository
    /// リモート送信キュー（URL 未設定でも保持、通信のみ停止）。
    private let remote: RemoteRepository

    /// backendBaseURL は NarrativeState.backendBaseURL を渡す想定。
    public init(baseURL: String, store: NarrativeStore = NarrativeStore()) {
        self.local = LocalRepository(store: store)
        self.remote = RemoteRepository(baseURL: baseURL, store: store)
    }

    @discardableResult
    public func save(_ event: NarrativeEvent) -> Bool {
        guard local.save(event) else { return false }
        return remote.save(event)
    }

    @discardableResult
    public func saveContext(_ event: ContextEvent) -> Bool {
        guard local.saveContext(event) else { return false }
        return remote.saveContext(event)
    }

    /// 退避キューの再送（キーボード表示時などに呼ぶ）。
    public func flushUnsent() {
        remote.flushUnsent()
    }
}
