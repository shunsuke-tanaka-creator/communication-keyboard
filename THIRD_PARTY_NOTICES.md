# 第三者ライセンス表示（THIRD PARTY NOTICES）

MozcFlickKeyboard は以下の第三者ソフトウェアを利用しています。各ソフトウェアの著作権および
ライセンスは、それぞれの原著作者に帰属します。本プロジェクト自体のライセンスは [LICENSE](LICENSE)
（BSD-3-Clause）を参照してください。

> **名称に関する注意**: 本プロジェクトは変換エンジンとしてオープンソースの **Mozc** を利用しますが、
> 製品名 **「Google 日本語入力」** の名称・商標は使用しません。Mozc は Google 日本語入力の
> オープンソース版に相当しますが、両者は別物として扱い、本プロジェクトが Google 公式製品で
> あるかのような表記は行いません。

各ライブラリのライセンス全文・取得元・固定バージョンは、調査担当が `docs/licenses/` 配下に
配置します（本ファイルはその要約・索引です）。

---

## 1. Mozc

- 用途: かな漢字変換エンジン（本体）
- ライセンス: **BSD-3-Clause**
- 取得元 / 固定リビジョン: [docs/initial-research.md](docs/initial-research.md) 参照（プレースホルダ）
- ライセンス全文: `docs/licenses/mozc-LICENSE.txt`（調査担当が配置）
- 備考: 「Google 日本語入力」名称は不使用。

```
（Mozc の BSD-3-Clause 全文をここ、または docs/licenses/mozc-LICENSE.txt に記載）
Copyright (c) Google Inc. and contributors. All rights reserved.
```

---

## 2. Protocol Buffers (protobuf)

- 用途: Mozc の内部データ / IPC メッセージ定義
- ライセンス: **BSD-3-Clause**
- 固定バージョン: [docs/initial-research.md](docs/initial-research.md) 参照（プレースホルダ）
- ライセンス全文: `docs/licenses/protobuf-LICENSE.txt`（調査担当が配置）

---

## 3. Abseil (abseil-cpp)

- 用途: Mozc が依存する C++ 基盤ライブラリ
- ライセンス: **Apache License 2.0**
- 固定バージョン: [docs/initial-research.md](docs/initial-research.md) 参照（プレースホルダ）
- ライセンス全文: `docs/licenses/abseil-LICENSE.txt`（調査担当が配置）
- 備考: Apache-2.0 は NOTICE ファイルの同梱が必要な場合があるため、`docs/licenses/abseil-NOTICE.txt` も併せて配置。

---

## 4. その他の依存（Mozc のビルドが引き込むもの）

Mozc の Bazel ビルドは上記以外にも依存を引き込むことがあります（例: GoogleTest 等の
テスト依存はランタイムには含まれない想定）。実際に配布物へ含まれる依存の一覧・ライセンスは
`docs/licenses/` に網羅し、本ファイルへ追記します。

| ライブラリ | ライセンス | 全文の場所 | 備考 |
| --- | --- | --- | --- |
| Mozc | BSD-3-Clause | docs/licenses/mozc-LICENSE.txt | 名称不使用の注記あり |
| protobuf | BSD-3-Clause | docs/licenses/protobuf-LICENSE.txt |  |
| abseil-cpp | Apache-2.0 | docs/licenses/abseil-LICENSE.txt | NOTICE 同梱 |
| （追記） |  |  |  |

---

## 5. 更新方針

- 依存の追加・バージョン更新時は、`docs/licenses/` にライセンス全文を追加し、本ファイルの表と
  該当節を更新すること。
- 固定バージョンは [docs/initial-research.md](docs/initial-research.md) を単一の情報源とする。
