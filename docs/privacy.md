# プライバシー方針

この研究版（MacBook統合版）は、キーボードが記録した入力イベント（確定本文・前後文脈を含む）、お天気分の回答・文脈、端末Context（HealthKit・カレンダー・バッテリー）を Tailscale 経由で MacBook の研究サーバーへ同期します。Mac側では SwitchBot の開閉記録と合わせて SQLite に保存します。

- 接続先の既定値は `http://100.106.185.3:8000`（`NarrativeState.recommendedBackendURL`）。設定画面の Backend URL を**空欄にして保存すると**送信・取得を停止します。保存済みのデータや送信待ちキューは端末に残ります。
- 操作手順は [macbook-lifelog.md](macbook-lifelog.md) を参照してください。

---

## 1. 基本方針

- かな漢字変換（Mozc / スタブ）、候補学習、ユーザー辞書は端末内だけで処理します。入力ログの保存・同期はこれとは別の経路です。
- **Full Access が無効**のときは、入力と変換だけが動きます。入力ログ・学習・ユーザー辞書・お天気分・触覚フィードバック・ネットワーク通信はすべて無効です（`KeyboardViewController.applySettings` / `enableLoggingIfAllowed` / `evaluateNarrativeTriggers`）。
- Full Access が有効で、かつプライベートモードが OFF のとき、`SessionLogger` が入力イベントを記録します。Backend URL が設定されていれば、セッション終了ごとに本文を含むセッションを Mac へ送信します。
- お天気分の回答と文脈イベントは、端末内の JSONL に保存したうえで永続キュー（`ResearchEventOutbox`）からMacへ送信します。失敗した分は次の同期で再送します。Mac側ではイベントIDで重複を防ぎます。
- 送信先は設定した研究サーバーだけです。広告・解析SDK・クラウドAIには送信しません。通信は平文 HTTP です（`NSAllowsArbitraryLoads = true`）。Tailscale の経路暗号化を前提にしています。
- `PrivacyInfo.xcprivacy` は本ドキュメントの内容に合わせてあります。研究版では `project.yml` のホストアプリのリソースとして同梱します。場所IDを用いる任意の外出研究機能も記載しています。

---

## 2. 取得するデータ一覧

### 2.1 キーボード入力ログ（`SessionLogger` → `ResearchSessionUpload`）

記録の条件: Full Access 有効、プライベートモード OFF、キーボード表示中。1セッションは最大60秒です。キーボードを閉じたとき、または60秒無入力のときにも確定します。

| type | 記録内容 |
| --- | --- |
| `meta` | 入力欄の `keyboardType` / `returnKeyType`、Full Access の有無、入力モード、セッション内の変換回数 |
| `key` | キーID・フリック方向 |
| `kana` | 入力したかな、未確定よみ、候補数 |
| `delete` | 削除対象（`text` / `composition`）、削除後の未確定よみ |
| `dakuten` | 濁点切替後の未確定よみ |
| `conversion` | よみ、**候補一覧（`|` 区切り）**、文節よみ、変換回数 |
| `candidate` | 選択した候補ID、選択後の文字列 |
| `cancel` | 変換取消時のよみ |
| `commit` | **確定文字列（本文）** |
| `context` | **カーソル前後のテキスト（`documentContextBeforeInput` / `AfterInput`）・選択テキスト**。確定・実削除・スペース・改行の直後に記録 |
| `space` / `return` / `nextKeyboard` | 押下したという事実 |
| `moveFocus` / `moveCursor` | 文節フォーカスやカーソルの移動量 |
| `inputMode` | 入力モードの切替 |
| `safetyCheck` | 安否確認の予定時刻と質問文 |

セッションには次も付きます: `session_id`、`participant_id`、`device_id`、開始・終了時刻、終了理由（`interval` / `idle_timeout` / `keyboard_hidden`）、打鍵特徴（2.2）、端末Context（2.3）。

- お天気分の自由記述入力中（研究入力モード）は、入力したかなと本文を `SessionLogger` に記録せず、入力欄（`textDocumentProxy`）にも挿入しません。ただし `key` イベント（キーID・フリック方向）は `KeyboardView` から常に通知されるため、研究入力モード中も記録されます。
- `isSecureTextEntry` の欄では、iOS がカスタムキーボードの代わりに標準キーボードを表示するため、記録されません。

### 2.2 打鍵特徴（`TypingMetrics` → `TypingFeatures`）

打鍵時刻と回数だけから算出します。文字の内容は使いません。

`typing_speed_cpm` / `backspace_rate` / `mean_key_interval_ms` / `session_duration_sec` / `backspace_count` / `total_typed_characters` / `pause_count`（2秒超の間）/ `long_pause_duration_sec`

セッション、回答（`NarrativeEvent.typing`）、打鍵ベースライン（App Group UserDefaults、EMA α=0.2）に使います。

### 2.3 端末Context（親アプリ `ResearchContextCollector` → `ResearchDeviceContext`）

キーボード拡張は HealthKit / EventKit を使えません。そのため親アプリが取得して App Group UserDefaults（`research.deviceContext`）に保存し、キーボードがセッション送信時に添付します。

| 区分 | 項目 | 集計 |
| --- | --- | --- |
| HealthKit（読み取りのみ） | 歩数 / 歩行距離 / 登った階段 / 活動エネルギー | 今日0時〜現在の合計 |
| HealthKit（読み取りのみ） | 歩行速度 / 歩幅 / 歩行非対称性 | 直近1時間の平均 |
| EventKit | 今日の全カレンダーの予定の**タイトル**・開始・終了時刻 | 今日0時〜24時 |
| バッテリー | 残量（0〜1）・状態 | 取得時点 |
| センサー最新値 | `door_open` / `living_presence` / `temperature` | 疑似センサー受信時に更新 |
| 更新時刻 | `updated_at` | — |

- 取得タイミング: 親アプリが前面になるたび（`sceneDidBecomeActive`）。HealthKit はこれに加えて、`HKObserverQuery` + `enableBackgroundDelivery(.hourly)` により約1時間ごとに取得します（`AppDelegate` で開始）。端末ロック中は HealthKit を読めません。
- キーボード下部の「情報」ボタンを押すと、保存済みの HealthKit 7項目を表示します。表示処理は App Group の読み取りだけです。
- `ContextSnapshot.calendar_busy` は `CalendarContextProvider` が stub のため常に `false` です。予定は出題判定には使っていません。

### 2.4 お天気分の回答（`NarrativeEvent`）

| 質問（`QuestionKind`） | 出る条件 | 保存値 |
| --- | --- | --- |
| `morningMood` | 当日初回のキーボード利用 かつ 6〜10時台 | good / normal / slightly_tired / bad |
| `nightReflection` | 22時〜翌2時台、または手動「寝る」 | `label=daily_reflection`、`free_text` に気分・疲労・ストレス・集中度・眠気を各1〜5で記録した JSON |
| `outingDestination` | 手動「外出した」/ 疑似センサー `door_open` | work / shopping / walk / meal / hospital / other |
| `outingEvaluation` | 手動「帰宅した」/ 疑似センサー `door_close` | good / normal / tired / difficult |
| `fatigueCheck` | 疑似センサー温度 high / low | yes / no |
| `activityCheck` | サーバーが返したとき（`GET /api/questions/pending/{id}`） | 大分類→詳細活動の value。「その他」は `other:<大分類>` ＋ **自由記述** |
| その他の種類（`morningGoal` / `workState` / `breakCheck` / `freeNarrative` / `interventionFeedback`） | ローカルの Trigger には接続していません。サーバーが返した場合だけ出ます | 各選択肢の value。自由記述を許可する質問では自由記述も |
| 親アプリ「活動を記録」 | 手動 | `event_type=activity_report`、**自由記述（最大500文字）** |

回答と一緒に保存する項目: きっかけの発生時刻・表示時刻・回答時刻、「あとで」回数、`ContextSnapshot`（時間帯・入力中か・外部トリガー）、ルールベースの感情・経験タイプ、PMTT ノード（Mock）、打鍵特徴。

プライベートモードは入力ログと学習だけを止めます。お天気分の出題・回答保存・送信はプライベートモード中も動きます（停止するには設定の「質問機能」を OFF にします）。

### 2.5 文脈イベント（`ContextEvent`）

| 発生源 | event_type | 端末保存 | Mac送信 |
| --- | --- | --- | --- |
| キーボード「記録」→「起きた」 | `wake_up` | `context_yyyyMMdd.jsonl` | `POST /api/context-events`（再送キューあり） |
| 疑似センサー（HTTP受信・アプリ内テスト） | `sensor_<type>` | `context_yyyyMMdd.jsonl` | **送信しない**（代わりに 2.6 の `ResearchSensorEvent` を送る） |

キーボードと親アプリ Dashboard の「外出した」「帰宅した」「寝る」は、`NarrativeState` の手動イベントキューに積まれるだけです。単独では保存されず、続いて出る質問の回答として記録されます。

### 2.6 疑似センサー（研究用・HTTP受信は既定 OFF）

- 受け取るのは `type`（`door_open` / `door_close` / `toilet` / `temperature` / `living_presence`）、`value`（`high` / `mid` / `low`、`present` / `absent`）、`at` の3項目だけです。
- HTTP 受信（`SensorHTTPServer`、`POST /sensor`、既定ポート 8770）は、設定「疑似センサー受信」が ON で、かつ親アプリが前面のときだけ待ち受けます。ローカルネットワーク許可（`NSLocalNetworkUsageDescription`）が必要です。
- 親アプリ Dashboard の「疑似センサーテスト」ボタンは、HTTP を使わず直接 `SensorEventRouter` を呼びます。
- どちらの経路でも `SensorEventRouter.route` が次を行います:
  1. `ContextEvent` を端末へ保存
  2. 端末Context の最新値を更新
  3. Backend URL 設定時に `ResearchSensorEvent`（participant_id / device_id / type / value / occurred_at）を `POST /api/sensor-events` へ**1回だけ**送る（失敗しても再送しない）

### 2.7 安否確認（`SafetyCheckLog`）

- 予定（時刻・文言・チェック要否・曜日）は App Group UserDefaults `schedules` に保存します。
- チェックボタンを押すと、`SafetyChecks/check_yyyyMMdd.jsonl` に押した時刻・予定時刻・質問文を追記します。このファイル自体は送信しませんが、同じ内容が入力ログの `safetyCheck` イベントとして送信されます（入力ログの記録条件を満たす場合）。

### 2.8 変換・辞書・設定（端末内のみ・送信しない）

| 情報 | 内容 | 保存先 |
| --- | --- | --- |
| 設定 | トグル入力・フリックのみ・学習・プライベートモード、研究設定（参加者ID・質問機能・Backend URL・疑似センサー受信/ポート） | App Group UserDefaults |
| 候補学習（`LearningStore`） | よみ・確定語・頻度・最終使用日時（最大5000件）。学習 OFF・プライベートモード・`isSecureTextEntry` では記録しない | `Learning/learning.json`（+ backup） |
| ユーザー辞書（`UserDictionaryStore`） | よみ・単語・品詞・コメント・作成/更新日時・有効フラグ | `UserDictionary/user_dictionary.json`（+ backup） |
| 端末UUID | 初回アクセス時に生成する `device_id` | App Group UserDefaults `research.deviceID` |

- ユーザー辞書のストアと CSV/JSON 入出力（`DictionaryImportExport`）は Shared に実装されています。ただし、現状のホストアプリには辞書を編集・入出力する画面がありません。
- Mozc エンジン自体のセッション内学習は Mozc の実装に従います。

---

## 3. 保存場所

App Group `group.com.tanaka05.MozcFlickKeyboard` の共有コンテナ:

| パス | 内容 |
| --- | --- |
| `Library/Caches/SessionLogs/session_yyyyMMdd_HHmmss_SSS_<ID8桁>.jsonl` | 入力ログ（親アプリ「入力ログ」で閲覧可能） |
| `Library/Application Support/PendingResearchSessions/<session_id>.json` | 未送信のセッション（送信成功で削除） |
| `Library/Application Support/ResearchOutbox/<hash>.json` | 未送信の回答・文脈イベント（送信成功で削除） |
| `Narrative/narrative_yyyyMMdd.jsonl` / `context_yyyyMMdd.jsonl` | 回答・文脈イベント |
| `Narrative/unsent_narrative.jsonl` | 旧バージョンの未送信分。読み込んだら ResearchOutbox へ移行する |
| `SafetyChecks/check_yyyyMMdd.jsonl` | 安否確認チェック |
| `Learning/` / `UserDictionary/` | 学習・ユーザー辞書 |

- 親アプリのダッシュボード取得結果は、親アプリ自身の `Caches/LifeLog/<sha256>.json` にキャッシュします。
- Mac側の記録はサーバーディレクトリの `data/lifelog.sqlite3` です。
- iCloud 同期や他アプリとの共有はしません。

---

## 4. プライベートモード

- ON のときにキーボードを開いても、入力ロガーを開始しません。候補学習も記録しません。
- 既存のログ・送信待ちは削除しません。過去の送信待ちも含めて通信を止めたい場合は、Backend URL を空欄にしてください。
- お天気分の質問・回答、親アプリの「活動を記録」、Mac側の SwitchBot 受信はプライベートモードの対象外です。

---

## 5. 送信経路

| 経路 | タイミング | API | 実装 |
| --- | --- | --- | --- |
| 入力セッション | セッション終了時。未送信分はキーボード表示時と親アプリ同期時に再送 | `POST /api/sessions` | `KeyboardViewController.uploadClosedSession` → `ResearchAPIClient` |
| 回答・文脈 | 保存時。未送信分はキーボード表示時と親アプリ同期時に再送 | `POST /api/narrative-events` / `POST /api/context-events` | `NarrativeRepositoryHub` → `RemoteRepository` → `ResearchEventOutbox` |
| 疑似センサー | 受信時（再送なし） | `POST /api/sensor-events` | `SensorEventRouter` → `ResearchAPIClient.sendSensorEvent` |
| 最新質問の取得 | キーボード表示時・60秒ごと | `GET /api/questions/pending/{participant_id}` | `ResearchAPIClient.fetchPendingQuestion` |
| ダッシュボード | 親アプリ前面時（15秒ごと） | `GET /api/dashboard/{participant}` / `GET /api/records/...` / `PUT /api/devices/{id}/name` | `LifeLogAPI` |

古いデータや受信が途絶えたデータは、現在の確定情報として扱いません。活動回答と推定は区別し、ドアの開閉だけで人の所在を断定しません。

---

## 6. 削除方法

- 現状のホストアプリには、ユーザー辞書・学習・入力ログ・回答を削除する画面がありません（予定は設定画面の左スワイプで削除できます）。
- **アプリ削除**: iPhone からアプリを削除すると、App Group 共有コンテナのデータも OS によって削除されます。
- iPhone 側で削除しても Mac の DB は消えません。Mac の記録を削除するには、サーバーを停止し、必要なバックアップを取ったうえで `data/` を管理してください。自動の削除期限は設定していません。

---

## 7. ファイル保護

- `learning.json` と `user_dictionary.json` には `FileProtectionType.completeUntilFirstUserAuthentication` を明示的に設定しています。
- その他のファイル（入力ログ・送信キュー・Narrative・安否確認）には保護属性を個別に設定していません。OS の既定値に従います。
- 端末のパスコード設定によって保護の強さが変わります。パスコードの設定を推奨します。
