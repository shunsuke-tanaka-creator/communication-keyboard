import XCTest
@testable import MozcFlickShared

final class ResearchWorkflowTests: XCTestCase {
    func testServerQuestionContractIncludingCurrentState() throws {
        struct Fixture: Decodable { let questions: [PendingQuestion] }
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "workflow-contract", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let questions = try NarrativeJSON.decoder.decode(Fixture.self, from: data).questions
        XCTAssertTrue(questions.contains { $0.kind == .currentState })
        XCTAssertTrue(questions.allSatisfy { $0.expiresAt != nil })
        let weather = try XCTUnwrap(questions.first { $0.kind == .weatherMood })
        XCTAssertEqual(Set(weather.options.map(\.value)), Set(WeatherMood.allCases.map(\.rawValue)))
        XCTAssertEqual(questions.first { $0.kind == .supportOutcome }?.relatedID, "offered-break")
        for q in questions { _ = try NarrativeJSON.decoder.decode(PendingQuestion.self, from: NarrativeJSON.encoder.encode(q)) }
    }

    func testBehaviorContextQuestionContract() throws {
        struct Fixture: Decodable { let questions: [PendingQuestion] }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "workflow-contract", withExtension: "json"))
        let questions = try NarrativeJSON.decoder.decode(Fixture.self, from: Data(contentsOf: url)).questions
        let base = try XCTUnwrap(questions.first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NarrativeJSON.encoder.encode(base)) as? [String: Any])
        for kind in ["placeCheck", "taskCheck"] {
            json["kind"] = kind
            json["options"] = [["label": "候補", "value": kind == "placeCheck" ? "place_a" : "task_a"]]
            let q = try NarrativeJSON.decoder.decode(PendingQuestion.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNotNil(ResearchWorkflow.contextAnswer(q, value: q.options[0].value))
            XCTAssertNil(ResearchWorkflow.contextAnswer(q, value: "unoffered"))
            let body = try XCTUnwrap(ResearchWorkflow.contextAnswer(q, value: q.options[0].value))
            let encoded = try JSONEncoder().encode(body)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: String])
            XCTAssertEqual(object["axis"], kind == "placeCheck" ? "place" : "task")
            XCTAssertEqual(object["question_id"], q.id)
            XCTAssertNil(object["latitude"])
        }
    }

    func testWeatherIsNominalAndStateScalesRemainIndependent() {
        XCTAssertEqual(WeatherMood.allCases.count, 4)
        XCTAssertEqual(StateAssessment.keys.count, 5)
        XCTAssertEqual(StateAssessment.options(index: 1).map(\.value), ["scale:fatigue:1","scale:fatigue:2","scale:fatigue:3","scale:fatigue:4","scale:fatigue:5","scale:fatigue:skip"])
        XCTAssertTrue(WeatherMood.angry.label.contains("雷"))
    }

    func testEventEncodingDoesNotUploadCoordinates() throws {
        let event = ResearchWorkflowEvent(kind: "context_label", payload: ["axis": .string("place"), "class_id": .string("place_A"),
            "start": .string("2026-11-10T10:00:00+09:00"), "end": .string("2026-11-10T10:05:00+09:00")])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: NarrativeJSON.encoder.encode(event)) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? String, "research-v2")
        XCTAssertNil(payload["latitude"]); XCTAssertNil(payload["longitude"])
        XCTAssertEqual(payload["class_id"] as? String, "place_A")
    }

    func testCompositionAndCommittedDeletionBothCount() {
        let metrics = TypingMetrics()
        let t = Date()
        metrics.recordKeystroke(at: t)
        metrics.recordKeystroke(at: t.addingTimeInterval(1))
        metrics.recordBackspace(at: t.addingTimeInterval(2))
        metrics.recordBackspace(at: t.addingTimeInterval(3))
        XCTAssertEqual(metrics.snapshot(now: t.addingTimeInterval(4)).backspaceCount, 2)
    }
}
