# お天気分・生活パターン

親アプリの「生活の気づき」で天気、研究質問、通知・質問設定を扱います。研究ログの本人回答とモデル推定を区別し、未学習・観測不足では値を断定しません。

GPSの場所クラス・行き先予測・位置監視は削除しました。旧版からの起動時に停止処理だけを実行し、旧queueは送信せず隔離します。[行動に基づく拠点・タスク](behavior-context.md)は継続します。

研究日の境界はJST。既定4質問はcurrent/night/weather各1＋place/task交互1。自動支援の追加枠はサーバー設定でdaily_limitを5以上にした場合のみ利用します。

`ResearchNotificationCoordinator` は前面ポーリングとBGAppRefreshの機会に同期します。通知は本人がONにした場合のみで、iOSの実行制限があるため時刻や毎日の配信は保証できません。HealthKitの背景更新は処理完了後にobserver completionを呼びます。

[README](../README.md)でビルドし、[testing.md](testing.md)の実機確認を行ってください。今回の環境ではXCTest・署名・通知の実機動作を検証していません。
