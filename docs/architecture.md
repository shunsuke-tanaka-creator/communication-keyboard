# アーキテクチャ

> 変更: 本書はコードの現状に合わせてあります。研究データの取得範囲・送信経路は [privacy.md](privacy.md)、MacBook 連携の運用は [macbook-lifelog.md](macbook-lifelog.md) を参照してください。

MozcFlickKeyboard は「ホストアプリ」と「Keyboard Extension」の 2 ターゲットから成り、共通ロジックを Shared として共有します。かな漢字変換は Mozc（C++）を Swift から呼び出して実現し、Mozc 未ビルド時は同一プロトコルのローカルスタブへ差し替えて動作します。

---

## 1. 全体構成

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│  ホストアプリ (App)          │        │  Keyboard Extension (Keyboard) │
│  - くらしのログ（Mac連携）   │        │  - 12キーフリック UI           │
│  - 設定 / 予定・安否確認     │        │  - 入力 → 変換 → 確定          │
│  - お天気分ダッシュボード    │        │  - UITextDocumentProxy 反映     │
│  - 入力ログ・安否確認ログ閲覧│        │  - 入力ログ / お天気分バナー    │
│  - HealthKit/EventKit 取得   │        │  - 研究サーバーへ送信          │
└──────────────┬──────────────┘        └───────────────┬──────────────┘
               │                                        │
               └──────────────┬─────────────────────────┘
                              ▼
                 ┌──────────────────────────┐
                 │  Shared (MozcFlickShared) │
                 │  - JapaneseConversionEngine（プロトコル）
                 │  - PersonalizedConversionEngine（辞書・学習の重ね合わせ）
                 │  - ConversionResult/Candidate/Segment
                 │  - AppConfig（App Group）
                 │  - UserDictionary / Learning
                 │  - KanaTable / KanaTransform / KeyLayout
                 │  - SessionLogger / Narrative / Research
                 └────────────┬─────────────┘
                              ▼
        ┌───────────────────────────────────────────────┐
        │  変換エンジン実装                                │
        │  ┌──────────────────┐  ┌───────────────────────┐│
        │  │ LocalStubEngine   │  │ MozcConversionEngine   ││
        │  │ (純 Swift スタブ) │  │  ↓ ObjC++ ブリッジ     ││
        │  └──────────────────┘  │  ↓ Mozc C++ (session)  ││
        │                        └───────────────────────┘│
        └───────────────────────────────────────────────┘
```

- App / Keyboard は Shared を通じてのみ変換エンジンに触れ、Mozc の C++ 型は一切露出しません。
- `MOZC_AVAILABLE` の有無で `MozcConversionEngine` / `LocalStubEngine` を切り替えます。`project.yml` では実機 SDK（`iphoneos*`）のときだけ `MOZC_AVAILABLE` を定義します。シミュレータでは `LocalStubEngine` で動作します。実機でも Mozc の初期化に失敗した場合（`isMozcAvailable == false`）は `LocalStubEngine` に切り替わります。
- キーボードは、選んだエンジンを `PersonalizedConversionEngine` で包み、ユーザー辞書の候補と学習スコアを重ねます（Full Access が無いと辞書・学習ストアは nil）。

---

## 2. 各ターゲットの責務

| ターゲット | 責務 | 触れないもの |
| --- | --- | --- |
| **App（ホスト）** | タブ「くらしのログ」（Mac ダッシュボード・活動記録・機器名）／「キーボード」（設定・予定・研究設定、お天気分ダッシュボード、入力ログ・安否確認ログ閲覧、ライセンス、デバッグ情報）、HealthKit / EventKit / バッテリーの取得、疑似センサー HTTP 受信 | UITextDocumentProxy（拡張のみ） |
| **Keyboard（拡張）** | フリック UI、入力イベント → 変換エンジン → `UITextDocumentProxy` へ反映、地球儀キー切替、入力ログ記録と送信、お天気分バナー、安否確認表示 | HealthKit / EventKit（親アプリが取得した値を App Group から読むだけ） |
| **Shared** | 変換プロトコル・値型、App Group アクセス、かな変換テーブル、ユーザー辞書・学習ストア、SessionLogger、Narrative、Research（送信クライアント・キュー） | UIKit 依存の最小化 |
| **MozcBridge** | Swift ↔ C++ 境界（ObjC++）。Mozc session を包む | Swift へ C++ 型を漏らさない |

---

## 3. Swift ↔ ObjC++ ↔ C++ 境界

Mozc は C++ で書かれているため、Swift から直接呼べません。以下の 3 層で隔離します。

1. **Swift 層**: `MozcConversionEngine`（`JapaneseConversionEngine` 準拠）。入出力は純 Swift 値型（`ConversionResult` 等）。
2. **ObjC++ 層（MozcBridge）**: `.mm` ファイル。Swift から見える Objective-C クラス（例: `MozcSessionBridge`）を公開し、内部で Mozc の C++ API（`mozc::Session` 等）を呼ぶ。Swift へは `NSString` / プリミティブ / 単純な struct のみ返す。
3. **C++ 層（Mozc）**: `out/mozc` にビルド済みの静的ライブラリ / XCFramework。

境界での型変換方針:

- 文字列は UTF-8（C++）↔ `NSString`/`String`（Swift）。
- 候補配列は ObjC++ 側で `NSArray<NSDictionary>` 等に詰め替え、Swift 側で `ConversionCandidate` に写像。
- Mozc の protobuf メッセージ（`commands::Output` 等）は境界を越えさせない。

---

## 4. Mozc セッション管理

- Keyboard Extension のライフサイクルに合わせて 1 つの Mozc セッションを保持。
- 起動時に一度だけ初期化（辞書ロード）。初期化コストは [performance.md](performance.md) の目標値を参照。
- 入力ごとに `insert` / `requestConversion` を session へ委譲。`commit` でセッションのコンテキストをリセット。
- 拡張がメモリ都合で破棄・再生成される場合に備え、辞書・学習は App Group の永続層へ保存し、セッションは再初期化で復元。

---

## 5. 状態遷移

`JapaneseConversionEngine` を軸にした入力状態:

```
     ┌────────────┐  insert / deleteBackward   ┌───────────────┐
     │  Empty      │ ─────────────────────────▶ │  Composing     │
     │ (composition│ ◀───────────────────────── │ (かな未確定)   │
     │  = "")      │       commit / reset        └──────┬────────┘
     └────────────┘                                     │ requestConversion
            ▲                                            ▼
            │ commit（確定文字列を proxy へ）      ┌───────────────┐
            └──────────────────────────────────── │  Converting    │
                     cancelConversion              │ (文節・候補)   │
                     （Composing へ戻る）           └───────────────┘
```

- **Empty → Composing**: `insert` でかな追加。
- **Composing → Converting**: `requestConversion`（`isConverting=true`、`segments` 生成）。
- **Converting 内**: `selectCandidate` / `moveFocus` / `resizeFocusedSegment` で候補・文節を操作。
- **Converting → Composing**: `cancelConversion`（composition 保持）。
- **→ Empty**: `commit`（確定文字列を返し内部リセット）または `reset`。

拡張側 UI（`KeyboardViewController`）は `UITextDocumentProxy` に marked text API が無いため、未確定文字列（変換中は選択中の文節列）を `syncInline` で入力欄へ実際に挿入します。`pendingComposition` との差分だけを `deleteBackward` / `insertText` で更新し、確定時は挿入済みの分を消してから確定文字列を入れ直します。

---

## 6. 永続化

| データ | 形式 | 場所 |
| --- | --- | --- |
| 設定（トグル入力・フリックのみ・学習・プライベートモード・予定・研究設定） | `UserDefaults(suiteName: AppGroupID)` | App Group |
| ユーザー辞書（`UserDictionaryEntry`） | JSON（Codable） | `UserDictionary/user_dictionary.json` |
| 候補学習（`LearningRecord`: よみ・語・頻度・最終使用） | JSON（Codable、最大5000件） | `Learning/learning.json`（プライベートモード・学習OFF・パスワード欄では書き込まない） |
| 入力ログ | JSONL | `Library/Caches/SessionLogs/` |
| 送信キュー | 1件1ファイルの JSON | `Library/Application Support/PendingResearchSessions/` / `ResearchOutbox/` |
| お天気分 | JSONL | `Narrative/narrative_*.jsonl` / `context_*.jsonl` |
| 安否確認 | JSONL | `SafetyChecks/check_*.jsonl` |
| 端末Context・端末UUID | JSON / 文字列 | App Group UserDefaults（`research.deviceContext` / `research.deviceID`） |

`learning.json` と `user_dictionary.json` にだけ `.completeUntilFirstUserAuthentication` を明示的に設定しています。詳細は [privacy.md](privacy.md)。

---

## 7. App Group

- ID: `group.com.tanaka05.MozcFlickKeyboard`（`Config/Project.xcconfig` の `APP_GROUP_ID`）。
- アクセスは `AppConfig.appGroupID` / `AppConfig.sharedContainerURL` に集約。
- ホスト（設定・予定・端末Context の書き込み、ログ閲覧）と拡張（辞書の読み取り、学習・ログ・回答の書き込み）が同じコンテナを読み書きするため、書き込みは原子的置換（一時ファイル → rename）を推奨。

---

## 8. スレッドモデル

- UI 操作・`UITextDocumentProxy` 反映は**メインスレッド**。
- Mozc 変換呼び出しは短時間で完了する想定のため原則同期呼び出し。重い初期化（辞書ロード）は起動時のバックグラウンドで先読みし、初回入力までに完了を目指す。
- ユーザー辞書の大量入出力（CSV/JSON 数千〜万件）はバックグラウンドキューで実行し、完了後にメインで反映。

---

## 9. エラー設計

- 変換エンジンは**例外を投げない**（プロトコルは throwing でない）。異常時は空の `ConversionResult`（`.empty`）へフォールバックし、UI を壊さない。
- Mozc 初期化失敗時は `LocalStubEngine` へ自動フォールバックし、入力自体は継続可能にする。
- 永続層（辞書 I/O）は throwing。呼び出し側でユーザー通知（ホストアプリ）または握りつぶし（拡張は入力継続優先）を選択。

---

## 10. 採用ビルド方式と理由

- **採用: Bazel（bazelisk）**。理由:
  - Mozc 公式が Bazel ビルドを提供・保守しており、iOS 向けクロスビルド設定を流用できる。
  - 依存（protobuf / abseil 等）のバージョン整合を Bazel が管理し、再現性が高い。
  - CMake/GYP など旧経路より公式サポートが手厚い。
- 具体的な取得元・固定リビジョン・確認済みビルドフラグは [initial-research.md](initial-research.md) を参照（調査担当が確定値を記載）。
- 成果物（`.a` / `.xcframework`）は `out/mozc` に生成し、`scripts/generate_xcode_project.sh` が生成する Xcode プロジェクトへリンクします。

---

## 11. お天気分・研究ログ

現在のサーバー連携・回答保存・キュー制御は [narrative-integration.md](narrative-integration.md) を参照してください。

- `ResearchSessionQueue` と `ResearchEventOutbox` はそれぞれ1セッション/1イベント1ファイルで永続化。
- `ResearchPersistence` はJSONL追記のflock、恒久失敗の原本隔離・明示復帰を担当。
- `ResearchSessionEvents` は回答入力区間だけをマークし、Controllerの表示責務から分離。
- `NarrativeRepositoryHub` はローカルと送信queueの保存結果を返す。UIは失敗を回答済みと扱わない。
- 変換・学習・辞書、App/Extension/Sharedのtarget境界は維持。未使用MockRecommendationEngineは削除。

モデル学習・評価・受信時刻のcutoffはPython側で管理します。GPSは使用しません。実機での時刻・送信・保存・競合確認は [testing.md](testing.md) の対象です。
