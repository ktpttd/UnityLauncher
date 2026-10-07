import Foundation
@preconcurrency import UserNotifications

extension TaskItem {
    /// Title/body for a macOS notification, or nil when the task was too quick to be worth one.
    func notification(finishedAt end: Date) -> (title: String, body: String)? {
        let seconds = end.timeIntervalSince(startedAt)
        guard seconds >= 20 else { return nil }
        switch state {
        case .running:
            return nil
        case .succeeded:
            return ("\(title) succeeded", (["Done in \(formatDuration(seconds))"] + [summary].compactMap { $0 }).joined(separator: " · "))
        case .failed(let message):
            return ("\(title) failed", failureDetails.first ?? message)
        }
    }
}

/// Posts "task finished" notifications. Only from the bundled app: UserNotifications needs a real bundle.
@MainActor
enum Notify {
    private static let available = Bundle.main.bundleURL.pathExtension == "app"

    static func taskFinished(_ item: TaskItem) {
        guard available, let end = item.finishedAt, let text = item.notification(finishedAt: end) else { return }
        let (title, body) = text
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
