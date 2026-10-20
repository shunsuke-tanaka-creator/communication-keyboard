// CandidateListView.swift
// MozcFlickKeyboard — 展開時の候補一覧。
//
// 候補バーの展開ボタンで表示する、複数行グリッドの候補一覧。
// 縦スクロール UICollectionView（左詰めフロー）で全候補を一覧表示する。
// タップで確定（onSelect）。Dynamic Type / ダークモード / VoiceOver 対応。

import UIKit
import MozcFlickShared // 追加: 共有フレームワークの ConversionCandidate を利用

final class CandidateListView: UIView {

    /// 候補タップ時に呼ばれる。
    var onSelect: ((ConversionCandidate) -> Void)?
    var onClose: (() -> Void)?
    private var focusedID: String?
    private let closeButton = UIButton(type: .system)
    /// 触覚フィードバック ON/OFF（Full Access 無しでは false にしてエラーログを避ける）。
    var hapticsEnabled = true

    private var candidates: [ConversionCandidate] = []

    private let collectionView: UICollectionView = {
        let layout = LeadingCandidateLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.estimatedItemSize = .zero
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { return nil }

    private func setup() {
        backgroundColor = KeyboardAppearance.surface

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseID)

        closeButton.setTitle("閉じる", for: .normal)
        closeButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        closeButton.tintColor = KeyboardAppearance.accent
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        addSubview(closeButton)
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 88),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// 候補を設定して再描画する。
    func setCandidates(_ candidates: [ConversionCandidate], focused: String? = nil, resetScroll: Bool = true) {
        guard self.candidates != candidates || focusedID != focused || resetScroll else { return }
        let offset = collectionView.contentOffset
        self.candidates = candidates
        focusedID = focused
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let maximum = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        collectionView.setContentOffset(resetScroll ? .zero : CGPoint(x: 0, y: min(max(0, offset.y), maximum)), animated: false)
    }
}

extension CandidateListView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        candidates.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateCell.reuseID, for: indexPath)
        guard let candidateCell = cell as? CandidateCell else { return cell }
        candidateCell.configure(text: candidates[indexPath.item].value, focused: candidates[indexPath.item].id == focusedID)
        return candidateCell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .medium), maximumPointSize: 20)
        let width = (candidates[indexPath.item].value as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: min(max(52, ceil(width) + 20), min(240, max(52, collectionView.bounds.width - 16))), height: 44)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard candidates.indices.contains(indexPath.item) else { return }
        if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        onSelect?(candidates[indexPath.item])
    }
}

/// Keep gaps constant instead of stretching a sparse row across the entire width.
private final class LeadingCandidateLayout: UICollectionViewFlowLayout {
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let original = super.layoutAttributesForElements(in: rect) else { return nil }
        let attributes = original.compactMap { $0.copy() as? UICollectionViewLayoutAttributes }
        var left = sectionInset.left
        var rowY: CGFloat = -.greatestFiniteMagnitude
        for item in attributes where item.representedElementCategory == .cell {
            if abs(item.frame.minY - rowY) > 1 {
                left = sectionInset.left
                rowY = item.frame.minY
            }
            item.frame.origin.x = left
            left += item.frame.width + minimumInteritemSpacing
        }
        return attributes
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}
