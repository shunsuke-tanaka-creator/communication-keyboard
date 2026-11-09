import Foundation

/// 追加: 提案の取得元。App Group に rawValue を保存し、親アプリとキーボードで共有する。
public enum ProposalDataSource: String, Codable, CaseIterable {
    case actual
    case sample
    case combined

    public var serverDataMode: String {
        switch self {
        case .actual: return "real"
        case .sample: return "sample"
        case .combined: return "combined"
        }
    }

    public var usesPreviewEndpoint: Bool { self != .actual }

    public var displayName: String {
        switch self {
        case .actual: return "実データ"
        case .sample: return "サンプルのみ"
        case .combined: return "実データ＋サンプル"
        }
    }

    /// 追加: 親アプリ内で設定変更を即時反映する通知。
    public static let didChangeNotification = Notification.Name("ProposalDataSourceDidChange")
}

/// 追加: 取得経路を純粋関数として判定できるテスト用の seam。
public enum ProposalFetchRoute: Equatable {
    case pending
    case preview(dataMode: String)

    public static func route(for source: ProposalDataSource) -> Self {
        source.usesPreviewEndpoint ? .preview(dataMode: source.serverDataMode) : .pending
    }
}

/// 追加: PendingQuestion に表示上のプレビュー性を構造的に付与する。
public struct ProposalCandidate {
    public var question: PendingQuestion
    public let isPreview: Bool

    public init(question: PendingQuestion, isPreview: Bool) {
        self.question = question
        self.isPreview = isPreview
    }
}

/// 追加: サーバー側ゲートの評価結果。
public struct PreviewGate: Codable {
    public let passed: Bool
    public let detail: String
}

/// 追加: GET /api/research/{participant_id}/proposal-preview の応答。
public struct PreviewResponse: Codable {
    public let preview: Bool
    public let participant: String
    public let dataMode: String
    public let containsSample: Bool
    /// サーバーの ISO 8601 表現を情報欠落なく保持する（秒・小数秒の精度差を許容）。
    public let at: String
    public let question: PendingQuestion?
    public let gates: [String: PreviewGate]

    private enum CodingKeys: String, CodingKey {
        case preview, participant, at, question, gates
        case dataMode = "data_mode"
        case containsSample = "contains_sample"
    }
}
