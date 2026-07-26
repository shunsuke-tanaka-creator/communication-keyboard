import Foundation

/// ユーザー辞書関連のエラー。ユーザー向け(errorDescription)と開発者向け(debugDetail)を分離。
public enum UserDictionaryError: Error, LocalizedError {
    case sharedContainerUnavailable
    case emptyReading
    case emptyWord
    case duplicateEntry(reading: String, word: String)
    case entryNotFound(id: UUID)
    case encodeFailed(underlying: Error)
    case decodeFailed(underlying: Error)
    case writeFailed(underlying: Error)

    /// ユーザー向けメッセージ（入力文字列は含めない）。
    public var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "共有データ領域を利用できません。"
        case .emptyReading:
            return "よみを入力してください。"
        case .emptyWord:
            return "単語を入力してください。"
        case .duplicateEntry:
            return "同じよみと単語の項目が既に登録されています。"
        case .entryNotFound:
            return "対象の項目が見つかりませんでした。"
        case .encodeFailed, .writeFailed:
            return "辞書の保存に失敗しました。"
        case .decodeFailed:
            return "辞書の読み込みに失敗しました。"
        }
    }

    /// 開発者向け詳細（ログ用。入力語そのものは載せない）。
    public var debugDetail: String {
        switch self {
        case .sharedContainerUnavailable: return "App Group container URL is nil."
        case .emptyReading: return "reading is empty after normalization."
        case .emptyWord: return "word is empty."
        case .duplicateEntry: return "duplicate (reading, word) pair."
        case .entryNotFound(let id): return "entry not found: \(id)."
        case .encodeFailed(let e): return "encode failed: \(e)"
        case .decodeFailed(let e): return "decode failed: \(e)"
        case .writeFailed(let e): return "write failed: \(e)"
        }
    }
}

/// 検索・並び替えの基準。
public enum DictionarySortKey: Sendable {
    case readingAscending
    case updatedAtDescending
    case createdAtDescending
}

/// ユーザー辞書の永続化ストア（App Group 共有コンテナへ JSON 保存）。
/// - スキーマバージョン管理
/// - 破損時はバックアップ復旧 → 失敗なら空初期化
/// - 前方一致検索用の内部インデックス
public final class UserDictionaryStore {

    // MARK: - 永続化スキーマ

    /// 現在のスキーマバージョン。破壊的変更時に上げてマイグレーションを行う。
    public static let schemaVersion = 1

    /// ディスク保存フォーマット。version を先頭に持たせる。
    private struct DictionaryFile: Codable {
        var schemaVersion: Int
        var entries: [UserDictionaryEntry]
    }

    // MARK: - 状態

    private let fileManager: FileManager
    private let containerURL: URL
    private let fileURL: URL
    private let backupURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 内部保持データ。id → entry で管理し順序は sortedIDs で持つ。
    private var entriesByID: [UUID: UserDictionaryEntry] = [:]

    /// 前方一致検索インデックス: 正規化よみ → その読みを持つ entry の id 集合。
    /// 読みそのものをキーにし、検索時は正規化よみ全走査で prefix 判定する。
    private var readingIndex: [String: Set<UUID>] = [:]

    // MARK: - 初期化

    /// - Parameters:
    ///   - fileManager: 差し替え用（テスト）。
    ///   - directoryName: 共有コンテナ内サブディレクトリ名。
    ///   - baseURL: ベースディレクトリの差し替え（テスト）。nil なら App Group 共有コンテナを使う。
    public init(fileManager: FileManager = .default,
                directoryName: String = "UserDictionary",
                baseURL: URL? = nil) throws {
        self.fileManager = fileManager

        guard let base = baseURL ?? AppConfig.sharedContainerURL else {
            throw UserDictionaryError.sharedContainerUnavailable
        }
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        self.containerURL = dir
        self.fileURL = dir.appendingPathComponent("user_dictionary.json")
        self.backupURL = dir.appendingPathComponent("user_dictionary.backup.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    // MARK: - 読み込み / 復旧

    /// ディスクから読み込む。破損時はバックアップ→空初期化の順で復旧。
    private func load() {
        if let loaded = tryDecode(url: fileURL) {
            apply(loaded)
            return
        }
        // 本体破損 → バックアップから復旧。
        if let backup = tryDecode(url: backupURL) {
            apply(backup)
            // 復旧内容を本体へ書き戻す（失敗は無視: 次回起動で再試行）。
            try? persist()
            return
        }
        // どちらも無い/破損 → 空初期化。
        applyEmpty()
    }

    private func tryDecode(url: URL) -> [UserDictionaryEntry]? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return nil
        }
        guard let file = try? decoder.decode(DictionaryFile.self, from: data) else {
            return nil
        }
        // スキーマ移行が必要ならここで行う（現状 v1 のみ）。
        return file.entries
    }

    private func apply(_ entries: [UserDictionaryEntry]) {
        entriesByID.removeAll()
        readingIndex.removeAll()
        for e in entries {
            entriesByID[e.id] = e
            indexInsert(e)
        }
    }

    private func applyEmpty() {
        entriesByID.removeAll()
        readingIndex.removeAll()
    }

    // MARK: - インデックス操作

    private func indexInsert(_ e: UserDictionaryEntry) {
        let key = ReadingNormalizer.normalize(e.reading)
        readingIndex[key, default: []].insert(e.id)
    }

    private func indexRemove(_ e: UserDictionaryEntry) {
        let key = ReadingNormalizer.normalize(e.reading)
        readingIndex[key]?.remove(e.id)
        if readingIndex[key]?.isEmpty == true {
            readingIndex.removeValue(forKey: key)
        }
    }

    // MARK: - 永続化

    /// 現在の内容をディスクへ書き込む。書込前に本体をバックアップへ退避。
    private func persist() throws {
        let file = DictionaryFile(schemaVersion: Self.schemaVersion,
                                  entries: Array(entriesByID.values))
        let data: Data
        do {
            data = try encoder.encode(file)
        } catch {
            throw UserDictionaryError.encodeFailed(underlying: error)
        }

        // 既存本体をバックアップへ複製（存在時のみ）。
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: fileURL, to: backupURL)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            // ファイル保護属性: 初回認証後まではアクセス不可。
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw UserDictionaryError.writeFailed(underlying: error)
        }
    }

    // MARK: - CRUD

    /// 追加。読みは正規化して重複チェックする。
    @discardableResult
    public func add(reading: String,
                    word: String,
                    partOfSpeech: PartOfSpeech = .noun,
                    comment: String = "") throws -> UserDictionaryEntry {
        let normalized = ReadingNormalizer.normalize(reading)
        guard !normalized.isEmpty else { throw UserDictionaryError.emptyReading }
        guard !word.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UserDictionaryError.emptyWord
        }
        if findDuplicate(normalizedReading: normalized, word: word) != nil {
            throw UserDictionaryError.duplicateEntry(reading: normalized, word: word)
        }

        let entry = UserDictionaryEntry(reading: reading,
                                        word: word,
                                        partOfSpeech: partOfSpeech,
                                        comment: comment)
        entriesByID[entry.id] = entry
        indexInsert(entry)
        try persist()
        return entry
    }

    /// 既存項目を差し替え更新。読み変更時はインデックスも張り直す。
    @discardableResult
    public func update(_ entry: UserDictionaryEntry) throws -> UserDictionaryEntry {
        guard let old = entriesByID[entry.id] else {
            throw UserDictionaryError.entryNotFound(id: entry.id)
        }
        let normalized = ReadingNormalizer.normalize(entry.reading)
        guard !normalized.isEmpty else { throw UserDictionaryError.emptyReading }
        guard !entry.word.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UserDictionaryError.emptyWord
        }
        // 自分以外に同一(読み,語)があれば重複。
        if let dup = findDuplicate(normalizedReading: normalized, word: entry.word),
           dup.id != entry.id {
            throw UserDictionaryError.duplicateEntry(reading: normalized, word: entry.word)
        }

        indexRemove(old)
        var updated = entry
        updated.updatedAt = Date()
        entriesByID[updated.id] = updated
        indexInsert(updated)
        try persist()
        return updated
    }

    /// 削除。
    public func remove(id: UUID) throws {
        guard let e = entriesByID[id] else {
            throw UserDictionaryError.entryNotFound(id: id)
        }
        indexRemove(e)
        entriesByID.removeValue(forKey: id)
        try persist()
    }

    /// 全削除。
    public func removeAll() throws {
        applyEmpty()
        try persist()
    }

    /// 有効/無効の切り替え。
    @discardableResult
    public func setEnabled(id: UUID, isEnabled: Bool) throws -> UserDictionaryEntry {
        guard var e = entriesByID[id] else {
            throw UserDictionaryError.entryNotFound(id: id)
        }
        e.isEnabled = isEnabled
        e.updatedAt = Date()
        entriesByID[id] = e
        try persist()
        return e
    }

    // MARK: - 参照 / 検索

    /// 全件を指定順で返す。
    public func allEntries(sortedBy key: DictionarySortKey = .readingAscending) -> [UserDictionaryEntry] {
        sort(Array(entriesByID.values), by: key)
    }

    /// id 取得。
    public func entry(id: UUID) -> UserDictionaryEntry? {
        entriesByID[id]
    }

    /// 前方一致検索。normalizedReading が prefix。enabledOnly で有効項目のみ。
    public func search(prefix rawPrefix: String,
                       enabledOnly: Bool = false,
                       sortedBy key: DictionarySortKey = .readingAscending) -> [UserDictionaryEntry] {
        let prefix = ReadingNormalizer.normalize(rawPrefix)
        guard !prefix.isEmpty else {
            let all = enabledOnly ? entriesByID.values.filter { $0.isEnabled } : Array(entriesByID.values)
            return sort(all, by: key)
        }
        var result: [UserDictionaryEntry] = []
        for (readingKey, ids) in readingIndex where readingKey.hasPrefix(prefix) {
            for id in ids {
                guard let e = entriesByID[id] else { continue }
                if enabledOnly && !e.isEnabled { continue }
                result.append(e)
            }
        }
        return sort(result, by: key)
    }

    /// 正規化よみの完全一致検索（変換候補反映で使用）。
    public func entries(forExactReading rawReading: String,
                        enabledOnly: Bool = true) -> [UserDictionaryEntry] {
        let key = ReadingNormalizer.normalize(rawReading)
        guard let ids = readingIndex[key] else { return [] }
        var result: [UserDictionaryEntry] = []
        for id in ids {
            guard let e = entriesByID[id] else { continue }
            if enabledOnly && !e.isEnabled { continue }
            result.append(e)
        }
        return result
    }

    /// 現在の件数。
    public var count: Int { entriesByID.count }

    // MARK: - サンプル辞書

    /// サンプル項目を登録する（重複はスキップ）。登録件数を返す。
    @discardableResult
    public func registerSampleEntries() throws -> Int {
        let samples: [(String, String, PartOfSpeech, String)] = [
            ("わたし", "私", .noun, "一人称"),
            ("すもーん", "(*'ω'*)", .emoticon, "顔文字サンプル"),
            ("とうきょう", "東京", .placeName, ""),
            ("やまだ", "山田", .personName, ""),
            ("めーる", "example@example.com", .noun, "定型文")
        ]
        var added = 0
        for (reading, word, pos, comment) in samples {
            let normalized = ReadingNormalizer.normalize(reading)
            if findDuplicate(normalizedReading: normalized, word: word) != nil { continue }
            let entry = UserDictionaryEntry(reading: reading, word: word,
                                            partOfSpeech: pos, comment: comment)
            entriesByID[entry.id] = entry
            indexInsert(entry)
            added += 1
        }
        if added > 0 { try persist() }
        return added
    }

    // MARK: - private helpers

    private func findDuplicate(normalizedReading: String, word: String) -> UserDictionaryEntry? {
        guard let ids = readingIndex[normalizedReading] else { return nil }
        for id in ids {
            if let e = entriesByID[id], e.word == word { return e }
        }
        return nil
    }

    private func sort(_ arr: [UserDictionaryEntry], by key: DictionarySortKey) -> [UserDictionaryEntry] {
        switch key {
        case .readingAscending:
            return arr.sorted {
                let l = ReadingNormalizer.normalize($0.reading)
                let r = ReadingNormalizer.normalize($1.reading)
                return l == r ? $0.word < $1.word : l < r
            }
        case .updatedAtDescending:
            return arr.sorted { $0.updatedAt > $1.updatedAt }
        case .createdAtDescending:
            return arr.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Import/Export 連携用（内部一括差し替え）

    /// インポートで得た項目群を追加マージする（重複はスキップ）。追加件数を返す。
    @discardableResult
    func mergeImported(_ imported: [UserDictionaryEntry]) throws -> Int {
        var added = 0
        for e in imported {
            let normalized = ReadingNormalizer.normalize(e.reading)
            if normalized.isEmpty || e.word.isEmpty { continue }
            if findDuplicate(normalizedReading: normalized, word: e.word) != nil { continue }
            entriesByID[e.id] = e
            indexInsert(e)
            added += 1
        }
        if added > 0 { try persist() }
        return added
    }
}
