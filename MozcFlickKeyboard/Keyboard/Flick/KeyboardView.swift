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

    /// 追加: 候補バーの上に置く「お天気分」質問／手動イベントバナー。既定は高さ0 + 非表示。
    let questionBanner = NarrativeQuestionBanner()

    /// 追加: バナーの高さ制約。質問なし=0。フル画面時は無効化して bannerFullScreenConstraint を使う。
    private var bannerHeightConstraint: NSLayoutConstraint?

    /// 追加: フル画面時にバナー下端を infoBar の上まで伸ばす制約。質問表示中のみ有効化する。
    private var bannerFullScreenConstraint: NSLayoutConstraint?

    /// 追加: フル画面時に追加で確保する高さ（pt）。選択肢を大きく並べるため通常より背を高くする。
    static let bannerVisibleHeight: CGFloat = 60

    /// 追加: キーボード全体に必要な高さが変わったときに通知する。KeyboardViewController が高さ制約へ反映する。
    /// バナー非表示時は 0、表示時は bannerVisibleHeight を渡す。
    var onRequiredExtraHeightChanged: ((CGFloat) -> Void)?

    /// 上部候補バー。
    let candidateBar = CandidateBarView()

    /// 展開時の候補一覧（既定は非表示）。
    let candidateList = CandidateListView()

    /// 追加: 情報バー内の文言ラベル（予定・安否確認の質問文など）。
    private let infoLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.text = ""
        return l
    }()

    /// 追加: 安否確認のチェックボタン。既定は非表示。押下で onCheck を呼ぶ。
    private let checkButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("チェック", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.isHidden = true
        return b
    }()

    /// 追加: 手動イベント記録ボタン。押下で onRecordTap を呼び、バナーに手動イベント4ボタンを展開する。
    private let recordButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("記録", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }()

    /// 追加: 最下層に表示する情報バー（文言ラベル + 記録ボタン + チェックボタン）。入力欄には書かず表示のみ。
    private lazy var infoBar: UIStackView = {
        let s = UIStackView(arrangedSubviews: [infoLabel, recordButton, checkButton])
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    /// 追加: チェックボタン押下時のコールバック。KeyboardViewController が設定する。
    var onCheck: (() -> Void)?

    /// 追加:「記録」ボタン押下時のコールバック。KeyboardViewController が手動イベントバナーを開く。
    var onRecordTap: (() -> Void)?

    // 追加: バナーのコールバックをそのまま controller へ中継する透過プロパティ群。
    //       KeyboardView は proxy を持たないため、これらは決して入力欄へ繋がらない。
    /// 追加: 選択肢タップの中継。
    var onQuestionOption: ((QuestionOption) -> Void)?
    /// 追加:「あとで」の中継。
    var onQuestionSnooze: (() -> Void)?
    /// 追加:「自由入力」開始の中継。
    var onFreeTextStart: (() -> Void)?
    /// 追加: 自由記述「決定」の中継。
    var onFreeTextCommit: (() -> Void)?
    /// 追加: 自由記述「キャンセル」の中継。
    var onFreeTextCancel: (() -> Void)?
    /// 追加: 手動イベント選択の中継。
    var onManualEvent: ((ManualEvent) -> Void)?

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

        questionBanner.translatesAutoresizingMaskIntoConstraints = false // 追加: バナーの AutoLayout 管理
        questionBanner.isHidden = true // 追加: 既定は非表示（質問なし）

        addSubview(questionBanner) // 追加: 候補バーの上へバナーを差し込む
        addSubview(candidateBar)
        addSubview(rootStack)
        addSubview(infoBar) // 追加: 最下層の情報バー
        // 追加: 候補一覧は展開時にキー領域を覆うため最前面に置く（rootStack より後に追加）。
        addSubview(candidateList)

        checkButton.addTarget(self, action: #selector(checkButtonTapped), for: .touchUpInside) // 追加
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside) // 追加:「記録」ボタン配線

        // 追加: バナーのコールバックを透過プロパティへ中継する（proxy へは一切繋がない）。
        questionBanner.onSelectOption = { [weak self] option in self?.onQuestionOption?(option) }
        questionBanner.onSnooze = { [weak self] in self?.onQuestionSnooze?() }
        questionBanner.onFreeTextStart = { [weak self] in self?.onFreeTextStart?() }
        questionBanner.onFreeTextCommit = { [weak self] in self?.onFreeTextCommit?() }
        questionBanner.onFreeTextCancel = { [weak self] in self?.onFreeTextCancel?() }
        questionBanner.onManualEvent = { [weak self] event in self?.onManualEvent?(event) }

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

        // 追加: バナー高さ制約を保持（既定0 = 非表示）。フル画面時は無効化する。
        let bh = questionBanner.heightAnchor.constraint(equalToConstant: 0)
        bannerHeightConstraint = bh

        // 追加: フル画面制約（バナー下端を infoBar の上まで伸ばす）。質問表示中のみ有効化するので既定は無効。
        let bf = questionBanner.bottomAnchor.constraint(equalTo: infoBar.topAnchor, constant: -3)
        bannerFullScreenConstraint = bf
        bf.isActive = false

        NSLayoutConstraint.activate([
            // 追加: バナーを最上部にピン留め（候補バーの上）。
            questionBanner.topAnchor.constraint(equalTo: topAnchor),
            questionBanner.leadingAnchor.constraint(equalTo: leadingAnchor),
            questionBanner.trailingAnchor.constraint(equalTo: trailingAnchor),
            bh, // 追加: 可変高さ（0/64）

            // 変更: 候補バーの上端を topAnchor からバナーの下端へ付け替える。
            candidateBar.topAnchor.constraint(equalTo: questionBanner.bottomAnchor),
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

            // 追加: 情報バーを最下層に固定（高さ 36pt。チェックボタンを収めるため拡大）。
            infoBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            infoBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            infoBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            infoBar.heightAnchor.constraint(equalToConstant: 36),
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
        infoLabel.text = text
    }

    /// 追加: 安否確認のチェック表示にする（質問文 + チェックボタン表示）。
    func setCheckPrompt(_ text: String) {
        infoLabel.text = text
        infoLabel.textColor = .label
        checkButton.isHidden = false
    }

    /// 追加: 安否確認のチェック表示を解除する（通常の情報表示へ戻す）。
    func clearCheckPrompt() {
        infoLabel.textColor = .secondaryLabel
        checkButton.isHidden = true
    }

    /// 追加: チェックボタン押下。
    @objc private func checkButtonTapped() {
        onCheck?()
    }

    /// 追加:「記録」ボタン押下。手動イベントバナーを開く指示を controller へ送る。
    @objc private func recordButtonTapped() {
        onRecordTap?()
    }

    // MARK: - 公開 API（お天気分バナー）

    /// 変更: 質問をバナーに表示する。フル画面モードでキーボード全体を占有する（キー・候補バーを隠す）。
    func showQuestion(_ pending: PendingQuestion) {
        questionBanner.showQuestion(pending) // 追加: 内容を構築
        setNarrativeFullScreen(true) // 追加: キー領域・候補バーを隠してバナーが全面を使う
    }

    /// 変更: バナーを閉じる（フル画面解除 + 内容消去）。通常のキーボードへ戻る。
    func hideQuestion() {
        setNarrativeFullScreen(false) // 追加: 通常キーボード表示へ戻す
        questionBanner.clear() // 追加: 内容消去
    }

    /// 変更: 手動イベント4ボタンをバナーに表示する（infoBar「記録」から）。フル画面で表示。
    func showManualEventPicker() {
        questionBanner.showManualEvents() // 追加: 手動イベントボタン構築
        setNarrativeFullScreen(true) // 追加: フル画面で大きなボタンを見せる
    }

    /// 追加: 「お天気分」フル画面モードの ON/OFF。
    /// ON のとき、バナーをキーボード全体（候補バー〜キー領域〜infoBar の上まで）に広げ、
    /// 候補バー・キー領域・候補一覧を隠す。OFF で元の通常キーボードへ戻す。
    private func setNarrativeFullScreen(_ on: Bool) {
        questionBanner.isHidden = !on // 追加: バナーの表示切替
        candidateBar.isHidden = on // 追加: 質問中は候補バーを隠す
        rootStack.isHidden = on // 追加: 質問中はキー領域を隠す
        if on { setCandidateListVisible(false) } // 追加: 候補一覧が開いていたら閉じる

        // 追加: 制約を入れ替える。ON はバナー下端を infoBar の上まで伸ばして全面占有、OFF は高さ0に戻す。
        bannerHeightConstraint?.isActive = !on // 追加: OFF のときだけ高さ0制約を使う
        bannerFullScreenConstraint?.isActive = on // 追加: ON のときだけ下端まで伸ばす
        onRequiredExtraHeightChanged?(on ? Self.bannerVisibleHeight : 0) // 追加: フル画面時はキーボード全体を高くして選択肢を見せる
        NSLog("[MFK-Narrative] fullScreen=\(on)") // 追加: 表示モードのデバッグ
    }

    /// 追加: 研究入力モードの下書き文字列をバナーへ反映する。
    func setResearchDraft(_ text: String) {
        questionBanner.updateFreeTextDraft(text)
    }

    /// 変更: バナーを自由記述 UI に切り替える／戻す。
    /// 自由記述中はフリック入力でキーを打つ必要があるため、フル画面を解除してキー領域を表示する
    /// （バナーは上部の帯に戻り、下書きと決定/キャンセルだけを見せる）。
    /// 自由記述をやめて選択肢へ戻るときは、再びフル画面にして大きな選択肢を見せる。
    func setResearchFreeTextMode(_ on: Bool) {
        questionBanner.setFreeTextMode(on)
        if on {
            // 追加: キーを出すためフル画面を解除し、バナーは帯状で残す。
            candidateBar.isHidden = false // 追加: 変換候補を見せる（自由記述もかな漢字変換を使う）
            rootStack.isHidden = false // 追加: キー領域を出す
            bannerFullScreenConstraint?.isActive = false // 追加: 全面制約を外す
            bannerHeightConstraint?.isActive = true // 追加: 帯状の高さ制約へ戻す
            bannerHeightConstraint?.constant = Self.bannerVisibleHeight // 追加: 帯の高さ
            questionBanner.isHidden = false // 追加: バナー自体は出したままにする
            onRequiredExtraHeightChanged?(Self.bannerVisibleHeight) // 追加: 帯の分だけ全体を高くする
            NSLog("[MFK-Narrative] freeText mode: keys visible") // 追加: デバッグ
        } else {
            setNarrativeFullScreen(true) // 追加: 選択肢表示へ戻るのでフル画面に戻す
        }
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
