import Foundation

/// Only active answer input is assessment data. Merely displaying a banner is not.
public enum ResearchSessionEvents {
    public static func markAssessments(_ events: [SessionEvent], intervals: [(Date, Date)], activeStart: Date?) -> [SessionEvent] {
        events.map { event in
            var data = event.data
            if let time = NarrativeJSON.dateFormatter.date(from: event.time),
               intervals.contains(where: { time >= $0.0 && time <= $0.1 }) || (activeStart.map { time >= $0 } ?? false) {
                data["purpose"] = "assessment"
            }
            return SessionEvent(time: event.time, type: event.type, data: data)
        }
    }
}
