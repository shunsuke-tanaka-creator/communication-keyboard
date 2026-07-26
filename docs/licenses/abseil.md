# abseil-cpp ライセンス

対象: Mozc が依存する abseil-cpp(`src/MODULE.bazel` の `com_google_absl`)。

## ライセンス種別

- **Apache License 2.0**
- Copyright Google LLC / Abseil authors。
- 出典: https://github.com/abseil/abseil-cpp/blob/master/LICENSE

## 要件(要旨)

Apache-2.0:

1. ライセンス全文の複製を配布物に含める。
2. 改変したファイルには変更を示す告知を付す。
3. `NOTICE` ファイルが存在する場合はその内容を配布物に保持する。
4. 特許ライセンス条項あり(訴訟提起時の終了条項)。
5. 無保証。

→ 研究用アプリへの組み込み・再配布は **可能**。Apache-2.0 全文 + NOTICE の同梱が条件。

## 本プロジェクトでの順守

- アプリ内ライセンス表示に Apache-2.0 全文と abseil の NOTICE を含める。
- 取り込むバージョンは選定 Mozc タグの `src/MODULE.bazel` で確定(調査時点 upstream では abseil `20250814.x` 系が言及)。実ビルド時にバージョン固定・原文確認。
