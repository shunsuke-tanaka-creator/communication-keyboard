// KeyboardViewController.swift
// MozcFlickKeyboard — Custom Keyboard Extension の基盤 UIInputViewController。
//
// 責務:
//  - 12キーフリック UI（KeyboardView）を container view に差し込む。
//  - KeyboardView から届く入力イベント（KeyboardActionDelegate 経由）を InputState / 変換エンジンで処理し、
//    確定文字列を UITextDocumentProxy へ反映する。
//  - 地球儀キーによるキーボード切替。入力・変換は Full Access 不要。
//    変更: 入力ログ・学習・ユーザー辞書・お天気分・触覚・研究サーバー送信は Full Access 有効時のみ動く。
//
// 未確定文字列の扱い:
//  - 変更: UITextDocumentProxy には marked text 相当の API が無いため、未確定よみ（変換中は選択中の文節列）を
//    syncInline で入力欄へ実際に挿入し、変化のたびに差分だけ deleteBackward / insertText する（擬似インライン表示）。
//    確定時は挿入済みの未確定分を消してから確定文字列を insertText する。
//    詳細は docs/ios-keyboard-limitations.md 参照。

import UIKit
import MozcFlickShared // 追加: 共有フレームワークの型（InputState/エンジン/AppConfig 等）を利用

/// App Group の UserDefaults に保存する設定値のキーを集約する。
/// ホストアプリ側の SettingsViewController と同じ文字列を用いること。
enum SettingsKeys {
    static let toggleInputEnabled = "toggleInputEnabled"
    static let flickOnlyEnabled = "flickOnlyEnabled"
    static let learningEnabled = "learningEnabled"
    static let privateModeEnabled = "privateModeEnabled"
    static let schedules = "schedules"         // 変更: 予定の配列。各要素は TSV "HH:mm\t文言\tチェック要否(0/1)\t曜日ビット7桁"（旧 "HH:mm\t文言" も読める）。
}

final class KeyboardViewController: UIInputViewController {

    // MARK: - 状態

    /// 変換状態管理。エンジンを注入して駆動する。
    /// 既定は Mozc 未リンクでも動作する LocalStubEngine。MOZC_AVAILABLE 時は MozcConversionEngine を使う。
    private lazy var inputState: InputState = {
        let engine: JapaneseConversionEngine
        #if MOZC_AVAILABLE
        let mozc = MozcConversionEngine()
        engine = mozc.isMozcAvailable ? mozc : LocalStubEngine()
        NSLog("[MFK] engine = MozcConversionEngine (MOZC_AVAILABLE=ON) isMozcAvailable=\((engine as? MozcConversionEngine)?.isMozcAvailable ?? false)") // 追加: エンジン種別のデバッグ
        #else
        engine = LocalStubEngine()
        NSLog("[MFK] engine = LocalStubEngine (MOZC_AVAILABLE=OFF)") // 追加: エンジン種別のデバッグ
        #endif
        let personalized = PersonalizedConversionEngine(base: engine,
            dictionaryEntries: { [weak self] reading in
                self?.userDictionary?.search(prefix: reading, enabledOnly: true) ?? []
            }, learningScores: { [weak self] reading in
                guard let store = self?.learningStore, store.isLearningEnabled, !store.isPrivateMode else { return [:] }
                return store.scores(forReading: reading)
            }, recordSelection: { [weak self] reading, word in
                guard let self else { return }
                do {
                    try self.learningStore?.recordSelection(reading: reading, word: word,
                        isSecureInput: self.textDocumentProxy.isSecureTextEntry ?? false)
                } catch { NSLog("[MFK] Could not save candidate learning: %@", String(describing: error)) }
            })
        return InputState(engine: personalized)
    }()

    private var userDictionary: UserDictionaryStore?
    private var learningStore: LearningStore?

    /// 12キー UI 本体。
    private let keyboardView = KeyboardView()

    /// App Group 共有の UserDefaults。設定値の参照に使う。
    private let sharedDefaults = UserDefaults(suiteName: AppConfig.appGroupID)

    /// 追加: いま入力欄へインライン挿入している未確定文字列（擬似 marked text）。
    /// UITextDocumentProxy に marked text API が無いため、未確定よみを実挿入して Simeji 風に見せる。
    /// composition が変わるたびにこの値との差分を取り、古い分を削除して新しい分を入れ直す。
    private var pendingComposition = ""

    /// 追加: 入力イベントをセッション単位で記録するロガー。
    private let sessionLogger = SessionLogger()

    /// 追加: このセッションの変換要求回数（メタ情報）。
    private var conversionCount = 0

    /// 追加: いま表示中の安否確認チェック対象（押下時にログへ記録する）。
    private var pendingCheck: ScheduleItem?

    /// 追加: 1分間隔で予定を再判定するタイマー。表示中のみ稼働。
    private var checkTimer: Timer?

    // MARK: - お天気分（Narrative）状態

    /// 追加: 出題制御の状態ストア（App Group UserDefaults）。
    private let narrativeState = NarrativeState()

    /// 追加: Trigger 評価の司令塔（makeDefault で構築）。
    private lazy var narrativeEngine: TriggerEngine = TriggerEngine.makeDefault(state: narrativeState)

    /// 変更: NarrativeEvent / ContextEvent の唯一の保存入口（ローカル必須 + v0.1 サーバーへ best-effort 送信）。
    private var narrativeRepo: NarrativeRepositoryHub { NarrativeRepositoryHub(baseURL: narrativeState.backendBaseURL) }

    /// 追加: 打鍵特徴の集計器（本文は渡さず時刻・回数のみ）。
    private let typingMetrics = TypingMetrics()

    /// 追加: 研究用端末Contextと端末IDの共有ストア（親アプリが書き、ここで送信時に読む）。
    private let researchContextStore = ResearchContextStore()

    /// 追加: 回答の解析器（Mock、ルールベース）。
    private let narrativeAnalyzer = MockNarrativeAnalyzer()

    /// 追加: PMTT ノード対応付け（Mock、同期）。
    private let narrativePMTT = MockPMTTAdapter()

    /// 追加: いまバナーに表示中の質問（回答保存で参照）。
    private var currentPending: PendingQuestion?

    /// 追加: 研究入力モード（自由記述）中か。true の間は通常入力を proxy へ流さない。
    private var researchInputMode = false

    /// 追加: 研究入力モードの下書きバッファ（本文はここだけに溜め、proxy には出さない）。
    private var researchDraft = ""

    /// 追加: 自由入力に入る直前に選ばれていた選択肢 value（未選択なら nil）。決定時に answer.label へ入れる。
    private var researchChosenOptionValue: String?

    /// 追加: 活動質問の2段階選択で、現在開いている大分類。
    private var selectedActivityCategory: ResearchActivityCategory?

    /// 追加: 夜の5段階振り返りで集めた回答と、いま何項目目か。
    private var dailyScaleAnswers: [String: Int] = [:]
    private var dailyScaleIndex = 0

    /// 追加: 夜の振り返り5項目（key / 質問文 / 1の意味 / 5の意味）。
    private let dailyScaleItems: [(key: String, prompt: String, low: String, high: String)] = [
        ("mood", "今日の気分は？", "とても悪い", "とても良い"),
        ("fatigue", "今日の疲労は？", "まったくない", "とても強い"),
        ("stress", "今日のストレスは？", "まったくない", "とても強い"),
        ("concentration", "今日の集中度は？", "とても低い", "とても高い"),
        ("sleepiness", "今日の眠気は？", "まったくない", "とても強い"),
    ]

    // MARK: - ライフサイクル

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("[MFK] viewDidLoad KeyboardViewController loaded") // 追加: 拡張起動確認のデバッグ
        print("[MFK-print] viewDidLoad KeyboardViewController loaded") // 追加: NSLogが出ない場合の確認用 print
        view.backgroundColor = KeyboardAppearance.canvas // キー領域と Safe Area の色を統一
        setupKeyboardView()
        // 追加: 安否確認チェックボタン押下時の処理を配線する。
        keyboardView.onCheck = { [weak self] in self?.didTapSafetyCheck() }
        wireNarrativeCallbacks() // 追加: お天気分バナーのコールバックを配線する
        // 追加: セッション終了（非表示 or 60秒無入力）で送信キューへ積む。
        sessionLogger.onSessionClosed = { [weak self] session in
            self?.uploadClosedSession(session)
        }
        applySettings()
        enableLoggingIfAllowed() // 追加: viewWillAppear が呼ばれない場合に備え、ここでも記録を有効化。
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }

    // 変更: キーボードを開いたときに「次の予定」を1回だけ表示する（時刻トリガーはやめた）。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySettings()
        updateInfoBar()
        startCheckTimer() // 追加: 表示中は1分間隔で予定を再判定する。
        // 追加: セッション記録を有効化（プライベートモード ON のときは記録しない）。
        let started = enableLoggingIfAllowed()
        if started {
            // セッション開始時のメタ情報（入力欄の種別など取得可能なものを記録）。
            sessionLogger.log(type: "meta", data: [
                "keyboardType": "\(textDocumentProxy.keyboardType?.rawValue ?? -1)",
                "returnKeyType": "\(textDocumentProxy.returnKeyType?.rawValue ?? -1)",
                "hasFullAccess": "\(hasFullAccess)",
                "inputMode": "\(inputState.inputMode)",
            ])
        }
        NSLog("[MFK] viewWillAppear session started=\(started)") // 追加: セッション開始のデバッグ
        narrativeRepo.flushUnsent() // 追加: オフライン退避分の回答があれば再送を試みる
        ResearchAPIClient(baseURL: narrativeState.backendBaseURL).flushPendingSessions() // 追加: 未送信セッションを再送
        evaluateNarrativeTriggers() // 変更: サーバー最新質問を優先し、無ければローカルTriggerへフォールバック
    }

    /// 追加: プライベートモード OFF のときだけ記録を有効化する共通ヘルパ。
    /// - Returns: 有効化した(=記録する)なら true。
    @discardableResult
    private func enableLoggingIfAllowed() -> Bool {
        let isPrivate = sharedDefaults?.bool(forKey: SettingsKeys.privateModeEnabled) ?? false
        guard hasFullAccess, !isPrivate else { return false } // 変更: Full Access が無ければ記録しない
        conversionCount = 0
        sessionLogger.enable()
        return true
    }

    /// 追加: キーボードが閉じたらセッションを終了しファイルを閉じる。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopCheckTimer() // 追加: 表示中のみ稼働するタイマーを止める。
        sessionLogger.log(type: "meta", data: ["conversionCount": "\(conversionCount)"])
        sessionLogger.stop(reason: "keyboard_hidden") // 変更: 終了理由を付けて閉じる（送信コールバックが走る）
        NSLog("[MFK] viewDidDisappear session stopped conversionCount=\(conversionCount)") // 追加: セッション終了のデバッグ
    }

    /// 追加: 終了セッションへ打鍵特徴と親アプリ由来Contextを付け、再送キュー経由で送る。
    private func uploadClosedSession(_ session: LoggedSession) {
        let typing = typingMetrics.snapshot(now: session.endedAt)
        typingMetrics.reset()
        let payload = ResearchSessionUpload(sessionID: session.sessionID,
                                            participantID: narrativeState.participantID,
                                            deviceID: researchContextStore.deviceID,
                                            startedAt: session.startedAt,
                                            endedAt: session.endedAt,
                                            closeReason: session.closeReason,
                                            events: session.events,
                                            typing: typing,
                                            context: researchContextStore.load())
        NSLog("[MFK-Research] session closed id=\(session.sessionID) reason=\(session.closeReason) events=\(session.events.count)") // 追加: デバッグ
        ResearchAPIClient(baseURL: narrativeState.backendBaseURL).upload(payload)
    }

    /// 変更: 予定配列から表示内容を決める。判定順は「安否確認チェック対象 → 次の予定」。
    /// チェック対象（needsCheck かつ 当日曜日 かつ 5分前〜+30分 かつ 当日未チェック）があれば
    /// 時刻が早い1件を質問文 + チェックボタンで表示する。無ければ従来どおり「次の予定」を表示する。
    private func updateInfoBar() {
        let list = sharedDefaults?.stringArray(forKey: SettingsKeys.schedules) ?? []
        let items = ScheduleItem.parse(list)
        let now = Date()
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        // 追加: 安否確認チェック対象を最優先で判定する。
        let checked = SafetyCheckLog.checkedKeys(on: now)
        // 追加: 各予定がなぜチェック対象になる/ならないかを可視化するデバッグログ。
        for it in items {
            NSLog("[MFK] schedule item time=\(it.time) text='\(it.text)' needsCheck=\(it.needsCheck) weekdays=\(it.weekdays) active=\(it.isActive(on: now)) inWindow=\(it.isInWindow(nowMinutes: nowMinutes)) checked=\(checked.contains(it.logKey)) nowMinutes=\(nowMinutes)")
        }
        let target = items
            .filter { $0.needsCheck && $0.isActive(on: now) && $0.isInWindow(nowMinutes: nowMinutes) && !checked.contains($0.logKey) }
            .sorted { ($0.minutes ?? 0) < ($1.minutes ?? 0) }
            .first

        if let t = target {
            pendingCheck = t
            keyboardView.setCheckPrompt(t.text.isEmpty ? "確認してください" : t.text)
            NSLog("[MFK] updateInfoBar check target=\(t.logKey)") // 追加: チェック対象のデバッグ
            return
        }

        // チェック対象なし → 従来の「次の予定」表示に戻す。
        pendingCheck = nil
        keyboardView.clearCheckPrompt()
        var next: ScheduleItem?
        for item in items {
            guard let m = item.minutes, m >= nowMinutes else { continue } // 過去はスキップ
            if next == nil || m < (next?.minutes ?? Int.max) {
                next = item
            }
        }
        if let n = next {
            keyboardView.setInfoText("次の予定 \(n.time) \(n.text)")
        } else {
            keyboardView.setInfoText("")
        }
        NSLog("[MFK] updateInfoBar next=\(String(describing: next?.logKey))") // 追加: 次の予定のデバッグ
    }

    /// 追加: 安否確認のチェックボタンが押されたときの処理。ログへ記録し表示を消す。
    private func didTapSafetyCheck() {
        guard let item = pendingCheck else { return }
        SafetyCheckLog.append(item)
        sessionLogger.log(type: "safetyCheck", data: ["scheduled": item.time, "question": item.text])
        NSLog("[MFK] didTapSafetyCheck logged=\(item.logKey)") // 追加: チェック記録のデバッグ
        pendingCheck = nil
        keyboardView.clearCheckPrompt() // 追加: 押したら即座に表示を消す
        updateInfoBar() // 次の対象へ切替（無ければ「次の予定」表示に戻る）
    }

    /// 追加: 1分間隔で updateInfoBar を呼ぶタイマーを開始する。
    private func startCheckTimer() {
        stopCheckTimer()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateInfoBar()
            self?.evaluateNarrativeTriggers() // 追加: 60秒ごとにお天気分の出題判定も回す（夜トリガー等の時刻到達に対応）
        }
    }

    /// 追加: タイマーを停止する。
    private func stopCheckTimer() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // keyboardType / returnKeyType に応じて UI を切り替えられるフック。
        // 数字・電話・URL 入力欄などでは変換を無効化するのが自然（今後の拡張点）。
    }

    // MARK: - UI 構築

    private func setupKeyboardView() {
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.actionDelegate = self
        view.addSubview(keyboardView)

        let guide = view.safeAreaLayoutGuide // SafeArea 考慮
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: guide.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
        // 追加: キーボード全体の高さは可変制約で管理する。ベースを 290pt にして各キーの高さを約46ptに確保し、
        //       バナー表示時はその分だけ上乗せしてキー領域が縮まないようにする。
        let baseHeight: CGFloat = 290
        let hc = keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: baseHeight)
        hc.priority = .required
        hc.isActive = true
        keyboardHeightConstraint = hc // 追加: バナー表示で更新するため保持
        keyboardBaseHeight = baseHeight // 追加: 上乗せ計算の基準
        // 追加: バナー高さ変化をキーボード全体の高さへ反映する（キーを縮めずバナー分だけ背を高くする）。
        keyboardView.onRequiredExtraHeightChanged = { [weak self] extra in
            guard let self = self else { return }
            self.keyboardHeightConstraint?.constant = self.keyboardBaseHeight + extra // 追加: ベース + バナー分
        }
    }

    /// 追加: キーボード全体の高さ制約。バナー表示時に定数を増やす。
    private var keyboardHeightConstraint: NSLayoutConstraint?
    /// 追加: バナー非表示時の基準高さ。
    private var keyboardBaseHeight: CGFloat = 260

    /// App Group の設定を UI / 状態へ反映する。
    private func applySettings() {
        let d = sharedDefaults
        // 既定値: トグル ON / フリックのみ OFF / 学習 ON。
        let toggle = d?.object(forKey: SettingsKeys.toggleInputEnabled) as? Bool ?? true
        let flickOnly = d?.bool(forKey: SettingsKeys.flickOnlyEnabled) ?? false
        inputState.toggleInputEnabled = toggle
        inputState.flickOnlyEnabled = flickOnly
        let learning = d?.object(forKey: SettingsKeys.learningEnabled) as? Bool ?? true
        let isPrivate = d?.bool(forKey: SettingsKeys.privateModeEnabled) ?? false
        // Reload when the extension reappears so host-app dictionary changes are visible.
        userDictionary = hasFullAccess ? try? UserDictionaryStore() : nil
        learningStore = hasFullAccess ? try? LearningStore() : nil
        learningStore?.isLearningEnabled = learning
        learningStore?.isPrivateMode = isPrivate
        inputState.setLearningEnabled(learning && !isPrivate && hasFullAccess)
        // 追加: Full Access 無しの Keyboard Extension は触覚フィードバックがサンドボックスで
        // 使えず AVAudioSession/CHHapticEngine のエラーログを吐き続ける。hasFullAccess で抑制する。
        let haptics = hasFullAccess
        NSLog("[MFK] applySettings hasFullAccess=\(hasFullAccess) haptics=\(haptics)") // 追加: Full Access 判定のデバッグ
        keyboardView.applySettings(toggleInput: toggle, flickOnly: flickOnly, haptics: haptics)
    }

    // MARK: - 反映ヘルパ

    /// 追加: 未確定文字列を入力欄へインライン反映する（擬似 marked text）。
    /// 変換前は composition(よみ)、変換中は選択中の文節列(変換後文字列)を表示対象にする。
    /// 現在挿入済みの pendingComposition と新しい表示文字列の共通プレフィックスを残し、
    /// 差分だけ削除・挿入して Simeji 風のインライン未確定表示を実現する。
    /// UI（候補バー等）の update も併せて行う。
    private func syncInline(_ result: ConversionResult) {
        // 変更: 変換中は選択中の文節列を結合した変換後文字列をインライン表示する。
        let new: String
        if result.isConverting && !result.segments.isEmpty {
            new = result.segments.map { $0.selected.value }.joined()
        } else {
            new = result.composition
        }
        let old = pendingComposition
        if new != old {
            // 共通プレフィックス長を求める。
            var common = 0
            let newChars = Array(new)
            let oldChars = Array(old)
            while common < newChars.count && common < oldChars.count && newChars[common] == oldChars[common] {
                common += 1
            }
            // 共通部分より後ろの古い分を削除。
            for _ in 0..<(oldChars.count - common) {
                textDocumentProxy.deleteBackward()
            }
            // 新しい分を挿入。
            let inserted = String(newChars[common...])
            if !inserted.isEmpty {
                textDocumentProxy.insertText(inserted)
            }
            pendingComposition = new
            NSLog("[MFK] syncInline old='\(old)' -> new='\(new)'") // 追加: インライン同期のデバッグ
        }
        keyboardView.update(with: result)
    }

    /// 確定文字列を proxy へ送り、UI を初期状態へ戻す。
    private func commitAndInsert() {
        // インライン挿入済みの未確定分をいったん削除してから確定文字列を入れ直す。
        let deleteCount = pendingComposition.count
        for _ in 0..<deleteCount {
            textDocumentProxy.deleteBackward()
        }
        NSLog("[MFK] commitAndInsert pending='\(pendingComposition)' deleted=\(deleteCount)") // 追加: 未確定削除のデバッグ
        pendingComposition = ""
        let text = inputState.commit()
        NSLog("[MFK] commitAndInsert text='\(text)'") // 追加: 確定文字列のデバッグ
        sessionLogger.log(type: "commit", data: ["text": text]) // 追加: 確定文字列を記録
        if !text.isEmpty {
            textDocumentProxy.insertText(text)
        }
        logContext() // 追加: 確定後のカーソル付近文脈を記録
        keyboardView.update(with: .empty)
    }

    /// 追加: カーソル付近の文脈（前後テキスト・選択テキスト）をログへ記録するヘルパ。
    private func logContext() {
        sessionLogger.log(type: "context", data: [
            "before": textDocumentProxy.documentContextBeforeInput ?? "",
            "after": textDocumentProxy.documentContextAfterInput ?? "",
            "selected": textDocumentProxy.selectedText ?? "",
        ])
    }

    // MARK: - お天気分（Narrative）配線・出題

    /// 追加: KeyboardView のバナーコールバックを controller の処理へ配線する。
    ///       これらの経路は textDocumentProxy を一切呼ばない（回答は研究データとしてのみ保存）。
    private func wireNarrativeCallbacks() {
        keyboardView.onRecordTap = { [weak self] in self?.showManualEventPicker() } // 追加:「記録」→ 手動イベント展開
        keyboardView.onQuestionOption = { [weak self] option in self?.handleOptionSelected(option) } // 追加: 選択肢回答
        keyboardView.onQuestionSnooze = { [weak self] in self?.handleSnooze() } // 追加:「あとで」
        keyboardView.onFreeTextStart = { [weak self] in self?.enterResearchInputMode() } // 追加:「自由入力」開始
        keyboardView.onFreeTextCommit = { [weak self] in self?.commitResearchText() } // 追加: 自由記述「決定」
        keyboardView.onFreeTextCancel = { [weak self] in self?.cancelResearchInputMode() } // 追加: 自由記述「キャンセル」
        keyboardView.onManualEvent = { [weak self] event in self?.handleManualEvent(event) } // 追加: 手動イベント選択
        keyboardView.onInfoTap = { [weak self] in self?.showInfoPage() } // 追加:「情報」→ Info ページ展開
        keyboardView.onInfoClose = { [weak self] in self?.keyboardView.hideQuestion() } // 追加: Info ページ「閉じる」
    }

    /// 変更: 出題判定。サーバー（v0.1）の最新質問を優先し、未設定・無し・失敗ならローカル Trigger へフォールバックする。
    ///       安否確認が出ている間・機能OFF・既に質問表示中・Full Access 無しは何もしない（同時1問）。
    private func evaluateNarrativeTriggers() {
        guard narrativeState.narrativeEnabled else { return } // 追加: 機能OFFなら早期リターン
        guard hasFullAccess else { return } // 追加: 研究機能は Full Access 必須
        guard pendingCheck == nil else { return } // 追加: 安否確認が出ている間は Narrative 質問を出さない
        guard currentPending == nil else { return } // 追加: 既に質問表示中なら二重表示しない
        guard !researchInputMode else { return } // 追加: 研究入力中は判定しない

        // 追加: Backend URL 未設定ならローカルのみ。
        let client = ResearchAPIClient(baseURL: narrativeState.backendBaseURL)
        guard client.isConfigured else {
            evaluateLocalNarrativeTriggers()
            return
        }
        // 追加: サーバーの最新質問1件を取りに行く（応答は main で返る）。
        client.fetchPendingQuestion(participantID: narrativeState.participantID) { [weak self] pending in
            guard let self else { return }
            guard self.currentPending == nil, !self.researchInputMode else { return } // 追加: 待っている間に表示された場合は出さない
            if let pending {
                self.presentQuestion(pending, now: Date()) // 追加: サーバー質問を表示
            } else {
                self.evaluateLocalNarrativeTriggers() // 追加: 無ければローカル
            }
        }
    }

    /// 追加: ローカル Trigger による出題（Backend 未設定・未接続時も既存のお天気分質問を動かす）。
    private func evaluateLocalNarrativeTriggers() {
        guard narrativeState.narrativeEnabled,
              pendingCheck == nil,
              currentPending == nil,
              !researchInputMode else { return }

        let now = Date() // 追加: 評価基準時刻
        let isFirst = narrativeState.markKeyboardUse(at: now) // 追加: 当日初回か（朝トリガー用）
        let typing = typingMetrics.snapshot(now: now) // 追加: 現在の打鍵特徴（本文なし）

        guard let pending = narrativeEngine.nextQuestion(now: now, isFirstKeyboardUseToday: isFirst, typing: typing) else { return } // 追加: 出題なし
        presentQuestion(pending, now: now) // 追加: バナーへ提示
    }

    /// 追加: 質問をバナーへ提示し、表示済みとして記録する。
    private func presentQuestion(_ pending: PendingQuestion, now: Date) {
        var p = pending // 追加: questionShownAt を埋めるため可変にする
        p.questionShownAt = now // 追加: 表示時刻
        currentPending = p // 追加: 回答保存で参照
        narrativeState.markShown(kind: p.kind, at: now) // 追加: cooldown 起点を記録
        keyboardView.showQuestion(p) // 追加: バナー表示（高さ64）
        NSLog("[MFK-Narrative] question shown kind=\(p.kind.rawValue) eventType=\(p.eventType)") // 追加: デバッグ
    }

    /// 追加: 選択肢が回答された。回答を保存し、必要なら手動イベントを消費してバナーを閉じる。
    private func handleOptionSelected(_ option: QuestionOption) {
        guard let pending = currentPending else { return } // 追加: 質問が無ければ無視
        // 追加: 活動質問は2段階、夜の振り返りは5尺度を順に聞く。
        if pending.kind == .activityCheck {
            handleActivityOption(option, pending: pending)
            return
        }
        if pending.kind == .nightReflection {
            handleDailyReflectionOption(option, pending: pending)
            return
        }
        let answer = QuestionAnswer(label: option.value, freeText: nil) // 追加: value を保存（label 仕様に合わせる）
        saveAnswer(pending: pending, answer: answer) // 追加: 保存フロー
    }

    /// 追加: 現在活動を「大分類→詳細活動」の2段階で選ぶ。「その他」は自由入力へ進む。
    private func handleActivityOption(_ option: QuestionOption, pending: PendingQuestion) {
        if option.value.hasPrefix("category:") {
            // 追加: 1段目 → 大分類を覚えて詳細活動の選択肢へ切り替える。
            let value = String(option.value.dropFirst("category:".count))
            guard let category = ResearchActivityCatalog.category(value: value) else { return }
            selectedActivityCategory = category
            keyboardView.showQuestionOptions(prompt: "\(category.label)のうち、どれですか？",
                                             options: ResearchActivityCatalog.activityOptions(for: category),
                                             allowFreeText: false)
            NSLog("[MFK-Narrative] activity category=\(category.value)") // 追加: デバッグ
            return
        }
        if option.value == ResearchActivityCatalog.otherFreeTextValue {
            // 追加: その他 → 大分類を選んでいれば "other:<大分類>" として自由入力へ。
            researchChosenOptionValue = selectedActivityCategory.map { "other:\($0.value)" } ?? "other"
            researchDraft = ""
            researchInputMode = true
            keyboardView.setResearchFreeTextMode(true)
            keyboardView.setResearchDraft(researchDraft)
            NSLog("[MFK-Narrative] activity other free text label=\(researchChosenOptionValue ?? "-")") // 追加: デバッグ
            return
        }
        // 追加: 2段目 → 詳細活動の value を保存する。
        saveAnswer(pending: pending, answer: QuestionAnswer(label: option.value, freeText: nil))
    }

    /// 追加: 夜の振り返りを5項目×5段階で進め、最後に JSON（{"mood":3,...}）を free_text として保存する。
    private func handleDailyReflectionOption(_ option: QuestionOption, pending: PendingQuestion) {
        if option.value == "start_daily_reflection" {
            dailyScaleAnswers.removeAll()
            dailyScaleIndex = 0
            showCurrentDailyScale()
            return
        }
        // 追加: value は "scale:<key>:<1-5>"。
        let parts = option.value.split(separator: ":")
        guard parts.count == 3,
              parts[0] == "scale",
              let score = Int(parts[2]) else { return }
        dailyScaleAnswers[String(parts[1])] = score
        dailyScaleIndex += 1
        if dailyScaleIndex < dailyScaleItems.count {
            showCurrentDailyScale()
            return
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: dailyScaleAnswers, options: [.sortedKeys])
        let json = jsonData.flatMap { String(data: $0, encoding: .utf8) }
        NSLog("[MFK-Narrative] daily reflection done answers=\(json ?? "-")") // 追加: デバッグ
        saveAnswer(pending: pending,
                   answer: QuestionAnswer(label: "daily_reflection", freeText: json))
    }

    /// 追加: 夜の振り返りの現在項目を 1〜5 の選択肢で表示する（途中は「あとで」を出さない）。
    private func showCurrentDailyScale() {
        guard dailyScaleIndex < dailyScaleItems.count else { return }
        let item = dailyScaleItems[dailyScaleIndex]
        let options = (1...5).map { score -> QuestionOption in
            let suffix: String
            if score == 1 { suffix = "：\(item.low)" }
            else if score == 5 { suffix = "：\(item.high)" }
            else { suffix = "" }
            return QuestionOption(label: "\(score)\(suffix)", value: "scale:\(item.key):\(score)")
        }
        keyboardView.showQuestionOptions(prompt: "\(dailyScaleIndex + 1)/\(dailyScaleItems.count)  \(item.prompt)",
                                         options: options,
                                         allowFreeText: false,
                                         showSnooze: false)
    }

    /// 追加:「あとで」。種別を snoozeInterval 後まで再表示しないよう記録してバナーを閉じる。
    private func handleSnooze() {
        guard let pending = currentPending else { return } // 追加: 質問が無ければ無視
        let now = Date() // 追加: 基準時刻
        narrativeState.markSnoozed(kind: pending.kind, until: now.addingTimeInterval(NarrativeConfig.snoozeInterval)) // 追加: snooze 記録
        NSLog("[MFK-Narrative] snooze kind=\(pending.kind.rawValue)") // 追加: デバッグ
        dismissBanner() // 追加: バナーを閉じる
    }

    /// 追加: 回答保存フロー。NarrativeEvent を作り、解析（Mock）→ PMTT → repo.save → 状態更新までを行う。
    ///       この経路は textDocumentProxy を一切呼ばない。
    private func saveAnswer(pending: PendingQuestion, answer: QuestionAnswer) {
        let now = Date() // 追加: 回答時刻
        let typing = typingMetrics.snapshot(now: now) // 追加: 打鍵特徴（本文なし）
        var event = NarrativeEvent.make(from: pending, answer: answer, typing: typing, answeredAt: now) // 追加: イベント生成

        // 追加: 解析は Mock（同期的に emotion/experienceType を算出）。UI を止めない軽量処理。
        let value = answer.label ?? answer.freeText // 追加: 判定入力
        let experience = narrativeAnalyzer.experienceClass(for: value, kind: pending.kind) // 追加: 経験タイプ
        let emotion = emotionClass(for: value) // 追加: 感情ラベル
        event.narrative = NarrativeEvent.Narrative(summary: event.narrative?.summary, emotion: emotion, experienceType: experience) // 追加: 解析結果を反映
        event.pmtt = narrativePMTT.link(event: event) // 追加: PMTT ノード対応付け

        narrativeRepo.save(event) // 追加: ローカル JSONL + リモート best-effort（throw しない）
        narrativeState.markAnswered(kind: pending.kind, on: now) // 追加: 当日回答済み・1日上限に反映
        narrativeState.updateTypingBaseline(with: typing) // 追加: 打鍵ベースライン更新
        NSLog("[MFK-Narrative] answer saved kind=\(pending.kind.rawValue) emotion=\(emotion) exp=\(experience)") // 追加: デバッグ

        consumeManualEventsIfNeeded(for: pending) // 追加: 外出/帰宅由来なら手動イベントを消費
        dismissBanner() // 追加: バナーを閉じる
    }

    /// 追加: 感情ラベルの簡易マッピング（Analyzer の emotionClass 相当を同期で持つ）。
    private func emotionClass(for value: String?) -> String {
        switch value {
        case "bad", "slightly_tired", "tired", "difficult": return "negative"
        case "good", "helpful": return "positive"
        default: return "neutral"
        }
    }

    /// 変更: 外出先/外出評価の回答を保存したら手動イベントを、センサー由来なら保留質問キューを取り除く（二重処理防止）。
    private func consumeManualEventsIfNeeded(for pending: PendingQuestion) {
        // 追加: センサー由来（sensor_pending）は保留質問キューを消費する。
        if pending.eventType == "sensor_pending" {
            _ = narrativeState.dequeuePendingKinds() // 追加: 消費して次回の再出題を防ぐ
            NSLog("[MFK-Narrative] pending kinds dequeued after \(pending.kind.rawValue)") // 追加: デバッグ
            return
        }
        guard pending.kind == .outingDestination || pending.kind == .outingEvaluation else { return } // 追加: 対象外は消費しない
        _ = narrativeState.dequeueAllManualEvents() // 追加: 消費して次回の再出題を防ぐ
        NSLog("[MFK-Narrative] manual events dequeued after \(pending.kind.rawValue)") // 追加: デバッグ
    }

    /// 追加: バナーを閉じて表示状態を初期化する。
    private func dismissBanner() {
        currentPending = nil // 追加: 表示中質問を解除
        researchInputMode = false // 追加: 研究入力を確実に解除
        researchDraft = "" // 追加: 下書きを消す
        researchChosenOptionValue = nil // 追加: 選択退避を消す
        selectedActivityCategory = nil // 追加: 活動2段階の状態を消す
        dailyScaleAnswers.removeAll() // 追加: 夜5尺度の途中回答を消す
        dailyScaleIndex = 0
        keyboardView.hideQuestion() // 追加: 高さ0 + 非表示
    }

    // MARK: - 研究入力モード（自由記述）

    /// 追加:「自由入力」開始。研究入力モードへ入り、以降のフリック入力を researchDraft へ流す。
    private func enterResearchInputMode() {
        guard let pending = currentPending else { return } // 追加: 質問が無ければ無視
        // 変更: 活動質問で大分類を選んでいれば "other:<大分類>" を label に残す。
        if pending.kind == .activityCheck {
            researchChosenOptionValue = selectedActivityCategory.map { "other:\($0.value)" } ?? "other"
        } else {
            researchChosenOptionValue = nil // 追加: 選択肢は未選択（自由記述のみ）
        }
        researchDraft = "" // 追加: 下書き初期化
        researchInputMode = true // 追加: モード ON（入力ハンドラの分岐に使う）
        keyboardView.setResearchFreeTextMode(true) // 追加: バナーを自由記述 UI へ
        keyboardView.setResearchDraft(researchDraft) // 追加: 空の下書きを表示
        NSLog("[MFK-Narrative] research-mode enter kind=\(pending.kind.rawValue)") // 追加: デバッグ
    }

    /// 追加: 自由記述「決定」。researchDraft を answer.freeText として保存する。
    private func commitResearchText() {
        guard let pending = currentPending else { return } // 追加: 質問が無ければ無視
        let trimmed = researchDraft.trimmingCharacters(in: .whitespacesAndNewlines) // 追加: 前後空白を除去
        let answer = QuestionAnswer(label: researchChosenOptionValue, freeText: trimmed.isEmpty ? nil : trimmed) // 追加: 回答生成
        NSLog("[MFK-Narrative] research-mode exit(commit) length=\(trimmed.count)") // 追加: デバッグ（本文は出さない）
        researchInputMode = false // 追加: モード OFF（保存前に解除）
        saveAnswer(pending: pending, answer: answer) // 追加: 保存フロー（内部で dismiss）
    }

    /// 追加: 自由記述「キャンセル」。保存せず選択肢表示へ戻す（質問は残す）。
    private func cancelResearchInputMode() {
        researchInputMode = false // 追加: モード OFF
        researchDraft = "" // 追加: 下書き破棄
        researchChosenOptionValue = nil // 追加: 選択退避破棄
        keyboardView.setResearchFreeTextMode(false) // 追加: 選択肢 UI へ戻す
        NSLog("[MFK-Narrative] research-mode exit(cancel)") // 追加: デバッグ
    }

    /// 追加: 研究入力中の下書きへ文字を追記してバナー表示を更新する（proxy には出さない）。
    private func appendResearchText(_ text: String) {
        researchDraft.append(text) // 追加: 下書きに追記
        keyboardView.setResearchDraft(researchDraft) // 追加: バナー表示更新
    }

    /// 追加: 研究入力中の下書きから1文字削除してバナー表示を更新する。
    private func deleteResearchText() {
        if !researchDraft.isEmpty { researchDraft.removeLast() } // 追加: 末尾1文字削除
        keyboardView.setResearchDraft(researchDraft) // 追加: バナー表示更新
    }

    // MARK: - 手動イベント（infoBar「記録」）

    /// 追加:「記録」→ 手動イベント4ボタンをバナーへ展開する。
    private func showManualEventPicker() {
        guard hasFullAccess else { return } // 追加: 研究イベント記録は Full Access 必須
        guard currentPending == nil, !researchInputMode else { return } // 追加: 質問表示中/研究入力中は開かない（同時1問）
        keyboardView.showManualEventPicker() // 追加: 手動イベントボタン表示
        NSLog("[MFK-Narrative] manual picker shown") // 追加: デバッグ
    }

    /// 追加:「情報」→ 親アプリが集めた HealthKit 活動量サマリーをバナーへ全画面表示する。
    /// App Group 共有の値を読むだけ（キーボードは HealthKit を直接読めない）。
    private func showInfoPage() {
        guard hasFullAccess else { return } // 追加: App Group 読み取りは Full Access 前提（記録ボタンと揃える）
        guard currentPending == nil, !researchInputMode else { return } // 追加: 質問表示中/研究入力中は開かない（同時1問）
        let context = researchContextStore.load() // 追加: 最新 Context（未保存なら nil）
        keyboardView.showInfo(text: Self.infoText(from: context)) // 追加: 7項目を整形して表示
        NSLog("[MFK-Narrative] info page shown steps=\(context?.stepCount ?? -1)") // 追加: デバッグ
    }

    /// 追加: Context を Info ページ用の複数行テキストへ整形する。値が無い項目は「--」。
    private static func infoText(from c: ResearchDeviceContext?) -> String {
        func line(_ title: String, _ value: Double?, scale: Double, unit: String, digits: Int) -> String {
            guard let v = value else { return "\(title)：--" } // 追加: nil は「--」
            let scaled = v / scale
            let num = String(format: "%.\(digits)f", scaled)
            return "\(title)：\(num) \(unit)"
        }
        return [
            line("歩数", c?.stepCount, scale: 1, unit: "歩", digits: 0),
            line("歩行距離", c?.walkingDistanceM, scale: 1000, unit: "km", digits: 2), // m → km
            line("登った階段", c?.flightsClimbed, scale: 1, unit: "階", digits: 0),
            line("活動エネルギー", c?.activeEnergyKcal, scale: 1, unit: "kcal", digits: 0),
            line("歩行速度", c?.walkingSpeedMps, scale: 1.0 / 3.6, unit: "km/h", digits: 1), // m/s → km/h（÷(1/3.6)=×3.6）
            line("歩幅", c?.walkingStepLengthM, scale: 0.01, unit: "cm", digits: 0),        // m → cm
            line("歩行非対称性", c?.walkingAsymmetryPct, scale: 1, unit: "%", digits: 1),
        ].joined(separator: "\n")
    }

    /// 追加: 手動イベントが選ばれた。起床は即記録、外出/帰宅/就寝はキューへ積んで再評価する。
    private func handleManualEvent(_ event: ManualEvent) {
        let now = Date() // 追加: 基準時刻
        switch event {
        case .wakeUp:
            // 追加: 起床は質問を伴わない ContextEvent として即保存（キューには積まない）。
            let snapshot = ContextSnapshot(timeOfDay: TimeOfDay.label(for: now),
                                           typingActive: false,
                                           calendarBusy: false,
                                           externalTrigger: "manual_wake_up") // 追加: 起床の文脈
            let ctx = ContextEvent(participantID: narrativeState.participantID,
                                   eventType: "wake_up",
                                   detectedAt: now,
                                   source: "keyboard",
                                   context: snapshot) // 追加: 文脈イベント生成
            narrativeRepo.saveContext(ctx) // 追加: 保存（throw しない）
            NSLog("[MFK-Narrative] manual event handled wake_up") // 追加: デバッグ
        case .outing, .returnHome, .sleep:
            // 追加: 外出/帰宅は質問トリガーの契機、就寝は夜の振り返りを可能にするためキューへ積む。
            narrativeState.enqueueManualEvent(event, at: now) // 追加: キュー投入
            NSLog("[MFK-Narrative] manual event handled \(event.rawValue)") // 追加: デバッグ
        }
        keyboardView.hideQuestion() // 追加: ピッカーを閉じる
        evaluateLocalNarrativeTriggers() // 変更: 手動イベント由来の質問はローカルで即座に出す
    }
}

// MARK: - KeyboardActionDelegate（KeyboardView からの入力を InputState / proxy へ反映）

extension KeyboardViewController: KeyboardActionDelegate {

    func keyboardDidInputKey(keyID: String, direction: FlickDirection) {
        guard let key = KanaTable.key(for: keyID), let text = key.character(for: direction) else { return }
        if researchInputMode {
            appendResearchText(keyboardView.inputMode == .katakana ? KanaTransform.toKatakana(text) : text)
            return
        }
        typingMetrics.recordKeystroke(at: Date())
        if inputState.currentResult.isConverting { commitAndInsert() }
        let result = inputState.input(kanaKeyID: keyID, direction: direction)
        sessionLogger.log(type: "kana", data: ["kana": text, "composition": result.composition,
                                             "candidates": "\(result.candidates.count)"])
        syncInline(result)
    }

    func keyboardDidInput(kana: String) {
        // 追加: 研究入力モード中は本文を researchDraft へ流し、proxy / inputState には一切触れない。
        if researchInputMode {
            appendResearchText(kana) // 追加: 下書きへ追記
            return // 追加: 通常入力経路へ進ませない
        }
        typingMetrics.recordKeystroke(at: Date()) // 追加: 打鍵を集計（本文は渡さず時刻のみ）
        if inputState.currentResult.isConverting { commitAndInsert() }
        let result = inputState.input(fixed: kana)
        NSLog("[MFK] keyboardDidInput kana='\(kana)' -> composition='\(result.composition)' candidates=\(result.candidates.count)") // 追加: 入力とcompositionのデバッグ
        // 追加: 入力かなと未確定よみ・候補数を記録。
        sessionLogger.log(type: "kana", data: [
            "kana": kana,
            "composition": result.composition,
            "candidates": "\(result.candidates.count)",
        ])
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    // 追加: 押された生のキー操作（キーID・フリック方向）を記録する。
    func keyboardDidPressKey(keyID: String, direction: String) {
        sessionLogger.log(type: "key", data: ["keyID": keyID, "direction": direction])
    }

    func keyboardDidDeleteBackward() {
        // 追加: 研究入力モード中は researchDraft を1文字削るだけ（proxy / inputState には触れない）。
        if researchInputMode {
            deleteResearchText() // 追加: 下書き末尾を削除
            return // 追加: 通常削除経路へ進ませない
        }
        if inputState.currentResult.composition.isEmpty {
            // 未確定が無ければ実テキストを削除。
            NSLog("[MFK] keyboardDidDeleteBackward -> proxy.deleteBackward (composition empty)") // 追加: 削除経路のデバッグ
            sessionLogger.log(type: "delete", data: ["target": "text"]) // 追加: 実テキスト削除を記録
            typingMetrics.recordBackspace(at: Date()) // 追加: backspace を集計（時刻のみ）
            textDocumentProxy.deleteBackward()
            logContext() // 追加: 実テキスト削除後のカーソル付近文脈を記録
        } else {
            let result = inputState.deleteBackward()
            NSLog("[MFK] keyboardDidDeleteBackward -> composition='\(result.composition)'") // 追加: 削除後compositionのデバッグ
            sessionLogger.log(type: "delete", data: ["target": "composition", "composition": result.composition]) // 追加: 未確定削除を記録
            syncInline(result) // 変更: 未確定を入力欄へインライン反映
        }
    }

    func keyboardDidToggleDakuten() {
        let result = inputState.toggleDakuten()
        sessionLogger.log(type: "dakuten", data: ["composition": result.composition]) // 追加: 濁点トグルを記録
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidRequestConversion() {
        let result = inputState.requestConversion()
        conversionCount += 1 // 追加: 変換回数カウント
        // 追加: 変換要求とその結果（候補一覧・文節）を記録。
        sessionLogger.log(type: "conversion", data: [
            "composition": result.composition,
            "candidates": result.candidates.map { $0.value }.joined(separator: "|"),
            "segments": result.segments.map { $0.reading }.joined(separator: "|"),
            "count": "\(conversionCount)",
        ])
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidSelectCandidate(id: String) {
        guard !researchInputMode, inputState.currentResult.candidates.contains(where: { $0.id == id }) else { return }
        // 候補選択 → その状態で確定して proxy へ挿入。
        let result = inputState.selectCandidate(id: id)
        // 追加: 選択された候補を記録。
        sessionLogger.log(type: "candidate", data: [
            "id": id,
            "selected": result.segments.map { $0.selected.value }.joined(),
        ])
        commitAndInsert()
    }

    func keyboardDidCommit() {
        commitAndInsert()
    }

    func keyboardDidCancelConversion() {
        let result = inputState.cancelConversion()
        sessionLogger.log(type: "cancel", data: ["composition": result.composition]) // 追加: 変換取消を記録
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidInputSpace() {
        // 追加: 研究入力モード中は下書きへ半角スペースを追記（proxy には触れない）。
        if researchInputMode {
            appendResearchText(" ") // 追加: 下書きへスペース追記
            return // 追加: 通常経路へ進ませない
        }
        if inputState.currentResult.composition.isEmpty {
            // 未確定が無ければ空白を直接入力。
            sessionLogger.log(type: "space", data: [:]) // 追加: 空白入力を記録
            textDocumentProxy.insertText(" ")
            logContext() // 追加: 空白入力後のカーソル付近文脈を記録
        } else {
            // 未確定があれば変換を要求（一般的な IME の挙動）。
            let result = inputState.requestConversion()
            conversionCount += 1 // 追加: 変換回数カウント
            sessionLogger.log(type: "conversion", data: [ // 追加: スペース経由の変換も記録
                "composition": result.composition,
                "candidates": result.candidates.map { $0.value }.joined(separator: "|"),
                "count": "\(conversionCount)",
            ])
            syncInline(result) // 変更: 未確定を入力欄へインライン反映
        }
    }

    func keyboardDidTapReturn() {
        // 追加: 研究入力モード中は改行を下書きへ追記（proxy には触れない）。
        if researchInputMode {
            appendResearchText("\n") // 追加: 下書きへ改行追記
            return // 追加: 通常経路へ進ませない
        }
        if inputState.currentResult.composition.isEmpty {
            sessionLogger.log(type: "return", data: [:]) // 追加: 改行を記録
            textDocumentProxy.insertText("\n")
            logContext() // 追加: 改行入力後のカーソル付近文脈を記録
        } else {
            // 未確定があれば確定（改行はしない、一般的な IME の確定挙動）。
            commitAndInsert()
        }
    }

    func keyboardDidMoveFocus(by offset: Int) {
        let result = inputState.moveFocus(by: offset)
        sessionLogger.log(type: "moveFocus", data: ["offset": "\(offset)", "focused": "\(result.focusedSegment)"]) // 追加: 文節フォーカス移動を記録
        syncInline(result) // 変更: 未確定を入力欄へインライン反映
    }

    func keyboardDidMoveCursor(by offset: Int) {
        // 未確定が無いときのみ実カーソルを移動。
        guard inputState.currentResult.composition.isEmpty else { return }
        sessionLogger.log(type: "moveCursor", data: ["offset": "\(offset)"]) // 追加: カーソル移動を記録
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func keyboardDidChangeInputMode(_ mode: InputMode) {
        if !researchInputMode && !inputState.currentResult.composition.isEmpty { commitAndInsert() }
        inputState.setInputMode(mode)
        sessionLogger.log(type: "inputMode", data: ["mode": "\(mode)"])
    }

    func keyboardWillBeginCursorControl() -> Bool {
        guard !researchInputMode else { return false }
        if !inputState.currentResult.composition.isEmpty { commitAndInsert() }
        return true
    }

    func keyboardDidTapNextKeyboard() {
        sessionLogger.log(type: "nextKeyboard", data: [:]) // 追加: 地球儀キーを記録
        advanceToNextInputMode()
    }
}
