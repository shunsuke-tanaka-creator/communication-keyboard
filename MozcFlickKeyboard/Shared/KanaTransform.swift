// KanaTransform.swift
// MozcFlickKeyboard — かな文字操作ロジック（データ駆動）。
//
// 提供する変換:
//  - 濁点/半濁点/小書きの循環トグル（例: か → が → か、は → ば → ぱ → は、つ → っ → つ）
//  - ひらがな → カタカナ / 半角カタカナ
//  - あ → ぁ 等の母音小書き、や → ゃ、つ → っ 等
//
// すべて if 分岐ではなく変換テーブル（辞書）で定義する。

import Foundation

public enum KanaTransform {

    // MARK: - 循環トグルテーブル
    //
    // 「濁点半濁点小文字」機能キーで直前1文字を循環変換するためのテーブル。
    // 各文字が次に遷移する文字を定義し、末尾は先頭へ戻る（循環）。
    // 例: "か" -> "が" -> "か"（2要素で循環）, "は" -> "ば" -> "ぱ" -> "は"。

    /// 循環グループ。同一グループ内を順に巡回する。
    private static let cycleGroups: [[String]] = [
        // か行濁点
        ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
        // さ行濁点
        ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
        // た行濁点 + っ 小書き
        ["た", "だ"], ["ち", "ぢ"], ["つ", "っ", "づ"], ["て", "で"], ["と", "ど"],
        // は行 濁点半濁点
        ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"], ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
        // あ行 小書き母音
        ["あ", "ぁ"], ["い", "ぃ"], ["う", "ぅ", "ゔ"], ["え", "ぇ"], ["お", "ぉ"],
        // や行 小書き
        ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"],
        // わ 小書き
        ["わ", "ゎ"],
    ]

    /// 文字 -> 循環次文字（トグル用）を事前展開したテーブル。
    private static let cycleNext: [String: String] = {
        var table: [String: String] = [:]
        for group in cycleGroups where group.count >= 2 {
            for (i, ch) in group.enumerated() {
                let next = group[(i + 1) % group.count]
                table[ch] = next
            }
        }
        return table
    }()

    /// 1文字を循環トグルした結果を返す。対象外文字はそのまま返す。
    public static func cycled(_ ch: String) -> String {
        cycleNext[ch] ?? ch
    }

    /// 文字列末尾1文字を循環トグルする。空文字列はそのまま返す。
    public static func cyclingLastCharacter(of text: String) -> String {
        guard let last = text.last else { return text }
        let toggled = cycled(String(last))
        return String(text.dropLast()) + toggled
    }

    // MARK: - 小書きトグル（大小のみ、濁点は除く）
    //
    // 大文字 <-> 小文字のみを行うトグル（や行・あ行母音・つ・わ）。

    private static let smallPairs: [String: String] = {
        let pairs: [(String, String)] = [
            ("あ", "ぁ"), ("い", "ぃ"), ("う", "ぅ"), ("え", "ぇ"), ("お", "ぉ"),
            ("や", "ゃ"), ("ゆ", "ゅ"), ("よ", "ょ"),
            ("つ", "っ"), ("わ", "ゎ"),
        ]
        var table: [String: String] = [:]
        for (big, small) in pairs {
            table[big] = small
            table[small] = big
        }
        return table
    }()

    /// 大小のみトグル。対象外はそのまま。
    public static func smallToggled(_ ch: String) -> String {
        smallPairs[ch] ?? ch
    }

    // MARK: - カタカナ変換
    //
    // ひらがな U+3041...U+3096 は カタカナ U+30A1...U+30F6 と 0x60 のオフセット関係。

    /// ひらがな文字列をカタカナへ変換する。
    public static func toKatakana(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            if scalar.value >= 0x3041 && scalar.value <= 0x3096,
               let converted = Unicode.Scalar(scalar.value + 0x60) {
                return Character(converted)
            }
            return Character(scalar)
        })
    }

    /// カタカナ文字列をひらがなへ変換する。
    public static func toHiragana(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            if scalar.value >= 0x30A1 && scalar.value <= 0x30F6,
               let converted = Unicode.Scalar(scalar.value - 0x60) {
                return Character(converted)
            }
            return Character(scalar)
        })
    }

    // MARK: - 半角カタカナ変換
    //
    // 全角カタカナ -> 半角カタカナのマッピングテーブル（濁点は結合文字で表現）。

    private static let fullToHalfKatakana: [String: String] = [
        "ア": "ｱ", "イ": "ｲ", "ウ": "ｳ", "エ": "ｴ", "オ": "ｵ",
        "カ": "ｶ", "キ": "ｷ", "ク": "ｸ", "ケ": "ｹ", "コ": "ｺ",
        "サ": "ｻ", "シ": "ｼ", "ス": "ｽ", "セ": "ｾ", "ソ": "ｿ",
        "タ": "ﾀ", "チ": "ﾁ", "ツ": "ﾂ", "テ": "ﾃ", "ト": "ﾄ",
        "ナ": "ﾅ", "ニ": "ﾆ", "ヌ": "ﾇ", "ネ": "ﾈ", "ノ": "ﾉ",
        "ハ": "ﾊ", "ヒ": "ﾋ", "フ": "ﾌ", "ヘ": "ﾍ", "ホ": "ﾎ",
        "マ": "ﾏ", "ミ": "ﾐ", "ム": "ﾑ", "メ": "ﾒ", "モ": "ﾓ",
        "ヤ": "ﾔ", "ユ": "ﾕ", "ヨ": "ﾖ",
        "ラ": "ﾗ", "リ": "ﾘ", "ル": "ﾙ", "レ": "ﾚ", "ロ": "ﾛ",
        "ワ": "ﾜ", "ヲ": "ｦ", "ン": "ﾝ",
        "ガ": "ｶﾞ", "ギ": "ｷﾞ", "グ": "ｸﾞ", "ゲ": "ｹﾞ", "ゴ": "ｺﾞ",
        "ザ": "ｻﾞ", "ジ": "ｼﾞ", "ズ": "ｽﾞ", "ゼ": "ｾﾞ", "ゾ": "ｿﾞ",
        "ダ": "ﾀﾞ", "ヂ": "ﾁﾞ", "ヅ": "ﾂﾞ", "デ": "ﾃﾞ", "ド": "ﾄﾞ",
        "バ": "ﾊﾞ", "ビ": "ﾋﾞ", "ブ": "ﾌﾞ", "ベ": "ﾍﾞ", "ボ": "ﾎﾞ",
        "パ": "ﾊﾟ", "ピ": "ﾋﾟ", "プ": "ﾌﾟ", "ペ": "ﾍﾟ", "ポ": "ﾎﾟ",
        "ヴ": "ｳﾞ",
        "ァ": "ｧ", "ィ": "ｨ", "ゥ": "ｩ", "ェ": "ｪ", "ォ": "ｫ",
        "ャ": "ｬ", "ュ": "ｭ", "ョ": "ｮ", "ッ": "ｯ",
        "ー": "ｰ", "、": "､", "。": "｡", "・": "･",
    ]

    /// ひらがな/カタカナ文字列を半角カタカナへ変換する。
    /// まずカタカナへ寄せてからマッピングする。
    public static func toHalfWidthKatakana(_ text: String) -> String {
        let katakana = toKatakana(text)
        var result = ""
        for ch in katakana {
            let s = String(ch)
            result += fullToHalfKatakana[s] ?? s
        }
        return result
    }
}
