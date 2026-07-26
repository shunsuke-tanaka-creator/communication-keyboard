// KanaInputTests.swift
// MozcFlickKeyboard — かな入力ロジック（KanaTransform / KanaTable）の単体テスト。
//
// 結合後の実 API に合わせて調整済み:
//  - KanaTable.key(for:)?.character(for: FlickDirection) でフリック文字を取得
//  - KanaTransform.cycled(_:) 濁点/半濁点/小書き循環トグル
//  - KanaTransform.smallToggled(_:) 大小トグル
//  - KanaTransform.toKatakana(_:) ひらがな→カタカナ
// 方向割り当ては KanaTable の実データ（中央/左/上/右/下）に一致させている。

import XCTest
@testable import MozcFlickShared

final class KanaInputTests: XCTestCase {

    /// フリック文字取得ヘルパ。
    private func flick(_ id: String, _ dir: FlickDirection) -> String? {
        KanaTable.key(for: id)?.character(for: dir)
    }

    // MARK: - 基本 5 段（あいうえお / かきくけこ）

    // 中央=あ, 左=い, 上=う, 右=え, 下=お。
    func testSeionAGyou() {
        XCTAssertEqual(flick("あ", .center), "あ")
        XCTAssertEqual(flick("あ", .left),   "い")
        XCTAssertEqual(flick("あ", .up),     "う")
        XCTAssertEqual(flick("あ", .right),  "え")
        XCTAssertEqual(flick("あ", .down),   "お")
    }

    func testSeionKaGyou() {
        XCTAssertEqual(flick("か", .center), "か")
        XCTAssertEqual(flick("か", .left),   "き")
        XCTAssertEqual(flick("か", .up),     "く")
        XCTAssertEqual(flick("か", .right),  "け")
        XCTAssertEqual(flick("か", .down),   "こ")
    }

    // MARK: - 濁点（がぎぐげご）: cycled で か→が

    func testDakuten() {
        XCTAssertEqual(KanaTransform.cycled("か"), "が")
        XCTAssertEqual(KanaTransform.cycled("き"), "ぎ")
        XCTAssertEqual(KanaTransform.cycled("く"), "ぐ")
        XCTAssertEqual(KanaTransform.cycled("け"), "げ")
        XCTAssertEqual(KanaTransform.cycled("こ"), "ご")
        // 濁点/半濁点/小書きの循環対象でない文字はそのまま。
        XCTAssertEqual(KanaTransform.cycled("ん"), "ん")
    }

    // MARK: - 半濁点（ぱぴぷぺぽ）: は→ば→ぱ→は の循環

    func testHandakuten() {
        // は→ば（濁点）→ぱ（半濁点）→は。
        XCTAssertEqual(KanaTransform.cycled("は"), "ば")
        XCTAssertEqual(KanaTransform.cycled("ば"), "ぱ")
        XCTAssertEqual(KanaTransform.cycled("ぱ"), "は")
        XCTAssertEqual(KanaTransform.cycled("ひ"), "び")
        XCTAssertEqual(KanaTransform.cycled("び"), "ぴ")
    }

    // MARK: - 小文字化（ぁぃぅぇぉ / っゃゅょ）: smallToggled

    func testSmallVowels() {
        XCTAssertEqual(KanaTransform.smallToggled("あ"), "ぁ")
        XCTAssertEqual(KanaTransform.smallToggled("い"), "ぃ")
        XCTAssertEqual(KanaTransform.smallToggled("う"), "ぅ")
        XCTAssertEqual(KanaTransform.smallToggled("え"), "ぇ")
        XCTAssertEqual(KanaTransform.smallToggled("お"), "ぉ")
    }

    func testSmallTsuAndYouon() {
        XCTAssertEqual(KanaTransform.smallToggled("つ"), "っ")
        XCTAssertEqual(KanaTransform.smallToggled("や"), "ゃ")
        XCTAssertEqual(KanaTransform.smallToggled("ゆ"), "ゅ")
        XCTAssertEqual(KanaTransform.smallToggled("よ"), "ょ")
        XCTAssertEqual(KanaTransform.smallToggled("わ"), "ゎ")
        // 小文字化対象外はそのまま。
        XCTAssertEqual(KanaTransform.smallToggled("か"), "か")
    }

    // MARK: - わ行・記号（わをんー / 、。！？）

    // わ行キー: 中央=わ, 左=を, 上=ん, 右=ー（実データに一致）。
    func testWaGyouAndChoonpu() {
        XCTAssertEqual(flick("わ", .center), "わ")
        XCTAssertEqual(flick("わ", .left),   "を")
        XCTAssertEqual(flick("わ", .up),     "ん")
        XCTAssertEqual(flick("わ", .right),  "ー")
    }

    // 記号キー（、。？！…）: 中央=、 左=。 上=？ 右=！ 下=…（実データに一致）。
    func testSymbols() {
        XCTAssertEqual(flick("、", .center), "、")
        XCTAssertEqual(flick("、", .left),   "。")
        XCTAssertEqual(flick("、", .up),     "？")
        XCTAssertEqual(flick("、", .right),  "！")
        XCTAssertEqual(flick("、", .down),   "…")
    }

    // MARK: - カタカナ変換

    func testToKatakana() {
        XCTAssertEqual(KanaTransform.toKatakana("あいうえお"), "アイウエオ")
        XCTAssertEqual(KanaTransform.toKatakana("がっこう"), "ガッコウ")
        XCTAssertEqual(KanaTransform.toKatakana("きゃっと"), "キャット")
        // 非ひらがな（記号）はそのまま。
        XCTAssertEqual(KanaTransform.toKatakana("ー"), "ー")
    }

    // MARK: - トグル入力（同一キー連打でかな循環：cyclingLastCharacter）

    func testCyclingLastCharacter() {
        // 末尾1文字を循環トグル。「あか」→「あが」。
        XCTAssertEqual(KanaTransform.cyclingLastCharacter(of: "あか"), "あが")
        // 「あ」→「ぁ」（母音小書き循環）。
        XCTAssertEqual(KanaTransform.cyclingLastCharacter(of: "あ"), "ぁ")
    }

    // MARK: - 複合ケース（小文字化 → カタカナ化）

    func testCompositeSmallThenKatakana() {
        let small = KanaTransform.smallToggled("つ")  // っ
        XCTAssertEqual(small, "っ")
        XCTAssertEqual(KanaTransform.toKatakana(small), "ッ")
    }
}
