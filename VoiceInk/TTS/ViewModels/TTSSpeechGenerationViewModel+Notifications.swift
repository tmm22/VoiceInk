import Foundation
import UserNotifications

// MARK: - Notifications
extension TTSSpeechGenerationViewModel {
    func sendBatchCompletionNotification(successCount: Int, failureCount: Int) {
        guard let coordinator,
              coordinator.notificationsEnabled,
              successCount + failureCount > 0,
              let notificationCenter = coordinator.notificationCenter else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Batch Generation Complete"

        if failureCount == 0 {
            content.body = "All \(successCount) segment(s) generated successfully."
        } else if successCount == 0 {
            content.body = "Batch generation failed for all \(failureCount) segment(s)."
        } else {
            content.body = "\(successCount) succeeded • \(failureCount) failed."
        }

        let request = UNNotificationRequest(
            identifier: "batch-complete-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        notificationCenter.add(request)
    }
}
