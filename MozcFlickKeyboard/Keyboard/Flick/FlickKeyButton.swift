// FlickKeyButton.swift
// MozcFlickKeyboard — 1キーの UIControl。
//
// 機能:
//  - タップ / 4方向フリック判定（FlickGesture を利用）
//  - フリックガイド表示（指を置いた時に上下左右の候補文字を表示）
//  - キーポップアップ（押下中に現在方向の文字を拡大表示）
//  - 長押し（バックスペースの連続削除・段階加速に使用）
//  - 誤フリック抑制（距離/速度/角度しきい値）
//  - 触覚フィードバック（タップ時）
//
// 入力音について:
//  iOS の Custom Keyboard は Full Access 無しでは UIDevice.playInputClick / AudioServices の
//  クリック音を鳴らせない（RequestsOpenAccess が必要）。ここでは触覚フィードバックのみを既定とし、
//  クリック音は Full Access 前提の任意機能としてコメントで明記する。

import UIKit
import MozcFlickShared // 追加: 共有フレームワークの型を利用

/// FlickKeyButton の押下結果を受け取る委譲。
protocol FlickKeyButtonDelegate: AnyObject {
    /// 指定方向で確定した（タップ or フリック）。
    func flickKeyButton(_ button: FlickKeyButton, didActivate direction: FlickDirection)
    /// 長押しが継続中（連続削除などのため）。開始からの経過で加速判定に使う。
    func flickKeyButtonDidRepeat(_ button: FlickKeyButton)
}

final class FlickKeyButton: UIControl {

    weak var delegate: FlickKeyButtonDelegate?

    /// このキーの定義。
    let keyDefinition: KeyDefinition

    /// フリック判定しきい値。
    var thresholds: FlickThresholds = .standard

    /// 触覚フィードバック ON/OFF。
    var hapticsEnabled = true

    /// 長押しで連続リピートするキーか（バックスペース等）。
    var isRepeatable = false

    // MARK: - 内部状態

    private var startPoint: CGPoint = .zero
    private var currentDirection: FlickDirection = .center

    /// 長押しリピート用タイマーと加速段階。
    private var repeatTimer: Timer?
    private var repeatCount = 0

    // MARK: - サブビュー

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.font = UIFont.preferredFont(forTextStyle: .title2)
        l.adjustsFontForContentSizeCategory = true // Dynamic Type
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// 押下中に方向の文字を拡大表示するポップアップ。
    private let popupLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.font = UIFont.systemFont(ofSize: 28, weight: .medium)
        l.textColor = .label
        l.backgroundColor = .secondarySystemBackground
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// フリックガイド（上下左右の候補を薄く表示するコンテナ）。
    private let guideView = FlickGuideView()

    // MARK: - init

    init(keyDefinition: KeyDefinition) {
        self.keyDefinition = keyDefinition
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        return nil // Storyboard 未使用
    }

    private func setup() {
        backgroundColor = .tertiarySystemBackground
        layer.cornerRadius = 6
        layer.masksToBounds = false

        addSubview(guideView)
        addSubview(titleLabel)
        addSubview(popupLabel)
        guideView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = keyDefinition.label

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            guideView.leadingAnchor.constraint(equalTo: leadingAnchor),
            guideView.trailingAnchor.constraint(equalTo: trailingAnchor),
            guideView.topAnchor.constraint(equalTo: topAnchor),
            guideView.bottomAnchor.constraint(equalTo: bottomAnchor),
            popupLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            popupLabel.bottomAnchor.constraint(equalTo: topAnchor, constant: -4),
            popupLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            popupLabel.heightAnchor.constraint(equalToConstant: 44),
        ])

        // かなキーならフリックガイドに方向文字を設定。
        guideView.configure(with: keyDefinition.kanaKey)

        // アクセシビリティ。
        isAccessibilityElement = true
        accessibilityLabel = keyDefinition.label
        accessibilityTraits = .keyboardKey
    }

    // MARK: - タッチ処理

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        startPoint = touch.location(in: self)
        currentDirection = .center
        showPopup(for: .center)
        guideView.setActive(true)
        startRepeatIfNeeded()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let translation = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
        // フリックのみモードでも方向表示は行う。中央は flickOnly 制御を上位で行う。
        let dir = FlickGesture.direction(translation: translation, thresholds: thresholds)
        if dir != currentDirection {
            currentDirection = dir
            showPopup(for: dir)
            guideView.highlight(dir)
            fireHaptic(.selection)
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        finishTouch(activate: true)
    }

    override func cancelTracking(with event: UIEvent?) {
        finishTouch(activate: false)
    }

    private func finishTouch(activate: Bool) {
        hidePopup()
        guideView.setActive(false)
        stopRepeat()
        NSLog("[MFK] finishTouch label='\(keyDefinition.label)' activate=\(activate) dir=\(currentDirection)") // 追加: タッチ確定のデバッグ
        if activate {
            fireHaptic(.impact)
            delegate?.flickKeyButton(self, didActivate: currentDirection)
        }
        currentDirection = .center
    }

    // MARK: - ポップアップ

    private func showPopup(for direction: FlickDirection) {
        let text: String?
        if let kana = keyDefinition.kanaKey {
            text = kana.character(for: direction)
        } else {
            text = (direction == .center) ? keyDefinition.label : nil
        }
        guard let t = text else { popupLabel.isHidden = true; return }
        popupLabel.text = t
        popupLabel.isHidden = false
    }

    private func hidePopup() {
        popupLabel.isHidden = true
    }

    // MARK: - 長押しリピート（段階加速）

    private func startRepeatIfNeeded() {
        guard isRepeatable else { return }
        repeatCount = 0
        // 初回は 0.4s 後、以降は加速（0.4 → 0.1s）。
        scheduleRepeat(after: 0.4)
    }

    private func scheduleRepeat(after interval: TimeInterval) {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatCount += 1
            self.delegate?.flickKeyButtonDidRepeat(self)
            // 段階加速: 押し続けるほど間隔を詰める。
            let next = max(0.1, 0.4 - Double(self.repeatCount) * 0.05)
            self.scheduleRepeat(after: next)
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: - 触覚フィードバック

    private enum HapticKind { case selection, impact }

    private func fireHaptic(_ kind: HapticKind) {
        guard hapticsEnabled else { return }
        switch kind {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .impact:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // 入力クリック音: Full Access 有効時のみ有効化する想定（既定は無効）。
        // if hasFullAccess { UIDevice.current.playInputClick() } // self を UIInputViewControllerInputClientProtocol 準拠にする必要あり
    }
}

/// フリックガイド（キー背景に上下左右の候補文字を薄く表示する）。
final class FlickGuideView: UIView {

    private var directionLabels: [FlickDirection: UILabel] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for dir in FlickDirection.allCases where dir != .center {
            let l = UILabel()
            l.textAlignment = .center
            l.font = UIFont.systemFont(ofSize: 12)
            l.textColor = .tertiaryLabel
            l.translatesAutoresizingMaskIntoConstraints = false
            l.isHidden = true
            addSubview(l)
            directionLabels[dir] = l
            NSLayoutConstraint.activate(constraints(for: dir, label: l))
        }
    }

    required init?(coder: NSCoder) { return nil }

    private func constraints(for dir: FlickDirection, label l: UILabel) -> [NSLayoutConstraint] {
        switch dir {
        case .left:
            return [l.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                    l.centerYAnchor.constraint(equalTo: centerYAnchor)]
        case .right:
            return [l.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                    l.centerYAnchor.constraint(equalTo: centerYAnchor)]
        case .up:
            return [l.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                    l.centerXAnchor.constraint(equalTo: centerXAnchor)]
        case .down:
            return [l.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                    l.centerXAnchor.constraint(equalTo: centerXAnchor)]
        case .center:
            return []
        }
    }

    /// かなキーの方向文字をガイドへ設定。
    func configure(with kanaKey: KanaKey?) {
        for dir in FlickDirection.allCases where dir != .center {
            directionLabels[dir]?.text = kanaKey?.character(for: dir)
        }
    }

    /// ガイド表示のON/OFF（指を置いた時のみ表示）。
    func setActive(_ active: Bool) {
        for (_, l) in directionLabels {
            l.isHidden = !active || (l.text?.isEmpty ?? true)
        }
        if !active { resetHighlight() }
    }

    /// 現在の方向を強調。
    func highlight(_ direction: FlickDirection) {
        for (dir, l) in directionLabels {
            l.textColor = (dir == direction) ? .label : .tertiaryLabel
        }
    }

    private func resetHighlight() {
        for (_, l) in directionLabels {
            l.textColor = .tertiaryLabel
        }
    }
}
