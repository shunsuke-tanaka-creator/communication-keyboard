# ライセンス概要 (MozcFlickKeyboard)

本アプリ「MozcFlickKeyboard」に Mozc とその依存を組み込む際のライセンス整理。
調査日: 2026-07-13 / 出典は各ファイル末尾および `../initial-research.md` §9 参照。

このディレクトリのファイル:

- `mozc.md`      : Mozc 本体(Google 作成コード)のライセンス概要
- `dictionary.md`: 辞書データ(system dictionary)のライセンス概要
- `protobuf.md`  : protobuf 依存のライセンス概要
- `abseil.md`    : abseil-cpp 依存のライセンス概要
- `third-party.md`: その他 Bazel/bzlmod 依存のライセンス概要

---

## サマリ表

| 対象 | ライセンス | 商用/研究組み込み | 表記義務 |
|------|-----------|------------------|---------|
| Mozc 本体(Google コード) | BSD 3-Clause | 可 | 著作権表示・免責条項の同梱 |
| 辞書 IPAdic 部分 | NAIST BSD系 + ICOT term | 可 | NAIST 著作権表示 + ICOT 条項の同梱 |
| 辞書 沖縄辞書 | Public Domain | 可(制限なし) | なし(任意) |
| protobuf | BSD 3-Clause 系 | 可 | 著作権表示の同梱 |
| abseil-cpp | Apache-2.0 | 可 | ライセンス全文 + NOTICE の同梱 |
| bazel_skylib / rules_python / apple_support 等 | Apache-2.0 中心 | 可(ビルド時のみ多い) | 配布物に含む場合はライセンス同梱 |

---

## 重要な順守事項

1. **著作権表示・ライセンス全文の同梱**: BSD 3-Clause / Apache-2.0 いずれもバイナリ配布時に著作権表示とライセンス条項の同梱が必要。アプリ内に「ライセンス表示」画面を設け、Mozc / 辞書(NAIST/ICOT)/ protobuf / abseil の表記を含めること。
2. **「Google 日本語入力」名称・商標を使わない**: 名称・ロゴ・"Google Japanese Input" / "Gboard" 等の商標は使用しない。本アプリ名は「MozcFlickKeyboard」、エンジン表記は「Mozc」に留める。
3. **辞書由来表記**: 辞書は Google 日本語入力の辞書とは別(OSS/IPAdic 相当)である旨を明記可能。NAIST/ICOT 条項は改変版でも同梱必須。

> 注: 本整理は法的助言ではない。研究用途を超えて配布する場合は、各ライセンス原文と最新の依存構成(選定タグの `MODULE.bazel` / `src/third_party/`)を必ず再確認すること。
