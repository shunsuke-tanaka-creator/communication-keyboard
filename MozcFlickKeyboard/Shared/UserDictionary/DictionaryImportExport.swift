import Foundation

/// インポート結果のレポート。成功件数と不正行を分離して返す。
public struct ImportReport: Sendable {
    /// 追加された件数（重複スキップ後）。
    public let importedCount: Int
    /// 解析に成功したが重複でスキップした件数。
    public let skippedDuplicateCount: Int
    /// 解析に失敗した行（1始まり行番号と理由）。入力語そのものは載せない。
    public let invalidLines: [(line: Int, reason: String)]

    public init(importedCount: Int, skippedDuplicateCount: Int, invalidLines: [(line: Int, reason: String)]) {
        self.importedCount = importedCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.invalidLines = invalidLines
    }
}

/// 入出力のエラー。
public enum ImportExportError: Error, LocalizedError {
    case encodeFailed(underlying: Error)
    case decodeFailed(underlying: Error)
    case invalidTextEncoding

    public var errorDescription: String? {
        switch self {
        case .encodeFailed: return "書き出しに失敗しました。"
        case .decodeFailed: return "ファイルの解析に失敗しました。"
        case .invalidTextEncoding: return "文字コードを判別できませんでした。"
        }
    }

    public var debugDetail: String {
        switch self {
        case .encodeFailed(let e): return "encode failed: \(e)"
        case .decodeFailed(let e): return "decode failed: \(e)"
        case .invalidTextEncoding: return "text encoding not UTF-8."
        }
    }
}

/// ユーザー辞書の CSV / JSON 入出力。UserDictionaryStore と連携する。
public enum DictionaryImportExport {

    // MARK: - JSON

    /// 現在の辞書を JSON データへエクスポート。
    public static func exportJSON(entries: [UserDictionaryEntry]) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        do {
            return try enc.encode(entries)
        } catch {
            throw ImportExportError.encodeFailed(underlying: error)
        }
    }

    /// JSON データを解析し、Store へマージする。
    @discardableResult
    public static func importJSON(_ data: Data, into store: UserDictionaryStore) throws -> ImportReport {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let entries: [UserDictionaryEntry]
        do {
            entries = try dec.decode([UserDictionaryEntry].self, from: data)
        } catch {
            throw ImportExportError.decodeFailed(underlying: error)
        }
        let before = store.count
        let added = try store.mergeImported(entries)
        let skipped = max(0, entries.count - added)
        _ = before
        return ImportReport(importedCount: added,
                            skippedDuplicateCount: skipped,
                            invalidLines: [])
    }

    // MARK: - CSV

    /// CSV へエクスポート。列: 読み,単語,品詞,コメント。
    public static func exportCSV(entries: [UserDictionaryEntry]) -> String {
        var lines: [String] = ["読み,単語,品詞,コメント"]
        for e in entries {
            let row = [e.reading, e.word, e.partOfSpeech.displayName, e.comment]
                .map { escapeCSVField($0) }
                .joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    /// CSV 文字列を解析して Store へマージ。不正行はスキップしレポートへ記録。
    /// 1行目がヘッダ（"読み"で始まる）なら読み飛ばす。
    @discardableResult
    public static func importCSV(_ text: String, into store: UserDictionaryStore) throws -> ImportReport {
        let rows = parseCSV(text)
        var parsed: [UserDictionaryEntry] = []
        var invalid: [(line: Int, reason: String)] = []

        for (index, fields) in rows.enumerated() {
            let lineNo = index + 1
            // ヘッダ行スキップ。
            if index == 0, let first = fields.first,
               first.trimmingCharacters(in: .whitespaces) == "読み" {
                continue
            }
            // 空行スキップ。
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                continue
            }
            guard fields.count >= 2 else {
                invalid.append((lineNo, "列数不足（読み,単語が必要）"))
                continue
            }
            let reading = fields[0].trimmingCharacters(in: .whitespaces)
            let word = fields[1].trimmingCharacters(in: .whitespaces)
            guard !reading.isEmpty else {
                invalid.append((lineNo, "よみが空"))
                continue
            }
            guard !word.isEmpty else {
                invalid.append((lineNo, "単語が空"))
                continue
            }
            let pos = fields.count >= 3 ? PartOfSpeech.fromDisplayName(fields[2]) : .noun
            let comment = fields.count >= 4 ? fields[3] : ""
            parsed.append(UserDictionaryEntry(reading: reading, word: word,
                                              partOfSpeech: pos, comment: comment))
        }

        let added = try store.mergeImported(parsed)
        let skipped = max(0, parsed.count - added)
        return ImportReport(importedCount: added,
                            skippedDuplicateCount: skipped,
                            invalidLines: invalid)
    }

    // MARK: - CSV low-level

    /// CSV フィールドのエスケープ（区切り/改行/引用符を含む場合はダブルクォート囲み）。
    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    /// RFC4180 準拠寄りの CSV パーサ。引用符内の改行/カンマに対応。
    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let scalars = Array(text)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    record.append(field)
                    field = ""
                case "\r":
                    break // \r\n の \r は無視。
                case "\n":
                    record.append(field)
                    rows.append(record)
                    field = ""
                    record = []
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        // 末尾フィールド/レコード。
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            rows.append(record)
        }
        return rows
    }
}
