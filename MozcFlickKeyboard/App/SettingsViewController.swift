// SettingsViewController.swift
// MozcFlickKeyboard — 入力設定画面。
// トグル入力 / フリックのみ / 学習 / プライベートモード の各設定を
// App Group の UserDefaults(suiteName: AppConfig.appGroupID) に保存し、Keyboard Extension と共有する。

import UIKit
import MozcFlickShared // 追加: AppConfig を利用

/// 設定値のキー。Keyboard 側の SettingsKeys と同じ文字列を用いること。
private enum SettingsKeys {
    static let toggleInputEnabled = "toggleInputEnabled"
    static let flickOnlyEnabled = "flickOnlyEnabled"
    static let learningEnabled = "learningEnabled"
    static let privateModeEnabled = "privateModeEnabled"
    static let schedules = "schedules"         // 追加: 予定の配列。各要素は "HH:mm\t文言"。
}

final class SettingsViewController: UIViewController {

    /// 設定1項目の定義。
    private struct Item {
        let key: String
        let title: String
        let subtitle: String
        let defaultValue: Bool
    }

    private let items: [Item] = [
        Item(key: SettingsKeys.toggleInputEnabled,
             title: "トグル入力",
             subtitle: "同じキーの連打でかなを循環入力する",
             defaultValue: true),
        Item(key: SettingsKeys.flickOnlyEnabled,
             title: "フリックのみ",
             subtitle: "トグルを無効化しフリック入力だけにする",
             defaultValue: false),
        Item(key: SettingsKeys.learningEnabled,
             title: "学習",
             subtitle: "変換結果を学習して候補を最適化する",
             defaultValue: true),
        Item(key: SettingsKeys.privateModeEnabled,
             title: "プライベートモード",
             subtitle: "入力履歴・学習を保存しない",
             defaultValue: false)
    ]

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    /// App Group 共有の UserDefaults。
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID)

    /// 追加: 予定の配列（各要素は "HH:mm\t文言"）。UserDefaults と同期する。
    private var schedules: [String] {
        get { defaults?.stringArray(forKey: SettingsKeys.schedules) ?? [] }
        set { defaults?.set(newValue, forKey: SettingsKeys.schedules) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "設定"
        view.backgroundColor = .systemBackground // ダークモード追従
        // 追加: 予定を1件追加する + ボタン。
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addSchedule))
        setupTableView()
        registerKeyboardNotifications() // 追加: キーボード表示でセルが隠れないようにする
    }

    // 追加: ソフトキーボードの表示/非表示に応じて tableView の下端インセットを調整する。
    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        // キーボードが覆う高さぶん下端に余白を作り、編集中セルまでスクロール可能にする。
        let overlap = max(0, tableView.frame.maxY - frame.minY)
        tableView.contentInset.bottom = overlap
        tableView.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func keyboardWillHide() {
        tableView.contentInset.bottom = 0
        tableView.verticalScrollIndicatorInsets.bottom = 0
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

    /// 現在値を取得（未設定なら既定値）。
    private func boolValue(for item: Item) -> Bool {
        guard let defaults, defaults.object(forKey: item.key) != nil else {
            return item.defaultValue
        }
        return defaults.bool(forKey: item.key)
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        let item = items[sender.tag]
        defaults?.set(sender.isOn, forKey: item.key)
    }

    /// 追加: 予定を1件追加する（時刻は現在時刻を既定、文言は空）。
    @objc private func addSchedule() {
        var list = schedules
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        let now = f.string(from: Date()) // 追加: 既定は現在時刻
        list.append("\(now)\t") // "HH:mm\t文言"
        schedules = list
        tableView.reloadData()
    }

    /// 追加: 予定文言の編集を保存する。tag = 行番号。
    @objc private func scheduleFieldChanged(_ sender: UITextField) {
        let row = sender.tag
        var list = schedules
        guard row < list.count else { return }
        let parts = list[row].components(separatedBy: "\t")
        let time = parts.first ?? ""
        list[row] = "\(time)\t\(sender.text ?? "")"
        schedules = list
    }

    /// 追加: 時刻ピッカーの選択を "HH:mm" にして保存する。tag = 行番号。
    @objc private func scheduleTimeChanged(_ sender: UIDatePicker) {
        let row = sender.tag
        var list = schedules
        guard row < list.count else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        let time = f.string(from: sender.date)
        let parts = list[row].components(separatedBy: "\t")
        let text = parts.count > 1 ? parts[1] : ""
        list[row] = "\(time)\t\(text)"
        schedules = list
    }
}

// MARK: - UITextFieldDelegate

extension SettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // 追加: 編集開始時にその予定行を見える位置までスクロールする。
    func textFieldDidBeginEditing(_ textField: UITextField) {
        let indexPath = IndexPath(row: textField.tag, section: 1)
        tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
    }
}

    
// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // 追加: section1 に予定入力を追加
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 1 ? "予定（キーボードを開くと次の予定を表示）" : nil // 変更
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 1 { return schedules.count } // 変更: 予定の件数
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 追加: section1 は予定1件（時刻 + 文言）の入力行。
        if indexPath.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let parts = schedules[indexPath.row].components(separatedBy: "\t")
            let time = parts.first ?? ""
            let text = parts.count > 1 ? parts[1] : ""

            // 変更: 時刻はテキスト入力ではなく UIDatePicker（時刻ホイール）で選ぶ。
            let timePicker = UIDatePicker()
            timePicker.datePickerMode = .time
            timePicker.preferredDatePickerStyle = .compact // タップでポップオーバー表示
            timePicker.minuteInterval = 5 // 追加: 5分刻みで選びやすく
            timePicker.locale = Locale(identifier: "en_GB") // 追加: 24時間表記
            timePicker.tag = indexPath.row
            // 保存済み "HH:mm" があれば初期値に反映。
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: time) { timePicker.date = d }
            timePicker.addTarget(self, action: #selector(scheduleTimeChanged(_:)), for: .valueChanged)
            timePicker.setContentHuggingPriority(.required, for: .horizontal)

            let textField = UITextField()
            textField.borderStyle = .roundedRect
            textField.placeholder = "予定の文言（例: 会議）"
            textField.text = text
            textField.delegate = self
            textField.tag = indexPath.row // 変更: 文言のみ。tag は行番号。
            textField.addTarget(self, action: #selector(scheduleFieldChanged(_:)), for: .editingChanged)

            let stack = UIStackView(arrangedSubviews: [timePicker, textField])
            stack.axis = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            ])
            cell.selectionStyle = .none
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = items[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.subtitle
        cell.contentConfiguration = config

        let toggle = UISwitch()
        toggle.tag = indexPath.row
        toggle.isOn = boolValue(for: item)
        toggle.accessibilityLabel = item.title
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }

    // 追加: 予定行はスワイプで削除できる。
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard indexPath.section == 1, editingStyle == .delete else { return }
        var list = schedules
        guard indexPath.row < list.count else { return }
        view.endEditing(true) // 追加: 編集中フィールドの tag ずれ防止
        list.remove(at: indexPath.row)
        schedules = list
        tableView.reloadData()
    }
}

