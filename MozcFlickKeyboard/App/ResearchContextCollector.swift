// ResearchContextCollector.swift
// MozcFlickKeyboard — 追加: 親アプリで端末Contextを集め、App Group（ResearchContextStore）へ書き込む。
//
// 変更: 取得するもの（コードの実装に合わせて更新）:
//  - HealthKit: 今日0時〜現在の合計（歩数・歩行距離・登った階段・活動エネルギー）と
//               直近1時間の平均（歩行速度・歩幅・歩行非対称性）の7種（読み取りのみ）
//  - EventKit : 今日の全カレンダー予定のタイトルと開始・終了時刻
//  - Battery  : 残量と状態
// キーボード拡張は HealthKit / EventKit を使えないため、親アプリが集めた最新値をセッション送信時に添付する。
// SceneDelegate.sceneDidBecomeActive から refresh() を呼ぶ（初回だけ権限ダイアログが出る）。
// HealthKit は AppDelegate から startBackgroundDelivery() を呼び、約1時間ごとにバックグラウンド更新する。

import UIKit
import HealthKit
import EventKit
import MozcFlickShared // 追加: ResearchContextStore / ResearchCalendarEvent

final class ResearchContextCollector {

    static let shared = ResearchContextCollector()

    private let healthStore = HKHealthStore()
    private let eventStore = EKEventStore()
    private let contextStore = ResearchContextStore()

    /// 追加: 全 Context を取り直す。各取得は非同期で、取れた順に main で保存する。
    func refresh() {
        NSLog("[MFK-Research] context refresh start") // 追加: デバッグ
        refreshBattery()
        refreshHealth()
        refreshCalendar()
    }

    // MARK: - Battery

    private func refreshBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Double(UIDevice.current.batteryLevel) // 0.0〜1.0（不明時 -1）
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        contextStore.update { context in
            context.batteryLevel = level >= 0 ? level : nil
            context.batteryState = state
            context.measurementUpdatedAt = (context.measurementUpdatedAt ?? [:]).merging(["battery_level": Date()]) { _, new in new }
        }
    }

    // MARK: - HealthKit（歩数・歩行距離・階段・歩行速度・歩幅・非対称性・活動エネルギー）

    // 追加: 読み取る7タイプ（合計系4 + 平均系3）。
    private var stepType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .stepCount)! }
    private var distanceType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)! }
    private var flightsType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .flightsClimbed)! }
    private var energyType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)! }
    private var speedType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .walkingSpeed)! }
    private var stepLengthType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .walkingStepLength)! }
    private var asymmetryType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage)! }

    // 追加: 全読み取りタイプの集合（権限要求・Observer・BackgroundDelivery で共用）。
    private var readTypes: Set<HKQuantityType> {
        [stepType, distanceType, flightsType, energyType, speedType, stepLengthType, asymmetryType]
    }

    private func refreshHealth() {
        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] ok, error in
            NSLog("[MFK-Research] HealthKit auth ok=\(ok) error=\(String(describing: error))") // 追加: デバッグ
            guard let self = self else { return }
            let todayStart = Calendar.current.startOfDay(for: Date())
            let lastHourStart = Date().addingTimeInterval(-3600) // 追加: 直近1時間（平均系の集計窓）

            // 合計系（今日0時〜現在）
            self.fetchStat(type: self.stepType, unit: .count(), options: .cumulativeSum, start: todayStart) { v in
                self.contextStore.update { c in c.stepCount = v; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["step_count": Date()]) { _, new in new } }
            }
            self.fetchStat(type: self.distanceType, unit: .meter(), options: .cumulativeSum, start: todayStart) { v in
                self.contextStore.update { c in c.walkingDistanceM = v; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["walking_distance_m": Date()]) { _, new in new } }
            }
            self.fetchStat(type: self.flightsType, unit: .count(), options: .cumulativeSum, start: todayStart) { v in
                self.contextStore.update { c in c.flightsClimbed = v; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["flights_climbed": Date()]) { _, new in new } }
            }
            self.fetchStat(type: self.energyType, unit: .kilocalorie(), options: .cumulativeSum, start: todayStart) { v in
                self.contextStore.update { c in c.activeEnergyKcal = v; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["active_energy_kcal": Date()]) { _, new in new } }
            }

            // 平均系（直近1時間）
            self.fetchStat(type: self.speedType, unit: HKUnit.meter().unitDivided(by: .second()), options: .discreteAverage, start: lastHourStart) { v in
                self.contextStore.update { c in c.walkingSpeedMps = v; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["walking_speed_mps": Date()]) { _, new in new } }
            }
            self.fetchStat(type: self.stepLengthType, unit: .meter(), options: .discreteAverage, start: lastHourStart) { v in
                self.contextStore.update { c in c.walkingStepLengthM = v; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["walking_step_length_m": Date()]) { _, new in new } }
            }
            self.fetchStat(type: self.asymmetryType, unit: .percent(), options: .discreteAverage, start: lastHourStart) { v in
                self.contextStore.update { c in c.walkingAsymmetryPct = v.map { $0 * 100; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["walking_asymmetry_pct": Date()]) { _, new in new } } } // 追加: 0〜1 → %
            }
        }
    }

    /// 変更: start〜現在の統計値を取得し、main で返す（データ無しは nil）。
    /// options が .cumulativeSum なら sumQuantity、.discreteAverage なら averageQuantity を読む。
    private func fetchStat(type: HKQuantityType, unit: HKUnit, options: HKStatisticsOptions, start: Date, completion: @escaping (Double?) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: predicate,
                                      options: options) { _, stats, error in
            let quantity = options.contains(.discreteAverage) ? stats?.averageQuantity() : stats?.sumQuantity()
            let value = quantity?.doubleValue(for: unit)
            NSLog("[MFK-Research] HealthKit \(type.identifier)=\(value ?? -1) error=\(String(describing: error))") // 追加: デバッグ
            DispatchQueue.main.async { completion(value) }
        }
        healthStore.execute(query)
    }

    // MARK: - バックグラウンド更新（HKObserverQuery + enableBackgroundDelivery）

    /// 追加: 7タイプに Observer を張り、更新のたびに refreshHealth() を呼ぶ。
    /// アプリ起動のたびに AppDelegate から呼ぶ（バックグラウンドで起こされた場合も Observer を張り直す）。
    func startBackgroundDelivery() {
        for type in readTypes {
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                NSLog("[MFK-Research] HealthKit observer fired \(type.identifier) error=\(String(describing: error))") // 追加: デバッグ
                self?.refreshHealth()
                completionHandler()
            }
            healthStore.execute(observer)
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { ok, error in
                NSLog("[MFK-Research] HealthKit backgroundDelivery \(type.identifier) ok=\(ok) error=\(String(describing: error))") // 追加: デバッグ
            }
        }
    }

    // MARK: - EventKit（今日の予定）

    private func refreshCalendar() {
        let handler: (Bool, Error?) -> Void = { [weak self] granted, error in
            NSLog("[MFK-Research] Calendar auth granted=\(granted) error=\(String(describing: error))") // 追加: デバッグ
            guard granted else { return }
            DispatchQueue.main.async { self?.fetchTodayEvents() }
        }
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents(completion: handler)
        } else {
            eventStore.requestAccess(to: .event, completion: handler)
        }
    }

    private func fetchTodayEvents() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).map {
            ResearchCalendarEvent(title: $0.title ?? "", start: $0.startDate, end: $0.endDate)
        }
        NSLog("[MFK-Research] Calendar events today=\(events.count)") // 追加: デバッグ
        contextStore.update { c in c.calendarEvents = events; c.measurementUpdatedAt = (c.measurementUpdatedAt ?? [:]).merging(["calendar_events": Date()]) { _, new in new } }
    }
}
