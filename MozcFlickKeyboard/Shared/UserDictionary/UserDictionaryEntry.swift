import Foundation

/// ユーザー辞書の品詞。Mozc の品詞体系を簡略化した最小セット。
public enum PartOfSpeech: String, Codable, CaseIterable, Sendable {
    case noun          // 名詞
    case personName    // 人名
    case placeName     // 地名
    case verb          // 動詞
    case adjective     // 形容詞
    case adverb        // 副詞
    case symbol        // 記号
    case emoticon      // 顔文字
    case other         // その他

    /// 表示用の日本語ラベル。
    public var displayName: String {
        switch self {
        case .noun: return "名詞"
        case .personName: return "人名"
        case .placeName: return "地名"
        case .verb: return "動詞"
        case .adjective: return "形容詞"
        case .adverb: return "副詞"
        case .symbol: return "記号"
        case .emoticon: return "顔文字"
        case .other: return "その他"
        }
    }

    /// 日本語ラベルから品詞を復元する（CSV インポート用）。未知は .other。
    public static func fromDisplayName(_ name: String) -> PartOfSpeech {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for pos in PartOfSpeech.allCases where pos.displayName == trimmed {
            return pos
        }
        // rawValue 一致も許容する。
        return PartOfSpeech(rawValue: trimmed) ?? .other
    }
}

/// ユーザー辞書の1項目。JSON へ Codable 永続化する純値型。
public struct UserDictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    /// よみ（正規化前の入力そのまま。正規化は Store 側で normalizedReading を持つ）
    public var reading: String
    /// 変換後の単語
    public var word: String
    public var partOfSpeech: PartOfSpeech
    public var comment: String
    public let createdAt: Date
    public var updatedAt: Date
    public var isEnabled: Bool

    public init(id: UUID = UUID(),
                reading: String,
                word: String,
                partOfSpeech: PartOfSpeech = .noun,
                comment: String = "",
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                isEnabled: Bool = true) {
        self.id = id
        self.reading = reading
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEnabled = isEnabled
    }
}
