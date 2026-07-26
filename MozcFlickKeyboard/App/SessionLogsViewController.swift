// SessionLogsViewController.swift
// MozcFlickKeyboard — ホストアプリ: キーボード拡張が記録したセッションログの閲覧画面。
//
// App Group 共有コンテナの SessionLogs/ 配下にある "session_*.jsonl" を一覧表示し、
// 選択したファイルの中身（JSON Lines）を表示する。

import UIKit
import MozcFlickShared // SessionLogger.logsDirectoryURL を利用

final class SessionLogsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    /// 新しい順に並べたログファイル URL。
    private var files: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "入力ログ"
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

    /// ログディレクトリを走査して "session_*.jsonl" を新しい順に集める。
    private func reloadFiles() {
        files = []
        if let dir = SessionLogger.logsDirectoryURL,
           let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            files = urls.filter { $0.pathExtension == "jsonl" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent } // 名前=日時なので降順で新しい順
        }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SessionLogsViewController: UITableViewDataSource, UITableViewDelegate {

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
        let detail = SessionLogDetailViewController(fileURL: url)
        navigationController?.pushViewController(detail, animated: true)
    }
}

/// ログ1ファイルの中身を表示する画面。
final class SessionLogDetailViewController: UIViewController {

    private let fileURL: URL
    private let textView = UITextView()

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "読み込みに失敗しました"
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
