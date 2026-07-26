// ConversionEngineTests.swift
// MozcFlickKeyboard — JapaneseConversionEngine プロトコルの契約テスト。
//
// 【対象と確定度】
//  - JapaneseConversionEngine / ConversionResult / ConversionCandidate / ConversionSegment
//    は Shared/JapaneseConversionEngine.swift の確定済み契約なので、その不変条件を厳密に検証する。
//  - LocalStubEngine は Shared/LocalStubEngine.swift として作られる想定（API 未確定）。
//    本ファイルではまず「プロトコルに準拠していれば満たすべき契約」を、テスト内モック実装
//    (MockConversionEngine) を対象に検証する。LocalStubEngine 用テストは末尾に用意し、
//    #if で切り替えられるようにしてある。
//
// 【モジュール名について】
//  - import する対象モジュール名は @testable import MozcFlickShared 等になる可能性があるが未確定。
//    モジュール名はメインが結合時に調整すること（下の import 行を実際のモジュール名へ）。

import XCTest
// モジュール名はメインが結合時に調整すること。
@testable import MozcFlickShared

// MARK: - テスト用モック実装（プロトコル契約の検証用。実装ファイルは編集しない）

/// JapaneseConversionEngine の最小モック。
/// 実 Mozc / LocalStubEngine が満たすべき「呼び出し順と ConversionResult 不変条件」を
/// 表現するために、テスト内でのみ用いる素朴な実装。
final class MockConversionEngine: JapaneseConversionEngine {
    private(set) var composition = ""
    private var converting = false
    /// commit / reset が呼ばれた回数（副作用検証用）。
    private(set) var resetCount = 0

    func reset() {
        composition = ""
        converting = false
        resetCount += 1
    }

    func insert(_ text: String) {
        composition += text
    }

    func deleteBackward() {
        guard !composition.isEmpty else { return }
        composition.removeLast()
    }

    func requestConversion() -> ConversionResult {
        converting = true
        // よみ全体を1文節・1候補として返す最小変換（漢字化はしない素朴実装）。
        let cand = ConversionCandidate(id: "seg0-0", value: composition, reading: composition)
        let seg = ConversionSegment(reading: composition, selected: cand, candidates: [cand])
        return ConversionResult(composition: composition,
                                segments: [seg],
                                candidates: [cand],
                                focusedSegment: 0,
                                isConverting: true)
    }

    func requestPrediction() -> ConversionResult {
        // 予測は変換前サジェスト。isConverting は false のまま。
        let cand = ConversionCandidate(id: "pred0", value: composition, reading: composition)
        return ConversionResult(composition: composition,
                                candidates: composition.isEmpty ? [] : [cand],
                                isConverting: false)
    }

    func selectCandidate(id: String) -> ConversionResult {
        // 選択しても composition は保持（commit 前）。
        return requestConversion()
    }

    func moveFocus(by offset: Int) -> ConversionResult {
        return requestConversion()
    }

    func resizeFocusedSegment(by offset: Int) -> ConversionResult {
        return requestConversion()
    }

    func commit() -> String {
        let out = composition
        reset() // 契約: commit の副作用で内部状態はリセット。
        return out
    }

    func cancelConversion() -> ConversionResult {
        converting = false
        // かな入力状態へ戻す（composition は保持）。
        return ConversionResult(composition: composition, isConverting: false)
    }
}

// MARK: - 契約テスト本体

final class ConversionEngineTests: XCTestCase {

    private var engine: JapaneseConversionEngine!

    override func setUp() {
        super.setUp()
        engine = MockConversionEngine()
        engine.reset()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // reset 直後は空の状態であること。
    func testResetProducesEmptyState() {
        engine.insert("あ")
        engine.reset()
        let r = engine.requestPrediction()
        XCTAssertEqual(r.composition, "", "reset 後の composition は空であるべき")
        XCTAssertFalse(r.isConverting, "reset 後は変換中でないべき")
        XCTAssertTrue(r.candidates.isEmpty, "reset 後は候補が無いべき")
    }

    // insert が composition 末尾へ追加されること。
    func testInsertAppendsToComposition() {
        engine.insert("あ")
        engine.insert("い")
        engine.insert("う")
        let r = engine.requestConversion()
        XCTAssertEqual(r.composition, "あいう", "insert は composition 末尾へ順に追加されるべき")
    }

    // deleteBackward が末尾1文字を削除すること。
    func testDeleteBackwardRemovesLastCharacter() {
        engine.insert("あい")
        engine.deleteBackward()
        let r = engine.requestConversion()
        XCTAssertEqual(r.composition, "あ", "deleteBackward は末尾1文字を削除するべき")
    }

    // 空状態での deleteBackward はクラッシュせず空のまま。
    func testDeleteBackwardOnEmptyIsSafe() {
        engine.deleteBackward()
        let r = engine.requestConversion()
        XCTAssertEqual(r.composition, "", "空状態の deleteBackward は空のままであるべき")
    }

    // requestConversion は isConverting=true で、segments が composition を覆うこと。
    func testRequestConversionInvariants() {
        engine.insert("へんかん")
        let r = engine.requestConversion()
        XCTAssertTrue(r.isConverting, "requestConversion 後は isConverting=true であるべき")
        XCTAssertFalse(r.segments.isEmpty, "変換後は少なくとも1文節あるべき")
        // 不変条件: focusedSegment は segments の範囲内。
        XCTAssertTrue((0..<r.segments.count).contains(r.focusedSegment),
                      "focusedSegment は segments の範囲内であるべき")
        // 不変条件: 各文節の selected は candidates に含まれること。
        for seg in r.segments {
            XCTAssertTrue(seg.candidates.contains(seg.selected),
                          "各文節の selected は candidates に含まれるべき")
        }
        // 不変条件: segments の reading を連結すると composition と一致する。
        let joined = r.segments.map { $0.reading }.joined()
        XCTAssertEqual(joined, r.composition, "文節 reading の連結は composition と一致すべき")
    }

    // 呼び出し順: insert → requestConversion → commit の一連で確定文字列が返り、状態がリセットされること。
    func testCommitReturnsCompositionAndResets() {
        engine.insert("あい")
        _ = engine.requestConversion()
        let committed = engine.commit()
        XCTAssertEqual(committed, "あい", "commit は確定文字列を返すべき")
        // commit 後は空状態。
        let after = engine.requestPrediction()
        XCTAssertEqual(after.composition, "", "commit 後は composition が空であるべき")
        XCTAssertFalse(after.isConverting, "commit 後は変換中でないべき")
    }

    // cancelConversion は変換を取り消し、かな入力状態（isConverting=false）へ戻すこと。
    func testCancelConversionReturnsToKanaInput() {
        engine.insert("へんかん")
        _ = engine.requestConversion()
        let r = engine.cancelConversion()
        XCTAssertFalse(r.isConverting, "cancelConversion 後は isConverting=false であるべき")
        XCTAssertEqual(r.composition, "へんかん", "cancelConversion は composition を保持するべき")
    }

    // 候補は全て空でない value を持つこと（不変条件）。
    func testCandidatesHaveNonEmptyValues() {
        engine.insert("てすと")
        let r = engine.requestConversion()
        for c in r.candidates {
            XCTAssertFalse(c.value.isEmpty, "候補の value は空でないべき")
            XCTAssertFalse(c.id.isEmpty, "候補の id は空でないべき")
        }
    }

    // ConversionResult.empty の定義確認（確定契約）。
    func testConversionResultEmpty() {
        let e = ConversionResult.empty
        XCTAssertEqual(e.composition, "")
        XCTAssertTrue(e.segments.isEmpty)
        XCTAssertTrue(e.candidates.isEmpty)
        XCTAssertEqual(e.focusedSegment, 0)
        XCTAssertFalse(e.isConverting)
    }

    // ConversionCandidate の Equatable / 値保持の確認。
    func testCandidateEquatable() {
        let a = ConversionCandidate(id: "1", value: "今日", reading: "きょう")
        let b = ConversionCandidate(id: "1", value: "今日", reading: "きょう")
        let c = ConversionCandidate(id: "2", value: "京", reading: "きょう")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - LocalStubEngine 用テスト（実装が結合されたら有効化）
//
// LocalStubEngine のイニシャライザ API は未確定。メインが結合時に以下を調整すること:
//   - 生成方法: LocalStubEngine() 想定（引数無し）。辞書注入が必要ならメインが調整。
// 以下は LOCAL_STUB_AVAILABLE を定義した時だけコンパイルされる。
#if LOCAL_STUB_AVAILABLE
final class LocalStubEngineContractTests: XCTestCase {
    func testLocalStubConformsToContract() {
        // 仮定: 引数無しイニシャライザ（未確定 → メインが結合時に確認）。
        let engine: JapaneseConversionEngine = LocalStubEngine()
        engine.reset()
        engine.insert("へんかん")
        let r = engine.requestConversion()
        XCTAssertTrue(r.isConverting)
        XCTAssertEqual(r.composition, "へんかん")
        let committed = engine.commit()
        XCTAssertFalse(committed.isEmpty)
    }
}
#endif
