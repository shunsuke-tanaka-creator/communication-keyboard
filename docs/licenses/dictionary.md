# 辞書データ (system dictionary) ライセンス

対象: OSS 版 Mozc の辞書 `src/data/dictionary_oss/`(および `src/data/test/dictionary/`)。
出典: https://github.com/google/mozc/blob/master/src/data/dictionary_oss/README.txt, LICENSE, Debian copyright。

## 構成と由来

OSS 版辞書は **Mixed(混在)ライセンス**。Google 日本語入力の辞書とは別物で、以下の特徴:

- Web コーパス由来の大規模語彙は **含まれない**。
- 語彙は基本的に **IPAdic(mecab-ipadic-2.7.0-20070801 / ipadic-2.7.0)相当**。
- Collocation / Reading Correction / Suggestion Filter は **プレースホルダのみ**(実データは Google 内部)。

## ライセンス種別

### 1. IPAdic 由来語彙 (主要部分)

- Copyright 2000, 2001, 2002, 2003 Nara Institute of Science and Technology (NAIST). All Rights Reserved.
- **NAIST BSD 系ライセンス + ICOT Free Software 条項**。
- 要旨:
  - 使用・複製・配布が許可される。
  - オリジナル/改変版いずれの複製にも、上記著作権表示と以降の段落(条項)を必ず含めること。
  - NAIST 名を推奨/宣伝に使わない旨、無保証・免責。
  - 辞書エントリの大部分は ICOT Free Software 由来のため、ICOT Free Software の条件も同様に適用される。

### 2. 沖縄辞書

- **Public Domain**。使用・変更・配布に一切の制限なし。商品への組み込みも自由。

## 同梱可否(本プロジェクト評価)

- **同梱可能。** 研究用アプリに OSS 辞書を組み込み配布できる。
- 条件: **NAIST の著作権表示および NAIST/ICOT 条項を、辞書を含む配布物(アプリ)に同梱すること。** アプリ内ライセンス表示画面に含める。
- 沖縄辞書は表記義務なし(任意で明記可)。

## 注意 / 品質面

- OSS 辞書は IPAdic 相当かつ補正系がプレースホルダのため、**変換・予測品質は Google 日本語入力より低い**。研究用途では許容だが、評価時に留意する。
