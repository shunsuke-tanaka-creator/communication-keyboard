// QuestionPolicy.swift
// MozcFlickKeyboard — 追加: 「今この質問を出してよいか」を NarrativeState を見て判定するゲート。
//
// TriggerEngine は Trigger が返した種別を canShow(kind:now:) に通し、通ったものだけ出題する。
// 判定要素: 質問機能 ON/OFF / 当日回答済み / 種別 cooldown / 1日上限 / snooze。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

/// 追加: 出題可否を判定するポリシー。ハイパーパラメータは NarrativeConfig を参照する。
public final class QuestionPolicy {
    /// 追加: 判定に使う状態ストア。
    private let state: NarrativeState
    /// 追加: 1日あたりの最大出題数（NarrativeConfig.maxQuestionsPerDay を注入）。
    private let maxQuestionsPerDay: Int

    /// 追加: 状態ストアと上限を注入する。上限の既定は NarrativeConfig の値。
    public init(state: NarrativeState, maxQuestionsPerDay: Int = NarrativeConfig.maxQuestionsPerDay) {
        self.state = state
        self.maxQuestionsPerDay = maxQuestionsPerDay
    }

    /// 追加: 手動イベント由来（外出先 / 外出評価）は外出のたびに新しい事象なので「当日1回」制約を免除する。
    /// 追加: ただし maxPerDay と 1日上限は引き続き尊重する。
    private func isManualKind(_ kind: QuestionKind) -> Bool {
        kind == .outingDestination || kind == .outingEvaluation
    }

    /// 追加: センサー由来で積まれた質問かどうか（pendingKindQueue に載っているか）。
    /// 疑似センサー（玄関開閉・温度など）は「その都度発生した実事象」なので、
    /// 外出/帰宅と同じく「当日1回」制約を免除する。これが無いと
    /// 温度 high を2回注入しても2回目が出ない（実験中の再現ができない）。
    /// なお cooldown（fatigueCheck は60分）と1日上限は引き続き効くため、出しすぎにはならない。
    private func isSensorQueuedKind(_ kind: QuestionKind) -> Bool {
        state.peekPendingKinds().contains { $0.0 == kind }
    }

    /// 追加: 今この種別を出してよいか。すべての制約を満たしたときだけ true。
    public func canShow(kind: QuestionKind, now: Date) -> Bool {
        // 追加: 質問機能が OFF なら一切出さない。
        guard state.narrativeEnabled else { return false }

        let template = QuestionCatalog.template(for: kind)

        // 追加: 1日上限（回答数が上限に達していたら出さない）。
        guard state.answeredCount(on: now) < maxQuestionsPerDay else { return false }

        // 追加: snooze 期限内なら出さない。
        if let until = state.snoozeUntil(kind: kind), now < until { return false }

        // 変更: 手動由来・センサー由来以外は「当日既に回答済みなら出さない」（morningMood 等 maxPerDay=1 の制約もこれで満たす）。
        // 変更: 手動由来（外出先/外出評価）とセンサー由来（pendingKindQueue）は毎回新規事象なので免除し、
        //       種別ごとの回数は cooldown と 1日上限 maxQuestionsPerDay で間接的に抑える。
        if !isManualKind(kind), !isSensorQueuedKind(kind), state.isAnswered(kind: kind, on: now) { return false }

        // 追加: 種別 cooldown（前回表示から template.cooldown 秒経っていなければ出さない）。
        // 注意: センサー由来でも cooldown は免除しない（fatigueCheck は60分）。
        //       これは「質問を出しすぎない」要件を守るため。実験で温度 high を連続注入した場合、
        //       2回目以降は60分経つまで出題されない（キューには残り、cooldown 明けに出る）。
        if template.cooldown > 0, let last = state.lastShown(kind: kind) {
            if now.timeIntervalSince(last) < template.cooldown { return false }
        }

        return true
    }

    // MARK: - 記録ヘルパー（状態ストアへ委譲）

    /// 追加: 表示したことを記録する（cooldown 起点になる）。
    public func recordShown(kind: QuestionKind, now: Date) {
        state.markShown(kind: kind, at: now)
    }

    /// 追加: 回答済みにする（当日回答済み・1日上限のカウントに反映）。
    public func recordAnswered(kind: QuestionKind, now: Date) {
        state.markAnswered(kind: kind, on: now)
    }

    /// 追加: 「あとで」を記録する（snoozeInterval 後まで再表示しない）。
    public func recordSnoozed(kind: QuestionKind, now: Date) {
        state.markSnoozed(kind: kind, until: now.addingTimeInterval(NarrativeConfig.snoozeInterval))
    }
}
