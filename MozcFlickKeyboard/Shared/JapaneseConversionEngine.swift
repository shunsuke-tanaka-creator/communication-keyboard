import Foundation

/// 変換候補1件。
/// C++ / Mozc 内部型を一切漏らさない純 Swift 値型。
public struct ConversionCandidate: Equatable, Identifiable, Sendable {
    public let id: String
    public let value: String        // 表示・確定する文字列
    public let reading: String      // よみ（ひらがな）
    public let description: String? // 品詞や注釈（任意）

    public init(id: String, value: String, reading: String, description: String? = nil) {
        self.id = id
        self.value = value
        self.reading = reading
        self.description = description
    }
}

/// 文節（変換の単位）。文節伸縮・移動のために区切りを保持する。
public struct ConversionSegment: Equatable, Sendable {
    public let reading: String
    public var selected: ConversionCandidate
    public var candidates: [ConversionCandidate]

    public init(reading: String, selected: ConversionCandidate, candidates: [ConversionCandidate]) {
        self.reading = reading
        self.selected = selected
        self.candidates = candidates
    }
}

/// 変換エンジンが返す状態。UI はこれだけを見て描画する。
public struct ConversionResult: Equatable, Sendable {
    /// 未確定のよみ（プリエディット全体）
    public let composition: String
    /// 変換中の文節列（変換前は空でよい）
    public let segments: [ConversionSegment]
    /// 候補バーに出す予測・変換候補
    public let candidates: [ConversionCandidate]
    /// フォーカス中の文節インデックス
    public let focusedSegment: Int
    /// 変換モードかどうか（false なら入力中のかな表示）
    public let isConverting: Bool

    public init(composition: String,
                segments: [ConversionSegment] = [],
                candidates: [ConversionCandidate] = [],
                focusedSegment: Int = 0,
                isConverting: Bool = false) {
        self.composition = composition
        self.segments = segments
        self.candidates = candidates
        self.focusedSegment = focusedSegment
        self.isConverting = isConverting
    }

    public static let empty = ConversionResult(composition: "")
}

/// かな漢字変換エンジンの抽象インターフェース。
/// Mozc 実装（MozcConversionEngine）とローカルスタブ（LocalStubEngine）が準拠する。
/// これにより Mozc のビルド完了前でもアプリ全体が動作・テスト可能。
public protocol JapaneseConversionEngine: AnyObject {
    /// 内部状態を破棄して初期状態へ戻す。
    func reset()

    /// かな1文字以上を未確定文字列末尾へ追加する。
    func insert(_ text: String)

    /// 未確定文字列末尾を1文字削除する。
    func deleteBackward()

    /// 現在の未確定文字列を変換し、候補を返す。
    func requestConversion() -> ConversionResult

    /// 予測候補（変換前サジェスト）を返す。
    func requestPrediction() -> ConversionResult

    /// 指定 id の候補を選択（学習にも反映）。
    func selectCandidate(id: String) -> ConversionResult

    /// フォーカス文節を移動する（+1 / -1）。
    func moveFocus(by offset: Int) -> ConversionResult

    /// フォーカス文節を伸縮する（+1 / -1 文字）。
    func resizeFocusedSegment(by offset: Int) -> ConversionResult

    /// 現在の選択状態を確定し、確定文字列を返す。副作用で内部状態はリセット。
    func commit() -> String

    /// 変換を取り消し、かな入力状態へ戻す。
    func cancelConversion() -> ConversionResult
}
