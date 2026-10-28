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
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "抽出", style: .plain, target: self, action: #selector(openExport)) // 追加: 期間抽出画面へ
    }

    /// 追加: 期間指定してログを抽出・共有する画面を開く。
    @objc private func openExport() {
        navigationController?.pushViewController(SessionLogExportViewController(), animated: true)
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

/// 追加: 開始・終了日時を指定し、期間内のセッションログを1つのJSONLに結合して共有シートで書き出す画面。
/// 期間判定はファイル名のセッション開始時刻（session_yyyyMMdd_HHmmss_SSS_xxxxxxxx.jsonl）で行う。
/// 各行には元ファイル名を "file" キーとして先頭に付与する。
final class SessionLogExportViewController: UIViewController {

    private let startPicker = UIDatePicker() // 追加
    private let endPicker = UIDatePicker() // 追加

    /// 追加: ファイル名の日時部分を読むフォーマッタ（SessionLogger と同じ形式）。
    private let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "期間を指定して抽出"
        view.backgroundColor = .systemBackground
        startPicker.datePickerMode = .dateAndTime
        endPicker.datePickerMode = .dateAndTime
        startPicker.date = Calendar.current.startOfDay(for: Date()) // 追加: 既定は今日0時〜現在
        endPicker.date = Date()

        let startLabel = UILabel()
        startLabel.text = "開始"
        let endLabel = UILabel()
        endLabel.text = "終了"
        let button = UIButton(type: .system)
        button.setTitle("抽出してダウンロード", for: .normal)
        button.addTarget(self, action: #selector(export), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [startLabel, startPicker, endLabel, endPicker, button])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    /// 追加: 期間内ファイルを古い順に結合し、一時ファイルに書いて共有シートを開く。
    @objc private func export() {
        let start = startPicker.date
        let end = endPicker.date
        let dir = SessionLogger.logsDirectoryURL!
        let urls = try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let targets = urls.filter { url in
            let name = url.lastPathComponent
            guard url.pathExtension == "jsonl", name.hasPrefix("session_") else { return false }
            let stamp = String(name.dropFirst("session_".count).prefix(19)) // yyyyMMdd_HHmmss_SSS
            guard let date = fileNameFormatter.date(from: stamp) else { return false }
            return date >= start && date <= end
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var output = ""
        for url in targets {
            let name = url.lastPathComponent
            let text = try! String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") where line.hasPrefix("{") {
                output += "{\"file\":\"\(name)\"," + line.dropFirst() + "\n" // 先頭にファイル名を付与
            }
        }

        let outName = "session_export_\(fileNameFormatter.string(from: start))_\(fileNameFormatter.string(from: end)).jsonl"
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(outName)
        try! output.write(to: outURL, atomically: true, encoding: .utf8)
        NSLog("[MFK-Log] export files=\(targets.count) bytes=\(output.utf8.count) url=\(outURL.path)") // デバッグ: 抽出結果

        let activity = UIActivityViewController(activityItems: [outURL], applicationActivities: nil)
        present(activity, animated: true)
    }
}
