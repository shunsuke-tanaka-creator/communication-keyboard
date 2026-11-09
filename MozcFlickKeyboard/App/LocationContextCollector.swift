import CoreLocation
import Foundation
import MozcFlickShared

/// Upgrade cleanup only. No location permission request, monitoring start, or GPS callback.
final class LocationContextCollector {
    static let shared = LocationContextCollector()
    func restore() {
        let manager = CLLocationManager()
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
        var preferences = WorkflowPreferences.current
        preferences.locationEnabled = false
        WorkflowPreferences.current = preferences
        // Old coordinate maps are no longer needed or used for inference.
        UserDefaults(suiteName: AppConfig.appGroupID)?.removeObject(forKey: "research.placeMap")
    }
}
