// ResearchStateTests.swift
// MozcFlickKeyboard — 追加: 回答済み質問IDの永続化と現在状態の出題間隔を検証する。

import XCTest
@testable import MozcFlickShared

final class ResearchStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var state: NarrativeState!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "test.research.state.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        state = NarrativeState(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        state = nil
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testAnsweredRequestPersistsAcrossStateInstances() throws {
        XCTAssertFalse(state.hasAnsweredRequest("q1"))
        state.markAnsweredRequest("q1")

        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reloaded = NarrativeState(defaults: reloadedDefaults)
        XCTAssertTrue(reloaded.hasAnsweredRequest("q1"))
        XCTAssertFalse(reloaded.hasAnsweredRequest("q2"))
        XCTAssertEqual(reloadedDefaults.stringArray(forKey: "research.answeredRequests"), ["q1"])
    }

    func testAnsweredRequestsKeepOnlyTheLatest200() throws {
        for index in 0..<205 { state.markAnsweredRequest("q\(index)") }

        let reloaded = NarrativeState(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        for index in 0..<5 { XCTAssertFalse(reloaded.hasAnsweredRequest("q\(index)")) }
        for index in 5..<205 { XCTAssertTrue(reloaded.hasAnsweredRequest("q\(index)")) }
        XCTAssertEqual(defaults.stringArray(forKey: "research.answeredRequests"), (5..<205).map { "q\($0)" })
    }

    func testRepeatedAnsweredRequestMovesToEndWithoutDuplicating() {
        for index in 0..<200 { state.markAnsweredRequest("q\(index)") }
        state.markAnsweredRequest("q0")
        state.markAnsweredRequest("q0")
        XCTAssertEqual(defaults.stringArray(forKey: "research.answeredRequests"),
                       (1..<200).map { "q\($0)" } + ["q0"])

        state.markAnsweredRequest("q200")
        XCTAssertTrue(state.hasAnsweredRequest("q0"))
        XCTAssertFalse(state.hasAnsweredRequest("q1"))
        XCTAssertEqual(defaults.stringArray(forKey: "research.answeredRequests")?.count, 200)
    }

    func testLastRequestIDPersistsAndCanBeCleared() throws {
        XCTAssertNil(state.lastRequestID)
        state.lastRequestID = "last-question"
        let reloaded = NarrativeState(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(reloaded.lastRequestID, "last-question")
        XCTAssertEqual(defaults.string(forKey: "research.lastRequestID"), "last-question")

        reloaded.lastRequestID = nil
        XCTAssertNil(NarrativeState(defaults: defaults).lastRequestID)
    }

    func testCurrentStateCooldownIsThreeHours() {
        XCTAssertEqual(QuestionCatalog.template(for: .currentState).cooldown, 10800)
    }

    func testCurrentStateCanBeAnsweredAgainAfterCooldownOnSameDay() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        let earlier = now.addingTimeInterval(-10800)
        state.markAnswered(kind: .currentState, on: now)
        state.markShown(kind: .currentState, at: earlier)
        let policy = QuestionPolicy(state: state)
        XCTAssertFalse(policy.canShow(kind: .currentState, now: now.addingTimeInterval(-1)))
        XCTAssertTrue(policy.canShow(kind: .currentState, now: now))

        state.markAnswered(kind: .morningMood, on: now)
        XCTAssertFalse(policy.canShow(kind: .morningMood, now: now))
    }

    func testCurrentStateStillRespectsSnoozeAndDailyLimit() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12))!
        let policy = QuestionPolicy(state: state, maxQuestionsPerDay: 1)
        state.markSnoozed(kind: .currentState, until: now.addingTimeInterval(1800))
        XCTAssertFalse(policy.canShow(kind: .currentState, now: now.addingTimeInterval(1799)))
        XCTAssertTrue(policy.canShow(kind: .currentState, now: now.addingTimeInterval(1800)))

        state.markAnswered(kind: .currentState, on: now)
        XCTAssertFalse(policy.canShow(kind: .currentState, now: now.addingTimeInterval(1800)))
    }

    func testMarkMeasurementInitializesMissingTimesAndPreservesOtherItems() throws {
        var context = ResearchDeviceContext()
        context.measurementUpdatedAt = nil
        let before = Date()
        context.markMeasurement("battery_state")
        let batteryStateTime = try XCTUnwrap(context.measurementUpdatedAt?["battery_state"])
        XCTAssertGreaterThanOrEqual(batteryStateTime, before)
        XCTAssertLessThanOrEqual(batteryStateTime, Date())

        context.markMeasurement("battery_level")
        XCTAssertEqual(context.measurementUpdatedAt?["battery_state"], batteryStateTime)
        XCTAssertNotNil(context.measurementUpdatedAt?["battery_level"])
    }
}
