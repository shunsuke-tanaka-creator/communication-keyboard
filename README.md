# MozcFlickKeyboard

iOS用フリック/QWERTYキーボードと研究ログ収集アプリです。かな漢字変換はMozc、SimulatorはLocalStubEngineを使います。候補学習・ユーザー辞書は端末内で動作します。入力・回答・HealthKit/予定などの研究ログは、設定した [Pythonサーバー](https://github.com/shunsuke-tanaka-creator/switch_bot_python) へ同期します。

GPS分類・座標収集・位置による通知起動は廃止しています。拠点とタスクは行動情報と本人回答で別々に扱います。

## 開発環境とビルド

macOS、Xcode（iOS 15以上を対象にできるSDK）、XcodeGen、実機MozcビルドにはBazelisk・git・rsyncが必要です。SimulatorのビルドとXCTestは[GitHub Actions](https://github.com/shunsuke-tanaka-creator/communication-keyboard/actions/workflows/validate.yml)のmacOS 15環境で実行します。2026-11-12の検証環境はXcode 16.4 / XcodeGen 2.46.0です。実機Mozcビルド・署名の検証とは区別します。

SimulatorはMozcの取得・辞書生成をせずに構成できます。

```sh
./scripts/generate_xcode_project.sh
xcodebuild test -project MozcFlickKeyboard.xcodeproj -scheme MozcFlickKeyboard -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

期待：プロジェクト生成成功、利用可能なSimulatorで `** TEST SUCCEEDED **`。
意図しない出力：`xcodegen が見つかりません` / `Unable to find a destination` / `** TEST FAILED **`。必要ツールとインストール済みSimulator名を確認します。Simulator変換はstubで、実Mozcの品質検証にはなりません。

実機用Mozcは次の順で準備します。初回は外部依存の取得と長時間ビルドを伴います。

```sh
./scripts/bootstrap.sh
./scripts/build_mozc_ios.sh
./scripts/generate_xcode_project.sh
```

期待：固定SHA/patchの確認、arm64静的ライブラリ・辞書・必要ヘッダの検証後に `build_mozc_ios 完了`。
意図しない出力：revision不一致、patch競合、Bazel失敗、成果物不足。非0で停止し、既存checkoutを勝手に更新しません。元のローカルMozcに独自差分がある場合は保存して比較してください。

固定元は既存調査文書のMozcタグ `2.32.5994.102`、対応commit `d9c3f195582de6b0baa07ecb81a04e8902acf9af`。`scripts/mozc-revision.txt`、`.bazelversion`（8.4.1）、`scripts/patches/mozc-ios-archive.patch` を管理します。以前のMac成功環境の未共有diffとの同一性は確認できておらず、**今回管理したpatchのclean実機ビルドは未検証**です。新しい版へ自動fallbackしません。

成功した成果物は `out/mozc/` の `libmozc_ios.a`、`mozc.data`、`include/`、`build-manifest.txt`。一時ディレクトリで検証後に切り替え、前回成果物を `out/mozc-previous.*` に残します。実機SDKだけ辞書をアプリへコピーし、欠落ならビルドを止めます。XCFrameworkは生成しません。bridgeは固定上流と同じC++20でコンパイルします。

## 署名・設定

`Config/Project.xcconfig` の `PRODUCT_BUNDLE_PREFIX` と `APP_GROUP_ID` が共有設定です。既存値は `com.tanaka05.MozcFlickKeyboard` / `group.com.tanaka05.MozcFlickKeyboard` を維持します。target IDとBGTask識別子はprefixを参照します。TeamはXcodeのSigning & Capabilitiesで選択してください。

App GroupをApp/Extensionの両方の署名へ登録します。**既存インストールのIDを変えると以前のコンテナを参照できません。** ID変更を更新手順として行わないでください。

実機で親アプリを起動し、iOS設定 → 一般 → キーボードから追加します。研究機能にはフルアクセスが必要です。設定のBackend URLに自分のMacのTailscale URLを入力します。新規の既定URLは空欄、保存済みURLは保持します。

## 研究・プライバシー

- フルアクセス＋プライベートモードOFFで入力ログを記録。本文・前後文脈を含みます。通常の診断ログには入力本文・回答本文を出しません。
- プライベートモードは入力収集と候補学習を止めます。既存queueや明示的な研究回答は削除しません。通信停止にはBackend URLを空欄にします。
- サーバー設定済みの場合、204/通信失敗では質問を表示せず、ローカル質問へfallbackしません。URL未設定時のみローカルTriggerを使います。
- 既定4質問は現在状態・夜の振り返り・天気・拠点/タスク日替わり各1。発行判断はサーバー側です。条件を満たさない場合は4件未満です。
- 日本語確定・英数字・記号は共通のcommitイベント。英語候補の置換は `replaces` も付けます。研究回答の入力は通常の入力欄に挿入しません。
- 回答はローカルJSONLと送信queueの保存成功後に回答済みとします。保存失敗時はエラー表示し、自由入力/5尺度フォームを保持します。通信待ちは保存失敗と区別します。
- 不正JSONとHTTP400/413/422は原本を `.failed-*` へ隔離して後続を送信します。401/403/429/5xxや通信断はqueueに残します。隔離は削除ではありません。

詳しくは [プライバシー](docs/privacy.md)、[研究フロー](docs/narrative-integration.md)、[拠点・タスク](docs/behavior-context.md)、[サーバー接続](docs/macbook-lifelog.md)、[検証](docs/testing.md)、[監査修正一覧](docs/audit-fixes.md) を参照。

## 構成

| パス | 役割 |
| --- | --- |
| `App/` | 設定・回答・HealthKit/予定収集・通知・サーバー画面 |
| `Keyboard/` | フリック/QWERTY、変換候補、入力状態、質問表示 |
| `Shared/Conversion`, `Shared/Learning`, `Shared/UserDictionary` | 端末内変換と個人化 |
| `Shared/Research/` | API、セッション/イベントqueue、保存排他、入力イベント境界 |
| `Shared/Narrative/` | 質問モデル、回答repository、ルール判定 |
| `MozcBridge/` | SwiftとMozc C++の接続 |
| `Tests/` | XCTestと共通API fixture |
| `scripts/`, `Config/`, `docs/` | 固定ビルド手順、署名設定、仕様 |

ソースの上位ルートは `MozcFlickKeyboard/`。既存のApp/Extension/Shared targetを維持します。モデルの研究学習はPython側で行います。

## ライセンス

Mozc・辞書・推移的依存は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) と [docs/licenses/](docs/licenses/README.md) を確認してください。過去の調査・実機記録はGit履歴と `docs/initial-research.md` / `docs/assumptions.md` に残します。現在の手順はこのREADMEを優先します。
