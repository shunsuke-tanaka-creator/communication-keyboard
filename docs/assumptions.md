# 調査上の仮定・未決事項 (assumptions.md)

Mozc 調査(初期リサーチ)で置いた仮定と、確認できていない未決事項の記録。
確定した事実は `docs/initial-research.md` に、仮定はここに分離する。
調査日: 2026-07-13

---

## 1. 置いた仮定 (Assumptions)

| # | 仮定 | 理由 | リスク/影響 |
|---|------|------|-----------|
| A1 | ビルドは Bazel(bazelisk)方式を採用する | Mozc が全環境 Bazel へ移行済み・GYP 廃止方向 | 低。upstream 方針と一致 |
| A2 | 選定タグ `2.32.5994.102` で iOS arm64 ビルドを試みる | 2.32 系は ARM/Bazel/macOS12 対応が入った最新タグ | 中。iOS ビルドは未検証。通らなければ `2.31.5851.102` へ後退 |
| A3 | Mozc コアを静的ライブラリ / xcframework 化して Keyboard Extension にリンクする | iOS に既存の app/extension ターゲットが無いため | 中。独自 BUILD ターゲット追加が必要 |
| A4 | 変換 API は protobuf(`commands::Command`)ベースで叩く | session/engine 層がこの形式を採用 | 低〜中。現行 master の名称差異は要確認 |
| A5 | 最低対応 iOS を 15.0 とする(暫定) | macOS12(2021秋)と同時期・SwiftUI 実用ライン | 中。ターゲット端末分布で要再決定 |
| A6 | OSS 辞書(dictionary_oss)を同梱し、Google 日本語入力辞書は使わない | ライセンス上組み込み可・研究用途で十分 | 低。品質は劣るが要件上許容と仮定 |
| A7 | 予測/学習は UserHistoryPredictor ベースで実現可能 | 既存 API に学習機構あり | 中。iOS Extension のストレージ/同期挙動は要検証 |

---

## 2. 未決事項 (メインエージェント/開発者への確認事項)

以下は本調査だけでは確定できず、方針決定が必要な項目。

### ビルド / エンジン
1. **iOS arm64 実ビルドの疎通**: 選定タグで `bazelisk build`(`--cpu=ios_arm64` / `ios_sim_arm64`)が通るか。最初のマイルストーンで検証必須。通らない場合のフォールバック(2.31.5851.102 等)採用可否。
2. **Extension のメモリ制限**: system dictionary ロード時のメモリ使用量が Keyboard Extension の上限に収まるか。要計測。辞書を軽量化/分割する必要があるか。
3. **エンジン呼び出し方式**: `src/ios/session/ios_engine.mm` 相当のラッパをそのまま使うか、独自ブリッジ(Swift ↔ C++/Obj-C++)を書くか。

### バージョン / 対応範囲
4. **最低対応 iOS バージョン**: 15 / 16 / 17 のどれにするか(対応端末数 vs 新 API のトレードオフ)。研究対象端末は?
5. **選定タグの最終確定**: iOS ビルド検証結果を踏まえ `2.32.5994.102` を確定してよいか、より新しい 3.x 系を狙うか。

### 辞書 / 品質
6. **辞書品質の許容度**: OSS 辞書(IPAdic 相当・補正プレースホルダ)の変換品質で研究要件を満たすか。ユーザー辞書追加は必要か。
7. **学習データの永続化**: ユーザー学習を端末内のどこに保存するか(App Group 共有コンテナ等)。プライバシー要件は?

### ライセンス / 配布
8. **配布形態**: 研究内部配布のみか、TestFlight / App Store 配布まで想定するか(配布範囲でライセンス表記の厳密さが変わる)。
9. **`src/third_party/` の全数ライセンス確認**: 選定タグをチェックアウト後に個別確認が必要(本調査では未実施)。

---

## 3. 自由記述欄 (メモ・追記用)

<!-- 開発者・メインエージェントが方針・決定事項を追記する欄 -->

### 2026-07-14 iOS arm64 ビルド疎通 検証結果（未決事項1 → 解決）

選定タグ `2.32.5994.102` で **Mozc 変換エンジンコアの iOS arm64 静的ライブラリ化に成功**（A2/R1 クリア）。

- 環境: bazelisk 1.29.0（Mozc の `.bazeliskrc` により Bazel 8.4.1 使用）/ Xcode 26.2 / macOS Apple Silicon
- 生成物: `third_party/mozc/src/bazel-bin/ios/libios_engine.a`（arm64 / platform=iOS / minos 15.0）
- ビルドコマンド:
  ```
  cd third_party/mozc/src
  bazelisk build --config=macos_env --define TARGET=ios \
    --platforms=@build_bazel_apple_support//platforms:ios_arm64 \
    --ios_minimum_os=15.0 //ios:ios_engine
  ```
- 注意: `--config=oss_macos` は `TARGET=oss_macos` を強制し mac 専用コード(Cocoa)を引くため使えない。`macos_env`(コンパイラ設定のみ)+ `TARGET=ios` が正解。

必要だった Mozc 側パッチ（いずれも upstream の iOS 未メンテ由来。third_party 内を最小修正）:
1. `src/base/BUILD.bazel` `mozc_version_txt` の `mozc_select` に `ios = ["--target_platform=iOS"]` を追加（`--target_platform` 空エラー回避。`mozc_version.py` は 'iOS' を正式受理）。
2. `src/BUILD.bazel` の `//:macro` `defines` の `ios` 分岐に `MOZC_BUILD` を追加（`base/mac/mac_util.mm` の `#error Unknown branding` 回避）。

残課題（次マイルストーン）:
- ~~`libios_engine.a` は本体オブジェクトのみ。session/engine/protobuf/absl 等の依存 `.a` を集約して Xcode リンクする必要~~ → **2026-07-14 解決（下記）**
- 辞書データ `mozc.data`（`//data_manager/oss:mozc.data`）の iOS 同梱と `IosEngine(data_file_path)` への受け渡し。
- `MozcEngineBridge.mm` の実装（現状 TODO のみ。`ios/ios_engine.h` の protobuf Command API を呼ぶ）。
- Extension メモリ制限の検証（未決事項2 / R2）。

### 2026-07-14 ステップ1: 依存を含む集約静的ライブラリ 生成成功（A3 クリア）

`ios_engine` とその推移的依存を 1 本の iOS 用静的ライブラリに集約できた。

- 追加ターゲット: `src/ios/BUILD.bazel` に `apple_static_library(name="mozc_ios_combined", platform_type="ios", minimum_os_version="15.0", deps=[":ios_engine"])` を追加（`rules_apple` 4.1.2 を load）。
- ビルド: `bazelisk build --config=macos_env --define TARGET=ios --ios_multi_cpus=arm64 --ios_minimum_os=15.0 //ios:mozc_ios_combined`
- 成果物: `bazel-bin/ios/mozc_ios_combined_lipo.a` → `out/mozc/libmozc_ios.a` にコピー。
  - arm64 / iOS 15.0 / 381 オブジェクト（engine/session/protobuf/absl 含む）/ **71MB**（デッドコード除去前）。
  - `IosEngine::CreateSession` 等のシンボルが `T`(公開) で存在しリンク可能。
- ヘッダ: `out/mozc/include/ios/ios_engine.h` に収集。
- `scripts/build_mozc_ios.sh` を上記の検証済みコマンド/収集処理に更新済み。
- 注意: 71MB は静的段階のサイズ。Extension のメモリ制限(R2)は辞書ロード時のランタイム値で別途要検証。

### 2026-07-14 ステップ2: OSS 辞書データ mozc.data 生成成功

`IosEngine(data_file_path)` に渡す辞書データを生成できた。

- ターゲット: `//data_manager/oss:mozc.data`（`mozc_dataset` ルールの出力ファイル）。
- ビルド: `bazelisk build --config=oss_macos //data_manager/oss:mozc.data`（辞書はデータコンパイラのホスト成果物なので iOS フラグ不要）。
- 成果物: `bazel-bin/data_manager/oss/mozc.data`（**18MB**）→ `out/mozc/mozc.data` にコピー。
- `scripts/build_mozc_ios.sh` に辞書ビルド + 収集処理を追加済み。
- 次: Extension バンドルに `mozc.data` を同梱し、`MozcEngineBridge.mm` から `IosEngine(dataFilePath)` に絶対パスを渡して初期化する。

残課題:
- `MozcEngineBridge.mm` の実装（現状 TODO のみ。`ios/ios_engine.h` の protobuf Command API を呼ぶ）。
- Extension メモリ制限の検証（R2）: 静的71MB + 辞書18MB のランタイム消費が Extension 制限内か。

### 2026-07-14 ステップ3: MozcEngineBridge.mm 実 API 実装

`ios/ios_engine.h` の `IosEngine`(protobuf Command API) を呼ぶ実装を追加した（`MOZC_AVAILABLE` 定義時のみ有効。未定義時は従来スタブ）。

- 初期化: `MozcEngineBridge -initWithDataPath:` を追加（既存 `-init` は空パス委譲で互換維持）。
  - `IosEngine(data_file_path)` → `SetMobileRequest("12KEYS")` → `FillMobileConfig`/`SetConfig` → `CreateSession`。
  - `CreateSession` 成功で `_engineReady=YES`。失敗時はスタブ経路にフォールバック。
- 入力: `insertText:` は composed character 単位で `SendKey` を送信。`deleteBackward` は `SendSpecialKey(BACKSPACE)`。
- 変換/予測: モバイルは SendKey 応答にサジェストが載るため、直近 `Output`(_lastOutput) を `resultFromLastOutput` で辞書化して返す。
  - composition = `preedit.segment(i).value` 連結。candidates = `all_candidate_words.candidates` の `id`/`value`/`key`(=よみ)。
- 選択: `selectCandidateWithID:` は id を int へ戻して `SubmitCandidate(index)`。
- 確定: `commit` は `Submit` → `output.result().value`。取消: `cancelConversion`/`reset` は `ResetContext`。
- `moveFocusBy:`/`resizeFocusedSegmentBy:` はモバイル12キーで通常不使用のためスタブ据え置き（実 API 経路は未接続）。
- Swift 側 `MozcConversionEngine(dataPath:)` を追加。省略時は `Bundle.main.path(forResource:"mozc", ofType:"data")` を解決して渡す。
- 例外/文字コード方針は既存どおり（C++ 例外は各メソッドで try/catch、UTF-8<->UTF-16 明示変換）。

Xcode 結合時にメイン側で必要な設定:
- `MOZC_AVAILABLE` を Objective-C++/Swift 両方の compile flags に定義。
- `out/mozc/libmozc_ios.a` を Extension にリンク、`out/mozc/include`(ios_engine.h)＋`third_party/mozc/src`(protocol/*.pb.h)をヘッダ検索パスに追加。
- `out/mozc/mozc.data` を Extension バンドルの Resources に同梱（ファイル名 `mozc.data`）。

残課題:
- Extension メモリ制限の検証（R2）: 静的71MB + 辞書18MB のランタイム消費が Extension 制限内か（実機ビルドで確認）。

### 2026-07-17 不具合修正: 複数文字で候補が出ない（「あ」は出るが「あした」は出ない）

原因: 候補の取り出し先が誤り。`output.all_candidate_words()`(CandidateList) を使っていたが、
表示用候補は `output.candidate_window()`(CandidateWindow) に入る。`all_candidate_words` は
1文字サジェスト等では埋まるが通常の予測では空になり、複数文字入力で候補0件になっていた。
（公式サンプル `ios/ios_engine_main.cc` も `command.output().candidate_window().candidate(i)` を参照）

修正(`MozcEngineBridge.mm` `resultFromLastOutput`):
- 第一優先で `candidate_window().candidate(i)`（`group Candidate = 3`: index/value/id）から候補を取得。
  - `candidate_window` の Candidate は `key`(よみ)を持たないため、reading は composition で代用（表示には不要）。
- `candidate_window` が空のときのみ `all_candidate_words`(key あり) にフォールバック。
- デバッグログ追加: `[MozcEngineBridge] resultFromLastOutput composition=... candidates=N (window=? all=?)`。

エンジン種別確認用ログ(`KeyboardViewController`):
- 起動時に `[MFK] engine = MozcConversionEngine (MOZC_AVAILABLE=ON) isMozcAvailable=...`
  または `[MFK] engine = LocalStubEngine (MOZC_AVAILABLE=OFF)` を出力。
  → MOZC_AVAILABLE の有無と実エンジン初期化成否をログで判定できる。

### 2026-07-17 Mozc 実エンジン結合（MOZC_AVAILABLE=ON）: Xcode プロジェクト設定

これまで `project.yml` に `MOZC_AVAILABLE` 定義が無く、常に `LocalStubEngine` で動作していた
（＝「あ」は出るが「あした」で候補が出ない主因）。実エンジンをリンクする設定を追加した。

ヘッダ収集（`build_mozc_ios.sh` の成果物収集を拡張、`out/mozc/include` に集約）:
- `ios/ios_engine.h` は `protocol/*.pb.h` → `google/protobuf/*`, `absl/*` を推移的 include するため、
  それらをすべて 1 本のヘッダ検索パス `out/mozc/include` に収集する。
  - `protocol/*.pb.h`: `bazel-bin/protocol/*.pb.h`（生成物）
  - `absl/**`(.h/.inc): `bazel-src/external/abseil-cpp+/absl`
  - `google/**`(.h/.inc): `bazel-src/external/protobuf+/src/google`
  - 合計約 10MB（ヘッダのみ）。

`project.yml` 追加設定:
- `MozcFlickShared`（.mm を含むフレームワーク）:
  - `GCC_PREPROCESSOR_DEFINITIONS += MOZC_AVAILABLE=1`（ObjC++ 側 `#ifdef MOZC_AVAILABLE`）
  - `SWIFT_ACTIVE_COMPILATION_CONDITIONS: MOZC_AVAILABLE`
  - `HEADER_SEARCH_PATHS += $(SRCROOT)/out/mozc/include`
  - `LIBRARY_SEARCH_PATHS += $(SRCROOT)/out/mozc`、`OTHER_LDFLAGS += -lmozc_ios`
- `MozcFlickKeyboardExtension`（app-extension）:
  - `SWIFT_ACTIVE_COMPILATION_CONDITIONS: MOZC_AVAILABLE`（KeyboardViewController の `#if` 用）
  - `LIBRARY_SEARCH_PATHS`/`OTHER_LDFLAGS -lmozc_ios`（静的ライブラリは最終実行体で明示リンク）
  - `out/mozc/mozc.data` を `buildPhase: resources` で Extension バンドルへ同梱。
    → Swift 側 `MozcConversionEngine(dataPath:)` が `Bundle.main.path(forResource:"mozc", ofType:"data")` で解決。

注意/残課題:
- `out/mozc/libmozc_ios.a` は **arm64 実機専用**（Non-fat arm64）。
  シミュレータで Mozc 実エンジンを使うには `--ios_multi_cpus=sim_arm64`（+x86_64）で別途ビルドし xcframework 化が必要。
- リンク時に protobuf/absl のシンボルや C++ 標準ライブラリ関連で不足が出る可能性。出た場合は
  `OTHER_LDFLAGS` に `-lc++` や `-ObjC`、不足 framework を追加して対処（実機ビルドで確認）。
- Extension メモリ制限（R2）は実機ビルドで要確認（静的71MB＋辞書18MB）。

### 2026-07-22 シミュレータビルド対応（Mozc 関連設定を [sdk=iphoneos*] 限定に）

`libmozc_ios.a` が arm64 実機専用のため従来はシミュレータビルド不可だった。
`project.yml` の Mozc 関連設定（`MOZC_AVAILABLE` 定義 / `-lmozc_ios` / ヘッダ・ライブラリ検索パス）を
すべて `[sdk=iphoneos*]` 条件付きキーに変更し、**実機 SDK のときのみ** 適用するようにした。

- シミュレータ(`iphonesimulator*`): `MOZC_AVAILABLE` 未定義 → `#if MOZC_AVAILABLE` が偽になり
  `LocalStubEngine`（純 Swift）で動作。Mozc ライブラリはリンクしないためビルドが通る。
- 実機(`iphoneos*`): 従来どおり `MOZC_AVAILABLE=1` + `libmozc_ios.a` リンクで実 Mozc 経路。
- ソース（Swift/ObjC++）は既に `#if MOZC_AVAILABLE` / `#ifdef MOZC_AVAILABLE` で両対応済みのため変更不要。
- `mozc.data` はシミュレータでもバンドル同梱されるが `MozcConversionEngine` を生成しないため未参照（無害）。
- 検証: iPhone 16 シミュレータ / generic iOS Device いずれも `xcodebuild build ... ** BUILD SUCCEEDED **`。




