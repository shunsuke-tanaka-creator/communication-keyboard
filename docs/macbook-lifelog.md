# MacBook・SwitchBotとの接続

1. [Python側README](https://github.com/shunsuke-tanaka-creator/switch_bot_python)に従いMacでサーバーを起動する。既定はloopback/収集のみなので、Tailscaleのhost/allowed_clientsを自分の端末に設定する。
2. 親アプリの設定で参加者IDとBackend URLを入力する。初期URLは空欄で、固定の個人IPへ自動接続しない。既存の保存済みURLは維持する。
3. iOS設定でキーボードを追加し、研究収集を使う場合はフルアクセスをON、プライベートモードをOFFにする。
4. ダッシュボードの接続状態と受信時刻を確認し、実際に開閉させたBLE機器へ名前を付ける。

設定の「接続先を設定する」は設定画面を開きます。疑似センサーのiPhone HTTP待受は通常OFFでよく、MacのBLE収集に不要です。

入力は最大60秒・無入力60秒・非表示の境界で確定。永続queueを経由して再送します。iOSが未確定セッション中に拡張を強制終了した場合の完全回収は保証できません。サーバーは参加者/種別/IDで重複を防ぎます。

通信断は保存済み表示と区別します。接続先が空欄なら通信しませんが、既存のデータやqueueは残ります。DBや旧端末ログを自動削除・自動再投入しません。
