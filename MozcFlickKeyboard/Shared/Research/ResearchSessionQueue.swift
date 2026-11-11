import Foundation

/// 追加: 未送信セッションを App Group の1セッション1ファイルで保持する再送キュー。
public final class ResearchSessionQueue {
    public static var directoryURL: URL? {
        AppConfig.sharedContainerURL?.appendingPathComponent("Library/Application Support/PendingResearchSessions", isDirectory: true)
    }

    public init(directory: URL? = nil) {
        self.overrideDirectory = directory
        guard directory == nil else { return }
        // Preserve queues written by previous app versions; pending uploads must not live in Caches.
        guard let old = AppConfig.sharedContainerURL?.appendingPathComponent("Library/Caches/PendingResearchSessions"),
              let directory = Self.directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.moveItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
        }
    }

    private let overrideDirectory: URL?
    private var directory: URL? { overrideDirectory ?? Self.directoryURL }

    @discardableResult
    public func enqueue(_ payload: ResearchSessionUpload) -> Bool {
        guard let directory, !payload.sessionID.isEmpty,
              !payload.sessionID.contains("/"), payload.sessionID != ".", payload.sessionID != ".." else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try NarrativeJSON.encoder.encode(payload)
            try data.write(to: directory.appendingPathComponent(payload.sessionID).appendingPathExtension("json"), options: .atomic)
            return true
        } catch { return false }
    }

    public var pendingFiles: [URL] {
        guard let directory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
    }

    public var pendingCount: Int { pendingFiles.count }

    /// Compatibility read for exports; the network sender loads only one file at a time.
    public func loadAll() -> [ResearchSessionUpload] {
        pendingFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? NarrativeJSON.decoder.decode(ResearchSessionUpload.self, from: data)
        }.sorted { $0.startedAt < $1.startedAt }
    }

    public func remove(sessionID: String) {
        guard let directory else { return }
        let url = directory.appendingPathComponent(sessionID).appendingPathExtension("json")
        try? FileManager.default.removeItem(at: url)
    }
}
