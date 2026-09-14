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

    /// 追加: 研究設定（お天気分）の状態ストア。同じ App Group UserDefaults へ書き込む。
    private let narrativeState = NarrativeState()

    /// 追加: 予定の配列（各要素は TSV）。UserDefaults と同期する。
    private var schedules: [String] {
        get { defaults?.stringArray(forKey: SettingsKeys.schedules) ?? [] }
        set { defaults?.set(newValue, forKey: SettingsKeys.schedules) }
    }

    /// 追加: 指定行の ScheduleItem を取得する。
    private func item(at row: Int) -> ScheduleItem? {
        let list = schedules
        guard row < list.count else { return nil }
        return ScheduleItem(tsv: list[row])
    }

    /// 追加: 指定行の ScheduleItem を保存する。
    private func setItem(_ item: ScheduleItem, at row: Int) {
        var list = schedules
        guard row < list.count else { return }
        list[row] = item.tsv
        schedules = list
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "設定"
        view.backgroundColor = .systemBackground // ダークモード追従
        // 変更: 予定を1件追加する + ボタンと、サンプル読み込みボタンを並べる。
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSchedule)),
            UIBarButtonItem(title: "サンプル", style: .plain, target: self, action: #selector(loadSampleSchedules)), // 追加: サンプル一括追加
        ]
        seedSampleSchedulesIfEmpty() // 追加: 予定が未登録なら初回だけサンプルを投入する
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

    // 追加: 研究設定（お天気分）— 各テキストフィールドの tag 定数（予定行の tag=行番号と衝突しない値）。
    private enum NarrativeFieldTag: Int {
        case participantID = 9001 // 追加: 参加者ID フィールド
        case backendURL = 9002    // 追加: Backend URL フィールド
    }

    // 追加: 参加者ID / Backend URL の編集を NarrativeState 経由で App Group へ保存する。
    @objc private func narrativeTextChanged(_ sender: UITextField) {
        let text = sender.text ?? ""
        switch NarrativeFieldTag(rawValue: sender.tag) {
        case .participantID: narrativeState.participantID = text // 追加: 参加者ID を保存
        case .backendURL:    narrativeState.backendBaseURL = text // 追加: 空なら通常入力本文は勿論、研究回答もローカルのみ
        case .none: break
        }
    }

    // 追加: 質問機能 ON/OFF を NarrativeState 経由で保存する。
    @objc private func narrativeEnabledChanged(_ sender: UISwitch) {
        narrativeState.narrativeEnabled = sender.isOn // 追加: 質問機能の有効/無効を保存
    }

    /// 追加: 予定が1件も無いときだけ、サンプル予定を初回投入する（既存の登録は絶対に上書きしない）。
    private func seedSampleSchedulesIfEmpty() {
        guard schedules.isEmpty else { return } // 追加: 既に登録があれば何もしない
        schedules = ScheduleItem.samples.map { $0.tsv } // 追加: サンプルを TSV にして保存
        NSLog("[MFK] seedSampleSchedulesIfEmpty count=\(ScheduleItem.samples.count)") // 追加: 初回投入のデバッグ
    }

    /// 追加: サンプル予定をまとめて追加する。既存の予定は残したまま、重複（同じ時刻+文言）だけ避けて足す。
    @objc private func loadSampleSchedules() {
        var list = schedules // 追加: 現在の登録
        let existingKeys = Set(ScheduleItem.parse(list).map { $0.logKey }) // 追加: 重複判定用（時刻+文言）
        var added = 0 // 追加: 実際に足した件数
        for sample in ScheduleItem.samples where !existingKeys.contains(sample.logKey) {
            list.append(sample.tsv) // 追加: 未登録のサンプルだけ足す
            added += 1
        }
        // 追加: 時刻順に並べ替えて見やすくする（パース不能な行は末尾へ）。
        list = ScheduleItem.parse(list)
            .sorted { ($0.minutes ?? Int.max) < ($1.minutes ?? Int.max) }
            .map { $0.tsv }
        schedules = list
        tableView.reloadData()
        NSLog("[MFK] loadSampleSchedules added=\(added) total=\(list.count)") // 追加: 追加件数のデバッグ
        // 追加: 結果をユーザーへ知らせる。
        let message = added > 0 ? "サンプル予定を \(added) 件追加しました。" : "追加できるサンプルはありません（すべて登録済み）。"
        let alert = UIAlertController(title: "サンプル読み込み", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// 追加: 予定を1件追加する（時刻は現在時刻を既定、文言は空、チェックOFF、毎日）。
    @objc private func addSchedule() {
        var list = schedules
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        let now = f.string(from: Date()) // 追加: 既定は現在時刻
        let item = ScheduleItem(time: now, text: "", needsCheck: false, weekdays: "1111111")
        list.append(item.tsv)
        schedules = list
        tableView.reloadData()
    }

    /// 追加: 予定文言の編集を保存する。tag = 行番号。
    @objc private func scheduleFieldChanged(_ sender: UITextField) {
        guard var it = item(at: sender.tag) else { return }
        it.text = sender.text ?? ""
        setItem(it, at: sender.tag)
    }

    /// 追加: 時刻ピッカーの選択を "HH:mm" にして保存する。tag = 行番号。
    @objc private func scheduleTimeChanged(_ sender: UIDatePicker) {
        guard var it = item(at: sender.tag) else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        it.time = f.string(from: sender.date)
        setItem(it, at: sender.tag)
    }

    /// 追加: チェック要否スイッチの変更を保存する。tag = 行番号。
    @objc private func scheduleCheckChanged(_ sender: UISwitch) {
        guard var it = item(at: sender.tag) else { return }
        it.needsCheck = sender.isOn
        setItem(it, at: sender.tag)
        NSLog("[MFK] scheduleCheckChanged row=\(sender.tag) needsCheck=\(it.needsCheck) tsv='\(it.tsv)'") // 追加: 保存確認
    }

    /// 追加: 曜日ボタンのトグルを保存する。tag = 行番号 * 10 + 曜日index(0=日..6=土)。
    @objc private func scheduleWeekdayTapped(_ sender: UIButton) {
        let row = sender.tag / 10
        let index = sender.tag % 10
        guard var it = item(at: row) else { return }
        var chars = Array(it.weekdays)
        while chars.count < 7 { chars.append("1") }
        chars[index] = chars[index] == "1" ? "0" : "1"
        it.weekdays = String(chars)
        setItem(it, at: row)
        applyWeekdayButtonStyle(sender, on: chars[index] == "1")
    }

    /// 追加: 曜日ボタンの見た目（選択/非選択）を反映する。
    private func applyWeekdayButtonStyle(_ button: UIButton, on: Bool) {
        button.backgroundColor = on ? .systemBlue : .secondarySystemBackground
        button.setTitleColor(on ? .white : .secondaryLabel, for: .normal)
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
        // 追加: 研究設定のフィールド（tag=9001/9002）は予定行ではないのでスクロール対象外。
        if NarrativeFieldTag(rawValue: textField.tag) != nil { return }
        let indexPath = IndexPath(row: textField.tag, section: 1)
        tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
    }
}

    
// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3 // 変更: section2 に研究設定（お天気分）を追加
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        // 変更: 予定セクションに操作方法（追加・サンプル・編集・削除）を明記する。
        if section == 1 { return "予定・安否確認（時刻の5分前から表示 / 右上＋で追加・サンプルで一括追加 / 左スワイプで削除）" } // 変更
        if section == 2 { return "研究設定（お天気分）" } // 追加
        return nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 1 { return schedules.count } // 変更: 予定の件数
        if section == 2 { return 3 } // 追加: 参加者ID / Backend URL / 質問機能
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 追加: section1 は予定1件の入力行（上段: 時刻+文言、下段: チェック要否+曜日）。
        if indexPath.section == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let it = item(at: indexPath.row) ?? ScheduleItem(time: "", text: "", needsCheck: false, weekdays: "1111111")

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
            if let d = f.date(from: it.time) { timePicker.date = d }
            timePicker.addTarget(self, action: #selector(scheduleTimeChanged(_:)), for: .valueChanged)
            timePicker.setContentHuggingPriority(.required, for: .horizontal)

            let textField = UITextField()
            textField.borderStyle = .roundedRect
            textField.placeholder = "文言 / 質問（例: 朝ごはん食べましたか）"
            textField.text = it.text
            textField.delegate = self
            textField.tag = indexPath.row // 変更: 文言のみ。tag は行番号。
            textField.addTarget(self, action: #selector(scheduleFieldChanged(_:)), for: .editingChanged)

            let topStack = UIStackView(arrangedSubviews: [timePicker, textField])
            topStack.axis = .horizontal
            topStack.spacing = 8

            // 追加: 下段 — チェック要否スイッチ + 曜日7ボタン。
            let checkLabel = UILabel()
            checkLabel.text = "チェック"
            checkLabel.font = .systemFont(ofSize: 14)
            checkLabel.setContentHuggingPriority(.required, for: .horizontal)

            let checkSwitch = UISwitch()
            checkSwitch.isOn = it.needsCheck
            checkSwitch.tag = indexPath.row
            checkSwitch.addTarget(self, action: #selector(scheduleCheckChanged(_:)), for: .valueChanged)

            let weekdayStack = UIStackView()
            weekdayStack.axis = .horizontal
            weekdayStack.distribution = .fillEqually
            weekdayStack.spacing = 4
            let names = ["日", "月", "火", "水", "木", "金", "土"]
            let wdChars = Array(it.weekdays.count == 7 ? it.weekdays : "1111111")
            for i in 0..<7 {
                let b = UIButton(type: .system)
                b.setTitle(names[i], for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
                b.layer.cornerRadius = 6
                b.tag = indexPath.row * 10 + i
                b.addTarget(self, action: #selector(scheduleWeekdayTapped(_:)), for: .touchUpInside)
                applyWeekdayButtonStyle(b, on: wdChars[i] == "1")
                b.heightAnchor.constraint(equalToConstant: 32).isActive = true
                weekdayStack.addArrangedSubview(b)
            }

            let bottomStack = UIStackView(arrangedSubviews: [checkLabel, checkSwitch, weekdayStack])
            bottomStack.axis = .horizontal
            bottomStack.spacing = 8
            bottomStack.alignment = .center

            let stack = UIStackView(arrangedSubviews: [topStack, bottomStack])
            stack.axis = .vertical
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

        // 追加: section2 は研究設定（お天気分）。0=参加者ID, 1=Backend URL, 2=質問機能 ON/OFF。
        if indexPath.section == 2 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            if indexPath.row == 2 {
                // 追加: 質問機能 ON/OFF のスイッチ行。
                var config = cell.defaultContentConfiguration()
                config.text = "質問機能"
                config.secondaryText = "お天気分の質問を表示する"
                cell.contentConfiguration = config
                let toggle = UISwitch()
                toggle.isOn = narrativeState.narrativeEnabled // 追加: 現在値を反映
                toggle.accessibilityLabel = "質問機能"
                toggle.addTarget(self, action: #selector(narrativeEnabledChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                return cell
            }

            // 追加: 参加者ID / Backend URL の編集フィールド行（ラベル + テキストフィールド）。
            let titleLabel = UILabel()
            titleLabel.font = .systemFont(ofSize: 15)
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)

            let field = UITextField()
            field.borderStyle = .roundedRect
            field.delegate = self
            field.autocapitalizationType = .none // 追加: ID / URL は自動大文字化しない
            field.autocorrectionType = .no
            if indexPath.row == 0 {
                titleLabel.text = "参加者ID" // 追加
                field.text = narrativeState.participantID // 追加: 現在値を反映（既定 p001）
                field.placeholder = "p001"
                field.tag = NarrativeFieldTag.participantID.rawValue // 追加
            } else {
                titleLabel.text = "Backend URL" // 追加
                field.text = narrativeState.backendBaseURL // 追加: 現在値を反映（空なら送信しない）
                field.placeholder = "http://192.168.x.x:8000" // 追加: 空なら送信しない
                field.keyboardType = .URL
                field.tag = NarrativeFieldTag.backendURL.rawValue // 追加
            }
            field.addTarget(self, action: #selector(narrativeTextChanged(_:)), for: .editingChanged)

            let stack = UIStackView(arrangedSubviews: [titleLabel, field])
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

