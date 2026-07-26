// KeyboardViewController.swift
// MozcFlickKeyboard — Custom Keyboard Extension の基盤 UIInputViewController。
//
// 責務:
//  - 12キーフリック UI（KeyboardView）を container view に差し込む。
//  - KeyboardView から届く入力イベント（KeyboardActionDelegate 経由）を InputState / 変換エンジンで処理し、
//    確定文字列を UITextDocumentProxy へ反映する。
//  - 地球儀キーによるキーボード切替、returnKeyType / keyboardType の考慮、Full Access 不要な範囲での動作。
//
// 未確定文字列の扱い:
//  - UITextDocumentProxy には marked text 相当の API が無いため、確定前の文字列（composition）は insertText せず
//    InputState / エンジン内部に保持し、確定時にまとめて insertText する。削除は deleteBackward を用いる。
//    詳細は docs/ios-keyboard-limitations.md 参照。

import UIKit
import MozcFlickShared // 追加: 共有フレームワークの型（InputState/エンジン/AppConfig 等）を利用

/// App Group の UserDefaults に保存する設定値のキーを集約する。
/// ホストアプリ側の SettingsViewController と同じ文字列を用いること。
enum SettingsKeys {
    static let toggleInputEnabled = "toggleInputEnabled"
    static let flickOnlyEnabled = "flickOnlyEnabled"
    static let learningEnabled = "learningEnabled"
    static let privateModeEnabled = "privateModeEnabled"
    static let schedules = "schedules"         // 追加: 予定の配列。各要素は "HH:mm\t文言"。
}

final class KeyboardViewController: UIInputViewController {

    // MARK: - 状態

    /// 変換状態管理。エンジンを注入して駆動する。
    /// 既定は Mozc 未リンクでも動作する LocalStubEngine。MOZC_AVAILABLE 時は MozcConversionEngine を使う。
    private lazy var inputState: InputState = {
        let engine: JapaneseConversionEngine
        #if MOZC_AVAILABLE
        engine = MozcConversionEngine()
        NSLog("[MFK] engine = MozcConversionEngine (MOZC_AVAILABLE=ON) isMozcAvailable=\((engine as? MozcConversionEngine)?.isMozcAvailable ?? false)") // 追加: エンジン種別のデバッグ
        #else
        engine = LocalStubEngine()
        NSLog("[MFK] engine = LocalStubEngine (MOZC_AVAILABLE=OFF)") // 追加: エンジン種別のデバッグ
        #endif
        return InputState(engine: engine)
    }()

    /// 12キー UI 本体。
    private let keyboardView = KeyboardView()

    /// App Group 共有の UserDefaults。設定値の参照に使う。
    private let sharedDefaults = UserDefaults(suiteName: AppConfig.appGroupID)

    /// 追加: いま入力欄へインライン挿入している未確定文字列（擬似 marked text）。
    /// UITextDocumentProxy に marked text API が無いため、未確定よみを実挿入して Simeji 風に見せる。
    /// composition が変わるたびにこの値との差分を取り、古い分を削除して新しい分を入れ直す。
    private var pendingComposition = ""

    /// 追加: 入力イベントをセッション単位で記録するロガー。
    private let sessionLogger = SessionLogger()

    /// 追加: このセッションの変換要求回数（メタ情報）。
    private var conversionCount = 0

    // MARK: - ライフサイクル

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("[MFK] viewDidLoad KeyboardViewController loaded") // 追加: 拡張起動確認のデバッグ
        print("[MFK-print] viewDidLoad KeyboardViewController loaded") // 追加: NSLogが出ない場合の確認用 print
        view.backgroundColor = .systemBackground // ダークモード追従
        setupKeyboardView()
        applySettings()
        enableLoggingIfAllowed() // 追加: viewWillAppear が呼ばれない場合に備え、ここでも記録を有効化。
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }

    // 変更: キーボードを開いたときに「次の予定」を1回だけ表示する（時刻トリガーはやめた）。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateInfoBar()
        // 追加: セッション記録を有効化（プライベートモード ON のときは記録しない）。
        let started = enableLoggingIfAllowed()
        if started {
            // セッション開始時のメタ情報（入力欄の種別など取得可能なものを記録）。
            sessionLogger.log(type: "meta", data: [
                "keyboardType": "\(textDocumentProxy.keyboardType?.rawValue ?? -1)",
                "returnKeyType": "\(textDocumentProxy.returnKeyType?.rawValue ?? -1)",
                "hasFullAccess": "\(hasFullAccess)",
                "inputMode": "\(inputState.inputMode)",
            ])
        }
        NSLog("[MFK] viewWillAppear session started=\(started)") // 追加: セッション開始のデバッグ
    }

    /// 追加: プライベートモード OFF のときだけ記録を有効化する共通ヘルパ。
    /// - Returns: 有効化した(=記録する)なら true。
    @discardableResult
    private func enableLoggingIfAllowed() -> Bool {
        let isPrivate = sharedDefaults?.bool(forKey: SettingsKeys.privateModeEnabled) ?? false
        guard !isPrivate else { return false }
        conversionCount = 0
        sessionLogger.enable()
        return true
    }

    /// 追加: キーボードが閉じたらセッションを終了しファイルを閉じる。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionLogger.log(type: "meta", data: ["conversionCount": "\(conversionCount)"])
        sessionLogger.stop()
        NSLog("[MFK] viewDidDisappear session stopped conversionCount=\(conversionCount)") // 追加: セッション終了のデバッグ
    }

    /// 変更: App Group の予定配列から「現在時刻以降で最も近い次の予定」を1つバーに表示する（表示のみ）。
    private func updateInfoBar() {
        let list = sharedDefaults?.stringArray(forKey: SettingsKeys.schedules) ?? []
        let now = Date()
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        // 各要素 "HH:mm\t文言" を (分, 時刻文字列, 文言) に変換。
        var next: (minutes: Int, time: String, text: String)?
        for item in list {
            let parts = item.components(separatedBy: "\t")
            guard let time = parts.first, !time.isEmpty else { continue }
            let text = parts.count > 1 ? parts[1] : ""
            let hm = time.split(separator: ":")
            guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { continue }
            let minutes = h * 60 + m
            guard minutes >= nowMinutes else { continue } // 過去はスキップ
            if next == nil || minutes < next!.minutes {
                next = (minutes, time, text)
            }
        }

        if let n = next {
            keyboardView.setInfoText("次の予定 \(n.time) \(n.text)")
        } else {
            keyboardView.setInfoText("")
        }
        NSLog("[MFK] updateInfoBar next=\(String(describing: next))") // 追加: 次の予定のデバッグ
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // keyboardType / returnKeyType に応じて UI を切り替えられるフック。
        // 数字・電話・URL 入力欄などでは変換を無効化するのが自然（今後の拡張点）。
    }

    // MARK: - UI 構築

    private func setupKeyboardView() {
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.actionDelegate = self
        view.addSubview(keyboardView)

        let guide = view.safeAreaLayoutGuide // SafeArea 考慮
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: guide.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 216),
        ])
    }

    /// App Group の設定を UI / 状態へ反映する。
    private func applySettings() {
        let d = sharedDefaults
        // 既定値: トグル ON / フリックのみ OFF / 学習 ON。
        let toggle = d?.object(forKey: SettingsKeys.toggleInputEnabled) as? Bool ?? true
        let flickOnly = d?.bool(forKey: SettingsKeys.flickOnlyEnabled) ?? false
        inputState.toggleInputEnabled = toggle
        inputState.flickOnlyEnabled = flickOnly
        // 追加: Full Access 無しの Keyboard Extension は触覚フィードバックがサンドボックスで
        // 使えず AVAudioSession/CHHapticEngine のエラーログを吐き続ける。hasFullAccess で抑制する。
        let haptics = hasFullAccess
        NSLog("[MFK] applySettings hasFullAccess=\(hasFullAccess) haptics=\(haptics)") // 追加: Full Access 判定のデバッグ
        keyboardView.applySettings(toggleInput: toggle, flickOnly: flickOnly, haptics: haptics)
    }

    // MARK: - 反映ヘルパ

    /// 追加: 未確定文字列を入力欄へインライン反映する（擬似 marked text）。
    /// 変換前は composition(よみ)、変換中は選択中の文節列(変換後文字列)を表示対象にする。
    /// 現在挿入済みの pendingComposition と新しい表示文字列の共通プレフィックスを残し、
    /// 差分だけ削除・挿入して Simeji 風のインライン未確定表示を実現する。
    /// UI（候補バー等）の update も併せて行う。
    private func syncInline(_ result: ConversionResult) {
        // 変更: 変換中は選択中の文節列を結合した変換後文字列をインライン表示する。
        let new: String
        if result.isConverting && !result.segments.isEmpty {
            new = result.segments.map { $0.selected.value }.joined()
        } else {
            new = result.composition
        }
        let old = pendingComposition
        if new != old {
            // 共通プレフィックス長を求める。
            var common = 0
            let newChars = Array(new)
            let oldChars = Array(old)
            while common < newChars.count && common < oldChars.count && newChars[common] == oldChars[common] {
                common += 1
            }
            // 共通部分より後ろの古い分を削除。
            for _ in 0..<(oldChars.count - common) {
                textDocumentProxy.deleteBackward()
            }
            // 新しい分を挿入。
            let inserted = String(newChars[common...])
            if !inserted.isEmpty {
                textDocumentProxy.insertText(inserted)
            }
            pendingComposition = new
            NSLog("[MFK] syncInline old='\(old)' -> new='\(new)'") // 追加: インライン同期のデバッグ
        }
        keyboardView.update(with: result)
    }

    /// 確定文字列を proxy へ送り、UI を初期状態へ戻す。
    private func commitAndInsert() {
        // インライン挿入済みの未確定分をいったん削除してから確定文字列を入れ直す。
        let deleteCount = pendingComposition.count
        for _ in 0..<deleteCount {
            textDocumentProxy.deleteBackward()
        }
        NSLog("[MFK] commitAndInsert pending='\(pendingComposition)' deleted=\(deleteCount)") // 追加: 未確定削除のデバッグ
        pendingComposition = ""
        let text = inputState.commit()
        NSLog("[MFK] commitAndInsert text='\(text)'") // 追加: 確定文字列のデバッグ
        sessionLogger.log(type: "commit", data: ["text": text]) // 追加: 確定文字列を記録
        if !text.isEmpty {
            textDocumentProxy.insertText(text)
        }
        logContext() // 追加: 確定後のカーソル付近文脈を記録
        keyboardView.update(with: .empty)
    }

    /// 追加: カーソル付近の文脈（前後テキスト・選択テキスト）をログへ記録するヘルパ。
    private func logContext() {
        sessionLogger.log(type: "context", data: [
            "before": textDocumentProxy.documentContextBeforeInput ?? "",
            "after": textDocumentProxy.documentContextAfterInput ?? "",
            "selected": textDocumentProxy.selectedText ?? "",
        ])
    }
}

// MARK: - KeyboardActionDelegate（KeyboardView からの入力を InputState / proxy へ反映）

extension KeyboardViewController: KeyboardActionDelegate {

    func keyboardDidInput(kana: String) {
        let result = inputState.input(fixed: kana)
        NSLog("[MFK] keyboardDidInput kana='\(kana)' -> composition='\(result.composition)' candidates=\(result.candidates.count)") // 追加: 入力とcompositionのデバッグ
        // 追加: 入力かなと未確定よみ・候補数を記録。
        sessionLogger.log(type: "kana", data: [
            "kana": kana,
            "composition": result.composition,
            "candidates": "\(result.candidates.count)",
        ])
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    // 追加: 押された生のキー操作（キーID・フリック方向）を記録する。
    func keyboardDidPressKey(keyID: String, direction: String) {
        sessionLogger.log(type: "key", data: ["keyID": keyID, "direction": direction])
    }

    func keyboardDidDeleteBackward() {
        if inputState.currentResult.composition.isEmpty {
            // 未確定が無ければ実テキストを削除。
            NSLog("[MFK] keyboardDidDeleteBackward -> proxy.deleteBackward (composition empty)") // 追加: 削除経路のデバッグ
            sessionLogger.log(type: "delete", data: ["target": "text"]) // 追加: 実テキスト削除を記録
            textDocumentProxy.deleteBackward()
            logContext() // 追加: 実テキスト削除後のカーソル付近文脈を記録
        } else {
            let result = inputState.deleteBackward()
            NSLog("[MFK] keyboardDidDeleteBackward -> composition='\(result.composition)'") // 追加: 削除後compositionのデバッグ
            sessionLogger.log(type: "delete", data: ["target": "composition", "composition": result.composition]) // 追加: 未確定削除を記録
            syncInline(result) // 変更: 未確定を入力欄へインライン反映
        }
    }

    func keyboardDidToggleDakuten() {
        let result = inputState.toggleDakuten()
        sessionLogger.log(type: "dakuten", data: ["composition": result.composition]) // 追加: 濁点トグルを記録
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidRequestConversion() {
        let result = inputState.requestConversion()
        conversionCount += 1 // 追加: 変換回数カウント
        // 追加: 変換要求とその結果（候補一覧・文節）を記録。
        sessionLogger.log(type: "conversion", data: [
            "composition": result.composition,
            "candidates": result.candidates.map { $0.value }.joined(separator: "|"),
            "segments": result.segments.map { $0.reading }.joined(separator: "|"),
            "count": "\(conversionCount)",
        ])
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidSelectCandidate(id: String) {
        // 候補選択 → その状態で確定して proxy へ挿入。
        let result = inputState.selectCandidate(id: id)
        // 追加: 選択された候補を記録。
        sessionLogger.log(type: "candidate", data: [
            "id": id,
            "selected": result.segments.map { $0.selected.value }.joined(),
        ])
        commitAndInsert()
    }

    func keyboardDidCommit() {
        commitAndInsert()
    }

    func keyboardDidCancelConversion() {
        let result = inputState.cancelConversion()
        sessionLogger.log(type: "cancel", data: ["composition": result.composition]) // 追加: 変換取消を記録
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidInputSpace() {
        if inputState.currentResult.composition.isEmpty {
            // 未確定が無ければ空白を直接入力。
            sessionLogger.log(type: "space", data: [:]) // 追加: 空白入力を記録
            textDocumentProxy.insertText(" ")
            logContext() // 追加: 空白入力後のカーソル付近文脈を記録
        } else {
            // 未確定があれば変換を要求（一般的な IME の挙動）。
            let result = inputState.requestConversion()
            conversionCount += 1 // 追加: 変換回数カウント
            sessionLogger.log(type: "conversion", data: [ // 追加: スペース経由の変換も記録
                "composition": result.composition,
                "candidates": result.candidates.map { $0.value }.joined(separator: "|"),
                "count": "\(conversionCount)",
            ])
            syncInline(result) // 変更: 未確定を入力欄へインライン反映
        }
    }

    func keyboardDidTapReturn() {
        if inputState.currentResult.composition.isEmpty {
            sessionLogger.log(type: "return", data: [:]) // 追加: 改行を記録
            textDocumentProxy.insertText("\n")
            logContext() // 追加: 改行入力後のカーソル付近文脈を記録
        } else {
            // 未確定があれば確定（改行はしない、一般的な IME の確定挙動）。
            commitAndInsert()
        }
    }

    func keyboardDidMoveFocus(by offset: Int) {
        let result = inputState.moveFocus(by: offset)
        sessionLogger.log(type: "moveFocus", data: ["offset": "\(offset)", "focused": "\(result.focusedSegment)"]) // 追加: 文節フォーカス移動を記録
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidMoveCursor(by offset: Int) {
        // 未確定が無いときのみ実カーソルを移動。
        guard inputState.currentResult.composition.isEmpty else { return }
        sessionLogger.log(type: "moveCursor", data: ["offset": "\(offset)"]) // 追加: カーソル移動を記録
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func keyboardDidChangeInputMode(_ mode: InputMode) {
        // KeyboardView 側で既にキー再構築済み。状態側の追随は現状不要。
        sessionLogger.log(type: "inputMode", data: ["mode": "\(mode)"]) // 追加: 入力モード変更を記録
    }

    func keyboardDidTapNextKeyboard() {
        sessionLogger.log(type: "nextKeyboard", data: [:]) // 追加: 地球儀キーを記録
        advanceToNextInputMode()
    }
}
