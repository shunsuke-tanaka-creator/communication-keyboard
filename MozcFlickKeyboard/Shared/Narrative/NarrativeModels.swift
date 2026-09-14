// NarrativeModels.swift
// MozcFlickKeyboard — 追加: 「お天気分」micro-diary のデータモデル一式。
//
// Context → Trigger → Question → Answer → NarrativeEvent の各段で受け渡す型をここへ集約する。
// すべて Codable。保存 JSON のキーは研究ログ仕様に合わせ snake_case（CodingKeys で明示）。
// Shared は framework ターゲット MozcFlickShared なので、外部公開する型・メンバは全て public。

import Foundation

// MARK: - 質問種別

/// 質問の種別。JSON の question.kind としてそのまま保存される安定ラベル。
public enum QuestionKind: String, Codable, CaseIterable {
    /// 朝の気分（当日初回キーボード表示・06:00-10:00）
    case morningMood
    /// 今日の目標（朝、morningMood の後）
    case morningGoal
    /// 夜の振り返り（21:00-翌02:00）
    case nightReflection
    /// 外出先（手動イベント「外出した」由来）
    case outingDestination
    /// 外出の評価（手動イベント「帰宅した」由来）
    case outingEvaluation
    /// 作業状態（長時間入力セッション由来 / Phase2）
    case workState
    /// 疲労確認（打鍵特徴の乖離由来 / Phase2）
    case fatigueCheck
    /// 休憩提案の受け入れ確認（Phase2）
    case breakCheck
    /// 自由記述の想起質問
    case freeNarrative
    /// 介入（提案）に対するフィードバック
    case interventionFeedback
}

// MARK: - 質問テンプレート

/// 質問1件の定義。文言・選択肢・出題制約を1箇所に集約する（ベタ書き禁止要件への対応）。
public struct QuestionTemplate: Codable {
    /// 質問種別。
    public let kind: QuestionKind
    /// 画面に出す日本語の質問文。
    public let prompt: String
    /// 選択肢（表示ラベルと研究用の安定値のペア）。
    public let options: [QuestionOption]
    /// 自由記述を許可するか。
    public let allowFreeText: Bool
    /// 同一種別を再出題できるまでの最短間隔（秒）。0 なら間隔制約なし。
    public let cooldown: TimeInterval
    /// 1日あたりの最大出題回数。
    public let maxPerDay: Int

    public init(kind: QuestionKind,
                prompt: String,
                options: [QuestionOption],
                allowFreeText: Bool,
                cooldown: TimeInterval,
                maxPerDay: Int) {
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.allowFreeText = allowFreeText
        self.cooldown = cooldown
        self.maxPerDay = maxPerDay
    }
}

/// 選択肢1件。表示と保存値を分離する。
/// label は UI に出す日本語（例「少し疲れた」）、value は保存 JSON に入る英語 snake_case（例 slightly_tired）。
public struct QuestionOption: Codable {
    /// UI 表示用の日本語ラベル。
    public let label: String
    /// 研究ログへ保存する安定値（snake_case 英語）。
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

// MARK: - 出題中の質問

/// 出題が決まった質問1件。バナー表示〜回答保存まで持ち回す。
public struct PendingQuestion: Codable {
    /// 一意 ID（UUID 文字列）。NarrativeEvent の event_id にそのまま使う。
    public let id: String
    /// 被験者 ID。
    public let participantID: String
    /// 質問種別。
    public let kind: QuestionKind
    /// 表示する質問文。
    public let prompt: String
    /// 表示する選択肢。
    public let options: [QuestionOption]
    /// 自由記述を許可するか。
    public let allowFreeText: Bool
    /// この質問を生んだイベント種別（morning_first_use / outing など）。
    public let eventType: String
    /// トリガーが成立した時刻。
    public let detectedAt: Date
    /// 実際にバナーへ表示した時刻（未表示なら nil）。
    public var questionShownAt: Date?
    /// 「あとで」を押された回数。
    public var snoozeCount: Int
    /// 出題時点の文脈スナップショット。
    public let context: ContextSnapshot

    public init(id: String = UUID().uuidString,
                participantID: String,
                kind: QuestionKind,
                prompt: String,
                options: [QuestionOption],
                allowFreeText: Bool,
                eventType: String,
                detectedAt: Date,
                questionShownAt: Date? = nil,
                snoozeCount: Int = 0,
                context: ContextSnapshot) {
        self.id = id
        self.participantID = participantID
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.allowFreeText = allowFreeText
        self.eventType = eventType
        self.detectedAt = detectedAt
        self.questionShownAt = questionShownAt
        self.snoozeCount = snoozeCount
        self.context = context
    }
}

// MARK: - 文脈

/// 出題時点の文脈。保存 JSON の context ブロックに対応する。
public struct ContextSnapshot: Codable {
    /// "morning" / "afternoon" / "evening" / "night"
    public let timeOfDay: String
    /// 直近に入力操作があったか。
    public let typingActive: Bool
    /// カレンダー上で多忙か（Phase1 は stub で常に false）。
    public let calendarBusy: Bool
    /// 外部トリガー名（manual_outing / switchbot_door など）。無ければ nil。
    public let externalTrigger: String?

    public init(timeOfDay: String,
                typingActive: Bool,
                calendarBusy: Bool,
                externalTrigger: String?) {
        self.timeOfDay = timeOfDay
        self.typingActive = typingActive
        self.calendarBusy = calendarBusy
        self.externalTrigger = externalTrigger
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case timeOfDay = "time_of_day"
        case typingActive = "typing_active"
        case calendarBusy = "calendar_busy"
        case externalTrigger = "external_trigger"
    }
}

// MARK: - 打鍵特徴

/// 打鍵から算出する特徴量。本文は一切含めず、時刻と回数のみ。
public struct TypingFeatures: Codable {
    /// 打鍵速度（characters per minute）。
    public let typingSpeedCPM: Double?
    /// 総打鍵数に対する backspace の比率。
    public let backspaceRate: Double?
    /// 平均キー間隔（ミリ秒）。
    public let meanKeyIntervalMS: Double?
    /// セッション継続時間（秒）。
    public let sessionDurationSec: Double?
    /// backspace 回数。
    public let backspaceCount: Int?
    /// 入力文字数（本文は保存しない）。
    public let totalTypedCharacters: Int?
    /// ポーズ（一定時間以上の無操作）回数。
    public let pauseCount: Int?
    /// 最長ポーズの長さ（秒）。
    public let longPauseDurationSec: Double?

    public init(typingSpeedCPM: Double? = nil,
                backspaceRate: Double? = nil,
                meanKeyIntervalMS: Double? = nil,
                sessionDurationSec: Double? = nil,
                backspaceCount: Int? = nil,
                totalTypedCharacters: Int? = nil,
                pauseCount: Int? = nil,
                longPauseDurationSec: Double? = nil) {
        self.typingSpeedCPM = typingSpeedCPM
        self.backspaceRate = backspaceRate
        self.meanKeyIntervalMS = meanKeyIntervalMS
        self.sessionDurationSec = sessionDurationSec
        self.backspaceCount = backspaceCount
        self.totalTypedCharacters = totalTypedCharacters
        self.pauseCount = pauseCount
        self.longPauseDurationSec = longPauseDurationSec
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case typingSpeedCPM = "typing_speed_cpm"
        case backspaceRate = "backspace_rate"
        case meanKeyIntervalMS = "mean_key_interval_ms"
        case sessionDurationSec = "session_duration_sec"
        case backspaceCount = "backspace_count"
        case totalTypedCharacters = "total_typed_characters"
        case pauseCount = "pause_count"
        case longPauseDurationSec = "long_pause_duration_sec"
    }
}

// MARK: - 回答

/// 質問への回答。選択肢と自由記述の両方を持てる。
public struct QuestionAnswer: Codable {
    /// 選択された選択肢の value（snake_case 英語）。未選択なら nil。
    public let label: String?
    /// 自由記述の本文。無ければ nil。
    public let freeText: String?

    public init(label: String? = nil, freeText: String? = nil) {
        self.label = label
        self.freeText = freeText
    }

    /// 保存 JSON のキーは label / free_text。
    public enum CodingKeys: String, CodingKey {
        case label
        case freeText = "free_text"
    }
}

// MARK: - 文脈イベント（質問を伴わない記録）

/// 質問を伴わない文脈イベント（起床・外出検知など）。context_yyyyMMdd.jsonl へ保存する。
public struct ContextEvent: Codable {
    /// 一意 ID。
    public let eventID: String
    /// 被験者 ID。
    public let participantID: String
    /// イベント種別（wake_up / outing / return_home など）。
    public let eventType: String
    /// 検知時刻。
    public let detectedAt: Date
    /// 発生元（keyboard / parent_app）。
    public let source: String
    /// 検知時点の文脈。
    public let context: ContextSnapshot
    /// 打鍵特徴（あれば）。
    public let typing: TypingFeatures?

    public init(eventID: String = UUID().uuidString,
                participantID: String,
                eventType: String,
                detectedAt: Date,
                source: String,
                context: ContextSnapshot,
                typing: TypingFeatures? = nil) {
        self.eventID = eventID
        self.participantID = participantID
        self.eventType = eventType
        self.detectedAt = detectedAt
        self.source = source
        self.context = context
        self.typing = typing
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case participantID = "participant_id"
        case eventType = "event_type"
        case detectedAt = "detected_at"
        case source
        case context
        case typing
    }
}

// MARK: - PMTT 連携

/// PMTT（行動遷移モデル）側のノード情報。NarrativeEvent に埋め込む。
public struct PMTTContext: Codable {
    /// ノード ID（例 weekday_afternoon_desk_work）。
    public let nodeID: String?
    /// 状態ラベル。
    public let stateLabel: String?
    /// 遷移 ID。
    public let transitionID: String?

    public init(nodeID: String? = nil, stateLabel: String? = nil, transitionID: String? = nil) {
        self.nodeID = nodeID
        self.stateLabel = stateLabel
        self.transitionID = transitionID
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case stateLabel = "state_label"
        case transitionID = "transition_id"
    }
}

/// NarrativeEvent と PMTT ノードの対応付け1件（PMTT 側から参照する用）。
public struct PMTTLink: Codable {
    /// 対応する NarrativeEvent の event_id。
    public let eventID: String
    /// ノード ID。
    public let nodeID: String?
    /// 状態ラベル。
    public let stateLabel: String?
    /// 遷移 ID。
    public let transitionID: String?

    public init(eventID: String, nodeID: String? = nil, stateLabel: String? = nil, transitionID: String? = nil) {
        self.eventID = eventID
        self.nodeID = nodeID
        self.stateLabel = stateLabel
        self.transitionID = transitionID
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case nodeID = "node_id"
        case stateLabel = "state_label"
        case transitionID = "transition_id"
    }
}

// MARK: - 解析結果

/// NarrativeAnalyzer の出力。Phase1 は Mock がルールで埋める。
public struct NarrativeAnalysis: Codable {
    /// 感情ラベル（positive / neutral / negative など）。
    public let emotion: String?
    /// 経験タイプ（work / rest / social など）。
    public let experienceType: String?
    /// 文埋め込み（Phase1 は nil）。
    public let embedding: [Float]?

    public init(emotion: String? = nil, experienceType: String? = nil, embedding: [Float]? = nil) {
        self.emotion = emotion
        self.experienceType = experienceType
        self.embedding = embedding
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case emotion
        case experienceType = "experience_type"
        case embedding
    }
}

// MARK: - 介入

/// 介入（提案）1件の記録。
public struct InterventionEvent: Codable {
    /// 一意 ID。
    public let id: String
    /// 被験者 ID。
    public let participantID: String
    /// 契機となった NarrativeEvent の event_id。
    public let narrativeEventID: String
    /// 介入種別（break_suggestion など）。
    public let kind: String
    /// 結果（accepted / declined / ignored）。未確定なら nil。
    public let outcome: String?
    /// 生成時刻。
    public let createdAt: Date

    public init(id: String = UUID().uuidString,
                participantID: String,
                narrativeEventID: String,
                kind: String,
                outcome: String? = nil,
                createdAt: Date) {
        self.id = id
        self.participantID = participantID
        self.narrativeEventID = narrativeEventID
        self.kind = kind
        self.outcome = outcome
        self.createdAt = createdAt
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case id
        case participantID = "participant_id"
        case narrativeEventID = "narrative_event_id"
        case kind
        case outcome
        case createdAt = "created_at"
    }
}

// MARK: - NarrativeEvent（保存の中心）

/// 回答済みの micro-diary 1件。narrative_yyyyMMdd.jsonl の1行に対応する。
/// JSON 形状は研究ログ仕様どおり（question / answer / narrative をネストさせる）。
public struct NarrativeEvent: Codable {

    /// question ブロック（質問種別と文言）。
    public struct Question: Codable {
        /// 質問種別。
        public let kind: QuestionKind
        /// 出題した日本語の質問文。
        public let prompt: String

        public init(kind: QuestionKind, prompt: String) {
            self.kind = kind
            self.prompt = prompt
        }
    }

    /// narrative ブロック（要約と解析結果）。
    public struct Narrative: Codable {
        /// 回答から作る短い要約テキスト。
        public let summary: String?
        /// 感情ラベル（Analyzer が埋める）。
        public let emotion: String?
        /// 経験タイプ（Analyzer が埋める）。
        public let experienceType: String?

        public init(summary: String? = nil, emotion: String? = nil, experienceType: String? = nil) {
            self.summary = summary
            self.emotion = emotion
            self.experienceType = experienceType
        }

        /// 保存 JSON のキーは snake_case にする。
        public enum CodingKeys: String, CodingKey {
            case summary
            case emotion
            case experienceType = "experience_type"
        }
    }

    /// 一意 ID（PendingQuestion.id を引き継ぐ）。
    public let eventID: String
    /// 被験者 ID。
    public let participantID: String
    /// 発生元。"keyboard" または "parent_app"。
    public let source: String
    /// この回答を生んだイベント種別。
    public let eventType: String
    /// トリガー成立時刻。
    public let detectedAt: Date
    /// 質問を表示した時刻。
    public let questionShownAt: Date?
    /// 回答時刻。
    public let answeredAt: Date?
    /// 文脈スナップショット。
    public let context: ContextSnapshot
    /// 質問ブロック。
    public let question: Question
    /// 回答ブロック。
    public let answer: QuestionAnswer
    /// 要約・解析ブロック。
    public var narrative: Narrative?
    /// 打鍵特徴（あれば）。
    public let typing: TypingFeatures?
    /// PMTT ノード情報（あれば）。
    public var pmtt: PMTTContext?
    /// 「あとで」を押された回数。
    public let snoozeCount: Int

    public init(eventID: String,
                participantID: String,
                source: String,
                eventType: String,
                detectedAt: Date,
                questionShownAt: Date?,
                answeredAt: Date?,
                context: ContextSnapshot,
                question: Question,
                answer: QuestionAnswer,
                narrative: Narrative? = nil,
                typing: TypingFeatures? = nil,
                pmtt: PMTTContext? = nil,
                snoozeCount: Int = 0) {
        self.eventID = eventID
        self.participantID = participantID
        self.source = source
        self.eventType = eventType
        self.detectedAt = detectedAt
        self.questionShownAt = questionShownAt
        self.answeredAt = answeredAt
        self.context = context
        self.question = question
        self.answer = answer
        self.narrative = narrative
        self.typing = typing
        self.pmtt = pmtt
        self.snoozeCount = snoozeCount
    }

    /// 保存 JSON のキーは snake_case にする。
    public enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case participantID = "participant_id"
        case source
        case eventType = "event_type"
        case detectedAt = "detected_at"
        case questionShownAt = "question_shown_at"
        case answeredAt = "answered_at"
        case context
        case question
        case answer
        case narrative
        case typing
        case pmtt
        case snoozeCount = "snooze_count"
    }

    /// PendingQuestion + 回答から NarrativeEvent を組み立てる簡易ファクトリ。
    /// source は "keyboard" 固定（親アプリから作る場合は init を直接使う）。
    /// summary は「選択肢ラベル + 自由記述」を連結した最小の要約にする。
    public static func make(from pending: PendingQuestion,
                           answer: QuestionAnswer,
                           typing: TypingFeatures?,
                           answeredAt: Date) -> NarrativeEvent {
        // 要約: 選択肢 value と自由記述を空白区切りで連結（どちらも無ければ nil）
        let parts = [answer.label, answer.freeText].compactMap { $0 }.filter { !$0.isEmpty }
        let summary = parts.isEmpty ? nil : parts.joined(separator: " / ")
        return NarrativeEvent(eventID: pending.id,
                              participantID: pending.participantID,
                              source: "keyboard",
                              eventType: pending.eventType,
                              detectedAt: pending.detectedAt,
                              questionShownAt: pending.questionShownAt,
                              answeredAt: answeredAt,
                              context: pending.context,
                              question: Question(kind: pending.kind, prompt: pending.prompt),
                              answer: answer,
                              narrative: Narrative(summary: summary),
                              typing: typing,
                              pmtt: nil,
                              snoozeCount: pending.snoozeCount)
    }
}

// MARK: - 手動イベント

/// キーボード最下部「記録」ボタンから登録できる手動イベント。
/// rawValue は保存 JSON の event_type としてそのまま使う。
public enum ManualEvent: String, Codable, CaseIterable {
    /// 起床
    case wakeUp = "wake_up"
    /// 外出
    case outing
    /// 帰宅
    case returnHome = "return_home"
    /// 就寝
    case sleep

    /// バナーのボタンに出す日本語ラベル。
    public var displayName: String {
        switch self {
        case .wakeUp: return "起きた"
        case .outing: return "外出した"
        case .returnHome: return "帰宅した"
        case .sleep: return "寝る"
        }
    }
}

// MARK: - Trigger 入出力

/// Trigger 評価に渡す現在の文脈一式。ContextProvider 群の集約結果。
public struct CurrentContext {
    /// 評価基準時刻（テストで注入する）。
    public let now: Date
    /// 被験者 ID。
    public let participantID: String
    /// 文脈スナップショット。
    public let snapshot: ContextSnapshot
    /// 打鍵特徴（無ければ nil）。
    public let typing: TypingFeatures?
    /// 当日初回のキーボード利用か（朝トリガー用）。
    public let isFirstKeyboardUseToday: Bool
    /// 未処理の手動イベント（発生順）。
    public let manualEvents: [ManualEvent]
    /// 直近入力からの経過秒（無操作判定用）。無ければ nil。
    public let lastInputInterval: TimeInterval?

    public init(now: Date,
                participantID: String,
                snapshot: ContextSnapshot,
                typing: TypingFeatures? = nil,
                isFirstKeyboardUseToday: Bool = false,
                manualEvents: [ManualEvent] = [],
                lastInputInterval: TimeInterval? = nil) {
        self.now = now
        self.participantID = participantID
        self.snapshot = snapshot
        self.typing = typing
        self.isFirstKeyboardUseToday = isFirstKeyboardUseToday
        self.manualEvents = manualEvents
        self.lastInputInterval = lastInputInterval
    }
}

/// Trigger が成立したときの結果。どの質問をどのイベント名で出すかだけを持つ。
public struct TriggerResult {
    /// 出題する質問種別。
    public let kind: QuestionKind
    /// 保存する event_type。
    public let eventType: String
    /// 外部トリガー名（あれば）。
    public let externalTrigger: String?

    public init(kind: QuestionKind, eventType: String, externalTrigger: String? = nil) {
        self.kind = kind
        self.eventType = eventType
        self.externalTrigger = externalTrigger
    }
}

// MARK: - 時間帯判定

/// 時刻 → 時間帯ラベルの変換。ContextSnapshot.timeOfDay に入れる値を一元管理する。
public enum TimeOfDay {
    /// 朝（5-11時）
    public static let morning = "morning"
    /// 昼（11-17時）
    public static let afternoon = "afternoon"
    /// 夕方（17-21時）
    public static let evening = "evening"
    /// 夜（21-5時）
    public static let night = "night"

    /// 「時」の値から時間帯ラベルを返す。
    public static func label(hour: Int) -> String {
        switch hour {
        case 5..<11: return morning
        case 11..<17: return afternoon
        case 17..<21: return evening
        default: return night
        }
    }

    /// Date から時間帯ラベルを返す（端末カレンダー基準）。
    public static func label(for date: Date, calendar: Calendar = .current) -> String {
        label(hour: calendar.component(.hour, from: date))
    }
}

// MARK: - JSON 設定

/// Narrative 系の JSON 入出力設定を一元化する。
/// 日付は SafetyCheckLog と同じ "yyyy-MM-dd'T'HH:mm:ss.SSSZ"（en_US_POSIX）で統一する。
public enum NarrativeJSON {

    /// 日付整形用フォーマッタ（SafetyCheckLog と同一書式）。
    public static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f
    }()

    /// 追記・送信共通のエンコーダ。
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .formatted(dateFormatter)
        return e
    }()

    /// 読み出し共通のデコーダ。
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .formatted(dateFormatter)
        return d
    }()

    /// 日付を ISO8601(ミリ秒付き)文字列にする（CSV 出力などで使う）。
    public static func string(from date: Date?) -> String {
        guard let date else { return "" }
        return dateFormatter.string(from: date)
    }
}
