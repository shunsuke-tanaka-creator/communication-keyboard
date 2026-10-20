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
    func flickKeyButtonWillBeginCursorControl(_ button: FlickKeyButton) -> Bool
    func flickKeyButton(_ button: FlickKeyButton, didMoveCursorBy offset: Int)
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
    var displaysKatakana = false {
        didSet { guideView.configure(with: keyDefinition.kanaKey, katakana: displaysKatakana) }
    }
    private var previousPoint = CGPoint.zero
    private var previousTimestamp: TimeInterval = 0
    private var cursorTimer: Timer?
    private var cursorGestureConsumed = false
    private var cursorControlAllowed = false
    private var cursorDrag = CursorDragState()

    private var isSpaceKey: Bool { keyDefinition.action == .space }

    func setDisplayTitle(_ title: String) {
        titleLabel.text = title
        accessibilityLabel = title
    }

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
        l.textColor = KeyboardAppearance.ink
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// 押下中に方向の文字を拡大表示するポップアップ。
    private let popupLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.font = UIFont.systemFont(ofSize: 28, weight: .medium)
        l.textColor = .white
        l.backgroundColor = KeyboardAppearance.accentFill
        l.layer.cornerRadius = 12
        l.layer.cornerCurve = .continuous
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.5
        l.layer.masksToBounds = true
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// フリックガイド（上下左右の候補を薄く表示するコンテナ）。
    private let guideView = FlickGuideView()
    private let symbolView = UIImageView()
    private var touchIsActive = false

    private var isCharacterKey: Bool {
        switch keyDefinition.action {
        case .kana, .input: return true
        default: return false
        }
    }

    private var isPrimaryKey: Bool {
        if case .returnOrConfirm = keyDefinition.action { return keyDefinition.row == 2 }
        return false
    }

    private func updateAppearance() {
        backgroundColor = touchIsActive ? KeyboardAppearance.accentSoft
            : (isPrimaryKey ? KeyboardAppearance.accentFill
                : (isCharacterKey ? KeyboardAppearance.key : KeyboardAppearance.utilityKey))
        let foreground: UIColor = isPrimaryKey && !touchIsActive ? .white : KeyboardAppearance.ink
        titleLabel.textColor = foreground
        symbolView.tintColor = foreground
        layer.borderColor = KeyboardAppearance.border.resolvedColor(with: traitCollection).cgColor
        layer.shadowOpacity = touchIsActive ? 0 : (traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.04)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

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
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.25
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0.8
        layer.masksToBounds = false

        addSubview(titleLabel)
        addSubview(popupLabel)
        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)

        titleLabel.text = keyDefinition.label
        let size: CGFloat = isCharacterKey && keyDefinition.label.count == 1 ? 23 : 14
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: size, weight: isCharacterKey ? .regular : .medium),
            maximumPointSize: size + 5)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.65
        switch keyDefinition.action {
        case .backspace: symbolView.image = UIImage(systemName: "delete.left")
        case .nextKeyboard: symbolView.image = UIImage(systemName: "globe")
        default: break
        }
        titleLabel.isHidden = symbolView.image != nil
        updateAppearance()

        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 24),
            symbolView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            popupLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            popupLabel.bottomAnchor.constraint(equalTo: topAnchor, constant: -4),
            popupLabel.widthAnchor.constraint(equalTo: widthAnchor),
            popupLabel.heightAnchor.constraint(equalToConstant: 48),
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
        touchIsActive = true
        updateAppearance()
        // ガイドとポップアップを隣接キーより前に描画する（タッチ領域は変えない）。
        layer.zPosition = 10
        superview?.layer.zPosition = 10
        startPoint = touch.location(in: self)
        previousPoint = startPoint
        previousTimestamp = touch.timestamp
        cursorGestureConsumed = false
        cursorControlAllowed = false
        cursorDrag = CursorDragState()
        cursorTimer?.invalidate()
        if isSpaceKey {
            cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.beginCursorControl()
            }
        }
        currentDirection = .center
        showPopup(for: .center)
        if keyDefinition.kanaKey != nil { presentGuide() }
        startRepeatIfNeeded()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let translation = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
        let elapsed = max(touch.timestamp - previousTimestamp, 0.001)
        let delta = CGPoint(x: point.x - previousPoint.x, y: point.y - previousPoint.y)
        previousPoint = point
        previousTimestamp = touch.timestamp
        if isSpaceKey {
            if !cursorGestureConsumed && abs(translation.x) >= 12 && abs(translation.x) > abs(translation.y) {
                beginCursorControl()
                return true // Anchor here so activation does not jump the cursor.
            }
            if cursorControlAllowed {
                let offset = cursorDrag.move(by: delta.x)
                if offset != 0 { delegate?.flickKeyButton(self, didMoveCursorBy: offset) }
            }
            return true
        }
        let velocity = CGPoint(x: delta.x / elapsed, y: delta.y / elapsed)
        let dir = FlickGesture.direction(translation: translation, velocity: velocity,
            thresholds: thresholds, previousDirection: currentDirection)
        if dir != currentDirection {
            currentDirection = dir
            showPopup(for: dir)
            guideView.highlight(dir)
            fireHaptic(.selection)
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { _ = continueTracking(touch, with: event) }
        finishTouch(activate: true)
    }

    override func cancelTracking(with event: UIEvent?) {
        finishTouch(activate: false)
    }

    private func finishTouch(activate: Bool) {
        touchIsActive = false
        updateAppearance()
        layer.zPosition = 0
        superview?.layer.zPosition = 0
        cursorTimer?.invalidate()
        cursorTimer = nil
        hidePopup()
        guideView.setActive(false)
        guideView.removeFromSuperview()
        stopRepeat()
        NSLog("[MFK] finishTouch label='\(keyDefinition.label)' activate=\(activate) dir=\(currentDirection)") // 追加: タッチ確定のデバッグ
        if activate && !cursorGestureConsumed && repeatCount == 0 {
            fireHaptic(.impact)
            delegate?.flickKeyButton(self, didActivate: currentDirection)
        }
        currentDirection = .center
        cursorGestureConsumed = false
        cursorControlAllowed = false
    }

    private func beginCursorControl() {
        guard touchIsActive, isSpaceKey, !cursorGestureConsumed else { return }
        cursorTimer?.invalidate()
        cursorGestureConsumed = true
        cursorControlAllowed = delegate?.flickKeyButtonWillBeginCursorControl(self) ?? false
        if cursorControlAllowed {
            popupLabel.text = "↔"
            popupLabel.isHidden = false
            fireHaptic(.selection)
        }
    }

    private func presentGuide() {
        var host: UIView? = superview
        while let view = host, !(view is KeyboardView) { host = view.superview }
        guard let host else { return }
        let rect = convert(bounds, to: host)
        let width = min(170, host.bounds.width - 8)
        guideView.frame = CGRect(x: min(max(4, rect.midX - width / 2), host.bounds.width - width - 4),
                                 y: max(2, rect.minY - 46), width: width, height: 42)
        host.addSubview(guideView)
        guideView.setActive(true)
        guideView.highlight(.center)
    }

    // MARK: - ポップアップ

    private func showPopup(for direction: FlickDirection) {
        // Kana use a floating five-direction guide above the finger.
        if keyDefinition.kanaKey != nil { popupLabel.isHidden = true; return }
        guard isCharacterKey else { popupLabel.isHidden = true; return }
        let text = (direction == .center) ? titleLabel.text : nil
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

/// Floating directional hints fit inside the extension, above the touched key.
final class FlickGuideView: UIView {
    private let directions: [FlickDirection] = [.left, .up, .center, .down, .right]
    private var labels: [FlickDirection: UILabel] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = KeyboardAppearance.surface
        layer.cornerRadius = 9
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        for direction in directions {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 2
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            addSubview(label)
            labels[direction] = label
        }
    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = (bounds.width - 8) / 5
        for (index, direction) in directions.enumerated() {
            labels[direction]?.frame = CGRect(x: 4 + CGFloat(index) * width, y: 3, width: width - 2, height: bounds.height - 6)
        }
    }
    func configure(with key: KanaKey?, katakana: Bool = false) {
        let arrows: [FlickDirection: String] = [.left: "←", .up: "↑", .center: "•", .down: "↓", .right: "→"]
        for direction in directions {
            let character = key?.character(for: direction) ?? ""
            let text = NSMutableAttributedString(string: (arrows[direction] ?? "") + "\n",
                attributes: [.font: UIFont.systemFont(ofSize: 9, weight: .medium)])
            text.append(NSAttributedString(string: katakana ? KanaTransform.toKatakana(character) : character,
                attributes: [.font: UIFont.systemFont(ofSize: 18, weight: .medium)]))
            labels[direction]?.attributedText = text
        }
    }
    func setActive(_ active: Bool) { isHidden = !active }
    func highlight(_ direction: FlickDirection) {
        for (key, label) in labels {
            label.backgroundColor = key == direction ? KeyboardAppearance.accentFill : .clear
            label.textColor = key == direction ? .white : KeyboardAppearance.ink
        }
    }
}
