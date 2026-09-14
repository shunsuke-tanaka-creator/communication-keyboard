// PMTTAdapter.swift
// MozcFlickKeyboard — 追加: NarrativeEvent を PMTT（行動遷移モデル）のノードへ対応付けるアダプタのプロトコルと Mock 実装。
//
// Phase1 は MockPMTTAdapter が「曜日区分 + 時間帯 + 粗い活動種別」から weekday_afternoon_desk_work 形式の nodeID をルール生成する。
// stateLabel は解析済み emotion があればそれを流用、transitionID は nil（Phase4 で実体化）。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

/// 追加: NarrativeEvent を PMTTContext（ノード情報）へ対応付ける。
public protocol PMTTAdapter {
    /// 追加: イベントからノード情報を作る（同期・失敗なし）。
    func link(event: NarrativeEvent) -> PMTTContext
}

/// 追加: ルールベースの Mock アダプタ（Phase1）。
public final class MockPMTTAdapter: PMTTAdapter {
    /// 追加: 曜日・時刻の判定に使うカレンダー。
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// 追加: nodeID は "<曜日区分>_<時間帯>_<活動>" の3要素連結。
    ///   曜日区分: 平日=weekday / 土日=weekend
    ///   時間帯  : TimeOfDay ラベル（morning/afternoon/evening/night）
    ///   活動    : eventType から粗く推定（外出=outing / 帰宅=return_home / 就寝=rest / それ以外=desk_work）
    /// 例: weekday_afternoon_desk_work
    public func link(event: NarrativeEvent) -> PMTTContext {
        // 追加: 対応付けの基準時刻は回答時刻→無ければ検知時刻。
        let base = event.answeredAt ?? event.detectedAt
        // 追加: weekday は 1=日 … 7=土。土日を weekend、それ以外を weekday とする。
        let weekday = calendar.component(.weekday, from: base)
        let dayClass = (weekday == 1 || weekday == 7) ? "weekend" : "weekday"
        // 追加: 時間帯ラベル。
        let timeOfDay = TimeOfDay.label(for: base, calendar: calendar)
        // 追加: 活動の粗い推定。
        let activity = activityClass(for: event.eventType)
        let nodeID = "\(dayClass)_\(timeOfDay)_\(activity)"
        // 追加: stateLabel は解析済み emotion があればそれを流用（無ければ nil）。
        let stateLabel = event.narrative?.emotion
        return PMTTContext(nodeID: nodeID, stateLabel: stateLabel, transitionID: nil)
    }

    /// 追加: eventType → 活動区分の粗いマッピング。
    private func activityClass(for eventType: String) -> String {
        switch eventType {
        case "outing":
            return "outing"
        case "return_home":
            return "return_home"
        case "night_reflection":
            return "rest"
        default:
            return "desk_work"
        }
    }
}
