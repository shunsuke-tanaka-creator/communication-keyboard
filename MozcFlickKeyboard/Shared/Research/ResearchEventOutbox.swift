import Foundation
import CryptoKit

/// One durable file per event. An ACK removes only that event, never concurrently queued answers.
public final class ResearchEventOutbox {
    private struct Entry: Codable { let route: String; let body: Data }
    private static var directory: URL? {
        AppConfig.sharedContainerURL?.appendingPathComponent("Library/Application Support/ResearchOutbox", isDirectory: true)
    }
    public init() {}

    @discardableResult
    public func enqueue<T: Encodable>(_ event: T, route: String, id: String) -> Bool {
        guard let directory = Self.directory else { return false }
        do {
            let body = try NarrativeJSON.encoder.encode(event)
            let hash = SHA256.hash(data: Data((route + id).utf8)).map { String(format: "%02x", $0) }.joined()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Entry(route: route, body: body)).write(to: directory.appendingPathComponent(hash + ".json"), options: .atomic)
            return true
        } catch { return false }
    }

    public var pendingCount: Int { files.count }
    private var files: [URL] {
        guard let directory = Self.directory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func flush(baseURL: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: root), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            completion(false); return
        }
        send(files, index: 0, root: url, completion: completion)
    }

    private func send(_ files: [URL], index: Int, root: URL, completion: @escaping (Bool) -> Void) {
        guard index < files.count else { completion(true); return }
        let file = files[index]
        guard let data = try? Data(contentsOf: file), let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            // Another process may already have acknowledged the same event.
            if !FileManager.default.fileExists(atPath: file.path) { send(files, index: index + 1, root: root, completion: completion) }
            else { completion(false) }
            return
        }
        var request = URLRequest(url: root.appendingPathComponent(entry.route), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = entry.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { [self] _, response, error in
            guard error == nil, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                completion(false); return
            }
            if (try? Data(contentsOf: file)) == data { try? FileManager.default.removeItem(at: file) }
            send(files, index: index + 1, root: root, completion: completion)
        }.resume()
    }
}
