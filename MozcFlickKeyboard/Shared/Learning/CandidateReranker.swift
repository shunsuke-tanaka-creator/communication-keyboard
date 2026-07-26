import Foundation

/// 変換候補の再ランキングとユーザー辞書反映を行う純ロジック。
/// JapaneseConversionEngine が返した候補配列を、LearningStore の頻度と
/// UserDictionaryStore の項目で並べ替え・補強する。副作用を持たない。
public enum CandidateReranker {

    /// 再ランキングの入力パラメータ。
    public struct Input {
        public let reading: String                 // 対象よみ（正規化前でも可）
        public let candidates: [ConversionCandidate]
        public let learningScores: [String: Int]   // word → 頻度
        public let userDictEntries: [UserDictionaryEntry] // 同一よみの有効項目
        /// 学習の重み。頻度に掛けてスコア化する。
        public let learningWeight: Double
        /// ユーザー辞書項目を先頭付近へ寄せる際の基礎スコア。
        public let userDictBonus: Double

        public init(reading: String,
                    candidates: [ConversionCandidate],
                    learningScores: [String: Int],
                    userDictEntries: [UserDictionaryEntry],
                    learningWeight: Double = 10.0,
                    userDictBonus: Double = 1000.0) {
            self.reading = reading
            self.candidates = candidates
            self.learningScores = learningScores
            self.userDictEntries = userDictEntries
            self.learningWeight = learningWeight
            self.userDictBonus = userDictBonus
        }
    }

    /// 再ランキングを実行して新しい候補配列を返す。
    /// 手順:
    /// 1. ユーザー辞書項目を候補へマージ（未収載なら追加、既存なら情報付与）。
    /// 2. 各候補へ score = 元順位由来スコア + 学習頻度*重み + ユーザー辞書ボーナス。
    /// 3. score 降順で安定ソート（同点は元の順序維持）。
    public static func rerank(_ input: Input) -> [ConversionCandidate] {
        var merged = input.candidates
        let existingValues = Set(merged.map { $0.value })

        // 1. ユーザー辞書項目のマージ（同よみ・有効のみ想定）。
        for entry in input.userDictEntries where entry.isEnabled {
            if !existingValues.contains(entry.word) {
                merged.append(ConversionCandidate(
                    id: "userdict:\(entry.id.uuidString)",
                    value: entry.word,
                    reading: entry.reading,
                    description: entry.partOfSpeech.displayName
                ))
            }
        }

        let userDictWords = Set(input.userDictEntries.filter { $0.isEnabled }.map { $0.word })
        let n = merged.count

        // 2. スコアリング（元順位は先頭ほど高い基礎点を与える）。
        struct Scored {
            let index: Int
            let candidate: ConversionCandidate
            let score: Double
        }
        var scored: [Scored] = []
        scored.reserveCapacity(n)
        for (i, c) in merged.enumerated() {
            let baseScore = Double(n - i)                     // 元順位由来
            let learn = Double(input.learningScores[c.value] ?? 0) * input.learningWeight
            let dict = userDictWords.contains(c.value) ? input.userDictBonus : 0
            scored.append(Scored(index: i, candidate: c, score: baseScore + learn + dict))
        }

        // 3. score 降順・同点は元順序（index 昇順）で安定ソート。
        scored.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        return scored.map { $0.candidate }
    }

    /// Store から必要データを引いて再ランキングする便宜メソッド。
    /// - Note: I/O は Store 側。ここでは読み取りのみで副作用なし。
    public static func rerank(reading: String,
                              candidates: [ConversionCandidate],
                              learningStore: LearningStore,
                              userDictionaryStore: UserDictionaryStore,
                              learningWeight: Double = 10.0,
                              userDictBonus: Double = 1000.0) -> [ConversionCandidate] {
        let scores = learningStore.scores(forReading: reading)
        let entries = userDictionaryStore.entries(forExactReading: reading, enabledOnly: true)
        let input = Input(reading: reading,
                          candidates: candidates,
                          learningScores: scores,
                          userDictEntries: entries,
                          learningWeight: learningWeight,
                          userDictBonus: userDictBonus)
        return rerank(input)
    }
}
