import SwiftUI
import Foundation
import Combine

// MARK: - Profile Service
@MainActor
class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published var userName: String = "User"
    @Published var userIcon: String = "person.circle.fill"
    @Published var userImage: PlatformImage?
    
    private let userDefaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let userNameKey = "profileUserName"
    private let userIconKey = "profileUserIcon"
    private let userImageKey = "profileUserImage"
    private let imageFileName = "profile-user-image.jpg"
    
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
    }
    
    @objc private func cloudStoreDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.loadProfile()
        }
    }
    
    func loadProfile() {
        if let cloudName = cloudStore.string(forKey: userNameKey), !cloudName.isEmpty {
            userName = cloudName
        } else if let localName = userDefaults.string(forKey: userNameKey), !localName.isEmpty {
            userName = localName
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
        
        Task {
            if let storedImage = await loadImageFromDiskAsync() {
                userImage = storedImage
            } else if let legacyData = cloudStore.data(forKey: userImageKey) ?? userDefaults.data(forKey: userImageKey),
                      let image = platformImage(from: legacyData) {
                userImage = image
                saveImageToDisk(legacyData)
                cloudStore.removeObject(forKey: userImageKey)
                userDefaults.removeObject(forKey: userImageKey)
            } else {
                userImage = nil
            }
        }
        
        cloudStore.synchronize()
    }
    
    func updateProfile(name: String, icon: String) {
        userName = name
        userIcon = icon
        
        cloudStore.set(name, forKey: userNameKey)
        cloudStore.set(icon, forKey: userIconKey)
        cloudStore.synchronize()
        
        userDefaults.set(name, forKey: userNameKey)
        userDefaults.set(icon, forKey: userIconKey)
    }
    
    func updateProfileImage(_ image: PlatformImage) {
        let processed = processProfileImageForStorage(image)
        userImage = processed
        if let imageData = processed.jpegData(compressionQuality: 0.7) {
            saveImageToDisk(imageData)
        }
    }
    
    func removeProfileImage() {
        userImage = nil
        removeStoredImage()
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
            try? FileManager.default.setAttributes(
                [FileAttributeKey.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
        }
    }
    
    private func loadImageFromDiskAsync() async -> PlatformImage? {
        guard let url = imageFileURL(),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let image = platformImage(from: data) else { return nil }
            return image
        }.value
    }
    
    private func removeStoredImage() {
        guard let url = imageFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Image downsampling / compression
    private func processProfileImageForStorage(_ image: PlatformImage) -> PlatformImage {
        #if canImport(UIKit)
        let target = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: target)
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (target.width - scaledSize.width) / 2, y: (target.height - scaledSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
        #elseif canImport(AppKit)
        let target = CGSize(width: 200, height: 200)
        let newImage = NSImage(size: target)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        let rect = CGRect(origin: .zero, size: target)
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - scaledSize.width) / 2, y: (target.height - scaledSize.height) / 2)
        image.draw(in: CGRect(origin: origin, size: scaledSize), from: .zero, operation: .sourceOver, fraction: 1.0)
        return newImage
        #else
        return image
        #endif
    }
}
