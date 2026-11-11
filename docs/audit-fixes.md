# 監査後の修正（2026-11-11）

| 監査項目 | 修正 |
| --- | --- |
| K01 | 入力・候補・回答本文の診断出力を除去。収集許可条件と区別 |
| K02/K03 | 既存文書のMozcタグをcommit固定、Bazel版と必要patchを管理。上流のC++20にbridge設定を揃える。成果物不足をエラー、成功後のみ新成果物を採用 |
| K04 | Bundle prefix参照とBGTask IDを整合。既存ID値を維持。SimulatorはMozc辞書不要 |
| K05 | 永続保存BoolをUIへ伝達。保存失敗時は回答済みにせず自由入力/尺度フォームを保持 |
| K06/K07 | 不正・恒久HTTP失敗の原本隔離、後続送信、JSONL排他、同一IDの再試行 |
| X01/X02 | 英数字/記号commitと英語候補置換の契約、質問入力区間の分離、XCTest追加 |
| GPS | 旧分類・収集説明を削除。旧監視停止と旧queueの送信防止は保持 |

未使用Mock推薦を削除。旧PMTTLink/InterventionEvent/lastUsedの外部利用は判断できないためdeprecatedとして互換維持。感情分類は共通Analyzerへ統一。未送信セッションqueueと回答入力区間の変換処理をController/APIから分離。変換モデルのparameter/辞書形式は変更しない。

固定Mozcの元は既存文書の2.32.5994.102。上流commitとBUILD定義を照合しpatchを作成したが、ユーザーのMac成功環境にある未共有diffを取得していない。clean実機ビルド・XCTest・署名・実機通知・容量不足・プロセス間競合の実機確認は未実施。新しいビルド経路が成功するとの保証はしていない。

実施した検証：plist/JSON/YAML、シェル構文、pinned上流へのpatch適用チェック、両repoの契約fixture照合、参照/差分の静的確認。Swiftコンパイルを実施済みとは扱わない。

Python側と同時に変更を確認する。v2の受信cutoff/全入力commitを使うモデルは旧v1と区別して再学習する。既存DB、保存済みURL、App Group、Bundle ID、旧queueを消す移行は行わない。
