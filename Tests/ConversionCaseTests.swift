// ConversionCaseTests.swift
// MozcFlickKeyboard — 変換テストケースをデータとして列挙する回帰テスト。
//
// 【対象と確定度】
//  - LocalStubEngine（Shared/LocalStubEngine.swift 想定）を JapaneseConversionEngine として対象にする。
//    LocalStubEngine の生成 API は未確定 → メインが結合時に調整すること。
//  - JapaneseConversionEngine / ConversionResult / ConversionCandidate は確定契約。
//
// 【判定方針】
//  - 厳密一致が期待できるもの（辞書に確実に載る定番）は「第1候補が一致」を検証。
//  - スタブでは厳密一致が難しいもの（長文・予測・日付/時刻/数値）は
//    「候補のいずれかに期待文字列が含まれること」を検証する（弱い契約）。
//  - スタブの語彙が未実装で落ちる場合、メインは LocalStubEngine の辞書へ本ファイルの
//    expected を追加するか、テストの strictness を調整すること。
//
// 【仮定した API（結合時に要確認）】
//  - LocalStubEngine() : 引数無しイニシャライザ。
//  - 変換フロー: reset() → insert(reading) → requestConversion() で候補取得。
//  - 予測フロー: reset() → insert(prefix) → requestPrediction() で候補取得。
//
// 【モジュール名について】
//  - モジュール名はメインが結合時に調整すること（@testable import 行）。

import XCTest
// モジュール名はメインが結合時に調整すること。
@testable import MozcFlickShared

// LocalStubEngine が結合されるまではビルド対象外。結合後 LOCAL_STUB_AVAILABLE を定義する。
#if LOCAL_STUB_AVAILABLE

final class ConversionCaseTests: XCTestCase {

    private var engine: JapaneseConversionEngine!

    override func setUp() {
        super.setUp()
        engine = LocalStubEngine() // 生成 API 未確定 → メインが調整
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // 入力（よみ）を変換し、第1候補（先頭候補）の value を返すヘルパ。
    private func firstCandidate(for reading: String) -> String? {
        engine.reset()
        engine.insert(reading)
        let r = engine.requestConversion()
        return r.candidates.first?.value ?? r.segments.first?.selected.value
    }

    // 入力を変換し、候補 value 群を返すヘルパ。
    private func candidateValues(for reading: String) -> [String] {
        engine.reset()
        engine.insert(reading)
        let r = engine.requestConversion()
        var values = r.candidates.map { $0.value }
        values.append(contentsOf: r.segments.map { $0.selected.value })
        return values
    }

    // MARK: - 厳密一致（第1候補一致）を期待する定番ケース

    func testExactConversions() {
        // (よみ, 期待する第1候補)
        let cases: [(String, String)] = [
            ("へんかん", "変換"),
            ("とうきょうと", "東京都"),
            ("にほんご", "日本語"),
            ("かんじ", "漢字"),
            ("あさ", "朝"),
        ]
        for (reading, expected) in cases {
            let got = firstCandidate(for: reading)
            XCTAssertEqual(got, expected,
                           "「\(reading)」の第1候補は「\(expected)」を期待（実際: \(got ?? "nil")）")
        }
    }

    // MARK: - 候補に含まれることを期待する（長文・厳密一致が難しい）ケース

    func testContainedInCandidates() {
        // (よみ, 候補のどこかに含まれてほしい文字列)
        let cases: [(String, String)] = [
            ("きょうはいいてんきです", "今日はいい天気です"),
            ("ありがとうございます", "ありがとうございます"),
            ("よろしくおねがいします", "よろしくお願いします"),
        ]
        for (reading, expected) in cases {
            let values = candidateValues(for: reading)
            XCTAssertTrue(values.contains(expected),
                          "「\(reading)」の候補に「\(expected)」が含まれることを期待（実際: \(values)）")
        }
    }

    // MARK: - 予測変換（変換前サジェスト）

    func testPrediction() {
        engine.reset()
        engine.insert("きょう") // 「きょう」から「今日」「京都」等を予測
        let r = engine.requestPrediction()
        XCTAssertFalse(r.isConverting, "予測段階は isConverting=false であるべき")
        XCTAssertFalse(r.candidates.isEmpty, "予測候補が返るべき")
        let values = r.candidates.map { $0.value }
        XCTAssertTrue(values.contains(where: { $0.contains("今日") || $0.contains("京") }),
                      "予測候補に『今日』または『京』を含む語を期待（実際: \(values)）")
    }

    // MARK: - 日付・時刻・数値の特殊変換（候補に含まれることを検証）

    // 「きょう」→ 今日の日付候補が出る想定（例: 2026/07/13 等）。厳密値は環境依存なので形式で検証。
    func testDateConversionFormat() {
        let values = candidateValues(for: "きょう")
        // yyyy/MM/dd もしくは M月d日 形式の候補があること（どちらか一方でも可）。
        let hasDate = values.contains { v in
            v.range(of: #"^\d{4}/\d{1,2}/\d{1,2}$"#, options: .regularExpression) != nil ||
            v.range(of: #"\d{1,2}月\d{1,2}日"#, options: .regularExpression) != nil
        }
        XCTAssertTrue(hasDate, "「きょう」の候補に日付形式が含まれることを期待（実際: \(values)）")
    }

    // 「いま」→ 現在時刻候補（HH:mm 形式）が出る想定。
    func testTimeConversionFormat() {
        let values = candidateValues(for: "いま")
        let hasTime = values.contains { v in
            v.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil ||
            v.range(of: #"\d{1,2}時\d{1,2}分"#, options: .regularExpression) != nil
        }
        XCTAssertTrue(hasTime, "「いま」の候補に時刻形式が含まれることを期待（実際: \(values)）")
    }

    // 数値の読み → 漢数字/アラビア数字候補。「ひゃく」→「100」または「百」。
    func testNumberConversion() {
        let values = candidateValues(for: "ひゃく")
        XCTAssertTrue(values.contains("100") || values.contains("百"),
                      "「ひゃく」の候補に『100』または『百』を期待（実際: \(values)）")
    }

    // MARK: - 変換結果の不変条件（全ケース共通で成立すべき）

    func testConversionInvariantsForSample() {
        engine.reset()
        engine.insert("へんかん")
        let r = engine.requestConversion()
        // 文節 reading 連結 == composition。
        let joined = r.segments.map { $0.reading }.joined()
        if !r.segments.isEmpty {
            XCTAssertEqual(joined, r.composition)
        }
        // 各文節 selected は candidates に含まれる。
        for seg in r.segments {
            XCTAssertTrue(seg.candidates.contains(seg.selected))
        }
    }
}

#endif
