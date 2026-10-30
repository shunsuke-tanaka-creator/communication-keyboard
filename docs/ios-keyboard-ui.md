# iOSに近いキーボード操作への変更

PR #2の研究機能ブランチを土台とする。研究の質問・回答・通信・下部の「記録・情報」の位置を維持する。Appleの非公開キーボード実装のコピーではなく、UIKitで独自実装する。

| 従来の問題 | 変更 |
| --- | --- |
| 英語は@とA〜Jだけ | QWERTY全26文字、小文字、Shift、ダブルタップCaps Lock |
| 全モードを4×5に配置 | 英語10/9/7文字の行、数字・記号の専用ページ、幅比で伸縮 |
| 英語が日本語変換へ入る | 英数記号は直接入力、空白と改行を独立 |
| 英語候補なし | UITextCheckerの端末内補完候補。タップで現在の単語を置換 |
| 自動修正の設定なし | 初期OFF。ON時のみ空白でスペル修正。URL/メールでは無効 |
| 文頭大文字なし | 入力欄の大文字指定を参照。初期ON、設定可能 |
| フリック候補が横一列 | キー中心に上下左右の十字ガイド、選択方向を強調 |
| 連打で意図せず別の文字 | 新規設定の既定はフリックのみ。「あ」2回で「ああ」。既存設定は保持 |
| 独自の青緑配色 | グレーの背景・白い文字キー・グレーの機能キー、ダーク配色 |
| Return表示が固定 | 検索・送信・完了などを入力欄に合わせる。未確定中は確定 |
| 候補一覧が下部バーを覆う | 一覧はキー領域だけを覆う |
| 未確定を削除・再挿入 | UIKit setMarkedText/unmarkText。範囲はUTF-16で指定 |
| カーソル/入力欄移動で未確定状態が残る | 外部選択変更・入力欄変更・キーボード終了で変換状態を解放 |
| 変換中の削除で読みも1文字消す | 1回目は変換取消、2回目から読みを削除 |
| 複数文節の候補に全文置換が混在 | 文節変換ではMozcの文節候補を保持し、全文辞書候補を混ぜない |
| カタカナを確定しづらい | 読みのカタカナ候補を明示。合成候補IDをMozcへ送らない |
| 地球儀が次への切替だけ | 標準の入力モード一覧イベントに接続 |

## 検証状況

Linux環境でSwift全ファイルのtree-sitter構文解析とgit diff --checkを実施。構文解析はSwiftコンパイラによる型チェックではない。

XCTestにはQWERTY全文字、Shift/Caps Lock、Return表示、英語候補と未確定の分離、フリック既定値、変換取消から削除、カタカナ合成候補、複数文節の候補混在防止を追加。既存テストのQWERTY幅・連打設定の期待値も更新した。

この環境にはXcode/iOS SDKがなく、XCTest・iOSビルド・実機のMozc・UIKit描画は未実行。Apple標準と同等の予測精度・操作感を検証済みとはしない。SimulatorはLocalStubEngineのため、実機Mozcの品質評価を代替しない。

## Macでの確認

既存のREADMEに従ってMozcをビルドし、プロジェクトを生成する。シミュレータ名はXcodeにインストール済みのものを指定する。

```sh
xcodebuild -project MozcFlickKeyboard.xcodeproj -scheme MozcFlickKeyboard -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

期待する出力: `** TEST SUCCEEDED **`。意図しない出力: `** TEST FAILED **`、`error:`、`Unable to find a destination`。最後の場合はインストール済みSimulator名へ変更する。成功を確認するまではマージ判定に使わない。

実機・Simulatorでの確認項目:

- iPhone 16 Pro、320pt幅、小型/大型iPhone、横向き、iPad幅、ライト/ダーク。
- `hello world`、Shiftで`Hello`、Caps Lockで`HELLO`、数字・記号、モード往復。
- 新規設定と既存設定、フリックのみON/OFF、濁点・半濁点・小文字・長音。
- `きょう`→予測→今日、カタカナ候補、複数文節、空白連打、取消→削除→再入力。
- 未確定中のカーソル移動、別入力欄への移動、選択置換、キーボード切替で周辺文が消えないこと。
- メモ・Safari入力欄・検索・メール・URLでmarked textとReturn動作。
- 英語修正OFFで単語が勝手に変わらないこと。ON時の修正、文頭大文字、補完候補選択。
- 地球儀の長押し、VoiceOver、削除長押し、空白ドラッグ。
- 研究質問・自由記述・記録・情報が元の導線で使用でき、自由記述がホストへ漏れないこと。

## 残る差

英語補完はUITextCheckerでありApple標準の文脈予測モデルではない。スワイプ英語入力、絵文字検索、音声入力、標準と同等の自動修正取消UIは未実装。marked textを使った挙動は各ホストアプリで実機確認が必要。日本語の予測精度は同梱Mozc辞書と学習量に依存し、この変更で辞書自体を入れ替えてはいない。

Apple API根拠: https://developer.apple.com/documentation/uikit/uitextdocumentproxy/setmarkedtext(_:selectedrange:)

## マージ順

このPRのbaseは`codex/otenki-topological-lifelog`。まずPR #2をmainへマージし、続いてこのPRのbaseをmainへ変更して差分と競合を確認する。PR #2をsquash/rebase mergeした場合は、この変更分をmainへrebaseする必要がある場合がある。マージ操作は利用者が行う。
