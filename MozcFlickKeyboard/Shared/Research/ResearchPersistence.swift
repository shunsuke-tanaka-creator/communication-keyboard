import Foundation
import Darwin

/// Cross-process append lock for the App and Extension. Never logs event contents.
public enum ResearchPersistence {
    @discardableResult
    public static func appendJSONLine(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { return false }
            defer { Darwin.close(fd) }
            guard flock(fd, LOCK_EX) == 0 else { return false }
            defer { flock(fd, LOCK_UN) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            // A retry of the same answer must not duplicate the local record.
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = object["event_id"] as? String,
               let existing = try handle.readToEnd(), let text = String(data: existing, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    if let bytes = String(line).data(using: .utf8),
                       let row = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                       row["event_id"] as? String == id { return true }
                }
            }
            try handle.seekToEnd()
            var line = data; line.append(0x0A)
            try handle.write(contentsOf: line)
            try handle.synchronize()
            return true
        } catch { return false }
    }

    public static func isPermanentHTTPFailure(_ code: Int) -> Bool {
        [400, 413, 422].contains(code) // Auth, timeouts, rate limits and 5xx remain retryable.
    }

    @discardableResult
    public static func quarantine(_ url: URL, reason: String, expected: Data? = nil) -> Bool {
        do {
            if let expected, (try? Data(contentsOf: url)) != expected { return true }
            let destination = url.appendingPathExtension("failed-" + reason + "-" + UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return true
        } catch { return !FileManager.default.fileExists(atPath: url.path) }
    }

    public static func restoreQuarantined(in directory: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var count = 0
        for file in files where file.pathExtension.hasPrefix("failed-") {
            let target = file.deletingPathExtension()
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            do { try FileManager.default.moveItem(at: file, to: target); count += 1 } catch { }
        }
        return count
    }
}

public enum ResearchClock {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
}
