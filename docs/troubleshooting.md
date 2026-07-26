# トラブルシューティング（ビルドエラーと解決）

想定されるビルド/実行時の問題と解決策をまとめます。**実際に遭遇したエラーはメインが後日ここへ追記**してください（下部に追記欄あり）。

---

## 1. Mozc / Bazel 関連

### `bazelisk が見つかりません`
- 原因: bazelisk 未導入。
- 解決: `brew install bazelisk` を実行後、`./scripts/bootstrap.sh` を再実行。

### `Mozc ソースがありません: .../third_party/mozc`
- 原因: `bootstrap.sh` 未実行、または clone 失敗。
- 解決: `./scripts/bootstrap.sh` を実行。ネットワーク/URL/リビジョンを確認（[initial-research.md](initial-research.md)）。

### `Bazel の WORKSPACE/MODULE.bazel が見つかりません`
- 原因: Mozc のディレクトリ構成が想定と異なる（`src/` 有無など）。
- 解決: `third_party/mozc` の構成を確認。`build_mozc_ios.sh` は `src/` → ルートの順に探索する。

### `Mozc の Bazel ビルドに失敗しました`
- よくある原因と対処:
  - ターゲット名不一致 → `MOZC_BAZEL_TARGET` を環境変数で指定。
  - iOS toolchain / Xcode 設定不足 → `xcode-select -p` を確認、必要なら `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。
  - `--config=oss_macos` などの config 名変更 → Mozc の `docs/build` を参照。

---

## 2. Xcode プロジェクト生成 / 署名

### `scripts/generate_xcode_project.sh` が無い / 失敗する
- 原因: 生成スクリプト未整備、または XcodeGen 未導入。
- 解決: `brew install xcodegen`。スクリプトの前提はメインが整備（[README](../README.md) の該当節参照）。

### `Signing for "..." requires a development team`
- 原因: `DEVELOPMENT_TEAM` 未設定。
- 解決: `Config/Project.xcconfig` の `DEVELOPMENT_TEAM` を自分の Team ID に設定（Xcode > Settings > Accounts で確認）。

### `Failed to register bundle identifier` / Provisioning エラー
- 原因: Bundle ID 重複、App Group 未作成。
- 解決: `PRODUCT_BUNDLE_PREFIX` を一意な値に変更。App Group（`APP_GROUP_ID`）を Developer で作成し両ターゲットに追加。

---

## 3. App Group / 共有データ

### 拡張から辞書・設定が読めない
- 原因: App Group が両ターゲットで有効化されていない / ID 不一致。
- 解決: ホスト・拡張の Signing & Capabilities で同一の App Group を有効化。`AppConfig.appGroupID` と `Config/Project.xcconfig` の `APP_GROUP_ID` を一致させる。

### `containerURL(forSecurityApplicationGroupIdentifier:)` が nil
- 原因: App Group エンタイトルメント未付与。
- 解決: エンタイトルメント（App Groups）を再確認し、再署名。

---

## 4. Keyboard Extension 実行時

### キーボードが一覧に出ない
- 解決: ホストアプリを一度起動 → 設定 > 一般 > キーボード > 新しいキーボードを追加。

### 入力しても文字が入らない
- 原因: セキュア欄（`isSecureTextEntry`）、または未確定文字列の未確定状態。
- 解決: 通常のテキスト欄で確認。確定操作（`commit`）が呼ばれているか確認（[ios-keyboard-limitations.md](ios-keyboard-limitations.md)）。

### 拡張がすぐ落ちる
- 原因: メモリ超過の可能性。
- 解決: Instruments でピークメモリ確認、辞書の遅延ロード（[performance.md](performance.md)）。

---

## 5. テスト

### `LocalStubEngine` / `UserDictionaryStore` が未解決でテストがビルドできない
- 原因: 実装未結合、フラグ未定義。
- 解決: 実装結合後に `-D LOCAL_STUB_AVAILABLE` / `-D USER_DICT_AVAILABLE` を付与（[testing.md](testing.md)）。

### `@testable import` でモジュールが見つからない
- 原因: モジュール名不一致。
- 解決: テストファイル冒頭コメントの通り、実際の Shared モジュール名へ import を修正（メインが結合時に確定）。

---

## 6. 追記欄（メインが実エラーを記録）

<!-- 実際に遭遇したビルドエラーと解決を、日付・エラーメッセージ・原因・対処の順で追記してください。 -->

| 日付 | エラー概要 | 原因 | 対処 |
| --- | --- | --- | --- |
|  |  |  |  |
