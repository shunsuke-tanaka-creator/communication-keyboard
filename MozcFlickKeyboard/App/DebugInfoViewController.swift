// DebugInfoViewController.swift
// MozcFlickKeyboard — デバッグ情報表示画面。
// Mozc 初期化時間 / 候補取得時間 / 辞書サイズ / メモリ概算 / 辞書件数 などを表示する。
// これらの実値は MozcBridge 側から共有される想定。取得できない項目はプレースホルダ("—")を表示する。

import UIKit
import MozcFlickShared // 追加: AppConfig を利用

final class DebugInfoViewController: UIViewController {

    /// デバッグ表示1項目。
    private struct Metric {
        let title: String
        let value: String
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var metrics: [Metric] = []

    /// App Group 共有の UserDefaults（MozcBridge が計測値を書き込む想定のキーを読む）。
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "デバッグ情報"
        view.backgroundColor = .systemBackground // ダークモード追従
        setupTableView()
        reloadMetrics()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// 計測値を収集する。値が無ければプレースホルダ。
    private func reloadMetrics() {
        let placeholder = "—"

        // MozcBridge が書き込む想定のキー（未定義なら placeholder）。
        let initMs = doubleString(forKey: "debug.mozcInitMs", suffix: " ms") ?? placeholder
        let convMs = doubleString(forKey: "debug.lastConversionMs", suffix: " ms") ?? placeholder
        let dictBytes = byteString(forKey: "debug.dictionaryBytes") ?? placeholder
        let dictCount = intString(forKey: "debug.dictionaryEntries") ?? placeholder

        // メモリ概算は端末側で取得可能。
        let memory = currentMemoryString() ?? placeholder

        metrics = [
            Metric(title: "Mozc 初期化時間", value: initMs),
            Metric(title: "候補取得時間(直近)", value: convMs),
            Metric(title: "辞書サイズ", value: dictBytes),
            Metric(title: "辞書件数", value: dictCount),
            Metric(title: "メモリ使用量(概算)", value: memory)
        ]
        tableView.reloadData()
    }

    // MARK: - 値の整形

    private func doubleString(forKey key: String, suffix: String) -> String? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        return String(format: "%.1f%@", defaults.double(forKey: key), suffix)
    }

    private func intString(forKey key: String) -> String? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        return "\(defaults.integer(forKey: key)) 件"
    }

    private func byteString(forKey key: String) -> String? {
        guard let defaults, defaults.object(forKey: key) != nil else { return nil }
        let bytes = Int64(defaults.integer(forKey: key))
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 現在プロセスのメモリ使用量概算。取得できなければ nil。
    private func currentMemoryString() -> String? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(info.resident_size), countStyle: .memory)
    }
}

// MARK: - UITableViewDataSource

extension DebugInfoViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return metrics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let metric = metrics[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = metric.title
        config.secondaryText = metric.value
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        return cell
    }
}
