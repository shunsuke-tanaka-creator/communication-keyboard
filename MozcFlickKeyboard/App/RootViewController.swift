// RootViewController.swift
// MozcFlickKeyboard — ホストアプリのトップ画面（ハブ）。
// キーボードの追加手順を説明し、設定 / ライセンス / デバッグ情報の各画面へ遷移する。

import UIKit

final class RootViewController: UIViewController {

    /// 遷移先を表す行データ。
    private enum Row: Int, CaseIterable {
        case settings
        case license
        case debug
        case logs // 追加: 入力ログ閲覧

        var title: String {
            switch self {
            case .settings: return "設定"
            case .license: return "ライセンス"
            case .debug:    return "デバッグ情報"
            case .logs:     return "入力ログ" // 追加
            }
        }
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    /// キーボード追加手順の説明文。
    private let instructionText =
        "MozcFlick を使うには:\n" +
        "1. 「設定」App →「一般」→「キーボード」→「キーボード」\n" +
        "2. 「新しいキーボードを追加」→ MozcFlick を選択\n" +
        "3. 入力欄で地球儀キーを長押しして MozcFlick に切替"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "MozcFlick"
        view.backgroundColor = .systemBackground // ダークモード追従
        setupTableView()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableHeaderView = makeHeaderView()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// キーボード追加手順を表示するヘッダー。
    private func makeHeaderView() -> UIView {
        let container = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body) // Dynamic Type 対応
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.text = instructionText
        label.accessibilityLabel = "キーボード追加手順"
        container.addSubview(label)
        // 追加: tableHeaderView の高さ自前計算時、一時 frame(幅0/高さ1)で bottom/trailing 制約が
        //       競合し Auto Layout 警告が出る。優先度を下げて一時状態の破綻を避ける（確定サイズは不変）。
        let bottom = label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        bottom.priority = .defaultHigh
        let trailing = label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            trailing,
            bottom
        ])
        // tableHeaderView は Auto Layout の高さを自前計算する必要があるため一度レイアウトする。
        container.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 1)
        container.setNeedsLayout()
        container.layoutIfNeeded()
        let height = container.systemLayoutSizeFitting(
            CGSize(width: view.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        ).height
        container.frame.size.height = height
        return container
    }
}

// MARK: - UITableViewDataSource / Delegate

extension RootViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        if let row = Row(rawValue: indexPath.row) {
            var config = cell.defaultContentConfiguration()
            config.text = row.title
            cell.contentConfiguration = config
        }
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        let next: UIViewController
        switch row {
        case .settings: next = SettingsViewController()
        case .license:  next = LicenseViewController()
        case .debug:    next = DebugInfoViewController()
        case .logs:     next = SessionLogsViewController() // 追加: 入力ログ閲覧
        }
        navigationController?.pushViewController(next, animated: true)
    }
}
