import XCTest
import UIKit
@testable import MozcFlickShared

final class PersonalizedEngineTests: XCTestCase {
    func testKatakanaAlternativeCommitsWithoutSubmittingNativeID() {
        let base = CandidateSpyEngine()
        let engine = PersonalizedConversionEngine(base: base)
        engine.insert("きょう")
        XCTAssertTrue(engine.requestPrediction().candidates.contains { $0.id == "literal:katakana" })
        _ = engine.selectCandidate(id: "literal:katakana")
        XCTAssertEqual(engine.commit(), "キョウ")
        XCTAssertNil(base.selectedID)
    }
    func testMultiSegmentConversionDoesNotMixWholePhraseReplacements() {
        let entry = UserDictionaryEntry(reading: "はしはな", word: "橋と花")
        let engine = PersonalizedConversionEngine(base: LocalStubEngine(), dictionaryEntries: { _ in [entry] })
        engine.insert("はしはな")
        let result = engine.requestConversion()
        XCTAssertGreaterThan(result.segments.count, 1)
        XCTAssertFalse(result.candidates.contains { $0.value == "橋と花" || $0.id.hasPrefix("literal:") })
        XCTAssertEqual(engine.commit(), "橋花")
    }
    func testLiteralDoesNotSelectNativeCandidateZero() {
        let base = CandidateSpyEngine()
        let engine = PersonalizedConversionEngine(base: base)
        engine.insert("きょう")
        let result = engine.requestPrediction()
        XCTAssertEqual(result.candidates.first?.value, "今日")
        _ = engine.selectCandidate(id: "literal:reading")
        XCTAssertEqual(engine.commit(), "きょう")
        XCTAssertNil(base.selectedID)
        XCTAssertEqual(engine.commit(), "")
    }

    func testDictionaryCompletionUsesWholeWordAndLearnsOnce() {
        let base = CandidateSpyEngine()
        let entry = UserDictionaryEntry(reading: "くぼた", word: "久保田研究室")
        var learned: [(String, String)] = []
        let engine = PersonalizedConversionEngine(base: base, dictionaryEntries: { _ in [entry] },
            recordSelection: { learned.append(($0, $1)) })
        engine.insert("くぼ")
        let candidate = engine.requestPrediction().candidates.first!
        XCTAssertEqual(candidate.value, "久保田研究室")
        _ = engine.selectCandidate(id: candidate.id)
        XCTAssertEqual(engine.commit(), "久保田研究室")
        XCTAssertNil(base.selectedID)
        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned.first?.0, "くぼた")
        _ = engine.commit()
        XCTAssertEqual(learned.count, 1)
    }

    func testNativeIDsAndWholeSentenceCommitArePreserved() {
        let base = CandidateSpyEngine()
        var learned = ""
        let engine = PersonalizedConversionEngine(base: base, recordSelection: { _, value in learned = value })
        engine.insert("きょうは")
        let result = engine.requestPrediction()
        XCTAssertEqual(result.candidates.first?.id, "42")
        _ = engine.selectCandidate(id: "42")
        XCTAssertEqual(base.selectedID, "42")
        XCTAssertEqual(engine.commit(), "今日は")
        XCTAssertEqual(learned, "今日")
    }

    func testStaleCandidateDoesNotReachEngine() {
        let base = CandidateSpyEngine()
        let engine = PersonalizedConversionEngine(base: base)
        engine.insert("きょう")
        _ = engine.requestPrediction()
        engine.reset()
        _ = engine.selectCandidate(id: "42")
        XCTAssertNil(base.selectedID)
        XCTAssertEqual(engine.commit(), "")
    }

    func testDisabledAndUnrelatedDictionaryEntriesAreNotSuggested() {
        let engine = PersonalizedConversionEngine(base: CandidateSpyEngine(), dictionaryEntries: { _ in [
            UserDictionaryEntry(reading: "きょう", word: "非表示", isEnabled: false),
            UserDictionaryEntry(reading: "あした", word: "別の読み")
        ] })
        engine.insert("きょう")
        XCTAssertFalse(engine.requestPrediction().candidates.contains { ["非表示", "別の読み"].contains($0.value) })
    }

    func testUserDictionaryDuplicatesAreDeduplicated() {
        let entries = [UserDictionaryEntry(reading: "きょう", word: "今日"),
                       UserDictionaryEntry(reading: "きょうと", word: "今日")]
        let engine = PersonalizedConversionEngine(base: LocalStubEngine(), dictionaryEntries: { _ in entries })
        engine.insert("きょ")
        XCTAssertEqual(engine.requestPrediction().candidates.filter { $0.value == "今日" }.count, 1)
    }

    func testLearningChangesRankAndSurvivesReloadButPrivateModeDoesNotWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LearningStore(baseURL: directory)
        let engine = PersonalizedConversionEngine(base: LocalStubEngine(), learningScores: { store.scores(forReading: $0) },
            recordSelection: { try? store.recordSelection(reading: $0, word: $1) })
        engine.insert("はし")
        let candidate = try XCTUnwrap(engine.requestPrediction().candidates.first { $0.value == "箸" })
        _ = engine.selectCandidate(id: candidate.id)
        XCTAssertEqual(engine.commit(), "箸")
        engine.insert("はし")
        XCTAssertEqual(engine.requestPrediction().candidates.first?.value, "箸")
        store.isPrivateMode = true
        try store.recordSelection(reading: "はし", word: "橋")
        store.isPrivateMode = false
        store.isLearningEnabled = false
        try store.recordSelection(reading: "はし", word: "端")
        let reloaded = try LearningStore(baseURL: directory)
        XCTAssertEqual(reloaded.scores(forReading: "はし"), ["箸": 1])
    }
}

private final class CandidateSpyEngine: JapaneseConversionEngine {
    var reading = ""
    var selectedID: String?
    func reset() { reading = "" }
    func insert(_ text: String) { reading += text }
    func deleteBackward() { if !reading.isEmpty { reading.removeLast() } }
    func requestPrediction() -> ConversionResult {
        ConversionResult(composition: reading, candidates: reading.isEmpty ? [] : [
            ConversionCandidate(id: "42", value: "今日", reading: "きょう")])
    }
    func requestConversion() -> ConversionResult { requestPrediction() }
    func selectCandidate(id: String) -> ConversionResult { selectedID = id; return requestPrediction() }
    func moveFocus(by offset: Int) -> ConversionResult { requestPrediction() }
    func resizeFocusedSegment(by offset: Int) -> ConversionResult { requestPrediction() }
    func cancelConversion() -> ConversionResult { requestPrediction() }
    func commit() -> String {
        let result = reading.isEmpty ? "" : (selectedID == nil ? reading : "今日は")
        reading = ""
        return result
    }
}

final class KeyboardInputStateTests: XCTestCase {
    func testFlickOnlyStillAcceptsCenterAndRepeatedCenter() {
        let state = InputState(engine: LocalStubEngine())
        state.flickOnlyEnabled = true
        state.input(kanaKeyID: "あ", direction: .center)
        state.input(kanaKeyID: "あ", direction: .center)
        XCTAssertEqual(state.commit(), "ああ")
    }
    func testToggleExpiresAndFlickDoesNotToggle() {
        var clock: TimeInterval = 0
        let state = InputState(engine: LocalStubEngine(), now: { clock })
        state.flickOnlyEnabled = false
        state.input(kanaKeyID: "あ", direction: .center)
        clock = 0.1
        state.input(kanaKeyID: "あ", direction: .center)
        XCTAssertEqual(state.currentResult.composition, "い")
        clock = 1.2
        state.input(kanaKeyID: "あ", direction: .center)
        state.input(kanaKeyID: "あ", direction: .up)
        XCTAssertEqual(state.commit(), "いあう")
    }
    func testKatakanaInputAndDirectModeSwitch() {
        let state = InputState(engine: LocalStubEngine())
        state.setInputMode(.katakana)
        state.input(kanaKeyID: "か", direction: .left)
        XCTAssertEqual(state.commit(), "キ")
        state.setInputMode(.hiragana)
        state.input(kanaKeyID: "か", direction: .left)
        XCTAssertEqual(state.commit(), "き")
    }
    func testNextCandidateDoesNotCommitOrDropRemainingSegments() {
        let state = InputState(engine: LocalStubEngine())
        state.input(fixed: "はしはな")
        XCTAssertEqual(state.requestConversion().segments.first?.selected.value, "橋")
        let next = state.requestConversion()
        XCTAssertEqual(next.segments.first?.selected.value, "箸")
        XCTAssertEqual(next.composition, "はしはな")
        XCTAssertEqual(state.commit(), "箸花")
    }
    func testDeleteCancelsConversionBeforeDeletingReading() {
        let state = InputState(engine: LocalStubEngine())
        state.input(fixed: "きょう")
        state.requestConversion()
        let cancelled = state.deleteBackward()
        XCTAssertFalse(cancelled.isConverting)
        XCTAssertEqual(cancelled.composition, "きょう")
        XCTAssertEqual(state.deleteBackward().composition, "きょ")
    }
    func testFlickOnlyIsDefault() {
        let state = InputState(engine: LocalStubEngine())
        state.input(kanaKeyID: "あ", direction: .center)
        state.input(kanaKeyID: "あ", direction: .center)
        XCTAssertEqual(state.commit(), "ああ")
    }
    func testCancelConversionPreservesReading() {
        let state = InputState(engine: LocalStubEngine())
        state.input(fixed: "きょう")
        state.requestConversion()
        XCTAssertEqual(state.cancelConversion().composition, "きょう")
        XCTAssertEqual(state.commit(), "きょう")
    }
    func testSmallFlickAndDiagonalHysteresis() {
        XCTAssertEqual(FlickGesture.direction(translation: CGPoint(x: 12, y: 0)), .right)
        XCTAssertEqual(FlickGesture.direction(translation: CGPoint(x: 8, y: 0), velocity: CGPoint(x: 400, y: 0)), .right)
        XCTAssertEqual(FlickGesture.direction(translation: CGPoint(x: 2, y: 0), velocity: CGPoint(x: 1000, y: 0)), .center)
        XCTAssertEqual(FlickGesture.direction(translation: CGPoint(x: 12, y: 13), previousDirection: .right), .right)
        XCTAssertEqual(FlickGesture.direction(translation: CGPoint(x: 12, y: 17), previousDirection: .right), .down)
        XCTAssertEqual(FlickGesture.direction(translation: .zero, previousDirection: .right), .center)
    }
    func testCursorDragAccumulatesAndReverses() {
        var drag = CursorDragState()
        XCTAssertEqual(drag.move(by: 6), 0)
        XCTAssertEqual(drag.move(by: 6), 1)
        XCTAssertEqual(drag.move(by: -12), -1)
        XCTAssertEqual(drag.move(by: -20), -2)
    }
}

@MainActor
final class KeyboardPresentationTests: XCTestCase {
    private func keys(_ view: UIView) -> [FlickKeyButton] {
        view.subviews.flatMap { ($0 as? FlickKeyButton).map { [$0] } ?? keys($0) }
    }
    func testAllModesFitSmallScreenAndHaveTallerKeys() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let keyboard = KeyboardView()
        keyboard.translatesAutoresizingMaskIntoConstraints = true
        keyboard.frame = CGRect(x: 0, y: 0, width: 320, height: 290)
        host.view.addSubview(keyboard)
        for mode in InputMode.allCases {
            keyboard.setInputMode(mode)
            host.view.layoutIfNeeded()
            keyboard.layoutIfNeeded()
            for key in keys(keyboard) {
                XCTAssertGreaterThanOrEqual(key.bounds.height, 44)
                XCTAssertGreaterThanOrEqual(key.bounds.width, mode == .hiragana || mode == .katakana ? 44 : 24)
                XCTAssertFalse(key.hasAmbiguousLayout)
            }
        }
    }
    func testModeKeysAndNextCandidateDispatchDistinctActions() throws {
        let keyboard = KeyboardView()
        let delegate = KeyboardDelegateSpy()
        keyboard.actionDelegate = delegate
        let english = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .setInputMode(.alphabet) })
        keyboard.flickKeyButton(english, didActivate: .center)
        XCTAssertEqual(delegate.mode, .alphabet)
        XCTAssertEqual(keyboard.inputMode, .alphabet)
        keyboard.setInputMode(.hiragana)
        let next = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .nextCandidate })
        keyboard.flickKeyButton(next, didActivate: .center)
        XCTAssertEqual(delegate.conversions, 1)
        XCTAssertEqual(delegate.returns, 0)
    }
    func testKeyLabelsFollowComposition() throws {
        let keyboard = KeyboardView()
        let space = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .space })
        let enter = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .returnOrConfirm })
        XCTAssertEqual(space.accessibilityLabel, "空白")
        keyboard.update(with: ConversionResult(composition: "あ"))
        XCTAssertEqual(space.accessibilityLabel, "変換")
        XCTAssertEqual(enter.accessibilityLabel, "確定")
        keyboard.update(with: .empty)
        XCTAssertEqual(enter.accessibilityLabel, "改行")
    }
    func testExpandedCandidatesCanCloseWithoutSelection() {
        let keyboard = KeyboardView()
        keyboard.setCandidateListVisible(true)
        XCTAssertFalse(keyboard.candidateList.isHidden)
        keyboard.candidateList.onClose?()
        XCTAssertTrue(keyboard.candidateList.isHidden)
    }
    func testEnglishShiftCapsLockAndCompleteAlphabet() throws {
        let keyboard = KeyboardView()
        let delegate = KeyboardDelegateSpy()
        keyboard.actionDelegate = delegate
        keyboard.setInputMode(.alphabet)
        let letter = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .input("q") })
        let shift = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .shift })
        keyboard.flickKeyButton(letter, didActivate: .center)
        keyboard.flickKeyButton(shift, didActivate: .center)
        keyboard.flickKeyButton(letter, didActivate: .center)
        keyboard.flickKeyButton(letter, didActivate: .center)
        XCTAssertEqual(delegate.text, ["q", "Q", "q"])
        keyboard.flickKeyButton(shift, didActivate: .center)
        keyboard.flickKeyButton(shift, didActivate: .center)
        keyboard.flickKeyButton(letter, didActivate: .center)
        keyboard.flickKeyButton(letter, didActivate: .center)
        XCTAssertEqual(Array(delegate.text.suffix(2)), ["Q", "Q"])
        let letters = KeyLayout.alphabetLayout().compactMap { key -> String? in
            if case let .input(text) = key.action { return text }; return nil
        }
        XCTAssertEqual(Set(letters), Set("abcdefghijklmnopqrstuvwxyz".map(String.init)))
    }
    func testReturnTraitAndEnglishSuggestionsDoNotCreateComposition() throws {
        let keyboard = KeyboardView()
        keyboard.setInputMode(.alphabet)
        keyboard.returnTitle = "検索"
        keyboard.setEnglishSuggestions(["hello"])
        let enter = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .returnOrConfirm })
        let space = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .space })
        XCTAssertEqual(enter.accessibilityLabel, "検索")
        XCTAssertEqual(space.accessibilityLabel, "space")
    }
    func testCenterTapIsForwardedInFlickOnlyMode() throws {
        let keyboard = KeyboardView()
        let delegate = KeyboardDelegateSpy()
        keyboard.actionDelegate = delegate
        keyboard.flickOnlyEnabled = true
        let key = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .kana(kanaKeyID: "あ") })
        keyboard.flickKeyButton(key, didActivate: .center)
        XCTAssertEqual(delegate.kanaKey, "あ")
        XCTAssertEqual(delegate.direction, .center)
    }
    func testCursorControlAsksControllerBeforeMoving() throws {
        let keyboard = KeyboardView()
        let delegate = KeyboardDelegateSpy()
        keyboard.actionDelegate = delegate
        let space = try XCTUnwrap(keys(keyboard).first { $0.keyDefinition.action == .space })
        XCTAssertTrue(keyboard.flickKeyButtonWillBeginCursorControl(space))
        keyboard.flickKeyButton(space, didMoveCursorBy: -2)
        XCTAssertEqual(delegate.cursorEvents, [0, -2])
    }
}

private final class KeyboardDelegateSpy: KeyboardActionDelegate {
    var text: [String] = []
    var mode: InputMode?
    var conversions = 0
    var returns = 0
    var kanaKey: String?
    var direction: FlickDirection?
    var cursorEvents: [Int] = []
    func keyboardDidInputKey(keyID: String, direction: FlickDirection) { kanaKey = keyID; self.direction = direction }
    func keyboardWillBeginCursorControl() -> Bool { cursorEvents.append(0); return true }
    func keyboardDidInput(kana: String) { text.append(kana) }
    func keyboardDidPressKey(keyID: String, direction: String) {}
    func keyboardDidDeleteBackward() {}
    func keyboardDidToggleDakuten() {}
    func keyboardDidRequestConversion() { conversions += 1 }
    func keyboardDidSelectCandidate(id: String) {}
    func keyboardDidCommit() {}
    func keyboardDidCancelConversion() {}
    func keyboardDidInputSpace() {}
    func keyboardDidTapReturn() { returns += 1 }
    func keyboardDidMoveFocus(by offset: Int) {}
    func keyboardDidMoveCursor(by offset: Int) { cursorEvents.append(offset) }
    func keyboardDidChangeInputMode(_ mode: InputMode) { self.mode = mode }
    func keyboardDidTapNextKeyboard() {}
}
