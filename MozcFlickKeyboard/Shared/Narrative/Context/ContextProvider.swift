// ContextProvider.swift
// MozcFlickKeyboard — 追加: 文脈の断片（ContextFragment）を提供する Provider 群。
//
// 各 Provider は「自分が知っている文脈の一部」だけを ContextFragment で返し、
// TriggerEngine 側でそれらをマージして CurrentContext を組み立てる。
// すべての値は optional / 空配列を既定にして、マージ時に「知らない項目は上書きしない」を成立させる。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

// MARK: - 文脈断片

/// 追加: Provider 1つが寄与する文脈の断片。未知の項目は nil / 空にしておきマージ時に無視させる。
public struct ContextFragment {
    /// 追加: 直近に入力操作があったか（判らなければ nil）。
    public var typingActive: Bool?
    /// 追加: カレンダー上で多忙か（判らなければ nil）。
    public var calendarBusy: Bool?
    /// 追加: 外部トリガー名（無ければ nil）。
    public var externalTrigger: String?
    /// 追加: 手動イベント（無ければ空）。
    public var manualEvents: [ManualEvent]
    /// 追加: 打鍵特徴（無ければ nil）。
    public var typing: TypingFeatures?

    /// 追加: すべて未知（nil / 空）を既定にして、断片が綺麗にマージできるようにする。
    public init(typingActive: Bool? = nil,
                calendarBusy: Bool? = nil,
                externalTrigger: String? = nil,
                manualEvents: [ManualEvent] = [],
                typing: TypingFeatures? = nil) {
        self.typingActive = typingActive
        self.calendarBusy = calendarBusy
        self.externalTrigger = externalTrigger
        self.manualEvents = manualEvents
        self.typing = typing
    }
}

// MARK: - プロトコル

/// 追加: 現在時刻を基準に文脈の断片を返す Provider。
public protocol ContextProvider {
    /// 追加: now 基準の文脈断片を返す。
    func fragment(now: Date) -> ContextFragment
}

// MARK: - 実装群

/// 追加: 時刻由来の文脈を担う Provider。時間帯は Engine 側で TimeOfDay から導くため、ここでは何も寄与しない。
/// 対称性のために存在させておく（将来「時刻由来のフラグ」を足す余地）。
public final class TimeContextProvider: ContextProvider {
    public init() {}

    /// 追加: 現状は寄与なし（空断片）。
    public func fragment(now: Date) -> ContextFragment {
        ContextFragment()
    }
}

/// 追加: キーボードから渡された打鍵特徴を保持し、typingActive と typing を寄与する Provider。
public final class TypingContextProvider: ContextProvider {
    /// 追加: キーボード側が update(_:) で差し込む最新の打鍵特徴。
    private var features: TypingFeatures?
    /// 追加: 最後に update された時刻（typingActive の recency 判定に使う）。
    private var updatedAt: Date?
    /// 追加: この秒数以内に update があれば typingActive=true とみなす閾値。
    private let activeWindow: TimeInterval

    /// 追加: activeWindow の既定は 60 秒。
    public init(activeWindow: TimeInterval = 60) {
        self.activeWindow = activeWindow
    }

    /// 追加: キーボードが最新の打鍵特徴をセットする。
    public func update(_ features: TypingFeatures?) {
        self.features = features
        self.updatedAt = Date()
    }

    /// 追加: 最新の打鍵特徴と、更新の新しさから typingActive を返す。
    public func fragment(now: Date) -> ContextFragment {
        // 追加: 直近 activeWindow 秒以内に update があれば入力中とみなす。
        let active: Bool?
        if let updatedAt {
            active = now.timeIntervalSince(updatedAt) <= activeWindow
        } else {
            active = nil
        }
        return ContextFragment(typingActive: active, typing: features)
    }
}

/// 追加: カレンダー多忙度を担う Provider。Phase1 は Stub で常に calendarBusy=false。
/// 追加: EventKit 連携（実際の予定取得）は将来拡張。今は権限要求もしない。
public final class CalendarContextProvider: ContextProvider {
    public init() {}

    /// 追加: Stub のため常に「多忙でない」を返す。
    public func fragment(now: Date) -> ContextFragment {
        ContextFragment(calendarBusy: false)
    }
}

/// 追加: SwitchBot 等の外部センサ由来トリガーを担う Provider。Phase1 は寄与なし。
/// 追加: Phase3 でドア開閉から OUT_DOOR / IN_DOOR を externalTrigger として寄与する予定。
public final class SwitchBotContextProvider: ContextProvider {
    public init() {}

    /// 追加: 現状は寄与なし（空断片）。
    public func fragment(now: Date) -> ContextFragment {
        ContextFragment()
    }
}

/// 追加: 手動イベントキューを NarrativeState から読み、ManualEvent を寄与する Provider。
public final class ManualContextProvider: ContextProvider {
    /// 追加: 手動イベントキューを保持している状態ストア。
    private let state: NarrativeState

    /// 追加: 状態ストアを注入する。
    public init(state: NarrativeState) {
        self.state = state
    }

    /// 追加: キューを消費せず覗いて（peek）、溜まっている ManualEvent を発生順で返す。
    /// 追加: 実際の dequeue は KeyboardViewController が記録成功後に行う契約。
    public func fragment(now: Date) -> ContextFragment {
        let events = state.peekManualEvents().map { $0.0 }
        return ContextFragment(manualEvents: events)
    }
}
