import Foundation
import CryptoKit
import MozcFlickShared

struct LifeLogDashboard: Codable {
    struct Scanner: Codable { let state: String; let error: String?; let lastReceivedAt: Date? }
    struct Activity: Codable { let label: String; let source: String; let evidence: String; let observedAt: Date? }
    struct Device: Codable {
        let deviceId: String
        let name: String
        let state: String
        let battery: Int?
        let lastSeen: Date?
        let rssi: Int?
        let stale: Bool
        var stateLabel: String {
            switch state {
            case "open": return "開いている"
            case "close": return "閉じている"
            case "timeOutNotClose": return "開いたまま"
            default: return "不明"
            }
        }
    }
    struct Summary: Codable {
        let text: String
        let sessionCount: Int
        let typedCharacters: Int
        let answerCount: Int
        let doorChanges: Int
    }
    struct Timeline: Codable {
        let id: String
        let recordId: String
        let kind: String
        let occurredAt: Date
        let title: String
        let detail: String
        var source: String {
            switch kind {
            case "switchbot": return "SwitchBot"
            case "session": return "キーボード"
            case "narrative": return "本人の回答"
            case "sensor": return "疑似センサー"
            default: return "活動記録"
            }
        }
    }
    struct Context: Codable {
        let stepCount: Double?
        let walkingDistanceM: Double?
        let batteryLevel: Double?
        let updatedAt: Date?
    }
    let day: String
    let generatedAt: Date
    let scanner: Scanner
    let currentActivity: Activity
    let devices: [Device]
    let summary: Summary
    let deviceContext: Context?
    var timeline: [Timeline]
    let totalEvents: Int
    var nextOffset: Int?
    let snapshotSeq: Int
}

final class LifeLogAPI {
    enum Failure: LocalizedError {
        case invalidURL, http(Int), invalidResponse
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "設定でMacBookの接続先を確認してください。"
            case .http(403): return "接続が拒否されました。iPhoneのTailscale IPとサーバーの許可設定を確認してください。"
            case .http(let code): return "サーバーエラー（HTTP \(code)）"
            case .invalidResponse: return "サーバーの応答を読み取れませんでした。"
            }
        }
    }
    let baseURL: String
    let participant: String
    init(baseURL: String, participant: String) { self.baseURL = baseURL; self.participant = participant }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return decoder
    }

    private func url(_ components: [String], query: [URLQueryItem] = []) throws -> URL {
        guard var url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw Failure.invalidURL }
        for component in components { url.appendPathComponent(component) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw Failure.invalidURL }
        parts.queryItems = query.isEmpty ? nil : query
        guard let result = parts.url else { throw Failure.invalidURL }
        return result
    }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw Failure.http(response.statusCode) }
        return data
    }

    func dashboard(day: String, offset: Int = 0, snapshot: Int? = nil) async throws -> LifeLogDashboard {
        var query = [URLQueryItem(name: "day", value: day), URLQueryItem(name: "offset", value: String(offset))]
        if let snapshot { query.append(URLQueryItem(name: "snapshot_seq", value: String(snapshot))) }
        let data = try await request(url(["api", "dashboard", participant], query: query))
        let result = try Self.decoder().decode(LifeLogDashboard.self, from: data)
        if offset == 0, let cache = cacheURL(day: day) {
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cache, options: .atomic)
        }
        return result
    }

    func cached(day: String) -> LifeLogDashboard? {
        guard let file = cacheURL(day: day), let data = try? Data(contentsOf: file) else { return nil }
        return try? Self.decoder().decode(LifeLogDashboard.self, from: data)
    }

    private func cacheURL(day: String) -> URL? {
        let hash = SHA256.hash(data: Data((baseURL + "|" + participant + "|" + day).utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LifeLog").appendingPathComponent(hash + ".json")
    }

    func rename(device: String, name: String) async throws {
        let body = try JSONEncoder().encode(["participant_id": participant, "name": name])
        _ = try await request(url(["api", "devices", device, "name"]), method: "PUT", body: body)
    }

    func detail(_ item: LifeLogDashboard.Timeline) async throws -> String {
        let data = try await request(url(["api", "records", participant, item.kind, item.recordId]))
        let json = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: pretty, encoding: .utf8) ?? ""
    }

    func sync() async {
        // Keep the upload client alive until ACK; sync finishes before dashboard GET.
        await withCheckedContinuation { continuation in
            ResearchAPIClient(baseURL: baseURL).flushPendingSessions { _ in continuation.resume() }
        }
        await withCheckedContinuation { continuation in
            RemoteRepository(baseURL: baseURL, store: NarrativeStore()).flushUnsent { _ in continuation.resume() }
        }
    }
}
