import AppKit
import UserNotifications

@MainActor
final class CompletionNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var authorizationTask: Task<Void, Never>?

    private var center: UNUserNotificationCenter? {
        // Command-line builds and unit tests have no app notification identity.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    func prepareAuthorization() async {
        if let authorizationTask {
            await authorizationTask.value
            return
        }
        guard let center else { return }
        let task = Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert])
        }
        authorizationTask = task
        await task.value
        authorizationTask = nil
    }

    func notifyFinished(inputURL: URL, runID: UUID) async {
        await send(Self.request(inputURL: inputURL, runID: runID))
    }

    func notifyQueueFinished(completed: Int, failed: Int, runID: UUID) async {
        await send(Self.queueRequest(completed: completed, failed: failed, runID: runID))
    }

    private func send(_ request: UNNotificationRequest) async {
        guard !Self.isAppInForeground, !Task.isCancelled, let center else { return }
        await prepareAuthorization()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              !Self.isAppInForeground, !Task.isCancelled else { return }
        do {
            try await center.add(request)
        } catch {
            // A notification failure must not turn a completed transcript into a failed job.
        }
    }

    nonisolated static func request(inputURL: URL, runID: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Whisper for Mac"
        content.subtitle = "Transcription finished"
        content.body = inputURL.lastPathComponent
        return UNNotificationRequest(identifier: "transcription-\(runID.uuidString)", content: content, trigger: nil)
    }

    nonisolated static func queueRequest(completed: Int, failed: Int, runID: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Whisper for Mac"
        content.subtitle = "Queue finished"
        content.body = "\(completed) finished · \(failed) failed"
        return UNNotificationRequest(identifier: "queue-\(runID.uuidString)", content: content, trigger: nil)
    }

    static var isAppInForeground: Bool {
        let app = NSApplication.shared
        return app.isActive && app.windows.contains { $0.isVisible && !$0.isMiniaturized }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            Self.isAppInForeground ? [] : [.banner, .list]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            let app = NSApplication.shared
            if let window = app.windows.first(where: { $0.title == "Whisper for Mac" }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
            app.activate(ignoringOtherApps: true)
        }
    }
}
