// KeyLayout.swift
// MozcFlickKeyboard — データ駆動の12キー配列モデル。
//
// キーボードの物理配置（4行×5列相当）を「if 分岐なし」でデータとして定義する。
// 各キーは種類（かな入力キー / 機能キー / モード切替キー）を持ち、
// かなキーは KanaTable の KanaKey を参照する。
//
// 入力モード（ひらがな/カタカナ/英字/数字/記号）ごとに配列を差し替える設計。

import Foundation

/// キーの押下で発生するアクション種別。
/// UI はこのアクションを見て delegate へ通知する（大量の if 分岐を避ける）。
public enum KeyAction: Equatable, Sendable {
    /// かな入力キー（KanaTable の id を参照）。フリック方向で文字が変わる。
    case kana(kanaKeyID: String)
    /// 任意固定文字の入力（英字・数字・記号モードで使用）。
    case input(String)
    /// 濁点/半濁点/小書きトグル（直前文字を循環変換）。
    case toggleDakuten
    /// 削除（バックスペース）。長押しで連続削除。
    case backspace
    /// 空白。長押しでカーソル移動モード。
    case space
    /// 改行 / 確定（変換中は確定、未変換は改行）。
    case returnOrConfirm
    /// 次のキーボードへ切替（地球儀）。
    case nextKeyboard
    /// 入力モード切替（ひらがな/カタカナ/英数/記号を循環）。
    case switchInputMode
    /// カーソル左移動。
    case cursorLeft
    /// カーソル右移動。
    case cursorRight
}

/// 入力モード。
public enum InputMode: String, CaseIterable, Sendable {
    case hiragana   // ひらがな
    case katakana   // カタカナ
    case alphabet   // 英字
    case number     // 数字
    case symbol     // 記号

    /// switchInputMode で循環する次モード。
    public var next: InputMode {
        switch self {
        case .hiragana: return .katakana
        case .katakana: return .alphabet
        case .alphabet: return .number
        case .number:   return .symbol
        case .symbol:   return .hiragana
        }
    }

    /// キー上に表示するモードラベル。
    public var label: String {
        switch self {
        case .hiragana: return "あ"
        case .katakana: return "ア"
        case .alphabet: return "A"
        case .number:   return "1"
        case .symbol:   return "☆"
        }
    }
}

/// 1つのキーの定義。表示ラベルとアクションを持つ。
public struct KeyDefinition: Sendable {
    /// キー中央に表示するラベル。かなキーは KanaKey.id と一致。
    public let label: String
    /// 押下時のアクション。
    public let action: KeyAction
    /// グリッド上の位置（row: 0..3, column: 0..4）。
    public let row: Int
    public let column: Int

    public init(label: String, action: KeyAction, row: Int, column: Int) {
        self.label = label
        self.action = action
        self.row = row
        self.column = column
    }

    /// かなキーなら対応する KanaKey を返す（ひらがなテーブル基準）。
    public var kanaKey: KanaKey? {
        if case let .kana(id) = action {
            return KanaTable.key(for: id)
        }
        return nil
    }
}

/// 12キーレイアウト全体（4行×5列）。
public enum KeyLayout {

    /// 標準の12キー日本語フリック配列。
    /// iOS 標準のかなキーボードに合わせた 4行×5列配置（絵文字/マイクは除外）:
    ///   row0: [☆123]  あ か さ      [⌫]
    ///   row1: [ABC]    た な は      [空白]
    ///   row2: [あいう]  ま や ら      [改行/確定]
    ///   row3: [🌐]     小゛゜  わ  、。?!  [次候補]
    /// 左列はモード切替（循環）、右列は削除/空白/確定、下段中央に句読点・わ・濁点トグル。
    public static func hiraganaLayout() -> [KeyDefinition] {
        return [
            // row0
            KeyDefinition(label: "☆123", action: .switchInputMode, row: 0, column: 0),
            KeyDefinition(label: "あ", action: .kana(kanaKeyID: "あ"), row: 0, column: 1),
            KeyDefinition(label: "か", action: .kana(kanaKeyID: "か"), row: 0, column: 2),
            KeyDefinition(label: "さ", action: .kana(kanaKeyID: "さ"), row: 0, column: 3),
            KeyDefinition(label: "⌫", action: .backspace, row: 0, column: 4),
            // row1
            KeyDefinition(label: "ABC", action: .switchInputMode, row: 1, column: 0),
            KeyDefinition(label: "た", action: .kana(kanaKeyID: "た"), row: 1, column: 1),
            KeyDefinition(label: "な", action: .kana(kanaKeyID: "な"), row: 1, column: 2),
            KeyDefinition(label: "は", action: .kana(kanaKeyID: "は"), row: 1, column: 3),
            KeyDefinition(label: "空白", action: .space, row: 1, column: 4),
            // row2
            KeyDefinition(label: "あいう", action: .switchInputMode, row: 2, column: 0),
            KeyDefinition(label: "ま", action: .kana(kanaKeyID: "ま"), row: 2, column: 1),
            KeyDefinition(label: "や", action: .kana(kanaKeyID: "や"), row: 2, column: 2),
            KeyDefinition(label: "ら", action: .kana(kanaKeyID: "ら"), row: 2, column: 3),
            KeyDefinition(label: "改行", action: .returnOrConfirm, row: 2, column: 4),
            // row3
            KeyDefinition(label: "🌐", action: .nextKeyboard, row: 3, column: 0),
            KeyDefinition(label: "小゛゜", action: .toggleDakuten, row: 3, column: 1), // 変更: 「、。?!」と左右入れ替え
            KeyDefinition(label: "わ", action: .kana(kanaKeyID: "わ"), row: 3, column: 2),
            KeyDefinition(label: "、。?!", action: .kana(kanaKeyID: "、"), row: 3, column: 3), // 変更: 「小゛゜」と左右入れ替え
            KeyDefinition(label: "次候補", action: .returnOrConfirm, row: 3, column: 4),
        ]
    }

    /// 数字・英字・記号などの固定文字レイアウトを生成する共通関数。
    /// characters は中央3列(col1..3)へ順に割り当てる。
    /// 左列・右列・下段機能キーは iOS 標準配置（かなと同じ）に揃える。
    private static func fixedLayout(modeLabel: String, characters: [String]) -> [KeyDefinition] {
        var keys: [KeyDefinition] = [
            // 左列: モード切替（循環）。iOS 標準に合わせ ☆123 / ABC / あいう を縦に並べる。
            KeyDefinition(label: "☆123", action: .switchInputMode, row: 0, column: 0),
            KeyDefinition(label: "ABC", action: .switchInputMode, row: 1, column: 0),
            KeyDefinition(label: "あいう", action: .switchInputMode, row: 2, column: 0),
            KeyDefinition(label: "🌐", action: .nextKeyboard, row: 3, column: 0),
            // 右列: 削除 / 空白 / 改行(確定) / 次候補。
            KeyDefinition(label: "⌫", action: .backspace, row: 0, column: 4),
            KeyDefinition(label: "空白", action: .space, row: 1, column: 4),
            KeyDefinition(label: "改行", action: .returnOrConfirm, row: 2, column: 4),
            KeyDefinition(label: "次候補", action: .returnOrConfirm, row: 3, column: 4),
        ]
        // 中央3列 × row0..3 に文字を並べる（最大12文字。row3 は col1,col2,col3）。
        let slots: [(Int, Int)] = [
            (0, 1), (0, 2), (0, 3),
            (1, 1), (1, 2), (1, 3),
            (2, 1), (2, 2), (2, 3),
            (3, 1), (3, 2), (3, 3),
        ]
        for (i, ch) in characters.prefix(slots.count).enumerated() {
            let (row, col) = slots[i]
            keys.append(KeyDefinition(label: ch, action: .input(ch), row: row, column: col))
        }
        return keys
    }

    /// カタカナはひらがなキー配列のラベルだけカタカナに置換（入力自体は KanaTransform で変換）。
    /// 実際の文字変換は InputState 側でモードを見て行うため、ここではひらがな配列を流用する。
    public static func katakanaLayout() -> [KeyDefinition] {
        hiraganaLayout()
    }

    public static func alphabetLayout() -> [KeyDefinition] {
        fixedLayout(modeLabel: InputMode.alphabet.label,
                    characters: ["@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J"])
    }

    public static func numberLayout() -> [KeyDefinition] {
        fixedLayout(modeLabel: InputMode.number.label,
                    characters: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"])
    }

    public static func symbolLayout() -> [KeyDefinition] {
        fixedLayout(modeLabel: InputMode.symbol.label,
                    characters: ["、", "。", "！", "？", "「", "」", "（", "）", "・", "…", "〜"])
    }

    /// モードに応じたレイアウトを返す。
    public static func layout(for mode: InputMode) -> [KeyDefinition] {
        switch mode {
        case .hiragana: return hiraganaLayout()
        case .katakana: return katakanaLayout()
        case .alphabet: return alphabetLayout()
        case .number:   return numberLayout()
        case .symbol:   return symbolLayout()
        }
    }

    /// グリッドの行数・列数。
    public static let rowCount = 4
    public static let columnCount = 5
}
