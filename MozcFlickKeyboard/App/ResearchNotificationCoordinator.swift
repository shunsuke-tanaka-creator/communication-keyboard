import UIKit
import UserNotifications
import BackgroundTasks
import MozcFlickShared

/// Local notifications on foreground refresh, visit callbacks and best-effort BGAppRefresh.
/// iOS chooses background execution times; this is not a continuous polling daemon.
final class ResearchNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ResearchNotificationCoordinator()
    static let refreshID = "com.tanaka05.MozcFlickKeyboard.research-refresh"
    static let openQuestion = Notification.Name("ResearchOpenQuestion")
    private var polling = false
    private var timer: Timer?
    func register() {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshID, using: .main) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            self.scheduleRefresh()
            var finished = false
            func finish(_ success: Bool) { if !finished { finished = true; refresh.setTaskCompleted(success: success) } }
            refresh.expirationHandler = { DispatchQueue.main.async { finish(false) } }
            self.poll { ok in finish(ok) }
        }
    }
    func setEnabled(_ enabled: Bool) {
        var p = WorkflowPreferences.current; p.notificationsEnabled = enabled; WorkflowPreferences.current = p
        if enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    if !granted { var p = WorkflowPreferences.current; p.notificationsEnabled = false; WorkflowPreferences.current = p }
                    self.poll()
                }
            }
        } else {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("research-") }.map(\.identifier))
            }
        }
    }
    func foreground() {
        timer?.invalidate()
        cancelDisallowed()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.poll() }
    }
    func background() { timer?.invalidate(); timer = nil; scheduleRefresh() }
    func cancelDisallowed() {
        let center = UNUserNotificationCenter.current()
        let enabled = WorkflowPreferences.current.notificationsEnabled && NarrativeState().narrativeEnabled
        let interventions = WorkflowPreferences.current.interventionsEnabled
        center.getPendingNotificationRequests { requests in
            let ids = requests.filter { request in
                guard request.identifier.hasPrefix("research-") else { return false }
                if !enabled { return true }
                guard let data = request.content.userInfo["question"] as? Data,
                      let q = try? NarrativeJSON.decoder.decode(PendingQuestion.self, from: data) else { return true }
                return (q.kind == .breakCheck && !interventions) || (q.expiresAt.map { $0 <= Date() } ?? false)
            }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
    func scheduleRefresh() {
        guard WorkflowPreferences.current.notificationsEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    func poll(completion: @escaping (Bool) -> Void = { _ in }) {
        guard !polling, NarrativeState().narrativeEnabled, WorkflowPreferences.current.notificationsEnabled else { completion(true); return }
        polling = true
        let state = NarrativeState()
        ResearchEventOutbox().flush(baseURL: state.backendBaseURL) { _ in
            ResearchAPIClient(baseURL: state.backendBaseURL).fetchPendingQuestion(participantID: state.participantID) { q in
                guard let q = q, ResearchPresentation.canShow(q), let data = try? NarrativeJSON.encoder.encode(q) else {
                    self.polling = false; completion(true); return
                }
                let content = UNMutableNotificationContent()
                content.title = "お天気分"
                content.body = "生活の記録について、短い質問があります。"
                content.userInfo = ["question": data]
                let request = UNNotificationRequest(identifier: "research-" + q.id, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
                UNUserNotificationCenter.current().add(request) { error in
                    DispatchQueue.main.async {
                        if error == nil { ResearchPresentation.record(q); ResearchWorkflow.questionState(q, "scheduled") }
                        self.polling = false; completion(error == nil)
                    }
                }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if let data = notification.request.content.userInfo["question"] as? Data,
           let q = try? NarrativeJSON.decoder.decode(PendingQuestion.self, from: data),
           NarrativeState().narrativeEnabled,
           q.kind != .breakCheck || WorkflowPreferences.current.interventionsEnabled,
           q.expiresAt.map({ $0 > Date() }) ?? true {
            ResearchWorkflow.questionState(q, "shown"); completionHandler([.banner, .list])
        } else { completionHandler([]) }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let data = response.notification.request.content.userInfo["question"] as? Data {
                UserDefaults(suiteName: AppConfig.appGroupID)?.set(data, forKey: "research.notificationQuestion")
                NotificationCenter.default.post(name: Self.openQuestion, object: nil)
            }
            completionHandler()
        }
    }
}
