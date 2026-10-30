import CoreLocation
import Foundation
import MozcFlickShared

/// Visits, not transient GPS fixes, form the place topology. No naming or coordinate upload.
final class LocationContextCollector: NSObject, CLLocationManagerDelegate {
    static let shared = LocationContextCollector()
    private let manager = CLLocationManager()
    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID)
    private var map: AutomaticPlaceMap
    var authorizationDescription: String {
        switch manager.authorizationStatus {
        case .authorizedAlways: return "常に許可・訪問検出を利用可能"
        case .authorizedWhenInUse: return "使用中のみ許可・背景での検出は制限されます"
        case .denied, .restricted: return "位置情報の許可なし"
        default: return "未設定"
        }
    }
    private override init() {
        if let data = UserDefaults(suiteName: AppConfig.appGroupID)?.data(forKey: "research.placeMap"),
           let saved = try? JSONDecoder().decode(AutomaticPlaceMap.self, from: data) { map = saved }
        else { map = AutomaticPlaceMap() }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func restore() {
        guard WorkflowPreferences.current.locationEnabled else { stop(); return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startMonitoringVisits()
            if manager.authorizationStatus == .authorizedAlways { manager.startMonitoringSignificantLocationChanges() }
        default: stop()
        }
    }
    func enable(_ enabled: Bool) {
        var p = WorkflowPreferences.current; p.locationEnabled = enabled; WorkflowPreferences.current = p
        if !enabled { stop(); return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { restore() }
    }
    func requestBackgroundPermission() {
        guard WorkflowPreferences.current.locationEnabled else { return }
        manager.requestAlwaysAuthorization()
    }
    private func stop() { manager.stopMonitoringVisits(); manager.stopMonitoringSignificantLocationChanges() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { restore() }
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard WorkflowPreferences.current.locationEnabled,
              let place = map.classify(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude, accuracy: visit.horizontalAccuracy) else { return }
        if let data = try? JSONEncoder().encode(map) { defaults?.set(data, forKey: "research.placeMap") }
        // Core Location may deliver arrival and departure in a single delayed callback.
        for (phase, time) in [("arrival", visit.arrivalDate), ("departure", visit.departureDate)] {
            guard time != Date.distantPast, time != Date.distantFuture, time <= Date() else { continue }
            let id = "visit-\(place)-\(phase)-\(time.timeIntervalSince1970)"
            ResearchWorkflow.emit(kind: "place_visit", payload: ["place_id": .string(place), "phase": .string(phase),
                "accuracy_m": .number(visit.horizontalAccuracy), "device_id": .string(ResearchContextStore().deviceID)], at: time, id: id)
        }
        ResearchNotificationCoordinator.shared.poll()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Significant change wakes the app for synchronization, not a confirmed arrival.
        ResearchEventOutbox().flush(baseURL: NarrativeState().backendBaseURL)
        ResearchNotificationCoordinator.shared.poll()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[MFK-Research] Location update unavailable: %@", error.localizedDescription)
    }
}
