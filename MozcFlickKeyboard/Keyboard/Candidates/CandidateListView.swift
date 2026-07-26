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
    /// 触覚フィードバック ON/OFF（Full Access 無しでは false にしてエラーログを避ける）。
    var hapticsEnabled = true

    private var candidates: [ConversionCandidate] = []

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
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
        backgroundColor = .secondarySystemBackground

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseID)

        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// 候補を設定して再描画する。
    func setCandidates(_ candidates: [ConversionCandidate]) {
        self.candidates = candidates
        collectionView.reloadData()
    }
}

extension CandidateListView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        candidates.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CandidateCell.reuseID, for: indexPath)
        guard let candidateCell = cell as? CandidateCell else { return cell }
        candidateCell.configure(text: candidates[indexPath.item].value, focused: false)
        return candidateCell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
        onSelect?(candidates[indexPath.item])
    }
}
