import XCTest
@testable import MozcFlickShared

final class ResearchStateTests: XCTestCase {
    func testServerCurrentQuestionDecodesAndOfflineAnswerIsRemembered() throws {
        let json = """
        {"id":"q1","participantID":"p001","kind":"currentState","prompt":"今の状態",
        "options":[{"label":"始める","value":"start_current_state"}],"allowFreeText":false,
        "eventType":"state_assessment","detectedAt":"2026-10-29T09:00:00.000+0900","snoozeCount":0,
        "context":{"time_of_day":"morning","typing_active":false,"calendar_busy":false}}
        """
        let q = try NarrativeJSON.decoder.decode(PendingQuestion.self, from: Data(json.utf8))
        XCTAssertEqual(q.kind, .currentState)
        let name = "test.research.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = NarrativeState(defaults: defaults)
        state.markAnsweredRequest(q.id)
        XCTAssertTrue(NarrativeState(defaults: defaults).hasAnsweredRequest(q.id))
        XCTAssertEqual(QuestionCatalog.template(for: .currentState).cooldown, 10800)
    }
}
