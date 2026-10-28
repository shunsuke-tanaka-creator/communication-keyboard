import UIKit
import MozcFlickShared

/// MacBook is the collector; iPhone only needs an outbound Tailscale connection.
final class LifeLogDashboardViewController: UITableViewController {
    private let state = NarrativeState()
    private let datePicker = UIDatePicker()
    private var dashboard: LifeLogDashboard?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var loading = false
    private var online = false
    private var connectionMessage = "MacBookに接続しています…"
    private var identity = ""
    private var api: LifeLogAPI { LifeLogAPI(baseURL: state.backendBaseURL, participant: state.participantID) }
    private var day: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: datePicker.date)
    }

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); task?.cancel(); NotificationCenter.default.removeObserver(self) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "くらしのログ"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 90
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "研究", style: .plain, target: self, action: #selector(openResearch)),
            UIBarButtonItem(title: "活動を記録", style: .plain, target: self, action: #selector(recordActivity))
        ]
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(settings))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.locale = Locale(identifier: "ja_JP")
        datePicker.timeZone = TimeZone(identifier: "Asia/Tokyo")
        datePicker.maximumDate = Date()
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        let label = UILabel()
        label.text = "振り返る日"
        label.font = .preferredFont(forTextStyle: .headline)
        let stack = UIStackView(arrangedSubviews: [label, datePicker])
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        stack.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 66)
        tableView.tableHeaderView = stack
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let currentIdentity = state.backendBaseURL + "|" + state.participantID
        if identity != currentIdentity { identity = currentIdentity; dashboard = nil; online = false }
        dashboard = dashboard ?? api.cached(day: day)
        refresh()
        startTimer()
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); pause() }
    @objc private func pause() { timer?.invalidate(); timer = nil; task?.cancel(); generation = UUID(); loading = false; refreshControl?.endRefreshing() }
    @objc private func becameActive() {
        guard viewIfLoaded?.window != nil, navigationController?.topViewController === self else { return }
        refresh(); startTimer()
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
    }
    @objc private func openResearch() {
        navigationController?.pushViewController(ResearchDashboardViewController(), animated: true)
    }
    @objc private func settings() { navigationController?.pushViewController(SettingsViewController(), animated: true) }
    @objc private func dateChanged() {
        pause(); dashboard = api.cached(day: day); online = false
        tableView.reloadData(); refresh(); startTimer()
    }
    @objc private func refresh() { datePicker.maximumDate = Date(); load(more: false) }

    private func load(more: Bool) {
        guard !loading else { return }
        loading = true
        let requestID = UUID(); generation = requestID
        let client = api, selectedDay = day
        let offset = more ? dashboard?.nextOffset ?? 0 : 0
        let snapshot = more ? dashboard?.snapshotSeq : nil
        connectionMessage = "同期中…"
        tableView.reloadData()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            if !more { await client.sync() }
            guard !Task.isCancelled, generation == requestID else { return }
            do {
                let result = try await client.dashboard(day: selectedDay, offset: offset, snapshot: snapshot)
                guard !Task.isCancelled, generation == requestID else { return }
                if more, var old = dashboard {
                    let existing = Set(old.timeline.map(\.id))
                    old.timeline += result.timeline.filter { !existing.contains($0.id) }
                    old.nextOffset = result.nextOffset
                    dashboard = old
                } else { dashboard = result }
                online = true
                connectionMessage = "MacBookに接続済み・15秒ごとに更新"
            } catch {
                guard !Task.isCancelled, generation == requestID else { return }
                online = false
                connectionMessage = "接続できません：\(error.localizedDescription)\nMacのサーバーと、両端末のTailscaleを確認してください。"
            }
            loading = false
            refreshControl?.endRefreshing()
            tableView.reloadData()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["接続と同期", "いまの状況（現在時刻）", "SwitchBot（現在の最終観測）", "\(day) のまとめ・日本時間", "1日のタイムライン・新しい順"][section]
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return state.backendBaseURL.isEmpty ? 2 : 1
        case 1: return dashboard?.deviceContext == nil ? 1 : 2
        case 2: return max(dashboard?.devices.count ?? 0, 1)
        case 3: return 1
        default: return max(dashboard?.timeline.count ?? 0, 1) + (dashboard?.nextOffset == nil ? 0 : 1)
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        let offline = online ? "" : "保存済みの情報・現在は未確認\n"
        switch indexPath.section {
        case 0:
            if indexPath.row == 1 {
                content.text = "このMacBookに接続する"
                content.secondaryText = NarrativeState.recommendedBackendURL
                content.image = UIImage(systemName: "link")
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = connectionMessage
                let pending = ResearchSessionQueue().loadAll().count + ResearchEventOutbox().pendingCount
                content.secondaryText = "\(state.backendBaseURL.isEmpty ? "接続先未設定" : state.backendBaseURL)\n参加者：\(state.participantID)・未送信 \(pending)件"
                if let dashboard { content.secondaryText! += "\n最終取得：\(time(dashboard.generatedAt, full: true))" }
                if let scanner = dashboard?.scanner {
                    let label = scanner.state == "scanning" ? "BLE受信中" : scanner.state == "disabled" ? "BLE受信は無効" : "BLE受信を確認してください"
                    content.secondaryText! += "\n\(label)\(scanner.error.map { "：" + $0 } ?? "")"
                }
                content.image = UIImage(systemName: online ? "checkmark.icloud" : "icloud.slash")
            }
        case 1:
            if indexPath.row == 0 {
                content.text = dashboard?.currentActivity.label ?? "現在の活動は不明"
                content.secondaryText = offline + (dashboard.map { "\($0.currentActivity.source)・\(time($0.currentActivity.observedAt))\n\($0.currentActivity.evidence)" } ?? "キーボードを使うか、「活動を記録」で今していることを残せます。")
                content.image = UIImage(systemName: "person.crop.circle")
            } else if let context = dashboard?.deviceContext {
                content.text = "iPhoneの情報（\(time(context.updatedAt, full: true))）"
                content.secondaryText = offline + "歩数：\(context.stepCount.map { String(Int($0)) } ?? "未取得")　歩行距離：\(context.walkingDistanceM.map { String(Int($0)) + "m" } ?? "未取得")\n電池：\(context.batteryLevel.map { String(Int($0 * 100)) + "%" } ?? "未取得")"
                content.image = UIImage(systemName: "iphone")
            }
        case 2:
            if let devices = dashboard?.devices, !devices.isEmpty {
                let device = devices[indexPath.row]
                let stale = device.stale || device.lastSeen.map { Date().timeIntervalSince($0) > 120 } ?? true
                content.text = "\(device.name) · \(stale || !online ? "現在不明" : device.stateLabel)"
                content.secondaryText = "\(stale || !online ? "最終観測：" + device.stateLabel + "\n" : "")電池 \(device.battery.map { "\($0)%" } ?? "不明")・受信 \(time(device.lastSeen, full: true))\nID: \(device.deviceId)\nタップして設置場所を設定"
                content.image = UIImage(systemName: "sensor.tag.radiowaves.forward")
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = "センサーをまだ受信していません"
                content.secondaryText = "玄関・寝室兼作業部屋のセンサーを開閉し、MacのBluetoothが有効か確認してください。受信後、各機器に名前を付けられます。"
                content.image = UIImage(systemName: "sensor")
            }
        case 3:
            content.text = dashboard?.summary.text ?? "この日のログは未取得です"
            content.secondaryText = offline + "受信した記録の要約です。入力セッションは終了日の集計です。記録のない時間の活動は分かりません。"
            content.image = UIImage(systemName: "sun.max")
        default:
            let items = dashboard?.timeline ?? []
            if indexPath.row < items.count {
                let item = items[indexPath.row]
                content.text = "\(time(item.occurredAt))  \(item.title)"
                content.secondaryText = "\(item.source)\n\(item.detail)"
                content.image = UIImage(systemName: item.kind == "session" ? "keyboard" : item.kind == "switchbot" ? "door.left.hand.closed" : "text.bubble")
                cell.accessoryType = .disclosureIndicator
            } else if !items.isEmpty {
                content.text = "前の記録を読み込む"
                content.secondaryText = "\(items.count) / \(dashboard?.totalEvents ?? 0)件"
            } else {
                content.text = "記録はありません"
                content.secondaryText = "日付を変えるか、下に引いて更新してください。"
            }
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, indexPath.row == 1 {
            state.backendBaseURL = NarrativeState.recommendedBackendURL
            refresh()
        } else if indexPath.section == 2, let devices = dashboard?.devices, indexPath.row < devices.count {
            rename(devices[indexPath.row])
        } else if indexPath.section == 4, let items = dashboard?.timeline {
            if indexPath.row < items.count {
                navigationController?.pushViewController(LifeLogDetailViewController(api: api, item: items[indexPath.row]), animated: true)
            } else if dashboard?.nextOffset != nil { load(more: true) }
        }
    }

    @objc private func recordActivity() {
        let alert = UIAlertController(title: "今、何をしていますか？", message: "回答は時刻と一緒に保存され、通信が戻るとMacに同期されます。", preferredStyle: .actionSheet)
        for category in ResearchActivityCatalog.categories {
            alert.addAction(UIAlertAction(title: category.label, style: .default) { [weak self] _ in self?.chooseActivity(category) })
        }
        alert.addAction(UIAlertAction(title: "自由に入力", style: .default) { [weak self] _ in self?.freeActivity() })
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        present(alert, animated: true)
    }
    private func chooseActivity(_ category: ResearchActivityCategory) {
        let alert = UIAlertController(title: category.label, message: nil, preferredStyle: .actionSheet)
        for activity in category.activities {
            alert.addAction(UIAlertAction(title: activity.label, style: .default) { [weak self] _ in self?.saveActivity(activity.label, value: activity.value) })
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        present(alert, animated: true)
    }
    private func freeActivity() {
        let alert = UIAlertController(title: "活動を記録", message: "例：寝室兼作業部屋で研究している", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "今していること" }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            self?.saveActivity(String(text.prefix(500)))
        })
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        present(alert, animated: true)
    }
    private func saveActivity(_ text: String, value: String? = nil) {
        let now = Date()
        let event = NarrativeEvent(eventID: UUID().uuidString, participantID: state.participantID, source: "parent_app", eventType: "activity_report", detectedAt: now, questionShownAt: now, answeredAt: now,
                                   context: ContextSnapshot(timeOfDay: TimeOfDay.label(for: now), typingActive: false, calendarBusy: false, externalTrigger: nil),
                                   question: .init(kind: .activityCheck, prompt: "今、何をしていますか？"), answer: .init(label: value, freeText: text))
        guard ResearchEventOutbox().enqueue(event, route: "api/narrative-events", id: event.eventID) else {
            showError("端末への保存に失敗しました。App Group設定と空き容量を確認してください。"); return
        }
        NarrativeStore().appendNarrative(event)
        pause(); refresh(); startTimer()
        let alert = UIAlertController(title: "活動を端末に保存しました", message: text + "\n通信できるときにMacへ同期します。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    private func rename(_ device: LifeLogDashboard.Device) {
        let alert = UIAlertController(title: "設置場所を設定", message: "ID: \(device.deviceId)\n一方のドアだけを開閉して、表示が変わった機器を選んでください。", preferredStyle: .alert)
        alert.addTextField { $0.text = device.name; $0.placeholder = "玄関 / 寝室兼作業部屋" }
        for name in ["玄関", "寝室兼作業部屋"] {
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in self?.applyName(name, device: device) })
        }
        alert.addAction(UIAlertAction(title: "入力した名前で保存", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            self?.applyName(String(name.prefix(100)), device: device)
        })
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        present(alert, animated: true)
    }
    private func applyName(_ name: String, device: LifeLogDashboard.Device) {
        Task { @MainActor in
            do { try await api.rename(device: device.deviceId, name: name); refresh() }
            catch { showError(error.localizedDescription) }
        }
    }
    private func showError(_ text: String) {
        let alert = UIAlertController(title: "保存できませんでした", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    private func time(_ date: Date?, full: Bool = false) -> String {
        guard let date else { return "未取得" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = full ? "M/d HH:mm:ss" : "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private final class LifeLogDetailViewController: UIViewController {
    private let api: LifeLogAPI
    private let item: LifeLogDashboard.Timeline
    init(api: LifeLogAPI, item: LifeLogDashboard.Timeline) { self.api = api; self.item = item; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.title
        let text = UITextView()
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.backgroundColor = .systemBackground
        text.text = "記録を読み込んでいます…"
        view = text
        Task { @MainActor in
            do { text.text = try await api.detail(item) }
            catch { text.text = "詳細を取得できませんでした。\n" + error.localizedDescription }
        }
    }
}
