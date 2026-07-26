// KanaTable.swift
// MozcFlickKeyboard — かな行データ（データ駆動）。
//
// 12キーフリックの各キーが持つ「中央/上下左右」のかな文字をデータとして定義する。
// フリック方向の割り当ては一般的な日本語フリック配置に準拠する:
//   中央(center)=1文字目, 左(left)=2文字目, 上(up)=3文字目, 右(right)=4文字目, 下(down)=5文字目。
// 5文字未満のキー（や行・わ行・記号）は一般的な配置に従い一部方向を空にする。
//
// ここでは「トグル入力（同一キー連打でかな循環）」のための循環順も cycle として保持する。

import Foundation

/// フリック方向。中央タップと4方向。
public enum FlickDirection: Int, CaseIterable, Sendable {
    case center = 0
    case left
    case up
    case right
    case down
}

/// 1つの「かなキー」の定義。方向ごとに出力するかな文字を持つ。
/// value が空文字 "" の方向は「その方向にフリックしても入力なし」を表す。
public struct KanaKey: Sendable {
    /// キーの識別子（あ/か/さ...）。表示ラベルにも使う中央文字。
    public let id: String
    /// 方向 -> 出力かな。center は必ず持つ。
    public let flicks: [FlickDirection: String]

    public init(id: String, flicks: [FlickDirection: String]) {
        self.id = id
        self.flicks = flicks
    }

    /// 指定方向の出力文字。無ければ nil。
    public func character(for direction: FlickDirection) -> String? {
        guard let v = flicks[direction], !v.isEmpty else { return nil }
        return v
    }

    /// トグル入力用の循環順（center,left,up,right,down の順で空でないものだけ）。
    public var cycle: [String] {
        FlickDirection.allCases.compactMap { character(for: $0) }
    }
}

/// ひらがな 10 行 + 記号キーのデータテーブル。
/// 入力モード（ひらがな/カタカナ/英字/数字/記号）はこのひらがなを基準に KanaTransform で変換する。
public enum KanaTable {

    /// あ行〜わ行 + 記号キーの並び（12キー配列の「かなキー」部分）。
    public static let hiragana: [KanaKey] = [
        // あ行: あ い う え お
        KanaKey(id: "あ", flicks: [.center: "あ", .left: "い", .up: "う", .right: "え", .down: "お"]),
        // か行: か き く け こ
        KanaKey(id: "か", flicks: [.center: "か", .left: "き", .up: "く", .right: "け", .down: "こ"]),
        // さ行: さ し す せ そ
        KanaKey(id: "さ", flicks: [.center: "さ", .left: "し", .up: "す", .right: "せ", .down: "そ"]),
        // た行: た ち つ て と
        KanaKey(id: "た", flicks: [.center: "た", .left: "ち", .up: "つ", .right: "て", .down: "と"]),
        // な行: な に ぬ ね の
        KanaKey(id: "な", flicks: [.center: "な", .left: "に", .up: "ぬ", .right: "ね", .down: "の"]),
        // は行: は ひ ふ へ ほ
        KanaKey(id: "は", flicks: [.center: "は", .left: "ひ", .up: "ふ", .right: "へ", .down: "ほ"]),
        // ま行: ま み む め も
        KanaKey(id: "ま", flicks: [.center: "ま", .left: "み", .up: "む", .right: "め", .down: "も"]),
        // や行: 中央や 上ゆ 下よ / 左右は入力なし
        KanaKey(id: "や", flicks: [.center: "や", .left: "", .up: "ゆ", .right: "", .down: "よ"]),
        // ら行: ら り る れ ろ
        KanaKey(id: "ら", flicks: [.center: "ら", .left: "り", .up: "る", .right: "れ", .down: "ろ"]),
        // わ行: わ を ん ー / 中央わ 左を 上ん 右ー
        KanaKey(id: "わ", flicks: [.center: "わ", .left: "を", .up: "ん", .right: "ー", .down: ""]),
        // 記号キー: 、。？！ / 中央、 左。 上？ 右！ 下…
        KanaKey(id: "、", flicks: [.center: "、", .left: "。", .up: "？", .right: "！", .down: "…"]),
    ]

    /// id から KanaKey を引く。
    public static func key(for id: String) -> KanaKey? {
        hiragana.first { $0.id == id }
    }
}
