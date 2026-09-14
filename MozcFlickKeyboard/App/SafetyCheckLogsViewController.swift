// SafetyCheckLogsViewController.swift
// MozcFlickKeyboard — ホストアプリ: キーボード拡張が記録した安否確認チェックのログ閲覧画面。
//
// App Group 共有コンテナの SafetyChecks/ 配下にある "check_*.jsonl" を一覧表示し、
// 選択したファイルの中身（JSON Lines）を表示する。詳細表示は SessionLogDetailViewController を再利用する。

import UIKit
import MozcFlickShared // SafetyCheckLog.logsDirectoryURL を利用

final class SafetyCheckLogsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    /// 新しい順に並べたログファイル URL。
    private var files: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "安否確認ログ"
        view.backgroundColor = .systemBackground // ダークモード追従
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadFiles()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// ログディレクトリを走査して "check_*.jsonl" を新しい順に集める。
    private func reloadFiles() {
        files = []
        if let dir = SafetyCheckLog.logsDirectoryURL,
           let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            files = urls.filter { $0.pathExtension == "jsonl" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent } // 名前=日付なので降順で新しい順
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SafetyCheckLogsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files.isEmpty ? 1 : files.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if files.isEmpty {
            config.text = "ログはまだありません"
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            config.text = files[indexPath.row].lastPathComponent
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !files.isEmpty else { return }
        let url = files[indexPath.row]
        // 詳細表示は入力ログと同じビューアを再利用する。
        let detail = SessionLogDetailViewController(fileURL: url)
        navigationController?.pushViewController(detail, animated: true)
    }
}
