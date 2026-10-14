import XCTest
@testable import MozcFlickShared

final class SessionRotationTests: XCTestCase {
    func testPeriodicUploadPreservesLoggingAndSessionBoundaries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = SessionLogger(idleTimeout: 10, maximumDuration: 0.05, directory: directory)
        let first = expectation(description: "periodic session closed")
        var sessions: [LoggedSession] = []
        logger.onSessionClosed = { session in
            sessions.append(session)
            if sessions.count == 1 { first.fulfill() }
        }
        logger.enable()
        logger.log(type: "key", data: ["key": "あ"])
        wait(for: [first], timeout: 2)
        XCTAssertEqual(sessions.first?.closeReason, "interval")
        logger.log(type: "key", data: ["key": "か"])
        logger.stop(reason: "keyboard_hidden")
        XCTAssertEqual(sessions.count, 2)
        XCTAssertNotEqual(sessions[0].sessionID, sessions[1].sessionID)
        XCTAssertEqual(sessions[0].events.count, 1)
        XCTAssertEqual(sessions[1].events.first?.data["key"], "か")
        logger.log(type: "key", data: ["key": "さ"])
        logger.stop()
        XCTAssertEqual(sessions.count, 2, "Hidden keyboard must not log")
    }

    func testIdleTimeoutCanStartAnotherSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = SessionLogger(idleTimeout: 0.03, maximumDuration: 10, directory: directory)
        let idle = expectation(description: "idle closed")
        var sessions: [LoggedSession] = []
        logger.onSessionClosed = { session in
            sessions.append(session)
            if sessions.count == 1 { idle.fulfill() }
        }
        logger.enable()
        logger.log(type: "delete", data: [:])
        wait(for: [idle], timeout: 2)
        XCTAssertEqual(sessions[0].closeReason, "idle_timeout")
        logger.log(type: "key", data: [:])
        logger.stop()
        XCTAssertEqual(sessions.count, 2)
    }
}
