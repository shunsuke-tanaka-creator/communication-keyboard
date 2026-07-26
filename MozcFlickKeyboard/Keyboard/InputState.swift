// InputState.swift
// MozcFlickKeyboard — 変換状態管理。
//
// かな入力バッファ、変換中/未変換、文節フォーカス、候補選択、確定・取消の状態遷移を管理する。
// JapaneseConversionEngine を保持して駆動するが、エンジンのインスタンスは init で注入する（疎結合）。
//
// KeyboardView からの入力イベントを受け取る delegate プロトコル KeyboardActionDelegate をここで定義する。
// KeyboardView はこの delegate を通じてのみ外部（KeyboardViewController）へ通知し、
// エンジンを直接触らない。InputState が delegate を実装し、エンジンと橋渡しする役割を担える。

import Foundation
import MozcFlickShared // 追加: 共有フレームワークの型を利用

/// KeyboardView が発行する入力イベントを外部へ通知する委譲プロトコル。
/// KeyboardViewController などがこれを実装し、エンジン / UITextDocumentProxy へ反映する。
public protocol KeyboardActionDelegate: AnyObject {
    /// かな1文字以上を未確定バッファへ追加してほしい。
    func keyboardDidInput(kana: String)
    /// 追加: 押された生のキー操作（キーID・フリック方向）を通知（ログ記録用）。
    func keyboardDidPressKey(keyID: String, direction: String)
    /// 未確定末尾を1文字削除（未確定が空なら実テキストを削除）してほしい。
    func keyboardDidDeleteBackward()
    /// 直前文字の濁点/半濁点/小書きトグルを行ってほしい（変換前バッファ操作）。
    func keyboardDidToggleDakuten()
    /// 変換を要求してほしい（スペース or 変換キー）。
    func keyboardDidRequestConversion()
    /// 候補が選択された（id）。確定へ進める。
    func keyboardDidSelectCandidate(id: String)
    /// 現在の状態を確定してほしい。
    func keyboardDidCommit()
    /// 変換を取り消してほしい。
    func keyboardDidCancelConversion()
    /// 空白を入力してほしい（未変換時）。
    func keyboardDidInputSpace()
    /// 改行 / 確定してほしい。
    func keyboardDidTapReturn()
    /// フォーカス文節を移動してほしい（+1 / -1）。
    func keyboardDidMoveFocus(by offset: Int)
    /// カーソルを左右へ移動してほしい（+1 / -1）。
    func keyboardDidMoveCursor(by offset: Int)
    /// 入力モードが変わった（UI 再描画のため通知）。
    func keyboardDidChangeInputMode(_ mode: InputMode)
    /// 次のキーボードへ切替（地球儀）。
    func keyboardDidTapNextKeyboard()
}

/// 変換状態を管理し、エンジンを駆動するクラス。
/// UI（KeyboardView）はこのクラスの currentResult / inputMode を見て描画する。
public final class InputState {

    /// 注入された変換エンジン。
    private let engine: JapaneseConversionEngine

    /// 現在の入力モード。
    public private(set) var inputMode: InputMode = .hiragana

    /// トグル入力（同一キー連打でかな循環）ON/OFF。
    public var toggleInputEnabled = true
    /// フリックのみ入力 ON/OFF（true ならタップ中央入力を無効化）。
    public var flickOnlyEnabled = false

    /// エンジンが返す最新の変換状態。UI はこれを描画する。
    public private(set) var currentResult: ConversionResult = .empty

    /// トグル入力用: 直前に入力したかなキー ID と、その循環インデックス。
    private var lastKanaKeyID: String?
    private var lastCycleIndex = 0

    public init(engine: JapaneseConversionEngine) {
        self.engine = engine
    }

    // MARK: - 状態遷移

    /// かな入力キー押下（フリック方向つき）。トグル入力にも対応。
    /// - Returns: 更新後の ConversionResult。
    @discardableResult
    public func input(kanaKeyID: String, direction: FlickDirection) -> ConversionResult {
        guard let key = KanaTable.key(for: kanaKeyID) else { return currentResult }

        var kana: String
        if direction == .center && toggleInputEnabled && lastKanaKeyID == kanaKeyID && !key.cycle.isEmpty {
            // 同一キー中央タップ連打 → 循環（トグル入力）。直前の1文字を差し替える。
            lastCycleIndex = (lastCycleIndex + 1) % key.cycle.count
            kana = key.cycle[lastCycleIndex]
            engine.deleteBackward() // 直前の仮入力を1文字戻す
        } else {
            kana = key.character(for: direction) ?? key.character(for: .center) ?? ""
            lastKanaKeyID = (direction == .center) ? kanaKeyID : nil
            lastCycleIndex = 0
        }

        // カタカナモードなら入力かなをカタカナへ寄せる。
        if inputMode == .katakana {
            kana = KanaTransform.toKatakana(kana)
        }

        engine.insert(kana)
        currentResult = engine.requestPrediction()
        return currentResult
    }

    /// 固定文字（英字/数字/記号）を入力。
    @discardableResult
    public func input(fixed text: String) -> ConversionResult {
        lastKanaKeyID = nil
        engine.insert(text)
        currentResult = engine.requestPrediction()
        return currentResult
    }

    /// 削除。
    @discardableResult
    public func deleteBackward() -> ConversionResult {
        lastKanaKeyID = nil
        engine.deleteBackward()
        currentResult = engine.requestPrediction()
        return currentResult
    }

    /// 直前文字の濁点/半濁点/小書きトグル。
    /// エンジンの composition 末尾を取り、循環変換して差し替える。
    @discardableResult
    public func toggleDakuten() -> ConversionResult {
        lastKanaKeyID = nil
        guard let last = currentResult.composition.last else { return currentResult }
        let toggled = KanaTransform.cycled(String(last))
        if toggled != String(last) {
            engine.deleteBackward()
            engine.insert(toggled)
            currentResult = engine.requestPrediction()
        }
        return currentResult
    }

    /// 変換要求。
    @discardableResult
    public func requestConversion() -> ConversionResult {
        lastKanaKeyID = nil
        currentResult = engine.requestConversion()
        return currentResult
    }

    /// 候補選択。
    @discardableResult
    public func selectCandidate(id: String) -> ConversionResult {
        lastKanaKeyID = nil
        currentResult = engine.selectCandidate(id: id)
        return currentResult
    }

    /// フォーカス移動。
    @discardableResult
    public func moveFocus(by offset: Int) -> ConversionResult {
        currentResult = engine.moveFocus(by: offset)
        return currentResult
    }

    /// 確定。確定文字列を返し、状態をリセット。
    public func commit() -> String {
        lastKanaKeyID = nil
        let text = engine.commit()
        currentResult = .empty
        return text
    }

    /// 変換取消。
    @discardableResult
    public func cancelConversion() -> ConversionResult {
        lastKanaKeyID = nil
        currentResult = engine.cancelConversion()
        return currentResult
    }

    /// 入力モード切替（循環）。
    @discardableResult
    public func switchInputMode() -> InputMode {
        inputMode = inputMode.next
        lastKanaKeyID = nil
        return inputMode
    }

    /// 全リセット。
    public func reset() {
        engine.reset()
        currentResult = .empty
        lastKanaKeyID = nil
        lastCycleIndex = 0
    }
}
