//
//  ProfileService.swift
//  InkSlate
//

import SwiftUI
import Foundation

// MARK: - Profile Service
class ProfileService: ObservableObject {
    @Published var userName: String = "User"
    @Published var userIcon: String = "person.circle.fill"
    @Published var userImage: UIImage?
    
    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let userNameKey = "profileUserName"
    private let userIconKey = "profileUserIcon"
    private let userImageKey = "profileUserImage"
    private let imageFileName = "profile-user-image.jpg"
    
    // Available icons for customization
    let availableIcons = [
        "person.circle.fill",
        "person.crop.circle.fill",
        "person.2.circle.fill",
        "person.3.circle.fill",
        "star.circle.fill",
        "heart.circle.fill",
        "flame.circle.fill",
        "leaf.circle.fill",
        "moon.circle.fill",
        "sun.max.circle.fill",
        "cloud.circle.fill",
        "bolt.circle.fill",
        "sparkles.circle.fill",
        "crown.circle.fill",
        "diamond.circle.fill"
    ]
    
    init() {
        loadProfile()
        setupCloudStoreObserver()
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupCloudStoreObserver() {
        // Listen for iCloud sync changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
    }
    
    @objc private func cloudStoreDidChange(_ notification: Notification) {
        // Reload profile when iCloud syncs changes
        DispatchQueue.main.async {
            self.loadProfile()
        }
    }
    
    func loadProfile() {
        // Try to load from iCloud first, fallback to local UserDefaults for migration
        if let cloudName = cloudStore.string(forKey: userNameKey), !cloudName.isEmpty {
            userName = cloudName
        } else if let localName = userDefaults.string(forKey: userNameKey), !localName.isEmpty {
            userName = localName
            // Migrate to iCloud
            cloudStore.set(localName, forKey: userNameKey)
        } else {
            userName = "User"
        }
        
        if let cloudIcon = cloudStore.string(forKey: userIconKey), !cloudIcon.isEmpty {
            userIcon = cloudIcon
        } else if let localIcon = userDefaults.string(forKey: userIconKey), !localIcon.isEmpty {
            userIcon = localIcon
            cloudStore.set(localIcon, forKey: userIconKey)
        } else {
            userIcon = "person.circle.fill"
        }
        
        if let storedImage = loadImageFromDisk() {
            userImage = storedImage
        } else if let legacyData = cloudStore.data(forKey: userImageKey) ?? userDefaults.data(forKey: userImageKey),
                  let image = UIImage(data: legacyData) {
            // Migrate legacy data into local storage
            userImage = image
            saveImageToDisk(legacyData)
            cloudStore.removeObject(forKey: userImageKey)
            userDefaults.removeObject(forKey: userImageKey)
        }
        
        // Synchronize iCloud store
        cloudStore.synchronize()
    }
    
    func updateProfile(name: String, icon: String) {
        userName = name
        userIcon = icon
        
        // Save to iCloud Key-Value Store for syncing
        cloudStore.set(name, forKey: userNameKey)
        cloudStore.set(icon, forKey: userIconKey)
        cloudStore.synchronize()
        
        // Also save locally as backup
        userDefaults.set(name, forKey: userNameKey)
        userDefaults.set(icon, forKey: userIconKey)
    }
    
    func updateProfileImage(_ image: UIImage) {
        userImage = image
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            saveImageToDisk(imageData)
        }
    }
    
    func resetToDefaults() {
        updateProfile(
            name: "User",
            icon: "person.circle.fill"
        )
        removeStoredImage()
    }
    
    // MARK: - Image Persistence Helpers
    private func imageFileURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(imageFileName, isDirectory: false)
    }
    
    private func saveImageToDisk(_ data: Data) {
        guard let url = imageFileURL() else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to write profile image to disk: \(error)")
            #endif
        }
    }
    
    private func loadImageFromDisk() -> UIImage? {
        guard let url = imageFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else { return nil }
        return image
    }
    
    private func removeStoredImage() {
        guard let url = imageFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
