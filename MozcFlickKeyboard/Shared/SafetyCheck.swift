// SafetyCheck.swift
// MozcFlickKeyboard — 安否確認チェックのデータモデルとログ。
//
// 既存の予定配列（App Group UserDefaults の "schedules"、各要素 TSV）を後方互換で拡張し、
// チェック要否・曜日を持たせる。チェック押下は App Group 共有コンテナへ日付別 JSONL で追記し、
// 親アプリはそれを閲覧できる。当日チェック済み判定は当日ファイルのみ読めば済む。

import Foundation

/// 予定1件。TSV 4フィールド "HH:mm\t文言\tチェック要否\t曜日ビット" を表す。
/// 後方互換: 旧形式 "HH:mm\t文言" は needsCheck=false / weekdays="1111111" として読む。
public struct ScheduleItem {
    /// "HH:mm"
    public var time: String
    /// 質問文/予定の文言。
    public var text: String
    /// チェック UI を出すか。
    public var needsCheck: Bool
    /// 曜日ビット 7文字（index 0=日 … 6=土）。"1" が有効。
    public var weekdays: String

    /// time を分に換算した値（時刻比較用）。パース不能なら nil。
    public var minutes: Int? {
        let hm = time.split(separator: ":")
        guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { return nil }
        return h * 60 + m
    }

    public init(time: String, text: String, needsCheck: Bool, weekdays: String) {
        self.time = time
        self.text = text
        self.needsCheck = needsCheck
        self.weekdays = weekdays
    }

    /// TSV 文字列からパースする（後方互換）。
    public init?(tsv: String) {
        let parts = tsv.components(separatedBy: "\t")
        guard let time = parts.first, !time.isEmpty else { return nil }
        self.time = time
        self.text = parts.count > 1 ? parts[1] : ""
        self.needsCheck = parts.count > 2 ? parts[2] == "1" : false
        let wd = parts.count > 3 ? parts[3] : ""
        self.weekdays = wd.count == 7 ? wd : "1111111"
    }

    /// UserDefaults に保存する TSV 文字列。
    public var tsv: String {
        "\(time)\t\(text)\t\(needsCheck ? "1" : "0")\t\(weekdays)"
    }

    /// 当日チェック済み判定に使うキー（時刻 + 文言）。
    public var logKey: String { "\(time)\t\(text)" }

    /// 予定配列（TSV の配列）をまとめてパースする。
    public static func parse(_ list: [String]) -> [ScheduleItem] {
        list.compactMap { ScheduleItem(tsv: $0) }
    }

    /// 指定日の曜日が有効か。Calendar の weekday は 1=日 … 7=土。
    public func isActive(on date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date) // 1=日
        let index = weekday - 1
        let chars = Array(weekdays)
        guard index >= 0, index < chars.count else { return true }
        return chars[index] == "1"
    }

    /// 現在の分数が表示ウィンドウ（時刻の5分前 〜 +30分）に入っているか。
    public func isInWindow(nowMinutes: Int) -> Bool {
        guard let m = minutes else { return false }
        return nowMinutes >= m - 5 && nowMinutes <= m + 30
    }

    // MARK: - サンプル予定（追加）

    /// 追加: 曜日ビットの定番パターン。index 0=日 … 6=土。
    public static let everyday = "1111111"   // 追加: 毎日
    public static let weekdays = "0111110"   // 追加: 平日（月〜金）
    public static let weekend = "1000001"    // 追加: 土日

    /// 追加: 初期投入・サンプル読み込み用の予定一覧。
    /// 生活リズム（起床→朝食→服薬→外出→水分→昼食→休憩→帰宅→夕食→入浴→服薬→就寝）を一通り網羅する。
    /// needsCheck=true はキーボード上に質問＋チェックボタンを出し、false は「次の予定」表示のみになる。
    /// すべて通常の予定として保存されるので、設定画面から時刻・文言・チェック・曜日を編集でき、削除もできる。
    public static var samples: [ScheduleItem] {
        [
            ScheduleItem(time: "07:00", text: "起きましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "07:30", text: "朝ごはんを食べましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "08:00", text: "朝の薬を飲みましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "08:30", text: "仕事に向かっていますか", needsCheck: true, weekdays: weekdays),
            ScheduleItem(time: "10:00", text: "水分をとりましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "12:00", text: "昼ごはんを食べましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "13:00", text: "少し休憩しましたか", needsCheck: true, weekdays: weekdays),
            ScheduleItem(time: "15:00", text: "体調はどうですか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "16:00", text: "散歩に行きませんか", needsCheck: true, weekdays: weekend),
            ScheduleItem(time: "17:30", text: "帰宅しましたか", needsCheck: true, weekdays: weekdays),
            ScheduleItem(time: "18:30", text: "夕食の準備", needsCheck: false, weekdays: everyday),
            ScheduleItem(time: "19:00", text: "夕ごはんを食べましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "21:00", text: "お風呂に入りましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "22:00", text: "夜の薬を飲みましたか", needsCheck: true, weekdays: everyday),
            ScheduleItem(time: "23:00", text: "寝る準備をしましたか", needsCheck: true, weekdays: everyday),
        ]
    }
}

/// 安否確認チェックのログ。App Group 共有コンテナへ日付別 JSONL で追記する。
public enum SafetyCheckLog {

    /// 記録する1件。JSONL の1行に対応。
    public struct Entry: Codable {
        public let time: String       // ISO8601(ミリ秒付き)の記録時刻
        public let scheduled: String  // 予定時刻 "HH:mm"
        public let question: String   // 質問文
    }

    /// App Group 共有コンテナ内のログ保存ディレクトリ。
    public static var logsDirectoryURL: URL? {
        guard let base = AppConfig.sharedContainerURL else { return nil }
        return base.appendingPathComponent("SafetyChecks", isDirectory: true)
    }

    /// 指定日のログファイル URL（check_yyyyMMdd.jsonl）。
    public static func fileURL(for date: Date) -> URL? {
        guard let dir = logsDirectoryURL else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return dir.appendingPathComponent("check_\(f.string(from: date)).jsonl")
    }

    /// チェック1件を当日ファイルへ追記する。
    public static func append(_ item: ScheduleItem, at date: Date = Date()) {
        guard let dir = logsDirectoryURL, let url = fileURL(for: date) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "en_US_POSIX")
        tf.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        let entry = Entry(time: tf.string(from: date), scheduled: item.time, question: item.text)
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A) // 改行(LF)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(line)
        try? handle.close()
    }

    /// 指定日にチェック済みの logKey 集合（時刻+文言）を返す。
    public static func checkedKeys(on date: Date) -> Set<String> {
        guard let url = fileURL(for: date),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var keys = Set<String>()
        let dec = JSONDecoder()
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? dec.decode(Entry.self, from: data) else { continue }
            keys.insert("\(entry.scheduled)\t\(entry.question)")
        }
        return keys
    }
}
