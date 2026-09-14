// QuestionTrigger.swift
// MozcFlickKeyboard — 追加: 文脈から「どの質問を出すか」を判定する Trigger 群。
//
// 各 Trigger は CurrentContext を受け取り、成立すれば TriggerResult を、しなければ nil を返す純関数的な判定器。
// Phase1 有効: Morning / NightReflection / Outing / ReturnHome。
// Phase2 は enabled フラグで無効化して同梱: LongSession / TypingFatigue。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

// MARK: - プロトコル

/// 追加: 文脈を評価し、成立時に TriggerResult を返す判定器。
public protocol QuestionTrigger {
    /// 追加: 成立すれば TriggerResult、しなければ nil。
    func evaluate(context: CurrentContext) -> TriggerResult?
}

// MARK: - Phase1 有効 Trigger

/// 追加: 朝トリガー。当日初回のキーボード利用かつ 06:00-10:59 なら morningMood を出す。
public final class MorningTrigger: QuestionTrigger {
    /// 追加: 時刻の「時」を取り出すためのカレンダー。
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func evaluate(context: CurrentContext) -> TriggerResult? {
        // 追加: 当日初回でなければ発火しない。
        guard context.isFirstKeyboardUseToday else { return nil }
        // 追加: 朝の時間帯（NarrativeConfig.morningHours）外なら発火しない。
        let hour = calendar.component(.hour, from: context.now)
        guard NarrativeConfig.morningHours.contains(hour) else { return nil }
        return TriggerResult(kind: .morningMood, eventType: "wake_up", externalTrigger: nil)
    }
}

/// 追加: 夜の振り返りトリガー。夜の時間帯（21:00-翌02:00）か、手動「寝る」があれば nightReflection を出す。
public final class NightReflectionTrigger: QuestionTrigger {
    /// 追加: 時刻の「時」を取り出すためのカレンダー。
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func evaluate(context: CurrentContext) -> TriggerResult? {
        // 追加: 手動「寝る」イベントがあれば時刻に関係なく発火。
        if context.manualEvents.contains(.sleep) {
            return TriggerResult(kind: .nightReflection, eventType: "night_reflection", externalTrigger: nil)
        }
        // 追加: 夜窓は日付をまたぐ（>= 21時 もしくは <= 2時）。
        let hour = calendar.component(.hour, from: context.now)
        let inNight = hour >= NarrativeConfig.nightStartHour || hour <= NarrativeConfig.nightEndHour
        guard inNight else { return nil }
        return TriggerResult(kind: .nightReflection, eventType: "night_reflection", externalTrigger: nil)
    }
}

/// 追加: 外出トリガー。手動「外出した」があれば outingDestination を出す。
public final class OutingTrigger: QuestionTrigger {
    public init() {}

    public func evaluate(context: CurrentContext) -> TriggerResult? {
        // 追加: 手動「外出した」が積まれていれば発火。
        guard context.manualEvents.contains(.outing) else { return nil }
        return TriggerResult(kind: .outingDestination, eventType: "outing", externalTrigger: "manual_outing")
    }
}

/// 追加: 帰宅トリガー。手動「帰宅した」があれば outingEvaluation を出す。
public final class ReturnHomeTrigger: QuestionTrigger {
    public init() {}

    public func evaluate(context: CurrentContext) -> TriggerResult? {
        // 追加: 手動「帰宅した」が積まれていれば発火。
        guard context.manualEvents.contains(.returnHome) else { return nil }
        return TriggerResult(kind: .outingEvaluation, eventType: "return_home", externalTrigger: "manual_return_home")
    }
}

// MARK: - Phase2 同梱（既定は無効）

/// 追加: 長時間セッショントリガー（Phase2）。既定は enabled=false で発火しない。
public final class LongSessionTrigger: QuestionTrigger {
    /// 追加: Phase2 で有効化するフラグ。既定は無効。
    public var enabled = false

    public init() {}

    public func evaluate(context: CurrentContext) -> TriggerResult? {
        // 追加: Phase2 まで無効。
        guard enabled else { return nil }
        // 追加: セッション継続時間が連続入力閾値を超えたら workState を出す。
        guard let duration = context.typing?.sessionDurationSec,
              duration >= NarrativeConfig.continuousTypingThreshold else { return nil }
        return TriggerResult(kind: .workState, eventType: "long_session", externalTrigger: nil)
    }
}

/// 追加: 打鍵疲労トリガー（Phase2）。既定は enabled=false。baseline と現在の打鍵特徴を比較する。
public final class TypingFatigueTrigger: QuestionTrigger {
    /// 追加: Phase2 で有効化するフラグ。既定は無効。
    public var enabled = false
    /// 追加: 比較基準となる打鍵ベースライン（NarrativeState.typingBaseline() を注入）。
    private let baseline: TypingFeatures?

    public init(baseline: TypingFeatures?) {
        self.baseline = baseline
    }

    public func evaluate(context: CurrentContext) -> TriggerResult? {
        // 追加: Phase2 まで無効。
        guard enabled else { return nil }
        // 追加: 現在特徴・ベースラインの両方が揃っている時だけ判定。
        guard let current = context.typing, let baseline else { return nil }
        // 追加: TypingMetrics.deviation の単純ルール（速度低下 / backspace 増 / ポーズ増）で乖離を判定。
        guard TypingMetrics.deviation(current: current, baseline: baseline) else { return nil }
        return TriggerResult(kind: .fatigueCheck, eventType: "typing_fatigue", externalTrigger: nil)
    }
}
