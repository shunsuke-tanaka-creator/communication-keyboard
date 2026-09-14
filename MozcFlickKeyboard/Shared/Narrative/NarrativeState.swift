// NarrativeState.swift
// MozcFlickKeyboard — 追加: 出題制御に必要な状態を App Group UserDefaults に保持する。
//
// 保持するもの: 日別の回答済みフラグ / 種別ごとの最終表示時刻 / snooze 期限と回数 /
// 当日初回キーボード利用時刻 / 手動イベントのキュー / 打鍵ベースライン / 研究設定。
// テストから差し替えられるよう init(defaults:) で UserDefaults を注入できる。
// 実装は「日付キー yyyyMMdd の辞書」だけで済ませ、極力単純に保つ。

import Foundation

/// UserDefaults のキー名。親アプリの SettingsViewController からも同じ文字列を参照できるよう public にする。
public enum NarrativeSettingsKeys {
    /// 日別の回答済み: [yyyyMMdd: [kind rawValue: 回答時刻(epoch秒)]]
    public static let answered = "narrative.answered"
    /// 種別ごとの最終表示時刻: [kind rawValue: epoch秒]
    public static let lastShown = "narrative.lastShown"
    /// 種別ごとの snooze 期限: [kind rawValue: epoch秒]
    public static let snoozeUntil = "narrative.snoozeUntil"
    /// 種別ごとの snooze 回数: [kind rawValue: 回数]
    public static let snoozeCount = "narrative.snoozeCount"
    /// 日別の初回キーボード利用時刻: [yyyyMMdd: epoch秒]
    public static let firstKeyboardUse = "narrative.firstKeyboardUse"
    /// 最終キーボード利用時刻: epoch秒
    public static let lastKeyboardUse = "narrative.lastKeyboardUse"
    /// 手動イベントキュー: [["event": rawValue, "at": epoch秒]]
    public static let manualEventQueue = "narrative.manualEventQueue"
    /// 打鍵ベースライン（TypingFeatures を JSON エンコードして保存）
    public static let typingBaseline = "narrative.typingBaseline"
    /// 被験者 ID（研究設定）
    public static let participantID = "narrative.participantID"
    /// 送信先ベース URL（研究設定 / 空なら送信しない）
    public static let backendBaseURL = "narrative.backendBaseURL"
    /// 質問機能の ON/OFF（研究設定）
    public static let narrativeEnabled = "narrative.enabled"
}

/// 出題制御の状態ストア。
public final class NarrativeState {

    /// 保存先。App Group が使えない場合は nil になり、全ての読み書きが no-op になる。
    private let defaults: UserDefaults?

    /// 日付キー（yyyyMMdd）生成用。
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    /// 既定は App Group の suite。テストでは使い捨ての suite を注入する。
    public init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupID)) {
        self.defaults = defaults
    }

    /// 指定日の日付キー。
    private func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    // MARK: - 回答済み管理

    /// 指定日に指定種別を回答済みか。
    public func isAnswered(kind: QuestionKind, on date: Date) -> Bool {
        let all = defaults?.dictionary(forKey: NarrativeSettingsKeys.answered) as? [String: [String: Double]]
        return all?[dayKey(date)]?[kind.rawValue] != nil
    }

    /// 指定日の指定種別を回答済みにする。
    public func markAnswered(kind: QuestionKind, on date: Date) {
        guard let defaults else { return }
        var all = defaults.dictionary(forKey: NarrativeSettingsKeys.answered) as? [String: [String: Double]] ?? [:]
        var today = all[dayKey(date)] ?? [:]
        today[kind.rawValue] = date.timeIntervalSince1970
        all[dayKey(date)] = today
        defaults.set(all, forKey: NarrativeSettingsKeys.answered)
    }

    /// 指定日の回答総数。maxQuestionsPerDay 判定に使う。
    public func answeredCount(on date: Date) -> Int {
        let all = defaults?.dictionary(forKey: NarrativeSettingsKeys.answered) as? [String: [String: Double]]
        return all?[dayKey(date)]?.count ?? 0
    }

    // MARK: - 最終表示時刻（cooldown 判定）

    /// 指定種別を最後に表示した時刻。
    public func lastShown(kind: QuestionKind) -> Date? {
        guard let dict = defaults?.dictionary(forKey: NarrativeSettingsKeys.lastShown) as? [String: Double],
              let t = dict[kind.rawValue] else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// 指定種別の最終表示時刻を記録する。
    public func markShown(kind: QuestionKind, at date: Date) {
        guard let defaults else { return }
        var dict = defaults.dictionary(forKey: NarrativeSettingsKeys.lastShown) as? [String: Double] ?? [:]
        dict[kind.rawValue] = date.timeIntervalSince1970
        defaults.set(dict, forKey: NarrativeSettingsKeys.lastShown)
    }

    // MARK: - snooze（あとで）

    /// 指定種別の snooze 期限。
    public func snoozeUntil(kind: QuestionKind) -> Date? {
        guard let dict = defaults?.dictionary(forKey: NarrativeSettingsKeys.snoozeUntil) as? [String: Double],
              let t = dict[kind.rawValue] else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// 指定種別を指定時刻まで snooze する（回数も加算する）。
    public func markSnoozed(kind: QuestionKind, until date: Date) {
        guard let defaults else { return }
        var untilDict = defaults.dictionary(forKey: NarrativeSettingsKeys.snoozeUntil) as? [String: Double] ?? [:]
        untilDict[kind.rawValue] = date.timeIntervalSince1970
        defaults.set(untilDict, forKey: NarrativeSettingsKeys.snoozeUntil)
        var countDict = defaults.dictionary(forKey: NarrativeSettingsKeys.snoozeCount) as? [String: Int] ?? [:]
        countDict[kind.rawValue] = (countDict[kind.rawValue] ?? 0) + 1
        defaults.set(countDict, forKey: NarrativeSettingsKeys.snoozeCount)
    }

    /// 指定種別が「あとで」された累積回数。
    public func snoozeCount(kind: QuestionKind) -> Int {
        let dict = defaults?.dictionary(forKey: NarrativeSettingsKeys.snoozeCount) as? [String: Int]
        return dict?[kind.rawValue] ?? 0
    }

    // MARK: - キーボード利用記録（朝トリガー用）

    /// 指定日の初回キーボード利用時刻。引数なしなら今日。
    public func firstKeyboardUseDate(on date: Date = Date()) -> Date? {
        guard let dict = defaults?.dictionary(forKey: NarrativeSettingsKeys.firstKeyboardUse) as? [String: Double],
              let t = dict[dayKey(date)] else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// キーボード利用を記録する。その日の初回だった場合のみ true を返す（朝トリガーの発火条件）。
    public func markKeyboardUse(at date: Date) -> Bool {
        guard let defaults else { return false }
        defaults.set(date.timeIntervalSince1970, forKey: NarrativeSettingsKeys.lastKeyboardUse)
        var dict = defaults.dictionary(forKey: NarrativeSettingsKeys.firstKeyboardUse) as? [String: Double] ?? [:]
        let key = dayKey(date)
        if dict[key] != nil { return false } // 当日2回目以降
        dict[key] = date.timeIntervalSince1970
        defaults.set(dict, forKey: NarrativeSettingsKeys.firstKeyboardUse)
        return true
    }

    /// 最後にキーボードを使った時刻。
    public func lastKeyboardUse() -> Date? {
        guard let t = defaults?.object(forKey: NarrativeSettingsKeys.lastKeyboardUse) as? Double else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    // MARK: - 手動イベントキュー

    /// 手動イベントを1件キューへ積む（キーボードの「記録」ボタン / 親アプリ Dashboard から）。
    public func enqueueManualEvent(_ event: ManualEvent, at date: Date) {
        guard let defaults else { return }
        var queue = defaults.array(forKey: NarrativeSettingsKeys.manualEventQueue) as? [[String: Any]] ?? []
        queue.append(["event": event.rawValue, "at": date.timeIntervalSince1970])
        defaults.set(queue, forKey: NarrativeSettingsKeys.manualEventQueue)
    }

    /// キューを全部取り出して空にする（Trigger 評価時に消費する）。
    public func dequeueAllManualEvents() -> [(ManualEvent, Date)] {
        let items = peekManualEvents()
        defaults?.removeObject(forKey: NarrativeSettingsKeys.manualEventQueue)
        return items
    }

    /// キューの内容を消費せずに覗く。
    public func peekManualEvents() -> [(ManualEvent, Date)] {
        let queue = defaults?.array(forKey: NarrativeSettingsKeys.manualEventQueue) as? [[String: Any]] ?? []
        return queue.compactMap { item in
            guard let raw = item["event"] as? String,
                  let event = ManualEvent(rawValue: raw),
                  let t = item["at"] as? Double else { return nil }
            return (event, Date(timeIntervalSince1970: t))
        }
    }

    // MARK: - 打鍵ベースライン

    /// 保存済みの打鍵ベースライン。
    public func typingBaseline() -> TypingFeatures? {
        guard let data = defaults?.data(forKey: NarrativeSettingsKeys.typingBaseline) else { return nil }
        return try? NarrativeJSON.decoder.decode(TypingFeatures.self, from: data)
    }

    /// 指数移動平均（alpha=0.2）でベースラインを更新する。初回はそのまま採用。
    public func updateTypingBaseline(with features: TypingFeatures) {
        guard let defaults else { return }
        let alpha = 0.2
        /// 旧値と新値を alpha で混ぜる。どちらか欠損ならある方を使う。
        func ema(_ old: Double?, _ new: Double?) -> Double? {
            guard let new else { return old }
            guard let old else { return new }
            return old * (1 - alpha) + new * alpha
        }
        func emaInt(_ old: Int?, _ new: Int?) -> Int? {
            guard let v = ema(old.map(Double.init), new.map(Double.init)) else { return nil }
            return Int(v.rounded())
        }
        let base = typingBaseline()
        let merged = TypingFeatures(typingSpeedCPM: ema(base?.typingSpeedCPM, features.typingSpeedCPM),
                                    backspaceRate: ema(base?.backspaceRate, features.backspaceRate),
                                    meanKeyIntervalMS: ema(base?.meanKeyIntervalMS, features.meanKeyIntervalMS),
                                    sessionDurationSec: ema(base?.sessionDurationSec, features.sessionDurationSec),
                                    backspaceCount: emaInt(base?.backspaceCount, features.backspaceCount),
                                    totalTypedCharacters: emaInt(base?.totalTypedCharacters, features.totalTypedCharacters),
                                    pauseCount: emaInt(base?.pauseCount, features.pauseCount),
                                    longPauseDurationSec: ema(base?.longPauseDurationSec, features.longPauseDurationSec))
        guard let data = try? NarrativeJSON.encoder.encode(merged) else { return }
        defaults.set(data, forKey: NarrativeSettingsKeys.typingBaseline)
    }

    // MARK: - 研究設定

    /// 被験者 ID。既定 "p001"。
    public var participantID: String {
        get { defaults?.string(forKey: NarrativeSettingsKeys.participantID) ?? "p001" }
        set { defaults?.set(newValue, forKey: NarrativeSettingsKeys.participantID) }
    }

    /// 送信先ベース URL。既定は空（= 送信しない）。
    public var backendBaseURL: String {
        get { defaults?.string(forKey: NarrativeSettingsKeys.backendBaseURL) ?? "" }
        set { defaults?.set(newValue, forKey: NarrativeSettingsKeys.backendBaseURL) }
    }

    /// 質問機能の ON/OFF。既定 true（キー未設定なら有効）。
    public var narrativeEnabled: Bool {
        get {
            guard let v = defaults?.object(forKey: NarrativeSettingsKeys.narrativeEnabled) as? Bool else { return true }
            return v
        }
        set { defaults?.set(newValue, forKey: NarrativeSettingsKeys.narrativeEnabled) }
    }

    // MARK: - テスト用

    /// 保存済みの全状態を消す（テスト / 動作確認用）。
    public func resetForTesting() {
        guard let defaults else { return }
        for key in [NarrativeSettingsKeys.answered,
                    NarrativeSettingsKeys.lastShown,
                    NarrativeSettingsKeys.snoozeUntil,
                    NarrativeSettingsKeys.snoozeCount,
                    NarrativeSettingsKeys.firstKeyboardUse,
                    NarrativeSettingsKeys.lastKeyboardUse,
                    NarrativeSettingsKeys.manualEventQueue,
                    NarrativeSettingsKeys.typingBaseline] {
            defaults.removeObject(forKey: key)
        }
    }
}
