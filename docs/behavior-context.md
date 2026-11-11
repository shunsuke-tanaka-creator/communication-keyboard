# GPSを使わない拠点・タスクの記録

対応する `switch_bot_python` のGPS不要版と同時に更新する。サーバーの変更、Mac単体運用、Ubuntuへの移行は [サーバー側の導入手順](https://github.com/shunsuke-tanaka-creator/switch_bot_python/blob/main/docs/behavior-context.md) を参照。

## iPhoneの変更

- 位置情報の許可要求、訪問監視、有意な位置変化の監視を廃止した。旧版で監視が有効だった場合は起動時に停止し、端末の旧座標マップを削除する。
- Info.plistから位置情報の説明キーとlocationバックグラウンドモードを削除した。位置情報によるバックグラウンド起動は使わない。質問通知は既存の前面ポーリング・BGAppRefreshの機会に依存し、配信時刻を保証しない。
- 未送信の旧 `place_visit` は送信せずローカルで `.gps-disabled` として隔離する。他の入力・回答は従来どおり再送する。
- 新しい `placeCheck` と `taskCheck` に親アプリ・キーボードの両方で回答できる。確認対象は独立しており、タスクを変更しても拠点の正解は変わらない。
- 質問に回答した時刻ではなく、質問発行時までの5分間をラベルにする。外出中の回答や通信の遅れを別の滞在に誤って割り当てない。質問IDを使った永続outboxで重複再送を吸収する。
- 拠点・タスクの確認は合計1回/日で軸を交互にし、全体4回/日の共通予算を使う。自動質問をOFFにすると停止する。

## 表示と訂正

「生活の気づき → 履歴・傾向・トポロジーを見る → 拠点とタスク」のリンクを開く。

現在の拠点とタスクを別々に表示する。未学習・観測不足・未確認の候補を確定表示しない。区間と対象を選び、既存IDへの確認、新しいまとまりへの分割、命名、統合を行える。1日の振り返りは当時のライブ推定と別に保存する。

このWeb画面の編集はオンライン時にサーバーへ保存する。通信に失敗した場合は保存エラーを表示するので再実行する。親アプリ/キーボードの質問回答はオフラインでもoutboxに保持する。

## ビルドと確認

既存のMozcライブラリ・Signing Team・App Groupは変更しない。プロジェクトを生成してXcodeから実機にインストールする。

```sh
./scripts/generate_xcode_project.sh
xcodebuild test -project MozcFlickKeyboard.xcodeproj -scheme MozcFlickKeyboard -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

期待：生成成功、対応Simulatorで `** TEST SUCCEEDED **`。
意図しない出力：`No such module` / `Unable to find a destination` / `** TEST FAILED **`。既存の環境・Simulator名・Mozc SDK別リンク設定を確認する。

今回の環境では設定・plist・JSON契約と静的参照を確認した。Swiftコンパイラはない。Xcode/iOS SDKがないため型検査・XCTest実行・実機通知は未確認。

実機では次を確認する。

1. 旧版で位置情報ONだった状態から更新し、起動後に新しい位置許可が出ず位置収集が止まる。
2. 入力・開閉ログがMacへ届き、拠点/タスクの質問が表示される。
3. 質問回答を通信断で保存し、再接続後に1回だけ反映する。
4. 同一拠点の別タスク、同一タスクの別拠点を個別に回答・訂正できる。
5. 質問OFF・上限・間隔が親アプリとキーボードで共有される。
6. 過去日を振り返り、当時の推定と訂正後の解釈が別々に残る。
