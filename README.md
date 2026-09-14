# MozcFlickKeyboard

iPhone 専用の 12 キー日本語フリックキーボード（Custom Keyboard Extension）です。かな漢字変換エンジンに [Mozc](https://github.com/google/mozc) を用います。**通常のキーボード入力は完全に端末内で完結し、入力本文を外部へ送信しません。** 研究用の追加機能「お天気分」のみ、研究者が Backend URL を設定した場合に限り研究データ（回答・打鍵統計等）を任意送信します（既定はオフ。詳細は [docs/narrative-integration.md](docs/narrative-integration.md)）。

> 研究用途（久保田研究室）で開発しています。名称・商標について「Google 日本語入力」の名称は使用しません（[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 参照）。

---

## 概要

- **対象**: iPhone（iPad 非対応 / `TARGETED_DEVICE_FAMILY = 1`）
- **入力方式**: 12 キーフリック入力（トグル入力併用可）
- **変換エンジン**: Mozc（C++）を iOS 向けにクロスビルドし、Swift から呼び出す
- **オフライン**: 変換・学習・ユーザー辞書はすべて端末内で完結
- **構成**: ホストアプリ（設定・辞書管理）＋ Keyboard Extension（実際の入力）

### 研究機能「お天気分」（micro-diary）

- キーボード上部に短い質問バナー（朝の気分・夜の振り返り・外出/帰宅など）を1問だけ表示し、1〜2 タップまたは短い自由記述で回答できる研究用マイクロ日記機能です。
- 回答は研究データ（`NarrativeEvent`）として端末内に保存され、**ホストアプリのテキスト欄には一切挿入されません**。通常入力の本文は収集・送信しません。
- **Backend への送信は任意で既定オフ**（Backend URL 未設定なら端末内のみ）。実装・データ形状・操作方法・テスト方法・残課題は [docs/narrative-integration.md](docs/narrative-integration.md) を参照してください。

主要ドキュメント:

| ドキュメント | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | 全体構成 / ターゲット責務 / Swift↔C++ 境界 / 状態遷移 |
| [docs/ios-keyboard-limitations.md](docs/ios-keyboard-limitations.md) | Custom Keyboard Extension の制約 |
| [docs/testing.md](docs/testing.md) | テスト方針と実行方法 |
| [docs/privacy.md](docs/privacy.md) | プライバシー方針（通常入力は端末内完結 / お天気分の任意送信） |
| [docs/narrative-integration.md](docs/narrative-integration.md) | お天気分（micro-diary）の設計・データモデル・操作/テスト方法・残課題 |
| [docs/performance.md](docs/performance.md) | 性能目標と測定方法 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | ビルドエラーと解決 |
| [docs/initial-research.md](docs/initial-research.md) | Mozc の取得元・固定バージョン・ビルド方式調査（調査担当が記載） |

---

## スクリーンショット

スクリーンショットは `docs/screenshots/` に配置してください（未作成の場合は同ディレクトリを作成）。

- `docs/screenshots/keyboard.png` … 12 キーフリックキーボード
- `docs/screenshots/host-app.png` … ホストアプリ（設定・辞書管理）

（プレースホルダ: 実機ビルド後に追加）

---

## 対応環境

- **iOS**: 15.0 以上（`IPHONEOS_DEPLOYMENT_TARGET = 15.0`）
- **デバイス**: iPhone のみ
- **開発機**: macOS（Apple Silicon 推奨）+ Xcode
- **Swift**: 5.0

---

## 必要ツール

| ツール | 用途 | 導入例 |
| --- | --- | --- |
| Xcode | ビルド・署名・実機インストール | App Store |
| Xcode Command Line Tools | `xcode-select` 等 | `xcode-select --install` |
| bazelisk | Mozc（C++）の Bazel ビルド | `brew install bazelisk` |
| git | ソース取得 | 同梱 / `brew install git` |
| XcodeGen（任意） | `.xcodeproj` 生成 | `brew install xcodegen` |

> Mozc の正確な取得元・固定バージョン・必要ツールの詳細は [docs/initial-research.md](docs/initial-research.md) を参照してください（調査担当が記載）。

---

## 初回セットアップ

```bash
# 1) リポジトリ取得
git clone <このリポジトリのURL> MozcFlickKeyboard
cd MozcFlickKeyboard/20270713

# 2) ビルド前提の確認と Mozc ソース取得（bazelisk / Xcode の存在チェック込み）
./scripts/bootstrap.sh

# 3) Mozc を iOS 向けにビルド（.a / .xcframework を out/mozc に生成）
#    ※ 初回は依存取得を含み数十分〜数時間かかる場合があります。
./scripts/build_mozc_ios.sh

# 4) Xcode プロジェクト生成（下記参照）
./scripts/generate_xcode_project.sh
```

---

## Mozc の取得方法と固定バージョン

- 取得は `scripts/bootstrap.sh` が行います（`third_party/mozc` へ shallow clone）。
- 取得元・**固定リビジョン**・ライセンスは [docs/initial-research.md](docs/initial-research.md) を参照してください（調査担当が確定値を記載）。
- 環境変数で上書き可能:

```bash
# 取得元とリビジョン（プレースホルダ: 確定値は docs/initial-research.md）
MOZC_REPO_URL="https://github.com/google/mozc.git" \
MOZC_REVISION="<固定リビジョン: docs/initial-research.md 参照>" \
  ./scripts/bootstrap.sh
```

固定バージョン（プレースホルダ）:

- Mozc リビジョン: `<docs/initial-research.md 参照>`
- protobuf / abseil バージョン: `<docs/initial-research.md 参照>`

---

## iOS ビルド方法

1. `./scripts/bootstrap.sh` → `./scripts/build_mozc_ios.sh` で Mozc 成果物（`out/mozc/*.a` or `*.xcframework`）を用意。
2. `./scripts/generate_xcode_project.sh` で `.xcodeproj` を生成。
3. Xcode で開き、ホストアプリターゲットを選択して実機ビルド。
4. Mozc 成果物をリンクし、`MOZC_AVAILABLE` を定義すると実 Mozc 経路が有効になります（未定義時は `LocalStubEngine` で動作）。

> 採用ビルド方式（Bazel）とその理由は [docs/architecture.md](docs/architecture.md) を参照。

---

## Xcode プロジェクト生成（scripts/generate_xcode_project.sh）

`.xcodeproj` はリポジトリに含めず、スクリプトで生成する方針です。

```bash
./scripts/generate_xcode_project.sh
```

- 生成には XcodeGen 等を用いる想定（詳細はスクリプト内および [docs/architecture.md](docs/architecture.md)）。
- 生成後、`Config/Project.xcconfig` の値がターゲットへ反映されます。

> 補足: 本ファイル執筆時点で `scripts/generate_xcode_project.sh` はメインが用意する前提のプレースホルダ参照です。

---

## Bundle ID 変更方法（Config/Project.xcconfig）

利用者固有の値は [`Config/Project.xcconfig`](Config/Project.xcconfig) に集約しています。ここだけ書き換えれば全ターゲットに反映されます。

```
# 例（プレースホルダ）
PRODUCT_BUNDLE_PREFIX  = com.tanaka05.MozcFlickKeyboard      # ← 任意の逆ドメイン
APP_GROUP_ID           = group.com.tanaka05.MozcFlickKeyboard
```

> **DEVELOPMENT_TEAM（Apple Developer Team ID）は xcconfig では指定しません。**
> Xcode の各ターゲット > **Signing & Capabilities > Team** のプルダウンで選択してください
> （xcconfig にハードコードすると GUI 選択が上書きされ、変更できなくなるため）。

- ホストアプリ Bundle ID: `<PRODUCT_BUNDLE_PREFIX>`（例: `com.tanaka05.MozcFlickKeyboard`）
- Keyboard Extension Bundle ID: `<PRODUCT_BUNDLE_PREFIX>.Keyboard`

---

## App Group 設定

ホストアプリと Keyboard Extension で設定・ユーザー辞書・学習データを共有するため App Group を使用します。

1. Apple Developer で App Group `group.com.tanaka05.MozcFlickKeyboard`（= `APP_GROUP_ID`）を作成。
2. 両ターゲットの Signing & Capabilities に **App Groups** を追加し、同じ ID を有効化。
3. コードからは [`AppConfig.appGroupID`](MozcFlickKeyboard/Shared/AppConfig.swift) / `AppConfig.sharedContainerURL` を参照（Info.plist の `AppGroupID` キーから読み、無ければ定数へフォールバック）。

---

## Code Signing

1. Xcode > Settings > Accounts に Apple ID を追加。
2. 各ターゲット > **Signing & Capabilities > Team** のプルダウンで Team を選択（GUI で設定）。
3. 各ターゲットで "Automatically manage signing" を有効化（無料アカウントでも実機動作可、ただし 7 日で失効）。

---

## 実機インストール

1. iPhone を USB 接続し、Xcode で信頼を許可。
2. ホストアプリターゲットを選び、接続端末を宛先にして Run。
3. iPhone 側で **設定 > 一般 > VPN とデバイス管理** から開発者を信頼。
4. ホストアプリを一度起動する（拡張の有効化に必要）。

---

## キーボード追加方法

1. iPhone の **設定 > 一般 > キーボード > キーボード > 新しいキーボードを追加**。
2. 「MozcFlickKeyboard」を選択。
3. 入力欄で地球儀キー長押し → 本キーボードを選択。

---

## Full Access の要否

- **通常入力のみなら不要**（Full Access なしで動作）。通常入力の本文はネットワークやペーストボード全体アクセスを要求しません。
- **お天気分の送信機能を使う場合**（設定で Backend URL を入力した場合）は、キーボード拡張からのネットワーク通信のため Full Access が必要です。既定は Backend URL 未設定＝送信なしのため Full Access も不要です。
- ユーザー辞書・学習データは App Group 共有コンテナに保存します。
- 制約の詳細は [docs/ios-keyboard-limitations.md](docs/ios-keyboard-limitations.md) を参照。

---

## テスト実行方法

- Xcode: `Product > Test`（⌘U）でテストターゲットを実行。
- CLI:

```bash
xcodebuild test \
  -project MozcFlickKeyboard.xcodeproj \
  -scheme MozcFlickKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

- 一部テストは実装モジュールの結合待ちのため、`LOCAL_STUB_AVAILABLE` / `USER_DICT_AVAILABLE` を定義すると有効化されます。詳細は [docs/testing.md](docs/testing.md)。

---

## トラブルシューティング

代表的なビルドエラーと解決策は [docs/troubleshooting.md](docs/troubleshooting.md) にまとめています。

---

## ライセンス

- 本プロジェクトのライセンス: [LICENSE](LICENSE)（BSD-3-Clause）
- Mozc 由来部分・第三者ライブラリ: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照。
