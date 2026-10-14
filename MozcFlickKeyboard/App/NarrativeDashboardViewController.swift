// NarrativeDashboardViewController.swift
// MozcFlickKeyboard — 追加: ホストアプリ「お天気分」ダッシュボード画面。
//
// 当日の micro-diary 記録（起床 / 朝の気分 / 外出 / 帰宅 / 夜の振り返り / 回答数）を一覧表示し、
// 手動イベント（起きた / 外出した / 帰宅した / 寝る）を NarrativeState.enqueueManualEvent で登録する。
// さらに保存済み NarrativeEvent を JSON / CSV で UIActivityViewController により書き出す。
// UIKit のみ・insetGrouped・プログラム Auto Layout で既存 App 画面（RootViewController 等）に揃える。

import UIKit
import MozcFlickShared // 追加: NarrativeState / NarrativeStore / NarrativeExport / ManualEvent 等を利用

/// 「お天気分」ダッシュボード。
final class NarrativeDashboardViewController: UIViewController {

    /// 追加: 画面のセクション定義。
    private enum Section: Int, CaseIterable {
        case today   // 今日の記録
        case sensor  // 追加: 疑似センサー受信状態
        case test    // 追加: 疑似センサーテスト（アプリ内から直接注入）
        case manual  // 手動イベント
        case export  // エクスポート
    }

    /// 追加: 今日の記録セクションに出す1行（タイトルと値）。
    private struct SummaryRow {
        let title: String
        let value: String
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    /// 追加: 出題制御・研究設定の状態ストア（App Group 共有）。
    private let state = NarrativeState()
    /// 追加: JSONL 読み出し用ストア。
    private let store = NarrativeStore()

    /// 追加: 疑似センサーのアプリ内注入に使うルーター（HTTP 受信と同じ経路を通す）。
    private lazy var sensorRouter = SensorEventRouter(state: state, store: store)

    /// 追加: 今日の記録セクションの行データ。viewWillAppear で再計算する。
    private var summaryRows: [SummaryRow] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "お天気分" // 追加: 画面タイトル
        view.backgroundColor = .systemBackground // ダークモード追従
        setupTableView() // 追加: テーブル構築
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSummary() // 追加: 表示のたびに当日記録を再計算して反映
        // 追加: 疑似センサーの受信を検知したら、その場で当日記録と受信状態を更新する。
        SensorHTTPServer.shared.onEventReceived = { [weak self] event in
            NSLog("[MFK-Sensor] dashboard refresh by type=\(event.type)") // 追加: 受信反映のデバッグ
            self?.reloadSummary()
        }
    }

    /// 追加: 画面を離れるときはコールバックを外す（他画面での不要な更新を避ける）。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SensorHTTPServer.shared.onEventReceived = nil
    }

    /// 追加: テーブルビューを構築する（既存 App 画面と同じ流儀）。
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

    // MARK: - 今日の記録の集計

    /// 追加: 当日の NarrativeEvent / ContextEvent / NarrativeState から今日の記録行を組み立てて再描画する。
    private func reloadSummary() {
        let today = Date()
        let events = store.narrativeEvents(on: today) // 追加: 当日の回答済みイベント
        let contexts = store.contextEvents(on: today) // 追加: 当日の文脈イベント（起床など）

        // 追加: 指定 kind の回答済みイベントのうち最新の回答ラベルを返す（無ければ nil）。
        func latestAnswerLabel(_ kind: QuestionKind) -> String? {
            let matched = events.filter { $0.question.kind == kind }
            guard let last = matched.last else { return nil }
            return last.answer.label ?? last.answer.freeText
        }

        // 追加: 起床 — wake_up の文脈イベントがあればその時刻、無ければ当日初回キーボード利用時刻。
        let wakeContext = contexts.first { $0.eventType == ManualEvent.wakeUp.rawValue }
        let wakeDate = wakeContext?.detectedAt ?? state.firstKeyboardUseDate(on: today)
        summaryRows = [] // 追加: 毎回作り直す

        let timeFormatter = DateFormatter() // 追加: 時刻表示用
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        let wakeValue = wakeDate.map { timeFormatter.string(from: $0) } ?? "—"
        summaryRows.append(SummaryRow(title: "起床", value: wakeValue)) // 追加

        // 追加: 朝の気分 — morningMood の回答ラベル。
        summaryRows.append(SummaryRow(title: "朝の気分", value: latestAnswerLabel(.morningMood) ?? "—"))

        // 追加: 外出 — outingDestination の回答件数と最新の行き先。
        let outingEvents = events.filter { $0.question.kind == .outingDestination }
        let outingValue = outingEvents.isEmpty
            ? "—"
            : "\(outingEvents.count)回 / \(latestAnswerLabel(.outingDestination) ?? "—")"
        summaryRows.append(SummaryRow(title: "外出", value: outingValue)) // 追加

        // 追加: 帰宅 — outingEvaluation の最新回答。
        summaryRows.append(SummaryRow(title: "帰宅", value: latestAnswerLabel(.outingEvaluation) ?? "—"))

        // 追加: 夜の振り返り — nightReflection の回答ラベル。
        summaryRows.append(SummaryRow(title: "夜の振り返り", value: latestAnswerLabel(.nightReflection) ?? "—"))

        // 追加: 回答した質問数 — 当日の回答総数（NarrativeState 集計）。
        summaryRows.append(SummaryRow(title: "回答した質問数", value: "\(state.answeredCount(on: today))"))

        tableView.reloadData() // 追加: 再描画
    }

    // MARK: - 手動イベント

    /// 追加: 手動イベントを1件キューへ積み、確認アラートを出して再描画する。
    private func recordManualEvent(_ event: ManualEvent) {
        state.enqueueManualEvent(event, at: Date()) // 追加: キーボードが次回拾う手動イベントキューへ積む
        NSLog("[MFK-Narrative] dashboard manualEvent=\(event.rawValue)") // デバッグ: 手動イベント記録
        let alert = UIAlertController(title: "記録しました",
                                      message: "「\(event.displayName)」を記録しました。",
                                      preferredStyle: .alert) // 追加: 簡易確認
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        reloadSummary() // 追加: 記録後に再描画
    }

    // MARK: - 追加: 疑似センサーのアプリ内注入（テストモード）

    /// 追加: プリセットを SensorEventRouter へ直接流す。HTTP を経由しないので Mac / 同一 Wi-Fi 不要。
    /// Python CLI と同じ type / value・同じ Router を通るため、挙動は実際の受信と完全に同じになる。
    private func injectSensorPreset(_ preset: SensorPreset) {
        let event = preset.makeEvent() // 追加: タップ時刻でイベント生成
        let result = sensorRouter.route(event) // 追加: 振り分け（キュー投入 + ContextEvent 保存）
        NSLog("[MFK-Sensor] dashboard inject type=\(event.type) value=\(event.value ?? "-")") // 追加: デバッグ

        // 追加: 何が起きたか（次にどの質問が出るか）をユーザーへ明示する。
        var detail: String
        if let manual = result.manualEvent {
            detail = "「\(manual.displayName)」として記録しました。次にキーボードを開くと質問が出ます。"
        } else if let kind = result.pendingKind {
            detail = "質問「\(QuestionCatalog.template(for: kind).prompt)」を予約しました。次にキーボードを開くと出ます。"
        } else {
            detail = "文脈として記録しました（質問は出ません）。"
        }
        let alert = UIAlertController(title: "注入しました：\(preset.title)",
                                      message: detail,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        reloadSummary() // 追加: 受信表示・当日記録を更新
    }

    // MARK: - エクスポート

    /// 追加: 保存済み全ファイルの NarrativeEvent を集めて返す。
    private func gatherAllEvents() -> [NarrativeEvent] {
        var all: [NarrativeEvent] = []
        for url in store.allNarrativeFileURLs() {
            // 追加: NarrativeStore は日付単位の API しか公開していないため、ファイル名の日付でまとめて読み出す。
            guard let date = dateFromNarrativeFile(url) else { continue }
            all.append(contentsOf: store.narrativeEvents(on: date))
        }
        return all
    }

    /// 追加: "narrative_yyyyMMdd.jsonl" のファイル名から Date を復元する。
    private func dateFromNarrativeFile(_ url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent // narrative_yyyyMMdd
        let stamp = name.replacingOccurrences(of: "narrative_", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.date(from: stamp)
    }

    /// 追加: JSON / CSV いずれかで書き出して共有シートを出す。
    private func export(asJSON: Bool) {
        let events = gatherAllEvents() // 追加: 全ファイルの記録を対象にする
        guard !events.isEmpty else {
            NSLog("[MFK-Narrative] export skipped: no events") // デバッグ: 記録なし
            let alert = UIAlertController(title: "記録がありません", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory // 追加: 一時ファイル置き場
        let url: URL
        let data: Data?
        if asJSON {
            url = tmpDir.appendingPathComponent("narrative_export.json") // 追加
            data = NarrativeExport.json(events: events) // 追加: JSON 生成
        } else {
            url = tmpDir.appendingPathComponent("narrative_export.csv") // 追加
            data = NarrativeExport.csv(events: events).data(using: .utf8) // 追加: CSV 生成
        }

        guard let data else {
            NSLog("[MFK-Narrative] export failed: encode error asJSON=\(asJSON)") // デバッグ: 生成失敗
            let alert = UIAlertController(title: "書き出しに失敗しました", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        try? data.write(to: url) // 追加: 一時ファイルへ書き出し
        NSLog("[MFK-Narrative] export asJSON=\(asJSON) count=\(events.count) file=\(url.lastPathComponent)") // デバッグ: 書き出し

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil) // 追加: 共有シート
        activity.popoverPresentationController?.sourceView = view // 追加: iPad の popover 起点
        present(activity, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension NarrativeDashboardViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count // 変更: 今日の記録 / 疑似センサー / 手動イベント / エクスポート
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .today:  return "今日の記録" // 追加
        case .sensor: return "疑似センサー（このアプリを開いている間だけ受信）" // 追加
        case .test:   return "疑似センサーテスト（Mac不要・タップで直接注入）" // 追加
        case .manual: return "手動イベント" // 追加
        case .export: return "エクスポート" // 追加
        case .none:   return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .today:  return summaryRows.count // 追加
        case .sensor: return 2 // 追加: 稼働状態 / 最後の受信
        case .test:   return SensorPreset.all.count // 追加: プリセット8種
        case .manual: return ManualEvent.allCases.count // 追加: 4ボタン
        case .export: return 2 // 追加: JSON / CSV
        case .none:   return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .none // 追加: 既定はアクセサリなし
        switch Section(rawValue: indexPath.section) {
        case .today:
            // 追加: タイトルと値（value スタイル）で表示。タップ不可。
            var config = UIListContentConfiguration.valueCell()
            let row = summaryRows[indexPath.row]
            config.text = row.title
            config.secondaryText = row.value
            cell.contentConfiguration = config
            cell.selectionStyle = .none
        case .sensor:
            // 追加: 疑似センサーの受信状態（0=稼働状態と接続先、1=最後に受けたイベント）。
            var config = UIListContentConfiguration.valueCell()
            if indexPath.row == 0 {
                config.text = "受信状態"
                let running = SensorHTTPServer.shared.isRunning
                let ip = SensorHTTPServer.currentWiFiIPAddress() ?? "IP取得不可"
                // 追加: OFF のときは設定への誘導、ON のときは接続先を出す。
                if !state.sensorReceiveEnabled {
                    config.secondaryText = "OFF（設定で有効化）"
                } else {
                    config.secondaryText = "\(running ? "受信中" : "停止中") \(ip):\(state.sensorPort)"
                }
            } else {
                config.text = "最後の受信"
                // 追加: 未受信なら "—"、受信済みなら「type=value HH:mm:ss」を出す。
                if state.lastSensorEvent.isEmpty {
                    config.secondaryText = "—"
                } else {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "HH:mm:ss"
                    let time = state.lastSensorEventAt.map { f.string(from: $0) } ?? ""
                    config.secondaryText = "\(state.lastSensorEvent) \(time)"
                }
            }
            cell.contentConfiguration = config
            cell.selectionStyle = .none
        case .test:
            // 追加: 疑似センサーのプリセット注入ボタン行。Mac が無くても同じ経路（Router）で試せる。
            var config = cell.defaultContentConfiguration()
            let preset = SensorPreset.all[indexPath.row]
            config.text = preset.title
            // 追加: 実際に送られる type=value を副題に出し、Python CLI との対応が分かるようにする。
            config.secondaryText = preset.value.map { "\(preset.type)=\($0)" } ?? preset.type
            config.textProperties.color = .systemBlue
            cell.contentConfiguration = config
            cell.selectionStyle = .default
        case .manual:
            // 追加: 手動イベントボタン行。
            var config = cell.defaultContentConfiguration()
            config.text = ManualEvent.allCases[indexPath.row].displayName
            config.textProperties.color = .systemBlue
            cell.contentConfiguration = config
            cell.selectionStyle = .default
        case .export:
            // 追加: エクスポート行（0=JSON, 1=CSV）。
            var config = cell.defaultContentConfiguration()
            config.text = indexPath.row == 0 ? "JSONで書き出し" : "CSVで書き出し"
            config.textProperties.color = .systemBlue
            cell.contentConfiguration = config
            cell.selectionStyle = .default
        case .none:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .test:
            injectSensorPreset(SensorPreset.all[indexPath.row]) // 追加: 疑似センサーを直接注入
        case .manual:
            recordManualEvent(ManualEvent.allCases[indexPath.row]) // 追加: 手動イベント登録
        case .export:
            export(asJSON: indexPath.row == 0) // 追加: JSON / CSV 書き出し
        default:
            break // 今日の記録はタップ操作なし
        }
    }
}
