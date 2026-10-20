# MozcFlickKeyboard

iPhone専用の日本語フリックキーボードです。変換は端末内で実行します。MacBook統合版では、記録された入力本文・文脈・活動回答・端末ContextをTailscale経由でMacに同期し、SwitchBotの開閉ログと合わせて「くらしのログ」に表示します。接続先の初期値は `http://100.106.185.3:8000`、空欄にすると同期を停止します。セットアップと制限は [docs/macbook-lifelog.md](docs/macbook-lifelog.md) を参照してください。

> 研究用途（久保田研究室）で開発しています。名称・商標について「Google 日本語入力」の名称は使用しません（[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 参照）。

---

## 概要

- **対象**: iPhone（iPad 非対応 / `TARGETED_DEVICE_FAMILY = 1`）
- **入力方式**: 12 キーフリック入力（トグル入力併用可）
- **変換エンジン**: Mozc（C++）を iOS 向けにクロスビルドし、Swift から呼び出す（実機のみ。シミュレータは `LocalStubEngine`）
- **変換はオフライン**: 変換・学習・ユーザー辞書は端末内で完結（研究ログの同期は別経路。下記）
- **構成**: ホストアプリ（くらしのログ・設定・お天気分・ログ閲覧・端末Context取得）＋ Keyboard Extension（実際の入力・入力ログ・質問バナー）

### 研究機能「お天気分」（micro-diary）

- キーボード上部に短い質問バナーを1問だけ表示します（朝の気分、22時以降の夜の振り返り5項目、外出先・外出の評価、センサー由来の疲労確認、サーバーからの活動質問など）。1〜2 タップまたは短い自由記述で回答できる、研究用のマイクロ日記機能です。
- 回答は研究データ（`NarrativeEvent`）として端末内に保存し、**ホストアプリのテキスト欄には一切挿入しません**。Backend URL が設定されていれば Mac へ送信します。
- 入力セッション（キー操作・確定本文・前後文脈・打鍵特徴・端末Context）は別の研究ログ経路で Mac へ同期します。
- MacBook統合版の Backend URL 初期値は `http://100.106.185.3:8000` です。明示的に空欄にすると同期を停止します。
- 取得・送信するデータの全一覧は [docs/privacy.md](docs/privacy.md) にあります。

主要ドキュメント:

| ドキュメント | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | 全体構成 / ターゲット責務 / Swift↔C++ 境界 / 状態遷移 |
| [docs/ios-keyboard-limitations.md](docs/ios-keyboard-limitations.md) | Custom Keyboard Extension の制約 |
| [docs/testing.md](docs/testing.md) | テスト方針と実行方法 |
| [docs/privacy.md](docs/privacy.md) | 取得データ全一覧・保存場所・Macへの送信経路 |
| [docs/macbook-lifelog.md](docs/macbook-lifelog.md) | MacBook + SwitchBot 統合ログの運用 |
| [docs/narrative-integration.md](docs/narrative-integration.md) | お天気分（micro-diary）の設計・データモデル・操作/テスト方法・残課題 |
| [docs/performance.md](docs/performance.md) | 性能目標と測定方法 |
| [docs/troubleshooting.md](docs/troubleshooting.md) | ビルドエラーと解決 |
| [docs/initial-research.md](docs/initial-research.md) | Mozc の取得元・固定バージョン・ビルド方式調査（調査担当が記載） |

---

## スクリーンショット

スクリーンショットは `docs/screenshots/` に配置してください（未作成の場合は同ディレクトリを作成）。

- `docs/screenshots/keyboard.png` … 12 キーフリックキーボード
- `docs/screenshots/host-app.png` … ホストアプリ（くらしのログ・設定）

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
- 変更: `scripts/bootstrap.sh` の既定値は `MOZC_REPO_URL=https://github.com/google/mozc.git`、`MOZC_REVISION=master` です（固定されていません）。選定したリビジョンとライセンスは [docs/initial-research.md](docs/initial-research.md) を参照してください。
- 環境変数で上書き可能:

```bash
MOZC_REPO_URL="https://github.com/google/mozc.git" \
MOZC_REVISION="<docs/initial-research.md の選定リビジョン>" \
  ./scripts/bootstrap.sh
```

---

## iOS ビルド方法

1. `./scripts/bootstrap.sh` → `./scripts/build_mozc_ios.sh` で Mozc 成果物（`out/mozc/*.a` or `*.xcframework`）を用意。
2. `./scripts/generate_xcode_project.sh` で `.xcodeproj` を生成。
3. Xcode で開き、ホストアプリターゲットを選択して実機ビルド。
4. `project.yml` は実機 SDK（`iphoneos*`）のときだけ Mozc 成果物をリンクし、`MOZC_AVAILABLE` を定義します。シミュレータや未定義時は `LocalStubEngine` で動作します。

> 採用ビルド方式（Bazel）とその理由は [docs/architecture.md](docs/architecture.md) を参照。

---

## Xcode プロジェクト生成（scripts/generate_xcode_project.sh）

`.xcodeproj` はリポジトリに含めず、スクリプトで生成する方針です。

```bash
./scripts/generate_xcode_project.sh
```

- 変更: スクリプトは XcodeGen（`brew install xcodegen`）で `project.yml` から生成します。未導入ならエラーで止まります。
- 生成後、`Config/Project.xcconfig` の値がターゲットへ反映されます。

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

ホストアプリと Keyboard Extension で、設定・ユーザー辞書・学習データ・入力ログ・研究データ・端末Context を共有するため App Group を使用します。

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

- **入力・変換だけなら不要**（Full Access なしで動作）。
- 変更: 次の機能は Full Access 有効時だけ動きます（`KeyboardViewController` の `hasFullAccess` 判定）:
  - ユーザー辞書・候補学習
  - 入力ログの記録と Mac への送信
  - お天気分（質問バナー・「記録」・「情報」）
  - 触覚フィードバック
- Backend URL の既定値は MacBook（`http://100.106.185.3:8000`）です。Full Access 有効・プライベートモード OFF なら、入力ログ（確定本文・前後文脈を含む）が既定で送信されます。止めるには Backend URL を空欄にしてください。
- 設定・予定・辞書・学習・ログは App Group 共有コンテナに保存します。
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

- `project.yml` のテストターゲットでは `LOCAL_STUB_AVAILABLE` / `USER_DICT_AVAILABLE` が定義済みで、全テストが有効です。詳細は [docs/testing.md](docs/testing.md)。

---

## トラブルシューティング

代表的なビルドエラーと解決策は [docs/troubleshooting.md](docs/troubleshooting.md) にまとめています。

---

## ライセンス

- 本プロジェクトのライセンス: [LICENSE](LICENSE)（BSD-3-Clause）
- Mozc 由来部分・第三者ライブラリ: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照。
