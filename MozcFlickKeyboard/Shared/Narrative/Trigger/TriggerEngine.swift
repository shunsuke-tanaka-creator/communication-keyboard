// TriggerEngine.swift
// MozcFlickKeyboard — 追加: Provider 群のマージ → CurrentContext 生成 → Trigger 評価 → Policy 適用 → PendingQuestion を最大1件返す司令塔。
//
// KeyboardViewController は makeDefault(state:) で組み立て、viewWillAppear などから nextQuestion(...) を呼ぶだけでよい。
// 手動イベントキューはここでは dequeue しない（peek のみ）。回答保存に成功した後で KeyboardViewController が dequeueAllManualEvents() する契約。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

/// 追加: 文脈統合と出題判定の司令塔。
public final class TriggerEngine {
    /// 追加: 出題制御の状態ストア。
    private let state: NarrativeState
    /// 追加: 文脈断片を出す Provider 群。
    private let providers: [ContextProvider]
    /// 追加: 質問判定 Trigger 群（優先順に評価する）。
    private let triggers: [QuestionTrigger]
    /// 追加: 出題可否ゲート。
    private let policy: QuestionPolicy
    /// 追加: 時間帯・時刻判定に使うカレンダー。
    private let calendar: Calendar

    /// 追加: 全依存を注入する。triggers は優先順（先頭優先）で渡す。
    public init(state: NarrativeState,
                providers: [ContextProvider],
                triggers: [QuestionTrigger],
                policy: QuestionPolicy,
                calendar: Calendar = .current) {
        self.state = state
        self.providers = providers
        self.triggers = triggers
        self.policy = policy
        self.calendar = calendar
    }

    /// 追加: Provider 断片をマージして CurrentContext を組み立てる。
    /// 追加: 時間帯は TimeOfDay.label(for:) から導き、typingActive / calendarBusy は断片の非 nil を採用する。
    public func buildContext(now: Date,
                             isFirstKeyboardUseToday: Bool,
                             typing: TypingFeatures?) -> CurrentContext {
        // 追加: 断片を順にマージ（後勝ちだが nil は上書きしない）。
        var typingActive: Bool?
        var calendarBusy: Bool?
        var externalTrigger: String?
        var manualEvents: [ManualEvent] = []
        var mergedTyping: TypingFeatures? = typing
        for provider in providers {
            let f = provider.fragment(now: now)
            if let v = f.typingActive { typingActive = v }
            if let v = f.calendarBusy { calendarBusy = v }
            if let v = f.externalTrigger { externalTrigger = v }
            manualEvents.append(contentsOf: f.manualEvents)
            if let v = f.typing { mergedTyping = v } // 追加: Provider 由来の打鍵特徴があれば優先
        }
        // 追加: ContextSnapshot は必須型のため、未知は安全側（false）に丸める。
        let snapshot = ContextSnapshot(timeOfDay: TimeOfDay.label(for: now, calendar: calendar),
                                       typingActive: typingActive ?? false,
                                       calendarBusy: calendarBusy ?? false,
                                       externalTrigger: externalTrigger)
        return CurrentContext(now: now,
                              participantID: state.participantID,
                              snapshot: snapshot,
                              typing: mergedTyping,
                              isFirstKeyboardUseToday: isFirstKeyboardUseToday,
                              manualEvents: manualEvents,
                              lastInputInterval: nil)
    }

    /// 追加: 出題すべき質問を最大1件返す。無ければ nil。
    /// 追加: 質問機能 OFF なら即 nil。Trigger を優先順に評価し、Policy を通った最初の結果だけを採用する。
    public func nextQuestion(now: Date,
                             isFirstKeyboardUseToday: Bool,
                             typing: TypingFeatures?) -> PendingQuestion? {
        // 追加: 機能 OFF なら何も出さない。
        guard state.narrativeEnabled else { return nil }

        let context = buildContext(now: now,
                                   isFirstKeyboardUseToday: isFirstKeyboardUseToday,
                                   typing: typing)

        // 追加: 優先順に評価し、Policy を通る最初の TriggerResult を1件だけ採用。
        for trigger in triggers {
            guard let result = trigger.evaluate(context: context) else { continue }
            guard policy.canShow(kind: result.kind, now: now) else { continue }
            return makePending(from: result, context: context, now: now)
        }
        return nil
    }

    /// 追加: TriggerResult + 文脈から PendingQuestion を組み立てる。文言は QuestionCatalog から取得。
    private func makePending(from result: TriggerResult,
                             context: CurrentContext,
                             now: Date) -> PendingQuestion {
        let template = QuestionCatalog.template(for: result.kind)
        // 追加: TriggerResult の externalTrigger を snapshot に載せ替えて保存する。
        let snapshot = ContextSnapshot(timeOfDay: context.snapshot.timeOfDay,
                                       typingActive: context.snapshot.typingActive,
                                       calendarBusy: context.snapshot.calendarBusy,
                                       externalTrigger: result.externalTrigger ?? context.snapshot.externalTrigger)
        return PendingQuestion(participantID: context.participantID,
                               kind: result.kind,
                               prompt: template.prompt,
                               options: template.options,
                               allowFreeText: template.allowFreeText,
                               eventType: result.eventType,
                               detectedAt: now,
                               context: snapshot)
    }

    // MARK: - 既定構成

    /// 追加: 5 Provider + Phase1 有効 4 Trigger（+ Phase2 の 2 Trigger は無効同梱）+ 既定 Policy を1発で組む。
    /// 追加: KeyboardViewController はこれを呼ぶだけで TriggerEngine を得られる。
    public static func makeDefault(state: NarrativeState, calendar: Calendar = .current) -> TriggerEngine {
        // 追加: Provider 群（Time / Typing / Calendar(stub) / SwitchBot(stub) / Manual）。
        let providers: [ContextProvider] = [
            TimeContextProvider(),
            TypingContextProvider(),
            CalendarContextProvider(),
            SwitchBotContextProvider(),
            ManualContextProvider(state: state)
        ]
        // 追加: 優先順は「手動 外出/帰宅 > 朝 > 夜 > 疲労/セッション」。
        let longSession = LongSessionTrigger()   // 追加: Phase2（既定 enabled=false）
        let fatigue = TypingFatigueTrigger(baseline: state.typingBaseline()) // 追加: Phase2（既定 enabled=false）
        let triggers: [QuestionTrigger] = [
            OutingTrigger(),
            ReturnHomeTrigger(),
            MorningTrigger(calendar: calendar),
            NightReflectionTrigger(calendar: calendar),
            fatigue,
            longSession
        ]
        let policy = QuestionPolicy(state: state)
        return TriggerEngine(state: state,
                             providers: providers,
                             triggers: triggers,
                             policy: policy,
                             calendar: calendar)
    }
}
