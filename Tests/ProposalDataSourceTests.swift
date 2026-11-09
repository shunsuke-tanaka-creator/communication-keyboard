import XCTest
@testable import MozcFlickShared

final class ProposalDataSourceTests: XCTestCase {
    func testPreviewResponseDecodesQuestionGatesAndContainsSample() throws {
        let json = """
        {
          "preview": true,
          "participant": "p001",
          "data_mode": "sample",
          "contains_sample": true,
          "at": "2026-11-09T12:00:00.000Z",
          "question": {
            "id": "preview-1",
            "participantID": "p001",
            "kind": "weatherMood",
            "prompt": "今の気分を天気でいうと？",
            "options": [{"label": "晴れ", "value": "happy"}],
            "allowFreeText": false,
            "eventType": "preview",
            "detectedAt": "2026-11-09T11:59:00.000Z",
            "questionShownAt": null,
            "snoozeCount": 0,
            "expiresAt": "2026-11-09T13:00:00.000Z",
            "context": {
              "time_of_day": "afternoon",
              "typing_active": false,
              "calendar_busy": false,
              "external_trigger": "server-v2"
            }
          },
          "gates": {
            "daily_limit": {"passed": true, "detail": "within limit"},
            "cooldown": {"passed": false, "detail": "preview detail"}
          }
        }
        """
        let response = try NarrativeJSON.decoder.decode(PreviewResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.preview)
        XCTAssertTrue(response.containsSample)
        XCTAssertEqual(response.dataMode, "sample")
        XCTAssertEqual(response.question?.id, "preview-1")
        XCTAssertEqual(response.question?.kind, .weatherMood)
        XCTAssertEqual(response.gates["daily_limit"]?.passed, true)
        XCTAssertEqual(response.gates["cooldown"]?.detail, "preview detail")
    }

    func testPreferenceDefaultsToActualAndRoundTrips() throws {
        let name = "ProposalDataSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = NarrativeState(defaults: defaults)
        XCTAssertEqual(state.proposalDataSource, .actual)
        state.proposalDataSource = .sample
        XCTAssertEqual(NarrativeState(defaults: defaults).proposalDataSource, .sample)
        state.proposalDataSource = .combined
        XCTAssertEqual(NarrativeState(defaults: defaults).proposalDataSource, .combined)
    }

    func testFetchRoutingUsesPendingOnlyForActual() {
        XCTAssertEqual(ProposalFetchRoute.route(for: .actual), .pending)
        XCTAssertEqual(ProposalFetchRoute.route(for: .sample), .preview(dataMode: "sample"))
        XCTAssertEqual(ProposalFetchRoute.route(for: .combined), .preview(dataMode: "combined"))
    }
}
