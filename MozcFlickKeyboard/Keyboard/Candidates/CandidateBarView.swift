// CandidateBarView.swift
// MozcFlickKeyboard — 上部候補バー。
//
// 機能:
//  - 横スクロール UICollectionView で変換候補を表示
//  - タップで候補確定（onSelect）
//  - 展開ボタン（onExpand）で候補一覧を表示
//  - 選択候補の視覚強調
//  - 長い候補の省略（末尾省略）
//  - Dynamic Type / ダークモード / VoiceOver ラベル対応

import UIKit
import MozcFlickShared // 追加: 共有フレームワークの ConversionCandidate を利用

final class CandidateBarView: UIView {

    /// 候補タップ時に呼ばれる。
    var onSelect: ((ConversionCandidate) -> Void)?
    /// 展開ボタンタップ時に呼ばれる。
    var onExpand: (() -> Void)?
    /// 触覚フィードバック ON/OFF（Full Access 無しでは false にしてエラーログを避ける）。
    var hapticsEnabled = true

    private var candidates: [ConversionCandidate] = []
    private var focusedID: String?

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private let expandButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        b.accessibilityLabel = "候補一覧を開く"
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { return nil }

    private func setup() {
        backgroundColor = .secondarySystemBackground // ダークモード追従

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseID)

        expandButton.addTarget(self, action: #selector(handleExpand), for: .touchUpInside)

        addSubview(collectionView)
        addSubview(expandButton)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.trailingAnchor.constraint(equalTo: expandButton.leadingAnchor),

            expandButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            expandButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 36),
        ])
    }

    /// 候補を設定して再描画する。focused で強調する候補IDを指定できる。
    func setCandidates(_ candidates: [ConversionCandidate], focused: String?) {
        self.candidates = candidates
        self.focusedID = focused
        expandButton.isHidden = candidates.count <= 1
        collectionView.reloadData()
        if !candidates.isEmpty {
            collectionView.setContentOffset(.zero, animated: false)
        }
    }

    @objc private func handleExpand() {
        onExpand?()
    }
}

// MARK: - DataSource / Delegate

extension CandidateBarView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        candidates.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateCell.reuseID, for: indexPath)
        guard let candidateCell = cell as? CandidateCell else { return cell }
        let candidate = candidates[indexPath.item]
        candidateCell.configure(text: candidate.value, focused: candidate.id == focusedID)
        return candidateCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let candidate = candidates[indexPath.item]
        // 候補選択の触覚フィードバック。
        if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        onSelect?(candidate)
    }
}

/// 候補セル。
final class CandidateCell: UICollectionViewCell {

    static let reuseID = "CandidateCell"

    private let label: UILabel = {
        let l = UILabel()
        l.font = UIFont.preferredFont(forTextStyle: .body) // Dynamic Type
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .label
        l.lineBreakMode = .byTruncatingTail // 長い候補は末尾省略
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 6
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            // 長すぎる候補の最大幅（省略のため）。
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { return nil }

    func configure(text: String, focused: Bool) {
        label.text = text
        contentView.backgroundColor = focused ? .systemBlue.withAlphaComponent(0.2) : .clear
        label.textColor = focused ? .systemBlue : .label
        accessibilityLabel = text // VoiceOver
    }
}
