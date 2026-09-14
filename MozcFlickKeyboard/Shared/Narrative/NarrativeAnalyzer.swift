// NarrativeAnalyzer.swift
// MozcFlickKeyboard — 追加: NarrativeEvent から感情・経験タイプを推定する解析器のプロトコルと Mock 実装。
//
// Phase1 は MockNarrativeAnalyzer が回答ラベル/値 + 質問種別からルールで emotion / experienceType を埋める（embedding=nil）。
// Phase4 で FastAPI 等の実体に差し替える想定。async throws にしておき、実体化時に非同期通信へ拡張できるようにする。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

/// 追加: NarrativeEvent を解析して NarrativeAnalysis（感情・経験タイプ・埋め込み）を返す。
public protocol NarrativeAnalyzer {
    /// 追加: 解析結果を返す。実体は将来リモート呼び出しになるため async throws。
    func analyze(event: NarrativeEvent) async throws -> NarrativeAnalysis
}

/// 追加: ルールベースの Mock 解析器（Phase1）。回答の value/label と質問種別から機械的にラベル付けする。
public final class MockNarrativeAnalyzer: NarrativeAnalyzer {
    public init() {}

    /// 追加: 解析本体。ネットワーク等は使わず即座に返す。
    public func analyze(event: NarrativeEvent) async throws -> NarrativeAnalysis {
        // 追加: 判定の入力は「選択肢 value（answer.label に value が入っている仕様）」を優先し、無ければ自由記述。
        let value = event.answer.label ?? event.answer.freeText
        let emotion = emotionClass(for: value)
        let experience = experienceClass(for: value, kind: event.question.kind)
        return NarrativeAnalysis(emotion: emotion, experienceType: experience, embedding: nil)
    }

    /// 追加: 感情ラベルのマッピング表。
    ///   negative ← bad / slightly_tired / tired / difficult
    ///   positive ← good / helpful
    ///   neutral  ← それ以外（normal など）や nil
    private func emotionClass(for value: String?) -> String {
        switch value {
        case "bad", "slightly_tired", "tired", "difficult":
            return "negative"
        case "good", "helpful":
            return "positive"
        default:
            return "neutral"
        }
    }

    /// 追加: 経験タイプのマッピング表（外部からも再利用できるよう public）。
    ///   failure         ← difficult / bad
    ///   success         ← good
    ///   partial_success ← tired / slightly_tired（達成はしたが負荷が高い）
    ///   neutral         ← それ以外 / nil
    public func experienceClass(for value: String?, kind: QuestionKind) -> String {
        switch value {
        case "difficult", "bad":
            return "failure"
        case "good":
            return "success"
        case "tired", "slightly_tired":
            return "partial_success"
        default:
            return "neutral"
        }
    }
}
