# 研究質問と保存経路

現在の仕様です。旧phase別手順・入力本文を含む診断ログ例は削除しました。UI操作は[README](../README.md)、データ項目は[privacy.md](privacy.md)を参照。

`ResearchAPIClient` → `PendingQuestion` → 親アプリ/キーボードの回答 → `NarrativeEvent.make` → `NarrativeRepositoryHub` → JSONLと永続outbox → Python API、という経路です。天気・拠点/タスク・支援結果は `ResearchWorkflow.annotate` で専用イベントも作り、質問IDに基づく安定IDで再送します。

現在状態・夜の振り返りは気分/疲労/ストレス/集中度/眠気の5尺度。未選択は欠測です。天気4分類は独立した名義尺度で、疲労点数へ変換しません。

サーバー設定済みで200が返った質問のみを表示します。204/通信失敗ではローカルfallbackしません。URL未設定時は従来のローカルTriggerを利用します。サーバー既定予算はcurrent/night/weather各1＋place/task日替わり1。イベント提案を使う場合はdaily_limitを5以上へ明示変更します。

`save` / `saveContext` / `enqueue` は永続保存のBoolを返します。失敗時は回答済みへ更新せず、自由入力や尺度フォームを残して再試行を促します。通信断でも保存できていれば回答は保持されます。JSONL追記はflockでApp/Extension間を排他し、同一event_idを再追記しません。旧unsentファイルは読込・移行のみ維持します。

セッション送信は `ResearchSessionQueue` に分離し、1ファイルずつ送信します。不正JSONまたは400/413/422は原本を隔離し、他のイベントの送信を続けます。`.failed-*` は原因修正後に `ResearchPersistence.restoreQuarantined(in:)` で戻せます。自動復帰はしません。旧GPS `.gps-disabled` は復帰・送信しません。

質問の自由入力は通常の入力欄へ挿入しません。バナーの表示だけで通常入力を除外せず、回答入力中の区間だけ `purpose=assessment` にします。診断NSLogに本文・候補・回答内容を出しません。記録を許可した研究ログには本文が入るため、診断ログと同一視しないでください。

疑似センサーのHTTP診断機能は継続しています。[tools/README_sensor.md](../tools/README_sensor.md)を参照。実BLE受信はMac側です。
