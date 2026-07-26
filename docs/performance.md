# 性能目標と測定方法

Custom Keyboard Extension は起動が都度発生し、メモリ上限も厳しい（[ios-keyboard-limitations.md](ios-keyboard-limitations.md)）ため、初期化と応答性を重視します。以下は目標値と測定方法です。目標値は開発機・実機での目安であり、実測後に調整します。

---

## 1. 目標値（初期目安）

| 指標 | 目標値 | 備考 |
| --- | --- | --- |
| Mozc 初期化（辞書ロード） | ≤ 1500 ms（初回起動） | 起動時に先読み。初回入力までに完了を目指す |
| 初回候補（初期化後の最初の変換） | ≤ 150 ms | ウォームアップ直後 |
| 通常候補（2回目以降の変換） | ≤ 50 ms | 体感即時 |
| 予測候補（サジェスト） | ≤ 50 ms | 入力ごとに呼ばれる |
| フリック判定 | ≤ 5 ms | UI スレッドを塞がない |
| 辞書サイズ（同梱 Mozc 辞書） | 実測記録（目安 数十 MB） | mmap で常駐を抑制 |
| 拡張ピークメモリ | ≤ 40 MB 目安 | OS 上限に対し余裕を確保 |

辞書件数別のユーザー辞書検索時間目標:

| 件数 | 検索目標 |
| --- | --- |
| 100 件 | ≤ 1 ms |
| 1,000 件 | ≤ 5 ms |
| 10,000 件 | ≤ 20 ms |

> 実装が線形探索の場合、件数増でこの目標を超える可能性があります。超過時は索引（よみ→エントリの辞書）を導入します。

---

## 2. 測定方法

### 2.1 Mozc 初期化・候補生成時間

- コード計測: `CFAbsoluteTimeGetCurrent()` または `os_signpost` で区間を囲む。
  - 区間 A: エンジン初期化開始〜完了。
  - 区間 B: `requestConversion()` 呼び出し前後。
- Instruments の **os_signpost / Time Profiler** で区間を可視化。

### 2.2 ユーザー辞書検索時間（件数別）

- `Tests/UserDictionaryTests.swift` の `measure` ブロックで 100 / 1000 / 10000 件を計測。
- XCTest の**パフォーマンスベースライン**を保存し、回帰を自動検出。

```bash
xcodebuild test \
  -project MozcFlickKeyboard.xcodeproj \
  -scheme MozcFlickKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:MozcFlickKeyboardTests/UserDictionaryTests \
  OTHER_SWIFT_FLAGS='-D USER_DICT_AVAILABLE'
```

### 2.3 メモリ

- Instruments の **Allocations / Leaks / VM Tracker** で、辞書ロード後と大量入力後のピークを測定。
- 実機（拡張プロセス）で測定すること。Simulator は上限挙動が実機と異なる。

### 2.4 辞書サイズ

- 同梱する Mozc 辞書ファイルのサイズを記録（`out/mozc` の成果物を含む）。バージョンは [initial-research.md](initial-research.md) を参照。

---

## 3. チューニング指針

- 初期化が遅い → 辞書の遅延ロード / mmap / 起動時プリウォーム。
- 候補生成が遅い → セッション再利用、不要な候補数の制限。
- 辞書検索が遅い → よみをキーにした辞書（`[String: [Entry]]`）で O(1) 近似。
- メモリ超過 → 常駐データ削減、キャッシュ上限設定、画像・大バッファ排除。
