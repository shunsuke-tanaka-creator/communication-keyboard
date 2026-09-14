// TypingMetrics.swift
// MozcFlickKeyboard — 追加: 打鍵イベントから TypingFeatures を集計する（本文は一切保持しない）。
//
// キーボードは1文字入力ごとに recordKeystroke(at:)、削除ごとに recordBackspace(at:) を呼ぶだけ。
// 内部では時刻の配列だけを持ち、snapshot(now:) で速度・backspace 率・平均間隔・ポーズ等を計算する。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

/// 追加: 打鍵特徴の集計器。プライバシー保護のため文字内容は保存しない。
public final class TypingMetrics {
    /// 追加: 各打鍵（1文字入力）の時刻。間隔・速度・ポーズ計算に使う。
    private var keystrokeTimes: [Date] = []
    /// 追加: 各 backspace の時刻。件数のみ使うが将来のため時刻で持つ。
    private var backspaceTimes: [Date] = []

    /// 追加: ポーズ（無操作）とみなすキー間隔の閾値（秒）。
    private let pauseThreshold: TimeInterval

    /// 追加: ポーズ閾値の既定は 2 秒。
    public init(pauseThreshold: TimeInterval = 2.0) {
        self.pauseThreshold = pauseThreshold
    }

    /// 追加: 1文字入力を記録する。
    public func recordKeystroke(at date: Date) {
        keystrokeTimes.append(date)
    }

    /// 追加: 1回の削除（backspace）を記録する。
    public func recordBackspace(at date: Date) {
        backspaceTimes.append(date)
    }

    /// 追加: セッションを初期化する（回答保存後などに呼ぶ）。
    public func reset() {
        keystrokeTimes.removeAll()
        backspaceTimes.removeAll()
    }

    /// 追加: 現在までの打鍵特徴を計算して返す。0除算は各所でガードする。
    public func snapshot(now: Date) -> TypingFeatures {
        let totalTyped = keystrokeTimes.count
        let backspaceCount = backspaceTimes.count

        // 追加: 打鍵が無ければ件数のみ埋めて返す（速度等は nil）。
        guard let first = keystrokeTimes.first, let last = keystrokeTimes.last, totalTyped > 0 else {
            return TypingFeatures(backspaceCount: backspaceCount,
                                  totalTypedCharacters: totalTyped)
        }

        // 追加: セッション継続時間 = 最初の打鍵から now まで（秒）。
        let sessionDurationSec = max(0, now.timeIntervalSince(first))

        // 追加: アクティブ span = 最初の打鍵から最後の打鍵まで（速度分母）。
        let activeSpanSec = max(0, last.timeIntervalSince(first))

        // 追加: 打鍵速度(CPM) = 文字数 / アクティブ分。span=0（1打鍵のみ等）なら nil。
        let typingSpeedCPM: Double? = activeSpanSec > 0 ? Double(totalTyped) / (activeSpanSec / 60.0) : nil

        // 追加: backspace 率 = backspace 数 / 総打鍵数（0除算はガード済み: totalTyped>0）。
        let backspaceRate: Double? = Double(backspaceCount) / Double(totalTyped)

        // 追加: 連続打鍵の間隔配列（隣接時刻の差）。
        var intervals: [TimeInterval] = []
        for i in 1..<keystrokeTimes.count {
            intervals.append(keystrokeTimes[i].timeIntervalSince(keystrokeTimes[i - 1]))
        }

        // 追加: 平均キー間隔(ms) = 間隔平均 * 1000。間隔が無ければ nil。
        let meanKeyIntervalMS: Double? = intervals.isEmpty ? nil : (intervals.reduce(0, +) / Double(intervals.count)) * 1000.0

        // 追加: ポーズ = 閾値超えの間隔。件数と合計時間を集計。
        let longPauses = intervals.filter { $0 > pauseThreshold }
        let pauseCount = longPauses.count
        let longPauseDurationSec = longPauses.reduce(0, +)

        return TypingFeatures(typingSpeedCPM: typingSpeedCPM,
                              backspaceRate: backspaceRate,
                              meanKeyIntervalMS: meanKeyIntervalMS,
                              sessionDurationSec: sessionDurationSec,
                              backspaceCount: backspaceCount,
                              totalTypedCharacters: totalTyped,
                              pauseCount: pauseCount,
                              longPauseDurationSec: longPauseDurationSec)
    }

    /// 追加: 現在の打鍵特徴がベースラインから「疲労側」に乖離しているかを単純ルールで判定する。
    /// 追加: 判定条件（いずれか成立で true）:
    ///   - 速度が baseline の 80% 未満（20%以上の低下）
    ///   - backspace 率が baseline + 0.10 を超える
    ///   - ポーズ回数が baseline の 1.5 倍超
    /// 追加: TypingFatigueTrigger（Phase2）がこの関数を使う。値が欠損している比較はスキップする。
    public static func deviation(current: TypingFeatures, baseline: TypingFeatures) -> Bool {
        // 追加: 速度低下（20%以上）。
        if let cur = current.typingSpeedCPM, let base = baseline.typingSpeedCPM, base > 0 {
            if cur < base * 0.8 { return true }
        }
        // 追加: backspace 率上昇（+0.10 超）。
        if let cur = current.backspaceRate, let base = baseline.backspaceRate {
            if cur > base + 0.10 { return true }
        }
        // 追加: ポーズ回数増（1.5 倍超）。
        if let cur = current.pauseCount, let base = baseline.pauseCount, base > 0 {
            if Double(cur) > Double(base) * 1.5 { return true }
        }
        return false
    }
}
