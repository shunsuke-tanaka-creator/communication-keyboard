# プライバシー方針

MacBook統合版では、キーボードが記録する入力イベント（確定本文・前後文脈を含む）、活動回答、端末ContextをTailscale経由でMacBookに同期します。SwitchBotの開閉記録と合わせてMacのSQLiteに保存します。初期接続先は `http://100.106.185.3:8000`。設定のBackend URLを空欄にすると通信を停止します。保存済みデータや送信待ちキューは残ります。操作手順は [macbook-lifelog.md](macbook-lifelog.md) を参照してください。

---

## 1. 基本方針

- かな漢字変換・辞書・学習処理は端末内で動作します。入力ログの保存・同期は別の経路です。
- Full Access有効・プライベートモードOFF時、既存のSessionLoggerが入力イベントを記録します。Backend URLがある場合、本文を含む記録済みセッションをMacへ送信します。
- 活動回答と文脈イベントは端末内に保存し、永続キューからMacへ再送します。MacではイベントIDで重複を防ぎます。
- Macのサーバーは指定Tailscale IPにbindし、指定iPhoneとMac自身の接続元IPのみ許可します。広告・解析SDK・クラウドAIには送信しません。
- 従来の疑似センサー受信は別のテスト機能です。今回のSwitchBot収集には不要です。
- 既存のPrivacyInfo.xcprivacyは旧テンプレートです。この研究版をApp Storeへ公開する場合の申告は別途整合を確認する必要があります。

---

## 2. 保存する情報

| 情報 | 内容 | 目的 |
| --- | --- | --- |
| 設定 | トグル入力・フリックのみ・学習 ON/OFF・プライベートモード | ユーザー体験の保存 |
| ユーザー辞書 | よみ・単語・品詞・コメント（`UserDictionaryEntry`） | 変換候補の追加 |
| 学習データ | 変換確定履歴（Mozc の学習） | 変換精度の向上 |

いずれも**端末内のみ**に保存し、外部へ送信しません。

---

## 2.1 お天気分（研究）データ

研究用機能「お天気分」は、質問への回答を研究データとして記録します。回答データと入力セッションは別の構造ですが、どちらもBackend URL設定時はMacへ同期します。

| 情報 | 内容 | 送信の有無 |
| --- | --- | --- |
| `NarrativeEvent` | 質問への回答（選択肢の値・自由記述）、要約、感情/経験タイプ、文脈、打鍵統計量、PMTT ノード | 端末内保存 + Macへ同期 |
| `ContextEvent` | 質問を伴わない文脈記録（起床・外出検知・疑似センサー受信など） | 端末内保存 + Macへ同期 |
| 打鍵統計量（`TypingFeatures`） | 打鍵速度・backspace 率・キー間隔・ポーズ等の**統計量のみ**（本文・キーの内容は保持しない） | 上記イベント・セッションに内包してMacへ同期 |

- 保存場所は App Group 共有コンテナ内の `Narrative/` 配下の日付別 JSONL:
  - `narrative_yyyyMMdd.jsonl` … 回答済み `NarrativeEvent`
  - `context_yyyyMMdd.jsonl` … `ContextEvent`
- **自由記述の入力はホストアプリのテキスト欄（`textDocumentProxy`）へは一切挿入されません**。研究用の下書きバッファにのみ保持し、回答としてのみ保存します。
- `ResearchSessionUpload.events` には、既存のローカルセッションログに記録されるキー・かな・変換・確定文字列・入力欄の前後文脈が含まれます。Macへの送信対象です。
- 親アプリの「お天気分」にあるJSON / CSV書き出しも引き続き利用できます。これは自動同期とは別の操作です。

### 2.1.1 端末Context（HealthKit 活動量）

- 親アプリ（`ResearchContextCollector`）が HealthKit から**読み取りのみ**で次の活動量を取得し、App Group（`ResearchDeviceContext`）へ最新値を保存し、入力セッションに付随してMacに送信します。カレンダーの予定タイトル・時刻、バッテリー状態も権限と取得状況に応じて含みます。キーボード拡張は HealthKit を直接読めないため、親アプリが集めた値を共有して使います。
  - 今日0時〜現在の合計: 歩数 / 歩行距離 / 登った階段 / 活動エネルギー量推定値
  - 直近1時間の平均: 歩行速度 / 歩幅 / 歩行非対称性
- **バックグラウンド更新**: `HKObserverQuery` と `enableBackgroundDelivery(frequency: .hourly)` により、親アプリが前面でなくても約1時間ごとに最新値へ更新します（`com.apple.developer.healthkit.background-delivery`）。端末ロック中は HealthKit を読めないため、ロック解除後に反映されます。
- **キーボードでの表示**: キーボード下部の「情報」ボタンから、保存済みの上記7項目を全画面の Info ページで表示します（開いた時点の保存値。開いている間は自動更新しません）。表示は App Group の読み取りのみで、ここから外部送信は行いません。

---

## 2.2 疑似センサー受信（研究用・既定オフ）

実際の IoT センサーが無い段階でも研究フローを動かせるように、同一 Wi-Fi 上の PC から親アプリへ疑似センサーイベントを注入できます（`MozcFlickKeyboard/App/Sensor/SensorHTTPServer.swift`。CLI は `tools/sensor_inject.py`）。

- **受け取る内容だけ**: `type`（`door_open` / `door_close` / `toilet` / `temperature` / `living_presence` など）、`value`（`high` / `mid` / `low`、`present` / `absent` など）、`at`（発生時刻）の3項目のみです。それ以外の情報は受け取りません。
- 注入自体は「PC → 親アプリ」です。受信したイベントの文脈記録・センサー記録は、Backend URL設定時にMacへの送信対象になります。実機BLEの受信と疑似イベントは区別されます。
- **親アプリ前面時のみ受信**: 受信サーバーは親アプリがアクティブなときだけ待ち受け、背面・バックグラウンドへ回ると停止します（iOS の制約）。キーボード拡張は受信に関与しません。
- **既定は OFF**: 設定「研究設定（お天気分）」の「疑似センサー受信」を明示的に ON にしたときだけ動きます（`sensorReceiveEnabled` 既定 `false`、ポート既定 `8770`）。
- **ローカルネットワーク許可が必要**: iOS 14 以降は初回にローカルネットワークアクセスの許可ダイアログが出ます（`NSLocalNetworkUsageDescription`）。拒否すると受信しません。
- **通信範囲は LAN 内のみ**: 平文 HTTP ですが、同一 Wi-Fi 内の研究用注入だけを想定しています。インターネットへは出ません。受信したイベントは `ContextEvent`（`event_type = "sensor_<type>"` / `source = "sensor"`）として端末内 JSONL に保存されます。
- アプリ内の疑似センサーボタンは直接 `SensorEventRouter` を呼びます。注入用HTTPは不要ですが、記録のMac同期はBackend URL設定に従います。

---

## 3. 保存場所（App Group）

- iPhoneの共有データは App Group `group.com.tanaka05.MozcFlickKeyboard` に保存します。送信待ちは `Library/Application Support/PendingResearchSessions` と `ResearchOutbox`。Macの記録はサーバーディレクトリの `data/lifelog.sqlite3`。画面キャッシュは親アプリのCachesに保存します。
  - 設定: `UserDefaults(suiteName: AppConfig.appGroupID)`
  - ユーザー辞書 / 学習データ: App Group 共有コンテナ内のファイル（`AppConfig.sharedContainerURL`）
- ホストアプリと Keyboard Extension が同じ領域を共有します。iCloud 同期・他アプリ共有は行いません。

---

## 4. プライベートモード

- プライベートモードONでキーボードを開くと入力ロガーは開始しません。既に保存したログや送信待ちは削除しません。過去の送信待ちも含めて通信を停止したい場合はBackend URLを空欄にしてください。活動の手動回答・Mac側のSwitchBot受信は別の記録です。
- 機微な入力を行う場面での利用を想定しています。

---

## 5. 送信経路

- `ResearchAPIClient` が入力セッションを `/api/sessions` へ送ります。
- `NarrativeRepositoryHub` が回答と文脈をローカル保存し、`ResearchEventOutbox` を通してMacへ送ります。失敗したイベントは次回同期時に再送します。
- `LifeLogAPI` が状態・日別ログ・詳細を取得します。設置場所の名前もMacに保存します。
- 古いデータや受信が途絶えたデータを現在の確定情報として扱いません。活動回答と推定を区別し、開閉だけで人の所在を断定しません。

---

## 6. 削除方法

- **ユーザー辞書の個別削除**: ホストアプリの辞書管理画面から項目単位で削除。
- **辞書・学習の全消去**: ホストアプリの「データを消去」操作（全エントリ削除・学習リセット）。
- **アプリ削除**: iPhone からアプリを削除すると、App Group 共有コンテナのデータも OS により削除されます。
- iPhone側の削除ではMacのDBは消えません。Macの記録を削除する場合はサーバー停止後、必要なバックアップを取って `data/` を管理してください。自動削除期限は設定していません。

---

## 7. ファイル保護

- 共有コンテナのファイルには iOS のデータ保護（Data Protection）を適用します。
- 既定の保護レベルは「初回ロック解除後にアクセス可能（`.completeUntilFirstUserAuthentication` 相当）」を目安とします。
  - 拡張はロック直後にも起動され得るため、より厳格すぎる保護は可用性を損なう点に留意。
- 端末のパスコード設定により保護強度が変わります。ユーザーにパスコード設定を推奨します。
