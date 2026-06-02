import SwiftUI
import CoreData
import Foundation
import Combine
import BackgroundTasks
#if canImport(UIKit)
import UIKit
#endif

@main
struct InkSlateApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(InkSlateAppDelegate.self) private var appDelegate
    #endif
    @ObservedObject private var persistenceController = PersistenceController.shared
    @StateObject private var themeService = ThemeService.shared
    @StateObject private var profileService = ProfileService.shared
    @StateObject private var subscriptionService = SubscriptionService.shared
    
    init() {
        PerformanceLogger.measure(log: PerformanceMetrics.appLaunch, name: "AppInitialization") {
            registerBackgroundTasks()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if persistenceController.persistentStoreLoadFailed {
                    StoreLoadFailureView()
                } else {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(SharedStateManager.shared)
                        .environmentObject(themeService)
                        .environmentObject(profileService)
                        .environmentObject(subscriptionService)
                        .preferredColorScheme(themeService.isDarkMode ? .dark : .light)
                        .tint(themeService.accentColor)
                        .id(themeService.appearanceVersion)
                        .onOpenURL { url in
                            SharedImportManager.handleIncomingURL(url, in: persistenceController.container.viewContext)
                        }
                        .onAppear {
                            PerformanceLogger.measure(log: PerformanceMetrics.appLaunch, name: "ContentViewOnAppear") {
                                performCleanup()
                                scheduleBackgroundCleanup()
                            }
                            Task {
                                await checkCloudKitStatus()
                            }
                            Task {
                                await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                            }
                            checkForRemoteReset()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            Task {
                                await InkSlateNotificationService.shared.rescheduleCaptureNudgeIfNeeded()
                            }
                            checkForRemoteReset()
                        }
                        .onReceive(
                            NotificationCenter.default
                                .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                                .receive(on: DispatchQueue.main)
                        ) { _ in
                            checkForRemoteReset()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                            Task {
                                await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                            Task {
                                await saveContextAsync()
                                scheduleBackgroundCleanup()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                            Task {
                                await saveContextAsync()
                            }
                        }
                }
            }
        }
    }
    
    private func saveContextAsync() async {
        await MainActor.run {
            persistenceController.save()
        }
    }

    @MainActor
    private func checkForRemoteReset() {
        guard !persistenceController.persistentStoreLoadFailed else { return }
        if let request = FactoryResetService.shared.pendingRemoteReset() {
            SharedStateManager.shared.pendingRemoteResetToken = request.token
        }
    }
    
    private func performCleanup() {
        let controller = persistenceController
        controller.container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.automaticallyMergesChangesFromParent = true
            NotesEncryptionRemoval.migrateIfNeeded(in: context)
            controller.purgeTrashedNotesOlderThan30Days(in: context)
            if context.hasChanges {
                try? context.save()
            }
        }
    }
    
    private func checkCloudKitStatus() async {
        await persistenceController.checkCloudKitStatus()
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.lucas.InkSlateNew.cleanup",
            using: nil
        ) { task in
            if let processingTask = task as? BGProcessingTask {
                self.handleBackgroundCleanup(task: processingTask)
            } else {
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func scheduleBackgroundCleanup() {
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil else {
            return
        }
        
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
            do {
                try BGTaskScheduler.shared.submit(fallbackRequest)
            } catch {
            }
        }
    }
    
    private func handleBackgroundCleanup(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        let controller = persistenceController
        controller.container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.automaticallyMergesChangesFromParent = true
            controller.purgeTrashedNotesOlderThan30Days(in: context)
            if context.hasChanges {
                try? context.save()
            }
            task.setTaskCompleted(success: true)
            DispatchQueue.main.async {
                self.scheduleBackgroundCleanup()
            }
        }
    }
}

private struct StoreLoadFailureView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn’t open your library")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("InkSlate couldn’t load its database. Free space, restart the device, or reinstall the app if this continues.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}