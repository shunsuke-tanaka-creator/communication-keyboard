// QuestionCatalog.swift
// MozcFlickKeyboard — 追加: 質問文・選択肢・出題制約の定義集（ベタ書き禁止要件への対応）。
//
// すべての QuestionKind に対応する QuestionTemplate をここだけに書く。
// UI（バナー）や Trigger 側は必ず QuestionCatalog.template(for:) を経由して文言を取得する。
// 併せて、出題ロジックのハイパーパラメータを NarrativeConfig に一元化する。

import Foundation

/// 質問テンプレートの定義集。
public enum QuestionCatalog {

    /// 指定種別のテンプレートを返す。
    public static func template(for kind: QuestionKind) -> QuestionTemplate {
        switch kind {
        case .morningMood, .weatherMood:
            return QuestionTemplate(kind: kind, prompt: "今の気分を天気でいうと？",
                options: WeatherMood.allCases.map { QuestionOption(label: $0.label, value: $0.rawValue) },
                allowFreeText: false, cooldown: 3 * 3600, maxPerDay: 1)
        case .currentState:
            return QuestionTemplate(kind: kind, prompt: "今の状態を教えてください",
                options: [QuestionOption(label: "回答を始める", value: "start_current_state")],
                allowFreeText: false, cooldown: 3 * 3600, maxPerDay: 2)
        case .typingReason:
            return QuestionTemplate(kind: kind, prompt: "入力の修正が増えています。主な理由は？",
                options: [("誤入力","mistype"),("文章を考え直した","rewrite"),("変換が合わない","conversion"),("わからない","unknown")].map { QuestionOption(label: $0.0, value: $0.1) },
                allowFreeText: false, cooldown: 3600, maxPerDay: 2)
        case .supportOutcome:
            return QuestionTemplate(kind: kind, prompt: "先ほどの提案はどうでしたか？", options: [], allowFreeText: false, cooldown: 3600, maxPerDay: 2)
        case .morningGoal:
            // 今日の目標: 1日1回、自由記述あり
            return QuestionTemplate(kind: .morningGoal,
                                    prompt: "今日はどんな1日にしたいですか？",
                                    options: [QuestionOption(label: "仕事を進めたい", value: "work"),
                                              QuestionOption(label: "ゆっくりしたい", value: "rest"),
                                              QuestionOption(label: "外出したい", value: "going_out")],
                                    allowFreeText: true,
                                    cooldown: 0,
                                    maxPerDay: 1)
        case .nightReflection:
            // 変更: 夜の振り返りは 5項目×5段階（気分・疲労・ストレス・集中度・眠気）。
            //       この選択肢で開始し、各項目は KeyboardViewController.showCurrentDailyScale が順に出す。
            return QuestionTemplate(kind: .nightReflection,
                                    prompt: "今日の振り返り（5項目・各5段階）に答えますか？",
                                    options: [QuestionOption(label: "振り返りを始める", value: "start_daily_reflection")],
                                    allowFreeText: false,
                                    cooldown: 0,
                                    maxPerDay: 1)
        case .outingDestination:
            // 外出先: 手動イベント「外出した」ごとに出すので1日複数回可
            return QuestionTemplate(kind: .outingDestination,
                                    prompt: "どこへ行きましたか？",
                                    options: [QuestionOption(label: "仕事", value: "work"),
                                              QuestionOption(label: "買い物", value: "shopping"),
                                              QuestionOption(label: "散歩", value: "walk"),
                                              QuestionOption(label: "食事", value: "meal"),
                                              QuestionOption(label: "病院", value: "hospital"),
                                              QuestionOption(label: "その他", value: "other")],
                                    allowFreeText: false,
                                    cooldown: 0,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .outingEvaluation:
            // 外出の評価: 手動イベント「帰宅した」ごと
            return QuestionTemplate(kind: .outingEvaluation,
                                    prompt: "今回の外出はどうでしたか？",
                                    options: [QuestionOption(label: "良かった", value: "good"),
                                              QuestionOption(label: "普通", value: "normal"),
                                              QuestionOption(label: "疲れた", value: "tired"),
                                              QuestionOption(label: "大変だった", value: "difficult")],
                                    allowFreeText: false,
                                    cooldown: 0,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .workState:
            // 作業状態: 長時間入力由来。60分の cooldown を置く（Phase2）
            return QuestionTemplate(kind: .workState,
                                    prompt: "今はどれに近いですか？",
                                    options: [QuestionOption(label: "作業中", value: "working"),
                                              QuestionOption(label: "休憩中", value: "break"),
                                              QuestionOption(label: "疲れた", value: "tired"),
                                              QuestionOption(label: "その他", value: "other")],
                                    allowFreeText: false,
                                    cooldown: NarrativeConfig.fatigueCooldown,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .fatigueCheck:
            // 疲労確認: 打鍵特徴の乖離由来。60分の cooldown（Phase2）
            return QuestionTemplate(kind: .fatigueCheck,
                                    prompt: "少し疲れていますか？",
                                    options: [QuestionOption(label: "はい", value: "yes"),
                                              QuestionOption(label: "いいえ", value: "no")],
                                    allowFreeText: false,
                                    cooldown: NarrativeConfig.fatigueCooldown,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .breakCheck:
            // 休憩提案: 60分の cooldown（Phase2）
            return QuestionTemplate(kind: .breakCheck,
                                    prompt: "少し休憩しますか？",
                                    options: [QuestionOption(label: "する", value: "yes"),
                                              QuestionOption(label: "しない", value: "no")],
                                    allowFreeText: false,
                                    cooldown: NarrativeConfig.fatigueCooldown,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .freeNarrative:
            // 自由記述の想起質問
            return QuestionTemplate(kind: .freeNarrative,
                                    prompt: "印象に残ったことはありますか？",
                                    options: [QuestionOption(label: "仕事", value: "work"),
                                              QuestionOption(label: "家族", value: "family"),
                                              QuestionOption(label: "外出", value: "going_out"),
                                              QuestionOption(label: "食事", value: "meal"),
                                              QuestionOption(label: "その他", value: "other")],
                                    allowFreeText: true,
                                    cooldown: 0,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .interventionFeedback:
            // 介入（提案）に対するフィードバック
            return QuestionTemplate(kind: .interventionFeedback,
                                    prompt: "今の提案は役に立ちましたか？",
                                    options: [QuestionOption(label: "役に立った", value: "helpful"),
                                              QuestionOption(label: "普通", value: "neutral"),
                                              QuestionOption(label: "役に立たなかった", value: "not_helpful")],
                                    allowFreeText: false,
                                    cooldown: 0,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        case .activityCheck:
            // 追加: 現在の主活動。1段目は大分類（value = "category:<大分類>"）、2段目は Keyboard 側で出す。
            return QuestionTemplate(kind: .activityCheck,
                                    prompt: "今は何をしていますか？",
                                    options: ResearchActivityCatalog.categoryOptions,
                                    allowFreeText: false,
                                    cooldown: 0,
                                    maxPerDay: NarrativeConfig.maxQuestionsPerDay)
        }
    }

    /// 全テンプレート（QuestionKind の宣言順）。設定画面や一覧表示で使う。
    public static let all: [QuestionTemplate] = QuestionKind.allCases.map { template(for: $0) }
}

/// 出題ロジックのハイパーパラメータ。計画で確定した値をここだけに書く。
public enum NarrativeConfig {
    /// 1日あたりの最大出題数。
    public static let maxQuestionsPerDay: Int = 4
    /// 朝トリガーの有効時間帯（6:00〜10:59 の「時」）。
    public static let morningHours: ClosedRange<Int> = 6...10
    /// 変更: 夜トリガーの開始「時」（v0.1 仕様で 21:00 → 22:00 以降）。
    public static let nightStartHour: Int = 22
    /// 夜トリガーの終了「時」（翌 02:00 まで）。
    public static let nightEndHour: Int = 2
    /// 「あとで」を押されたときの再表示までの間隔（30分）。
    public static let snoozeInterval: TimeInterval = 30 * 60
    /// 疲労系質問（workState / fatigueCheck / breakCheck）の cooldown（60分）。
    public static let fatigueCooldown: TimeInterval = 60 * 60
    /// 連続入力がこの時間を超えたら長時間セッションとみなす（30分）。
    public static let continuousTypingThreshold: TimeInterval = 30 * 60
    /// 直近60分の累積入力時間がこの値を超えたら長時間セッションとみなす（45分）。
    public static let recentCumulativeThreshold: TimeInterval = 45 * 60
    /// 上記「直近」の対象窓（60分）。
    public static let recentWindow: TimeInterval = 60 * 60
}
