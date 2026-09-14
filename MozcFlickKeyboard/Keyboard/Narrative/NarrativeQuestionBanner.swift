// NarrativeQuestionBanner.swift
// MozcFlickKeyboard — 追加: 「お天気分」micro-diary の質問／手動イベントを候補バー上部に出すバナー View。
//
// 責務:
//  - PendingQuestion を受けて質問文ラベル + 選択肢ボタン（横スクロール）+「あとで」+「自由入力」を表示する。
//  - 自由記述モードでは researchDraft の表示 +「決定」/「キャンセル」を出す（textDocumentProxy には一切触れない）。
//  - infoBar「記録」から呼ばれる手動イベントモードでは ManualEvent.allCases のボタンを出す。
//  - 操作はすべてクロージャで KeyboardView 経由 KeyboardViewController へ通知する（proxy への配線を構造的に持たない）。
//
// 高さ制御: このバナー自身は高さを持たず、親（KeyboardView）が bannerHeightConstraint を 0/64 で切り替える。

import UIKit // 追加: UIKit の View を構成する
import MozcFlickShared // 追加: PendingQuestion / QuestionOption / ManualEvent など共有型を使う

/// 追加: 質問・手動イベントを表示する候補バー上部バナー。
final class NarrativeQuestionBanner: UIView {

    // MARK: - コールバック（KeyboardView がまとめて受ける。proxy へは決して繋がない）

    /// 追加: 選択肢がタップされた。
    var onSelectOption: ((QuestionOption) -> Void)?
    /// 追加:「あとで」がタップされた。
    var onSnooze: (() -> Void)?
    /// 追加:「自由入力」がタップされ研究入力モードを開始する。
    var onFreeTextStart: (() -> Void)?
    /// 追加: 自由記述の「決定」がタップされた。
    var onFreeTextCommit: (() -> Void)?
    /// 追加: 自由記述の「キャンセル」がタップされた。
    var onFreeTextCancel: (() -> Void)?
    /// 追加: 手動イベントボタンがタップされた。
    var onManualEvent: ((ManualEvent) -> Void)?

    // MARK: - 内部状態

    /// 追加: いま表示中の質問（自由入力の「決定」で参照する）。
    private var currentPending: PendingQuestion?

    // MARK: - サブビュー（質問モード）

    /// 追加: 質問文の左に出す見出しアイコン（「お天気分」らしく天気マークを大きく出す）。
    private let headerIcon: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.tintColor = .systemYellow // 追加: 天気マークらしい色
        v.setContentHuggingPriority(.required, for: .horizontal)
        return v
    }()

    /// 変更: 質問文ラベル。フル画面表示になったので大きめの文字にする。
    private let promptLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .semibold) // 変更: 12 → 18pt（フル画面用）
        l.textColor = .label
        l.numberOfLines = 2
        return l
    }()

    /// 追加: 見出しアイコン + 質問文を横に並べるスタック。
    private lazy var headerStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [headerIcon, promptLabel])
        s.axis = .horizontal
        s.spacing = 4
        s.alignment = .center
        return s
    }()

    /// 変更: 選択肢ボタンを並べる ScrollView。フル画面表示なので縦スクロールにする。
    private let optionsScroll: UIScrollView = {
        let s = UIScrollView()
        s.showsHorizontalScrollIndicator = false
        s.showsVerticalScrollIndicator = false // 追加: 縦スクロールのインジケータも隠す
        return s
    }()

    /// 変更: 選択肢ボタン +「あとで」+「自由入力」を並べるスタック。フル画面なので縦並び・横幅いっぱい。
    private let optionsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical // 変更: horizontal → vertical（フル画面で大きなボタンを縦に並べる）
        s.spacing = 8 // 変更: 6 → 8（押しやすい間隔）
        s.alignment = .fill // 変更: center → fill（ボタンを横幅いっぱいに広げる）
        return s
    }()

    // MARK: - サブビュー（自由記述モード）

    /// 変更: 現在の researchDraft を表示するラベル。フル画面なので大きめ。
    private let draftLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17, weight: .regular) // 変更: 12 → 17pt
        l.textColor = .label
        l.numberOfLines = 1
        l.text = ""
        return l
    }()

    /// 変更: 自由記述の「決定」ボタン。フル画面なので大きめ。
    private let commitButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("決定", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold) // 変更: 12 → 17pt
        return b
    }()

    /// 変更: 自由記述の「キャンセル」ボタン。フル画面なので大きめ。
    private let cancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("キャンセル", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular) // 変更: 12 → 17pt
        return b
    }()

    /// 追加: 自由記述モードの横スタック（ラベル + 決定 + キャンセル）。
    private lazy var freeTextStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [draftLabel, commitButton, cancelButton])
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        return s
    }()

    // MARK: - init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup() // 追加: サブビュー構築
    }

    required init?(coder: NSCoder) { return nil } // 追加: Storyboard 非対応

    /// 追加: サブビューと制約を構築する。
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false // 追加: AutoLayout 管理
        backgroundColor = .secondarySystemBackground // 追加: 候補バーと区別できる薄い背景
        layer.cornerRadius = 10 // 追加: フル画面表示時に「質問カード」として見えるよう角丸にする

        // 追加: 見出し（天気アイコン + 質問文）を配置。
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        // 追加: 見出しアイコンのサイズを固定（フル画面表示なので大きめの天気マーク）。
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerIcon.widthAnchor.constraint(equalToConstant: 34), // 変更: 14 → 34pt
            headerIcon.heightAnchor.constraint(equalToConstant: 34), // 変更: 14 → 34pt
        ])

        // 追加: 選択肢 ScrollView と内部 Stack を配置。
        optionsScroll.translatesAutoresizingMaskIntoConstraints = false
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(optionsScroll)
        optionsScroll.addSubview(optionsStack)

        // 追加: 自由記述モードの Stack を配置（既定は非表示）。
        freeTextStack.translatesAutoresizingMaskIntoConstraints = false
        freeTextStack.isHidden = true
        addSubview(freeTextStack)

        // 追加: ボタンのアクションを配線（すべてクロージャ経由・proxy へは繋がない）。
        commitButton.addTarget(self, action: #selector(commitTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            // 変更: 見出し（天気アイコン + 質問文）を上部に固定。フル画面なので余白を広く。
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            // 変更: 選択肢 ScrollView は見出しの下・バナー下端まで。
            optionsScroll.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            optionsScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            optionsScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            optionsScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            // 変更: 内部 Stack を contentLayoutGuide にピン留めし、幅を frameLayoutGuide に合わせて縦スクロールにする。
            optionsStack.leadingAnchor.constraint(equalTo: optionsScroll.contentLayoutGuide.leadingAnchor),
            optionsStack.trailingAnchor.constraint(equalTo: optionsScroll.contentLayoutGuide.trailingAnchor),
            optionsStack.topAnchor.constraint(equalTo: optionsScroll.contentLayoutGuide.topAnchor),
            optionsStack.bottomAnchor.constraint(equalTo: optionsScroll.contentLayoutGuide.bottomAnchor),
            optionsStack.widthAnchor.constraint(equalTo: optionsScroll.frameLayoutGuide.widthAnchor), // 変更: height→width（縦スクロール）

            // 追加: 自由記述 Stack はバナー全体を覆う。
            freeTextStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            freeTextStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            freeTextStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - 公開 API

    /// 追加: 質問を表示する（選択肢ボタン群を作り直す）。
    func showQuestion(_ pending: PendingQuestion) {
        currentPending = pending // 追加: 自由入力の「決定」で参照するため保持
        setFreeTextMode(false) // 追加: 質問表示時は必ず選択肢モードから始める
        promptLabel.text = pending.prompt // 追加: 質問文を表示
        headerIcon.image = UIImage(systemName: headerIconName(for: pending.kind)) // 追加: 質問種別に応じた天気マーク
        rebuildOptionButtons(options: pending.options, allowFreeText: pending.allowFreeText, showSnooze: true, manual: false) // 追加: 選択肢を再構築
    }

    /// 追加: 手動イベント4ボタンを表示する（infoBar「記録」から）。
    func showManualEvents() {
        currentPending = nil // 追加: 質問ではないので保持なし
        setFreeTextMode(false) // 追加: 選択肢モード表示
        promptLabel.text = "記録する行動を選んでください" // 追加: 手動イベントの見出し
        headerIcon.image = UIImage(systemName: "square.and.pencil") // 追加: 手動記録は記録アイコン
        rebuildManualButtons() // 追加: ManualEvent ボタンを構築
    }

    /// 追加: 自由記述モードの ON/OFF を切り替える（選択肢 UI と自由記述 UI の表示を入れ替える）。
    func setFreeTextMode(_ on: Bool) {
        headerStack.isHidden = on // 変更: 自由記述中は見出し（アイコン+質問文）を隠して省スペース化
        optionsScroll.isHidden = on // 追加: 選択肢を隠す
        freeTextStack.isHidden = !on // 追加: 自由記述 UI を出す
    }

    /// 追加: 自由記述中の下書きテキストを更新表示する（proxy には出さない）。
    func updateFreeTextDraft(_ text: String) {
        draftLabel.text = text.isEmpty ? "（入力してください）" : text // 追加: 空なら誘導文
    }

    /// 追加: 表示内容を全消去する（バナー非表示時に呼ぶ）。
    func clear() {
        currentPending = nil // 追加: 保持解除
        promptLabel.text = "" // 追加: 文言消去
        headerIcon.image = nil // 追加: 見出しの天気マークも消す
        draftLabel.text = "" // 追加: 下書き消去
        setFreeTextMode(false) // 追加: 選択肢モードへ戻す
        clearOptionButtons() // 追加: 動的ボタンを撤去
    }

    // MARK: - ボタン構築（動的）

    /// 追加: optionsStack の中身を全撤去する。
    private func clearOptionButtons() {
        for v in optionsStack.arrangedSubviews {
            optionsStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    /// 追加: 選択肢ボタン群 +「あとで」+（許可時）「自由入力」を作る。
    private func rebuildOptionButtons(options: [QuestionOption], allowFreeText: Bool, showSnooze: Bool, manual: Bool) {
        clearOptionButtons() // 追加: 既存を撤去
        for option in options { // 追加: 選択肢ごとにボタンを作る
            // 追加: 気分・評価の選択肢なら天気マークを添える（「お天気分」の気分表現）。
            let b = makeButton(title: option.label, iconName: weatherIconName(for: option.value))
            b.addAction(UIAction { [weak self] _ in self?.onSelectOption?(option) }, for: .touchUpInside) // 追加: value ごと通知
            optionsStack.addArrangedSubview(b)
        }
        if allowFreeText { // 追加: 自由記述可なら「自由入力」ボタン
            let b = makeButton(title: "自由入力", iconName: "square.and.pencil") // 追加: 記入アイコン
            b.addAction(UIAction { [weak self] _ in self?.onFreeTextStart?() }, for: .touchUpInside)
            optionsStack.addArrangedSubview(b)
        }
        if showSnooze { // 追加:「あとで」ボタン
            let b = makeButton(title: "あとで", iconName: "clock.fill") // 追加: 時計アイコン
            b.addAction(UIAction { [weak self] _ in self?.onSnooze?() }, for: .touchUpInside)
            optionsStack.addArrangedSubview(b)
        }
    }

    /// 追加: 手動イベント4ボタン（ManualEvent.allCases）を作る。
    private func rebuildManualButtons() {
        clearOptionButtons() // 追加: 既存を撤去
        for event in ManualEvent.allCases { // 追加: 4種のイベントボタン
            let b = makeButton(title: event.displayName, iconName: manualIconName(for: event)) // 追加: 行動アイコン
            b.addAction(UIAction { [weak self] _ in self?.onManualEvent?(event) }, for: .touchUpInside)
            optionsStack.addArrangedSubview(b)
        }
    }

    /// 追加: 手動イベントごとのアイコン（起床＝日の出 / 外出＝歩行 / 帰宅＝家 / 就寝＝月）。
    private func manualIconName(for event: ManualEvent) -> String {
        switch event {
        case .wakeUp: return "sunrise.fill"      // 追加: 起きた
        case .outing: return "figure.walk"       // 追加: 外出した
        case .returnHome: return "house.fill"    // 追加: 帰宅した
        case .sleep: return "moon.stars.fill"    // 追加: 寝る
        }
    }

    /// 変更: 共通のボタン外観を作るヘルパ。フル画面表示なので大きく・アイコンも大きくする。
    private func makeButton(title: String, iconName: String? = nil) -> UIButton {
        let b = UIButton(type: .system) // 追加: system ボタン
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold) // 変更: 13 → 18pt
        b.backgroundColor = .tertiarySystemBackground // 追加: ボタン地色
        b.layer.cornerRadius = 10 // 変更: 6 → 10（大きいボタンに合わせる）
        b.contentHorizontalAlignment = .left // 追加: アイコン+文字を左寄せにして並びを揃える
        b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16) // 変更: 押しやすい大きな余白
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true // 追加: 指で押しやすい高さを確保
        // 追加: 「お天気分」らしく、気分・評価の選択肢には大きな天気マークを左に添える。
        if let iconName {
            // 追加: SF Symbols を大きめのポイントサイズで描画する。
            let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
            if let image = UIImage(systemName: iconName, withConfiguration: config) {
                b.setImage(image, for: .normal) // 追加: 天気アイコン
                b.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10) // 追加: アイコンと文字の間隔
                b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 26) // 追加: アイコン分の余白
            }
        }
        return b
    }

    // MARK: - 天気マーク（「お天気分」の気分表現）

    /// 追加: 選択肢の value を天気マーク（SF Symbols 名）へ対応づける。
    /// 「お天気分」は気分を天気で表す考え方なので、良い＝晴れ / 普通＝晴れ時々曇り / 疲れ＝曇り / 悪い＝雨 とする。
    /// 天気で表せない選択肢（外出先など）はその行動を表すアイコンを割り当て、全ボタンにアイコンを出す。
    private func weatherIconName(for value: String) -> String? {
        switch value {
        // --- 気分・評価（天気マーク） ---
        case "good", "helpful", "yes": return "sun.max.fill"          // 追加: 晴れ（良い）
        case "normal", "neutral": return "cloud.sun.fill"             // 追加: 晴れ時々曇り（普通）
        case "slightly_tired": return "cloud.fill"                    // 追加: 曇り（少し疲れた）
        case "tired": return "cloud.drizzle.fill"                     // 追加: 小雨（疲れた）
        case "bad", "not_helpful": return "cloud.rain.fill"           // 追加: 雨（悪い）
        case "difficult": return "cloud.bolt.rain.fill"               // 追加: 荒天（大変だった）
        case "no": return "xmark.circle.fill"                         // 追加: いいえ
        // --- 行動・場所（天気ではないが統一感のためアイコンを出す） ---
        case "work", "working": return "briefcase.fill"               // 追加: 仕事
        case "rest", "break": return "moon.zzz.fill"                  // 追加: 休息・休憩
        case "going_out": return "figure.walk"                        // 追加: 外出
        case "shopping": return "cart.fill"                           // 追加: 買い物
        case "walk": return "figure.walk.motion"                      // 追加: 散歩
        case "meal": return "fork.knife"                              // 追加: 食事
        case "hospital": return "cross.case.fill"                     // 追加: 病院
        case "family": return "person.2.fill"                         // 追加: 家族
        case "other": return "ellipsis.circle.fill"                   // 追加: その他
        default: return "circle.fill"                                 // 追加: 未定義の選択肢にも小さな印を出す
        }
    }

    /// 追加: 質問の種類に応じた見出しアイコン。「お天気分」の主目的である気分・振り返りには天気マークを出す。
    private func headerIconName(for kind: QuestionKind) -> String {
        switch kind {
        case .morningMood: return "sun.horizon.fill"      // 追加: 朝の気分＝日の出
        case .nightReflection: return "moon.stars.fill"   // 追加: 夜の振り返り＝夜空
        case .outingDestination: return "figure.walk"     // 追加: 外出先
        case .outingEvaluation: return "house.fill"       // 追加: 帰宅後の評価
        case .fatigueCheck, .breakCheck, .workState: return "cloud.sun.fill" // 追加: 体調・作業状態
        default: return "cloud.sun.fill"                  // 追加: 既定は天気マーク
        }
    }

    // MARK: - アクション（自由記述）

    /// 追加:「決定」→ 選択済み value（あれば）+ 下書きを親へ通知する経路。実データ確定は controller 側で行う。
    @objc private func commitTapped() {
        onFreeTextCommit?() // 追加: controller が researchDraft を読んで保存する
    }

    /// 追加:「キャンセル」→ 研究入力モードを抜ける通知。
    @objc private func cancelTapped() {
        onFreeTextCancel?()
    }
}
