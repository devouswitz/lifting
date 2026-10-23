import Foundation
import UserNotifications
import LiftingCore

@MainActor
final class WorkoutNotifications: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let identifiers = ["workout.unfinished.0", "workout.unfinished.1"]
    private var update: Task<Void, Never>?
    var openWorkout: ((UUID) -> Void)?

    func configure() { UNUserNotificationCenter.current().delegate = self }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func refresh(session: Session?, enabled: Bool) {
        let previous = update
        previous?.cancel()
        update = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: Self.identifiers)
            center.removeDeliveredNotifications(withIdentifiers: Self.identifiers)
            guard enabled, let session else { return }
            let settings = await center.notificationSettings()
            guard !Task.isCancelled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let now = Date()
            let dates = WorkoutReminder.dates(for: session)
            let lastOverdue = dates.lastIndex { $0 <= now }
            for (index, date) in dates.enumerated() {
                if date <= now, index != lastOverdue { continue }
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = session.pausedAt == nil ? "Workout still running" : "Workout paused"
                content.body = "Resume or finish \(session.name)."
                content.sound = .default
                content.userInfo = ["sessionID": session.id.uuidString]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
                let request = UNNotificationRequest(identifier: Self.identifiers[index], content: content, trigger: trigger)
                try? await center.add(request)
                if Task.isCancelled { return }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let isWorkout = Self.identifiers.contains(response.notification.request.identifier)
        let id = (response.notification.request.content.userInfo["sessionID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            if isWorkout, let id { openWorkout?(id) }
            completionHandler()
        }
    }
}
