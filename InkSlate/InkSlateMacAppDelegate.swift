#if os(macOS)
import AppKit
import CloudKit
import CoreData
import UserNotifications

final class InkSlateMacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        let cloudKit = CKNotification(fromRemoteNotificationDictionary: userInfo) != nil
        let silentContent = (userInfo["aps"] as? [String: Any])?["content-available"] as? Int == 1

        guard cloudKit || silentContent else { return }

        DispatchQueue.main.async {
            PersistenceController.shared.scheduleForceCloudKitSync()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            InkSlateNotificationService.shared.handleNotificationResponse(response)
            completionHandler()
        }
    }
}
#endif
