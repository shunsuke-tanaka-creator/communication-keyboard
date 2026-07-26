import Foundation

/// Mozc 未完成時でも日本語変換を実演できる、完全ローカルなスタブ変換エンジン。
///
/// 特徴:
///  - 小規模な内蔵かな漢字辞書（約50語）で、かな漢字変換・予測・カタカナ化・確定・取消が実際に動く。
///  - 簡易な文節分割（最長一致）で複数語のよみも変換できる。
///  - ローカル学習: 選択された候補の頻度を上げ、次回以降の候補順位に反映する。
///  - 強制アンラップは使用しない。全て安全に処理する。
public final class LocalStubEngine: JapaneseConversionEngine {

    // MARK: - 内蔵辞書

    /// よみ(ひらがな) -> 変換候補群。先頭ほど優先度が高い初期順序。
    /// 約50語の最小辞書。実運用では Mozc が担当するが、ここでは実演用。
    private static let dictionary: [String: [String]] = [
        "きょう": ["今日", "京"],
        "てんき": ["天気", "転機"],
        "とうきょう": ["東京"],
        "にほん": ["日本", "二本"],
        "あめ": ["雨", "飴"],
        "はし": ["橋", "箸", "端"],
        "はな": ["花", "鼻", "話"],
        "やま": ["山"],
        "かわ": ["川", "皮", "革"],
        "うみ": ["海", "膿"],
        "そら": ["空"],
        "みず": ["水"],
        "ひ": ["火", "日", "非"],
        "つき": ["月", "付き"],
        "ほし": ["星", "干し"],
        "がっこう": ["学校"],
        "せんせい": ["先生"],
        "がくせい": ["学生"],
        "ともだち": ["友達"],
        "かぞく": ["家族"],
        "でんわ": ["電話"],
        "でんしゃ": ["電車"],
        "くるま": ["車"],
        "ひこうき": ["飛行機"],
        "しごと": ["仕事"],
        "かいしゃ": ["会社"],
        "べんきょう": ["勉強"],
        "ほん": ["本"],
        "みせ": ["店", "見せ"],
        "えき": ["駅", "液"],
        "みち": ["道", "未知"],
        "た": ["田", "他"],
        "ぼく": ["僕"],
        "わたし": ["私"],
        "あなた": ["貴方"],
        "ねこ": ["猫"],
        "いぬ": ["犬"],
        "とり": ["鳥", "取り"],
        "さかな": ["魚"],
        "たべもの": ["食べ物"],
        "おちゃ": ["お茶"],
        "こめ": ["米", "込め"],
        "にく": ["肉"],
        "やさい": ["野菜"],
        "あさ": ["朝", "麻"],
        "よる": ["夜", "寄る"],
        "はる": ["春", "貼る"],
        "なつ": ["夏"],
        "あき": ["秋", "空き"],
        "ふゆ": ["冬"],
    ]

    /// 辞書のよみを長い順に並べたキャッシュ（最長一致の文節分割に使用）。
    private static let readingsByLengthDesc: [String] =
        dictionary.keys.sorted { $0.count > $1.count }

    // MARK: - 状態

    /// 未確定よみ（プリエディット全体）。
    private var composition: String = ""
    /// 変換中の文節列。
    private var segments: [ConversionSegment] = []
    /// フォーカス中の文節。
    private var focused: Int = 0
    /// 変換モードか。
    private var converting: Bool = false

    /// ローカル学習: (よみ+表記)の選択回数。多いほど候補順位を上げる。
    private var learningCounts: [String: Int] = [:]

    public init() {}

    // MARK: - JapaneseConversionEngine

    public func reset() {
        composition = ""
        segments = []
        focused = 0
        converting = false
    }

    public func insert(_ text: String) {
        composition += text
        converting = false
        segments = []
    }

    public func deleteBackward() {
        if !composition.isEmpty {
            composition.removeLast()
        }
        converting = false
        segments = []
    }

    public func requestConversion() -> ConversionResult {
        guard !composition.isEmpty else {
            return currentResult()
        }
        segments = splitIntoSegments(composition)
        focused = 0
        converting = true
        return currentResult()
    }

    public func requestPrediction() -> ConversionResult {
        // 変換前サジェスト。前方一致で辞書から予測し、候補バーへ出す。
        let predictions = predict(for: composition)
        return ConversionResult(composition: composition,
                                segments: [],
                                candidates: predictions,
                                focusedSegment: 0,
                                isConverting: false)
    }

    public func selectCandidate(id: String) -> ConversionResult {
        // id は "seg-<segIndex>-<candIndex>" もしくは予測候補 "pred-<reading>-<candIndex>"。
        if id.hasPrefix("seg-") {
            applySegmentSelection(id: id)
        } else if id.hasPrefix("pred-") {
            applyPredictionSelection(id: id)
        }
        return currentResult()
    }

    public func moveFocus(by offset: Int) -> ConversionResult {
        guard !segments.isEmpty else { return currentResult() }
        let next = focused + offset
        focused = min(max(next, 0), segments.count - 1)
        return currentResult()
    }

    public func resizeFocusedSegment(by offset: Int) -> ConversionResult {
        guard converting, segments.indices.contains(focused) else {
            return currentResult()
        }
        // フォーカス文節と後続を一旦よみへ戻し、境界を offset 文字ずらして再分割する。
        let tailReading = segments[focused...].map { $0.reading }.joined()
        guard !tailReading.isEmpty else { return currentResult() }

        let currentLen = segments[focused].reading.count
        var newLen = currentLen + offset
        newLen = min(max(newLen, 1), tailReading.count)

        let headReading = String(tailReading.prefix(newLen))
        let restReading = String(tailReading.dropFirst(newLen))

        var rebuilt = Array(segments[..<focused])
        rebuilt.append(makeSegment(reading: headReading, index: rebuilt.count))
        if !restReading.isEmpty {
            for seg in splitIntoSegments(restReading) {
                rebuilt.append(makeSegment(reading: seg.reading, index: rebuilt.count))
            }
        }
        segments = rebuilt
        focused = min(focused, segments.count - 1)
        return currentResult()
    }

    public func commit() -> String {
        let committed: String
        if converting, !segments.isEmpty {
            committed = segments.map { $0.selected.value }.joined()
        } else {
            committed = composition
        }
        reset()
        return committed
    }

    public func cancelConversion() -> ConversionResult {
        converting = false
        segments = []
        focused = 0
        return currentResult()
    }

    // MARK: - 変換ロジック

    /// よみ全体を最長一致で文節分割し、各文節に候補を割り当てる。
    private func splitIntoSegments(_ reading: String) -> [ConversionSegment] {
        var result: [ConversionSegment] = []
        var remaining = Substring(reading)

        while !remaining.isEmpty {
            let matchedReading = longestDictionaryPrefix(of: remaining) ?? String(remaining.prefix(1))
            let seg = makeSegment(reading: matchedReading, index: result.count)
            result.append(seg)
            remaining = remaining.dropFirst(matchedReading.count)
        }
        return result
    }

    /// remaining の先頭に一致する辞書よみのうち最長のものを返す。無ければ nil。
    private func longestDictionaryPrefix(of remaining: Substring) -> String? {
        for reading in Self.readingsByLengthDesc where remaining.hasPrefix(reading) {
            return reading
        }
        return nil
    }

    /// 1 文節ぶんの候補群を作る。学習頻度で並べ替え、末尾にカタカナ・ひらがなも足す。
    private func makeSegment(reading: String, index: Int) -> ConversionSegment {
        let candidates = makeCandidates(reading: reading, segIndex: index)
        // guard で安全に先頭を取得（候補は必ず 1 つ以上作られる）。
        let selected = candidates.first
            ?? ConversionCandidate(id: "seg-\(index)-0", value: reading, reading: reading)
        return ConversionSegment(reading: reading, selected: selected, candidates: candidates)
    }

    /// よみに対する候補列。漢字候補（学習順）＋ひらがな＋カタカナ。
    private func makeCandidates(reading: String, segIndex: Int) -> [ConversionCandidate] {
        var values: [String] = []

        // 辞書の漢字候補を学習頻度の高い順に並べる（同数は元の順序を維持）。
        if let kanji = Self.dictionary[reading] {
            let sorted = kanji.enumerated().sorted { lhs, rhs in
                let lc = learningCounts[learnKey(reading: reading, value: lhs.element)] ?? 0
                let rc = learningCounts[learnKey(reading: reading, value: rhs.element)] ?? 0
                if lc != rc { return lc > rc }
                return lhs.offset < rhs.offset
            }
            values.append(contentsOf: sorted.map { $0.element })
        }

        // ひらがなそのもの。
        if !values.contains(reading) {
            values.append(reading)
        }
        // カタカナ化。
        let katakana = toKatakana(reading)
        if katakana != reading, !values.contains(katakana) {
            values.append(katakana)
        }

        return values.enumerated().map { offset, value in
            ConversionCandidate(id: "seg-\(segIndex)-\(offset)",
                                value: value,
                                reading: reading,
                                description: nil)
        }
    }

    /// 前方一致予測。composition を先頭に含む辞書よみを集め、候補化する。
    private func predict(for prefix: String) -> [ConversionCandidate] {
        guard !prefix.isEmpty else { return [] }
        var candidates: [ConversionCandidate] = []

        // 完全一致するよみの漢字候補を優先。
        let exactValues = Self.dictionary[prefix] ?? []
        for (i, value) in exactValues.enumerated() {
            candidates.append(ConversionCandidate(id: "pred-\(prefix)-\(i)",
                                                  value: value,
                                                  reading: prefix))
        }

        // 前方一致（先頭が prefix で始まる別のよみ）も予測に加える。
        let matchedReadings = Self.dictionary.keys
            .filter { $0.hasPrefix(prefix) && $0 != prefix }
            .sorted { $0.count < $1.count }
        for reading in matchedReadings {
            guard let values = Self.dictionary[reading] else { continue }
            for (i, value) in values.enumerated() {
                candidates.append(ConversionCandidate(id: "pred-\(reading)-\(i)",
                                                      value: value,
                                                      reading: reading))
            }
        }
        return candidates
    }

    // MARK: - 選択適用（学習込み）

    private func applySegmentSelection(id: String) {
        // "seg-<segIndex>-<candIndex>"
        let parts = id.split(separator: "-")
        guard parts.count == 3,
              let segIndex = Int(parts[1]),
              let candIndex = Int(parts[2]),
              segments.indices.contains(segIndex),
              segments[segIndex].candidates.indices.contains(candIndex) else {
            return
        }
        let chosen = segments[segIndex].candidates[candIndex]
        segments[segIndex].selected = chosen
        focused = segIndex
        // 学習: 選択された (よみ, 表記) の頻度を上げる。
        bumpLearning(reading: chosen.reading, value: chosen.value)
        // 学習結果を候補順へ反映するため、この文節の候補を作り直す。
        segments[segIndex] = makeSegmentPreservingSelection(reading: chosen.reading,
                                                            index: segIndex,
                                                            selectedValue: chosen.value)
    }

    private func applyPredictionSelection(id: String) {
        // "pred-<reading>-<candIndex>": 予測確定は composition を確定文字列へ置き換える。
        // ここでは segments に単一文節を組み立て、変換確定できる状態にする。
        let parts = id.split(separator: "-")
        guard parts.count >= 3,
              let candIndex = Int(parts[parts.count - 1]) else {
            return
        }
        let reading = parts[1...(parts.count - 2)].joined(separator: "-")
        guard let values = Self.dictionary[reading],
              values.indices.contains(candIndex) else {
            return
        }
        let value = values[candIndex]
        composition = reading
        let seg = makeSegmentPreservingSelection(reading: reading, index: 0, selectedValue: value)
        segments = [seg]
        focused = 0
        converting = true
        bumpLearning(reading: reading, value: value)
    }

    /// 指定表記を選択状態に保ったまま文節を作り直す。
    private func makeSegmentPreservingSelection(reading: String, index: Int, selectedValue: String) -> ConversionSegment {
        let candidates = makeCandidates(reading: reading, segIndex: index)
        let selected = candidates.first(where: { $0.value == selectedValue })
            ?? candidates.first
            ?? ConversionCandidate(id: "seg-\(index)-0", value: reading, reading: reading)
        return ConversionSegment(reading: reading, selected: selected, candidates: candidates)
    }

    private func bumpLearning(reading: String, value: String) {
        let key = learnKey(reading: reading, value: value)
        learningCounts[key] = (learningCounts[key] ?? 0) + 1
    }

    private func learnKey(reading: String, value: String) -> String {
        "\(reading)\u{1F}\(value)" // 区切りに制御文字 US を使い衝突を避ける。
    }

    // MARK: - ユーティリティ

    /// ひらがな -> カタカナ変換。対象外の文字はそのまま返す。
    private func toKatakana(_ hiragana: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in hiragana.unicodeScalars {
            // ひらがな U+3041...U+3096 をカタカナ U+30A1... へ +0x60 シフト。
            if scalar.value >= 0x3041 && scalar.value <= 0x3096,
               let shifted = Unicode.Scalar(scalar.value + 0x60) {
                scalars.append(shifted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// 現在の内部状態から ConversionResult を組み立てる。
    private func currentResult() -> ConversionResult {
        // 候補バー: 変換中はフォーカス文節の候補、そうでなければ予測。
        let barCandidates: [ConversionCandidate]
        if converting, segments.indices.contains(focused) {
            barCandidates = segments[focused].candidates
        } else {
            barCandidates = predict(for: composition)
        }
        return ConversionResult(composition: composition,
                                segments: segments,
                                candidates: barCandidates,
                                focusedSegment: focused,
                                isConverting: converting)
    }
}
