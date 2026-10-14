// SensorEventRouter.swift
// MozcFlickKeyboard — 追加: 疑似 IoT センサーイベントを解釈し、お天気分の質問キュー / 文脈ログへ振り分ける。
//
// 受信経路: 同一 LAN の MacBook から Python CLI → 親アプリの SensorHTTPServer → この Router。
// 出力経路:
//   - 玄関開 (door_open)  → NarrativeState.enqueueManualEvent(.outing)      → 次回キーボードで「どこへ行きましたか？」
//   - 玄関閉 (door_close) → NarrativeState.enqueueManualEvent(.returnHome)  → 次回キーボードで「今回の外出はどうでしたか？」
//   - 温度 high / low     → NarrativeState.enqueuePendingKind(.fatigueCheck) → 次回キーボードで「少し疲れていますか？」
//   - 温度 mid / トイレ / 在室(present|absent) → 質問は出さず ContextEvent として記録のみ
// いずれの場合も「生の受信記録」として ContextEvent(eventType: "sensor_<type>", source: "sensor") を必ず保存する。
//
// Shared に置く理由: App からも Tests からも参照するため（Tests は MozcFlickShared にのみ依存）。
// Network.framework を使う受信サーバー本体（SensorHTTPServer）は App ターゲット側に置く。

import Foundation

/// 追加: 疑似センサーから受け取った1イベント。HTTP body の JSON に対応する。
public struct SensorEvent: Codable {
    /// 追加: イベント種別（door_open / door_close / toilet / temperature / living_presence）。
    public let type: String
    /// 追加: 付随値（temperature の high|mid|low、living_presence の present|absent）。無い場合は nil。
    public let value: String?
    /// 追加: 発生時刻。CLI が送らなければ受信時刻を使う。
    public let at: Date?

    public init(type: String, value: String? = nil, at: Date? = nil) {
        self.type = type
        self.value = value
        self.at = at
    }
}

/// 追加: SensorEvent の処理結果。Dashboard 表示やテストの検証に使う。
public struct SensorRouteResult {
    /// 追加: 手動イベントキューへ積んだもの（外出 / 帰宅）。無ければ nil。
    public let manualEvent: ManualEvent?
    /// 追加: 保留質問キューへ積んだ質問種別（疲労チェック等）。無ければ nil。
    public let pendingKind: QuestionKind?
    /// 追加: 記録した ContextEvent の event_type（常に "sensor_<type>"）。
    public let contextEventType: String
    /// 追加: 未知の type だったか（CLI 側のタイプミス検知用）。
    public let isUnknownType: Bool

    public init(manualEvent: ManualEvent?, pendingKind: QuestionKind?, contextEventType: String, isUnknownType: Bool) {
        self.manualEvent = manualEvent
        self.pendingKind = pendingKind
        self.contextEventType = contextEventType
        self.isUnknownType = isUnknownType
    }
}

/// 追加: 受信イベントを NarrativeState / NarrativeStore へ振り分けるルーター。
public final class SensorEventRouter {

    /// 追加: 質問キューを積む状態ストア。
    private let state: NarrativeState
    /// 追加: ContextEvent を保存するストア。
    private let store: NarrativeStore

    public init(state: NarrativeState = NarrativeState(), store: NarrativeStore = NarrativeStore()) {
        self.state = state
        self.store = store
    }

    // MARK: - 受信 type 定数（CLI と一致させること）

    /// 追加: 玄関が開いた（外出）。
    public static let typeDoorOpen = "door_open"
    /// 追加: 玄関が閉まった（帰宅）。
    public static let typeDoorClose = "door_close"
    /// 追加: トイレ利用。
    public static let typeToilet = "toilet"
    /// 追加: 温度（value = high | mid | low）。
    public static let typeTemperature = "temperature"
    /// 変更: リビングの在室状況（value = present | absent）。
    /// 計画時は「リビング材質」と記載していたが、実体は在室検知センサーのため名称を改めた。
    public static let typeLivingPresence = "living_presence"

    /// 追加: 1イベントを処理する。質問キュー投入と ContextEvent 保存を行い、結果を返す。
    @discardableResult
    public func route(_ event: SensorEvent) -> SensorRouteResult {
        let at = event.at ?? Date() // 追加: 時刻が無ければ受信時刻を使う
        var manual: ManualEvent?
        var pending: QuestionKind?
        var unknown = false

        switch event.type {
        case Self.typeDoorOpen:
            // 追加: 玄関開 → 外出として扱い、次回キーボードで外出先を聞く。
            manual = .outing
        case Self.typeDoorClose:
            // 追加: 玄関閉 → 帰宅として扱い、次回キーボードで外出評価を聞く。
            manual = .returnHome
        case Self.typeTemperature:
            // 追加: 高温・低温は体調に影響するため疲労チェックを出す。中温(mid)は記録のみ。
            if event.value == "high" || event.value == "low" {
                pending = .fatigueCheck
            }
        case Self.typeToilet, Self.typeLivingPresence:
            // 変更: トイレ・在室(present/absent)は質問を出さず、文脈として記録するだけ。
            break
        default:
            // 追加: 未知の type も記録は行う（研究ログを欠損させない）。CLI 側の綴り間違い検知用にフラグを返す。
            unknown = true
        }

        // 追加: キュー投入（質問を出す指示）。
        if let manual { state.enqueueManualEvent(manual, at: at) }
        if let pending { state.enqueuePendingKind(pending, at: at) }

        // 追加: 生の受信記録を必ず ContextEvent として残す。
        let contextEventType = "sensor_\(event.type)"
        let snapshot = ContextSnapshot(timeOfDay: TimeOfDay.label(for: at),
                                       typingActive: false,      // 追加: センサー受信時は打鍵状態を判定しない
                                       calendarBusy: false,      // 追加: Calendar は stub のため false
                                       externalTrigger: externalTriggerLabel(for: event)) // 追加: 値も含めて残す
        let contextEvent = ContextEvent(participantID: state.participantID,
                                        eventType: contextEventType,
                                        detectedAt: at,
                                        source: "sensor",
                                        context: snapshot)
        store.appendContext(contextEvent)

        // 追加: Dashboard 表示用に最後の受信内容を残す。
        state.lastSensorEvent = event.value.map { "\(event.type)=\($0)" } ?? event.type
        state.lastSensorEventAt = at

        // 追加: v0.1 研究サーバー連携。端末Contextへ最新値を反映し、サーバーへ送る（URL 未設定なら送らない）。
        let contextStore = ResearchContextStore()
        contextStore.applySensor(type: event.type, value: event.value)
        let sensorEvent = ResearchSensorEvent(participantID: state.participantID,
                                              deviceID: contextStore.deviceID,
                                              type: event.type,
                                              value: event.value,
                                              occurredAt: at)
        ResearchAPIClient(baseURL: state.backendBaseURL).sendSensorEvent(sensorEvent)

        NSLog("[MFK-Sensor] received type=\(event.type) value=\(event.value ?? "-") manual=\(manual?.rawValue ?? "-") pending=\(pending?.rawValue ?? "-") unknown=\(unknown)") // 追加: 受信デバッグ

        return SensorRouteResult(manualEvent: manual,
                                 pendingKind: pending,
                                 contextEventType: contextEventType,
                                 isUnknownType: unknown)
    }

    /// 追加: externalTrigger に載せるラベル（"sensor:temperature=high" のように値まで残す）。
    private func externalTriggerLabel(for event: SensorEvent) -> String {
        if let value = event.value, !value.isEmpty {
            return "sensor:\(event.type)=\(value)"
        }
        return "sensor:\(event.type)"
    }
}

// MARK: - 追加: アプリ内テストモード用のプリセット

/// 追加: 親アプリの「疑似センサーテスト」からワンタップ注入するためのプリセット定義。
/// Python CLI（tools/sensor_inject.py）と同じ type / value を使うので、
/// Mac が無い場所でも同じ経路（SensorEventRouter）を通して動作確認できる。
public struct SensorPreset {
    /// 追加: ボタンに出す日本語ラベル。
    public let title: String
    /// 追加: 送る type（CLI と一致させる）。
    public let type: String
    /// 追加: 送る value（不要なら nil）。
    public let value: String?

    public init(title: String, type: String, value: String? = nil) {
        self.title = title
        self.type = type
        self.value = value
    }

    /// 追加: SensorEvent へ変換する（時刻はタップ時刻）。
    public func makeEvent(at date: Date = Date()) -> SensorEvent {
        SensorEvent(type: type, value: value, at: date)
    }

    /// 追加: テスト用に注入できる全イベント。Dashboard はこの配列をそのままボタン化する。
    public static var all: [SensorPreset] {
        [
            SensorPreset(title: "玄関を開けた（外出）", type: SensorEventRouter.typeDoorOpen),
            SensorPreset(title: "玄関を閉めた（帰宅）", type: SensorEventRouter.typeDoorClose),
            SensorPreset(title: "トイレ", type: SensorEventRouter.typeToilet),
            SensorPreset(title: "在室（リビングにいる）", type: SensorEventRouter.typeLivingPresence, value: "present"),
            SensorPreset(title: "不在（リビングにいない）", type: SensorEventRouter.typeLivingPresence, value: "absent"),
            SensorPreset(title: "温度 高い", type: SensorEventRouter.typeTemperature, value: "high"),
            SensorPreset(title: "温度 ふつう", type: SensorEventRouter.typeTemperature, value: "mid"),
            SensorPreset(title: "温度 低い", type: SensorEventRouter.typeTemperature, value: "low"),
        ]
    }
}
