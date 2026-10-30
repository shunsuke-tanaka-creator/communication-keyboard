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

    func testAnonymousPlaceGrowthAndRestore() throws {
        var map = AutomaticPlaceMap()
        let a = try XCTUnwrap(map.classify(latitude: 35.68, longitude: 139.76, accuracy: 20))
        XCTAssertEqual(a, map.classify(latitude: 35.6801, longitude: 139.7601, accuracy: 30))
        let b = try XCTUnwrap(map.classify(latitude: 35.70, longitude: 139.80, accuracy: 30))
        XCTAssertNotEqual(a, b)
        XCTAssertNil(map.classify(latitude: 35.9, longitude: 139.8, accuracy: 1000))
        XCTAssertNil(map.classify(latitude: .nan, longitude: 139.8, accuracy: 10))
        var restored = try JSONDecoder().decode(AutomaticPlaceMap.self, from: JSONEncoder().encode(map))
        XCTAssertEqual(a, restored.classify(latitude: 35.68, longitude: 139.76, accuracy: 20))
        XCTAssertEqual(restored.nodes.count, 2)
    }

    func testWeatherIsNominalAndStateScalesRemainIndependent() {
        XCTAssertEqual(WeatherMood.allCases.count, 4)
        XCTAssertEqual(StateAssessment.keys.count, 5)
        XCTAssertEqual(StateAssessment.options(index: 1).map(\.value), ["scale:fatigue:1","scale:fatigue:2","scale:fatigue:3","scale:fatigue:4","scale:fatigue:5","scale:fatigue:skip"])
        XCTAssertTrue(WeatherMood.angry.label.contains("雷"))
    }

    func testEventEncodingDoesNotUploadCoordinates() throws {
        let event = ResearchWorkflowEvent(kind: "place_visit", payload: ["place_id": .string("place_A"),
            "phase": .string("arrival"), "accuracy_m": .number(30)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: NarrativeJSON.encoder.encode(event)) as? [String: Any])
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? String, "research-v2")
        XCTAssertNil(payload["latitude"]); XCTAssertNil(payload["longitude"])
        XCTAssertEqual(payload["place_id"] as? String, "place_A")
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
