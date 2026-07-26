// KeyboardView.swift
// MozcFlickKeyboard — 12キー全体を配置するキーボード本体 View。
//
// 責務:
//  - KeyLayout のデータに基づき FlickKeyButton を AutoLayout（UIStackView グリッド）で配置する。
//  - 入力モード（ひらがな/カタカナ/英字/数字/記号）切替でレイアウトを再構築する。
//  - トグル入力 ON/OFF・フリックのみ ON/OFF 設定を反映する。
//  - キー押下を解釈し、KeyboardActionDelegate へ通知する（エンジンは直接持たない）。
//  - ConversionResult / 候補を受けて上部の CandidateBarView を再描画する。
//
// 画面サイズ対応:
//  - UIStackView の等分割で iPhone SE〜大型まで破綻しない。SafeArea は KeyboardViewController 側で考慮済み。

import UIKit
import MozcFlickShared // 追加: 共有フレームワークの型を利用

final class KeyboardView: UIView {

    /// 入力イベントの通知先。KeyboardViewController が実装する。
    weak var actionDelegate: KeyboardActionDelegate?

    /// トグル入力 ON/OFF。
    var toggleInputEnabled = true
    /// フリックのみ入力 ON/OFF（true なら中央タップ入力を無効化）。
    var flickOnlyEnabled = false
    /// 触覚フィードバック ON/OFF。
    var hapticsEnabled = true {
        didSet { applyHapticsSetting() }
    }

    /// 現在の入力モード。
    private(set) var inputMode: InputMode = .hiragana

    // MARK: - サブビュー

    /// 上部候補バー。
    let candidateBar = CandidateBarView()

    /// 展開時の候補一覧（既定は非表示）。
    let candidateList = CandidateListView()

    /// 追加: 最下層に表示する情報バー（予定・タイマー文言など）。入力欄には書かず表示のみ。
    let infoBar: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.text = ""
        return l
    }()

    /// キー全体を縦に積む親スタック。
    private let rootStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.distribution = .fillEqually
        s.spacing = 6
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// 現在配置されている FlickKeyButton 群。
    private var keyButtons: [FlickKeyButton] = []

    // MARK: - init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { return nil }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        candidateBar.translatesAutoresizingMaskIntoConstraints = false
        candidateList.translatesAutoresizingMaskIntoConstraints = false
        candidateList.isHidden = true

        addSubview(candidateBar)
        addSubview(rootStack)
        addSubview(infoBar) // 追加: 最下層の情報バー
        // 追加: 候補一覧は展開時にキー領域を覆うため最前面に置く（rootStack より後に追加）。
        addSubview(candidateList)

        candidateBar.onSelect = { [weak self] candidate in
            self?.actionDelegate?.keyboardDidSelectCandidate(id: candidate.id)
        }
        candidateBar.onExpand = { [weak self] in
            self?.setCandidateListVisible(true)
        }
        candidateList.onSelect = { [weak self] candidate in
            self?.setCandidateListVisible(false)
            self?.actionDelegate?.keyboardDidSelectCandidate(id: candidate.id)
        }

        NSLayoutConstraint.activate([
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: 44),

            candidateList.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            candidateList.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateList.trailingAnchor.constraint(equalTo: trailingAnchor),
            // 追加: 展開時にキー領域全体を覆うよう下端を親まで伸ばす（これが無いと高さが確保されず見えない）。
            candidateList.bottomAnchor.constraint(equalTo: bottomAnchor),

            rootStack.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 6),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            // 変更: rootStack の下端を親からではなく infoBar の上に付け替える。
            rootStack.bottomAnchor.constraint(equalTo: infoBar.topAnchor, constant: -3),

            // 追加: 情報バーを最下層に固定（高さ 20pt）。
            infoBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            infoBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            infoBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            infoBar.heightAnchor.constraint(equalToConstant: 20),
        ])

        rebuildKeys()
    }

    // MARK: - 公開 API（状態更新）

    /// エンジンからの ConversionResult を受けて候補バー/一覧を再描画する。
    func update(with result: ConversionResult) {
        NSLog("[MFK] KeyboardView.update composition='\(result.composition)' candidates=\(result.candidates.count) converting=\(result.isConverting)") // 追加: 表示更新のデバッグ
        // 追加: 未確定よみ(composition)がある間は、打った文字そのものを候補バー先頭に表示する。
        // これが無いと辞書にヒットしない読みで候補が0件になり画面に何も出ない。選択で composition を確定する。
        var barCandidates = result.candidates
        if !result.composition.isEmpty && !result.isConverting {
            let compo = ConversionCandidate(id: "compo", value: result.composition, reading: result.composition)
            if barCandidates.first?.value != result.composition {
                barCandidates.insert(compo, at: 0)
            }
        }
        candidateBar.setCandidates(barCandidates, focused: nil)
        candidateList.setCandidates(barCandidates)
        if barCandidates.isEmpty {
            setCandidateListVisible(false)
        }
    }

    /// 入力モードを設定してキーを再構築する。
    func setInputMode(_ mode: InputMode) {
        guard mode != inputMode else { return }
        inputMode = mode
        rebuildKeys()
    }

    /// 設定（トグル/フリックのみ/触覚）をまとめて反映する。
    func applySettings(toggleInput: Bool, flickOnly: Bool, haptics: Bool) {
        toggleInputEnabled = toggleInput
        flickOnlyEnabled = flickOnly
        hapticsEnabled = haptics
    }

    /// 候補一覧の表示切替。
    func setCandidateListVisible(_ visible: Bool) {
        candidateList.isHidden = !visible
    }

    /// 追加: 最下層の情報バーに文言を設定する（表示のみ）。
    func setInfoText(_ text: String) {
        infoBar.text = text
    }

    // MARK: - キー構築（データ駆動）

    private func rebuildKeys() {
        for v in rootStack.arrangedSubviews {
            rootStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        keyButtons.removeAll()

        let layout = KeyLayout.layout(for: inputMode)
        // 行ごとに横スタックを作る。
        for row in 0..<KeyLayout.rowCount {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 6

            let rowKeys = layout.filter { $0.row == row }.sorted { $0.column < $1.column }
            for def in rowKeys {
                let button = FlickKeyButton(keyDefinition: def)
                button.delegate = self
                button.hapticsEnabled = hapticsEnabled
                if case .backspace = def.action { button.isRepeatable = true }
                keyButtons.append(button)
                rowStack.addArrangedSubview(button)
            }
            rootStack.addArrangedSubview(rowStack)
        }
    }

    private func applyHapticsSetting() {
        for b in keyButtons { b.hapticsEnabled = hapticsEnabled }
        // 追加: 候補バー/一覧の選択フィードバックにも伝播（Full Access 無しのエラーログ抑制）。
        candidateBar.hapticsEnabled = hapticsEnabled
        candidateList.hapticsEnabled = hapticsEnabled
    }

    // MARK: - アクション解釈

    /// キー定義 + フリック方向を delegate 通知へ変換する。
    private func handle(_ def: KeyDefinition, direction: FlickDirection) {
        NSLog("[MFK] handle action=\(def.action) dir=\(direction)") // 追加: キー押下→アクション解釈のデバッグ
        switch def.action {
        case let .kana(id):
            // フリックのみモードで中央タップは無視。
            if flickOnlyEnabled && direction == .center { return }
            emitKana(kanaKeyID: id, direction: direction)

        case let .input(text):
            actionDelegate?.keyboardDidInput(kana: text)

        case .toggleDakuten:
            actionDelegate?.keyboardDidToggleDakuten()

        case .backspace:
            actionDelegate?.keyboardDidDeleteBackward()

        case .space:
            actionDelegate?.keyboardDidInputSpace()

        case .returnOrConfirm:
            actionDelegate?.keyboardDidTapReturn()

        case .nextKeyboard:
            actionDelegate?.keyboardDidTapNextKeyboard()

        case .switchInputMode:
            let newMode = inputMode.next
            setInputMode(newMode)
            actionDelegate?.keyboardDidChangeInputMode(newMode)

        case .cursorLeft:
            actionDelegate?.keyboardDidMoveCursor(by: -1)

        case .cursorRight:
            actionDelegate?.keyboardDidMoveCursor(by: 1)
        }
    }

    /// かな入力を方向から文字へ解決し delegate へ通知する。
    /// トグル入力は InputState 側で行うため、ここでは方向つきの「かなキーID + 方向」を解決した文字を渡す。
    private func emitKana(kanaKeyID: String, direction: FlickDirection) {
        guard let key = KanaTable.key(for: kanaKeyID) else { return }
        var kana = key.character(for: direction) ?? key.character(for: .center) ?? ""
        if kana.isEmpty { return }
        // カタカナモードは表示・入力ともカタカナへ寄せる。
        if inputMode == .katakana {
            kana = KanaTransform.toKatakana(kana)
        }
        NSLog("[MFK] emitKana id='\(kanaKeyID)' dir=\(direction) -> kana='\(kana)'") // 追加: かな解決結果のデバッグ
        actionDelegate?.keyboardDidPressKey(keyID: kanaKeyID, direction: "\(direction)") // 追加: 生キー操作を通知（ログ用）
        actionDelegate?.keyboardDidInput(kana: kana)
    }
}

// MARK: - FlickKeyButtonDelegate

extension KeyboardView: FlickKeyButtonDelegate {

    func flickKeyButton(_ button: FlickKeyButton, didActivate direction: FlickDirection) {
        handle(button.keyDefinition, direction: direction)
    }

    func flickKeyButtonDidRepeat(_ button: FlickKeyButton) {
        // 現状はバックスペースのみリピート対象。
        if case .backspace = button.keyDefinition.action {
            actionDelegate?.keyboardDidDeleteBackward()
        }
    }
}
