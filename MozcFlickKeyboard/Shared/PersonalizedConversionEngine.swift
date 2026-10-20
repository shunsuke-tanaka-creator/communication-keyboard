import Foundation

/// Engine candidates retain their native IDs. Literal/user-dictionary candidates are
/// resolved here and never sent to Mozc as a numeric candidate ID.
public final class PersonalizedConversionEngine: JapaneseConversionEngine {
    private let base: JapaneseConversionEngine
    private let dictionaryEntries: (String) -> [UserDictionaryEntry]
    private let learningScores: (String) -> [String: Int]
    private let recordSelection: (String, String) -> Void
    private var latest = ConversionResult.empty
    private var directCandidates: [String: ConversionCandidate] = [:]
    private var directCommit: String?
    private var selected: ConversionCandidate?

    public init(base: JapaneseConversionEngine,
                dictionaryEntries: @escaping (String) -> [UserDictionaryEntry] = { _ in [] },
                learningScores: @escaping (String) -> [String: Int] = { _ in [:] },
                recordSelection: @escaping (String, String) -> Void = { _, _ in }) {
        self.base = base
        self.dictionaryEntries = dictionaryEntries
        self.learningScores = learningScores
        self.recordSelection = recordSelection
    }

    public func setInputMode(_ mode: InputMode) { base.setInputMode(mode) }
    public func setLearningEnabled(_ enabled: Bool) { base.setLearningEnabled(enabled) }

    public func reset() {
        base.reset()
        latest = .empty
        directCandidates = [:]
        directCommit = nil
        selected = nil
    }

    public func insert(_ text: String) {
        selected = nil
        directCommit = nil
        base.insert(text)
    }

    public func deleteBackward() {
        selected = nil
        directCommit = nil
        base.deleteBackward()
    }

    public func requestPrediction() -> ConversionResult { decorate(base.requestPrediction()) }
    public func requestConversion() -> ConversionResult { decorate(base.requestConversion()) }
    public func moveFocus(by offset: Int) -> ConversionResult { decorate(base.moveFocus(by: offset)) }
    public func resizeFocusedSegment(by offset: Int) -> ConversionResult {
        decorate(base.resizeFocusedSegment(by: offset))
    }
    public func cancelConversion() -> ConversionResult {
        selected = nil
        directCommit = nil
        return decorate(base.cancelConversion())
    }

    public func selectCandidate(id: String) -> ConversionResult {
        guard let candidate = latest.candidates.first(where: { $0.id == id }) else { return latest }
        selected = candidate
        if directCandidates[id] != nil {
            directCommit = candidate.value
            // Do not teach the base engine a different word by submitting its first candidate.
            base.reset()
            latest = ConversionResult(composition: candidate.reading,
                segments: [ConversionSegment(reading: candidate.reading, selected: candidate, candidates: [candidate])],
                candidates: [candidate], isConverting: true)
        } else {
            latest = base.selectCandidate(id: id)
        }
        return latest
    }

    public func commit() -> String {
        let text = directCommit ?? base.commit()
        if let selected, !text.isEmpty, selected.id != "literal:reading" {
            recordSelection(selected.reading, selected.value)
        }
        // commit() clears the base composition without discarding its context/history.
        latest = .empty
        directCommit = nil
        directCandidates = [:]
        selected = nil
        return text
    }

    private func decorate(_ result: ConversionResult) -> ConversionResult {
        directCommit = nil
        selected = nil
        directCandidates = [:]
        guard !result.composition.isEmpty else { latest = result; return result }
        let reading = ReadingNormalizer.normalize(result.composition)
        let entries = dictionaryEntries(reading).filter {
            $0.isEnabled && (result.isConverting ? ReadingNormalizer.normalize($0.reading) == reading : ReadingNormalizer.normalize($0.reading).hasPrefix(reading))
        }
        let originalIDs = Set(result.candidates.map(\.id))
        var scores: [String: Int] = [:]
        var scoreCache: [String: [String: Int]] = [:]
        for candidate in result.candidates {
            if scoreCache[candidate.reading] == nil {
                scoreCache[candidate.reading] = learningScores(candidate.reading)
            }
            scores[candidate.value] = scoreCache[candidate.reading]?[candidate.value]
        }
        for entry in entries {
            scores[entry.word] = learningScores(entry.reading)[entry.word]
        }
        var candidates = CandidateReranker.rerank(.init(reading: reading,
            candidates: result.candidates, learningScores: scores, userDictEntries: entries))
        for candidate in candidates where !originalIDs.contains(candidate.id) {
            directCandidates[candidate.id] = candidate
        }
        // A raw-reading candidate is explicit and comes after useful predictions.
        let literal = ConversionCandidate(id: "literal:reading", value: result.composition,
                                          reading: result.composition, description: "そのまま確定")
        if !candidates.contains(where: { $0.value == literal.value }) {
            candidates.append(literal)
            directCandidates[literal.id] = literal
        }
        latest = ConversionResult(composition: result.composition, segments: result.segments,
            candidates: candidates, focusedSegment: result.focusedSegment, isConverting: result.isConverting)
        return latest
    }
}
