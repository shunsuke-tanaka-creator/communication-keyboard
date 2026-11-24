# 疑似センサー注入 CLI（tools/sensor_inject.py）

## 概要

同一 LAN 上の MacBook から iPhone の**親アプリ**へ、疑似 IoT センサーイベントを HTTP POST で注入するための CLI です。
親アプリが受信したイベントは研究質問と回答記録（Narrative）機能の入力として扱い、ローカル質問キューや ContextEvent の記録に使います。

- 送信先: `POST http://<iPhone の LAN IP>:8770/sensor`
- 依存ライブラリ: **なし**（Python 3 標準ライブラリのみ。pip install 不要）

## 前提と制約

- **受信できるのは親アプリを前面で開いている間だけです。** iOS の制約により、キーボード拡張やバックグラウンド状態では HTTP 受信サーバーが稼働できません。注入作業は必ず親アプリを開いた状態で行ってください。
- 初回実行時、iPhone 側に **「ローカルネットワーク」へのアクセス許可ダイアログ**が表示されます。必ず「許可」を選んでください（拒否すると受信できません。拒否した場合は iOS 設定 > プライバシーとセキュリティ > ローカルネットワーク から許可し直します）。
- **iPhone と Mac が同一 Wi-Fi（同一サブネット）**に接続されている必要があります。ゲスト用ネットワークやプライベート Wi-Fi アドレスの分離設定では届かないことがあります。

## iPhone の LAN IP の調べ方

1. **推奨**: 親アプリの「設定」画面に、現在の LAN IP と受信ポートが表示されます。
2. または iOS の 設定 > Wi-Fi > 接続中ネットワークの (i) > IP アドレス。

## 使い方

```bash
# 玄関を開けた（外出）
python3 tools/sensor_inject.py --host 192.168.1.23 door_open

# 玄関を閉めた（帰宅）
python3 tools/sensor_inject.py --host 192.168.1.23 door_close

# トイレ（記録のみ）
python3 tools/sensor_inject.py --host 192.168.1.23 toilet

# 温度（high / mid / low）
python3 tools/sensor_inject.py --host 192.168.1.23 temp --value high

# リビング在室検知（present=在室 / absent=不在）
python3 tools/sensor_inject.py --host 192.168.1.23 presence --value present
python3 tools/sensor_inject.py --host 192.168.1.23 presence --value absent
```

オプション:

- `--host` … iPhone の LAN IP（必須）
- `--port` … 受信ポート（既定: `8770`）
- `--timeout` … タイムアウト秒（既定: `5`）

### 対話モード

サブコマンドを付けずに起動すると、番号を選んで繰り返し送信できる対話モードになります。

```bash
python3 tools/sensor_inject.py --host 192.168.1.23
```

```
対話モード: 送信したいイベントの番号を入力してください（q で終了）
  1: 玄関を開けた(外出)
  2: 玄関を閉めた(帰宅)
  3: トイレ
  4: 温度 high
  5: 温度 mid
  6: 温度 low
  7: 在室（present）
  8: 不在（absent）
  q: 終了
> 1
[OK] 200 sent type=door_open value=None
     payload={"type": "door_open", "value": null, "at": "2026-09-15T01:50:00.000+0900"}
> q
終了します。
```

`7`（在室）と `8`（不在）はどちらも値まで含めて1タップで送信されます（追加入力はありません）。

## イベント一覧

質問対象のイベントはローカル質問キューへ積みます。Backend URL 未設定時は Full Access・質問設定・予算・間隔条件を満たすとキーボードに表示します。サーバー設定済みの場合はサーバーの発行判断に従います。

| サブコマンド | 送信される `type` | `value` | iOS 側の挙動 |
| --- | --- | --- | --- |
| `door_open` | `door_open` | なし | 外出イベントとしてローカルキューへ積む（上記条件で「どこへ行きましたか？」を表示） |
| `door_close` | `door_close` | なし | 帰宅イベントとしてローカルキューへ積む（上記条件で「今回の外出はどうでしたか？」を表示） |
| `temp --value high` | `temperature` | `high` | 疲労チェックをローカルキューへ積む（上記条件で「少し疲れていますか？」を表示） |
| `temp --value low` | `temperature` | `low` | 疲労チェックをローカルキューへ積む（上記条件で「少し疲れていますか？」を表示） |
| `temp --value mid` | `temperature` | `mid` | 記録のみ（質問は出ない） |
| `toilet` | `toilet` | なし | 記録のみ（質問は出ない） |
| `presence --value present\|absent` | `living_presence` | `present`（在室）または `absent`（不在） | 記録のみ（質問は出ない） |

送信される JSON の形は共通です。

```json
{"type": "door_open", "value": null, "at": "2026-09-15T01:50:00.000+0900"}
```

- `type` … 必須。上表の値
- `value` … 任意。`temperature`（`high` / `mid` / `low`）/ `living_presence`（`present` / `absent`）のときに指定
- `at` … 任意。CLI は常に送信時刻（ミリ秒 + タイムゾーンオフセット）を付与します。省略時は iPhone 側の受信時刻が使われます（変更: `SensorEventRouter` の実装に合わせて表記修正）
- 追加: iOS 側は、どの type でも `ContextEvent`（`sensor_<type>`）を端末の `Narrative/context_yyyyMMdd.jsonl` に保存します。Backend URL の既定値は空欄です。利用者が明示した研究サーバーが設定されていれば、その `POST /api/sensor-events` へ1回送ります（再送なし）。

## 期待される出力例

CLI 側:

```
[OK] 200 sent type=door_open value=None
     payload={"type": "door_open", "value": null, "at": "2026-09-15T01:50:00.000+0900"}
```

親アプリ側（Xcode コンソール）:

```
[MFK-Sensor] received type=door_open
```

キーボード側（Xcode コンソール、Backend URL 未設定で Full Access・質問設定・予算・間隔条件を満たし、キーボードを開いて質問が表示された場合。サーバー設定済みの場合はサーバーの発行判断に従います）:

```
[MFK-Narrative] question shown kind=outingDestination
```

## トラブルシューティング

### 接続できない（`[NG] 接続できません` / タイムアウト）

- 親アプリが**前面で開いていない**（もっとも多い原因）。ホーム画面に戻ったり他アプリに切り替えると受信サーバーは停止します。
- `--host` の IP が違う。親アプリの 設定 画面に表示されている IP と一致しているか確認してください（DHCP で IP が変わることがあります）。
- `--port` が違う。既定は `8770`。親アプリ側でポートを変更した場合は合わせてください。
- 初回の**ローカルネットワーク許可を拒否**している。iOS 設定 > プライバシーとセキュリティ > ローカルネットワーク で親アプリを ON にしてください。
- iPhone と Mac が**別のネットワーク**にいる（テザリング、ゲスト SSID、5GHz/2.4GHz で分離されたネットワークなど）。同じ Wi-Fi に接続し直してください。
- 親アプリの「疑似センサー受信」設定が OFF になっている。

### `[OK] 200` だが質問が出ない

- Backend URL が設定済みの場合、ローカルキューは出題に使われません。サーバーの発行判断に従い、204 応答や通信失敗時もローカル質問へは切り替わりません。
- キーボードの Full Access が OFF になっている。
- **1日の質問上限（既定4件）**に達している。翌日まで待つか、「生活の気づき」の質問上限設定を確認してください。
- 質問機能が OFF になっている（親アプリの 設定 を確認）。
- その質問に**既に回答済み**、またはクールダウン中である。
- Backend URL 未設定時は、次回キーボード表示時または 60 秒間隔のチェックで、Full Access・質問設定・予算・間隔条件を満たすローカル質問を表示します。キーボードを開き直してみてください。

## 注意

この経路で送受信するのは**疑似センサーイベントのみ**です。キーボードで入力した通常の文字入力（本文）は一切送受信しません。
