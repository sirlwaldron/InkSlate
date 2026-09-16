import SwiftUI
import CoreData
import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

@main
@MainActor
struct InkSlateApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(InkSlateAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(InkSlateMacAppDelegate.self) private var macAppDelegate
    #endif
    @ObservedObject private var persistenceController = PersistenceController.shared
    @ObservedObject private var themeService = ThemeService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    #endif

    init() {
        PerformanceLogger.measure(log: PerformanceMetrics.appLaunch, name: "AppInitialization") {}
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup {
            Group {
                if persistenceController.persistentStoreLoadFailed {
                    StoreLoadFailureView()
                } else {
                    Group {
                        #if os(macOS)
                        ContentView(columnVisibility: $columnVisibility)
                        #else
                        ContentView()
                        #endif
                    }
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
                                #if os(iOS)
                                InkSlateAppDelegate.scheduleBackgroundCleanup()
                                #else
                                scheduleMacPeriodicCleanup()
                                #endif
                            }
                            // Defer non-critical database maintenance to avoid competing with initial screen presentation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                performCleanup()
                                checkForRemoteReset()
                            }
                            Task {
                                await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: PlatformLifecycle.didBecomeActive)) { _ in
                            #if os(iOS)
                            SharedImportManager.importPendingPayload(in: persistenceController.container.viewContext)
                            #endif
                            Task {
                                await subscriptionService.refreshEntitlements()
                                await InkSlateNotificationService.shared.rescheduleCaptureNudgeIfNeeded()
                            }
                            checkForRemoteReset()
                            persistenceController.forceCloudKitSync()
                        }
                        .onReceive(
                            NotificationCenter.default
                                .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                                .receive(on: DispatchQueue.main)
                        ) { _ in
                            checkForRemoteReset()
                            persistenceController.scheduleForceCloudKitSync()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: PlatformLifecycle.significantTimeChange)) { _ in
                            Task {
                                await InkSlateNotificationService.shared.refreshRepeatingNotificationsFromDefaultsIfAuthorized()
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: PlatformLifecycle.willResignActive)) { _ in
                            Task {
                                await saveContextAsync()
                                #if os(iOS)
                                InkSlateAppDelegate.scheduleBackgroundCleanup()
                                #endif
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: PlatformLifecycle.willTerminate)) { _ in
                            Task {
                                await saveContextAsync()
                            }
                        }
                        #if os(macOS)
                        .focusedSceneValue(\.inkSlateCommandContext, InkSlateCommandContext(
                            newNote: {
                                NotificationCenter.default.post(name: .inkSlateNewNote, object: nil)
                                SharedStateManager.shared.requestOpenMenu(.notes)
                            },
                            save: {
                                NotificationCenter.default.post(name: .inkSlateSave, object: nil)
                                persistenceController.save()
                            },
                            searchNotes: {
                                NotificationCenter.default.post(name: .inkSlateSearchNotes, object: nil)
                                SharedStateManager.shared.requestOpenMenu(.notes)
                            },
                            toggleSidebar: {
                                NotificationCenter.default.post(name: .inkSlateToggleSidebar, object: nil)
                                withAnimation {
                                    columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                                }
                            },
                            openSettings: {
                                NotificationCenter.default.post(name: .inkSlateOpenSettings, object: nil)
                                SharedStateManager.shared.requestOpenMenu(.settings)
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            }
                        ))
                        #endif
                }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            InkSlateCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(SharedStateManager.shared)
                .environmentObject(themeService)
                .environmentObject(profileService)
                .environmentObject(subscriptionService)
                .preferredColorScheme(themeService.isDarkMode ? .dark : .light)
                .tint(themeService.accentColor)
                .frame(minWidth: 560, idealWidth: 720, maxWidth: .infinity, minHeight: 480, idealHeight: 640, maxHeight: .infinity)
        }
        .defaultSize(width: 720, height: 640)
        #endif
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
        persistenceController.performBackgroundMaintenance()
    }

    private func checkCloudKitStatus() async {
        await persistenceController.checkCloudKitStatus()
    }

    #if os(macOS)
    private func scheduleMacPeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            Task { @MainActor in
                PersistenceController.shared.performBackgroundMaintenance()
            }
        }
    }
    #endif
}

private struct StoreLoadFailureView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't open your library")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("InkSlate couldn't load its database. Free space, restart the device, or reinstall the app if this continues.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.adaptiveSystemBackground)
    }
}
