// NarrativeStore.swift
// MozcFlickKeyboard — 追加: Narrative 系イベントを App Group 共有コンテナへ JSONL 追記／読み出しする。
//
// 既存 SafetyCheckLog と同じ流儀（日付別ファイル・FileHandle.seekToEndOfFile・try? で throw させない）。
// 置き場所: <AppGroup>/Narrative/
//   narrative_yyyyMMdd.jsonl … 回答済み NarrativeEvent
//   context_yyyyMMdd.jsonl   … 質問を伴わない ContextEvent
//   unsent_narrative.jsonl   … 送信失敗分の退避キュー（オフライン対応）
// App Group が無い / IO 失敗のいずれでもクラッシュせず黙って何もしない。

import Foundation

/// JSONL 保存・読み出しを担うストア。
public final class NarrativeStore {

    /// ファイル名の日付部分（yyyyMMdd）用。
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    public init() {}

    /// App Group 共有コンテナ内の保存ディレクトリ。
    public static var directoryURL: URL? {
        guard let base = AppConfig.sharedContainerURL else { return nil }
        return base.appendingPathComponent("Narrative", isDirectory: true)
    }

    /// 指定日の NarrativeEvent ファイル URL。
    public func narrativeFileURL(for date: Date) -> URL? {
        guard let dir = Self.directoryURL else { return nil }
        return dir.appendingPathComponent("narrative_\(dayFormatter.string(from: date)).jsonl")
    }

    /// 指定日の ContextEvent ファイル URL。
    public func contextFileURL(for date: Date) -> URL? {
        guard let dir = Self.directoryURL else { return nil }
        return dir.appendingPathComponent("context_\(dayFormatter.string(from: date)).jsonl")
    }

    /// 送信失敗分の退避キューファイル URL（日付で分けない）。
    public func unsentFileURL() -> URL? {
        guard let dir = Self.directoryURL else { return nil }
        return dir.appendingPathComponent("unsent_narrative.jsonl")
    }

    // MARK: - 追記

    /// 回答済み NarrativeEvent を当日ファイルへ1行追記する。
    public func appendNarrative(_ event: NarrativeEvent) {
        let url = narrativeFileURL(for: event.answeredAt ?? event.detectedAt)
        let ok = append(event, to: url)
        NSLog("[MFK-Narrative] appendNarrative kind=\(event.question.kind.rawValue) ok=\(ok)") // デバッグ: 回答保存
    }

    /// ContextEvent を当日ファイルへ1行追記する。
    public func appendContext(_ event: ContextEvent) {
        let ok = append(event, to: contextFileURL(for: event.detectedAt))
        NSLog("[MFK-Narrative] appendContext type=\(event.eventType) ok=\(ok)") // デバッグ: 文脈保存
    }

    /// 送信できなかった NarrativeEvent を退避キューへ追記する。
    public func appendUnsent(_ event: NarrativeEvent) {
        let ok = append(event, to: unsentFileURL())
        NSLog("[MFK-Narrative] appendUnsent event_id=\(event.eventID) ok=\(ok)") // デバッグ: 送信退避
    }

    // MARK: - 読み出し

    /// 指定日の NarrativeEvent を読み出す。
    public func narrativeEvents(on date: Date) -> [NarrativeEvent] {
        load(NarrativeEvent.self, from: narrativeFileURL(for: date))
    }

    /// 指定日の ContextEvent を読み出す。
    public func contextEvents(on date: Date) -> [ContextEvent] {
        load(ContextEvent.self, from: contextFileURL(for: date))
    }

    /// 退避キューの中身を読み出す。
    public func loadUnsent() -> [NarrativeEvent] {
        load(NarrativeEvent.self, from: unsentFileURL())
    }

    /// 退避キューを空にする（送信成功時に呼ぶ）。
    public func clearUnsent() {
        guard let url = unsentFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
        NSLog("[MFK-Narrative] clearUnsent") // デバッグ: 退避キュー削除
    }

    /// 保存済みの narrative_*.jsonl 全ファイル（export 用、ファイル名昇順）。
    public func allNarrativeFileURLs() -> [URL] {
        guard let dir = Self.directoryURL,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.lastPathComponent.hasPrefix("narrative_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - 内部共通処理

    /// Encodable 1件を指定ファイルへ JSONL として追記する。失敗しても throw しない。
    private func append<T: Encodable>(_ value: T, to url: URL?) -> Bool {
        guard let dir = Self.directoryURL, let url else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard var line = try? NarrativeJSON.encoder.encode(value) else { return false }
        line.append(0x0A) // 改行(LF)
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        handle.seekToEndOfFile()
        handle.write(line)
        try? handle.close()
        return true
    }

    /// JSONL を1行ずつデコードして配列にする。壊れた行は読み飛ばす。
    private func load<T: Decodable>(_ type: T.Type, from url: URL?) -> [T] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? NarrativeJSON.decoder.decode(T.self, from: data)
        }
    }
}

/// 研究ログの書き出し（親アプリの export 用）。
public enum NarrativeExport {

    /// NarrativeEvent 配列を JSON 配列として書き出す。
    public static func json(events: [NarrativeEvent]) -> Data? {
        try? NarrativeJSON.encoder.encode(events)
    }

    /// CSV の列名（研究ログ要件の項目を網羅する）。
    public static let csvHeader = ["event_id", "participant_id", "source", "event_type",
                                  "detected_at", "question_shown_at", "answered_at", "snooze_count",
                                  "question_kind", "prompt", "answer_label", "free_text",
                                  "time_of_day", "typing_active", "calendar_busy", "external_trigger",
                                  "typing_speed_cpm", "backspace_rate", "mean_key_interval_ms", "session_duration_sec",
                                  "emotion", "experience_type", "pmtt_node_id", "pmtt_state_label"]

    /// NarrativeEvent 配列を CSV 文字列にする（1行目はヘッダ）。
    public static func csv(events: [NarrativeEvent]) -> String {
        var lines = [csvHeader.joined(separator: ",")]
        for e in events {
            let cols: [String] = [e.eventID,
                        e.participantID,
                        e.source,
                        e.eventType,
                        NarrativeJSON.string(from: e.detectedAt),
                        NarrativeJSON.string(from: e.questionShownAt),
                        NarrativeJSON.string(from: e.answeredAt),
                        String(e.snoozeCount),
                        e.question.kind.rawValue,
                        e.question.prompt,
                        e.answer.label ?? "",
                        e.answer.freeText ?? "",
                        e.context.timeOfDay,
                        e.context.typingActive ? "true" : "false",
                        e.context.calendarBusy ? "true" : "false",
                        e.context.externalTrigger ?? ""]
            // 追加: 型推論の負荷を下げるため数値列と解析列は別配列で連結する
            let metrics: [String] = [number(e.typing?.typingSpeedCPM),
                                     number(e.typing?.backspaceRate),
                                     number(e.typing?.meanKeyIntervalMS),
                                     number(e.typing?.sessionDurationSec),
                                     e.narrative?.emotion ?? "",
                                     e.narrative?.experienceType ?? "",
                                     e.pmtt?.nodeID ?? "",
                                     e.pmtt?.stateLabel ?? ""]
            lines.append((cols + metrics).map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Double? を CSV 用文字列にする（nil は空欄）。
    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.3f", value)
    }

    /// カンマ・改行・二重引用符を含む値を "" で囲んでエスケープする。
    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
