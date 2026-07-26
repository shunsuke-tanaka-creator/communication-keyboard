# その他サードパーティ依存ライセンス

対象: Mozc のビルド/実行に関わるその他の bzlmod 依存および `src/third_party/`。
選定 Mozc タグの `src/MODULE.bazel` / 各サブディレクトリで最終確認すること。

## bzlmod 依存(調査時点で確認できたもの)

| 依存 | 主なライセンス | 備考 |
|------|--------------|------|
| bazel_skylib | Apache-2.0 | Bazel 汎用マクロ。ビルド時のみ。 |
| rules_python | Apache-2.0 | Python ビルドルール。ビルド時のみ。 |
| build_bazel_apple_support (apple_support) | Apache-2.0 | Apple CC ツールチェイン。iOS/macOS ビルドに必要。 |
| rules_apple(iOS ターゲット追加時に使用想定) | Apache-2.0 | iOS ライブラリ/バンドル生成。 |
| rules_cc | Apache-2.0 | C/C++ ビルドルール。 |

> これらの多くは **ビルドツールチェイン**であり、生成物(アプリ)に直接コードが混入しないものもある。ただし配布物に含まれる場合はライセンス同梱要。

## `src/third_party/`

- Mozc の `src/third_party/` 配下はサブディレクトリごとに個別ライセンス(BSD / MIT / Unicode 等)を持つ。
- 参考: AUR パッケージの license 表記は `Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NAIST-2003 AND Unicode-3.0 AND LicenseRef-Okinawa-Dictionary` と多数のライセンスの複合であることを示す。
- **選定タグをチェックアウト後、`src/third_party/` の各 README/COPYING を列挙して確定すること**(本調査では全数確認は未実施 = 未解決)。

## Unicode 系データ

- 絵文字/記号データ等に Unicode ライセンス(Unicode-3.0)が関与する。該当データを同梱する場合は Unicode ライセンス表記を含める。

## 本プロジェクトでの順守

- 最終的な同梱物に含まれる依存を洗い出し、それぞれのライセンス全文/表記をアプリ内ライセンス表示に集約する。
- ビルド専用ツール(生成物に含まれないもの)は原則同梱不要だが、判断に迷う場合は含める側に倒す。
