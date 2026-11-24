# 三階層生活状態モデルとの接続

旧ブランチの本人研究機能を、現行の提案プレビュー・永続outbox・項目別取得時刻の設計へ接続する。一般的な質問・保存経路は [narrative-integration.md](narrative-integration.md) を参照。

## 現在状態と今日全体の回答

`currentState` は「今」、`nightReflection` は「今日全体」の気分・疲労・ストレス・集中度・眠気を各1〜5で記録する。既存の5尺度フローを使用し、スキップした項目は欠測のまま扱う。

保存先は `NarrativeEvent` の `question.kind=currentState|nightReflection` と `answer.free_text` 内のJSON（例：`{"mood":3,"fatigue":2,"stress":2,"concentration":4,"sleepiness":1}`）。`answer.label` はそれぞれ `current_state` / `daily_reflection`。現在と1日全体を同じ回答種別に混在させない。

## キーボードでの再出題制御

- 実質問の回答保存が成功した後、質問IDを App Group UserDefaults の `research.answeredRequests` へ追加する。重複IDは末尾へ移し、直近200件を保持する。通信断で回答がoutboxに残っていても、保持中のIDは再出題しない。200件より古いIDの抑止はこの履歴だけでは保証しない。
- 実質問を表示すると `research.lastRequestID` を更新する。通常のサーバー `currentState` が別IDなら、同種別の最終表示から3時間未満は表示しない。介入前後のadaptive support質問はこの抑止の対象外で、サーバー支援条件と共通表示ゲートに従う。同じ直前IDの未回答なら再表示でき、当日の既存表示の続きとして表示予算を再消費しない。回答済みID・snooze・質問OFF・質問の有効期限は再表示にも適用する。
- 「あとで」は種別別に30分のsnoozeを記録し、サーバー質問にも期限を適用する。別IDの同種別も期限内は抑止する。
- ローカル `QuestionPolicy` は `currentState` を「当日回答済み」の抑止から除外する。3時間のcooldown・snooze・日次上限は維持する。テンプレートの `maxPerDay=2` は変更せず、この値を回数判定には使わない。サーバーの日次予算・生成方針も変更しない。
- プレビューは既存どおり端末内の実質問ゲートを通さず、回答済みID・直前ID・最終表示時刻を変更しない。この移植はキーボードの実質問経路へ適用し、既存の親アプリ回答・通知フローは維持する。

## 観測報告と項目別取得時刻

`ResearchAPIClient.sendObservation` は `POST /api/heartbeats` にJSONを1回だけ送る。必須項目は `event_id`（UUID）、`participant_id`、`occurred_at`（送信時のISO8601日時）、`source`、`questions_enabled`。`logging_enabled` は値が分かる場合だけ含める。`interventions_enabled` はこの契約では省略し、サーバー既定のtrueを使用する。現行の提案設定同期は `ResearchWorkflow.syncPreferences` の既存経路を維持する。

親アプリの `ResearchContextCollector.refresh()` は `source=parent_app`、`questions_enabled=narrativeEnabled` を送り、キーボードの記録状態を推測しないため `logging_enabled` は省略する。キーボードは出題判定の先頭で、Full Accessがある場合に `source=keyboard`、`logging_enabled=hasFullAccess && !privateModeEnabled`、`questions_enabled=narrativeEnabled` を送る。質問OFFでも動作時の観測報告は試みる。

heartbeatは動作したプロセスが把握する設定の報告であり、通信結果を確認せず、永続キューや再送も使用しない。到達・終日の収集・アプリを閉じた後の継続実行は保証しない。キーボードの送信はFull Accessが前提で、無効時は報告しない。親アプリの通信はキーボードのFull Access設定に依存しない。報告の欠如は観測不明であり、収集停止の証明にはならない。

`ResearchDeviceContext.measurement_updated_at` は項目ごとの取得時刻を保持する。別項目を更新して `updated_at` が新しくなっても、古い歩数や予定などを新しい観測と誤認しないための情報である。既存のHealthKit・カレンダーの取得時刻は維持し、電池残量 `battery_level` と電池状態 `battery_state` には同じ取得時刻を付ける。追加した `markMeasurement(_:)` は、時刻辞書が欠けていても初期化し、指定項目だけを更新する。

親アプリの活動カタログ回答は `answer.label` に安定値（例：`desk_work`）、`answer.free_text` に表示ラベルを保存する。自由入力は既存どおり本文だけを保存する。

## 本人の「研究」画面と接続

「くらしのログ」右上の「研究」で、設定済みBackend URLに `research/{participantID}` を追加したページを開く。タイトルは「生活状態の研究」。初期URLはhttp/httpsのみとし、通常遷移は初期ホストまたはblob URLに限定する。

この画面の内容は接続先サーバーが提供する。対応する研究サーバーでは、生活状態・本人回答のグラフ、推定方式の比較、活動・状態の訂正、PMTT・学習状況、提案の停止・再開、全種類のエクスポートを確認・操作できる。iOS側はページとJSONダウンロードの共有機能を担当する。

エクスポートは一時ディレクトリの `lifelog-all-<UUID>.json` に保存し、完了後に共有シートを開く。エクスポートには入力本文などが含まれ得るため、共有先は本人が選ぶ。この機能は外部AIへデータを送信しない。接続開始・ダウンロードの失敗はエラー内容をアラートで表示する。

iPhoneのBackend URLは既存のMac接続先を使用する。対応するMacサーバーで `research_upstream` をUbuntuの研究サーバーへ設定し、UbuntuがMacの記録を差分取得する構成と組み合わせる。サーバー側の設定・機能は対応版の `switch_bot_python/docs/research.md` を参照。このiOS移植では接続先やサーバー設定を自動変更しない。

## 検証状況とMacでの確認

この環境にはXcode・iOS SDK・Swiftコンパイラがなく、iOSビルド・XCTest・実機操作・WKDownloadの共有画面は未検証。`ResearchStateTests` へ、質問IDと直前IDの永続化、200件上限、重複IDの末尾移動、3時間cooldown、当日再回答と既存制約、取得時刻ヘルパーのテストを追加した。currentStateのデコードは既存 `ResearchWorkflowTests` を使用する。

Macでは次を確認する。

1. `./scripts/generate_xcode_project.sh` でプロジェクトを再生成し、インストール済みiPhone Simulatorを指定して `xcodebuild test -project MozcFlickKeyboard.xcodeproj -scheme MozcFlickKeyboard -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO` を実行する。
2. 実機で現在状態と夜の5尺度、通信断での回答保存と再送、保存失敗時に回答済みIDを記録しないことを確認する。同じ直前未回答IDの再表示、通常のcurrentState別IDの3時間抑止とadaptive support質問の例外、種別別30分snooze、200件の保持、プレビューの状態非更新も確認する。
3. サーバー側で親アプリ/キーボードのheartbeatとJSON項目を確認する。質問OFF、Full Access無効、プライベートモード、接続断を切り替え、報告の保証範囲を確認する。
4. 活動記録の安定値と表示ラベル、電池2項目の取得時刻、既存のHealthKit・予定の時刻保持を確認する。
5. 「研究」のURLと同一ホスト/blobの遷移、外部ホストの拒否、JSONダウンロード・共有、接続断/保存失敗時のアラートを確認する。iPadで実行できる構成では共有シートのpopoverも確認する。サーバー画面の訂正・提案停止/再開・エクスポート内容は対応サーバーと組み合わせて確認する。

既存の通知・バックグラウンド更新の実行時刻はiOSに依存する。この移植で常時観測や常時出題を保証する仕組みは追加しない。
