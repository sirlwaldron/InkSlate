import UIKit
import CloudKit
import CoreData
import UserNotifications

/// Handles silent remote notifications so `NSPersistentCloudKitContainer` can finish CloudKit work before `UIBackgroundFetchResult` is repor...
final class InkSlateAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let cloudKit = CKNotification(fromRemoteNotificationDictionary: userInfo) != nil
        let silentContent = (userInfo["aps"] as? [String: Any])?["content-available"] as? Int == 1

        guard cloudKit || silentContent else {
            completionHandler(.noData)
            return
        }

        let viewContext = PersistenceController.shared.container.viewContext
        viewContext.performAndWait {
        }
        DispatchQueue.main.async {
            completionHandler(.newData)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

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
