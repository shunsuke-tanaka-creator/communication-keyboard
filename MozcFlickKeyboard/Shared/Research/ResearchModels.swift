// ResearchModels.swift
// MozcFlickKeyboard — 変更: 研究サーバー（MacBook / Tailscale、既定 http://100.106.185.3:8000）とやり取りするモデル一式。
//
// - ResearchSessionUpload … POST /api/sessions の body（1分セッション単位の生ログ + 打鍵特徴 + 端末Context）
// - ResearchDeviceContext … 親アプリが集めた端末Context（HealthKit / カレンダー / バッテリー / センサー最新値）
// - ResearchSensorEvent   … POST /api/sensor-events の body
// - ResearchContextStore  … 端末UUIDと最新Contextを App Group で共有する（親アプリが書き、キーボードが読む）
// - ResearchActivityCatalog … 活動質問（大分類→詳細活動の2段階）の定義
// 日付は NarrativeJSON（yyyy-MM-dd'T'HH:mm:ss.SSSZ）で入出力する。

import Foundation

// MARK: - セッション送信

/// 追加: POST /api/sessions の body。同じ session_id の再送はサーバー側で冪等に扱われる。
public struct ResearchSessionUpload: Codable {
    public let sessionID: String
    public let participantID: String
    public let deviceID: String
    public let startedAt: Date
    public let endedAt: Date
    public let closeReason: String
    public let events: [SessionEvent]
    public let typing: TypingFeatures
    public let context: ResearchDeviceContext?

    public init(sessionID: String,
                participantID: String,
                deviceID: String,
                startedAt: Date,
                endedAt: Date,
                closeReason: String,
                events: [SessionEvent],
                typing: TypingFeatures,
                context: ResearchDeviceContext?) {
        self.sessionID = sessionID
        self.participantID = participantID
        self.deviceID = deviceID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.closeReason = closeReason
        self.events = events
        self.typing = typing
        self.context = context
    }

    public enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case participantID = "participant_id"
        case deviceID = "device_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case closeReason = "close_reason"
        case events
        case typing
        case context
    }
}

// MARK: - 端末Context

/// 追加: カレンダー予定1件（タイトルと時刻）。
public struct ResearchCalendarEvent: Codable {
    public let title: String
    public let start: Date
    public let end: Date

    public init(title: String, start: Date, end: Date) {
        self.title = title
        self.start = start
        self.end = end
    }
}

/// 追加: 親アプリが集めた端末Context。取れなかった項目は nil のまま送る。
public struct ResearchDeviceContext: Codable {
    public var stepCount: Double?
    public var walkingDistanceM: Double?
    public var flightsClimbed: Double?        // 追加: 今日登った階段（階）
    public var walkingSpeedMps: Double?       // 追加: 歩行速度（m/s、直近1時間平均）
    public var walkingStepLengthM: Double?    // 追加: 歩幅（m、直近1時間平均）
    public var walkingAsymmetryPct: Double?   // 追加: 歩行非対称性（%、直近1時間平均）
    public var activeEnergyKcal: Double?       // 追加: 活動エネルギー量推定値（kcal）
    public var calendarEvents: [ResearchCalendarEvent]?
    public var batteryLevel: Double?
    public var batteryState: String?
    public var doorOpen: Bool?
    public var livingPresence: Bool?
    public var temperature: String?
    public var measurementUpdatedAt: [String: Date]? = [:]
    public var updatedAt: Date?

    public init() {}

    public enum CodingKeys: String, CodingKey {
        case stepCount = "step_count"
        case walkingDistanceM = "walking_distance_m"
        case flightsClimbed = "flights_climbed"             // 追加
        case walkingSpeedMps = "walking_speed_mps"          // 追加
        case walkingStepLengthM = "walking_step_length_m"   // 追加
        case walkingAsymmetryPct = "walking_asymmetry_pct"  // 追加
        case activeEnergyKcal = "active_energy_kcal"        // 追加
        case calendarEvents = "calendar_events"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case doorOpen = "door_open"
        case livingPresence = "living_presence"
        case temperature
        case measurementUpdatedAt = "measurement_updated_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - センサー送信

/// 追加: POST /api/sensor-events の body。SensorEvent（疑似センサー）と同じ type / value を送る。
public struct ResearchSensorEvent: Codable {
    public let participantID: String
    public let deviceID: String
    public let type: String
    public let value: String?
    public let occurredAt: Date

    public init(participantID: String, deviceID: String, type: String, value: String?, occurredAt: Date) {
        self.participantID = participantID
        self.deviceID = deviceID
        self.type = type
        self.value = value
        self.occurredAt = occurredAt
    }

    public enum CodingKeys: String, CodingKey {
        case participantID = "participant_id"
        case deviceID = "device_id"
        case type
        case value
        case occurredAt = "occurred_at"
    }
}

// MARK: - 端末ID・最新Contextの共有ストア

/// 追加: App Group UserDefaults に端末UUIDと最新Contextを置く。親アプリが書き、キーボードが送信時に読む。
public final class ResearchContextStore {

    private static let deviceIDKey = "research.deviceID"
    private static let contextKey = "research.deviceContext"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupID)) {
        self.defaults = defaults
    }

    /// 追加: 端末UUID。初回アクセス時に生成して保存する。
    public var deviceID: String {
        if let id = defaults?.string(forKey: Self.deviceIDKey) { return id }
        let id = UUID().uuidString
        defaults?.set(id, forKey: Self.deviceIDKey)
        return id
    }

    /// 追加: 最新Context（未保存なら nil）。
    public func load() -> ResearchDeviceContext? {
        guard let data = defaults?.data(forKey: Self.contextKey) else { return nil }
        return try? NarrativeJSON.decoder.decode(ResearchDeviceContext.self, from: data)
    }

    /// 追加: 最新Contextを読み→変更→保存する。updatedAt は自動で更新する。
    public func update(_ change: (inout ResearchDeviceContext) -> Void) {
        var context = load() ?? ResearchDeviceContext()
        change(&context)
        context.updatedAt = Date()
        guard let data = try? NarrativeJSON.encoder.encode(context) else { return }
        defaults?.set(data, forKey: Self.contextKey)
        NSLog("[MFK-Research] context updated steps=\(context.stepCount ?? -1) battery=\(context.batteryLevel ?? -1) door=\(String(describing: context.doorOpen))") // 追加: デバッグ
    }

    /// 追加: センサーイベントの最新値を Context に反映する（door_open / living_presence / temperature）。
    public func applySensor(type: String, value: String?) {
        update { context in
            switch type {
            case "door_open": context.doorOpen = true
            case "door_close": context.doorOpen = false
            case "living_presence": context.livingPresence = (value == "present")
            case "temperature": context.temperature = value
            default: break
            }
        }
    }
}

// MARK: - 活動カタログ（大分類→詳細活動）

/// 追加: 詳細活動1件。
public struct ResearchActivity {
    public let value: String
    public let label: String

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    /// 追加: バナーの選択肢へ変換する（value がそのまま answer.label に入る）。
    public var questionOption: QuestionOption { QuestionOption(label: label, value: value) }
}

/// 追加: 活動の大分類1件。
public struct ResearchActivityCategory {
    public let value: String
    public let label: String
    public let activities: [ResearchActivity]

    public init(value: String, label: String, activities: [ResearchActivity]) {
        self.value = value
        self.label = label
        self.activities = activities
    }
}

/// 追加: 現在の主活動を聞く2段階質問の定義。
public enum ResearchActivityCatalog {

    /// 追加: 大分類の一覧。
    public static let categories: [ResearchActivityCategory] = [
        ResearchActivityCategory(value: "work", label: "仕事・勉強", activities: [
            ResearchActivity(value: "desk_work", label: "デスクワーク"),
            ResearchActivity(value: "meeting", label: "会議・打合せ"),
            ResearchActivity(value: "study", label: "勉強・研究"),
        ]),
        ResearchActivityCategory(value: "housework", label: "家事", activities: [
            ResearchActivity(value: "cooking", label: "料理"),
            ResearchActivity(value: "cleaning", label: "掃除"),
            ResearchActivity(value: "laundry", label: "洗濯"),
            ResearchActivity(value: "shopping", label: "買い物"),
        ]),
        ResearchActivityCategory(value: "self_care", label: "身の回り", activities: [
            ResearchActivity(value: "meal", label: "食事"),
            ResearchActivity(value: "bath", label: "入浴"),
            ResearchActivity(value: "toilet", label: "トイレ"),
            ResearchActivity(value: "dressing", label: "身支度"),
        ]),
        ResearchActivityCategory(value: "rest", label: "休息", activities: [
            ResearchActivity(value: "relax", label: "くつろぎ"),
            ResearchActivity(value: "nap", label: "仮眠"),
            ResearchActivity(value: "sleep_prep", label: "就寝準備"),
        ]),
        ResearchActivityCategory(value: "leisure", label: "趣味・娯楽", activities: [
            ResearchActivity(value: "video", label: "テレビ・動画"),
            ResearchActivity(value: "game", label: "ゲーム"),
            ResearchActivity(value: "reading", label: "読書"),
            ResearchActivity(value: "sns", label: "スマホ・SNS"),
        ]),
        ResearchActivityCategory(value: "move", label: "移動・外出", activities: [
            ResearchActivity(value: "walk", label: "散歩"),
            ResearchActivity(value: "commute", label: "通勤・通学"),
            ResearchActivity(value: "errand", label: "用事"),
        ]),
        ResearchActivityCategory(value: "social", label: "人と過ごす", activities: [
            ResearchActivity(value: "family", label: "家族と"),
            ResearchActivity(value: "friends", label: "友人と"),
            ResearchActivity(value: "call", label: "通話"),
        ]),
    ]

    /// 追加: 自由入力へ進む「その他」の value（KeyboardViewController が判定する）。
    public static let otherFreeTextValue = "activity_other_free_text"

    /// 追加: value から大分類を引く。
    public static func category(value: String) -> ResearchActivityCategory? {
        categories.first { $0.value == value }
    }

    /// 追加: 1段目（大分類）の選択肢。value は "category:<大分類>"。末尾に「その他」。
    public static var categoryOptions: [QuestionOption] {
        categories.map { QuestionOption(label: $0.label, value: "category:\($0.value)") }
            + [QuestionOption(label: "その他（自由入力）", value: otherFreeTextValue)]
    }

    /// 追加: 2段目（詳細活動）の選択肢。末尾に「その他」。
    public static func activityOptions(for category: ResearchActivityCategory) -> [QuestionOption] {
        category.activities.map(\.questionOption)
            + [QuestionOption(label: "その他（自由入力）", value: otherFreeTextValue)]
    }
}
