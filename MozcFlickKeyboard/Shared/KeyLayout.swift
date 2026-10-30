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
    case shift
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
    case setInputMode(InputMode)
    case nextCandidate
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
            KeyDefinition(label: "123", action: .setInputMode(.number), row: 0, column: 0),
            KeyDefinition(label: "あ", action: .kana(kanaKeyID: "あ"), row: 0, column: 1),
            KeyDefinition(label: "か", action: .kana(kanaKeyID: "か"), row: 0, column: 2),
            KeyDefinition(label: "さ", action: .kana(kanaKeyID: "さ"), row: 0, column: 3),
            KeyDefinition(label: "⌫", action: .backspace, row: 0, column: 4),
            // row1
            KeyDefinition(label: "ABC", action: .setInputMode(.alphabet), row: 1, column: 0),
            KeyDefinition(label: "た", action: .kana(kanaKeyID: "た"), row: 1, column: 1),
            KeyDefinition(label: "な", action: .kana(kanaKeyID: "な"), row: 1, column: 2),
            KeyDefinition(label: "は", action: .kana(kanaKeyID: "は"), row: 1, column: 3),
            KeyDefinition(label: "空白", action: .space, row: 1, column: 4),
            // row2
            KeyDefinition(label: "あいう", action: .setInputMode(.hiragana), row: 2, column: 0),
            KeyDefinition(label: "ま", action: .kana(kanaKeyID: "ま"), row: 2, column: 1),
            KeyDefinition(label: "や", action: .kana(kanaKeyID: "や"), row: 2, column: 2),
            KeyDefinition(label: "ら", action: .kana(kanaKeyID: "ら"), row: 2, column: 3),
            KeyDefinition(label: "改行", action: .returnOrConfirm, row: 2, column: 4),
            // row3
            KeyDefinition(label: "🌐", action: .nextKeyboard, row: 3, column: 0),
            KeyDefinition(label: "小゛゜", action: .toggleDakuten, row: 3, column: 1), // 変更: 「、。?!」と左右入れ替え
            KeyDefinition(label: "わ", action: .kana(kanaKeyID: "わ"), row: 3, column: 2),
            KeyDefinition(label: "、。?!", action: .kana(kanaKeyID: "、"), row: 3, column: 3), // 変更: 「小゛゜」と左右入れ替え
            KeyDefinition(label: "次候補", action: .nextCandidate, row: 3, column: 4),
        ]
    }

    /// カタカナはひらがなキー配列のラベルだけカタカナに置換（入力自体は KanaTransform で変換）。
    /// 実際の文字変換は InputState 側でモードを見て行うため、ここではひらがな配列を流用する。
    public static func katakanaLayout() -> [KeyDefinition] {
        hiraganaLayout().map { key in
            KeyDefinition(label: key.kanaKey == nil ? key.label : KanaTransform.toKatakana(key.label),
                          action: key.action, row: key.row, column: key.column)
        }
    }

    public static func alphabetLayout() -> [KeyDefinition] {
        qwertyRows([Array("qwertyuiop").map(String.init),
                    Array("asdfghjkl").map(String.init),
                    Array("zxcvbnm").map(String.init)], alphabet: true)
    }

    public static func numberLayout() -> [KeyDefinition] {
        qwertyRows([Array("1234567890").map(String.init),
                    ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                    [".", ",", "?", "!", "'"]], alphabet: false)
    }

    public static func symbolLayout() -> [KeyDefinition] {
        qwertyRows([["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                    ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
                    [".", ",", "?", "!", "'"]], alphabet: false, symbols: true)
    }

    private static func qwertyRows(_ rows: [[String]], alphabet: Bool, symbols: Bool = false) -> [KeyDefinition] {
        var result: [KeyDefinition] = []
        for (row, characters) in rows.enumerated() {
            var keys = characters.map { ($0, KeyAction.input($0)) }
            if row == 2 {
                keys.insert(alphabet ? ("⇧", .shift) : (symbols ? "123" : "#+=", .setInputMode(symbols ? .number : .symbol)), at: 0)
                keys.append(("⌫", .backspace))
            }
            result += keys.enumerated().map { KeyDefinition(label: $0.element.0, action: $0.element.1, row: row, column: $0.offset) }
        }
        let bottom: [(String, KeyAction)] = [(alphabet ? "123" : "ABC", .setInputMode(alphabet ? .number : .alphabet)),
            ("あいう", .setInputMode(.hiragana)), ("🌐", .nextKeyboard), ("space", .space), ("return", .returnOrConfirm)]
        result += bottom.enumerated().map { KeyDefinition(label: $0.element.0, action: $0.element.1, row: 3, column: $0.offset) }
        return result
    }

    /// モードに応じたレイアウトを返す。
    public static func layout(for mode: InputMode) -> [KeyDefinition] {
        let keys: [KeyDefinition]
        switch mode {
        case .hiragana: keys = hiraganaLayout()
        case .katakana: keys = katakanaLayout()
        case .alphabet: keys = alphabetLayout()
        case .number: keys = numberLayout()
        case .symbol: keys = symbolLayout()
        }
        return keys.map { key in
            guard mode == .hiragana || mode == .katakana else { return key }
            guard key.column == 0 else { return key }
            if key.row == 2 && mode == .hiragana {
                return KeyDefinition(label: "カナ", action: .setInputMode(.katakana), row: 2, column: 0)
            }
            return key
        }
    }

    /// グリッドの行数・列数。
    public static let rowCount = 4
    public static let columnCount = 5
}
