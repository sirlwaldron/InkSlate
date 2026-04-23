//
//  AppLaunchPreferences.swift
//  InkSlate
//
//  Controls whether a cold start restores the last main menu feature. We set a flag
//  only when the app has actually entered the background, so a typical force-quit path
//  (where the OS never delivers a background transition) does not restore.
//

import Foundation

enum AppLaunchPreferences {
    private static let exitedToBackgroundKey = "inkSlateExitedToBackgroundInLastRun"

    static func markEnteredBackground() {
        UserDefaults.standard.set(true, forKey: exitedToBackgroundKey)
    }

    /// Whether the *previous* process had reached the background at least once, then clear for this run.
    static func takeShouldRestoreLastMenuAfterColdStart() -> Bool {
        let value = UserDefaults.standard.bool(forKey: exitedToBackgroundKey)
        UserDefaults.standard.set(false, forKey: exitedToBackgroundKey)
        return value
    }
}
