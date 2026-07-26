# Mozc 本体ライセンス

## ライセンス種別

- **BSD 3-Clause License**
- Copyright 2010-2026 Google LLC
- 出典: https://github.com/google/mozc/blob/master/LICENSE, README の License セクション

## 概要

Mozc の Google が作成したコード(`src/` 配下の大部分、`src/third_party/` および一部辞書データを除く)は BSD 3-Clause License で配布される。

BSD 3-Clause の要件(要旨):

1. ソース再配布時は著作権表示・条件一覧・免責条項を保持する。
2. バイナリ再配布時は上記を同梱ドキュメント等に再掲する。
3. 著作権者名・貢献者名を、事前の書面許可なく派生製品の推奨/宣伝に使用しない。

→ 研究用アプリへの組み込み・再配布は **可能**。上記表記の同梱が条件。

## 本プロジェクトでの順守

- アプリ内ライセンス表示に Mozc の BSD 3-Clause 全文 + Copyright 2010-2026 Google LLC を含める。
- 「Google 日本語入力 / Google Japanese Input / Gboard」の名称・商標は使用しない(条項3および商標保護の観点)。
- `src/third_party/` 配下は各サブディレクトリごとに別ライセンスがあるため、選定タグで個別確認する。

## 注意

- Mozc は "not an officially supported Google product" であり、無保証(BSD 免責条項どおり)。
