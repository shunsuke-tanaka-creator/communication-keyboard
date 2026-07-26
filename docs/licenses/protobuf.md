# protobuf ライセンス

対象: Mozc が変換 API(`commands::Command` 等)およびシリアライズに使用する protobuf。
Mozc の bzlmod 依存(`src/MODULE.bazel` の `com_google_protobuf`)として取り込まれる。

## ライセンス種別

- **BSD 3-Clause 系ライセンス**(protobuf は 3-Clause BSD で配布)。
- Copyright Google Inc. / protobuf authors。
- 出典: https://github.com/protocolbuffers/protobuf/blob/main/LICENSE

## 要件(要旨)

BSD 3-Clause と同様:

1. ソース/バイナリ再配布時に著作権表示・条件一覧・免責条項を保持/再掲する。
2. 著作権者名を事前許可なく派生製品の推奨/宣伝に使用しない。

→ 研究用アプリへの組み込み・再配布は **可能**。表記同梱が条件。

## 本プロジェクトでの順守

- アプリ内ライセンス表示に protobuf の著作権表示とライセンスを含める。
- 実際に取り込むバージョンは選定 Mozc タグの `src/MODULE.bazel` で確定する(例として調査時点の upstream 議論では protobuf 32/33 系が言及されていた)。バージョンとライセンス原文は実ビルド時に固定・確認する。
