// RecommendationEngine.swift
// MozcFlickKeyboard — 追加: 文脈から介入（提案）を生成する推薦器のプロトコルと Mock 実装。
//
// Phase1 は MockRecommendationEngine が常に nil を返す（提案は出さない）。
// 将来（Phase4）は、過去の NarrativeEvent 群を埋め込み検索し、類似状況で有効だった経験を引いて提案文を生成する想定。
// Shared は framework ターゲット MozcFlickShared なので外部公開する型・メンバは全て public。

import Foundation

/// 追加: 現在文脈に対する提案を返す。提案なしなら nil。実体化に備えて async throws。
public protocol RecommendationEngine {
    /// 追加: 提案を1件返す（無ければ nil）。
    func generateSuggestion(context: CurrentContext) async throws -> Suggestion?
}

/// 追加: 介入（提案）1件。バナーに出す文言と選択肢、根拠イベント ID を持つ。
public struct Suggestion {
    /// 追加: 提案の質問文/文言。
    public let prompt: String
    /// 追加: 選択肢（表示ラベル）。
    public let options: [String]
    /// 追加: 提案の根拠になった NarrativeEvent の event_id（無ければ nil）。
    public let basedOnEventID: String?

    public init(prompt: String, options: [String], basedOnEventID: String? = nil) {
        self.prompt = prompt
        self.options = options
        self.basedOnEventID = basedOnEventID
    }
}

/// 追加: Phase1 の Mock。常に nil を返す（提案機能は無効）。
/// 追加: Phase4 では「現在文脈の埋め込み → 過去 NarrativeEvent の類似検索 → 有効だった経験の再提示」という流れに差し替える。
public final class MockRecommendationEngine: RecommendationEngine {
    public init() {}

    /// 追加: Phase1 は提案を出さない。
    public func generateSuggestion(context: CurrentContext) async throws -> Suggestion? {
        nil
    }
}
