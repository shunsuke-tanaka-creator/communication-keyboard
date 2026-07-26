import Foundation

/// Mozc 実エンジンへの Swift ラッパ。
/// Objective-C++ ブリッジ `MozcEngineBridge`（bridging header 経由で可視）を呼び出し、
/// 返ってきた辞書を共有契約型 `ConversionResult` へ変換する。
///
/// Mozc がまだ組み込まれていない場合、ブリッジ側は最小スタブ応答を返す。
/// 実用的なローカル変換は `LocalStubEngine` を使うこと（アプリの既定切替はメイン側の責務）。
public final class MozcConversionEngine: JapaneseConversionEngine {

    // ブリッジが返す辞書のキー。ObjC 側 kMozc* 定数と一致させる。
    private enum Key {
        static let composition = "composition"
        static let candidates = "candidates"
        static let segments = "segments"
        static let focusedSegment = "focusedSegment"
        static let isConverting = "isConverting"

        static let candID = "id"
        static let candValue = "value"
        static let candReading = "reading"
        static let candDescription = "description"

        static let segReading = "reading"
        static let segSelected = "selected"
        static let segCandidates = "candidates"
    }

    private let bridge: MozcEngineBridge

    /// Mozc 実 API が組み込まれているか。
    public var isMozcAvailable: Bool { bridge.isMozcAvailable }

    /// 辞書データのパスを指定して初期化する。
    /// 省略時はアプリ(Extension)バンドル内の `mozc.data` を探索して渡す。
    public init(dataPath: String? = nil) {
        let path = dataPath ?? Bundle.main.path(forResource: "mozc", ofType: "data") ?? ""
        bridge = MozcEngineBridge(dataPath: path)
    }

    // MARK: - JapaneseConversionEngine

    public func reset() {
        bridge.reset()
    }

    public func insert(_ text: String) {
        bridge.insertText(text)
    }

    public func deleteBackward() {
        bridge.deleteBackward()
    }

    public func requestConversion() -> ConversionResult {
        makeResult(from: bridge.requestConversion())
    }

    public func requestPrediction() -> ConversionResult {
        makeResult(from: bridge.requestPrediction())
    }

    public func selectCandidate(id: String) -> ConversionResult {
        makeResult(from: bridge.selectCandidate(withID: id))
    }

    public func moveFocus(by offset: Int) -> ConversionResult {
        makeResult(from: bridge.moveFocus(by: offset))
    }

    public func resizeFocusedSegment(by offset: Int) -> ConversionResult {
        makeResult(from: bridge.resizeFocusedSegment(by: offset))
    }

    public func commit() -> String {
        bridge.commit()
    }

    public func cancelConversion() -> ConversionResult {
        makeResult(from: bridge.cancelConversion())
    }

    // MARK: - 辞書 -> 契約型 変換

    private func makeResult(from dict: [String: Any]) -> ConversionResult {
        let composition = dict[Key.composition] as? String ?? ""
        let focused = (dict[Key.focusedSegment] as? NSNumber)?.intValue ?? 0
        let isConverting = (dict[Key.isConverting] as? NSNumber)?.boolValue ?? false

        let candidateDicts = dict[Key.candidates] as? [[String: Any]] ?? []
        let candidates = candidateDicts.compactMap(makeCandidate)

        let segmentDicts = dict[Key.segments] as? [[String: Any]] ?? []
        let segments = segmentDicts.compactMap(makeSegment)

        return ConversionResult(composition: composition,
                                segments: segments,
                                candidates: candidates,
                                focusedSegment: focused,
                                isConverting: isConverting)
    }

    private func makeCandidate(from dict: [String: Any]) -> ConversionCandidate? {
        guard let id = dict[Key.candID] as? String,
              let value = dict[Key.candValue] as? String,
              let reading = dict[Key.candReading] as? String else {
            return nil
        }
        // NSNull は説明なしとして扱う。
        let description = dict[Key.candDescription] as? String
        return ConversionCandidate(id: id, value: value, reading: reading, description: description)
    }

    private func makeSegment(from dict: [String: Any]) -> ConversionSegment? {
        guard let reading = dict[Key.segReading] as? String,
              let selectedDict = dict[Key.segSelected] as? [String: Any],
              let selected = makeCandidate(from: selectedDict) else {
            return nil
        }
        let candDicts = dict[Key.segCandidates] as? [[String: Any]] ?? []
        let candidates = candDicts.compactMap(makeCandidate)
        return ConversionSegment(reading: reading, selected: selected, candidates: candidates)
    }
}
