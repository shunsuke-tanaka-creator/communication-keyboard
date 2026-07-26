# テスト方針

MozcFlickKeyboard のテストは「単体」「UI」「実機」の 3 層で、確定済み契約（`JapaneseConversionEngine` とその値型）を中心に検証します。実装モジュール（`KanaTransform` / `LocalStubEngine` / `UserDictionaryStore` 等）は結合待ちのため、条件付きコンパイルで段階的に有効化します。

---

## 1. テストの種類とファイル

| ファイル | 種類 | 対象 | 有効化条件 |
| --- | --- | --- | --- |
| `Tests/ConversionEngineTests.swift` | 単体 | `JapaneseConversionEngine` 契約（モック実装で検証） | 常時 |
| `Tests/KanaInputTests.swift` | 単体 | かな入力（`KanaTransform` / `KanaTable`、API 仮定） | 実装結合後 |
| `Tests/FlickTests.swift` | 単体 | フリック方向判定（API 仮定） | 実装結合後 |
| `Tests/ConversionCaseTests.swift` | 単体/回帰 | 変換ケース（`LocalStubEngine` 対象） | `LOCAL_STUB_AVAILABLE` |
| `Tests/UserDictionaryTests.swift` | 単体/性能 | ユーザー辞書（`UserDictionaryStore`、API 仮定） | `USER_DICT_AVAILABLE` |

> テストファイル冒頭に「モジュール名・対象 API が未確定な場合はメインが結合時に調整」と明記しています。`@testable import` のモジュール名（例: `MozcFlickKeyboardShared`）は結合時に確定します。

---

## 2. 条件付きコンパイルフラグ

実装が Shared に結合されたら、テストターゲットの `Active Compilation Conditions`（または `xcodebuild ... OTHER_SWIFT_FLAGS='-D FLAG'`）に以下を追加して有効化します。

- `LOCAL_STUB_AVAILABLE` … `LocalStubEngine` を用いる契約/変換ケーステスト
- `USER_DICT_AVAILABLE` … `UserDictionaryStore` を用いる辞書テスト

---

## 3. 実行方法

### Xcode
- `Product > Test`（⌘U）。個別実行はテストナビゲータから。

### CLI
```bash
xcodebuild test \
  -project MozcFlickKeyboard.xcodeproj \
  -scheme MozcFlickKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

フラグを有効化して実行する例:
```bash
xcodebuild test \
  -project MozcFlickKeyboard.xcodeproj \
  -scheme MozcFlickKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  OTHER_SWIFT_FLAGS='-D LOCAL_STUB_AVAILABLE -D USER_DICT_AVAILABLE'
```

---

## 4. 対応入力欄のテスト（UI テスト方針）

Custom Keyboard の制約（[ios-keyboard-limitations.md](ios-keyboard-limitations.md)）を踏まえ、次の入力欄種別で手動/自動 UI テストを行います。

- 通常テキスト欄（`UITextField` / `UITextView`）
- `keyboardType = .numberPad` / `.phonePad`（数字系レイアウト）
- `.URL` / `.emailAddress`
- `isSecureTextEntry`（標準キーボードへ切替されることを確認）

UI テストは XCUITest で、キーボード表示 → キー押下 → ホスト欄の文字列アサートを基本形とします。

---

## 5. 日本語変換のテスト

- **かな入力**: あいうえお / かきくけこ / がぎぐげご / ぱぴぷぺぽ / ぁぃぅぇぉ / っゃゅょ / わをんー / 、。！？ を網羅（`KanaInputTests`）。
- **変換ケース**: 定番は第1候補一致、長文・予測・日付/時刻/数値は「候補に含まれること」を検証（`ConversionCaseTests`）。
  - 例: `へんかん→変換`、`とうきょうと→東京都`、`きょうはいいてんきです→今日はいい天気です`（含有）。
- 期待値が Mozc のバージョンで揺れる場合は、スタブ辞書側で固定するか strictness を緩める。

---

## 6. 性能テスト

- `UserDictionaryTests` の `measure` ブロックで 100 / 1000 / 10000 件の登録・検索を計測。
- 変換系の初期化・候補生成時間は [performance.md](performance.md) の目標値に対して計測。
- XCTest のパフォーマンスベースラインを記録し、回帰を検出する。

---

## 7. メモリテスト

- 拡張のメモリ上限（[ios-keyboard-limitations.md](ios-keyboard-limitations.md)）に対し、辞書ロード後・大量入力後のピークメモリを Instruments（Allocations / Leaks）で測定。
- 目標値は [performance.md](performance.md) を参照。

---

## 8. 回帰テスト方針

- `ConversionCaseTests` を変換の回帰スイートとして維持。新たな不具合を見つけたら「よみ→期待」を1行追加する運用。
- Mozc やスタブ辞書を更新した際は本スイートを必ず実行。
- CI では Simulator でユニット/回帰テストを実行し、実機依存（署名・キーボード追加）は手動チェックリストで補完。
