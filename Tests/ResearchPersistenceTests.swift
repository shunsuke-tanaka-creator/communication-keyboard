import XCTest
@testable import MozcFlickShared

final class ResearchPersistenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testAppendAndRetryKeepExactlyOneRecord() throws {
        let url = try temporaryDirectory().appendingPathComponent("events.jsonl")
        let data = Data(#"{"event_id":"same","answer":"kept"}"#.utf8)
        XCTAssertTrue(ResearchPersistence.appendJSONLine(data, to: url))
        XCTAssertTrue(ResearchPersistence.appendJSONLine(data, to: url))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
    }
    func testFileInPlaceOfDirectoryReportsSaveFailure() throws {
        let root = try temporaryDirectory().appendingPathComponent("blocker")
        try Data().write(to: root)
        XCTAssertFalse(ResearchPersistence.appendJSONLine(Data("{}".utf8), to: root.appendingPathComponent("event.jsonl")))
        let box = ResearchEventOutbox(directory: root)
        XCTAssertFalse(box.enqueue(["answer": "retained in UI"], route: "api/narrative-events", id: "id"))
    }
    func testConcurrentJSONLAppendDoesNotOverwriteOtherWriter() throws {
        let url = try temporaryDirectory().appendingPathComponent("events.jsonl")
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            let data = Data("{\"event_id\":\"\(index)\"}".utf8)
            XCTAssertTrue(ResearchPersistence.appendJSONLine(data, to: url))
        }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 30)
        for line in lines { XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8))) }
    }
    func testPoisonRecordIsRetainedAndCanBeRestored() throws {
        let root = try temporaryDirectory(); let file = root.appendingPathComponent("bad.json")
        let bytes = Data("corrupt".utf8); try bytes.write(to: file)
        XCTAssertTrue(ResearchPersistence.quarantine(file, reason: "decode"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let failed = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: failed), bytes)
        XCTAssertEqual(ResearchPersistence.restoreQuarantined(in: root), 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testNewerQueuedBodyIsNotQuarantinedByOlderFailure() throws {
        let file = try temporaryDirectory().appendingPathComponent("event.json")
        let old = Data("old".utf8), new = Data("new".utf8)
        try new.write(to: file)
        XCTAssertTrue(ResearchPersistence.quarantine(file, reason: "422", expected: old))
        XCTAssertEqual(try Data(contentsOf: file), new)
    }
    func testLegacyGPSQueueIsNeverRestored() throws {
        let root = try temporaryDirectory(); let file = root.appendingPathComponent("old.json.gps-disabled")
        try Data("legacy".utf8).write(to: file)
        XCTAssertEqual(ResearchPersistence.restoreQuarantined(in: root), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testRetryPolicyRetainsAuthRateLimitAndServerErrors() {
        for code in [400, 413, 422] { XCTAssertTrue(ResearchPersistence.isPermanentHTTPFailure(code)) }
        for code in [401, 403, 408, 429, 500, 503] { XCTAssertFalse(ResearchPersistence.isPermanentHTTPFailure(code)) }
    }
    func testDurableOutboxRetriesSameIDWithoutDuplicating() throws {
        let box = ResearchEventOutbox(directory: try temporaryDirectory())
        XCTAssertTrue(box.enqueue(["answer": "a"], route: "api/narrative-events", id: "same"))
        XCTAssertTrue(box.enqueue(["answer": "a"], route: "api/narrative-events", id: "same"))
        XCTAssertEqual(box.pendingCount, 1)
    }
    func testResearchDayUsesJSTEvenIfDeviceUsesAnotherZone() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T15:30:00Z"))
        XCTAssertEqual(ResearchClock.calendar.component(.day, from: date), 2)
        XCTAssertEqual(ResearchClock.calendar.component(.hour, from: date), 0)
    }
    func testBannerDoesNotExcludeNormalTypingAndAnswerInputDoes() throws {
        let date = Date(); let event = SessionEvent(time: NarrativeJSON.dateFormatter.string(from: date), type: "commit", data: ["text": "hello"])
        XCTAssertNil(ResearchSessionEvents.markAssessments([event], intervals: [], activeStart: nil)[0].data["purpose"])
        XCTAssertEqual(ResearchSessionEvents.markAssessments([event], intervals: [(date.addingTimeInterval(-1), date.addingTimeInterval(1))], activeStart: nil)[0].data["purpose"], "assessment")
    }
}
