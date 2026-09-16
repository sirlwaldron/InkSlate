import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Cross-platform application lifecycle notifications.
enum PlatformLifecycle {
    static var didBecomeActive: Notification.Name {
        #if canImport(UIKit)
        UIApplication.didBecomeActiveNotification
        #elseif canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        Notification.Name("PlatformLifecycle.didBecomeActive")
        #endif
    }

    static var willResignActive: Notification.Name {
        #if canImport(UIKit)
        UIApplication.willResignActiveNotification
        #elseif canImport(AppKit)
        NSApplication.willResignActiveNotification
        #else
        Notification.Name("PlatformLifecycle.willResignActive")
        #endif
    }

    static var willTerminate: Notification.Name {
        #if canImport(UIKit)
        UIApplication.willTerminateNotification
        #elseif canImport(AppKit)
        NSApplication.willTerminateNotification
        #else
        Notification.Name("PlatformLifecycle.willTerminate")
        #endif
    }

    static var significantTimeChange: Notification.Name {
        #if canImport(UIKit)
        UIApplication.significantTimeChangeNotification
        #elseif canImport(AppKit)
        NSNotification.Name.NSSystemClockDidChange
        #else
        Notification.Name("PlatformLifecycle.significantTimeChange")
        #endif
    }

    static var willEnterForeground: Notification.Name {
        #if canImport(UIKit)
        UIApplication.willEnterForegroundNotification
        #elseif canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        Notification.Name("PlatformLifecycle.willEnterForeground")
        #endif
    }
}
