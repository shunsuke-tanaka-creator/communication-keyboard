import Foundation

/// 学習ストアのエラー。
public enum LearningError: Error, LocalizedError {
    case sharedContainerUnavailable
    case encodeFailed(underlying: Error)
    case writeFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable: return "共有データ領域を利用できません。"
        case .encodeFailed, .writeFailed: return "学習データの保存に失敗しました。"
        }
    }

    public var debugDetail: String {
        switch self {
        case .sharedContainerUnavailable: return "App Group container URL is nil."
        case .encodeFailed(let e): return "encode failed: \(e)"
        case .writeFailed(let e): return "write failed: \(e)"
        }
    }
}

/// 1件の学習レコード（読み+確定語ごとの頻度と最終使用）。
public struct LearningRecord: Codable, Equatable, Sendable {
    public let reading: String   // 正規化済みよみ
    public let word: String      // 確定した語
    public var frequency: Int
    public var lastUsedAt: Date

    public init(reading: String, word: String, frequency: Int, lastUsedAt: Date) {
        self.reading = reading
        self.word = word
        self.frequency = frequency
        self.lastUsedAt = lastUsedAt
    }
}

/// 候補順位の学習ストア（完全ローカル / App Group 共有コンテナへ保存）。
/// - 学習 ON/OFF・プライベートモード・保存件数上限
/// - Secure Text Entry / パスワードらしい入力を学習しないためのフラグ引数
/// - 破損時復旧・スキーマバージョン
public final class LearningStore {

    // MARK: - スキーマ

    public static let schemaVersion = 1

    private struct LearningFile: Codable {
        var schemaVersion: Int
        var records: [LearningRecord]
    }

    // MARK: - 設定

    /// 学習全体の有効/無効。false の間は記録しない。
    public var isLearningEnabled: Bool = true

    /// プライベートモード。true の間は記録しない（設定は永続化しない揮発フラグ）。
    public var isPrivateMode: Bool = false

    /// 保存件数上限。超過時は頻度低→最終使用古い順に破棄。
    public let maxRecords: Int

    // MARK: - 状態

    private let fileManager: FileManager
    private let fileURL: URL
    private let backupURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// キー "reading\tword" → レコード。
    private var records: [String: LearningRecord] = [:]

    // MARK: - init

    public init(fileManager: FileManager = .default,
                directoryName: String = "Learning",
                maxRecords: Int = 5000) throws {
        self.fileManager = fileManager
        self.maxRecords = maxRecords

        guard let base = AppConfig.sharedContainerURL else {
            throw LearningError.sharedContainerUnavailable
        }
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("learning.json")
        self.backupURL = dir.appendingPathComponent("learning.backup.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    // MARK: - キー

    private func key(reading: String, word: String) -> String {
        "\(reading)\t\(word)"
    }

    // MARK: - 読み込み / 復旧

    private func load() {
        if let loaded = tryDecode(url: fileURL) {
            apply(loaded); return
        }
        if let backup = tryDecode(url: backupURL) {
            apply(backup)
            try? persist()
            return
        }
        records.removeAll()
    }

    private func tryDecode(url: URL) -> [LearningRecord]? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let file = try? decoder.decode(LearningFile.self, from: data) else {
            return nil
        }
        return file.records
    }

    private func apply(_ recs: [LearningRecord]) {
        records.removeAll()
        for r in recs {
            records[key(reading: r.reading, word: r.word)] = r
        }
    }

    // MARK: - 永続化

    private func persist() throws {
        let file = LearningFile(schemaVersion: Self.schemaVersion,
                                records: Array(records.values))
        let data: Data
        do {
            data = try encoder.encode(file)
        } catch {
            throw LearningError.encodeFailed(underlying: error)
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: fileURL, to: backupURL)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw LearningError.writeFailed(underlying: error)
        }
    }

    // MARK: - 記録

    /// 確定を記録する。
    /// - Parameter isSecureInput: Secure Text Entry 等のパスワードらしい入力なら true → 記録しない。
    public func recordSelection(reading rawReading: String,
                                word: String,
                                isSecureInput: Bool = false,
                                at date: Date = Date()) throws {
        guard isLearningEnabled, !isPrivateMode, !isSecureInput else { return }
        let reading = ReadingNormalizer.normalize(rawReading)
        guard !reading.isEmpty, !word.isEmpty else { return }

        let k = key(reading: reading, word: word)
        if var existing = records[k] {
            existing.frequency += 1
            existing.lastUsedAt = date
            records[k] = existing
        } else {
            records[k] = LearningRecord(reading: reading, word: word,
                                        frequency: 1, lastUsedAt: date)
        }
        enforceLimit()
        try persist()
    }

    /// 上限超過時、頻度低→最終使用古い順に破棄。
    private func enforceLimit() {
        guard records.count > maxRecords else { return }
        let sorted = records.values.sorted {
            $0.frequency == $1.frequency ? $0.lastUsedAt < $1.lastUsedAt : $0.frequency < $1.frequency
        }
        let overflow = records.count - maxRecords
        for r in sorted.prefix(overflow) {
            records.removeValue(forKey: key(reading: r.reading, word: r.word))
        }
    }

    // MARK: - 参照

    /// 指定よみに対する学習スコア（word → frequency）。CandidateReranker が使う。
    public func scores(forReading rawReading: String) -> [String: Int] {
        let reading = ReadingNormalizer.normalize(rawReading)
        guard !reading.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        let prefix = "\(reading)\t"
        for (k, r) in records where k.hasPrefix(prefix) {
            result[r.word] = r.frequency
        }
        return result
    }

    /// 指定よみ+語の最終使用日時（タイブレーク用）。
    public func lastUsed(reading rawReading: String, word: String) -> Date? {
        let reading = ReadingNormalizer.normalize(rawReading)
        return records[key(reading: reading, word: word)]?.lastUsedAt
    }

    public var count: Int { records.count }

    // MARK: - リセット

    /// 学習データを全消去する。
    public func reset() throws {
        records.removeAll()
        try persist()
    }
}
