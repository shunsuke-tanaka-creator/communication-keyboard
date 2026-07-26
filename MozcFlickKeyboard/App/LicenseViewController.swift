// LicenseViewController.swift
// MozcFlickKeyboard — ライセンス表示画面。
// docs/licenses やバンドルされたライセンステキストを表示する。
// 現状は読み込み元が未確定のため、バンドル内テキストを探し、無ければプレースホルダを表示（後で差し替え可能）。

import UIKit

final class LicenseViewController: UIViewController {

    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ライセンス"
        view.backgroundColor = .systemBackground // ダークモード追従
        setupTextView()
        textView.text = loadLicenseText()
    }

    private func setupTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = UIFont.preferredFont(forTextStyle: .body) // Dynamic Type 対応
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.accessibilityLabel = "ライセンス本文"
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// バンドルされたライセンステキストを読み込む。
    /// LICENSE.txt / licenses.txt を探し、見つからなければプレースホルダを返す（後で差し替え可能）。
    private func loadLicenseText() -> String {
        let candidates = ["LICENSE", "licenses", "LICENSES"]
        let extensions = ["txt", "md", ""]
        for name in candidates {
            for ext in extensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext),
                   let text = try? String(contentsOf: url, encoding: .utf8) {
                    return text
                }
            }
        }
        return "ライセンス情報は準備中です。\n（バンドルに LICENSE テキストを追加すると自動的に表示されます。）"
    }
}
