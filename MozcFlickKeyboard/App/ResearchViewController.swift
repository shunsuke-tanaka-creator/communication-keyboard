import UIKit
import WebKit
import MozcFlickShared

/// Native opt-ins and answers; detailed timelines/topologies are served by the research dashboard.
final class ResearchViewController: UITableViewController {
    private let state = NarrativeState()
    private var status = "名前を付けずに、場所と生活パターンを自動で学習します。"
    private var question: PendingQuestion?
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "生活の気づき"
        NotificationCenter.default.addObserver(self, selector: #selector(openNotification), name: ResearchNotificationCoordinator.openQuestion, object: nil)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ResearchEventOutbox().flush(baseURL: state.backendBaseURL)
        openNotification()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [4,7,2][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["お天気分を記録", "収集と質問の設定", "状態・傾向・自動マップ"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "天気は気分の4分類です。疲労の点数とは別に記録します。" }
        if section == 1 { return "位置の座標は端末内に保存し、場所IDだけを送ります。通知と背景の実行時刻はiOSにより制限されます。\n" + LocationContextCollector.shared.authorizationDescription }
        return status
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let p = WorkflowPreferences.current
        if indexPath.section == 0 { cell.textLabel?.text = WeatherMood.allCases[indexPath.row].label }
        if indexPath.section == 1 {
            let labels = ["自動質問", "場所の自動分類", "質問通知", "休憩などの提案", "背景の位置検出を許可", "1日の質問上限", "質問の間隔（分）"]
            cell.textLabel?.text = labels[indexPath.row]
            if indexPath.row < 4 {
                let control = UISwitch(); control.tag = indexPath.row
                control.isOn = [state.narrativeEnabled,p.locationEnabled,p.notificationsEnabled,p.interventionsEnabled][indexPath.row]
                control.addTarget(self, action: #selector(toggle(_:)), for: .valueChanged); cell.accessoryView = control
            } else {
                cell.accessoryType = .disclosureIndicator
                if indexPath.row == 5 { cell.detailTextLabel?.text = "\(p.dailyLimit)回（提案\(p.interventionLimit)回まで）" }
                if indexPath.row == 6 { cell.detailTextLabel?.text = "\(p.gapMinutes)分" }
            }
        }
        if indexPath.section == 2 { cell.textLabel?.text = indexPath.row == 0 ? "今の質問に回答" : "履歴・傾向・トポロジーを見る"; cell.accessoryType = .disclosureIndicator }
        return cell
    }
    @objc private func toggle(_ control: UISwitch) {
        var p = WorkflowPreferences.current
        switch control.tag {
        case 0: state.narrativeEnabled = control.isOn
        case 1: LocationContextCollector.shared.enable(control.isOn)
        case 2: ResearchNotificationCoordinator.shared.setEnabled(control.isOn)
        default: p.interventionsEnabled = control.isOn; WorkflowPreferences.current = p
        }
        ResearchNotificationCoordinator.shared.cancelDisallowed()
        ResearchWorkflow.syncPreferences(); tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            let mood = WeatherMood.allCases[indexPath.row]
            let saved = ResearchWorkflow.emit(kind: "weather_mood", payload: ["weather": .string(mood.rawValue)])
            status = saved ? "\(mood.label)を保存しました。通信できるときに同期します。" : "保存できませんでした。もう一度お試しください。"
            tableView.reloadData()
        } else if indexPath.section == 1 {
            if indexPath.row == 4 { LocationContextCollector.shared.requestBackgroundPermission() }
            if indexPath.row == 5 { choose(title: "1日の質問上限", values: [2,3,4,6,8]) { n in var p = WorkflowPreferences.current; p.dailyLimit = n; p.interventionLimit = min(2,n); WorkflowPreferences.current = p } }
            if indexPath.row == 6 { choose(title: "質問の間隔（分）", values: [30,60,90,120]) { n in var p = WorkflowPreferences.current; p.gapMinutes = n; WorkflowPreferences.current = p } }
        } else if indexPath.row == 0 { fetchQuestion() }
        else { navigationController?.pushViewController(ResearchWebViewController(), animated: true) }
    }
    private func choose(title: String, values: [Int], update: @escaping (Int) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        values.forEach { n in alert.addAction(UIAlertAction(title: String(n), style: .default) { _ in update(n); ResearchWorkflow.syncPreferences(); self.tableView.reloadData() }) }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel)); present(alert, animated: true)
    }
    private func fetchQuestion() {
        ResearchEventOutbox().flush(baseURL: state.backendBaseURL) { _ in
            ResearchAPIClient(baseURL: self.state.backendBaseURL).fetchPendingQuestion(participantID: self.state.participantID) { q in
                guard let q = q else { self.status = "今の質問はありません。天気は上の4種類からいつでも記録できます。"; self.tableView.reloadData(); return }
                self.show(q)
            }
        }
    }
    @objc private func openNotification() {
        let defaults = UserDefaults(suiteName: AppConfig.appGroupID)
        guard presentedViewController == nil, let data = defaults?.data(forKey: "research.notificationQuestion"),
              let q = try? NarrativeJSON.decoder.decode(PendingQuestion.self, from: data) else { return }
        defaults?.removeObject(forKey: "research.notificationQuestion")
        if q.expiresAt.map({ $0 > Date() }) ?? true { show(q) } else { fetchQuestion() }
    }
    private func show(_ value: PendingQuestion) {
        guard presentedViewController == nil, state.narrativeEnabled else { return }
        var q = value; q.questionShownAt = Date(); question = q
        ResearchPresentation.record(q)
        ResearchWorkflow.questionState(q, "shown")
        if q.kind == .currentState || q.kind == .nightReflection {
            let form = ResearchAssessmentViewController(daily: q.kind == .nightReflection) { [weak self] values in
                guard let self = self else { return }
                if let values = values {
                    let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                    self.save(value: q.kind == .currentState ? "current_state" : "daily_reflection", text: data.flatMap { String(data: $0, encoding: .utf8) })
                } else { ResearchWorkflow.questionState(q, "deferred") }
            }
            present(UINavigationController(rootViewController: form), animated: true)
            return
        }
        let alert = UIAlertController(title: "お天気分", message: q.prompt, preferredStyle: .alert)
        for option in q.options {
            alert.addAction(UIAlertAction(title: option.label, style: .default) { _ in
                self.save(value: option.value)
            })
        }
        alert.addAction(UIAlertAction(title: "あとで", style: .cancel) { _ in ResearchWorkflow.questionState(q, "deferred") })
        present(alert, animated: true)
    }
    private func save(value: String, text: String? = nil) {
        guard let q = question else { return }
        ResearchWorkflow.annotate(q, value: value)
        NarrativeRepositoryHub(baseURL: state.backendBaseURL).save(NarrativeEvent.make(from: q,
            answer: QuestionAnswer(label: value, freeText: text), typing: nil, answeredAt: Date(), source: "parent_app"))
        question = nil; status = "回答を保存しました。"; tableView.reloadData()
    }
}

final class ResearchWebViewController: UIViewController, WKNavigationDelegate {
    override func loadView() {
        let web = WKWebView(); web.navigationDelegate = self; view = web; title = "生活の気づき"
        let state = NarrativeState()
        if let root = URL(string: state.backendBaseURL) {
            web.load(URLRequest(url: root.appendingPathComponent("research/\(state.participantID)/insights")))
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let alert = UIAlertController(title: "接続できません", message: "サーバーの起動とTailscale接続を確認してください。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: .default)); present(alert, animated: true)
    }
}

/// One scrollable form avoids stacking UIAlertControllers between scale answers.
final class ResearchAssessmentViewController: UITableViewController {
    private let daily: Bool
    private let done: ([String: Int]?) -> Void
    private var values: [String: Int] = [:]
    init(daily: Bool, done: @escaping ([String: Int]?) -> Void) {
        self.daily = daily; self.done = done; super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = daily ? "今日全体の状態" : "今の状態"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "あとで", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(save))
        tableView.rowHeight = UITableView.automaticDimension
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { StateAssessment.keys.count }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "選ばなかった項目は未回答として保存します。" }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let label = UILabel(); label.numberOfLines = 0; label.font = .preferredFont(forTextStyle: .body)
        label.text = StateAssessment.names[indexPath.row] + "（" + (indexPath.row == 0 ? "1：とても悪い／5：とても良い" : indexPath.row == 3 ? "1：とても低い／5：とても高い" : "1：まったくない／5：とても強い") + "）"
        let control = UISegmentedControl(items: ["1","2","3","4","5"]); control.tag = indexPath.row
        control.accessibilityLabel = label.text; control.selectedSegmentIndex = (values[StateAssessment.keys[indexPath.row]].map { $0 - 1 }) ?? UISegmentedControl.noSegment
        control.addTarget(self, action: #selector(selectValue(_:)), for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [label, control]); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -16), stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16)])
        return cell
    }
    @objc private func selectValue(_ sender: UISegmentedControl) { values[StateAssessment.keys[sender.tag]] = sender.selectedSegmentIndex + 1 }
    @objc private func cancel() { dismiss(animated: true) { self.done(nil) } }
    @objc private func save() { dismiss(animated: true) { self.done(self.values) } }
}
