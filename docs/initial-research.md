# Mozc 初期調査レポート (MozcFlickKeyboard)

対象: iPhone専用12キー日本語フリックキーボード「MozcFlickKeyboard」の変換エンジンとして Mozc を採用するための調査。
調査日: 2026-07-13
担当: Mozc 調査・安定リビジョン選定・ライセンス確認

このドキュメントは「確認できた事実」と「不確実な点/仮定」を明確に分けて記述する。
仮定の一覧は `docs/assumptions.md` に、ライセンス詳細は `docs/licenses/` にまとめる。

---

## 1. Mozc の現行構成 (確認できた事実)

- リポジトリ: https://github.com/google/mozc (Copyright 2010-2026 Google LLC)。
- Mozc は「Google 日本語入力」由来のオープンソース IME だが、**公式サポート対象は Linux / Windows / macOS / Android(ライブラリ)** であり、Mozc 自体は "not an officially supported Google product" と明記されている。
- ソースは `src/` 配下に集約。ビルドは **Bazel(bazelisk 経由)へ移行済み**。旧 GYP ビルドは廃止方向。
  - `src/.bazeliskrc` で使用する Bazel バージョンを固定している。
  - `src/MODULE.bazel` (bzlmod) で依存(abseil, protobuf, bazel_skylib, rules_python, apple_support 等)のバージョンを固定している。
- CI(GitHub Actions)は Linux / Windows / macOS / Android library の 4 種のみ。**iOS 用ワークフローは存在しない。**
- バージョン番号の 3 番目の数値はバージョニング開始日からの経過日数。例: `2.32.5981` の `5981` は経過日数。
- **重要: Mozc には「安定版(Stable Release)」の概念が無い。** 公式ドキュメント(README の Release Plan)に "There is no stable version." と明記され、非自明な変更ごとにバージョン番号を上げるだけで、OSS 版に公式 QA は無い。したがって「安定リビジョン選定」は *タグが打たれ、Linux ディストリ等で実運用実績があるバージョンを選ぶ* という意味になる。

### 変換 API の概要 (確認できた事実 + 一部は過去リビジョン由来)

Mozc の変換処理は概ね以下の層構造(名称・構造は現行コードを優先して理解すること。以下は調査時点の理解):

- `session/session_handler.*` (`SessionHandler`): Mozc サーバのセッション管理。`NewSession()` でセッションを生成し、キーイベント(`commands::Command` / protobuf)を処理する中枢。
- `session` レイヤ: ユーザー入力(composition)と変換器の橋渡し(`SessionConverter` 等)。
- `engine/engine.*` (`Engine` / `EngineInterface`): 変換器(converter)、予測器(predictor)、リライタ(rewriter)を束ねるコア。`DataManagerInterface` と predictor factory を受け取り初期化する。
- `engine/engine_factory` / `MinimalEngine` / `MockDataEngineFactory`: エンジン生成のファクトリ群。OSS ビルドでは OSS 辞書データを持つ `DataManager` を用いてエンジンを構築する。
- 予測/学習: `prediction/`(`DictionaryPredictor`, `UserHistoryPredictor` 等)。`UserHistoryPredictor` によりユーザー学習(履歴)を担う。`GetUserDataManager()->Sync()` / `ClearUserHistory()` 等で学習データの同期・消去が可能。
- 入出力は基本的に **protobuf(`protocol/commands.proto` の `commands::Command` / `Input` / `Output`)** でやり取りする。キーボード拡張からはこの Command ベース API を叩くのが素直。

> 注: 上記の一部(session_factory 周りの細部)は過去リビジョンのコードから確認したもので、現行 master では名称・分割が変わっている可能性がある。**実装時は必ず選定リビジョンの実コードを確認すること**(ユーザールール: コード上のメモより実コードを優先)。

---

## 2. iOS / Apple Silicon 対応状況 (確認できた事実)

- **iOS 専用のコードは存在する。** `src/ios/` ディレクトリがあり、`src/ios/BUILD`(Bazel)と iOS 向け実装(例: `src/ios/session/ios_engine.mm`)が含まれる。これは 12 キー UI ではなく **Mozc エンジンを iOS から叩くための薄いラッパ/セッション層**。
- ただし公式に「Mozc does not officially support iOS build.」と明記されており、**iOS 向けの公式ビルド手順・CI・保証は無い。**
- Bazel の `mozc_select()` マクロには `ios` プラットフォーム分岐が定義済み(例: `ios = ["MOZC_USE_MOZC_TESTING"]`)。つまり **iOS ターゲットの存在自体はビルド定義に組み込まれている**が、メンテ・検証はされていない。
- Apple Silicon(arm64)まわり:
  - macOS 向けは **ARM64 ビルド対応済み**(`--macos_cpus=arm64` / Universal Binary 対応)。macOS の最低対応は **macOS 12 以降**に引き上げ済み。
  - Bazel の依存に `build_bazel_apple_support`(apple_support)が含まれており、Apple プラットフォーム向けの CC ツールチェインは利用可能。Bazel 7 以降では Apple ターゲット時にこのツールチェインが必須で、`--incompatible_enable_cc_toolchain_resolution` によりターゲットに応じたツールチェインが自動選択される。
  - Xcode のフルインストールが必要(Command Line Tools だけでは不可)。

### iOS arm64 クロスコンパイルの実現性 (事実 + 評価)

- 事実: Mozc 本体は C++/Objective-C++ の集合で、`cc_library` として Bazel でビルドされる。Apple 向けは `rules_apple` / `apple_support` を用いて iOS ターゲット(`--cpu=ios_arm64` 実機 / `--cpu=ios_sim_arm64` Apple Silicon シミュレータ)を指定できる。
- 事実: macOS/arm64 ビルドが動作している以上、Mozc のコア C++ 部分は arm64 でコンパイル可能。
- 評価(不確実): Mozc の Bazel 定義に `ios` 分岐はあるが検証されていないため、**Keyboard Extension 用の静的ライブラリ / framework として Mozc コアを arm64 でビルドするには、`rules_apple` の `apple_static_library` 等を用いた独自 BUILD ターゲットの追加が必要になる見込み**。ここは要実験・要検証(未解決点)。

### Keyboard Extension への組み込み (評価)

- iOS のキーボードは App Extension(`.appex`)として提供する。Mozc コアを **静的ライブラリ or xcframework** にまとめ、Extension ターゲットにリンクする構成が現実的。
- Extension はメモリ制限が厳しい(目安として数十 MB オーダー)。Mozc の system dictionary をロードするため、**メモリ使用量の検証が必須**(未解決点)。
- 変換 API は protobuf ベースの Command を介するため、`src/ios/session/ios_engine.mm` 相当のラッパを土台に Swift から呼び出すブリッジを実装するのが素直。

---

## 3. 選定した Mozc リビジョン

### 選定結果

- **タグ: `2.32.5994.102`**
- **コミットハッシュ: `d9c3f195582de6b0baa07ecb81a04e8902acf9af`**
- 取得: `git clone https://github.com/google/mozc.git && cd mozc && git checkout d9c3f195582de6b0baa07ecb81a04e8902acf9af`(サブモジュール/依存は bzlmod・build スクリプトで解決)

### 選定理由 (根拠)

1. **最新 HEAD を避けタグを選定した理由**: Mozc は "There is no stable version" を公言し master は日々変化する。再現性(同一結果を将来も得られること)を担保するには、**明示的にタグが打たれたリビジョンをピン留め**するのが安全。HEAD ピン留めは調査時点の master が動いても将来の追試で壊れうる。
2. **2.32 系を選ぶ理由**: 2.32 系で以下が完了している(確認できた事実):
   - **ARM ビルド対応(macOS / Windows)** — Apple Silicon 前提の本プロジェクトに必須。
   - **全環境の Bazel 移行完了(GYP 廃止方向)** — 本プロジェクトは Bazel ビルドを推奨方針とするため整合的。
   - **macOS 12 以降対応への引き上げ** — 近年の Xcode/ツールチェインと整合。
3. **`2.32.5994.102` を選ぶ理由(2.32 系の最新タグ)**: GitHub の tags 一覧で 2.32 系として打たれているタグは `2.32.5994.102` のみ(その次は 3.33/3.34 系へ移行)。2.32 系の中で最も新しく、ARM/Bazel 対応が入った後の安定点として妥当。`.102` サフィックスは OSS リリース系列を示す。
4. **Linux ディストリでの実運用実績**: 2.31 系(`2.31.5810.102` 等)が openSUSE / Debian 等でパッケージ化・運用されており、この近傍の系列はビルド・動作の実績がある。2.32 系はその直後の系列。

### 代替候補 (フォールバック)

- もし `2.32.5994.102` で iOS/arm64 のビルドに問題が出た場合の後退先として **`2.31.5851.102`**(sha: `d703e617246b3916edcb5b95812badef1a2764bc`)。2.31 系は Linux ディストリでの実績が最も厚い。
- さらに新しい挙動が必要なら `3.33.6089`(sha: `8f92cd985cba2fd009545963698f4df7424bec56`)以降を検討(ただし新しいほど破壊的変更リスクは上がる)。

> 注意(不確実): 上記選定は「タグの新しさ」「ARM/Bazel 対応の有無(公開情報ベース)」から行っている。**選定タグで iOS arm64 の実ビルドが通ることは未検証**。最初のマイルストーンで `bazelisk build` による arm64 ビルド疎通を検証し、通らなければフォールバック候補へ切り替える方針とする。

---

## 4. 推奨ビルド方式

- **Bazel(bazelisk 経由)を推奨。** 理由:
  - Mozc 公式が全プラットフォームで Bazel に移行済みで、GYP は廃止方向。今から GYP を使う合理性が無い。
  - Apple プラットフォーム向けに `rules_apple` / `apple_support` が既に依存として存在し、iOS ターゲットの土台がある。
  - 依存(abseil / protobuf 等)のバージョンが `MODULE.bazel` で固定されており再現性が高い。
- バージョン固定: `src/.bazeliskrc` に従い bazelisk が適切な Bazel バージョンを取得する。**手動で Bazel を入れず bazelisk を使う**こと。
- 前提: **Xcode フルインストール**が必要(apple_support の CC ツールチェイン要件)。
- iOS 向けターゲットは Mozc に用意されていないため、**Mozc コアを `apple_static_library` / xcframework 化する独自 BUILD ターゲットを追加**する必要がある見込み(要実装・要検証)。

---

## 5. 最低対応 iOS バージョンの推奨

- **推奨: iOS 15.0 以上**(暫定・要合意)。
- 根拠:
  - Mozc 本体の制約というより、**iOS Keyboard Extension + SwiftUI/UIKit の実装容易性**と**現実的なユーザー分布**から決めるべき値。iOS 15 は SwiftUI が実用的で、キーボード拡張 API も安定。
  - Mozc の macOS 側が「macOS 12(2021 年秋)以降」に引き上げられている時期感と揃えると、同時期の iOS 15(2021 年秋)を下限にするのが整合的。
  - C++ 依存(abseil / protobuf の新しめのバージョン)は比較的新しい C++ 標準を要求するが、Xcode に同梱の clang でビルドするため、実行時 iOS バージョンの下限を強く縛るのは主に UI/API 側。
- 不確実な点: これは **Mozc の技術要件から一意に決まる値ではない**。研究用アプリのターゲット端末・iOS 分布に合わせて確定する必要がある(`docs/assumptions.md` の未決事項参照)。iOS 16 や 17 に引き上げると新 API が使える一方、対応端末が減る。

---

## 6. 辞書データ (system dictionary) の同梱可否 (確認できた事実)

- OSS 版 Mozc の system dictionary は `src/data/dictionary_oss/` にあり、**Google 日本語入力の辞書とは別物**(Web コーパス由来の大規模語彙は含まれない)。語彙は基本的に **IPAdic(mecab-ipadic-2.7.0-20070801)相当**。
- Collocation / Reading Correction / Suggestion Filter データは OSS 版では **プレースホルダのみ**(実データは Google 内部)。→ 予測/補正の品質は Google 日本語入力より低い点に留意。
- **同梱可否**: 辞書はライセンス条件(下記 §7・`docs/licenses/`)を満たせば再配布・製品組み込み可能。研究用アプリへの同梱は可能と評価(ただし著作権表示等の順守が条件)。

---

## 7. ライセンス概要 (詳細は docs/licenses/)

- **Mozc 本体(Google 作成コード)**: BSD 3-Clause License。
- **主要依存**:
  - protobuf: BSD 系(3-Clause 相当)。
  - abseil (abseil-cpp): Apache-2.0。
  - その他 bzlmod 依存(bazel_skylib, rules_python, apple_support 等)は Apache-2.0 系が中心。
- **辞書データ(`src/data/dictionary_oss/`)**: Mixed。
  - IPAdic 由来: NAIST(奈良先端科学技術大学院大学)の著作権表示付き BSD 系条件 + ICOT Free Software 条件。著作権表示と条項の同梱が必須。
  - 沖縄辞書: Public Domain(制限なし・商用組み込み可)。
- **商標/名称**: 「Google 日本語入力」「Google Japanese Input」「Gboard」等の名称・ロゴ・商標は **使用しない**。アプリ名・表記は「Mozc」ベースに留める(本アプリは "MozcFlickKeyboard")。README の about_branding.md でも Mozc と Google 日本語入力は別ブランドと明記。
- 詳細な条文・ファイル対応は `docs/licenses/README.md` および各ライセンスファイル参照。

---

## 8. リスクと未解決点

| # | 項目 | 種別 | 内容 |
|---|------|------|------|
| R1 | iOS arm64 実ビルド未検証 | 事実+リスク | Mozc に iOS 分岐はあるが公式ビルド/CI 無し。選定タグで arm64 ビルドが通るかは未検証。最初に疎通検証が必要。 |
| R2 | Keyboard Extension のメモリ制限 | リスク | Extension のメモリ上限が厳しく、system dictionary ロードで超過する恐れ。要計測。 |
| R3 | iOS 用 BUILD ターゲット不在 | 事実+作業 | Mozc コアを静的ライブラリ/xcframework 化する独自 Bazel ターゲットの追加が必要。 |
| R4 | 変換 API の現行構造 | 不確実 | 過去リビジョン資料と現行 master で名称/分割が異なる可能性。選定タグの実コードで再確認要。 |
| R5 | 予測/補正品質 | 事実 | OSS 辞書は IPAdic 相当でプレースホルダ多数。Google 日本語入力より変換品質は劣る。研究用途では許容だが要認識。 |
| R6 | 最低 iOS バージョン | 未決 | 技術要件から一意に決まらない。ターゲット端末分布で確定要(暫定 iOS 15)。 |
| R7 | Bazel/Xcode バージョン整合 | リスク | Bazel 9 移行・apple_support/Xcode バージョンの組合せで破壊的変更が起きうる(Discussion #1436 参照)。bazelisk のピンに従う。 |
| R8 | 辞書ライセンス表記義務 | 作業 | NAIST/ICOT の著作権表示・条項をアプリ内(ライセンス表示画面)に含める必要。 |

---

## 9. 参照

- Mozc リポジトリ / README(Release Plan, ライセンス): https://github.com/google/mozc
- about_branding.md: https://github.com/google/mozc/blob/master/docs/about_branding.md
- macOS ビルド手順: https://github.com/google/mozc/blob/master/docs/build_mozc_in_osx.md
- OSS 辞書 README: https://github.com/google/mozc/blob/master/src/data/dictionary_oss/README.txt
- LICENSE: https://github.com/google/mozc/blob/master/LICENSE
- 変更まとめ(2024/10–2025/10, ARM 対応・Bazel 移行・macOS12): https://zenn.dev/komatsuh/articles/komatsuh_mozc_updates_from_2024_10
- タグ一覧(GitHub API): https://api.github.com/repos/google/mozc/tags
- apple_support(Apple CC toolchain): https://github.com/bazelbuild/apple_support
