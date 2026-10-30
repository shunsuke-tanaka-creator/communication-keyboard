import Foundation

/// Four nominal emotions. Deliberately has no conversion to fatigue or the mood 1...5 scale.
public enum WeatherMood: String, Codable, CaseIterable {
    case happy, normal, sad, angry
    public var label: String {
        switch self {
        case .happy: return "☀️ 晴れ・うれしい"
        case .normal: return "☁️ くもり・ふつう"
        case .sad: return "🌧️ 雨・悲しい"
        case .angry: return "⛈️ 雷・いらだち"
        }
    }
}

public enum ResearchValue: Codable {
    case string(String), number(Double), bool(Bool)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let x = try? c.decode(Bool.self) { self = .bool(x) }
        else if let x = try? c.decode(Double.self) { self = .number(x) }
        else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let x): try c.encode(x); case .number(let x): try c.encode(x); case .bool(let x): try c.encode(x) }
    }
}

public struct ResearchWorkflowEvent: Codable {
    public let schema_version: String
    public let event_id: String
    public let participant_id: String
    public let occurred_at: Date
    public let kind: String
    public let payload: [String: ResearchValue]
    public init(kind: String, payload: [String: ResearchValue], at: Date = Date(), id: String = UUID().uuidString) {
        self.schema_version = "research-v2"
        self.kind = kind; self.payload = payload; self.occurred_at = at; self.event_id = id
        self.participant_id = NarrativeState().participantID
    }
}

public struct WorkflowPreferences: Codable {
    public var locationEnabled = false
    public var notificationsEnabled = false
    public var interventionsEnabled = true
    public var dailyLimit = 4
    public var interventionLimit = 2
    public var gapMinutes = 60
    public init() {}
    public static var current: WorkflowPreferences {
        get {
            guard let data = UserDefaults(suiteName: AppConfig.appGroupID)?.data(forKey: "research.workflow.preferences"),
                  let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults(suiteName: AppConfig.appGroupID)?.set(data, forKey: "research.workflow.preferences")
        }
    }
}

/// All event writes are durable before transmission; answers survive process termination/offline use.
public enum ResearchWorkflow {
    @discardableResult
    public static func emit(kind: String, payload: [String: ResearchValue], at: Date = Date(), id: String = UUID().uuidString) -> Bool {
        let e = ResearchWorkflowEvent(kind: kind, payload: payload, at: at, id: id)
        let state = NarrativeState()
        let box = ResearchEventOutbox()
        let saved = box.enqueue(e, route: "api/research/\(state.participantID)/events", id: e.event_id)
        if saved { box.flush(baseURL: state.backendBaseURL) }
        return saved
    }
    public static func questionState(_ q: PendingQuestion, _ value: String) {
        emit(kind: "question_state", payload: ["question_id": .string(q.id), "state": .string(value)])
    }
    public static func syncPreferences() {
        let p = WorkflowPreferences.current
        emit(kind: "preferences", payload: ["questions_enabled": .bool(NarrativeState().narrativeEnabled),
            "interventions_enabled": .bool(p.interventionsEnabled), "daily_limit": .number(Double(p.dailyLimit)),
            "intervention_limit": .number(Double(p.interventionLimit)), "gap_minutes": .number(Double(p.gapMinutes))])
    }
    /// Specialized annotations are separate from model labels and generic narrative answers.
    public static func annotate(_ q: PendingQuestion, value: String) {
        if q.kind == .weatherMood || q.kind == .morningMood {
            var body: [String: ResearchValue] = ["weather": .string(value)]
            if q.context.externalTrigger == "server-v2" { body["question_id"] = .string(q.id) }
            emit(kind: "weather_mood", payload: body)
        } else if q.kind == .typingReason {
            emit(kind: "typing_reason", payload: ["question_id": .string(q.id), "reason": .string(value)])
        } else if q.kind == .supportOutcome {
            let parts = value.split(separator: ":").map(String.init)
            if parts.count == 3, let related = q.relatedID {
                let executed = parts[2] != "not_executed"
                emit(kind: "intervention_outcome", payload: ["question_id": .string(related),
                    "action": .string(parts[1]), "executed": .bool(executed),
                    "helpfulness": .string(executed ? parts[2] : "unknown")])
            }
        }
        if value == "stop" {
            var p = WorkflowPreferences.current; p.interventionsEnabled = false; WorkflowPreferences.current = p
            questionState(q, "stop")
        } else if value == "declined" { questionState(q, "declined") }
    }
}

public enum ResearchPresentation {
    private struct Display: Codable { let id: String; let at: Date; let intervention: Bool }
    private static var displays: [Display] {
        get {
            guard let data = UserDefaults(suiteName: AppConfig.appGroupID)?.data(forKey: "research.displays"),
                  let values = try? JSONDecoder().decode([Display].self, from: data) else { return [] }
            return values.filter { Date().timeIntervalSince($0.at) < 7 * 86400 }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults(suiteName: AppConfig.appGroupID)?.set(data, forKey: "research.displays") }
        }
    }
    public static func canShow(_ q: PendingQuestion, now: Date = Date()) -> Bool {
        let p = WorkflowPreferences.current
        guard NarrativeState().narrativeEnabled, q.expiresAt.map({ $0 > now }) ?? true else { return false }
        guard q.kind != .breakCheck || p.interventionsEnabled else { return false }
        let today = displays.filter { Calendar.current.isDate($0.at, inSameDayAs: now) }
        guard !today.contains(where: { $0.id == q.id }), today.count < p.dailyLimit else { return false }
        if q.kind == .breakCheck && today.filter({ $0.intervention }).count >= p.interventionLimit { return false }
        return today.last.map { now.timeIntervalSince($0.at) >= Double(p.gapMinutes) * 60 } ?? true
    }
    public static func record(_ q: PendingQuestion, now: Date = Date()) {
        guard !displays.contains(where: { $0.id == q.id }) else { return }
        var list = displays; list.append(Display(id: q.id, at: now, intervention: q.kind == .breakCheck)); displays = list
    }
}

/// Shared parent/keyboard assessment contract. Missing items stay missing, never zero-filled.
public enum StateAssessment {
    public static let keys = ["mood", "fatigue", "stress", "concentration", "sleepiness"]
    public static let names = ["気分", "疲労", "ストレス", "集中度", "眠気"]
    public static func prompt(index: Int, daily: Bool) -> String {
        return "\(daily ? "今日全体" : "今")の\(names[index])は？（\(index + 1)/5）"
    }
    public static func options(index: Int) -> [QuestionOption] {
        let endpoints = index == 0 ? ("とても悪い", "とても良い") : index == 3 ? ("とても低い", "とても高い") : ("まったくない", "とても強い")
        return (1...5).map { n in QuestionOption(label: "\(n)\(n == 1 ? "：" + endpoints.0 : n == 5 ? "：" + endpoints.1 : "")", value: "scale:\(keys[index]):\(n)") }
            + [QuestionOption(label: "この項目をスキップ", value: "scale:\(keys[index]):skip")]
    }
}

/// Portable visit clustering. Raw coordinates are persisted only on the phone.
public struct PlacePrototype: Codable {
    public let id: String
    public var latitude: Double
    public var longitude: Double
    public var count: Int
}
public struct AutomaticPlaceMap: Codable {
    public private(set) var nodes: [PlacePrototype] = []
    public init() {}
    public mutating func classify(latitude: Double, longitude: Double, accuracy: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude),
              accuracy.isFinite, accuracy >= 0, accuracy <= 150 else { return nil }
        func distance(_ n: PlacePrototype) -> Double {
            let r = Double.pi / 180
            let a = pow(sin((latitude-n.latitude)*r/2),2) + cos(latitude*r)*cos(n.latitude*r)*pow(sin((longitude-n.longitude)*r/2),2)
            return 6371000 * 2 * asin(sqrt(min(1, max(0,a))))
        }
        if let index = nodes.indices.min(by: { distance(nodes[$0]) < distance(nodes[$1]) }), distance(nodes[index]) <= max(100, accuracy * 1.5) {
            nodes[index].count += 1
            let n = Double(nodes[index].count)
            nodes[index].latitude += (latitude-nodes[index].latitude)/n
            nodes[index].longitude += (longitude-nodes[index].longitude)/n
            return nodes[index].id
        }
        let id = "place_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        nodes.append(PlacePrototype(id: id, latitude: latitude, longitude: longitude, count: 1))
        return id
    }
}
