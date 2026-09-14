// NarrativeTriggerTests.swift
// MozcFlickKeyboard — 追加: 「お天気分」micro-diary の Trigger / Policy / Export / TypingMetrics を検証する単体テスト。
//
// 【方針】
//  - TriggerEngine.nextQuestion は now を明示注入できるので、時刻に依存する朝/夜トリガーは
//    date(hour:minute:day:) で作った固定時刻を渡して決定的に検証する。
//  - 状態は毎テスト使い捨ての UserDefaults suite を注入し、setUp/tearDown で resetForTesting() する。
//  - Shared フレームワーク(MozcFlickShared)の public API だけをテストする（アプリ/拡張には依存しない）。
//
// 【実装挙動として確認した非自明点（docs 反映用メモ）】
//  - QuestionPolicy: 手動由来(outingDestination / outingEvaluation)は「当日回答済み」制約を免除する
//    （毎回の外出は別事象のため）。ただし maxQuestionsPerDay と snooze は尊重する。
//  - MorningTrigger は isFirstKeyboardUseToday==true かつ 06〜10時のときだけ発火する。
//  - TypingFeatures は数値/optional のみで、本文(text)を保持する API は存在しない（プライバシー保証）。

import XCTest
@testable import MozcFlickShared

final class NarrativeTriggerTests: XCTestCase {

    // 追加: 使い捨ての UserDefaults suite を注入した状態ストア（テストごとに作り直す）。
    private var state: NarrativeState!
    // 追加: suite 名（tearDown で破棄する）。
    private var suiteName: String!
    // 追加: 固定カレンダー（時刻注入の基準）。
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        suiteName = "test.narrative.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        state = NarrativeState(defaults: suite)
        state.resetForTesting()
    }

    override func tearDown() {
        state.resetForTesting()
        UserDefaults().removePersistentDomain(forName: suiteName)
        state = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - 時刻ヘルパー

    /// 追加: 固定した年月日を基準に hour:minute:day の Date を作る。
    /// day は 2026-03-01 を1日目とし、day 分だけ日を進める（翌日テスト用）。
    private func date(hour: Int, minute: Int = 0, day: Int = 1) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)!
    }

    /// 追加: 既定構成の TriggerEngine を state から作る。
    private func makeEngine() -> TriggerEngine {
        TriggerEngine.makeDefault(state: state, calendar: calendar)
    }

    // MARK: - 1. 朝の初回利用で morningMood

    func testMorningFirstUseShowsMorningMood() {
        // 朝07:00・当日初回 → morningMood が出る。
        let engine = makeEngine()
        let now = date(hour: 7)
        let q = engine.nextQuestion(now: now, isFirstKeyboardUseToday: true, typing: nil)
        XCTAssertEqual(q?.kind, .morningMood, "朝の初回利用では morningMood を出すべき")
    }

    // MARK: - 2. 同じ朝の2回目以降は重複表示しない

    func testMorningSecondOpenNoDuplicate() {
        let engine = makeEngine()
        let first = date(hour: 7)
        // 1回目: morningMood を取得し、表示＋回答を記録する。
        let q1 = engine.nextQuestion(now: first, isFirstKeyboardUseToday: true, typing: nil)
        XCTAssertEqual(q1?.kind, .morningMood)
        state.markShown(kind: .morningMood, at: first)
        state.markAnswered(kind: .morningMood, on: first)

        // 2回目: 同じ朝(07:30)・初回でない → morningMood は再出題されない。
        let second = date(hour: 7, minute: 30)
        let q2 = engine.nextQuestion(now: second, isFirstKeyboardUseToday: false, typing: nil)
        XCTAssertNotEqual(q2?.kind, .morningMood, "同じ朝に morningMood を重複表示してはいけない")
    }

    // MARK: - 3. 回答済みはその日再表示されない（Policy 直接）

    func testAnsweredNotShownAgain() {
        let now = date(hour: 7)
        let policy = QuestionPolicy(state: state)
        // 回答前は出せる。
        XCTAssertTrue(policy.canShow(kind: .morningMood, now: now))
        // 回答すると同日は出せない。
        state.markAnswered(kind: .morningMood, on: now)
        XCTAssertFalse(policy.canShow(kind: .morningMood, now: now), "当日回答済みの種別は再出題不可であるべき")
    }

    // MARK: - 4. snooze はクールダウン後に再表示

    func testSnoozeReappearsAfterCooldown() {
        let now = date(hour: 7)
        let policy = QuestionPolicy(state: state)
        // now から snoozeInterval(30分) だけ snooze する。
        state.markSnoozed(kind: .morningMood, until: now.addingTimeInterval(NarrativeConfig.snoozeInterval))
        // 10分後: まだ snooze 期限内 → 出せない。
        XCTAssertFalse(policy.canShow(kind: .morningMood, now: now.addingTimeInterval(10 * 60)),
                       "snooze 期限内は出題不可であるべき")
        // 31分後: snooze 期限切れ → 出せる。
        XCTAssertTrue(policy.canShow(kind: .morningMood, now: now.addingTimeInterval(31 * 60)),
                      "snooze 期限切れ後は再出題可能であるべき")
    }

    // MARK: - 5. 21時以降は nightReflection

    func testNightReflectionAfter21() {
        let engine = makeEngine()
        let now = date(hour: 22)
        // 22:00・初回でない・未回答 → nightReflection。
        let q = engine.nextQuestion(now: now, isFirstKeyboardUseToday: false, typing: nil)
        XCTAssertEqual(q?.kind, .nightReflection, "21時以降は nightReflection を出すべき")
    }

    // MARK: - 6. 翌日はまた morningMood（日別リセット）

    func testNextDayNewMorningMood() {
        let engine = makeEngine()
        // day1 の朝に morningMood を回答済みにする。
        let day1 = date(hour: 7, day: 1)
        state.markAnswered(kind: .morningMood, on: day1)
        XCTAssertFalse(QuestionPolicy(state: state).canShow(kind: .morningMood, now: day1))

        // day2 の朝・当日初回 → morningMood が再び出る（回答済みは日別管理）。
        let day2 = date(hour: 7, day: 2)
        let q = engine.nextQuestion(now: day2, isFirstKeyboardUseToday: true, typing: nil)
        XCTAssertEqual(q?.kind, .morningMood, "翌日は morningMood を再出題すべき（日別リセット）")
    }

    // MARK: - 7. 手動「外出した」で outingDestination

    func testManualOutingProducesOutingDestination() {
        let engine = makeEngine()
        let now = date(hour: 13) // 昼: 朝/夜トリガーは発火しない。
        state.enqueueManualEvent(.outing, at: now)
        // 昼・初回でない → 手動外出が最優先で outingDestination。
        let q = engine.nextQuestion(now: now, isFirstKeyboardUseToday: false, typing: nil)
        XCTAssertEqual(q?.kind, .outingDestination, "手動「外出した」で outingDestination を出すべき")
    }

    // MARK: - 8. 手動「帰宅した」で outingEvaluation

    func testManualReturnProducesOutingEvaluation() {
        let engine = makeEngine()
        let now = date(hour: 13)
        state.enqueueManualEvent(.returnHome, at: now)
        let q = engine.nextQuestion(now: now, isFirstKeyboardUseToday: false, typing: nil)
        XCTAssertEqual(q?.kind, .outingEvaluation, "手動「帰宅した」で outingEvaluation を出すべき")
    }

    // MARK: - 9. 機能OFF なら nil

    func testNarrativeDisabledReturnsNil() {
        let engine = makeEngine()
        state.narrativeEnabled = false
        // 朝の初回利用という「本来出る」条件でも、機能OFFなら何も出さない。
        let q = engine.nextQuestion(now: date(hour: 7), isFirstKeyboardUseToday: true, typing: nil)
        XCTAssertNil(q, "narrativeEnabled=false のときは常に nil を返すべき")
    }

    // MARK: - 10. CSV は自由記述をエスケープする

    func testExportCSVEscapesFreeText() {
        // カンマ・二重引用符・改行を含む自由記述を用意する。
        let tricky = "hello, \"quoted\"\nnewline"
        let now = date(hour: 20)
        let pending = PendingQuestion(participantID: state.participantID,
                                      kind: .nightReflection,
                                      prompt: "今日はどんな1日でしたか？",
                                      options: [],
                                      allowFreeText: true,
                                      eventType: "night_reflection",
                                      detectedAt: now,
                                      context: ContextSnapshot(timeOfDay: "evening",
                                                               typingActive: false,
                                                               calendarBusy: false,
                                                               externalTrigger: nil))
        let event = NarrativeEvent.make(from: pending,
                                        answer: QuestionAnswer(label: "good", freeText: tricky),
                                        typing: nil,
                                        answeredAt: now)
        let csv = NarrativeExport.csv(events: [event])

        // 追加: 参加者IDが含まれること（研究エクスポートの健全性）。
        XCTAssertTrue(csv.contains(state.participantID), "CSV に participant_id が含まれるべき")
        // 追加: 二重引用符は "" にエスケープされ、値全体が "" で囲われること。
        XCTAssertTrue(csv.contains("\"\"quoted\"\""), "二重引用符は \"\" にエスケープされるべき")
        // 追加: エスケープされた自由記述セル（カンマ・改行込み）がそのまま1セルとして囲われていること。
        XCTAssertTrue(csv.contains("\"hello, \"\"quoted\"\"\nnewline\""),
                      "カンマ・引用符・改行を含む自由記述は1セルとして \"\" で囲うべき")
        // 追加: ヘッダ行が存在すること。
        XCTAssertTrue(csv.hasPrefix("event_id,participant_id,"), "1行目は CSV ヘッダであるべき")
    }

    // MARK: - 11. TypingMetrics は件数のみで本文を持たない

    func testTypingMetricsNoTextOnlyCounts() {
        let metrics = TypingMetrics()
        let base = date(hour: 10)
        // 追加: 1秒間隔で5打鍵、途中で2回 backspace。
        for i in 0..<5 {
            metrics.recordKeystroke(at: base.addingTimeInterval(Double(i)))
        }
        metrics.recordBackspace(at: base.addingTimeInterval(1.5))
        metrics.recordBackspace(at: base.addingTimeInterval(2.5))

        let snap = metrics.snapshot(now: base.addingTimeInterval(6))

        // 打鍵数・backspace 数が妥当。
        XCTAssertEqual(snap.totalTypedCharacters, 5)
        XCTAssertEqual(snap.backspaceCount, 2)
        // backspaceRate は [0,1] に収まる（2/5 = 0.4）。
        let rate = snap.backspaceRate ?? -1
        XCTAssertGreaterThanOrEqual(rate, 0)
        XCTAssertLessThanOrEqual(rate, 1)
        XCTAssertEqual(rate, 0.4, accuracy: 0.0001)

        // プライバシー保証: TypingFeatures は数値/optional のみで、本文を取り出す API を持たない。
        // Mirror でプロパティを走査し、String / [String] を露出していないことを確認する
        // （本文を保存する型が万一混入した場合に落とす）。
        let mirror = Mirror(reflecting: snap)
        for child in mirror.children {
            XCTAssertFalse(child.value is String, "TypingFeatures が文字列プロパティを持ってはいけない: \(child.label ?? "?")")
            XCTAssertFalse(child.value is [String], "TypingFeatures が文字列配列を持ってはいけない: \(child.label ?? "?")")
        }
    }
}
