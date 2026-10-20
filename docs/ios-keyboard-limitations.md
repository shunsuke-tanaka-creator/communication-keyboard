# iOS Custom Keyboard Extension の制約

本キーボードは iOS の Custom Keyboard Extension として動作します。この仕組みには OS レベルの制約が多く、設計・実装に直接影響します。ここでは制約と、それに対する本プロジェクトの実装上の妥協点をまとめます。

---

## 1. marked text（未確定文字列）相当の制約

- 拡張が使える `UITextDocumentProxy` には、システム IME が持つ **marked text（下線付きの未確定文字列）API が無い**。
- そのため変換中の「未確定のかな／変換候補」をホストのテキスト欄に下線表示することはできない。
- **本プロジェクトの妥協点**:
  - 変更: 未確定よみ（変換中は選択中の文節列）は `KeyboardViewController.syncInline` で入力欄へ**実際に挿入**する（擬似インライン表示）。変わるたびに `pendingComposition` との差分だけを `deleteBackward()` / `insertText` で更新する。下線は付かない。
  - 確定（`commit`）時は、挿入済みの未確定分を消してから確定文字列を `insertText` する。未確定が空のときの削除は `deleteBackward()`。
  - 変換候補は**キーボード領域内**（候補バー／候補一覧）に表示する。

---

## 2. Secure Text Entry（パスワード欄）

- `isSecureTextEntry == true` の入力欄では、システムがカスタムキーボードを無効化し**標準キーボードへ強制切替**することがある。
- パスワード欄では起動されない／入力が届かない前提で設計する。
- **妥協点**: セキュア欄では動作保証しない。ユーザーには標準キーボードが表示される。

---

## 3. 電話番号 / URL / 数字入力欄（keyboardType）

- `keyboardType` が `.numberPad` / `.phonePad` / `.URL` / `.emailAddress` などの場合、ホストは特定の文字種を期待する。
- カスタムキーボードは keyboardType の情報を `textDocumentProxy` から参照できるが、レイアウトを自動で切り替えてはくれない。
- **妥協点**（変更: 現状の実装）:
  - `textDidChange` はフックだけで、`keyboardType` に応じたレイアウト切り替えは**実装していない**。数字・電話・URL・メール欄でも同じ12キーかなレイアウトが出る。
  - `keyboardType` / `returnKeyType` の値はセッション開始時の `meta` イベントとして入力ログに記録している。

---

## 4. メモリ制限

- Keyboard Extension は**非常に厳しいメモリ上限**（数十 MB 台、iOS バージョン依存）で動作し、超過すると OS に強制終了される。
- Mozc の辞書はサイズが大きいため、丸ごとメモリ常駐させると危険。
- **妥協点**:
  - 辞書は mmap 等で必要部分のみ読み込む（Mozc の既定挙動を尊重）。
  - 大きな一時バッファ・画像を持たない。候補バーは軽量に描画。
  - メモリ計測を [performance.md](performance.md) の目標に沿って継続監視。拡張が破棄・再生成されても App Group の永続層から復元。

---

## 5. Full Access

- `Keyboard/Info.plist` で `RequestsOpenAccess = true`。**入力・変換だけなら Full Access なしで動作**する。
- 変更: 次の機能はコード上 `hasFullAccess` が true のときだけ有効になる（`KeyboardViewController`）:
  - ユーザー辞書・候補学習（`UserDictionaryStore` / `LearningStore` を生成しない）
  - 入力ログ（`SessionLogger`）と研究サーバーへの送信
  - お天気分（質問バナー・「記録」・「情報」）
  - 触覚フィードバック（Full Access 無しではサンドボックスのエラーが出続けるため無効化）
- Full Access 無効時は、一般的なネットワーク通信と、システム全体のペーストボードへの自由なアクセスもできない。
- 詳細なプライバシー方針は [privacy.md](privacy.md)。

---

## 6. ネットワーク

- 変更: Full Access 有効時、キーボード拡張は研究サーバー（Backend URL、既定 `http://100.106.185.3:8000`）と次の通信をする:
  - `POST /api/sessions`
  - `POST /api/narrative-events`
  - `POST /api/context-events`
  - `GET /api/questions/pending/{participant_id}`
- 平文 HTTP を許可している（`NSAllowsArbitraryLoads = true`）。Backend URL を空欄にすると通信しない。
- 変換・予測・学習・辞書の処理は端末内で完結し、ネットワークを使わない。

---

## 7. ホストアプリとの共有

- 拡張とホストアプリはプロセスが別で、直接メモリ共有はできない。
- 共有手段は **App Group**（`UserDefaults(suiteName:)` と共有コンテナのファイル）。
- 設定変更は次回拡張起動時、または `UserDefaults` の再読込タイミングで反映される（拡張は常駐しないため即時反映されないことがある）。
- **妥協点**: 辞書・設定はファイル／`UserDefaults` 経由でやり取りし、拡張は起動時に最新を読み込む。書き込み競合を避けるため原子的置換を用いる。

---

## 8. その他の実装上の妥協点

- **カーソル移動・選択範囲**: `UITextDocumentProxy` で前後の文脈（`documentContextBeforeInput` 等）は取得できるが、任意位置へのカーソル移動 API は限定的。文節単位の高度な編集はキーボード内 UI で完結させる。
- **音・触覚フィードバック**: 変更: 触覚は Full Access 有効時だけ ON にする（`KeyboardView.applySettings(haptics: hasFullAccess)`）。
- **起動の遅延**: 拡張は入力欄フォーカス時に都度ロードされるため、初期化を軽く保つ（辞書遅延ロード・スタブフォールバック）。
