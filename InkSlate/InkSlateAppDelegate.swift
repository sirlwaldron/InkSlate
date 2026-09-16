#if os(iOS)
import UIKit
import CloudKit
import CoreData
import UserNotifications
import BackgroundTasks

/// Handles silent remote notifications so `NSPersistentCloudKitContainer` can finish CloudKit work before `UIBackgroundFetchResult` is repor...
final class InkSlateAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerBackgroundTasks()
        application.registerForRemoteNotifications()
        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.lucas.InkSlateNew.cleanup",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleBackgroundCleanup(task: processingTask)
        }
    }

    private static func handleBackgroundCleanup(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        PersistenceController.shared.performBackgroundMaintenance {
            task.setTaskCompleted(success: true)
            DispatchQueue.main.async {
                InkSlateAppDelegate.scheduleBackgroundCleanup()
            }
        }
    }

    static func scheduleBackgroundCleanup() {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil else { return }

        let request = BGProcessingTaskRequest(identifier: "com.lucas.InkSlateNew.cleanup")
        request.earliestBeginDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let fallbackRequest = BGProcessingTaskRequest(identifier: "com.lucas.InkSlateNew.cleanup")
            fallbackRequest.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            fallbackRequest.requiresNetworkConnectivity = false
            fallbackRequest.requiresExternalPower = false
            try? BGTaskScheduler.shared.submit(fallbackRequest)
        }
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
#endif
